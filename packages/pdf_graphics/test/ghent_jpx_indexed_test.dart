// Ghent JPEG2000 self-grading pages - decode guard (issue #431).
//
// GWG170 (DeviceCMYK) and GWG172 (ICCBasedRGB) each place a JPEG2000 image
// whose /ColorSpace is /Indexed with a single-entry palette (hival 0). The
// page draws a big fail-marker "X" and states "No 'X' must be visible when
// rendered correctly": the image, clipped to the X shape, is meant to cover
// that X with the palette colour. A JPX base decoded as if its single
// component were colour paints the raw index value instead - index 0 → gray 0
// → a solid black square, leaving a black X exposed.
//
// These pages grade themselves, so this pins the decode directly as well as
// through the all-page raster baseline. The image must decode to a uniform,
// opaque, distinctly-hued square - never the old black. The ICC sibling's
// palette green is then converted through the document OutputIntent.
import 'dart:io';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:test/test.dart';

void main() {
  final root = Directory('../../test_corpora/ghent');
  if (!root.existsSync()) {
    test('Ghent JPX indexed', skip: 'test_corpora/ghent not found', () {});
    return;
  }

  test('GWG170 JPEG2000 /Indexed DeviceCMYK decodes to its palette red', () {
    final pixels = _decodeJpxIndexed(
        '${root.path}/1-CMYK/GWG170_JPEG2000_compression_DeviceCMYK_X4.pdf');
    expect(pixels.width, 236);
    expect(pixels.height, 236);
    final (r, g, b) = _uniformOpaqueColor(pixels);
    // hival 0, palette CMYK [0 1 1 0] → red. The regression paints black.
    expect(r, greaterThan(200), reason: 'red channel; black would be ~0');
    expect(g, lessThan(120));
    expect(b, lessThan(120));
  });

  test('GWG172 JPEG2000 /Indexed ICCBasedRGB decodes to its palette green', () {
    final pixels = _decodeJpxIndexed(
        '${root.path}/3-ICC-CMS/GWG172_JPEG2000_compression_ICCBasedRGB_x4.pdf');
    expect(pixels.width, 236);
    expect(pixels.height, 236);
    final (r, g, b) = _uniformOpaqueColor(pixels);
    // hival 0, palette RGB [114 247 13] → output-managed green. The
    // regression paints black; the profile conversion gives approximately
    // RGB(85,175,59), so assert the hue rather than the unmanaged source byte.
    expect(g, greaterThan(150), reason: 'green channel; black would be ~0');
    expect(g - r, greaterThan(60));
    expect(g - b, greaterThan(80));
  });
}

/// Opens [path], finds its sole JPXDecode image XObject, and decodes it.
PdfDecodedPixels _decodeJpxIndexed(String path) {
  final cos = CosDocument.open(File(path).readAsBytesSync());
  for (final number in cos.objectNumbers) {
    final entry = cos.xrefEntry(number);
    final obj = cos.resolve(CosReference(number, entry?.generation ?? 0));
    if (obj is! CosStream) continue;
    final dict = obj.dictionary;
    if (cos.resolve(dict['Subtype']) != const CosName('Image')) continue;
    final filter = cos.resolve(dict['Filter']);
    final isJpx = filter == const CosName('JPXDecode') ||
        (filter is CosArray &&
            filter.items
                .any((f) => cos.resolve(f) == const CosName('JPXDecode')));
    if (!isJpx) continue;
    final pixels = decodePdfImagePixels(cos, obj);
    expect(pixels, isNotNull, reason: 'JPX /Indexed image failed to decode');
    return pixels!;
  }
  fail('no JPXDecode image found in $path');
}

/// Asserts every pixel is identical and opaque, returning that RGB. A uniform
/// square is exactly what a single-entry palette (hival 0) must produce.
(int, int, int) _uniformOpaqueColor(PdfDecodedPixels pixels) {
  final rgba = pixels.rgba;
  final r = rgba[0], g = rgba[1], b = rgba[2];
  for (var i = 0; i < rgba.length; i += 4) {
    expect(rgba[i], r);
    expect(rgba[i + 1], g);
    expect(rgba[i + 2], b);
    expect(rgba[i + 3], 255, reason: 'JPX image must be opaque');
  }
  return (r, g, b);
}
