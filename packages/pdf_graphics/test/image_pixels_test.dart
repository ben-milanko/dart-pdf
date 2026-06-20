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
    }, [10, 20, 30, 40, 50, 60]);

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
    }, [100, 200]);

    final pixels = decodePdfImagePixels(cos, stream)!;
    expect(pixels.rgba, [100, 100, 100, 255, 200, 200, 200, 255]);
  });

  test('/ImageMask stencil decodes to 0/255 alpha', () {
    final stream = image({
      'ImageMask': const CosBoolean(true),
      'Width': const CosInteger(2),
      'Height': const CosInteger(1),
      'BitsPerComponent': const CosInteger(1),
    }, [0x40]); // bit 0 paints, bit 1 skips
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
    }, [128, 0]);
    final stream = image({
      'Width': const CosInteger(2),
      'Height': const CosInteger(1),
      'BitsPerComponent': const CosInteger(8),
      'ColorSpace': const CosName('DeviceRGB'),
      'SMask': smask,
    }, [255, 255, 255, 255, 255, 255]);

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
    }, [0, 0, 0, 9, 9, 9]);

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

  test('decodePdfImageBase returns straight, unmasked, opaque RGBA', () {
    final smask = image({
      'Width': const CosInteger(1),
      'Height': const CosInteger(1),
      'BitsPerComponent': const CosInteger(8),
      'ColorSpace': const CosName('DeviceGray'),
    }, [0]);
    final stream = image({
      'Width': const CosInteger(1),
      'Height': const CosInteger(1),
      'BitsPerComponent': const CosInteger(8),
      'ColorSpace': const CosName('DeviceRGB'),
      'SMask': smask,
    }, [10, 20, 30]);

    // The base ignores the /SMask (alpha stays 255) — the caller bakes it in.
    final base = decodePdfImageBase(cos, stream)!;
    expect(base.opaque, isTrue);
    expect(base.rgba, [10, 20, 30, 255]);
  });
}
