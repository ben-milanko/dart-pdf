// Dash patterns (`d` operator) must produce gaps, honoring the phase.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

Uint8List buildDashedPdf() {
  // a 4pt black line across y=25, dashed 10 on / 10 off, and a second
  // line at y=10 with phase 10 (starts in the gap)
  const content = '1 g 0 0 100 50 re f\n'
      '4 w 0 G [10 10] 0 d 10 25 m 90 25 l S\n'
      '[10 10] 10 d 10 10 m 90 10 l S';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 50] '
        '/Contents 4 0 R >>',
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

void main() {
  testWidgets('dash arrays produce gaps and honor the phase', (tester) async {
    await tester.runAsync(() async {
      final doc = PdfDocument.open(buildDashedPdf());
      final image =
          await PdfPageRenderer.renderImage(doc.page(0), pixelRatio: 1);
      final data =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final px = data.buffer.asUint8List();
      int at(int x, int y) => px[(y * image.width + x) * 4];

      // y=25 (device row 25): on 10..20, off 20..30, on 30..40 ...
      expect(at(15, 25), lessThan(60), reason: 'first dash paints');
      expect(at(25, 25), greaterThan(200), reason: 'first gap is empty');
      expect(at(35, 25), lessThan(60), reason: 'second dash paints');

      // y=10 (device row 40): phase 10 starts inside the gap
      expect(at(15, 40), greaterThan(200), reason: 'phase shifts the gap');
      expect(at(25, 40), lessThan(60), reason: 'phase shifts the dash');
    });
  });
}
