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
}
