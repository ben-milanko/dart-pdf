import 'dart:async';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/strips.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart' show PdfRenderCommand;
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

Future<void> _waitFor(WidgetTester tester, Finder finder,
    {String label = 'render'}) async {
  for (var i = 0; i < 500; i++) {
    await tester.pump();
    final exception = tester.takeException();
    if (exception != null) fail('$label failed: $exception');
    if (finder.evaluate().isNotEmpty) return;
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
  }
  fail('$label did not arrive');
}

Future<void> _waitUntil(
  WidgetTester tester,
  bool Function() predicate, {
  String label = 'condition',
}) async {
  for (var i = 0; i < 500; i++) {
    await tester.pump();
    final exception = tester.takeException();
    if (exception != null) fail('$label failed: $exception');
    if (predicate()) return;
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
  }
  fail('$label did not arrive');
}

void main() {
  testWidgets('mixed Slug picture preserves image/text/vector painter order',
      (tester) async {
    await tester.runAsync(() async {
      final page = PdfDocument.open(buildEmbeddedFontImagePdf()).page(0);
      final scene = await PdfRetainedScene.record(page);
      addTearDown(scene.dispose);
      expect(PdfPageRenderer.hasImageDraws(scene.commands), isTrue);
      expect(scene.hasSlugTextCandidates, isTrue);

      final picture = await scene.replayStrips(pixelRatio: 1, slugGlyphs: true);
      final image = await picture.toImage(612, 792);
      picture.dispose();
      final pixels =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
              .buffer
              .asUint8List();
      image.dispose();
      (int, int, int) rgb(int x, int y) {
        final offset = (y * 612 + x) * 4;
        return (pixels[offset], pixels[offset + 1], pixels[offset + 2]);
      }

      final imagePixel = rgb(60, 110);
      expect(imagePixel.$3, greaterThan(imagePixel.$1),
          reason: 'the pale-blue inline image must paint behind the text');
      final glyphPixel = rgb(78, 80);
      expect(glyphPixel.$1 + glyphPixel.$2 + glyphPixel.$3, lessThan(150),
          reason: 'the embedded outline glyph must paint over the image');
      final occluder = rgb(94, 80);
      expect(occluder.$1, greaterThan(180));
      expect(occluder.$2, lessThan(100));
      expect(occluder.$3, lessThan(100),
          reason: 'the later vector must still occlude Slug text');
    });
  });

  testWidgets('detail raster yields to the mixed Slug base during live zoom',
      (tester) async {
    PdfPageView.webSlugGlyphLayer = true;
    PdfPageView.debugWebSlugGlyphLayerBackendOverride = true;
    addTearDown(() {
      PdfPageView.webSlugGlyphLayer = true;
      PdfPageView.debugWebSlugGlyphLayerBackendOverride = null;
    });
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);

    final bytes = buildEmbeddedFontImagePdf();
    final page = PdfDocument.open(bytes).page(0);
    final worker = PdfRenderWorker.startUncached(bytes);
    final transform = ChangeNotifier();
    addTearDown(worker.dispose);
    addTearDown(transform.dispose);
    Widget at(int settle) => Center(
          child: SizedBox(
            width: 612,
            child: PdfPageView(
              page: page,
              scale: 8,
              settleGeneration: settle,
              renderWorker: worker,
              transformChanges: transform,
            ),
          ),
        );

    StripPdfDevice.resetStats();
    await tester.pumpWidget(at(0));
    final slug = find.byKey(const ValueKey('pdf-page-slug-picture'));
    final detail = find.byKey(const ValueKey('pdf-page-detail-image'));
    await _waitFor(tester, slug, label: 'mixed Slug picture');
    await _waitFor(tester, detail, label: 'high-resolution detail');
    final picture =
        (tester.widget<CustomPaint>(slug).painter! as dynamic).picture;
    final quads = StripPdfDevice.totalSlugQuads;

    transform.notifyListeners();
    await tester.pump();
    expect(detail, findsNothing,
        reason: 'stale raster text must not cover the sharp live base');
    expect(slug, findsOneWidget);
    expect(
        identical(
            (tester.widget<CustomPaint>(slug).painter! as dynamic).picture,
            picture),
        isTrue);

    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpWidget(at(1));
    await _waitFor(tester, detail, label: 'settled replacement detail');
    expect(slug, findsOneWidget);
    expect(StripPdfDevice.totalSlugQuads, quads,
        reason: 'settles must reuse the transform-time Slug picture');
  });

  testWidgets('visible detail paints before the full-page image record starts',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);

    final bytes = buildEmbeddedFontImagePdf();
    final page = PdfDocument.open(bytes).page(0);
    final previews = PdfPagePreviewCache();
    await tester.runAsync(() async {
      final picture = await PdfPageRenderer.renderPictureRecorded(page);
      try {
        await previews.putFromPicture(0, page, picture);
      } finally {
        picture.dispose();
      }
    });
    expect(previews.isFresh(0, page), isTrue,
        reason: 'the regression starts with soft cached preview pixels');
    final worker =
        _DeferredFullRecordWorker(PdfRenderWorker.startUncached(bytes));
    addTearDown(previews.dispose);
    addTearDown(worker.dispose);

    await tester.pumpWidget(Align(
      alignment: Alignment.topLeft,
      child: OverflowBox(
        alignment: Alignment.topLeft,
        maxWidth: double.infinity,
        maxHeight: double.infinity,
        child: Transform.translate(
          offset: const Offset(0, -500),
          child: Transform.scale(
            alignment: Alignment.topLeft,
            scale: 2,
            child: SizedBox(
              width: 612,
              height: 792,
              child: PdfPageView(
                page: page,
                scale: 8,
                renderWorker: worker,
                previewCache: previews,
              ),
            ),
          ),
        ),
      ),
    ));

    await _waitUntil(tester, () => worker.regionRecordStarted.isCompleted,
        label: 'held region record');
    expect(worker.fullRecordStarted.isCompleted, isFalse,
        reason: 'full refinement must not overlap detail rasterization');

    await _waitFor(tester, find.byKey(const ValueKey('pdf-page-detail-image')),
        label: 'region-first high-resolution detail');
    expect(worker.fullRecordStarted.isCompleted, isTrue,
        reason: 'the ordinary full-page image record should still warm');
    expect(worker.fullRecordReleased, isFalse,
        reason: 'visible detail must land while the full-page record is held');
    expect(worker.regionRecordStarted.isCompleted, isTrue);
    expect(worker.regionRecordReleased, isFalse,
        reason:
            'sharp vector detail must also beat the complete region record');
    expect(worker.vectorRecordPriority, -100,
        reason: 'visible detail must preempt ordinary neighbouring pages');
  });
}

/// Holds the image-complete full-page and region records while delegating the
/// vector-first request, proving visible vector detail can paint independently
/// of either expensive result.
class _DeferredFullRecordWorker extends PdfRenderWorker {
  _DeferredFullRecordWorker(this._inner);

  final PdfRenderWorker _inner;
  final fullRecordStarted = Completer<void>();
  final _fullRecord = Completer<List<PdfRenderCommand>?>();
  final regionRecordStarted = Completer<void>();
  final _regionRecord = Completer<List<PdfRenderCommand>?>();
  int? vectorRecordPriority;

  bool get fullRecordReleased => _fullRecord.isCompleted;
  bool get regionRecordReleased => _regionRecord.isCompleted;

  @override
  bool get isActive => _inner.isActive;

  @override
  Future<List<PdfRenderCommand>?> record(int pageIndex,
      {bool annotations = true,
      int priority = 0,
      double? imagePixelRatio,
      bool decodeImages = true,
      int? commandLimit,
      PdfRect? imageDecodeRegion, PdfPartialRecordSink? onPartial}) {
    if (decodeImages && imageDecodeRegion != null) {
      if (!regionRecordStarted.isCompleted) regionRecordStarted.complete();
      return _regionRecord.future;
    }
    if (decodeImages && imageDecodeRegion == null) {
      if (!fullRecordStarted.isCompleted) fullRecordStarted.complete();
      return _fullRecord.future;
    }
    vectorRecordPriority = priority;
    return _inner.record(pageIndex,
        annotations: annotations,
        priority: priority,
        imagePixelRatio: imagePixelRatio,
        decodeImages: decodeImages,
        commandLimit: commandLimit,
        imageDecodeRegion: imageDecodeRegion);
  }

  @override
  void cancel(int pageIndex, {int priority = 0}) =>
      _inner.cancel(pageIndex, priority: priority);

  @override
  Future<StripPlan?> binStrips(int pageIndex,
          {required bool annotations,
          required List<double> pageToDevice,
          required int deviceWidth,
          required int deviceHeight,
          required double pixelRatio,
          bool slugGlyphs = false,
          int priority = 0}) =>
      _inner.binStrips(pageIndex,
          annotations: annotations,
          pageToDevice: pageToDevice,
          deviceWidth: deviceWidth,
          deviceHeight: deviceHeight,
          pixelRatio: pixelRatio,
          slugGlyphs: slugGlyphs,
          priority: priority);

  @override
  Future<PdfStripDetail?> recordStripDetail(int pageIndex,
          {required bool annotations,
          required List<double> pageToDevice,
          required int deviceWidth,
          required int deviceHeight,
          required double pixelRatio,
          required PdfRect imageDecodeRegion,
          int priority = 0}) =>
      _inner.recordStripDetail(pageIndex,
          annotations: annotations,
          pageToDevice: pageToDevice,
          deviceWidth: deviceWidth,
          deviceHeight: deviceHeight,
          pixelRatio: pixelRatio,
          imageDecodeRegion: imageDecodeRegion,
          priority: priority);

  @override
  void cancelBinStrips(int pageIndex, {int priority = 0}) =>
      _inner.cancelBinStrips(pageIndex, priority: priority);

  @override
  void dispose() {
    if (!_fullRecord.isCompleted) _fullRecord.complete(null);
    if (!_regionRecord.isCompleted) _regionRecord.complete(null);
    _inner.dispose();
  }
}
