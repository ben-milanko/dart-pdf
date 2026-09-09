import 'dart:async';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/region_replay_index.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

import 'fixtures/high_zoom_pdf.dart';

void main() {
  for (final (commandCount, expectedInFlight) in [(77312, 8), (250001, 2)]) {
    testWidgets('$commandCount commands use bounded tile admission',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      final oldTiles = PdfPageView.tileStoreDetail;
      final oldStore = PdfPageView.debugTileStoreOverride;
      final oldDirect = PdfPageView.directPicturePresentation;
      final oldSlug = PdfPageView.webSlugGlyphLayer;
      final oldStrips = PdfPageView.stripZoomReplay;
      final oldProgressive = PdfPageView.progressiveStreamingPaint;
      final oldLocalFirstPaint =
          PdfPageView.debugWebLocalFirstPaintBackendOverride;
      final store = PdfTileStore(
          tilePixels: 128, prefetchRing: 0, registerForMemoryPressure: false);
      final worker = _TranscriptWorker(commandCount);
      final backend = _PendingTileBackend();
      PdfPageView.tileStoreDetail = true;
      PdfPageView.debugTileStoreOverride = store;
      PdfPageView.directPicturePresentation = false;
      PdfPageView.webSlugGlyphLayer = false;
      PdfPageView.stripZoomReplay = false;
      PdfPageView.progressiveStreamingPaint = false;
      // The count belongs to the supplied worker transcript; the tiny PDF
      // exists only to provide geometry, so the web local shortcut must wait.
      PdfPageView.debugWebLocalFirstPaintBackendOverride = false;
      addTearDown(() {
        PdfPageView.tileStoreDetail = oldTiles;
        PdfPageView.debugTileStoreOverride = oldStore;
        PdfPageView.directPicturePresentation = oldDirect;
        PdfPageView.webSlugGlyphLayer = oldSlug;
        PdfPageView.stripZoomReplay = oldStrips;
        PdfPageView.progressiveStreamingPaint = oldProgressive;
        PdfPageView.debugWebLocalFirstPaintBackendOverride = oldLocalFirstPaint;
        worker.dispose();
        store.dispose();
      });

      final page = PdfDocument.open(buildHighZoomPagePdf()).page(0);
      await tester.pumpWidget(MediaQuery.fromView(
        view: tester.view,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: OverflowBox(
              maxWidth: double.infinity,
              maxHeight: double.infinity,
              child: SizedBox(
                width: 6120,
                child: PdfPageView(
                  page: page,
                  renderWorker: worker,
                  tileRasterBackend: backend,
                ),
              ),
            ),
          ),
        ),
      ));
      for (var i = 0; i < 300 && backend.requests.isEmpty; i++) {
        await tester.pump();
        final exception = tester.takeException();
        if (exception != null) fail('tile pacing setup failed: $exception');
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)));
      }
      expect(backend.requests, isNotEmpty,
          reason: 'the page must enter the actual tile scheduler');
      expect(worker.indexRequests, greaterThan(0));
      expect(backend.scene!.commands, hasLength(commandCount));
      expect(backend.scene!.regionIndexBuildIsHeavy, isTrue,
          reason: 'both transcripts should warm their grids off-thread');

      final painter = tester
          .widget<CustomPaint>(
              find.byKey(const ValueKey('pdf-page-tile-layer')))
          .painter as dynamic;
      expect(painter.maxNewTilesPerPaint, commandCount > 250000 ? 1 : isNull);
      expect(painter.maxInFlightTiles, expectedInFlight);
      // Keep every raster unresolved and force further paints. Medium pages
      // may fill an eight-tile slab; very large pages retain one-at-a-time
      // admission. Neither may grow an unbounded queue across repaints.
      for (var i = 0; i < 5; i++) {
        tester
            .renderObject<RenderObject>(
                find.byKey(const ValueKey('pdf-page-tile-layer')))
            .markNeedsPaint();
        await tester.pump();
      }
      expect(store.debugTilesScheduled, expectedInFlight);
      expect(store.debugTilesLanded, 0,
          reason: 'the queue bound must hold before any tile completes');

      await tester.pumpWidget(const SizedBox.shrink());
      backend.completeAll();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });
  }
}

class _TranscriptWorker extends PdfRenderWorker {
  _TranscriptWorker(int count)
      : commands = List<PdfRenderCommand>.unmodifiable([
          // Many cheap state slots model a dense transcript whose indexed
          // viewport work is small; drawing them requires no giant fixture.
          for (var i = 0; i < count - 1; i++)
            const PdfSetBlendModeCommand(PdfBlendMode.normal),
          const PdfFillPathCommand(
            PdfPath([
              PdfMoveTo(300, 390),
              PdfLineTo(312, 390),
              PdfLineTo(312, 402),
              PdfLineTo(300, 402),
              PdfClosePath(),
            ]),
            PdfColor(0, 0, 1),
            PdfFillRule.nonzero,
            1,
          ),
        ]);

  final List<PdfRenderCommand> commands;
  int indexRequests = 0;
  bool _active = true;

  @override
  bool get isActive => _active;

  @override
  Future<List<PdfRenderCommand>?> record(int pageIndex,
          {bool annotations = true,
          int priority = 0,
          double? imagePixelRatio,
          bool decodeImages = true,
          int? commandLimit,
          PdfRect? imageDecodeRegion,
          PdfPartialRecordSink? onPartial}) async =>
      commands;

  @override
  Future<PdfRegionReplayIndex?> buildRegionIndex(int pageIndex,
      {required bool annotations,
      required int maxCommands,
      required bool buildGrid,
      int priority = 0}) async {
    indexRequests++;
    return PdfRegionReplayIndex.build(commands,
        maxCommands: maxCommands, buildGrid: buildGrid);
  }

  @override
  void cancel(int pageIndex, {int priority = 0}) {}

  @override
  void dispose() => _active = false;
}

class _PendingTileBackend extends PdfCanvasTileRasterBackend {
  PdfRetainedScene? scene;
  final requests = <(Completer<ui.Image>, int, int)>[];

  @override
  PdfTileRasterSession createSession(PdfRetainedScene scene) {
    this.scene = scene;
    return _PendingTileSession(this, scene);
  }

  void completeAll() {
    for (final (completer, width, height) in requests) {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder);
      final picture = recorder.endRecording();
      completer.complete(picture.toImageSync(width, height));
      picture.dispose();
    }
    requests.clear();
  }
}

class _PendingTileSession implements PdfTileRasterSession {
  _PendingTileSession(this.backend, this.scene);
  final _PendingTileBackend backend;
  @override
  final PdfRetainedScene scene;

  @override
  Future<ui.Image> rasterizeRegion(ui.Rect region,
      {required double pixelRatio, int? tracePage}) {
    final completer = Completer<ui.Image>();
    backend.requests.add((
      completer,
      (region.width * pixelRatio).ceil(),
      (region.height * pixelRatio).ceil()
    ));
    return completer.future;
  }

  @override
  void dispose() {}
}
