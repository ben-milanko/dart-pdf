import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';

/// A 100x100 page whose content paints a type 4 mesh: one triangle
/// covering the lower-left half, red at (0,0), green at (100,0), blue
/// at (0,100).
Uint8List buildMeshPdf() {
  final meshData = [
    0, 0, 0, 255, 0, 0, //
    0, 255, 0, 0, 255, 0,
    0, 0, 255, 0, 0, 255,
  ];
  const content = '/Sh1 sh';
  final shadingDict = '<< /ShadingType 4 /ColorSpace /DeviceRGB '
      '/BitsPerCoordinate 8 /BitsPerComponent 8 /BitsPerFlag 8 '
      '/Decode [0 100 0 100 0 1 0 1 0 1] /Length ${meshData.length} >>';
  final objects = <Object>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] '
        '/Contents 4 0 R /Resources << /Shading << /Sh1 5 0 R >> >> >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    (shadingDict, meshData), // stream with binary payload
  ];
  final out = BytesBuilder();
  final offsets = <int>[];
  void write(String s) => out.add(s.codeUnits);
  write('%PDF-1.4\n');
  for (var i = 0; i < objects.length; i++) {
    offsets.add(out.length);
    final object = objects[i];
    if (object is String) {
      write('${i + 1} 0 obj\n$object\nendobj\n');
    } else {
      final (dict, data) = object as (String, List<int>);
      write('${i + 1} 0 obj\n$dict\nstream\n');
      out.add(data);
      write('\nendstream\nendobj\n');
    }
  }
  final xrefOffset = out.length;
  write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
      'startxref\n$xrefOffset\n%%EOF\n');
  return out.takeBytes();
}

void main() {
  testWidgets('a type 4 mesh shading renders Gouraud triangles',
      (tester) async {
    await tester.runAsync(() async {
      final doc = PdfDocument.open(buildMeshPdf());
      final image = await PdfPageRenderer.renderImage(doc.page(0));
      final data = (await image.toByteData(format: ImageByteFormat.rawRgba))!
          .buffer
          .asUint8List();
      List<int> at(int x, int y) {
        final i = (y * image.width + x) * 4;
        return [data[i], data[i + 1], data[i + 2]];
      }

      // PDF y-up: page (0,0) is the bottom-left of the raster
      final red = at(4, image.height - 5);
      expect(red[0], greaterThan(180));
      expect(red[1], lessThan(90));

      final green = at(image.width - 5, image.height - 5);
      expect(green[1], greaterThan(180));
      expect(green[0], lessThan(90));

      final blue = at(4, 4);
      expect(blue[2], greaterThan(180));
      expect(blue[1], lessThan(90));

      // the centroid blends all three corners
      final mid = at(30, 60);
      expect(mid[0], greaterThan(40));
      expect(mid[1], greaterThan(20));
      expect(mid[2], greaterThan(40));

      // outside the triangle (upper-right half) stays white
      final outside = at(image.width - 5, 4);
      expect(outside, [255, 255, 255]);
    });
  });
}
