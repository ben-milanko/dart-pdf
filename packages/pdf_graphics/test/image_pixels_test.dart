import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
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
  tearDown(() {
    pdfDctCmykDecoder = null;
    pdfDctGrayDecoder = null;
    pdfDctRgbaDecoder = null;
    pdfDeviceCmykToRgba = null;
    pdfComponentBoxDownsampler = null;
  });

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

  test('a JBIG2 stencil /Mask decodes through the image codec', () {
    // The MRC shape every scanner emits: a colour layer stencilled by a
    // JBIG2-coded text mask. JBIG2 is an image codec, not a stream filter, so
    // the mask cannot come back through the plain filter chain - and a mask
    // that fails to decode leaves the colour layer fully opaque, which on a
    // scanned page covers the whole sheet.
    const size = 16;
    final symbol = Jbig2Bitmap(4, 4)..fillRect(0, 0, 4, 4);
    final globals = encodeJbig2Globals([symbol]);
    final page = encodeJbig2TextPage(
      width: size,
      height: size,
      symbols: [symbol],
      placements: const [Jbig2Placement(0, 2, 2)],
    );
    Jbig2Decoder.debugResetGlobalsCache();

    final mask = image({
      'ImageMask': const CosBoolean(true),
      'Width': const CosInteger(size),
      'Height': const CosInteger(size),
      'BitsPerComponent': const CosInteger(1),
      'Filter': const CosName('JBIG2Decode'),
      'DecodeParms': CosDictionary({
        'JBIG2Globals': CosStream(CosDictionary({}), globals),
      }),
    }, page);
    final stream = image({
      'Width': const CosInteger(size),
      'Height': const CosInteger(size),
      'BitsPerComponent': const CosInteger(8),
      'ColorSpace': const CosName('DeviceRGB'),
      'Mask': mask,
    }, List.filled(size * size * 3, 255));

    final pixels = decodePdfImagePixels(cos, stream)!;
    expect(pixels.width, size);
    expect(pixels.height, size);
    int alphaAt(int x, int y) => pixels.rgba[(y * size + x) * 4 + 3];
    // The symbol's ink is black - a 0 sample, which /Mask paints - and the
    // rest of the page is white, which it masks out.
    expect(alphaAt(2, 2), 255);
    expect(alphaAt(5, 5), 255);
    expect(alphaAt(1, 2), 0);
    expect(alphaAt(6, 5), 0);
    expect(alphaAt(0, 0), 0);
  });

  test('a JPX /SMask decodes through the image codec', () {
    const size = 16;
    final smask = image({
      'Width': const CosInteger(size),
      'Height': const CosInteger(size),
      'BitsPerComponent': const CosInteger(8),
      'ColorSpace': const CosName('DeviceGray'),
      'Filter': const CosName('JPXDecode'),
    }, grayJpxCodestream);
    final stream = image({
      'Width': const CosInteger(size),
      'Height': const CosInteger(size),
      'BitsPerComponent': const CosInteger(8),
      'ColorSpace': const CosName('DeviceRGB'),
      'SMask': smask,
    }, List.filled(size * size * 3, 255));

    final pixels = decodePdfImagePixels(cos, stream)!;
    expect(
      [for (var i = 0; i < size * size; i++) pixels.rgba[i * 4 + 3]],
      grayJpxExpectedSamples,
    );
    // White under that alpha premultiplies to the alpha value itself.
    expect(
      [for (var i = 0; i < size * size; i++) pixels.rgba[i * 4]],
      grayJpxExpectedSamples,
    );
  });

  test('a colour JPX /SMask carries no alpha plane to read', () {
    // Three components are an image, not a mask: better to leave the base
    // opaque than to invent an alpha channel out of one of them.
    final smask = image({
      'Width': const CosInteger(2),
      'Height': const CosInteger(2),
      'BitsPerComponent': const CosInteger(8),
      'ColorSpace': const CosName('DeviceRGB'),
      'Filter': const CosName('JPXDecode'),
    }, const [0, 0]); // not a codestream at all: the decoder bails
    expect(pdfImageSoftMask(cos, CosDictionary({'SMask': smask})), isNull);
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

  test('a DCT /SMask decodes and composites on the portable path', () {
    const width = 16;
    final gray = img.Image(width: width, height: 1);
    for (final pixel in gray) {
      final value = pixel.x < width ~/ 2 ? 255 : 0;
      pixel
        ..r = value
        ..g = value
        ..b = value;
    }
    final smask = image({
      'Width': const CosInteger(width),
      'Height': const CosInteger(1),
      'BitsPerComponent': const CosInteger(8),
      'ColorSpace': const CosName('DeviceGray'),
      'Filter': const CosName('DCTDecode'),
    }, img.encodeJpg(gray, quality: 100));
    final stream = image({
      'Width': const CosInteger(width),
      'Height': const CosInteger(1),
      'BitsPerComponent': const CosInteger(8),
      'ColorSpace': const CosName('DeviceRGB'),
      'SMask': smask,
    }, [
      for (var i = 0; i < width; i++) ...[255, 0, 0],
    ]);

    final pixels = decodePdfImagePixels(cos, stream)!;
    expect(pixels.rgba[1 * 4 + 3], greaterThan(240));
    expect(pixels.rgba[14 * 4 + 3], lessThan(15));
    expect(pixels.rgba.sublist(14 * 4, 14 * 4 + 3), [0, 0, 0],
        reason: 'the transparent red base must be premultiplied');
  });

  test('a targeted DCT /SMask uses the grayscale accelerator', () {
    var calls = 0;
    pdfDctGrayDecoder = (
      bytes, {
      targetWidth,
      targetHeight,
    }) {
      calls++;
      expect(bytes, [1, 2, 3]);
      expect((targetWidth, targetHeight), (1, 1));
      return PdfDctGraySamples(Uint8List.fromList([255, 0]), 2, 1);
    };
    final smask = image({
      'Width': const CosInteger(2),
      'Height': const CosInteger(1),
      'BitsPerComponent': const CosInteger(8),
      'ColorSpace': const CosName('DeviceGray'),
      'Filter': const CosName('DCTDecode'),
    }, [
      1,
      2,
      3,
    ]);
    final stream = image({
      'Width': const CosInteger(2),
      'Height': const CosInteger(1),
      'BitsPerComponent': const CosInteger(8),
      'ColorSpace': const CosName('DeviceCMYK'),
      'SMask': smask,
    }, [
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
    ]);

    final pixels = decodePdfImage(
      cos,
      stream,
      targetWidth: 1,
      targetHeight: 1,
    )!;

    expect(calls, 1);
    expect((pixels.width, pixels.height), (1, 1));
    expect(pixels.rgba, [127, 127, 127, 127]);
  });

  test('/SMask /Matte un-preblends the base against the matte colour', () {
    // A white pixel preblended over a red matte at coverage 0.5 stores
    // c' = m + a·(c − m) = (255, 128, 128). With /Matte [1 0 0] the decoder
    // must recover the true white before premultiplying, so the result is a
    // neutral grey (128,128,128,128) - not the reddish (128,64,64,128) a
    // naïve decode would give.
    final smask = image({
      'Width': const CosInteger(1),
      'Height': const CosInteger(1),
      'BitsPerComponent': const CosInteger(8),
      'ColorSpace': const CosName('DeviceGray'),
      'Matte': CosArray([
        const CosInteger(1),
        const CosInteger(0),
        const CosInteger(0),
      ]),
    }, [
      128
    ]);
    final stream = image({
      'Width': const CosInteger(1),
      'Height': const CosInteger(1),
      'BitsPerComponent': const CosInteger(8),
      'ColorSpace': const CosName('DeviceRGB'),
      'SMask': smask,
    }, [
      255,
      128,
      128
    ]);

    final pixels = decodePdfImagePixels(cos, stream)!;
    expect(pixels.rgba.sublist(0, 4), [128, 128, 128, 128]);
  });

  test('an interleaved platform mask consumes its channel without a copy', () {
    final rgba = Uint8List.fromList([
      255,
      7,
      8,
      9,
      64,
      10,
      11,
      12,
    ]);
    final base = Uint8List.fromList([
      200,
      100,
      50,
      255,
      200,
      100,
      50,
      255,
    ]);

    final result = pdfApplyImageAlpha(
      base,
      2,
      1,
      PdfImageSoftMask(rgba, 2, 1, sampleStride: 4),
    );

    expect(result.$1, [200, 100, 50, 255, 200, 100, 50, 64]);
    expect(identical(rgba, result.$1), isFalse,
        reason: 'the base is mutated, while the mask remains only a view');
  });

  test('mask application can fuse codec premultiplication', () {
    final base = Uint8List.fromList([
      200,
      100,
      50,
      255,
      20,
      40,
      80,
      255,
    ]);

    final result = pdfApplyImageAlpha(
      base,
      2,
      1,
      PdfImageSoftMask(Uint8List.fromList([128, 0]), 2, 1),
      premultiply: true,
    );

    expect(result.$1, [100, 50, 25, 128, 0, 0, 0, 0]);
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

  group('CMYK JPEG polarity (#370)', () {
    // Two 16x8 baseline JPEGs, hand-built with constant 8x8 blocks and custom
    // Huffman tables so the stored samples are exact by construction. The
    // YCCK file carries an Adobe APP14 marker with transform=2 and stores
    // Y'CbCr of the inverted CMY (K stored as ink); the CMYK file carries
    // transform=0 and stores plain ink values. Both paint the same content:
    // left half cyan ink (255,0,0,0), right half magenta + half K
    // (0,255,0,128) in PDF ink polarity.
    //
    // Ground truth: pdf.js renders of each file embedded as a DeviceCMYK
    // image XObject (its _convertYcckToCmyk inverts the converted CMY and
    // leaves K unchanged; the plain CMYK path is untouched).
    const ycckJpeg =
        '/9j/7gAOQWRvYmUAZAAAAAAC/9sAQwAQCwoQGCgzPQwMDhMaOjw3Dg0QGCg5RTgOERYdM1dQPhIWJThEbWdNGCM3QFFocVwxQE5XZ3l4ZUhcX2JwZGdj/9sAQwEREhgvY2NjYxIVGkJjY2NjGBo4Y2NjY2MvQmNjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2Nj/8AAFAgACAAQBAERAAIRAQMRAQQRAP/EABYAAQEBAAAAAAAAAAAAAAAAAAUGB//EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAOBAEAAgADAAQAAD8AaKINoCLS7eGfv//Z';
    const cmykJpeg =
        '/9j/7gAOQWRvYmUAZAAAAAAA/9sAQwAQCwoQGCgzPQwMDhMaOjw3Dg0QGCg5RTgOERYdM1dQPhIWJThEbWdNGCM3QFFocVwxQE5XZ3l4ZUhcX2JwZGdj/9sAQwEREhgvY2NjYxIVGkJjY2NjGBo4Y2NjY2MvQmNjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2Nj/8AAFAgACAAQBAERAAIRAQMRAQQRAP/EABcAAQEBAQAAAAAAAAAAAAAAAAAGBwj/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oADgQBAAIAAwAEAAA/ANAQaDZ+5/bwNAf/2Q==';

    CosStream cmykDct(String b64) => image({
          'Width': const CosInteger(16),
          'Height': const CosInteger(8),
          'BitsPerComponent': const CosInteger(8),
          'ColorSpace': const CosName('DeviceCMYK'),
          'Filter': const CosName('DCTDecode'),
        }, base64Decode(b64));

    void expectPixel(Uint8List rgba, int x, List<int> expected) {
      final i = (4 * 16 + x) * 4; // middle row
      for (var ch = 0; ch < 3; ch++) {
        expect((rgba[i + ch] - expected[ch]).abs(), lessThanOrEqualTo(3),
            reason: 'x=$x channel=$ch');
      }
      expect(rgba[i + 3], 255);
    }

    test('YCCK (Adobe transform=2) inverts CMY and keeps K', () {
      final pixels = decodePdfImagePixels(cos, cmykDct(ycckJpeg))!;
      expect(pixels.width, 16);
      expectPixel(pixels.rgba, 2, [0, 7, 39]); // cyan + full K
      expectPixel(pixels.rgba, 12, [140, 17, 11]); // M+Y + half K
    });

    test('plain CMYK (Adobe transform=0) passes samples through', () {
      final pixels = decodePdfImagePixels(cos, cmykDct(cmykJpeg))!;
      expect(pixels.width, 16);
      expectPixel(pixels.rgba, 2, [0, 184, 241]); // pure cyan
      expectPixel(pixels.rgba, 12, [142, 15, 82]); // magenta + half K
    });

    test('target decode fuses component reduction without changing color', () {
      final pixels = decodePdfImageBase(
        cos,
        cmykDct(cmykJpeg),
        targetWidth: 1,
        targetHeight: 1,
      )!;
      final expected = PdfColor.cmyk(127 / 255, 127 / 255, 0, 64 / 255);

      expect((pixels.width, pixels.height), (1, 1));
      expect(pixels.rgba[0], closeTo((expected.red * 255).round(), 3));
      expect(pixels.rgba[1], closeTo((expected.green * 255).round(), 3));
      expect(pixels.rgba[2], closeTo((expected.blue * 255).round(), 3));
      expect(pixels.rgba[3], 255);
    });

    test('accelerated CMYK samples retain the common PDF colour pipeline', () {
      var calls = 0;
      pdfDctCmykDecoder = (
        bytes, {
        targetWidth,
        targetHeight,
      }) {
        calls++;
        expect(bytes, base64Decode(cmykJpeg));
        expect((targetWidth, targetHeight), (1, 1));
        final samples = Uint8List(16 * 8 * 4);
        for (var y = 0; y < 8; y++) {
          for (var x = 0; x < 16; x++) {
            final i = (y * 16 + x) * 4;
            if (x < 8) {
              samples[i] = 255;
            } else {
              samples[i + 1] = 255;
              samples[i + 3] = 128;
            }
          }
        }
        return PdfDctCmykSamples(samples, 16, 8);
      };

      final pixels = decodePdfImageBase(
        cos,
        cmykDct(cmykJpeg),
        targetWidth: 1,
        targetHeight: 1,
      )!;
      final expected = PdfColor.cmyk(127 / 255, 127 / 255, 0, 64 / 255);

      expect(calls, 1);
      expect((pixels.width, pixels.height), (1, 1));
      expect(pixels.rgba[0], closeTo((expected.red * 255).round(), 3));
      expect(pixels.rgba[1], closeTo((expected.green * 255).round(), 3));
      expect(pixels.rgba[2], closeTo((expected.blue * 255).round(), 3));
      expect(pixels.rgba[3], 255);
    });

    test('accelerator failures fall back to the portable decoder', () {
      pdfDctCmykDecoder = (
        _, {
        targetWidth,
        targetHeight,
      }) =>
          throw StateError('codec unavailable');

      final pixels = decodePdfImagePixels(cos, cmykDct(ycckJpeg))!;
      expectPixel(pixels.rgba, 2, [0, 7, 39]);
      expectPixel(pixels.rgba, 12, [140, 17, 11]);
    });

    test('bulk DeviceCMYK conversion accepts only the image sample span', () {
      final expected = Uint8List.fromList([
        1,
        2,
        3,
        255,
        4,
        5,
        6,
        255,
      ]);
      var calls = 0;
      pdfDeviceCmykToRgba = (samples) {
        calls++;
        expect(samples, [0, 0, 0, 0, 255, 0, 0, 0]);
        return expected;
      };
      final stream = image({
        'Width': const CosInteger(2),
        'Height': const CosInteger(1),
        'BitsPerComponent': const CosInteger(8),
        'ColorSpace': const CosName('DeviceCMYK'),
      }, [
        0,
        0,
        0,
        0,
        255,
        0,
        0,
        0,
        99, // tolerated trailing stream data must not reach the accelerator
      ]);

      final pixels = decodePdfImagePixels(cos, stream)!;
      expect(calls, 1);
      expect(pixels.rgba, expected);
    });

    test('bulk DeviceCMYK conversion receives samples after /Decode', () {
      var calls = 0;
      pdfDeviceCmykToRgba = (samples) {
        calls++;
        expect(samples, [254, 253, 252, 251]);
        return Uint8List.fromList([7, 8, 9, 255]);
      };
      final stream = image({
        'Width': const CosInteger(1),
        'Height': const CosInteger(1),
        'BitsPerComponent': const CosInteger(8),
        'ColorSpace': const CosName('DeviceCMYK'),
        'Decode': CosArray([
          const CosInteger(1),
          const CosInteger(0),
          const CosInteger(1),
          const CosInteger(0),
          const CosInteger(1),
          const CosInteger(0),
          const CosInteger(1),
          const CosInteger(0),
        ]),
      }, [
        1,
        2,
        3,
        4
      ]);

      final pixels = decodePdfImagePixels(cos, stream)!;
      expect(calls, 1);
      expect(pixels.rgba, [7, 8, 9, 255]);
    });

    test('targeted masked CMYK decode keeps the target through both halves',
        () {
      var calls = 0;
      pdfDctCmykDecoder = (
        _, {
        targetWidth,
        targetHeight,
      }) {
        calls++;
        expect((targetWidth, targetHeight), (1, 1));
        final samples = Uint8List(16 * 8 * 4);
        for (var i = 0; i < 16 * 8; i++) {
          samples[i * 4] = i < 64 ? 255 : 0;
        }
        return PdfDctCmykSamples(samples, 16, 8);
      };
      final mask = flateImage({
        'Width': const CosInteger(16),
        'Height': const CosInteger(8),
        'BitsPerComponent': const CosInteger(8),
        'ColorSpace': const CosName('DeviceGray'),
      }, [
        ...List.filled(64, 255),
        ...List.filled(64, 0),
      ]);
      final stream = image({
        'Width': const CosInteger(16),
        'Height': const CosInteger(8),
        'BitsPerComponent': const CosInteger(8),
        'ColorSpace': const CosName('DeviceCMYK'),
        'Filter': const CosName('DCTDecode'),
        'SMask': mask,
      }, base64Decode(cmykJpeg));

      final pixels = decodePdfImage(
        cos,
        stream,
        targetWidth: 1,
        targetHeight: 1,
      )!;

      expect(calls, 1);
      expect((pixels.width, pixels.height), (1, 1));
      expect(pixels.rgba[3], 127);
    });

    test('component box accelerator handles the base and Flate soft mask', () {
      pdfDctCmykDecoder = (
        _, {
        targetWidth,
        targetHeight,
      }) {
        final samples = Uint8List(16 * 8 * 4);
        return PdfDctCmykSamples(samples, 16, 8);
      };
      final calls = <int>[];
      pdfComponentBoxDownsampler = (
        samples,
        width,
        height,
        components,
        targetWidth,
        targetHeight,
      ) {
        calls.add(components);
        expect((width, height), (16, 8));
        expect((targetWidth, targetHeight), (1, 1));
        return components == 4
            ? Uint8List.fromList([0, 0, 0, 0])
            : Uint8List.fromList([128]);
      };
      final mask = flateImage({
        'Width': const CosInteger(16),
        'Height': const CosInteger(8),
        'BitsPerComponent': const CosInteger(8),
        'ColorSpace': const CosName('DeviceGray'),
      }, List.filled(16 * 8, 128));
      final stream = image({
        'Width': const CosInteger(16),
        'Height': const CosInteger(8),
        'BitsPerComponent': const CosInteger(8),
        'ColorSpace': const CosName('DeviceCMYK'),
        'Filter': const CosName('DCTDecode'),
        'SMask': mask,
      }, base64Decode(cmykJpeg));

      final pixels = decodePdfImage(
        cos,
        stream,
        targetWidth: 1,
        targetHeight: 1,
      )!;

      expect(calls, [4, 1]);
      expect(pixels.rgba, [128, 128, 128, 128]);
    });
  });

  test('the CMYK colour memo survives eviction and collision', () {
    // The decode path memoizes sample-tuple → sRGB (issue #451), which is only
    // sound if a hit is always the colour that tuple really converts to. The
    // danger is the two ways a fixed-size direct-mapped table can lie: an
    // eviction that leaves a stale colour behind, and two different tuples
    // hashing to one slot.
    //
    // So make the table thrash on purpose. 256x256 = 65536 pixels, every one a
    // distinct CMYK tuple, against a table an order of magnitude smaller: the
    // slot for any given tuple is overwritten many times over. Then check every
    // pixel against the conversion computed independently. A table that ever
    // returned a neighbour's colour cannot pass this.
    const size = 256;
    final samples = Uint8List(size * size * 4);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final i = (y * size + x) * 4;
        samples[i] = x;
        samples[i + 1] = y;
        samples[i + 2] = (x * 7 + y * 13) & 0xff;
        samples[i + 3] = (x ^ y) & 0xff;
      }
    }

    final stream = flateImage({
      'Width': const CosInteger(size),
      'Height': const CosInteger(size),
      'BitsPerComponent': const CosInteger(8),
      'ColorSpace': const CosName('DeviceCMYK'),
    }, samples);

    final pixels = decodePdfImagePixels(cos, stream)!;
    expect(pixels.width, size);
    expect(pixels.height, size);

    var mismatches = 0;
    for (var p = 0; p < size * size; p++) {
      final s = p * 4;
      final expected = PdfColor.cmyk(samples[s] / 255, samples[s + 1] / 255,
          samples[s + 2] / 255, samples[s + 3] / 255);
      if (pixels.rgba[s] != (expected.red * 255).round() ||
          pixels.rgba[s + 1] != (expected.green * 255).round() ||
          pixels.rgba[s + 2] != (expected.blue * 255).round()) {
        mismatches++;
      }
    }
    expect(mismatches, 0,
        reason: 'the memo handed back a colour belonging to another tuple');
  });

  test('an ICC-managed CMYK image converts through the memo unchanged', () {
    // The ICCBased CMYK branch is the one #451 measured at 0.85 us/px, and the
    // one this change touches most: it now feeds a reused Float64List to the
    // profile and reads its colours back through the memo. Both are chances to
    // leak state between pixels, so decode an image whose every pixel has an
    // independently known answer.
    final profile = IccProfile.parse(genericCmykIcc())!;
    const size = 64; // 4096 px: enough to exercise a real table
    final samples = Uint8List(size * size * 4);
    for (var p = 0; p < size * size; p++) {
      final s = p * 4;
      samples[s] = (p * 37) & 0xff;
      samples[s + 1] = (p * 11) & 0xff;
      samples[s + 2] = (p * 5) & 0xff;
      samples[s + 3] = (p ~/ size) & 0xff;
    }

    final stream = flateImage({
      'Width': const CosInteger(size),
      'Height': const CosInteger(size),
      'BitsPerComponent': const CosInteger(8),
      'ColorSpace': CosArray([
        const CosName('ICCBased'),
        CosStream(CosDictionary({'N': const CosInteger(4)}), genericCmykIcc()),
      ]),
    }, samples);

    final pixels = decodePdfImagePixels(cos, stream)!;

    var mismatches = 0;
    for (var p = 0; p < size * size; p++) {
      final s = p * 4;
      final expected = profile.toSrgb([
        samples[s] / 255,
        samples[s + 1] / 255,
        samples[s + 2] / 255,
        samples[s + 3] / 255,
      ]);
      if (pixels.rgba[s] != (expected.red * 255).round() ||
          pixels.rgba[s + 1] != (expected.green * 255).round() ||
          pixels.rgba[s + 2] != (expected.blue * 255).round()) {
        mismatches++;
      }
    }
    expect(mismatches, 0,
        reason: 'the ICC CMYK path disagreed with the profile itself');
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

  test('scaled unfiltered DeviceGray samples use the direct target path', () {
    final stream = image({
      'Width': const CosInteger(4),
      'Height': const CosInteger(4),
      'BitsPerComponent': const CosInteger(8),
      'ColorSpace': const CosName('DeviceGray'),
    }, [
      0,
      0,
      64,
      64,
      0,
      0,
      64,
      64,
      128,
      128,
      255,
      255,
      128,
      128,
      255,
      255,
    ]);

    final pixels = decodePdfImagePixelsScaled(
      cos,
      stream,
      2,
      2,
      samplesAreDecoded: true,
    )!;
    expect(pixels.width, 2);
    expect(pixels.height, 2);
    expect(pixels.rgba, [
      0,
      0,
      0,
      255,
      64,
      64,
      64,
      255,
      128,
      128,
      128,
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

    final decodedMask = image({
      'ImageMask': const CosBoolean(true),
      'Width': const CosInteger(4),
      'Height': const CosInteger(1),
      'BitsPerComponent': const CosInteger(1),
    }, [
      0xb0
    ]);
    final decodedStream = image({
      'Width': const CosInteger(4),
      'Height': const CosInteger(1),
      'BitsPerComponent': const CosInteger(1),
      'ColorSpace': CosArray([
        const CosName('Indexed'),
        const CosName('DeviceRGB'),
        const CosInteger(1),
        CosString(Uint8List.fromList([0, 0, 0, 255, 0, 0])),
      ]),
      'Mask': decodedMask,
    }, [
      0x50
    ]);
    final predecoded = decodePdfImagePixelsScaled(
      cos,
      decodedStream,
      2,
      1,
      samplesAreDecoded: true,
    )!;
    expect(predecoded.rgba, pixels.rgba);
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
    CosStream separation(List<int> samples,
            {Map<String, CosObject> extra = const {}}) =>
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

    test('target-sized Separation base converts only reduced samples', () {
      final full = separation([0, 0, 255, 255]);
      final target = decodePdfImageBase(
        cos,
        full,
        targetWidth: 2,
        targetHeight: 1,
      )!;
      final expected = decodePdfImageBase(cos, separation([0, 255]))!;

      expect((target.width, target.height), (2, 1));
      expect(target.rgba, expected.rgba,
          reason: 'uniform source cells must retain their tint colours');
    });

    test('targeted nonlinear ink decode matches full RGBA box filtering', () {
      final stream = separation([0, 255]);
      final full = decodePdfImagePixels(cos, stream)!;
      final expected = downsamplePdfDecodedPixels(full, 1, 1);
      final targeted = decodePdfImage(
        cos,
        stream,
        targetWidth: 1,
        targetHeight: 1,
      )!;

      expect(targeted.rgba, expected.rgba,
          reason: 'a tint transform is nonlinear, so component samples must '
              'be converted before they are averaged');
    });

    test('targeted DeviceCMYK decode matches full RGBA box filtering', () {
      final stream = flateImage({
        'Width': const CosInteger(2),
        'Height': const CosInteger(1),
        'BitsPerComponent': const CosInteger(8),
        'ColorSpace': const CosName('DeviceCMYK'),
      }, [
        0,
        0,
        0,
        0,
        255,
        255,
        255,
        255,
      ]);
      final full = decodePdfImagePixels(cos, stream)!;
      final expected = downsamplePdfDecodedPixels(full, 1, 1);
      final targeted = decodePdfImage(
        cos,
        stream,
        targetWidth: 1,
        targetHeight: 1,
      )!;

      expect(targeted.rgba, expected.rgba,
          reason: 'the DeviceCMYK polynomial must run before box filtering');
    });

    test('every distinct sample maps through the tint transform', () {
      // All 256 inputs, each appearing twice: the answers must match the
      // transform evaluated directly, so sharing cannot drift from the maths.
      final samples = [
        for (var i = 0; i < 256; i++) i,
        for (var i = 0; i < 256; i++) i
      ];
      final pixels = decodePdfImagePixels(cos, separation(samples))!;

      for (var i = 0; i < samples.length; i++) {
        final tint = samples[i] / 255;
        // The tint transform's CMYK, converted the way the decoder does.
        final expected =
            colorFromComponents([tint * 0.5, tint * 0.25, 0.0, 0.0], 4);
        expect(pixels.rgba[i * 4], (expected.red * 255).round().clamp(0, 255),
            reason: 'red for sample ${samples[i]}');
        expect(pixels.rgba[i * 4 + 1],
            (expected.green * 255).round().clamp(0, 255),
            reason: 'green for sample ${samples[i]}');
        expect(
            pixels.rgba[i * 4 + 2], (expected.blue * 255).round().clamp(0, 255),
            reason: 'blue for sample ${samples[i]}');
        expect(pixels.rgba[i * 4 + 3], 255);
      }
    });

    test('color-key /Mask stays per-pixel when samples repeat', () {
      // Alpha depends on the raw sample, not the shared colour: the two 128s
      // must both key out while their neighbours stay opaque.
      final pixels = decodePdfImagePixels(
          cos,
          separation([
            0,
            128,
            255,
            128
          ], extra: {
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
          separation([
            0,
            255
          ], extra: {
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

  // An /Indexed palette over a Separation/DeviceN base once returned null and
  // dropped the whole image (issue #430 - both images on the Ghent DeviceN
  // page are this shape). Each palette entry runs through the base's tint
  // transform, exactly as the non-indexed Separation/DeviceN path does.
  group('indexed over a tint base', () {
    /// `[/Indexed [/Separation Spot DeviceCMYK { dup 0.5 mul exch 0.25 mul 0 0 }]
    /// hival lookup]`: one ink per palette entry into DeviceCMYK.
    CosStream indexedSeparation(List<int> lookup, List<int> indices) => image({
          'Width': CosInteger(indices.length),
          'Height': const CosInteger(1),
          'BitsPerComponent': const CosInteger(8),
          'ColorSpace': CosArray([
            const CosName('Indexed'),
            CosArray([
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
            CosInteger(lookup.length - 1),
            CosString(Uint8List.fromList(lookup)),
          ]),
        }, indices);

    test('decodes instead of dropping the image', () {
      // The regression: this whole image used to decode to null.
      final pixels =
          decodePdfImagePixels(cos, indexedSeparation([0, 255], [0, 1]));
      expect(pixels, isNotNull);
      expect(pixels!.width, 2);
      expect(pixels.height, 1);
    });

    test('each palette entry maps through the tint transform', () {
      // Two colorant tints (0 and 1) selected by index; the decoded colour must
      // match the transform's CMYK converted the way the decoder does.
      final pixels =
          decodePdfImagePixels(cos, indexedSeparation([0, 255], [0, 1]))!;
      for (final (i, tint) in [(0, 0.0), (1, 1.0)]) {
        final expected =
            colorFromComponents([tint * 0.5, tint * 0.25, 0.0, 0.0], 4);
        expect(pixels.rgba[i * 4], (expected.red * 255).round().clamp(0, 255),
            reason: 'red for tint $tint');
        expect(pixels.rgba[i * 4 + 1],
            (expected.green * 255).round().clamp(0, 255),
            reason: 'green for tint $tint');
        expect(
            pixels.rgba[i * 4 + 2], (expected.blue * 255).round().clamp(0, 255),
            reason: 'blue for tint $tint');
        expect(pixels.rgba[i * 4 + 3], 255);
      }
    });

    test('DeviceN base sizes each palette entry by its colorant count', () {
      // `{ pop dup 0.0 0.0 }` paints with InkA and drops InkB, so a two-colorant
      // palette entry [InkA, InkB] must consume two lookup bytes: entries
      // [200, 0] and [200, 255] share InkA and must decode identically, while
      // [0, 0] must differ. A base mis-sized to one byte would misalign the
      // whole table.
      final stream = image({
        'Width': const CosInteger(3),
        'Height': const CosInteger(1),
        'BitsPerComponent': const CosInteger(8),
        'ColorSpace': CosArray([
          const CosName('Indexed'),
          CosArray([
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
          const CosInteger(2),
          CosString(Uint8List.fromList([200, 0, 200, 255, 0, 0])),
        ]),
      }, [
        0, 1, 2, //
      ]);

      final pixels = decodePdfImagePixels(cos, stream)!;
      List<int> pixelAt(int i) => pixels.rgba.sublist(i * 4, i * 4 + 4);
      expect(pixelAt(0), pixelAt(1)); // same InkA, InkB ignored
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

    test(
        'no region or target decodes at native size, like decodePdfImagePixels',
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
      final slice = decodePdfImage(cos, stream,
          region: const PdfImageRegion(1, 0, 2, 1))!;
      expect(slice.width, 2);
      expect(slice.height, 1);
      // premultiplied but fully opaque, so RGB is unchanged: pixels 1 and 2.
      expect(slice.rgba, [20, 21, 22, 255, 30, 31, 32, 255]);
    });

    test(
        'the fast region path and the full-decode fallback agree pixel-exactly',
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
        }, [
          255,
          255,
          255,
          255
        ]), // fully opaque mask: pixels are unchanged
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
      final scaled =
          decodePdfImage(cos, stream, targetWidth: 2, targetHeight: 1)!;
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

  group('a small-displayed JPX takes the resolution-reduced decode', () {
    CosStream jpxImage(int tw, int th) => image({
          'Width': const CosInteger(16),
          'Height': const CosInteger(16),
          'BitsPerComponent': const CosInteger(8),
          'ColorSpace': const CosName('DeviceRGB'),
          'Filter': const CosName('JPXDecode'),
        }, _rgbJ2kFixture);

    test('reduced-path output matches the full-decode downsample', () {
      // The reduced JPX decode (finest wavelet levels skipped) is not byte-
      // identical to decoding all 16x16 and box-averaging, but on this linear
      // ramp the two agree closely. The point is that the scaled façade routed
      // through the reduced path and produced the right pixels at target size.
      final stream = jpxImage(4, 4);
      final full = decodePdfImagePixels(cos, stream)!;
      final expected = downsamplePdfDecodedPixels(full, 4, 4);
      final scaled = decodePdfImagePixelsScaled(cos, stream, 4, 4)!;

      expect(scaled.width, 4);
      expect(scaled.height, 4);
      var maxDiff = 0;
      for (var i = 0; i < expected.rgba.length; i++) {
        maxDiff = maxDiff > (scaled.rgba[i] - expected.rgba[i]).abs()
            ? maxDiff
            : (scaled.rgba[i] - expected.rgba[i]).abs();
      }
      expect(maxDiff, lessThanOrEqualTo(24));
    });

    test('a target no smaller than native is left to the full path', () {
      // ratio < 2 → no reduce; the scaled façade declines and the caller
      // full-decodes. (16x16 asked for 16x16.)
      expect(decodePdfImagePixelsScaled(cos, jpxImage(16, 16), 16, 16), isNull);
    });
  });
}

/// The 16x16 lossless RGB (RCT + 5/3) JPEG 2000 codestream from pdf_cos's
/// jpx_test - a linear ramp (R=16x, G=16y, B=8x). Duplicated here (the two
/// test suites are independent) to exercise the JPX branch of the scaled decode
/// façade end to end.
const _rgbJ2kFixture = [
  255,
  79,
  255,
  81,
  0,
  47,
  0,
  0,
  0,
  0,
  0,
  16,
  0,
  0,
  0,
  16,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  16,
  0,
  0,
  0,
  16,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  3,
  7,
  1,
  1,
  7,
  1,
  1,
  7,
  1,
  1,
  255,
  82,
  0,
  12,
  0,
  0,
  0,
  1,
  1,
  2,
  4,
  4,
  0,
  1,
  255,
  92,
  0,
  10,
  64,
  64,
  72,
  72,
  80,
  72,
  72,
  80,
  255,
  100,
  0,
  37,
  0,
  1,
  67,
  114,
  101,
  97,
  116,
  101,
  100,
  32,
  98,
  121,
  32,
  79,
  112,
  101,
  110,
  74,
  80,
  69,
  71,
  32,
  118,
  101,
  114,
  115,
  105,
  111,
  110,
  32,
  50,
  46,
  53,
  46,
  52,
  255,
  144,
  0,
  10,
  0,
  0,
  0,
  0,
  0,
  158,
  0,
  1,
  255,
  147,
  223,
  128,
  128,
  18,
  15,
  51,
  220,
  41,
  248,
  240,
  83,
  215,
  233,
  92,
  255,
  7,
  107,
  224,
  63,
  207,
  180,
  52,
  6,
  65,
  148,
  140,
  180,
  7,
  54,
  238,
  103,
  24,
  210,
  232,
  251,
  223,
  128,
  112,
  6,
  65,
  148,
  140,
  180,
  7,
  54,
  238,
  103,
  24,
  211,
  235,
  51,
  111,
  192,
  249,
  2,
  65,
  243,
  131,
  0,
  34,
  24,
  119,
  191,
  3,
  127,
  191,
  193,
  243,
  133,
  131,
  231,
  8,
  34,
  26,
  8,
  93,
  127,
  0,
  207,
  213,
  81,
  195,
  234,
  5,
  135,
  212,
  10,
  34,
  26,
  8,
  93,
  127,
  0,
  207,
  213,
  82,
  63,
  192,
  124,
  34,
  64,
  249,
  3,
  0,
  54,
  161,
  132,
  63,
  61,
  166,
  52,
  47,
  249,
  83,
  192,
  249,
  2,
  64,
  249,
  2,
  0,
  54,
  161,
  153,
  207,
  62,
  98,
  162,
  175,
  193,
  243,
  132,
  131,
  231,
  10,
  54,
  161,
  153,
  207,
  62,
  98,
  162,
  176,
  63,
  255,
  217,
];
