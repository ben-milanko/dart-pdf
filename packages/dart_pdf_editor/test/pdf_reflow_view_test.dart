import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

/// A one-page PDF with two text paragraphs and a decodable 2×2 DeviceRGB image
/// drawn between them.
Uint8List _imagePdf() {
  const hex = 'FF000000FF000000FFFFFFFF>';
  const content = 'BT /F1 12 Tf 100 700 Td (Above the figure) Tj ET\n'
      'q 200 0 0 120 100 480 cm /Im0 Do Q\n'
      'BT /F1 12 Tf 100 360 Td (Below the figure) Tj ET';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R '
        '/Resources << /Font << /F1 5 0 R >> /XObject << /Im0 6 0 R >> >> >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    '<< /Type /XObject /Subtype /Image /Width 2 /Height 2 '
        '/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /ASCIIHexDecode '
        '/Length ${hex.length} >>\nstream\n$hex\nendstream',
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

Future<void> _settleReflow(WidgetTester tester) async {
  // The view loads pages and decodes images off the first frame; poll until the
  // FutureBuilder resolves (decoding needs real async via runAsync).
  for (var i = 0; i < 50; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    if (find.text('Above the figure').evaluate().isNotEmpty) return;
  }
}

void main() {
  testWidgets('renders a placed image inline with the text', (tester) async {
    await tester.runAsync(() async {
      final doc = PdfDocument.open(_imagePdf());
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PdfReflowView(document: doc)),
      ));
      await _settleReflow(tester);

      expect(find.text('Above the figure'), findsOneWidget);
      expect(find.text('Below the figure'), findsOneWidget);
      expect(find.byType(RawImage), findsOneWidget);
    });
  });

  testWidgets('showImages: false reads text-only, no image', (tester) async {
    await tester.runAsync(() async {
      final doc = PdfDocument.open(_imagePdf());
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PdfReflowView(document: doc, showImages: false),
        ),
      ));
      await _settleReflow(tester);

      expect(find.text('Above the figure'), findsOneWidget);
      expect(find.byType(RawImage), findsNothing);
    });
  });
}
