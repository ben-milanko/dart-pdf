import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/strips.dart';

Future<void> _waitForSlugPicture(WidgetTester tester) async {
  for (var i = 0; i < 200; i++) {
    await tester.pump();
    final exception = tester.takeException();
    if (exception != null) fail('Slug page render failed: $exception');
    if (find
        .byKey(const ValueKey('pdf-page-slug-picture'))
        .evaluate()
        .isNotEmpty) {
      return;
    }
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
  }
  fail('Slug page picture did not arrive '
      '(planPictures=${StripPdfDevice.totalPlanPictures}, '
      'slugQuads=${StripPdfDevice.totalSlugQuads}, '
      'fallbacks=${StripPdfDevice.totalSlugFallbackOutlineRuns}, '
      'mismatches=${StripPdfDevice.totalPlanMismatches})');
}

Future<void> _waitForRaster(WidgetTester tester) async {
  for (var i = 0; i < 200; i++) {
    await tester.pump();
    final exception = tester.takeException();
    if (exception != null) fail('page raster failed: $exception');
    if (find.byType(RawImage).evaluate().isNotEmpty) return;
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
  }
  fail('page raster did not arrive');
}

void main() {
  testWidgets('web Slug page picture survives zoom without re-recording',
      (tester) async {
    PdfPageView.webSlugGlyphLayer = true;
    PdfPageView.debugWebSlugGlyphLayerBackendOverride = true;
    addTearDown(() {
      PdfPageView.webSlugGlyphLayer = true;
      PdfPageView.debugWebSlugGlyphLayerBackendOverride = null;
    });
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);

    final page = PdfDocument.open(buildEmbeddedFontPdf()).page(0);
    Widget at(double scale) => Center(
          child: SizedBox(
            width: 612,
            child: PdfPageView(page: page, scale: scale),
          ),
        );

    StripPdfDevice.resetStats();
    await tester.pumpWidget(at(1));
    await _waitForSlugPicture(tester);
    final slugFinder = find.byKey(const ValueKey('pdf-page-slug-picture'));
    expect(slugFinder, findsOneWidget);
    expect(find.byType(RawImage), findsNothing,
        reason:
            'the retained picture replaces, rather than overlays, the raster');
    expect(StripPdfDevice.totalSlugQuads, greaterThan(0));
    final firstPicture =
        (tester.widget<CustomPaint>(slugFinder).painter! as dynamic).picture;
    final firstQuads = StripPdfDevice.totalSlugQuads;

    await tester.pumpWidget(at(8));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    expect(slugFinder, findsOneWidget);
    final zoomPicture =
        (tester.widget<CustomPaint>(slugFinder).painter! as dynamic).picture;
    expect(identical(zoomPicture, firstPicture), isTrue,
        reason: 'zoom must keep the same transform-time picture alive');
    expect(StripPdfDevice.totalSlugQuads, firstQuads,
        reason: 'zoom must reuse the retained Slug picture without replaying');
    expect(find.byType(RawImage), findsNothing,
        reason: 'an image-free Slug scene needs no deep-zoom raster patch');
  });

  testWidgets('substituted text keeps the cheaper raster path', (tester) async {
    PdfPageView.webSlugGlyphLayer = true;
    PdfPageView.debugWebSlugGlyphLayerBackendOverride = true;
    addTearDown(() {
      PdfPageView.webSlugGlyphLayer = true;
      PdfPageView.debugWebSlugGlyphLayerBackendOverride = null;
    });
    final page = PdfDocument.open(buildClassicPdf()).page(0);

    StripPdfDevice.resetStats();
    await tester.pumpWidget(
      Center(child: SizedBox(width: 612, child: PdfPageView(page: page))),
    );
    await _waitForRaster(tester);
    expect(find.byKey(const ValueKey('pdf-page-slug-picture')), findsNothing);
    expect(StripPdfDevice.totalSlugQuads, 0,
        reason: 'Base-14 text has no outline glyphs for Slug to evaluate');
  });

  testWidgets('dense page consumes a worker Slug plan once', (tester) async {
    PdfPageView.webSlugGlyphLayer = true;
    PdfPageView.debugWebSlugGlyphLayerBackendOverride = true;
    PdfPageView.debugStripZoomReplayBackendOverride = true;
    PdfPageView.retainedZoomReplayMaxCommands = 0;
    addTearDown(() {
      PdfPageView.webSlugGlyphLayer = true;
      PdfPageView.debugWebSlugGlyphLayerBackendOverride = null;
      PdfPageView.debugStripZoomReplayBackendOverride = null;
      PdfPageView.retainedZoomReplayMaxCommands = 20000;
    });
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);

    final bytes = buildEmbeddedFontPdf();
    final page = PdfDocument.open(bytes).page(0);
    final worker = PdfRenderWorker.startUncached(bytes);
    addTearDown(worker.dispose);
    Widget at(double scale) => Center(
          child: SizedBox(
            width: 612,
            child: PdfPageView(page: page, scale: scale, renderWorker: worker),
          ),
        );

    StripPdfDevice.resetStats();
    await tester.pumpWidget(at(1));
    await _waitForSlugPicture(tester);
    expect(StripPdfDevice.totalPlanPictures, 1,
        reason: 'dense Slug construction must consume the worker plan');
    final finder = find.byKey(const ValueKey('pdf-page-slug-picture'));
    final picture =
        (tester.widget<CustomPaint>(finder).painter! as dynamic).picture;
    final quads = StripPdfDevice.totalSlugQuads;

    await tester.pumpWidget(at(3));
    await tester.pump();
    expect(
        identical(
            (tester.widget<CustomPaint>(finder).painter! as dynamic).picture,
            picture),
        isTrue);
    expect(StripPdfDevice.totalSlugQuads, quads);
    expect(StripPdfDevice.totalPlanPictures, 1,
        reason: 'zoom must not request or upload another Slug plan');
  });
}
