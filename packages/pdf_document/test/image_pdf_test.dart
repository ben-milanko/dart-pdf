// The images→PDF assembler (PdfImageDocument): a stack of PNG/JPEG images
// becomes a one-page-per-image PDF that reparses cleanly.
import 'dart:convert';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

// 2x2 RGBA-8 PNG (from png_test.dart's fixtures).
final _png = base64.decode('iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0k'
    'AAAAGUlEQVR4nGP4z8DwHwgbWBgZ/jNyicr7AgA3BAUOTnqjAAAAAABJRU5ErkJggg==');

void main() {
  group('PdfImageDocument', () {
    test('round-trips a PNG and a JPEG into a new document', () {
      final jpeg = buildTestJpeg();
      final jpegInfo = PdfEmbeddableImage.jpeg(jpeg);

      final bytes = PdfImageDocument.fromImageBytes([_png, jpeg]);
      final doc = PdfDocument.open(bytes);

      expect(doc.pageCount, 2);

      // Page sizes follow the image pixels at the default 72 dpi.
      final page0 = doc.page(0);
      expect(page0.mediaBox.width, 2);
      expect(page0.mediaBox.height, 2);

      final page1 = doc.page(1);
      expect(page1.mediaBox.width, jpegInfo.width.toDouble());
      expect(page1.mediaBox.height, jpegInfo.height.toDouble());

      // Each page references its image XObject and draws it.
      expect(page0.resources['XObject'], isNotNull);
    });

    test('dpi scales the page down', () {
      final bytes = PdfImageDocument.fromImageBytes([_png], dpi: 144);
      final doc = PdfDocument.open(bytes);
      // 2 px at 144 dpi = 1 pt.
      expect(doc.page(0).mediaBox.width, 1);
      expect(doc.page(0).mediaBox.height, 1);
    });

    test('decoded images can be passed directly', () {
      final image = PdfEmbeddableImage.decode(_png);
      final doc =
          PdfDocument.open(PdfImageDocument.fromImages([image, image]));
      expect(doc.pageCount, 2);
    });

    test('rejects an empty list and a non-positive dpi', () {
      expect(() => PdfImageDocument.fromImages([]), throwsArgumentError);
      expect(
        () => PdfImageDocument.fromImageBytes([_png], dpi: 0),
        throwsArgumentError,
      );
    });
  });
}
