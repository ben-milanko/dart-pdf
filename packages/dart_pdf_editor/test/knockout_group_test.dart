// A knockout transparency group (/K true, §11.4.5) composites each element
// against the group's initial backdrop, so a later element replaces an
// earlier one where they overlap instead of blending over it. Mirrors
// pdf.js's knockout_isolated_overlap.pdf fixture.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

/// One page: a red and a blue rectangle, each filled at alpha 0.5, drawn
/// inside an isolated transparency group. [knockout] toggles the group's
/// /K flag. Red covers x[20,120], blue x[70,170]; they overlap in x[70,120].
Uint8List buildOverlapPdf({required bool knockout}) {
  const form = 'q /A gs '
      '1 0 0 rg 20 30 100 80 re f '
      '0 0 1 rg 70 50 100 80 re f Q';
  final groupDict = '<< /Type /Group /S /Transparency /CS /DeviceRGB '
      '/I true${knockout ? ' /K true' : ''} >>';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 160] /Contents 4 0 R '
        '/Resources << /XObject << /G1 5 0 R >> /ExtGState << /A 6 0 R >> >> >>',
    '<< /Length 11 >>\nstream\nq /G1 Do Q\nendstream',
    '<< /Type /XObject /Subtype /Form /FormType 1 /BBox [0 0 200 160] '
        '/Resources << /ExtGState << /A 6 0 R >> >> /Group $groupDict '
        '/Length ${form.length} >>\nstream\n$form\nendstream',
    '<< /Type /ExtGState /ca 0.5 /CA 0.5 >>',
  ];
  final buffer = StringBuffer('%PDF-1.7\n');
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
  // Samples the overlap centre and the red-only / blue-only regions of a
  // rendered overlap page. Page (200x160) renders y-flipped at ratio 1.
  Future<(List<int> redOnly, List<int> blueOnly, List<int> overlap)> sample(
      bool knockout) async {
    final doc = PdfDocument.open(buildOverlapPdf(knockout: knockout));
    final image = await PdfPageRenderer.renderImage(doc.page(0), pixelRatio: 1);
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final px = data.buffer.asUint8List();
    List<int> at(int x, int y) {
      final i = (y * image.width + x) * 4;
      return [px[i], px[i + 1], px[i + 2]];
    }
    // PDF y -> image y is (160 - y). red-only (45,40), blue-only (150,120),
    // overlap (95,80) all land inside their regions.
    return (at(45, 120), at(150, 40), at(95, 80));
  }

  testWidgets('knockout group: later element replaces earlier in the overlap',
      (tester) async {
    await tester.runAsync(() async {
      final (redOnly, blueOnly, overlap) = await sample(true);
      // red@0.5 over white and blue@0.5 over white are unaffected by knockout
      expect(redOnly[0], greaterThan(230)); // red
      expect(blueOnly[2], greaterThan(230)); // blue
      // overlap is blue@0.5 over white (~128,128,255): blue knocked out red,
      // so it is NOT the purple (~128,64,192) of blue-over-red blending.
      expect(overlap[2], greaterThan(230), reason: 'overlap blue: $overlap');
      expect(overlap[1], greaterThan(100), reason: 'overlap green: $overlap');
    });
  });

  testWidgets('without /K the overlap blends blue over red (purple)',
      (tester) async {
    await tester.runAsync(() async {
      final overlap = (await sample(false)).$3;
      // blue@0.5 over (red@0.5 over white) ~= (128,64,192): less blue, less
      // green than the knockout result — the control that proves /K matters.
      expect(overlap[2], lessThan(220), reason: 'overlap blue: $overlap');
      expect(overlap[1], lessThan(100), reason: 'overlap green: $overlap');
    });
  });
}
