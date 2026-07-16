import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  // US Letter shown 800px wide; crop box offset exercises the origin shift
  const geometry = PdfPageGeometry(
    cropBox: PdfRect(10, 20, 622, 812),
    rotation: 0,
    viewSize: Size(800, 1035.3),
  );

  test('maps PDF space to view space', () {
    final scale = 800 / 612;
    expect(geometry.scale, moreOrLessEquals(scale));
    // bottom-left of the crop box is the view's bottom-left corner
    final origin = geometry.toViewOffset(10, 20);
    expect(origin.dx, moreOrLessEquals(0));
    expect(origin.dy, moreOrLessEquals(792 * scale));
    // top-left corner of the page is the view origin
    final topLeft = geometry.toViewOffset(10, 812);
    expect(topLeft.dx, moreOrLessEquals(0));
    expect(topLeft.dy, moreOrLessEquals(0));

    final rect = geometry.toViewRect(const PdfRect(82, 712, 182, 762));
    expect(rect.left, moreOrLessEquals(72 * scale));
    expect(rect.top, moreOrLessEquals((812 - 762) * scale));
    expect(rect.width, moreOrLessEquals(100 * scale));
    expect(rect.height, moreOrLessEquals(50 * scale));
  });

  test('round-trips between page and view space', () {
    const pageRect = PdfRect(82, 712, 182, 762);
    final back = geometry.toPageRect(geometry.toViewRect(pageRect));
    expect(back.left, moreOrLessEquals(pageRect.left));
    expect(back.bottom, moreOrLessEquals(pageRect.bottom));
    expect(back.right, moreOrLessEquals(pageRect.right));
    expect(back.top, moreOrLessEquals(pageRect.top));

    final (x, y) = geometry.toPagePoint(geometry.toViewOffset(123, 456));
    expect(x, moreOrLessEquals(123));
    expect(y, moreOrLessEquals(456));
  });

  test('an inset origin makes the surrounding band map off-page', () {
    // the page is inset 40px on the left inside a wider drawing surface;
    // the 612pt page shows 720px wide (scale 720/612)
    const inset = PdfPageGeometry(
      cropBox: PdfRect(0, 0, 612, 792),
      rotation: 0,
      viewSize: Size(720, 932.9),
      origin: Offset(40, 0),
    );
    final scale = 720 / 612;
    // the page's top-left now sits at the origin, not the surface corner
    final topLeft = inset.toViewOffset(0, 792);
    expect(topLeft.dx, moreOrLessEquals(40));
    expect(topLeft.dy, moreOrLessEquals(0));
    // a gesture in the left pasteboard band (left of the page) maps to a
    // negative (off-page) x, unclamped - exactly what off-page authoring needs
    final (x, y) = inset.toPagePoint(const Offset(10, 100));
    expect(x, lessThan(0), reason: 'left of the page is off-page in x');
    expect(x, moreOrLessEquals((10 - 40) / scale));
    expect(y, moreOrLessEquals(792 - 100 / scale));
    // and the round-trip still holds through the origin
    final (rx, ry) = inset.toPagePoint(inset.toViewOffset(123, 456));
    expect(rx, moreOrLessEquals(123));
    expect(ry, moreOrLessEquals(456));
  });

  test('rotated pages swap the on-screen aspect and round-trip', () {
    for (final rotation in [90, 180, 270]) {
      final sideways = rotation != 180;
      final geometry = PdfPageGeometry(
        cropBox: const PdfRect(10, 20, 622, 812),
        rotation: rotation,
        viewSize: sideways ? const Size(792, 612) : const Size(612, 792),
      );
      expect(geometry.scale, moreOrLessEquals(1), reason: '$rotation');
      final (x, y) = geometry.toPagePoint(geometry.toViewOffset(123, 456));
      expect(x, moreOrLessEquals(123), reason: '$rotation');
      expect(y, moreOrLessEquals(456), reason: '$rotation');

      const pageRect = PdfRect(82, 712, 182, 762);
      final back = geometry.toPageRect(geometry.toViewRect(pageRect));
      expect(back.left, moreOrLessEquals(pageRect.left), reason: '$rotation');
      expect(back.top, moreOrLessEquals(pageRect.top), reason: '$rotation');
    }
  });

  test('/Rotate 90 turns the page clockwise', () {
    // an unrotated page's top-left corner lands at the view's top-right
    const geometry = PdfPageGeometry(
      cropBox: PdfRect(0, 0, 612, 792),
      rotation: 90,
      viewSize: Size(792, 612),
    );
    final corner = geometry.toViewOffset(0, 792);
    expect(corner.dx, moreOrLessEquals(792));
    expect(corner.dy, moreOrLessEquals(0));
  });

  group('agrees with the renderer', () {
    /// One 200x300 page with /Rotate [rotation] and a black 20x20 square
    /// at (100, 150)..(120, 170) in page space.
    Uint8List buildRotatedPdf(int rotation) {
      const content = '0 g 100 150 20 20 re f';
      final objects = <String>[
        '<< /Type /Catalog /Pages 2 0 R >>',
        '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 300] '
            '/Rotate $rotation /Contents 4 0 R >>',
        '<< /Length ${content.length} >>\nstream\n$content\nendstream',
      ];
      final buffer = StringBuffer('%PDF-1.4\n');
      final offsets = <int>[];
      for (var i = 0; i < objects.length; i++) {
        offsets.add(buffer.length);
        buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
      }
      final xrefOffset = buffer.length;
      buffer
        ..write('xref\n0 ${objects.length + 1}\n')
        ..write('0000000000 65535 f \n');
      for (final offset in offsets) {
        buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
      }
      buffer
        ..write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n')
        ..write('startxref\n$xrefOffset\n%%EOF\n');
      return ascii(buffer.toString());
    }

    for (final rotation in [0, 90, 180, 270]) {
      testWidgets('toViewOffset hits the rendered mark at /Rotate $rotation',
          (tester) async {
        await tester.runAsync(() async {
          final doc = PdfDocument.open(buildRotatedPdf(rotation));
          final page = doc.page(0);
          final image = await PdfPageRenderer.renderImage(page);
          final size = Size(image.width.toDouble(), image.height.toDouble());
          final geometry = PdfPageGeometry(
            cropBox: page.cropBox,
            rotation: page.rotation,
            viewSize: size,
          );
          final data =
              (await image.toByteData(format: ImageByteFormat.rawRgba))!
                  .buffer
                  .asUint8List();
          int pixelAt(Offset view) {
            final x = view.dx.round().clamp(0, image.width - 1);
            final y = view.dy.round().clamp(0, image.height - 1);
            return data[(y * image.width + x) * 4]; // red channel
          }

          // center of the square must be black, page center far from
          // the square must stay white
          expect(pixelAt(geometry.toViewOffset(110, 160)), lessThan(50));
          expect(pixelAt(geometry.toViewOffset(50, 50)), greaterThan(200));
        });
      });
    }
  });
}
