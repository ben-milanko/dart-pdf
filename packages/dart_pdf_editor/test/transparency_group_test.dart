// A transparency-group form composites as one object: the ca in effect at
// Do applies to the group's result even when content inside the group
// resets ca to 1.0 with its own gs (§11.6.6).
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

Uint8List buildGroupAlphaPdf() {
  const content = '1 g 0 0 100 100 re f\n'
      'q /GShalf gs /Grp Do Q\n'
      'q /GShalf gs /Plain Do Q';
  // both forms fill black under their own gs that resets ca to 1.0
  const inner = '/GSfull gs 0 g BBOX re f';
  final grpContent = inner.replaceFirst('BBOX', '10 10 30 30');
  final plainContent = inner.replaceFirst('BBOX', '60 10 30 30');
  const gsFull = '/GSfull << /Type /ExtGState /ca 1.0 /CA 1.0 >>';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Contents 4 0 R '
        '/Resources << '
        '/ExtGState << /GShalf << /Type /ExtGState /ca 0.5 /CA 0.5 >> >> '
        '/XObject << /Grp 5 0 R /Plain 6 0 R >> >> >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    '<< /Subtype /Form /BBox [0 0 100 100] '
        '/Group << /S /Transparency /Type /Group >> '
        '/Resources << /ExtGState << $gsFull >> >> '
        '/Length ${grpContent.length} >>\nstream\n$grpContent\nendstream',
    '<< /Subtype /Form /BBox [0 0 100 100] '
        '/Resources << /ExtGState << $gsFull >> >> '
        '/Length ${plainContent.length} >>\nstream\n$plainContent\nendstream',
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
  testWidgets(
      'group ca survives an inner gs reset; plain forms keep '
      'per-paint alpha semantics', (tester) async {
    await tester.runAsync(() async {
      final doc = PdfDocument.open(buildGroupAlphaPdf());
      final image =
          await PdfPageRenderer.renderImage(doc.page(0), pixelRatio: 1);
      final data =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final px = data.buffer.asUint8List();
      int at(int x, int y) => px[(y * image.width + x) * 4];
      // group form: black at group ca 0.5 over white ≈ 127
      expect(at(25, 75), inInclusiveRange(120, 135));
      // plain form: the inner gs legitimately resets ca → solid black
      expect(at(75, 75), lessThan(10));
    });
  });
}
