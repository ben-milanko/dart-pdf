import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

void main() {
  group('PdfEditor.compress', () {
    test('shrinks a classic multi-page file and keeps every page', () {
      final original = buildMultiPagePdf(24);
      final editor = PdfEditor(PdfDocument.open(original));
      final result = editor.compress();

      expect(result.compacted, isTrue);
      expect(result.bytesAfter, lessThan(result.bytesBefore));
      expect(result.bytes.length, result.bytesAfter);
      expect(result.ratio, greaterThan(0));

      final reopened = PdfDocument.open(result.bytes);
      expect(reopened.pageCount, 24);
    });

    test('includes pending unsaved edits in the compacted output', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(6)))
        ..setInfo(title: 'Compacted');
      final result = editor.compress();

      final reopened = PdfDocument.open(result.bytes);
      expect(reopened.info['Title'], 'Compacted');
      expect(reopened.pageCount, 6);
    });

    test('never returns a larger file than the input', () {
      // an already object-stream file has little structural slack; the gate
      // must keep the smaller of compacted vs. original.
      final original = buildXrefStreamPdf();
      final result = PdfEditor(PdfDocument.open(original)).compress();

      expect(result.bytesAfter, lessThanOrEqualTo(result.bytesBefore));
      if (!result.compacted) {
        expect(result.bytes, original);
        expect(result.bytesSaved, 0);
      }
    });

    test('refuses an encrypted document', () {
      final editor = PdfEditor(PdfDocument.open(buildEncryptedPdf()));
      expect(editor.compress, throwsArgumentError);
    });
  });
}
