import 'dart:io';
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

  CosStream flateImage(Map<String, CosObject> dict, List<int> data) => image(
      {...dict, 'Filter': const CosName('FlateDecode')}, zlib.encode(data));

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

  test('ICCBased 8-bit RGB decodes through the embedded profile', () {
    // The profile stream's /N picks the device family; the parsed AdobeRGB
    // profile is applied per pixel (littleCMS reference in icc_test:
    // AdobeRGB (128,64,200) -> sRGB (146,62,205)).
    final profile =
        CosStream(CosDictionary({'N': const CosInteger(3)}), adobeRgb1998Icc());
    final stream = image({
      'Width': const CosInteger(1),
      'Height': const CosInteger(1),
      'BitsPerComponent': const CosInteger(8),
      'ColorSpace': CosArray([const CosName('ICCBased'), profile]),
    }, [
      128,
      64,
      200,
    ]);

    final pixels = decodePdfImagePixels(cos, stream)!;
    expect(pixels.rgba[0], closeTo(146, 3));
    expect(pixels.rgba[1], closeTo(62, 3));
    expect(pixels.rgba[2], closeTo(205, 3));
    expect(pixels.rgba[3], 255);
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

  test('region-scaled DeviceRGB Flate decodes only the requested crop', () {
    final raw = <int>[];
    for (var y = 0; y < 4; y++) {
      for (var x = 0; x < 4; x++) {
        raw.addAll([x * 40, y * 50, 7]);
      }
    }
    final stream = flateImage({
      'Width': const CosInteger(4),
      'Height': const CosInteger(4),
      'BitsPerComponent': const CosInteger(8),
      'ColorSpace': const CosName('DeviceRGB'),
    }, raw);

    final pixels =
        decodePdfImagePixelsRegionScaled(cos, stream, 1, 1, 2, 2, 2, 2)!;
    expect(pixels.width, 2);
    expect(pixels.height, 2);
    expect(pixels.rgba, [
      40,
      50,
      7,
      255,
      80,
      50,
      7,
      255,
      40,
      100,
      7,
      255,
      80,
      100,
      7,
      255,
    ]);
  });

  test('region-scaled DeviceGray Flate preserves top-down source rows', () {
    final stream = flateImage({
      'Width': const CosInteger(3),
      'Height': const CosInteger(3),
      'BitsPerComponent': const CosInteger(8),
      'ColorSpace': const CosName('DeviceGray'),
    }, [
      10,
      11,
      12,
      20,
      21,
      22,
      30,
      31,
      32,
    ]);

    final pixels =
        decodePdfImagePixelsRegionScaled(cos, stream, 1, 0, 1, 3, 1, 3)!;
    expect(pixels.rgba, [
      11,
      11,
      11,
      255,
      21,
      21,
      21,
      255,
      31,
      31,
      31,
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

  test('scaled CCITT gray avoids native RGBA expansion', () {
    // 64x24 Group-4 image encoded independently by libtiff. The direct scaled
    // result must be identical to the historical full decode + area-average,
    // including /Decode inversion and raw-sample color-key transparency.
    const group4 = [
      200,
      25,
      156,
      93,
      148,
      12,
      216,
      49,
      178,
      139,
      251,
      40,
      71,
      143,
      254,
      72,
      95,
      101,
      107,
      236,
      173,
      61,
      148,
      31,
      178,
      136,
      29,
      148,
      141,
      148,
      124,
      127,
      32,
      215,
      101,
      102,
      202,
      189,
      130,
      136,
      240,
      1,
      0,
      16,
    ];
    final stream = image({
      'Width': const CosInteger(64),
      'Height': const CosInteger(24),
      'BitsPerComponent': const CosInteger(1),
      'ColorSpace': const CosName('DeviceGray'),
      'Filter': const CosName('CCITTFaxDecode'),
      'DecodeParms': CosDictionary({
        'K': const CosInteger(-1),
        'Columns': const CosInteger(64),
        'Rows': const CosInteger(24),
      }),
      'Decode': CosArray([
        const CosInteger(1),
        const CosInteger(0),
      ]),
      'Mask': CosArray([
        const CosInteger(1),
        const CosInteger(1),
      ]),
    }, group4);

    final full = decodePdfImagePixels(cos, stream)!;
    final expected = downsamplePdfDecodedPixels(full, 8, 3);
    final scaled = decodePdfImagePixelsScaled(cos, stream, 8, 3)!;

    expect(scaled.width, 8);
    expect(scaled.height, 3);
    expect(scaled.rgba, expected.rgba);
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

    // The base ignores the /SMask (alpha stays 255) - the caller bakes it in.
    final base = decodePdfImageBase(cos, stream)!;
    expect(base.opaque, isTrue);
    expect(base.rgba, [10, 20, 30, 255]);
  });

  // Separation and DeviceN samples reach RGB through a tint transform, which
  // the decoder resolves once per distinct sample tuple rather than once per
  // pixel. These pin that the shared answers stay per-pixel correct.
  group('tint transform', () {
    /// `{ dup 0.5 mul exch 0.25 mul 0.0 0.0 }`: one ink in, CMYK out, with
    /// different factors per output so a mixed-up tuple cannot pass by luck.
    CosStream separation(List<int> samples, {Map<String, CosObject> extra = const {}}) =>
        image({
          'Width': CosInteger(samples.length),
          'Height': const CosInteger(1),
          'BitsPerComponent': const CosInteger(8),
          'ColorSpace': CosArray([
            const CosName('Separation'),
            const CosName('Spot'),
            const CosName('DeviceCMYK'),
            CosStream(
                CosDictionary({
                  'FunctionType': const CosInteger(4),
                  'Domain': CosArray([const CosReal(0), const CosReal(1)]),
                  'Range': CosArray([
                    for (var i = 0; i < 4; i++) ...[
                      const CosReal(0),
                      const CosReal(1)
                    ]
                  ]),
                }),
                Uint8List.fromList(
                    '{ dup 0.5 mul exch 0.25 mul 0.0 0.0 }'.codeUnits)),
          ]),
          ...extra,
        }, samples);

    test('repeated samples decode the same as their first occurrence', () {
      // 0 and 255 repeat out of order, so a stale or mis-keyed answer shows up
      // as one pixel disagreeing with its twin.
      const samples = [0, 128, 255, 128, 0, 255, 64];
      final pixels = decodePdfImagePixels(cos, separation(samples))!;
      expect(pixels.width, samples.length);

      List<int> pixelAt(int i) => pixels.rgba.sublist(i * 4, i * 4 + 4);
      for (var i = 0; i < samples.length; i++) {
        final first = samples.indexOf(samples[i]);
        expect(pixelAt(i), pixelAt(first),
            reason: 'sample ${samples[i]} at $i differs from its first '
                'occurrence at $first');
      }
      // Distinct inks must not collapse onto one another.
      expect(pixelAt(0), isNot(pixelAt(1)));
      expect(pixelAt(1), isNot(pixelAt(2)));
    });

    test('every distinct sample maps through the tint transform', () {
      // All 256 inputs, each appearing twice: the answers must match the
      // transform evaluated directly, so sharing cannot drift from the maths.
      final samples = [for (var i = 0; i < 256; i++) i, for (var i = 0; i < 256; i++) i];
      final pixels = decodePdfImagePixels(cos, separation(samples))!;

      for (var i = 0; i < samples.length; i++) {
        final tint = samples[i] / 255;
        // The tint transform's CMYK, converted the way the decoder does.
        final expected = colorFromComponents(
            [tint * 0.5, tint * 0.25, 0.0, 0.0], 4);
        expect(pixels.rgba[i * 4], (expected.red * 255).round().clamp(0, 255),
            reason: 'red for sample ${samples[i]}');
        expect(pixels.rgba[i * 4 + 1],
            (expected.green * 255).round().clamp(0, 255),
            reason: 'green for sample ${samples[i]}');
        expect(pixels.rgba[i * 4 + 2],
            (expected.blue * 255).round().clamp(0, 255),
            reason: 'blue for sample ${samples[i]}');
        expect(pixels.rgba[i * 4 + 3], 255);
      }
    });

    test('color-key /Mask stays per-pixel when samples repeat', () {
      // Alpha depends on the raw sample, not the shared colour: the two 128s
      // must both key out while their neighbours stay opaque.
      final pixels = decodePdfImagePixels(
          cos,
          separation([0, 128, 255, 128], extra: {
            'Mask': CosArray([const CosInteger(128), const CosInteger(128)]),
          }))!;
      expect([for (var i = 0; i < 4; i++) pixels.rgba[i * 4 + 3]],
          [255, 0, 255, 0]);
    });

    test('/Decode inverts the ink before the tint transform', () {
      // /Decode [1 0] maps sample 0 to full ink: pixel 0 must equal what
      // sample 255 gives without /Decode.
      final plain = decodePdfImagePixels(cos, separation([0, 255]))!;
      final inverted = decodePdfImagePixels(
          cos,
          separation([0, 255], extra: {
            'Decode': CosArray([const CosReal(1), const CosReal(0)]),
          }))!;
      expect(inverted.rgba.sublist(0, 4), plain.rgba.sublist(4, 8));
      expect(inverted.rgba.sublist(4, 8), plain.rgba.sublist(0, 4));
    });

    test('DeviceN keys each colorant separately', () {
      // `{ pop dup 0.0 0.0 }` drops InkB and paints with InkA alone, so a key
      // that ignored InkA would make (0,255) and (255,0) agree, while one that
      // ignored InkB would (correctly) keep (0,255) and (0,0) together.
      final stream = image({
        'Width': const CosInteger(3),
        'Height': const CosInteger(1),
        'BitsPerComponent': const CosInteger(8),
        'ColorSpace': CosArray([
          const CosName('DeviceN'),
          CosArray([const CosName('InkA'), const CosName('InkB')]),
          const CosName('DeviceCMYK'),
          CosStream(
              CosDictionary({
                'FunctionType': const CosInteger(4),
                'Domain': CosArray([
                  const CosReal(0),
                  const CosReal(1),
                  const CosReal(0),
                  const CosReal(1)
                ]),
                'Range': CosArray([
                  for (var i = 0; i < 4; i++) ...[
                    const CosReal(0),
                    const CosReal(1)
                  ]
                ]),
              }),
              Uint8List.fromList('{ pop dup 0.0 0.0 }'.codeUnits)),
        ]),
      }, [
        0, 255, //
        0, 0, //
        255, 0,
      ]);

      final pixels = decodePdfImagePixels(cos, stream)!;
      List<int> pixelAt(int i) => pixels.rgba.sublist(i * 4, i * 4 + 4);
      expect(pixelAt(0), pixelAt(1)); // InkB is dropped by the transform
      expect(pixelAt(0), isNot(pixelAt(2))); // InkA drives the colour
    });
  });

  group('decodePdfImage façade', () {
    // A 4x1 Flate DeviceRGB image the region/scaled fast paths support.
    CosStream rgbStrip() => flateImage({
          'Width': const CosInteger(4),
          'Height': const CosInteger(1),
          'BitsPerComponent': const CosInteger(8),
          'ColorSpace': const CosName('DeviceRGB'),
        }, [
          10, 11, 12, //
          20, 21, 22, //
          30, 31, 32, //
          40, 41, 42,
        ]);

    test('no region or target decodes at native size, like decodePdfImagePixels',
        () {
      final stream = rgbStrip();
      final facade = decodePdfImage(cos, stream)!;
      final direct = decodePdfImagePixels(cos, stream)!;
      expect(facade.width, direct.width);
      expect(facade.height, direct.height);
      expect(facade.rgba, direct.rgba);
    });

    test('a region crops to the requested slice', () {
      final stream = rgbStrip();
      final slice =
          decodePdfImage(cos, stream, region: const PdfImageRegion(1, 0, 2, 1))!;
      expect(slice.width, 2);
      expect(slice.height, 1);
      // premultiplied but fully opaque, so RGB is unchanged: pixels 1 and 2.
      expect(slice.rgba, [20, 21, 22, 255, 30, 31, 32, 255]);
    });

    test('the fast region path and the full-decode fallback agree pixel-exactly',
        () {
      // The façade must return identical pixels whether the region fast path
      // handled the stream or it fell back to a full decode + crop. Adding a
      // Flate /SMask makes the region fast path bail (it only does
      // single-filter, mask-free streams) while the full decoder still copes -
      // so this compares the two façade paths for the same slice.
      const region = PdfImageRegion(1, 0, 2, 1);
      final plain = rgbStrip(); // fast region path
      final masked = flateImage({
        'Width': const CosInteger(4),
        'Height': const CosInteger(1),
        'BitsPerComponent': const CosInteger(8),
        'ColorSpace': const CosName('DeviceRGB'),
        'SMask': flateImage({
          'Width': const CosInteger(4),
          'Height': const CosInteger(1),
          'BitsPerComponent': const CosInteger(8),
          'ColorSpace': const CosName('DeviceGray'),
        }, [255, 255, 255, 255]), // fully opaque mask: pixels are unchanged
      }, [
        10, 11, 12, //
        20, 21, 22, //
        30, 31, 32, //
        40, 41, 42,
      ]);
      final fast = decodePdfImage(cos, plain, region: region)!;
      final fallback = decodePdfImage(cos, masked, region: region)!;
      expect(fallback.width, fast.width);
      expect(fallback.height, fast.height);
      expect(fallback.rgba, fast.rgba);
    });

    test('a smaller target downsamples to that size', () {
      final stream = rgbStrip();
      final scaled = decodePdfImage(cos, stream, targetWidth: 2, targetHeight: 1)!;
      expect(scaled.width, 2);
      expect(scaled.height, 1);
    });
  });

  group('cropDownsamplePdfDecodedPixels', () {
    test('crops an in-bounds rectangle', () {
      final full = PdfDecodedPixels(
        Uint8List.fromList([
          1, 1, 1, 255, 2, 2, 2, 255, //
          3, 3, 3, 255, 4, 4, 4, 255,
        ]),
        2,
        2,
      );
      final crop = cropDownsamplePdfDecodedPixels(full, 1, 0, 1, 2, 1, 2)!;
      expect(crop.width, 1);
      expect(crop.height, 2);
      expect(crop.rgba, [2, 2, 2, 255, 4, 4, 4, 255]);
    });

    test('returns null when the rectangle falls outside the image', () {
      final full = PdfDecodedPixels(Uint8List(16), 2, 2);
      expect(cropDownsamplePdfDecodedPixels(full, 1, 1, 2, 2, 2, 2), isNull);
    });
  });
}
