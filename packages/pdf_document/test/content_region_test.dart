import 'package:pdf_document/pdf_document.dart';
import 'package:test/test.dart';

import 'content_edit_test.dart' show buildContentPdf, pageText;

List<PdfContentElement> runs(PdfDocument doc) => PdfPageElements.of(doc, 0)
    .elements
    .where((e) => e.kind == PdfElementKind.text)
    .toList();

void main() {
  test('suffix and whole-run deletion preserve later text positions', () {
    for (final rect in [
      const PdfRect(78, 690, 85, 720), // B only in 10pt Courier AB
      const PdfRect(70, 690, 85, 720), // the whole first show
    ]) {
      final doc = PdfDocument.open(buildContentPdf(
        'BT /F1 10 Tf 72 700 Td (AB) Tj (CD) Tj ET',
        font: '<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>',
      ));
      final editor = PdfEditor(doc);
      expect(editor.deleteElementsInRect(PdfPageElements.of(doc, 0), rect), 1);
      final out = PdfDocument.open(editor.save());
      expect(runs(out).last.text, 'CD');
      expect(runs(out).last.bounds!.left, closeTo(84, 1e-6));
      expect(
          runs(out).map((r) => r.text), rect.left == 78 ? ['A', 'CD'] : ['CD']);
    }
  });

  test('kerning, font widths, spacing and horizontal scale survive cuts', () {
    final doc = PdfDocument.open(buildContentPdf(
      'BT /F1 10 Tf 2 Tc 3 Tw 50 Tz 8 Ts 72 700 Td '
      '[(A) -500 ( B) 100 (C)] TJ (Z) Tj ET',
      font: '<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>',
    ));
    // A: 4pt; kern: 2.5pt; space: 5.5pt; B:4pt; kern:-.5pt; C:4pt.
    final editor = PdfEditor(doc);
    expect(
        editor.deleteElementsInRect(
            PdfPageElements.of(doc, 0), const PdfRect(78, 707, 84, 720)),
        1);
    final out = PdfDocument.open(editor.save());
    expect(runs(out).map((r) => r.text), ['ABC', 'Z']);
    expect(runs(out).last.bounds!.left, closeTo(91.5, 1e-6));
    expect(pageText(out), contains('-500'));
    expect(pageText(out), contains('100'));
  });

  test('a concave lasso leaves the middle glyphs outside its two arms', () {
    final doc = PdfDocument.open(buildContentPdf(
      'BT /F1 10 Tf 72 700 Td (ABCDE) Tj ET',
      font: '<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>',
    ));
    final editor = PdfEditor(doc);
    expect(
        editor.deleteElementsInPolygon(PdfPageElements.of(doc, 0), const [
          (71, 695),
          (103, 695),
          (103, 715),
          (96, 715),
          (96, 700),
          (78, 700),
          (78, 715),
          (71, 715),
        ]),
        1);
    final out = PdfDocument.open(editor.save());
    expect(runs(out).single.text, 'BCD');
    expect(runs(out).single.textGlyphs.first.center.$1, closeTo(81, 1e-6));
  });

  test('rotated and reflected runs use transformed glyph centres', () {
    for (final entry in [
      ('0 1 -1 0 100 600 Tm', const PdfRect(90, 607, 105, 611)),
      ('-1 0 0 1 100 600 Tm', const PdfRect(89, 595, 93, 615)),
    ]) {
      final doc = PdfDocument.open(buildContentPdf(
        'BT /F1 10 Tf ${entry.$1} (ABC) Tj ET',
        font: '<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>',
      ));
      final editor = PdfEditor(doc);
      expect(
          editor.deleteElementsInRect(PdfPageElements.of(doc, 0), entry.$2), 1);
      expect(runs(PdfDocument.open(editor.save())).single.text, 'AC');
    }
  });

  test('glyphs reached by backtracking TJ survive run-bound approximations',
      () {
    final doc = PdfDocument.open(buildContentPdf(
      'BT /F1 10 Tf 72 700 Td [(AB) 1800 (C)] TJ ET',
      font: '<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>',
    ));
    final editor = PdfEditor(doc);
    expect(
        editor.deleteElementsInRect(
            PdfPageElements.of(doc, 0), const PdfRect(65, 695, 71, 715)),
        1);
    expect(runs(PdfDocument.open(editor.save())).single.text, 'AB');
  });

  test('composite glyph bytes can be sliced without deleting the whole run',
      () {
    final doc = PdfDocument.open(buildContentPdf(
      'BT /F1 10 Tf 72 700 Td <000100020003> Tj <0003> Tj ET',
      font:
          '<< /Type /Font /Subtype /Type0 /BaseFont /Test /Encoding /Identity-H '
          '/DescendantFonts [<< /Type /Font /Subtype /CIDFontType2 /DW 600 '
          '/CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> >>] >>',
    ));
    final editor = PdfEditor(doc);
    expect(
        editor.deleteElementsInRect(
            PdfPageElements.of(doc, 0), const PdfRect(78, 695, 84, 715)),
        1);
    final out = PdfDocument.open(editor.save());
    expect(runs(out).first.textGlyphs, hasLength(2));
    expect(pageText(out), contains('<0001> -600.0 <0003>'));
    expect(runs(out).last.bounds!.left, closeTo(90, 1e-6));
  });

  test('font encoding and Unicode expansion do not determine byte offsets', () {
    final doc = PdfDocument.open(buildContentPdf(
      'BT /F1 10 Tf 72 700 Td <010203> Tj ET',
      font: '<< /Type /Font /Subtype /Type1 /BaseFont /Courier '
          '/FirstChar 1 /LastChar 3 /Widths [600 600 600] '
          '/Encoding << /Type /Encoding /Differences [1 /A /fi /C] >> >>',
      toUnicode:
          '3 beginbfchar <01> <0041> <02> <00660069> <03> <0043> endbfchar',
    ));
    expect(runs(doc).single.text, 'AfiC');
    final editor = PdfEditor(doc);
    expect(
        editor.deleteElementsInRect(
            PdfPageElements.of(doc, 0), const PdfRect(78, 695, 84, 715)),
        1);
    expect(runs(PdfDocument.open(editor.save())).single.text, 'AC');
  });

  test('quote operator preserves line movement and spacing for following text',
      () {
    final doc = PdfDocument.open(buildContentPdf(
      'BT /F1 10 Tf 20 TL 72 720 Td 3 2 (A B) " (Z) Tj T* (N) Tj ET',
      font: '<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>',
    ));
    final editor = PdfEditor(doc);
    expect(
        editor.deleteElementsInRect(
            PdfPageElements.of(doc, 0), const PdfRect(70, 698, 99, 710)),
        1);
    final after = runs(PdfDocument.open(editor.save()));
    expect(after.map((r) => r.text), ['Z', 'N']);
    expect(after.first.bounds!.left, closeTo(99, 1e-6));
    expect(after.last.bounds!.left, 72);
    expect(after.last.bounds!.bottom, closeTo(678, 1e-6));
  });

  test('graphics-state text parameters restore and persist across BT', () {
    final doc = PdfDocument.open(buildContentPdf(
      '/F1 10 Tf 2 Tc q 8 Tc BT 72 720 Td (A) Tj ET Q '
      'BT 72 700 Td (AB) Tj (Z) Tj ET',
      font: '<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>',
    ));
    final editor = PdfEditor(doc);
    expect(
        editor.deleteElementsInRect(
            PdfPageElements.of(doc, 0), const PdfRect(79, 695, 85, 710)),
        1);
    final after = runs(PdfDocument.open(editor.save()));
    expect(after.map((r) => r.text), ['A', 'A', 'Z']);
    expect(after.last.bounds!.left, closeTo(88, 1e-6));
  });

  test('deleting a painted clip preserves its path and graphics state', () {
    final doc = PdfDocument.open(buildContentPdf(
        '100 100 50 50 re W 1 0 0 rg f 90 90 80 80 re f /Unknown sh'));
    final editor = PdfEditor(doc);
    expect(
        editor.deleteElementsInRect(
            PdfPageElements.of(doc, 0), const PdfRect(110, 110, 120, 120)),
        2);
    final out = PdfDocument.open(editor.save());
    expect(pageText(out), contains('W\n1 0 0 rg\nn'));
    expect(PdfPageElements.of(out, 0).elements.single.kind,
        PdfElementKind.shading);
  });

  test('unsupported composite encodings and clipping text stay untouched', () {
    for (final entry in [
      ('/Identity-V', '<000100020003>', ''),
      ('/Identity-H', '<0001000200>', ''),
      ('/Identity-H', '<000100020003>', '7 Tr'),
    ]) {
      final doc = PdfDocument.open(buildContentPdf(
        'BT /F1 10 Tf ${entry.$3} 72 700 Td ${entry.$2} Tj ET',
        font:
            '<< /Type /Font /Subtype /Type0 /BaseFont /Test /Encoding ${entry.$1} '
            '/DescendantFonts [<< /Type /Font /Subtype /CIDFontType2 /DW 600 >>] >>',
      ));
      final editor = PdfEditor(doc);
      expect(
          editor.deleteElementsInRect(
              PdfPageElements.of(doc, 0), const PdfRect(0, 0, 612, 792)),
          0);
      expect(editor.hasChanges, isFalse);
    }
  });

  test('zero-width paths can be erased; empty and collinear regions cannot',
      () {
    final doc = PdfDocument.open(buildContentPdf('100 100 m 100 150 l S'));
    final editor = PdfEditor(doc);
    final elements = PdfPageElements.of(doc, 0);
    expect(
        editor.deleteElementsInRect(
            elements, const PdfRect(100, 110, 100, 120)),
        0);
    expect(
        editor.deleteElementsInPolygon(
            elements, const [(90, 110), (100, 110), (110, 110)]),
        0);
    expect(editor.hasChanges, isFalse);
    expect(
        editor.deleteElementsInRect(elements, const PdfRect(95, 110, 105, 120)),
        1);
    expect(PdfPageElements.of(PdfDocument.open(editor.save()), 0).elements,
        isEmpty);
  });
}
