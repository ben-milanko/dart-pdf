// PdfEditor.injectTextLayer writes each OCR span along the page's visual
// reading direction: a /Rotate page gets a text matrix turned against the
// display rotation, so a word's on-screen width is the run's length (Tz)
// and its on-screen height is the font size. The extraction side of this
// (one run, matching bounds) is pinned in pdf_graphics' ocr_layer_test.
import 'dart:convert';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

void main() {
  // The OCR run's operators: font size, Tz, and its placement operator.
  ({double size, double scale, String place}) ocrRun(int rotation) {
    // A word ~200pt long and 30pt tall on screen: tall in user space on a
    // quarter-turned page, wide otherwise.
    final quarter = rotation == 90 || rotation == 270;
    final span = PdfOcrSpan(
      text: 'Recognized',
      bounds: quarter
          ? const PdfRect(200, 300, 230, 500)
          : const PdfRect(200, 300, 400, 330),
    );
    final editor =
        PdfEditor(PdfDocument.open(buildMultiPagePdf(1, rotation: rotation)));
    expect(editor.injectTextLayer(0, [span]), 1);
    final content =
        latin1.decode(PdfDocument.open(editor.save()).page(0).contentBytes());
    final run = RegExp(r'/OcrF\d+ (\S+) Tf\s+(\S+) Tz\s+([^\n]*?) (Td|Tm)')
        .firstMatch(content)!;
    return (
      size: double.parse(run[1]!),
      scale: double.parse(run[2]!),
      place: '${run[3]} ${run[4]}',
    );
  }

  test('an unrotated page keeps the Td form', () {
    final run = ocrRun(0);
    expect(run.size, closeTo(30, 1e-6));
    expect(run.place, '200 307.5 Td');
  });

  for (final (rotation, place) in const [
    (90, '0 1 -1 0 222.5 300 Tm'),
    (180, '-1 0 0 -1 400 322.5 Tm'),
    (270, '0 -1 1 0 207.5 500 Tm'),
  ]) {
    test('/Rotate $rotation turns the run to read with the page', () {
      final run = ocrRun(rotation);
      // The across-reading extent (30pt) is the size on every rotation, and
      // the along-reading one (200pt) sets the same scaling as rotation 0.
      expect(run.size, closeTo(30, 1e-6));
      expect(run.scale, closeTo(ocrRun(0).scale, 1e-3));
      expect(run.place, place);
    });
  }
}
