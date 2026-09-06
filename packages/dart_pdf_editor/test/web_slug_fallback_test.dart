import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/strips.dart';

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
  testWidgets('minified outline fallback is rejected once and rasterized',
      (tester) async {
    PdfPageView.webSlugGlyphLayer = true;
    PdfPageView.debugWebSlugGlyphLayerBackendOverride = true;
    addTearDown(() {
      PdfPageView.webSlugGlyphLayer = true;
      PdfPageView.debugWebSlugGlyphLayerBackendOverride = null;
    });
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);

    final bytes = buildEmbeddedFontPdf();
    const fontSize = [0x32, 0x34, 0x20, 0x54, 0x66]; // "24 Tf"
    for (var i = 0; i <= bytes.length - fontSize.length; i++) {
      var match = true;
      for (var j = 0; j < fontSize.length; j++) {
        if (bytes[i + j] != fontSize[j]) match = false;
      }
      if (!match) continue;
      bytes[i] = 0x20;
      bytes[i + 1] = 0x33; // same-width " 3 Tf", xref stays valid
      break;
    }
    final page = PdfDocument.open(bytes).page(0);
    Widget at(double scale) => Center(
          child: SizedBox(
              width: 612, child: PdfPageView(page: page, scale: scale)),
        );

    StripPdfDevice.resetStats();
    await tester.pumpWidget(at(1));
    await _waitForRaster(tester);
    expect(find.byKey(const ValueKey('pdf-page-slug-picture')), findsNothing);
    expect(StripPdfDevice.totalSlugQuads, 0);
    expect(StripPdfDevice.totalStripQuads, greaterThan(0),
        reason: 'the 3px outline run must trip the minification fallback');
    final rejectedFlushes = StripPdfDevice.totalFlushes;

    await tester.pumpWidget(at(3));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    expect(StripPdfDevice.totalFlushes, rejectedFlushes,
        reason: 'a rejected scene must not retry Slug on every settle');
  });
}
