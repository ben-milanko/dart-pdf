import 'dart:io';
import 'package:pdf_document/pdf_document.dart';
import 'package:test/test.dart';
import 'content_edit_test.dart' show buildContentPdf;
import 'content_edit_type0_test.dart' show buildType0Pdf;

double lastGlyphX(PdfDocument document) => PdfPageElements.of(document, 0)
    .elements
    .where((e) => e.kind == PdfElementKind.text)
    .last
    .textGlyphs
    .last
    .center
    .$1;

void main() {
  for (final (find, replace) in [('Ben', 'Benjamin'), ('Ben ', 'B')]) {
    for (final styled in [false, true]) {
      test('preserves trailing name spacing: $find → $replace, styled=$styled',
          () {
        final document = PdfDocument.open(buildContentPdf(
            'BT /F1 12 Tf 2 Tc 5 Tw 75 Tz 72 700 Td [(Ben ) -25 (Milanko)] TJ ET'));
        final original = lastGlyphX(document);
        final editor = PdfEditor(document);
        expect(
            editor.replaceText(0, find, replace,
                style: styled
                    ? const PdfTextStyle(
                        fontSize: 18, italic: true, color: 0x0000FF)
                    : null),
            1);
        final after = PdfDocument.open(editor.save());
        expect(lastGlyphX(after), closeTo(original, .002));
      });
    }
  }
  for (final styled in [false, true]) {
    test(
        'composite fonts retain Tc but do not apply single-byte Tw, styled=$styled',
        () {
      final bytes = File('test/fonts/DejaVuSans.ttf').readAsBytesSync();
      final document = PdfDocument.open(
          buildType0Pdf('Ben Milanko', bytes, textState: '2 Tc 5 Tw 75 Tz'));
      final before = lastGlyphX(document);
      final editor = PdfEditor(document);
      expect(
          editor.replaceText(0, 'Ben', 'Benjamin',
              style: styled
                  ? const PdfTextStyle(fontSize: 18, color: 0x0000FF)
                  : null),
          1);
      expect(
          lastGlyphX(PdfDocument.open(editor.save())), closeTo(before, .002));
    });
  }
  test('q/Q restores text font size and spacing for a later styled edit', () {
    final document = PdfDocument.open(buildContentPdf(
        'BT /F1 12 Tf 2 Tc 5 Tw 72 700 Td q /F1 30 Tf -1 Tc 0 Tw Q (Ben Milanko) Tj ET'));
    final before = lastGlyphX(document);
    final editor = PdfEditor(document);
    expect(
        editor.replaceText(0, 'Ben', 'Benjamin',
            style: const PdfTextStyle(fontSize: 18, italic: true)),
        1);
    expect(lastGlyphX(PdfDocument.open(editor.save())), closeTo(before, .002));
  });
}
