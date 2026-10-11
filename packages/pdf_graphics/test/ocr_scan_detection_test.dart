// pdfPageLooksScanned / pdfDocumentLooksScanned decide whether the app runs
// OCR over a document on its own: image-covered pages with no text at all.
import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

void main() {
  PdfDocument open(Uint8List bytes) => PdfDocument.open(bytes);

  group('pdfPageLooksScanned', () {
    test('a full-page image with no text is a scan', () {
      final doc = open(buildScannedPdf());
      expect(pdfPageLooksScanned(doc, 0), isTrue);
    });

    test('an inline full-page image is a scan too', () {
      final doc = open(buildScannedPdf(inlineImage: true));
      expect(pdfPageLooksScanned(doc, 0), isTrue);
    });

    test('a stamped Bates number does not stop it being a scan', () {
      final doc = open(buildScannedPdf(text: 'ABC-000123'));
      expect(pdfPageLooksScanned(doc, 0), isTrue);
    });

    test('a page with real text over its picture is not', () {
      final doc = open(buildScannedPdf(
          text: 'A born-digital paragraph laid over a full-bleed photograph, '
              'long enough to be the page text.'));
      expect(pdfPageLooksScanned(doc, 0), isFalse);
    });

    test('a page that already carries an OCR layer is not', () {
      final editor = PdfEditor(open(buildScannedPdf()));
      editor.injectTextLayer(0, [
        PdfOcrSpan(text: 'Recognized', bounds: PdfRect(72, 700, 200, 714)),
      ]);
      final doc = open(editor.save());
      expect(pdfPageLooksScanned(doc, 0), isFalse);
    });

    test('a small picture on an otherwise empty page is not', () {
      final doc = open(buildScannedPdf(coverage: 0.2));
      expect(pdfPageLooksScanned(doc, 0), isFalse);
    });

    test('a text-only page is not', () {
      final doc = open(buildMultiPagePdf(1));
      expect(pdfPageLooksScanned(doc, 0), isFalse);
    });

    test('an out-of-range page answers false instead of throwing', () {
      final doc = open(buildScannedPdf());
      expect(pdfPageLooksScanned(doc, 5), isFalse);
    });
  });

  group('pdfDocumentLooksScanned', () {
    test('samples the leading pages', () {
      expect(
          pdfDocumentLooksScanned(open(buildScannedPdf(pageCount: 4))), isTrue);
      expect(pdfDocumentLooksScanned(open(buildMultiPagePdf(4))), isFalse);
    });

    test('an empty sample is not a scan', () {
      final doc = open(buildScannedPdf());
      expect(pdfDocumentLooksScanned(doc, samplePages: 0), isFalse);
    });
  });
}
