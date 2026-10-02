// The document's first cold page decodes its images at 1x so first content is
// cheap, then refines them: once that raster is on screen,
// `_scheduleFocusedImageRefinement` drops the picture and its retained scene and
// records the page again at the 2x final-quality decode.
//
// A zoom that lands while that refine is still recording supersedes it (the
// scale change bumps the full-render generation), and the superseded pass
// throws its finished record away. The zoom's own pass, re-granted by the
// scheduler once the refine settled, then found the base raster "current":
// once the zoom outruns the base raster, `_baseRasterIsCurrent` stops comparing
// its image ratio because the detail path supplies the sharp pixels. So it
// skipped as `base-current`, and nothing rebuilt the scene after that: every
// detail request logged `scene=false tiles=no-scene`, no tile ever landed, no
// image detail was adopted, and each pan re-rendered a full-viewport picture.
// That was the web deep-zoom journey's intermittent failure (the Patrol perf
// e2e), and a real stall for anyone who zooms a cold, image-heavy dense page
// inside its refine window.
import 'dart:async';
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/region_replay_index.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_graphics/raster.dart' show StripPlan;
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

/// The deep-zoom journey's wide CAD strip, scaled down: image tiles under
/// enough linework that the page paints through a base raster (over
/// [PdfPageView.directPicturePresentationMaxCommands]) - the only route that
/// takes the cold 1x-then-refine transaction.
Uint8List _cadSheet() => buildSyntheticCadImageStrip(
      tiles: [
        for (var i = 0; i < 18; i++)
          PdfTileSpec(
            codec: i == 17
                ? PdfTileCodec.indexed
                : i % 3 == 2
                    ? PdfTileCodec.flateRgb
                    : PdfTileCodec.imageMask,
            width: 1024,
            height: 768,
          ),
      ],
      ops: 6000,
      streams: 4,
    );

Future<void> _settle(WidgetTester tester, {int rounds = 1}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

void main() {
  testWidgets(
      'a zoom that supersedes the cold image refine still rebuilds the scene '
      'and lands image-detail tiles', (tester) async {
    // The CI journey's geometry: a 2600px-wide viewport at 1x, the ultra-wide
    // sheet at fit width, then 400%.
    tester.view.physicalSize = const Size(2600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final logs = <String>[];
    PdfPerfLog.sink = logs.add;
    PdfPerfLog.enabled = true;
    final store =
        PdfTileStore(tilePixels: 256, registerForMemoryPressure: false);
    final oldTiles = PdfPageView.tileStoreDetail;
    PdfPageView.tileStoreDetail = true;
    PdfPageView.debugTileStoreOverride = store;
    PdfPageView.debugTileImageDetailAdoptions = 0;
    final bytes = _cadSheet();
    final worker = _HeldRefineWorker(PdfRenderWorker.startUncached(bytes));
    final scheduler = PdfPageRenderScheduler();
    // Fresh: zero observations is what makes this the document's first cold
    // page, the one that decodes at 1x and refines afterwards.
    final performance = PdfPerformanceController();
    addTearDown(() {
      PdfPerfLog.enabled = false;
      PdfPerfLog.sink = null;
      PdfPageView.tileStoreDetail = oldTiles;
      PdfPageView.debugTileStoreOverride = null;
      PdfPageView.debugTileImageDetailAdoptions = 0;
      scheduler.dispose();
      performance.dispose();
      worker.dispose();
      store.dispose();
    });

    final page = PdfDocument.open(bytes).page(0);
    // The viewer's shape: the page keeps its fit-width layout and a
    // fit-resolution backing raster (baseRasterScale 1) while the zoom is a
    // transform over it, so the page itself only learns the zoom via [scale].
    Widget at(double scale, int settleGeneration) => Align(
          alignment: Alignment.topLeft,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 2600,
              child: PdfPageView(
                key: const ValueKey('refine-race-page'),
                page: page,
                scale: scale,
                baseRasterScale: 1,
                settleGeneration: settleGeneration,
                renderWorker: worker,
                renderScheduler: scheduler,
                performance: performance,
              ),
            ),
          ),
        );

    await tester.pumpWidget(at(1, 0));
    for (var i = 0; i < 400 && !worker.refineHeld; i++) {
      await _settle(tester);
    }
    expect(worker.refineHeld, isTrue,
        reason: 'the cold first raster should have scheduled its image refine');
    final refineAt =
        logs.indexWhere((line) => line.contains('image-refine page=0'));
    expect(refineAt, isNot(-1));
    // The shape under test: a cold record at the page's exact footprint, then
    // the refine at the 2x final-quality decode (0.31 -> 0.61 in the CI trace,
    // the same geometry as here).
    expect(worker.imageRatios.first,
        moreOrLessEquals(2600 / 8503.939, epsilon: 0.01));
    expect(worker.imageRatios.last,
        moreOrLessEquals(2 * worker.imageRatios.first, epsilon: 0.01));
    final fullRecordsBeforeZoom = worker.fullRecords;

    // Zoom while the refine's record is in flight: the scale change supersedes
    // it, and the zoom's own request queues behind it in the scheduler.
    final zoomAt = logs.length;
    await tester.pumpWidget(at(4, 1));
    await _settle(tester, rounds: 3);
    expect(
      logs.skip(zoomAt).any((line) => line.contains('scheduler defer page=0')),
      isTrue,
      reason: 'the zoom must arrive while the refine is still in flight',
    );
    worker.releaseRefine();

    bool converged() =>
        PdfPageView.debugTileImageDetailAdoptions > 0 &&
        store.debugTilesLanded > 0 &&
        find.byKey(const ValueKey('pdf-page-tile-layer')).evaluate().isNotEmpty;
    for (var i = 0; i < 600 && !converged(); i++) {
      await _settle(tester);
    }

    final detailRequests = logs
        .where((line) => line.contains('detail request page=0'))
        .toList(growable: false);
    final lastDetail = detailRequests.isEmpty ? 'none' : detailRequests.last;
    expect(worker.fullRecords, greaterThan(fullRecordsBeforeZoom),
        reason: 'the superseded refine must be re-issued, not skipped as '
            'base-current (last detail request: $lastDetail)');
    expect(
      detailRequests.any((line) =>
          line.contains('scene=true') && line.contains('tiles=active')),
      isTrue,
      reason: 'the retained scene must come back so the tile path can run '
          '(last detail request: $lastDetail)',
    );
    expect(PdfPageView.debugTileImageDetailAdoptions, greaterThan(0),
        reason: 'tiles must adopt the region image re-decode '
            '(last detail request: $lastDetail)');
    expect(store.debugTilesLanded, greaterThan(0),
        reason: 'tiles must land (last detail request: $lastDetail)');
    expect(find.byKey(const ValueKey('pdf-page-tile-layer')), findsOneWidget);
    expect(
      logs.skip(refineAt).where((line) =>
          line.contains('detail request page=0') &&
          line.contains('tiles=no-scene')),
      isEmpty,
      reason: 'no detail request after the refine may find the scene gone',
    );
  });
}

/// Serves ordinary records from [inner] but holds the page's image refine -
/// the first full-page record asking for more image resolution than the cold
/// first record did - until [releaseRefine].
class _HeldRefineWorker extends PdfRenderWorker {
  _HeldRefineWorker(this.inner);

  final PdfRenderWorker inner;
  final Completer<void> _release = Completer<void>();
  bool refineHeld = false;

  /// Full-page, image-decoding records (not region or vector-only ones).
  int fullRecords = 0;

  /// The image ratio each of those records asked for, in order.
  final imageRatios = <double>[];

  void releaseRefine() {
    if (!_release.isCompleted) _release.complete();
  }

  @override
  bool get isActive => inner.isActive;

  @override
  Future<List<PdfRenderCommand>?> record(
    int pageIndex, {
    bool annotations = true,
    int priority = 0,
    double? imagePixelRatio,
    bool decodeImages = true,
    int? commandLimit,
    PdfRect? imageDecodeRegion,
    PdfPartialRecordSink? onPartial,
  }) async {
    if (imageDecodeRegion == null &&
        decodeImages &&
        commandLimit == null &&
        imagePixelRatio != null) {
      fullRecords++;
      imageRatios.add(imagePixelRatio);
      if (!refineHeld && imagePixelRatio > imageRatios.first * 1.5) {
        refineHeld = true;
        await _release.future;
      }
    }
    return inner.record(
      pageIndex,
      annotations: annotations,
      priority: priority,
      imagePixelRatio: imagePixelRatio,
      decodeImages: decodeImages,
      commandLimit: commandLimit,
      imageDecodeRegion: imageDecodeRegion,
      onPartial: onPartial,
    );
  }

  @override
  Future<StripPlan?> binStrips(
    int pageIndex, {
    required bool annotations,
    required List<double> pageToDevice,
    required int deviceWidth,
    required int deviceHeight,
    required double pixelRatio,
    bool slugGlyphs = false,
    int priority = 0,
  }) =>
      inner.binStrips(
        pageIndex,
        annotations: annotations,
        pageToDevice: pageToDevice,
        deviceWidth: deviceWidth,
        deviceHeight: deviceHeight,
        pixelRatio: pixelRatio,
        slugGlyphs: slugGlyphs,
        priority: priority,
      );

  @override
  Future<PdfStripDetail?> recordStripDetail(
    int pageIndex, {
    required bool annotations,
    required List<double> pageToDevice,
    required int deviceWidth,
    required int deviceHeight,
    required double pixelRatio,
    required PdfRect imageDecodeRegion,
    int priority = 0,
  }) =>
      inner.recordStripDetail(
        pageIndex,
        annotations: annotations,
        pageToDevice: pageToDevice,
        deviceWidth: deviceWidth,
        deviceHeight: deviceHeight,
        pixelRatio: pixelRatio,
        imageDecodeRegion: imageDecodeRegion,
        priority: priority,
      );

  @override
  Future<PdfRegionReplayIndex?> buildRegionIndex(
    int pageIndex, {
    required bool annotations,
    required int maxCommands,
    required bool buildGrid,
    int priority = 0,
  }) =>
      inner.buildRegionIndex(
        pageIndex,
        annotations: annotations,
        maxCommands: maxCommands,
        buildGrid: buildGrid,
        priority: priority,
      );

  @override
  void cancel(int pageIndex, {int priority = 0}) =>
      inner.cancel(pageIndex, priority: priority);

  @override
  void cancelBinStrips(int pageIndex, {int priority = 0}) =>
      inner.cancelBinStrips(pageIndex, priority: priority);

  @override
  void dispose() {
    releaseRefine();
    inner.dispose();
  }
}
