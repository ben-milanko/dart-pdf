import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';

/// Renders a free-text box in [font] and counts how many pixels carry ink
/// (any channel meaningfully below white) on the rasterized page.
Future<int> _inkPixels(PdfStandardFont font) async {
  final editor = PdfEditor(PdfDocument.open(buildClassicPdf()))
    ..addFreeText(0, const PdfRect(72, 600, 320, 700), 'Bold italic test',
        fontSize: 28, font: font);
  final doc = PdfDocument.open(editor.save());
  final image = await PdfPageRenderer.renderImage(doc.page(0));
  final data = await image.toByteData();
  var ink = 0;
  for (var i = 0; i < data!.lengthInBytes; i += 4) {
    if (data.getUint8(i) < 128) ink++;
  }
  return ink;
}

/// The darkest red channel inside a large black free-text box. On white paper
/// a 25%-opaque black glyph bottoms out near 191 instead of 0.
Future<int> _darkestTextPixel(double opacity) async {
  final editor = PdfEditor(PdfDocument.open(buildClassicPdf()))
    ..addFreeText(
      0,
      const PdfRect(72, 600, 360, 700),
      'OPACITY',
      fontSize: 42,
      opacity: opacity,
    );
  final doc = PdfDocument.open(editor.save());
  final image = await PdfPageRenderer.renderImage(doc.page(0));
  final data = await image.toByteData();
  var darkest = 255;
  // buildClassicPdf is a 612x792pt page and renderImage defaults to 1x.
  // PDF y-up [600,700] maps to raster y-down [92,192].
  for (var y = 92; y < 192; y++) {
    for (var x = 72; x < 360; x++) {
      final red = data!.getUint8((y * image.width + x) * 4);
      if (red < darkest) darkest = red;
    }
  }
  image.dispose();
  return darkest;
}

void main() {
  testWidgets('bold free text paints more ink than the regular face',
      (tester) async {
    await tester.runAsync(() async {
      final regular = await _inkPixels(PdfStandardFont.times);
      final bold = await _inkPixels(PdfStandardFont.timesBold);
      // the text must actually render…
      expect(regular, greaterThan(50));
      // …and the bold variant lays down visibly more ink.
      expect(bold, greaterThan(regular));
    });
  });

  testWidgets('italic free text renders without throwing', (tester) async {
    await tester.runAsync(() async {
      final italic = await _inkPixels(PdfStandardFont.timesBoldItalic);
      expect(italic, greaterThan(50));
    });
  });

  testWidgets('free-text appearance opacity fades the rendered glyphs',
      (tester) async {
    await tester.runAsync(() async {
      final opaque = await _darkestTextPixel(1);
      final faded = await _darkestTextPixel(0.25);
      expect(opaque, lessThan(80));
      expect(faded, greaterThan(opaque + 100));
      expect(faded, lessThan(245), reason: 'the faded text must still paint');
    });
  });
}
