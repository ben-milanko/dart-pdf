// encodePageForVectorPrinting is the Windows/Linux vector-print entry point:
// it lowers a page to the VPR1 op stream using the app's dart:ui-backed image
// decode, so baseline-JPEG underlays (which the pure-Dart path declines) still
// reach the stream. These tests drive that dart:ui path.
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

/// Builds a one-page PDF whose content is [content], with optional image and
/// font resources, using exact byte offsets so any raw image bytes survive.
Uint8List buildPagePdf(
  String content, {
  List<int>? imageBytes,
  int imageWidth = 0,
  int imageHeight = 0,
}) {
  final hasImage = imageBytes != null;
  final resources = hasImage
      ? '/Resources << /XObject << /Im0 5 0 R >> >>'
      : '/Resources << /Font << /F1 5 0 R >> >>';
  final objects = <List<int>>[
    '<< /Type /Catalog /Pages 2 0 R >>'.codeUnits,
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>'.codeUnits,
    ('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 300] /Contents 4 0 R '
            '$resources >>')
        .codeUnits,
    '<< /Length ${content.length} >>\nstream\n$content\nendstream'.codeUnits,
    if (hasImage)
      <int>[
        ...'<< /Type /XObject /Subtype /Image /Width $imageWidth '
                '/Height $imageHeight /ColorSpace /DeviceRGB /BitsPerComponent 8 '
                '/Length ${imageBytes.length} >>\nstream\n'
            .codeUnits,
        ...imageBytes,
        ...'\nendstream'.codeUnits,
      ]
    else
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'.codeUnits,
  ];
  final buffer = <int>[];
  void write(String s) => buffer.addAll(s.codeUnits);
  write('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    write('${i + 1} 0 obj\n');
    buffer.addAll(objects[i]);
    write('\nendobj\n');
  }
  final xrefOffset = buffer.length;
  write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
      'startxref\n$xrefOffset\n%%EOF\n');
  return Uint8List.fromList(buffer);
}

void main() {
  testWidgets('encodes a text page to a VPR1 stream with selectable text',
      (tester) async {
    await tester.runAsync(() async {
      final doc = PdfDocument.open(
          buildPagePdf('BT /F1 24 Tf 40 200 Td (Print me) Tj ET'));
      final bytes = await encodePageForVectorPrinting(doc.page(0));
      // VPR1 magic header.
      expect(bytes.sublist(0, 4), [0x56, 0x50, 0x52, 0x01]);
      final page = decodeVectorPrint(bytes);
      expect(page.widthPt, closeTo(300, 0.01));
      final texts = page.ops.whereType<VpText>().map((t) => t.text).join();
      expect(texts, contains('Print me'));
    });
  });

  testWidgets('decodes an image through dart:ui into an image op',
      (tester) async {
    await tester.runAsync(() async {
      // 2x1 DeviceRGB raw image (red, green), placed by a cm matrix.
      final doc = PdfDocument.open(buildPagePdf(
        'q 200 0 0 100 20 30 cm /Im0 Do Q',
        imageBytes: <int>[0xFF, 0x00, 0x00, 0x00, 0xFF, 0x00],
        imageWidth: 2,
        imageHeight: 1,
      ));
      final page = decodeVectorPrint(await encodePageForVectorPrinting(doc.page(0)));
      final images = page.ops.whereType<VpImage>().toList();
      expect(images, hasLength(1));
      expect(images.single.width, 2);
      expect(images.single.height, 1);
      // The dart:ui decode yields premultiplied RGBA (opaque here, so the
      // colour samples survive): first pixel red, second green.
      final rgba = images.single.rgba;
      expect(rgba[0], 255); // R of pixel 0
      expect(rgba[3], 255); // A of pixel 0
      expect(rgba[5], 255); // G of pixel 1
    });
  });
}
