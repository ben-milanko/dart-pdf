// Writers tile large images as abutting clipped strips; antialiased clip
// edges would leave hairline seams of the backdrop at every boundary.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

/// One page: a dark 1x1 image drawn twice over a white page, clipped to
/// two abutting bands whose shared edge (x=85.3) is not pixel-aligned.
Uint8List buildStripsPdf() {
  const content = 'q 10 10 75.3 80 re W n '
      'q 150.6 0 0 80 10 10 cm /Im Do Q Q '
      'q 85.3 10 75.3 80 re W n '
      'q 150.6 0 0 80 10 10 cm /Im Do Q Q';
  // 1x1 DeviceRGB pixel (40,40,40) - the bytes are ASCII '((('
  const pixel = '(((';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] /Contents 4 0 R '
        '/Resources << /XObject << /Im 5 0 R >> >> >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    '<< /Subtype /Image /Width 1 /Height 1 /BitsPerComponent 8 '
        '/ColorSpace /DeviceRGB /Length ${pixel.length} >>'
        '\nstream\n$pixel\nendstream',
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

void main() {
  testWidgets('abutting clipped image strips tile without seams',
      (tester) async {
    await tester.runAsync(() async {
      final doc = PdfDocument.open(buildStripsPdf());
      final image =
          await PdfPageRenderer.renderImage(doc.page(0), pixelRatio: 2);
      final data =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final px = data.buffer.asUint8List();

      // scan a row through the strips: every covered pixel must be the
      // image's dark gray, never a backdrop-blended seam
      const y = 100; // page y=50, inside the bands
      for (var x = 24; x < 318; x++) {
        final i = (y * image.width + x) * 4;
        expect(px[i], lessThan(80),
            reason: 'seam at x=$x: rgb(${px[i]},${px[i + 1]},${px[i + 2]})');
      }
    });
  });
}
