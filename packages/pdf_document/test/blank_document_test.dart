import 'package:pdf_document/pdf_document.dart';
import 'package:test/test.dart';

void main() {
  group('PdfBlankDocument', () {
    test('creates a valid blank document at the requested size', () {
      final document = PdfDocument.open(
        PdfBlankDocument.create(pageSize: PdfPageSize.a4.landscape),
      );

      expect(document.pageCount, 1);
      final page = document.page(0);
      expect(page.mediaBox.width, closeTo(PdfPageSize.a4.height, 0.01));
      expect(page.mediaBox.height, closeTo(PdfPageSize.a4.width, 0.01));
      expect(page.resources.entries, isEmpty);
      expect(page.contentBytes(), isEmpty);
    });

    test('can create several pages', () {
      final document = PdfDocument.open(PdfBlankDocument.create(
        pageSize: PdfPageSize.a5,
        pageCount: 3,
      ));

      expect(document.pageCount, 3);
      for (var i = 0; i < document.pageCount; i++) {
        expect(document.page(i).mediaBox.width, closeTo(419.53, 0.01));
        expect(document.page(i).mediaBox.height, closeTo(595.28, 0.01));
      }
    });

    test('rejects invalid sizes and page counts', () {
      expect(
        () => PdfBlankDocument.create(pageSize: const PdfPageSize(0, 100)),
        throwsArgumentError,
      );
      expect(
        () => PdfBlankDocument.create(
          pageSize: const PdfPageSize(double.nan, 100),
        ),
        throwsArgumentError,
      );
      expect(
        () => PdfBlankDocument.create(pageCount: 0),
        throwsArgumentError,
      );
    });
  });
}
