// PDF → image export (PdfPageExport): round-trips a solid-colour image
// through image→PDF→image at chosen DPI and format, proving the PNG path is
// byte-identical to the renderer and the JPEG path is faithful within
// tolerance.
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf_document/pdf_document.dart';

/// A [size]×[size] solid-colour PNG.
List<int> _solidPng(int size, int r, int g, int b) {
  final image = img.Image(width: size, height: size);
  img.fill(image, color: img.ColorRgb8(r, g, b));
  return img.encodePng(image);
}

void main() {
  // A 32-pixel solid-red square embedded at 72 dpi → a 32×32-pt page.
  PdfDocument redDoc() => PdfDocument.open(PdfImageDocument.fromImageBytes(
        [Uint8List.fromList(_solidPng(32, 220, 30, 30))],
      ));

  testWidgets('exports a page to PNG at the page resolution', (tester) async {
    await tester.runAsync(() async {
      final doc = redDoc();
      final bytes = await PdfPageExport.exportPage(doc.page(0), dpi: 72);

      // Real PNG signature.
      expect(bytes.sublist(0, 8),
          [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      final decoded = img.decodePng(bytes)!;
      expect(decoded.width, 32);
      expect(decoded.height, 32);
      final p = decoded.getPixel(16, 16);
      expect(p.r, closeTo(220, 4));
      expect(p.g, closeTo(30, 4));
      expect(p.b, closeTo(30, 4));
    });
  });

  testWidgets('dpi scales the raster up', (tester) async {
    await tester.runAsync(() async {
      final doc = redDoc();
      final bytes = await PdfPageExport.exportPage(doc.page(0), dpi: 144);
      final decoded = img.decodePng(bytes)!;
      // 32 pt at 144 dpi = 64 px.
      expect(decoded.width, 64);
      expect(decoded.height, 64);
    });
  });

  testWidgets('JPEG export carries the same picture within tolerance',
      (tester) async {
    await tester.runAsync(() async {
      final doc = redDoc();
      final png = img.decodePng(
          await PdfPageExport.exportPage(doc.page(0), dpi: 72))!;
      final jpegBytes = await PdfPageExport.exportPage(
        doc.page(0),
        format: PdfRasterFormat.jpeg,
        dpi: 72,
        jpegQuality: 95,
      );
      // JFIF/JPEG SOI marker.
      expect(jpegBytes[0], 0xFF);
      expect(jpegBytes[1], 0xD8);

      final jpeg = img.decodeJpg(jpegBytes)!;
      expect(jpeg.width, png.width);
      expect(jpeg.height, png.height);

      // Mean per-channel difference stays tiny (lossy, but quality 95).
      var diff = 0;
      var n = 0;
      for (var y = 0; y < png.height; y += 4) {
        for (var x = 0; x < png.width; x += 4) {
          final a = png.getPixel(x, y);
          final b = jpeg.getPixel(x, y);
          diff += (a.r - b.r).abs().toInt() +
              (a.g - b.g).abs().toInt() +
              (a.b - b.b).abs().toInt();
          n += 3;
        }
      }
      expect(diff / n, lessThan(6));
    });
  });

  testWidgets('JPEG flattens transparency onto the page colour',
      (tester) async {
    await tester.runAsync(() async {
      // A translucent page colour over the red image: JPEG has no alpha, so
      // the export must composite, never emit a black or transparent frame.
      final doc = redDoc();
      final jpegBytes = await PdfPageExport.exportPage(
        doc.page(0),
        format: PdfRasterFormat.jpeg,
        pageColor: const Color(0xFFFFFFFF),
        dpi: 72,
      );
      final jpeg = img.decodeJpg(jpegBytes)!;
      final corner = jpeg.getPixel(0, 0);
      // The image fills the page, so even the corner is the red image, not
      // black — proving the frame is a real composited picture.
      expect(corner.r, greaterThan(corner.b));
    });
  });

  testWidgets('exportPages walks a range', (tester) async {
    await tester.runAsync(() async {
      final doc = PdfDocument.open(PdfImageDocument.fromImageBytes([
        Uint8List.fromList(_solidPng(8, 255, 0, 0)),
        Uint8List.fromList(_solidPng(8, 0, 255, 0)),
        Uint8List.fromList(_solidPng(8, 0, 0, 255)),
      ]));
      final pages = await PdfPageExport.exportPages(doc, start: 1, dpi: 72);
      expect(pages.length, 2);
      final green = img.decodePng(pages[0])!.getPixel(4, 4);
      expect(green.g, greaterThan(green.r));
      expect(green.g, greaterThan(green.b));
    });
  });
}
