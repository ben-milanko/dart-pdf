import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

/// Direct coverage of the pure-Dart image decode that a render worker calls
/// (no `dart:ui`). The `dart:ui` glue is exercised separately by
/// dart_pdf_editor's image_decoder_test; here we pin the pixels the worker
/// would ship.
void main() {
  late CosDocument cos;
  setUp(() => cos = CosDocument.open(buildClassicPdf()));

  CosStream image(Map<String, CosObject> dict, List<int> data) =>
      CosStream(CosDictionary(dict), Uint8List.fromList(data));

  test('DeviceRGB 8-bit decodes opaque, straight through', () {
    final stream = image({
      'Width': const CosInteger(2),
      'Height': const CosInteger(1),
      'BitsPerComponent': const CosInteger(8),
      'ColorSpace': const CosName('DeviceRGB'),
    }, [
      10,
      20,
      30,
      40,
      50,
      60
    ]);

    final pixels = decodePdfImagePixels(cos, stream)!;
    expect(pixels.width, 2);
    expect(pixels.height, 1);
    expect(pixels.rgba, [10, 20, 30, 255, 40, 50, 60, 255]);
  });

  test('DeviceGray 8-bit replicates into RGB', () {
    final stream = image({
      'Width': const CosInteger(2),
      'Height': const CosInteger(1),
      'BitsPerComponent': const CosInteger(8),
      'ColorSpace': const CosName('DeviceGray'),
    }, [
      100,
      200
    ]);

    final pixels = decodePdfImagePixels(cos, stream)!;
    expect(pixels.rgba, [100, 100, 100, 255, 200, 200, 200, 255]);
  });

  test('/ImageMask stencil decodes to 0/255 alpha', () {
    final stream = image({
      'ImageMask': const CosBoolean(true),
      'Width': const CosInteger(2),
      'Height': const CosInteger(1),
      'BitsPerComponent': const CosInteger(1),
    }, [
      0x40
    ]); // bit 0 paints, bit 1 skips
    final pixels = decodePdfImagePixels(cos, stream)!;
    expect(pixels.rgba[3], 255); // painted
    expect(pixels.rgba[7], 0); // skipped
  });

  test('/SMask bakes into alpha and premultiplies', () {
    final smask = image({
      'Width': const CosInteger(2),
      'Height': const CosInteger(1),
      'BitsPerComponent': const CosInteger(8),
      'ColorSpace': const CosName('DeviceGray'),
    }, [
      128,
      0
    ]);
    final stream = image({
      'Width': const CosInteger(2),
      'Height': const CosInteger(1),
      'BitsPerComponent': const CosInteger(8),
      'ColorSpace': const CosName('DeviceRGB'),
      'SMask': smask,
    }, [
      255,
      255,
      255,
      255,
      255,
      255
    ]);

    final pixels = decodePdfImagePixels(cos, stream)!;
    // first pixel: white at alpha 128 → premultiplied 128 in each channel.
    expect(pixels.rgba.sublist(0, 4), [128, 128, 128, 128]);
    // second pixel: alpha 0 → fully transparent, channels premultiplied to 0.
    expect(pixels.rgba.sublist(4, 8), [0, 0, 0, 0]);
  });

  test('color-key /Mask turns matching samples transparent', () {
    final stream = image({
      'Width': const CosInteger(2),
      'Height': const CosInteger(1),
      'BitsPerComponent': const CosInteger(8),
      'ColorSpace': const CosName('DeviceRGB'),
      'Mask': CosArray([
        const CosInteger(0),
        const CosInteger(0),
        const CosInteger(0),
        const CosInteger(0),
        const CosInteger(0),
        const CosInteger(0),
      ]),
    }, [
      0,
      0,
      0,
      9,
      9,
      9
    ]);

    final pixels = decodePdfImagePixels(cos, stream)!;
    expect(pixels.rgba[3], 0); // (0,0,0) keyed out
    expect(pixels.rgba[7], 255); // (9,9,9) opaque
  });

  test('non-CMYK DCTDecode base declines to the platform codec', () {
    final stream = image({
      'Width': const CosInteger(8),
      'Height': const CosInteger(8),
      'BitsPerComponent': const CosInteger(8),
      'ColorSpace': const CosName('DeviceRGB'),
      'Filter': const CosName('DCTDecode'),
    }, List.filled(16, 0));
    expect(decodePdfImagePixels(cos, stream), isNull);
    expect(decodePdfImageBase(cos, stream), isNull);
  });

  test('scaled DeviceRGB Flate decodes directly to target size', () {
    final stream = image({
      'Width': const CosInteger(4),
      'Height': const CosInteger(4),
      'BitsPerComponent': const CosInteger(8),
      'ColorSpace': const CosName('DeviceRGB'),
      'Filter': const CosName('FlateDecode'),
    }, [
      120,
      156,
      251,
      207,
      192,
      240,
      159,
      1,
      140,
      255,
      67,
      8,
      6,
      100,
      10,
      2,
      144,
      217,
      0,
      210,
      107,
      23,
      233,
    ]);

    final pixels = decodePdfImagePixelsScaled(cos, stream, 2, 2)!;
    expect(pixels.width, 2);
    expect(pixels.height, 2);
    expect(pixels.rgba, [
      255,
      0,
      0,
      255,
      0,
      255,
      0,
      255,
      0,
      0,
      255,
      255,
      255,
      255,
      255,
      255,
    ]);
  });

  test('scaled ICCBased Flate falls back to full color conversion', () {
    final stream = image({
      'Width': const CosInteger(4),
      'Height': const CosInteger(4),
      'BitsPerComponent': const CosInteger(8),
      'ColorSpace': CosArray([
        const CosName('ICCBased'),
        image({'N': const CosInteger(3)}, const []),
      ]),
      'Filter': const CosName('FlateDecode'),
    }, [
      120,
      156,
      251,
      207,
      192,
      240,
      159,
      1,
      140,
      255,
      67,
      8,
      6,
      100,
      10,
      2,
      144,
      217,
      0,
      210,
      107,
      23,
      233,
    ]);

    expect(decodePdfImagePixelsScaled(cos, stream, 2, 2), isNull);
  });

  test('scaled ImageMask Flate decodes premultiplied alpha', () {
    final stream = image({
      'ImageMask': const CosBoolean(true),
      'Width': const CosInteger(4),
      'Height': const CosInteger(1),
      'BitsPerComponent': const CosInteger(1),
      'Filter': const CosName('FlateDecode'),
    }, [
      120,
      156,
      11,
      0,
      0,
      0,
      81,
      0,
      81
    ]); // bits: 0,1,0,1

    final pixels = decodePdfImagePixelsScaled(cos, stream, 2, 1)!;
    expect(pixels.width, 2);
    expect(pixels.height, 1);
    expect(pixels.rgba, [
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
    ]);
  });

  test('scaled Indexed Flate with stencil mask avoids full RGBA expansion', () {
    final mask = image({
      'ImageMask': const CosBoolean(true),
      'Width': const CosInteger(4),
      'Height': const CosInteger(1),
      'BitsPerComponent': const CosInteger(1),
      'Filter': const CosName('FlateDecode'),
    }, [
      120,
      156,
      219,
      0,
      0,
      0,
      177,
      0,
      177
    ]); // bits: 1,0,1,1; default stencil mask makes 1 transparent
    final stream = image({
      'Width': const CosInteger(4),
      'Height': const CosInteger(1),
      'BitsPerComponent': const CosInteger(1),
      'ColorSpace': CosArray([
        const CosName('Indexed'),
        const CosName('DeviceRGB'),
        const CosInteger(1),
        CosString(Uint8List.fromList([0, 0, 0, 255, 0, 0])),
      ]),
      'Filter': const CosName('FlateDecode'),
      'Mask': mask,
    }, [
      120,
      156,
      11,
      0,
      0,
      0,
      81,
      0,
      81
    ]); // indices: 0,1,0,1

    final pixels = decodePdfImagePixelsScaled(cos, stream, 2, 1)!;
    expect(pixels.width, 2);
    expect(pixels.height, 1);
    expect(pixels.rgba, [
      255,
      0,
      0,
      255,
      0,
      0,
      0,
      0,
    ]);
  });

  test('decodePdfImageBase returns straight, unmasked, opaque RGBA', () {
    final smask = image({
      'Width': const CosInteger(1),
      'Height': const CosInteger(1),
      'BitsPerComponent': const CosInteger(8),
      'ColorSpace': const CosName('DeviceGray'),
    }, [
      0
    ]);
    final stream = image({
      'Width': const CosInteger(1),
      'Height': const CosInteger(1),
      'BitsPerComponent': const CosInteger(8),
      'ColorSpace': const CosName('DeviceRGB'),
      'SMask': smask,
    }, [
      10,
      20,
      30
    ]);

    // The base ignores the /SMask (alpha stays 255) — the caller bakes it in.
    final base = decodePdfImageBase(cos, stream)!;
    expect(base.opaque, isTrue);
    expect(base.rgba, [10, 20, 30, 255]);
  });
}
