import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';

Uint8List buildPdf(String content) {
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
  ];
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = buffer.length;
  buffer.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final o in offsets) {
    buffer.write('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer.write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
      'startxref\n$xref\n%%EOF\n');
  return Uint8List.fromList(buffer.toString().codeUnits);
}

void main() {
  // Inline images synthesize a fresh CosStream every interpretation pass,
  // so decoded pixels must be keyed by value (PdfInlineImageKey) - keyed by
  // stream identity the paint-time lookup never hits and nothing draws.
  testWidgets('inline image (BI..ID..EI) renders', (tester) async {
    await tester.runAsync(() async {
      const content = 'q 100 0 0 100 50 50 cm '
          'BI /W 4 /H 4 /CS /RGB /BPC 8 /F /AHx ID\n'
          'e63030 ffffff e63030 ffffff\n'
          'ffffff e63030 ffffff e63030\n'
          'e63030 ffffff e63030 ffffff\n'
          'ffffff e63030 ffffff e63030 >\nEI Q\n';
      final doc = PdfDocument.open(buildPdf(content));
      final image = await PdfPageRenderer.renderImage(doc.page(0));
      final data = await image.toByteData();
      var red = 0;
      for (var i = 0; i < data!.lengthInBytes; i += 4) {
        if (data.getUint8(i) > 200 && data.getUint8(i + 1) < 100) red++;
      }
      expect(red, greaterThan(1000));
    });
  });
}
