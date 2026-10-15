import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

String content(PdfDocument doc, int index) =>
    String.fromCharCodes(doc.page(index).contentBytes());

void main() {
  group('pdfBakePageColor', () {
    test('white - opaque or fully transparent - has nothing to bake', () {
      expect(pdfPageColorNeedsBaking(const Color(0xFFFFFFFF)), isFalse);
      expect(pdfPageColorNeedsBaking(const Color(0x00336699)), isFalse);
      expect(pdfPageColorNeedsBaking(const Color(0xFFF4ECD8)), isTrue);
      final bytes = buildMultiPagePdf(1);
      expect(pdfBakePageColor(bytes, const Color(0xFFFFFFFF)), same(bytes));
    });

    test('paints the colour behind every page as an incremental update', () {
      final bytes = buildMultiPagePdf(2);
      final baked = pdfBakePageColor(bytes, const Color(0xFF000000));
      // an incremental update: the original bytes are a prefix
      expect(baked.sublist(0, bytes.length), bytes);
      final out = PdfDocument.open(baked);
      for (var i = 0; i < 2; i++) {
        expect(content(out, i), contains('q 0 0 0 rg 0 0 612 792 re f Q'));
      }
    });

    test('a translucent colour is composited over white first', () {
      final baked =
          pdfBakePageColor(buildMultiPagePdf(1), const Color(0x80000000));
      // 50% black over white
      expect(content(PdfDocument.open(baked), 0),
          contains('q 0.498 0.498 0.498 rg'));
    });

    test('a signed document is reported as blocked', () {
      expect(pdfPageColorBakeBlocked(PdfDocument.open(buildMultiPagePdf(1))),
          isFalse);
      final signed = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)))
          .saveSelfSigned(
              identity: PdfSigningIdentity.generate(name: 'Ada Lovelace'));
      expect(pdfPageColorBakeBlocked(PdfDocument.open(signed)), isTrue);
    });
  });
}
