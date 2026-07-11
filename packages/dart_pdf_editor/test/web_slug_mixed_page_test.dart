import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/strips.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
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
}
