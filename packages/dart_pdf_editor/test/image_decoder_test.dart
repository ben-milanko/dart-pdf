import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:dart_pdf_editor/src/image_decoder.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

Future<Uint8List> pixelsOf(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return data!.buffer.asUint8List();
}

/// Wraps a stream the way the interpreter hands images to the decoder.
PdfImageRequest req(CosStream stream) =>
    PdfImageRequest(stream: stream, transform: PdfMatrix.identity);

void main() {
  late CosDocument cos;

  setUp(() => cos = CosDocument.open(buildClassicPdf()));

  testWidgets('stencil masks decode to alpha coverage', (tester) async {
    await tester.runAsync(() async {
      final stencil = CosStream(
        CosDictionary({
          'Subtype': const CosName('Image'),
          'ImageMask': const CosBoolean(true),
          'Width': const CosInteger(2),
          'Height': const CosInteger(1),
          'BitsPerComponent': const CosInteger(1),
        }),
        // bits: 0 (paint), 1 (skip)
        Uint8List.fromList([0x40]),
      );
      final images = await decodeImages(cos, [req(stencil)]);
      final pixels = await pixelsOf(images[stencil]!);
      expect(pixels[3], 255); // first pixel painted
      expect(pixels[7], 0); // second pixel transparent
    });
  });

  testWidgets('stencil /Decode [1 0] inverts polarity', (tester) async {
    await tester.runAsync(() async {
      final stencil = CosStream(
        CosDictionary({
          'ImageMask': const CosBoolean(true),
          'Width': const CosInteger(2),
          'Height': const CosInteger(1),
          'BitsPerComponent': const CosInteger(1),
          'Decode': CosArray([const CosInteger(1), const CosInteger(0)]),
        }),
        Uint8List.fromList([0x40]),
      );
      final images = await decodeImages(cos, [req(stencil)]);
      final pixels = await pixelsOf(images[stencil]!);
      expect(pixels[3], 0);
      expect(pixels[7], 255);
    });
  });

  testWidgets('SMask samples become the alpha channel', (tester) async {
    await tester.runAsync(() async {
      final smask = CosStream(
        CosDictionary({
          'Width': const CosInteger(2),
          'Height': const CosInteger(1),
          'BitsPerComponent': const CosInteger(8),
          'ColorSpace': const CosName('DeviceGray'),
        }),
        Uint8List.fromList([255, 0]),
      );
      final image = CosStream(
        CosDictionary({
          'Width': const CosInteger(2),
          'Height': const CosInteger(1),
          'BitsPerComponent': const CosInteger(8),
          'ColorSpace': const CosName('DeviceRGB'),
          'SMask': smask,
        }),
        Uint8List.fromList([255, 0, 0, 0, 255, 0]),
      );
      final images = await decodeImages(cos, [req(image)]);
      final pixels = await pixelsOf(images[image]!);
      expect(pixels.sublist(0, 4), [255, 0, 0, 255]); // opaque red
      expect(pixels[7], 0); // green pixel fully masked out
    });
  });

  testWidgets('SMask resamples when dimensions differ', (tester) async {
    await tester.runAsync(() async {
      final smask = CosStream(
        CosDictionary({
          'Width': const CosInteger(1),
          'Height': const CosInteger(1),
          'BitsPerComponent': const CosInteger(8),
        }),
        Uint8List.fromList([128]),
      );
      final image = CosStream(
        CosDictionary({
          'Width': const CosInteger(2),
          'Height': const CosInteger(2),
          'BitsPerComponent': const CosInteger(8),
          'ColorSpace': const CosName('DeviceGray'),
          'SMask': smask,
        }),
        Uint8List.fromList([10, 20, 30, 40]),
      );
      final images = await decodeImages(cos, [req(image)]);
      final pixels = await pixelsOf(images[image]!);
      for (var i = 0; i < 4; i++) {
        expect(pixels[i * 4 + 3], 128);
      }
    });
  });

  testWidgets('a higher-res /Mask stencil keeps its resolution (issue4246)',
      (tester) async {
    await tester.runAsync(() async {
      // A tiny colour image carrying its detail in a much larger stencil - the
      // mask must NOT be crushed down to the base grid (that produced blocky
      // letters). Base 1x1 red, mask 4x1 paint/skip/paint/skip.
      final mask = CosStream(
        CosDictionary({
          'ImageMask': const CosBoolean(true),
          'Width': const CosInteger(4),
          'Height': const CosInteger(1),
          'BitsPerComponent': const CosInteger(1),
        }),
        // bits 0,1,0,1 -> paint,skip,paint,skip
        Uint8List.fromList([0x50]),
      );
      final image = CosStream(
        CosDictionary({
          'Width': const CosInteger(1),
          'Height': const CosInteger(1),
          'BitsPerComponent': const CosInteger(8),
          'ColorSpace': const CosName('DeviceRGB'),
          'Mask': mask,
        }),
        Uint8List.fromList([255, 0, 0]),
      );
      final images = await decodeImages(cos, [req(image)]);
      final decoded = images[image]!;
      // Output is built at the MASK's resolution, not the 1x1 base.
      expect(decoded.width, 4);
      expect(decoded.height, 1);
      final pixels = await pixelsOf(decoded);
      expect(pixels.sublist(0, 4), [255, 0, 0, 255]); // crisp painted red
      expect(pixels.sublist(4, 8), [0, 0, 0, 0]); // crisp cutout
      expect(pixels.sublist(8, 12), [255, 0, 0, 255]);
      expect(pixels.sublist(12, 16), [0, 0, 0, 0]);
    });
  });

  testWidgets('/Decode [1 0] inverts gray samples', (tester) async {
    await tester.runAsync(() async {
      final image = CosStream(
        CosDictionary({
          'Width': const CosInteger(2),
          'Height': const CosInteger(1),
          'BitsPerComponent': const CosInteger(8),
          'ColorSpace': const CosName('DeviceGray'),
          'Decode': CosArray([const CosInteger(1), const CosInteger(0)]),
        }),
        Uint8List.fromList([0, 200]),
      );
      final images = await decodeImages(cos, [req(image)]);
      final pixels = await pixelsOf(images[image]!);
      expect(pixels[0], 255); // 0 inverted
      expect(pixels[4], 55); // 200 inverted
    });
  });

  testWidgets('/Decode inverts 1-bit gray polarity', (tester) async {
    await tester.runAsync(() async {
      final image = CosStream(
        CosDictionary({
          'Width': const CosInteger(2),
          'Height': const CosInteger(1),
          'BitsPerComponent': const CosInteger(1),
          'ColorSpace': const CosName('DeviceGray'),
          'Decode': CosArray([const CosInteger(1), const CosInteger(0)]),
        }),
        Uint8List.fromList([0x40]), // bits: 0, 1
      );
      final images = await decodeImages(cos, [req(image)]);
      final pixels = await pixelsOf(images[image]!);
      expect(pixels[0], 255); // bit 0 → decode min 1 → white
      expect(pixels[4], 0); // bit 1 → decode max 0 → black
    });
  });

  testWidgets('color-key /Mask ranges knock samples transparent',
      (tester) async {
    await tester.runAsync(() async {
      final image = CosStream(
        CosDictionary({
          'Width': const CosInteger(2),
          'Height': const CosInteger(1),
          'BitsPerComponent': const CosInteger(8),
          'ColorSpace': const CosName('DeviceRGB'),
          // green-screen: kill pure green
          'Mask': CosArray([
            const CosInteger(0), const CosInteger(5), //
            const CosInteger(250), const CosInteger(255),
            const CosInteger(0), const CosInteger(5),
          ]),
        }),
        Uint8List.fromList([0, 255, 0, 200, 30, 40]),
      );
      final images = await decodeImages(cos, [req(image)]);
      final pixels = await pixelsOf(images[image]!);
      expect(pixels[3], 0); // green pixel keyed out
      expect(pixels[7], 255); // other pixel opaque
      expect(pixels.sublist(4, 7), [200, 30, 40]);
    });
  });

  testWidgets('an explicit /Mask stencil stream hides 1-samples',
      (tester) async {
    await tester.runAsync(() async {
      final mask = CosStream(
        CosDictionary({
          'Width': const CosInteger(2),
          'Height': const CosInteger(1),
          'BitsPerComponent': const CosInteger(1),
          'ImageMask': const CosBoolean(true),
        }),
        Uint8List.fromList([0x80]), // bits: 1 (mask out), 0 (keep)
      );
      final image = CosStream(
        CosDictionary({
          'Width': const CosInteger(2),
          'Height': const CosInteger(1),
          'BitsPerComponent': const CosInteger(8),
          'ColorSpace': const CosName('DeviceGray'),
          'Mask': mask,
        }),
        Uint8List.fromList([100, 100]),
      );
      final images = await decodeImages(cos, [req(image)]);
      final pixels = await pixelsOf(images[image]!);
      expect(pixels[3], 0);
      expect(pixels[7], 255);
    });
  });

  testWidgets('masked-out pixels premultiply to transparent black',
      (tester) async {
    await tester.runAsync(() async {
      // a white image whose SMask hides the first pixel: rgba8888 is
      // premultiplied, so (255,255,255,0) would composite as additive
      // white instead of disappearing
      final smask = CosStream(
        CosDictionary({
          'Width': const CosInteger(2),
          'Height': const CosInteger(1),
          'BitsPerComponent': const CosInteger(8),
        }),
        Uint8List.fromList([0, 255]),
      );
      final image = CosStream(
        CosDictionary({
          'Width': const CosInteger(2),
          'Height': const CosInteger(1),
          'BitsPerComponent': const CosInteger(8),
          'ColorSpace': const CosName('DeviceRGB'),
          'SMask': smask,
        }),
        Uint8List.fromList([255, 255, 255, 255, 255, 255]),
      );
      final images = await decodeImages(cos, [req(image)]);
      final pixels = await pixelsOf(images[image]!);
      expect(pixels.sublist(0, 4), [0, 0, 0, 0]);
      expect(pixels.sublist(4, 8), [255, 255, 255, 255]);
    });
  });

  testWidgets('indexed palettes resolve through an ICCBased base',
      (tester) async {
    await tester.runAsync(() async {
      // a 3-component ICC profile stream standing in for sRGB; the decoder
      // only reads /N
      final profile =
          CosStream(CosDictionary({'N': const CosInteger(3)}), Uint8List(0));
      final image = CosStream(
        CosDictionary({
          'Width': const CosInteger(2),
          'Height': const CosInteger(1),
          'BitsPerComponent': const CosInteger(8),
          'ColorSpace': CosArray([
            const CosName('Indexed'),
            CosArray([const CosName('ICCBased'), profile]),
            const CosInteger(1),
            CosString(Uint8List.fromList([255, 0, 0, 0, 255, 0])),
          ]),
        }),
        Uint8List.fromList([0, 1]),
      );
      final images = await decodeImages(cos, [req(image)]);
      final pixels = await pixelsOf(images[image]!);
      expect(pixels.sublist(0, 4), [255, 0, 0, 255]); // red
      expect(pixels.sublist(4, 8), [0, 255, 0, 255]); // green
    });
  });

  testWidgets('indexed CMYK palettes convert to RGB', (tester) async {
    await tester.runAsync(() async {
      final image = CosStream(
        CosDictionary({
          'Width': const CosInteger(2),
          'Height': const CosInteger(1),
          'BitsPerComponent': const CosInteger(8),
          'ColorSpace': CosArray([
            const CosName('Indexed'),
            const CosName('DeviceCMYK'),
            const CosInteger(1),
            // pure cyan, pure black
            CosString(Uint8List.fromList([255, 0, 0, 0, 0, 0, 0, 255])),
          ]),
        }),
        Uint8List.fromList([0, 1]),
      );
      final images = await decodeImages(cos, [req(image)]);
      final pixels = await pixelsOf(images[image]!);
      // pure cyan through pdf.js's DeviceCMYK polynomial ≈ (0, 185, 242)
      expect(pixels.sublist(0, 4), [0, 185, 242, 255]);
      // pure K is the SWOP profile's dark grey, not a perfect black
      expect(pixels.sublist(4, 8), [44, 46, 53, 255]);
    });
  });

  testWidgets('indexed Lab palettes decode through the CIE conversion',
      (tester) async {
    await tester.runAsync(() async {
      // Two palette entries as L*a*b* bytes: white (L*=100, a*=b*=0) and
      // black (L*=0). Before the Lab base was handled, the palette fell
      // through to DeviceGray and the L/a/b triples were read as separate
      // gray samples, so index 1 decoded to mid-gray (128) - banding a smooth
      // gradient into diagonal stripes (issue2761.pdf).
      final image = CosStream(
        CosDictionary({
          'Width': const CosInteger(2),
          'Height': const CosInteger(1),
          'BitsPerComponent': const CosInteger(8),
          'ColorSpace': CosArray([
            const CosName('Indexed'),
            CosArray([
              const CosName('Lab'),
              CosDictionary({
                'WhitePoint': CosArray([
                  const CosReal(0.9642),
                  const CosInteger(1),
                  const CosReal(0.8249),
                ]),
                'Range': CosArray([
                  const CosInteger(-128),
                  const CosInteger(127),
                  const CosInteger(-128),
                  const CosInteger(127),
                ]),
              }),
            ]),
            const CosInteger(1),
            // L*=100 a*=0 b*=0 (white), then L*=0 a*=0 b*=0 (black)
            CosString(Uint8List.fromList([255, 128, 128, 0, 128, 128])),
          ]),
        }),
        Uint8List.fromList([0, 1]),
      );
      final images = await decodeImages(cos, [req(image)]);
      final pixels = await pixelsOf(images[image]!);
      // index 0: near-white and neutral (R≈G≈B)
      expect(pixels[0], greaterThan(230));
      expect((pixels[0] - pixels[1]).abs(), lessThan(16));
      expect((pixels[1] - pixels[2]).abs(), lessThan(16));
      // index 1: near-black - the discriminator (the old gray fallback gave 128)
      expect(pixels[4], lessThan(30));
      expect(pixels[5], lessThan(30));
      expect(pixels[6], lessThan(30));
    });
  });

  testWidgets('color-key /Mask applies to platform-decoded JPEGs',
      (tester) async {
    await tester.runAsync(() async {
      final image = CosStream(
        CosDictionary({
          'Width': const CosInteger(8),
          'Height': const CosInteger(8),
          'BitsPerComponent': const CosInteger(8),
          'ColorSpace': const CosName('DeviceRGB'),
          'Filter': const CosName('DCTDecode'),
          // key out red, with slack for JPEG loss
          'Mask': CosArray([
            const CosInteger(200), const CosInteger(255), //
            const CosInteger(0), const CosInteger(50),
            const CosInteger(0), const CosInteger(50),
          ]),
        }),
        buildTestJpeg(),
      );
      final images = await decodeImages(cos, [req(image)]);
      final pixels = await pixelsOf(images[image]!);
      for (var i = 0; i < pixels.length; i += 4) {
        expect(pixels[i + 3], 0, reason: 'pixel $i should be keyed out');
      }
    });
  });

  testWidgets('/Decode inverts platform-decoded JPEG samples', (tester) async {
    await tester.runAsync(() async {
      final image = CosStream(
        CosDictionary({
          'Width': const CosInteger(8),
          'Height': const CosInteger(8),
          'BitsPerComponent': const CosInteger(8),
          'ColorSpace': const CosName('DeviceRGB'),
          'Filter': const CosName('DCTDecode'),
          'Decode': CosArray([
            const CosInteger(1), const CosInteger(0), //
            const CosInteger(1), const CosInteger(0),
            const CosInteger(1), const CosInteger(0),
          ]),
        }),
        buildTestJpeg(),
      );
      final images = await decodeImages(cos, [req(image)]);
      final pixels = await pixelsOf(images[image]!);
      // solid red inverts to cyan (chroma subsampling costs ~40 levels)
      expect(pixels[0], lessThan(60));
      expect(pixels[1], greaterThan(200));
      expect(pixels[2], greaterThan(200));
      expect(pixels[3], 255);
    });
  });

  testWidgets('DeviceCMYK DCT images decode in PDF sample polarity',
      (tester) async {
    await tester.runAsync(() async {
      final doc = PdfDocument.open(
          File('../../test_corpora/pdfjs/cmykjpeg.pdf').readAsBytesSync());
      final collector = ImageCollector();
      PdfInterpreter(cos: doc.cos, device: collector).drawPage(doc.page(0));
      expect(collector.streams, hasLength(1));

      final request = collector.streams.single;
      final images = await decodeImages(doc.cos, [request]);
      final image = images[pdfImageKey(request)]!;
      expect(image.width, 200);
      expect(image.height, 150);

      final pixels = await pixelsOf(image);
      // The embedded Adobe CMYK JPEG starts with a light sky pixel.
      // Platform RGB conversion rendered this nearly black.
      expect(pixels[0], greaterThan(90));
      expect(pixels[1], greaterThan(140));
      expect(pixels[2], greaterThan(170));
      expect(pixels[3], 255);
    });
  });

  testWidgets('ICCBased images convert through the real profile',
      (tester) async {
    await tester.runAsync(() async {
      final profile = CosStream(
          CosDictionary({'N': const CosInteger(3)}), adobeRgb1998Icc());
      final image = CosStream(
        CosDictionary({
          'Width': const CosInteger(1),
          'Height': const CosInteger(1),
          'BitsPerComponent': const CosInteger(8),
          'ColorSpace': CosArray([const CosName('ICCBased'), profile]),
        }),
        Uint8List.fromList([128, 64, 200]),
      );
      final images = await decodeImages(cos, [req(image)]);
      final pixels = await pixelsOf(images[image]!);
      // AdobeRGB (128,64,200) in sRGB per littleCMS: (146,62,205)
      expect(pixels[0], closeTo(146, 3));
      expect(pixels[1], closeTo(62, 3));
      expect(pixels[2], closeTo(205, 3));
    });
  });

  testWidgets('ICCBased CMYK images use the LUT profile', (tester) async {
    await tester.runAsync(() async {
      final profile = CosStream(
          CosDictionary({'N': const CosInteger(4)}), genericCmykIcc());
      final image = CosStream(
        CosDictionary({
          'Width': const CosInteger(1),
          'Height': const CosInteger(1),
          'BitsPerComponent': const CosInteger(8),
          'ColorSpace': CosArray([const CosName('ICCBased'), profile]),
        }),
        Uint8List.fromList([255, 0, 0, 0]), // pure cyan
      );
      final images = await decodeImages(cos, [req(image)]);
      final pixels = await pixelsOf(images[image]!);
      // littleCMS: (0,164,219) - the naive cmyk() heuristic gives
      // (0,158,224), so this proves the profile path ran... barely;
      // the black test separates them decisively
      expect(pixels[0], closeTo(0, 3));
      expect(pixels[1], closeTo(164, 3));
      expect(pixels[2], closeTo(219, 3));
    });
  });

  testWidgets('DeviceN images evaluate the tint transform', (tester) async {
    await tester.runAsync(() async {
      final tint = CosStream(
        CosDictionary({
          'FunctionType': const CosInteger(4),
          'Domain': CosArray([
            const CosInteger(0),
            const CosInteger(1),
            const CosInteger(0),
            const CosInteger(1),
            const CosInteger(0),
            const CosInteger(1),
          ]),
          'Range': CosArray([
            const CosInteger(0),
            const CosInteger(1),
            const CosInteger(0),
            const CosInteger(1),
            const CosInteger(0),
            const CosInteger(1),
          ]),
          'Length': const CosInteger(2),
        }),
        Uint8List.fromList('{}'.codeUnits),
      );
      final image = CosStream(
        CosDictionary({
          'Width': const CosInteger(2),
          'Height': const CosInteger(1),
          'BitsPerComponent': const CosInteger(8),
          'ColorSpace': CosArray([
            const CosName('DeviceN'),
            CosArray([
              const CosName('X'),
              const CosName('Y'),
              const CosName('Z'),
            ]),
            const CosName('DeviceRGB'),
            tint,
          ]),
        }),
        Uint8List.fromList([255, 128, 0, 0, 64, 255]),
      );
      final images = await decodeImages(cos, [req(image)]);
      final pixels = await pixelsOf(images[image]!);
      expect(pixels.sublist(0, 4), [255, 128, 0, 255]);
      expect(pixels.sublist(4, 8), [0, 64, 255, 255]);
    });
  });

  testWidgets('CCITT Group 4 images decode to 1-bit gray', (tester) async {
    await tester.runAsync(() async {
      // a libtiff-encoded 64x24 G4 strip (same data as the pdf_cos KAT):
      // black rectangle at x4..20 on rows 4..12 among other shapes
      final image = CosStream(
        CosDictionary({
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
        }),
        Uint8List.fromList(const [
          200, 25, 156, 93, 148, 12, 216, 49, 178, 139, 251, 40, 71, 143, //
          254, 72, 95, 101, 107, 236, 173, 61, 148, 31, 178, 136, 29, 148,
          141, 148, 124, 127, 32, 215, 101, 102, 202, 189, 130, 136, 240,
          1, 0, 16,
        ]),
      );
      final images = await decodeImages(cos, [req(image)]);
      final pixels = await pixelsOf(images[image]!);
      int grayAt(int x, int y) => pixels[(y * 64 + x) * 4];
      expect(grayAt(0, 0), 255); // background white
      expect(grayAt(10, 8), 0); // inside the black rectangle
      expect(grayAt(60, 23), 255);
    });
  });

  testWidgets('JBIG2 images decode with globals', (tester) async {
    await tester.runAsync(() async {
      // jbig2enc symbol-mode output: globals carry the symbol
      // dictionary, the page stream the text region (64x24 image with a
      // black rectangle at x4..20 rows 4..12 among other shapes)
      final globals = CosStream(
        CosDictionary({}),
        Uint8List.fromList(const [
          0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 41, 0, 0, 3, 255, 253, 255, 2, //
          254, 254, 254, 0, 0, 0, 4, 0, 0, 0, 4, 85, 82, 55, 183, 56, 30,
          214, 116, 64, 103, 36, 66, 172, 231, 67, 88, 194, 157, 165, 26,
          123, 255, 172,
        ]),
      );
      final image = CosStream(
        CosDictionary({
          'Width': const CosInteger(64),
          'Height': const CosInteger(24),
          'BitsPerComponent': const CosInteger(1),
          'ColorSpace': const CosName('DeviceGray'),
          'Filter': const CosName('JBIG2Decode'),
          'DecodeParms': CosDictionary({'JBIG2Globals': globals}),
        }),
        Uint8List.fromList(const [
          0, 0, 0, 1, 48, 0, 1, 0, 0, 0, 19, 0, 0, 0, 64, 0, 0, 0, 24, //
          0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 6, 34, 0, 1, 0, 0,
          0, 38, 0, 0, 0, 64, 0, 0, 0, 24, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
          0, 0, 0, 0, 5, 159, 117, 238, 240, 241, 108, 197, 150, 89, 20,
          32, 28, 127, 255, 172,
        ]),
      );
      final images = await decodeImages(cos, [req(image)]);
      final pixels = await pixelsOf(images[image]!);
      int grayAt(int x, int y) => pixels[(y * 64 + x) * 4];
      expect(grayAt(0, 0), 255); // background white
      expect(grayAt(10, 8), 0); // inside the black rectangle
      expect(grayAt(63, 23), 255);
    });
  });

  testWidgets('4-bit indexed samples unpack two pixels per byte',
      (tester) async {
    await tester.runAsync(() async {
      final image = CosStream(
        CosDictionary({
          'Width': const CosInteger(3),
          'Height': const CosInteger(2),
          'BitsPerComponent': const CosInteger(4),
          'ColorSpace': CosArray([
            const CosName('Indexed'),
            const CosName('DeviceRGB'),
            const CosInteger(2),
            CosString(Uint8List.fromList([255, 0, 0, 0, 255, 0, 0, 0, 255])),
          ]),
        }),
        // rows are byte-aligned: 0,1,2 then 2,1,0
        Uint8List.fromList([0x01, 0x20, 0x21, 0x00]),
      );
      final images = await decodeImages(cos, [req(image)]);
      final pixels = await pixelsOf(images[image]!);
      List<int> at(int x, int y) =>
          pixels.sublist((y * 3 + x) * 4, (y * 3 + x) * 4 + 3);
      expect(at(0, 0), [255, 0, 0]);
      expect(at(1, 0), [0, 255, 0]);
      expect(at(2, 0), [0, 0, 255]);
      expect(at(0, 1), [0, 0, 255]);
      expect(at(1, 1), [0, 255, 0]);
      expect(at(2, 1), [255, 0, 0]);
    });
  });

  // The per-pixel decode fast paths (no colour management, identity /Decode,
  // no colour key) copy samples straight through and leave the image opaque,
  // so the premultiply scan is skipped. These pin that the fast paths produce
  // exactly the same pixels as the general path would.
  testWidgets('DeviceRGB 8-bit samples decode straight through, opaque',
      (tester) async {
    await tester.runAsync(() async {
      final image = CosStream(
        CosDictionary({
          'Width': const CosInteger(2),
          'Height': const CosInteger(1),
          'BitsPerComponent': const CosInteger(8),
          'ColorSpace': const CosName('DeviceRGB'),
        }),
        Uint8List.fromList([12, 34, 56, 200, 100, 50]),
      );
      final images = await decodeImages(cos, [req(image)]);
      final pixels = await pixelsOf(images[image]!);
      expect(pixels.sublist(0, 4), [12, 34, 56, 255]);
      expect(pixels.sublist(4, 8), [200, 100, 50, 255]);
    });
  });

  testWidgets('DeviceGray 8-bit samples replicate to RGB, opaque',
      (tester) async {
    await tester.runAsync(() async {
      final image = CosStream(
        CosDictionary({
          'Width': const CosInteger(2),
          'Height': const CosInteger(1),
          'BitsPerComponent': const CosInteger(8),
          'ColorSpace': const CosName('DeviceGray'),
        }),
        Uint8List.fromList([40, 210]),
      );
      final images = await decodeImages(cos, [req(image)]);
      final pixels = await pixelsOf(images[image]!);
      expect(pixels.sublist(0, 4), [40, 40, 40, 255]);
      expect(pixels.sublist(4, 8), [210, 210, 210, 255]);
    });
  });

  testWidgets('raw DeviceCMYK converts through PdfColor.cmyk exactly',
      (tester) async {
    await tester.runAsync(() async {
      // A representative process colour, fed both to the decoder and to
      // PdfColor.cmyk directly - the inlined per-pixel path must match the
      // canonical conversion byte-for-byte (no hardcoded RGB constants).
      const c = 30, m = 90, y = 200, k = 60;
      final image = CosStream(
        CosDictionary({
          'Width': const CosInteger(1),
          'Height': const CosInteger(1),
          'BitsPerComponent': const CosInteger(8),
          'ColorSpace': const CosName('DeviceCMYK'),
        }),
        Uint8List.fromList([c, m, y, k]),
      );
      final images = await decodeImages(cos, [req(image)]);
      final pixels = await pixelsOf(images[image]!);
      final expected =
          PdfColor.cmyk(c / 255, m / 255, y / 255, k / 255);
      expect(pixels[0], (expected.red * 255).round());
      expect(pixels[1], (expected.green * 255).round());
      expect(pixels[2], (expected.blue * 255).round());
      expect(pixels[3], 255);
    });
  });

  testWidgets('DeviceRGB /Decode inverts through the LUT path', (tester) async {
    await tester.runAsync(() async {
      final image = CosStream(
        CosDictionary({
          'Width': const CosInteger(1),
          'Height': const CosInteger(1),
          'BitsPerComponent': const CosInteger(8),
          'ColorSpace': const CosName('DeviceRGB'),
          'Decode': CosArray([
            const CosInteger(1), const CosInteger(0), //
            const CosInteger(1), const CosInteger(0),
            const CosInteger(1), const CosInteger(0),
          ]),
        }),
        Uint8List.fromList([0, 64, 255]),
      );
      final images = await decodeImages(cos, [req(image)]);
      final pixels = await pixelsOf(images[image]!);
      // 0→255, 255→0, 64→191 (the same LUT the general path builds).
      expect(pixels.sublist(0, 4), [255, 191, 0, 255]);
    });
  });

  group('display-resolution decode cap', () {
    // One full-bleed underlay + gray soft mask on an A1-ish sheet, decoded
    // through the real interpreter so the request carries the true page-space
    // transform the cap reads its footprint from.
    Future<(CosDocument, List<PdfImageRequest>)> underlay(
        int nativeW, int nativeH) async {
      final bytes = buildSyntheticRasterUnderlaySheet(
        underlays: [PdfUnderlaySpec(width: nativeW, height: nativeH)],
        layers: 4,
        ops: 50,
      );
      final doc = CosDocument.open(bytes);
      final page = PdfDocument.open(bytes).page(0);
      final collector = ImageCollector();
      PdfInterpreter(cos: doc, device: collector)
          .drawPageContent(page, page.contentBytes());
      // The base underlay, not its mask (masks are referenced via /SMask, not
      // drawn), is the one image the page draws.
      return (doc, collector.streams);
    }

    testWidgets('a huge underlay decodes at display size, not native',
        (tester) async {
      await tester.runAsync(() async {
        final (doc, requests) = await underlay(4000, 2600);
        // ratio 0.5 px/pt over a ~2384pt-wide sheet -> ~1192px on screen; the
        // 2x headroom caps near 2384px, well under the 4000px native width.
        final images =
            await decodeImages(doc, requests, maxImagePixelRatio: 0.5);
        final image = images.values.single;
        expect(image.width, lessThan(4000));
        expect(image.width, greaterThan(1192)); // sharper than 1:1
        // The soft mask was fitted to the base, so the composite kept the cap
        // instead of ballooning back to the mask's native 4000x2600.
        expect(image.height, lessThan(2600));
      });
    });

    testWidgets('no ratio still clamps past the GPU max texture size',
        (tester) async {
      await tester.runAsync(() async {
        final (doc, requests) = await underlay(9460, 2918);
        // No display ratio: only the hard ceilings apply. 9460 > 8192 must be
        // brought within the common GPU max texture dimension.
        final images = await decodeImages(doc, requests);
        final image = images.values.single;
        expect(image.width, lessThanOrEqualTo(8192));
        expect(image.width * image.height, lessThanOrEqualTo(1 << 24));
      });
    });

    testWidgets('a small image is untouched by the cap', (tester) async {
      await tester.runAsync(() async {
        final (doc, requests) = await underlay(64, 48);
        final images =
            await decodeImages(doc, requests, maxImagePixelRatio: 2.0);
        final image = images.values.single;
        expect(image.width, 64);
        expect(image.height, 48);
      });
    });

    testWidgets('a DCTDecode base under a non-DCT soft mask caps on the '
        'platform-codec path', (tester) async {
      await tester.runAsync(() async {
        // The #458 shape: a non-CMYK JPEG base (platform codec, not the
        // pure-Dart path) with a Flate gray /SMask. Exercises
        // instantiateImageCodec(targetWidth:) and the _fitMask step that keeps
        // the composite at the capped base size instead of ballooning back to
        // the mask's native resolution.
        const w = 512, h = 384;
        final rgb = img.Image(width: w, height: h);
        for (final p in rgb) {
          p
            ..r = (p.x * 255 ~/ w)
            ..g = (p.y * 255 ~/ h)
            ..b = 128;
        }
        final jpeg = img.encodeJpg(rgb, quality: 90);
        // A fully-opaque Flate gray mask at the base's native size: if _fitMask
        // did not shrink it, pdfApplyImageAlpha would upsize the capped base
        // back to 512x384.
        final maskBytes =
            Uint8List.fromList(ZLibCodec(level: 6).encode(Uint8List(w * h)
              ..fillRange(0, w * h, 0xFF)));
        final base = CosStream(
          CosDictionary({
            'Subtype': const CosName('Image'),
            'Width': const CosInteger(w),
            'Height': const CosInteger(h),
            'BitsPerComponent': const CosInteger(8),
            'ColorSpace': const CosName('DeviceRGB'),
            'Filter': const CosName('DCTDecode'),
            'SMask': CosStream(
              CosDictionary({
                'Subtype': const CosName('Image'),
                'Width': const CosInteger(w),
                'Height': const CosInteger(h),
                'BitsPerComponent': const CosInteger(8),
                'ColorSpace': const CosName('DeviceGray'),
                'Filter': const CosName('FlateDecode'),
                'Length': CosInteger(maskBytes.length),
              }),
              maskBytes,
            ),
          }),
          Uint8List.fromList(jpeg),
        );
        // Unit square -> a 300x225 pt page footprint; at ratio 0.4 the 2x
        // headroom targets ~240px wide, well under the 512px native JPEG.
        final request = PdfImageRequest(
          stream: base,
          transform: PdfMatrix(300, 0, 0, 225, 0, 0),
        );
        final images =
            await decodeImages(cos, [request], maxImagePixelRatio: 0.4);
        final image = images.values.single;
        expect(image.width, lessThan(w));
        expect(image.height, lessThan(h));
        // Base and (fitted) mask agree, so the composite is the capped size,
        // not the mask's native 512x384.
        expect(image.width, greaterThan(0));
      });
    });
  });

  group('concurrent decode (#454)', () {
    CosStream rgbPixel(int r, int g, int b) => CosStream(
          CosDictionary({
            'Width': const CosInteger(1),
            'Height': const CosInteger(1),
            'BitsPerComponent': const CosInteger(8),
            'ColorSpace': const CosName('DeviceRGB'),
          }),
          Uint8List.fromList([r, g, b]),
        );

    testWidgets('decodes every distinct image in one batch', (tester) async {
      await tester.runAsync(() async {
        final streams = [
          rgbPixel(10, 20, 30),
          rgbPixel(40, 50, 60),
          rgbPixel(70, 80, 90),
          rgbPixel(100, 110, 120),
        ];
        final images =
            await decodeImages(cos, [for (final s in streams) req(s)]);
        expect(images.length, 4);
        for (final s in streams) {
          expect(images[s], isNotNull);
        }
        expect((await pixelsOf(images[streams[0]]!)).sublist(0, 3),
            [10, 20, 30]);
        expect((await pixelsOf(images[streams[3]]!)).sublist(0, 3),
            [100, 110, 120]);
      });
    });

    testWidgets('a repeated image is decoded once across the batch',
        (tester) async {
      await tester.runAsync(() async {
        final shared = rgbPixel(11, 22, 33);
        final other = rgbPixel(44, 55, 66);
        // shared appears three times; the map must collapse to two entries
        // (proving the dedup happens before the concurrent decodes launch).
        final images = await decodeImages(
            cos, [req(shared), req(other), req(shared), req(shared)]);
        expect(images.length, 2);
        expect(images[shared], isNotNull);
        expect(images[other], isNotNull);
      });
    });

    testWidgets('a warm cache serves the second batch without re-decoding',
        (tester) async {
      await tester.runAsync(() async {
        final cache = PdfImageCache();
        final stream = rgbPixel(7, 8, 9);
        final first = await decodeImages(cos, [req(stream)], cache: cache);
        final cold = await pixelsOf(first[stream]!);
        // Second call with the same cache must return the same pixels; the
        // hit is resolved in the synchronous planning pass, before any decode.
        final second = await decodeImages(cos, [req(stream)], cache: cache);
        final warm = await pixelsOf(second[stream]!);
        expect(warm, cold);
      });
    });
  });

  // The shared cache used to key worker-decoded pixels and locally-decoded
  // pixels by different *shapes*: a request carrying pixels produced a bare
  // content key, while a capped local decode produced a sized one. The same
  // image could therefore occupy two entries, and a record whose pixels were
  // dropped would miss the entry its own decode had populated. The two shapes
  // coincided whenever the resolution cap happened to be a no-op, which is why
  // it went unnoticed - so these pin both directions (#451).
  group('cache key shape (#451)', () {
    // A 2x2 image, and "worker" pixels for it in a colour a real decode of
    // that stream would never produce. If a later local decode returns this
    // colour, it resolved through the cache rather than decoding again -
    // which is exactly what a shared key buys.
    CosStream red2x2() => CosStream(
          CosDictionary({
            'Width': const CosInteger(2),
            'Height': const CosInteger(2),
            'BitsPerComponent': const CosInteger(8),
            'ColorSpace': const CosName('DeviceRGB'),
          }),
          Uint8List.fromList([
            for (var i = 0; i < 4; i++) ...[255, 0, 0],
          ]),
        );

    PdfDecodedPixels marker(int w, int h) => PdfDecodedPixels(
          Uint8List.fromList([
            for (var i = 0; i < w * h; i++) ...[0, 255, 0, 255],
          ]),
          w,
          h,
        );

    // A big image drawn small, so the resolution cap genuinely binds. That
    // matters: for an image the cap leaves alone, `_decodeTarget` returns null
    // and the old and new key shapes coincide - so a test on a small image
    // passes either way and proves nothing.
    CosStream big() => CosStream(
          CosDictionary({
            'Width': const CosInteger(64),
            'Height': const CosInteger(64),
            'BitsPerComponent': const CosInteger(8),
            'ColorSpace': const CosName('DeviceRGB'),
          }),
          Uint8List.fromList([
            for (var i = 0; i < 64 * 64; i++) ...[255, 0, 0],
          ]),
        );

    testWidgets('worker-decoded and locally-decoded pixels share one entry',
        (tester) async {
      await tester.runAsync(() async {
        final stream = big();
        // 64x64 native drawn into an 8x8pt box at 0.5 px/pt.
        final small = PdfMatrix(8, 0, 0, 8, 0, 0);
        const ratio = 0.5;

        // Discover the size the cap lands on rather than hard-coding the
        // headroom arithmetic, then confirm it really did bind.
        final probe = await decodeImages(
            cos, [PdfImageRequest(stream: stream, transform: small)],
            maxImagePixelRatio: ratio);
        final capped = probe[stream]!;
        expect(capped.width, lessThan(64),
            reason: 'the cap must bind, or this test proves nothing');
        final (cw, ch) = (capped.width, capped.height);

        // The worker path: a record carrying pixels already decoded to that
        // same capped size.
        final cache = PdfImageCache();
        final fromWorker = await decodeImages(
            cos,
            [
              PdfImageRequest(
                  stream: stream, transform: small, decoded: marker(cw, ch)),
            ],
            cache: cache);
        expect(await pixelsOf(fromWorker[stream]!), marker(cw, ch).rgba);

        // Then the same image with no pixels attached - the shape a record
        // takes once its RGBA has been dropped. It must find the entry the
        // worker path populated instead of decoding the stream afresh.
        final local = await decodeImages(
            cos, [PdfImageRequest(stream: stream, transform: small)],
            cache: cache, maxImagePixelRatio: ratio);
        expect(await pixelsOf(local[stream]!), marker(cw, ch).rgba,
            reason: 'a local decode should hit the entry worker pixels stored');
      });
    });

    testWidgets('two resolutions of one image still cache separately',
        (tester) async {
      await tester.runAsync(() async {
        // The other direction: unifying the shape must not let a sharp decode
        // and a small one stand in for each other. Distinct sizes, distinct
        // marker pixels; each must come back as itself.
        final cache = PdfImageCache();
        final stream = red2x2();

        final sharp = await decodeImages(
            cos,
            [
              PdfImageRequest(
                  stream: stream,
                  transform: PdfMatrix.identity,
                  decoded: marker(2, 2)),
            ],
            cache: cache);
        expect(await pixelsOf(sharp[stream]!), marker(2, 2).rgba);

        final tiny = await decodeImages(
            cos,
            [
              PdfImageRequest(
                  stream: stream,
                  transform: PdfMatrix.identity,
                  decoded: marker(1, 1)),
            ],
            cache: cache);
        final tinyPixels = tiny[stream]!;
        expect(tinyPixels.width, 1,
            reason: 'the 1x1 decode must not be served the 2x2 entry');
        expect(await pixelsOf(tinyPixels), marker(1, 1).rgba);

        // And the sharp one must still be intact afterwards.
        final again = await decodeImages(
            cos,
            [
              PdfImageRequest(
                  stream: stream,
                  transform: PdfMatrix.identity,
                  decoded: marker(2, 2)),
            ],
            cache: cache);
        expect(again[stream]!.width, 2);
      });
    });
  });
}
