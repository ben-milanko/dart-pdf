// The images→PDF assembler (PdfImageDocument): a stack of PNG/JPEG images
// becomes a one-page-per-image PDF that reparses cleanly.
import 'dart:convert';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

String _content(PdfDocument doc, int page) =>
    latin1.decode(doc.page(page).contentBytes(), allowInvalid: true);

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

      // The JPEG passes through verbatim: DCTDecode, raw bytes unchanged.
      final xobjects =
          doc.cos.resolve(page1.resources['XObject']) as CosDictionary;
      final image = doc.cos.resolve(xobjects['Im0']) as CosStream;
      expect(image.dictionary['Filter'], const CosName('DCTDecode'));
      expect(image.rawBytes, orderedEquals(jpeg));
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
      expect(
        () => PdfImageDocument.fromImageBytes([_png], margin: -1),
        throwsArgumentError,
      );
    });

    group('fixed page size with fit/placement', () {
      test('lays the image onto an A4 page', () {
        final doc = PdfDocument.open(
          PdfImageDocument.fromImageBytes([_png], pageSize: PdfPageSize.a4),
        );
        final box = doc.page(0).mediaBox;
        expect(box.width, closeTo(595.28, 0.01));
        expect(box.height, closeTo(841.89, 0.01));
      });

      test('contain centres a square image and preserves aspect ratio', () {
        // A 2x2 image on Letter, contain → scaled to the 612-pt width and
        // centred vertically.
        final doc = PdfDocument.open(PdfImageDocument.fromImageBytes(
          [_png],
          pageSize: PdfPageSize.letter,
          fit: PdfImageFit.contain,
        ));
        final content = _content(doc, 0);
        // square image, square-ish scale: drawn 612x612, centred at y=90.
        expect(content, contains('612 0 0 612 0 90 cm'));
        expect(content, contains('/Im0 Do'));
      });

      test('fill stretches to the whole content box', () {
        final doc = PdfDocument.open(PdfImageDocument.fromImageBytes(
          [_png],
          pageSize: const PdfPageSize(100, 200),
          fit: PdfImageFit.fill,
        ));
        expect(_content(doc, 0), contains('100 0 0 200 0 0 cm'));
      });

      test('cover clips the overflow to the content box', () {
        final doc = PdfDocument.open(PdfImageDocument.fromImageBytes(
          [_png],
          pageSize: const PdfPageSize(100, 200),
          fit: PdfImageFit.cover,
        ));
        final content = _content(doc, 0);
        // cover a 2x2 onto 100x200 → scale 100, drawn 200x200 (overflows
        // width), centred horizontally at x=-50 and clipped to the page.
        expect(content, contains('0 0 100 200 re'));
        expect(content, contains('W'));
        expect(content, contains('200 0 0 200 -50 0 cm'));
      });

      test('none keeps natural size and honours alignment + margin', () {
        final doc = PdfDocument.open(PdfImageDocument.fromImageBytes(
          [_png],
          pageSize: const PdfPageSize(100, 100),
          fit: PdfImageFit.none,
          align: PdfImageAlign.bottomLeft,
          margin: 10,
        ));
        final content = _content(doc, 0);
        // 2x2 at 72 dpi → 2x2 points, anchored at the content-box bottom-left
        // (margin 10), clipped to the 80x80 content box.
        expect(content, contains('10 10 80 80 re'));
        expect(content, contains('2 0 0 2 10 10 cm'));
      });

      test('portrait/landscape reorient a size', () {
        expect(PdfPageSize.a4.landscape.width, greaterThan(
            PdfPageSize.a4.landscape.height));
        expect(PdfPageSize.a4.portrait.height, greaterThan(
            PdfPageSize.a4.portrait.width));
      });
    });
  });
}
