// Unit coverage for image overprint - the colorant reading of a decoded raster
// and the substitute it composites to (issue #604).
//
// Three layers, each pinned on its own so a failure names one:
//
//   1. [PdfColorSpace.inkColorants] for /Indexed, which is what gives a
//      palette raster a colorant reading at all (GWG031's gray image is
//      /Indexed over DeviceCMYK);
//   2. [pdfImageColorants] - what colorants a raster carries, and the cases
//      that have none (an RGB palette, a stencil, a DCT stream);
//   3. [pdfImageOverprintStream] and [PdfOverprintCompositor.image] - the
//      substitute raster whose samples are already the subtractive composite,
//      and the buffer's decision to build one at all.
//
// The end-to-end guard is dart_pdf_editor's overprint_render_test.dart
// (GWG190/191/192 and GWG031).
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

void main() {
  late CosDocument cos;

  setUp(() => cos = CosDocument.open(buildClassicPdf()));

  /// A type-2 tint transform from one input to [c1]-scaled components.
  CosDictionary exponential(List<double> c1) => CosDictionary({
        'FunctionType': const CosInteger(2),
        'Domain': CosArray([const CosInteger(0), const CosInteger(1)]),
        'C0': CosArray([for (var _ in c1) const CosReal(0)]),
        'C1': CosArray([for (final v in c1) CosReal(v)]),
        'N': const CosInteger(1),
      });

  /// An unfiltered image XObject over [space] carrying [samples].
  CosStream image(CosObject space, List<int> samples,
          {int width = 2,
          int height = 2,
          Map<String, CosObject> extra = const {}}) =>
      CosStream(
          CosDictionary({
            'Type': const CosName('XObject'),
            'Subtype': const CosName('Image'),
            'Width': CosInteger(width),
            'Height': CosInteger(height),
            'BitsPerComponent': const CosInteger(8),
            'ColorSpace': space,
            ...extra,
          }),
          Uint8List.fromList(samples));

  /// `[/Indexed base 255 <lookup>]`.
  CosArray indexed(CosObject base, List<int> lookup) => CosArray([
        const CosName('Indexed'),
        base,
        const CosInteger(255),
        CosString(Uint8List.fromList(lookup)),
      ]);

  group('the colorant reading of a colour space', () {
    test('/Indexed reads its base space through the palette entry', () {
      // A grayscale ramp stored as DeviceCMYK K-only entries - GWG031's shape.
      final space = PdfColorSpace.parse(
          cos,
          indexed(const CosName('DeviceCMYK'),
              [0, 0, 0, 0, 0, 0, 0, 128, 0, 0, 0, 255]));
      expect(
          space.inkColorants(const [0])!.colorants, PdfColorants(0, 0, 0, 0));
      expect(
          space.inkColorants(const [2])!.colorants, PdfColorants(0, 0, 0, 1));
      // Entry 1 is 128/255; the reading is the palette's own value, not a
      // rounded tint.
      expect(
          space.inkColorants(const [1])!.colorants.k, closeTo(128 / 255, 1e-9));
    });

    test('/Indexed over an RGB palette has no colorant reading', () {
      final space = PdfColorSpace.parse(
          cos, indexed(const CosName('DeviceRGB'), [255, 0, 0, 0, 255, 0]));
      expect(space.inkColorants(const [0]), isNull);
    });

    test('/Indexed does not inherit DeviceCMYK\'s OPM-1 zero rule', () {
      final space = PdfColorSpace.parse(
          cos, indexed(const CosName('DeviceCMYK'), [0, 0, 0, 0]));
      // OPM 1's zero-component exception is scoped to DeviceCMYK itself. An
      // Indexed selection writes the complete palette colour even when its
      // base is DeviceCMYK (GWG010's OPM-1 image and mask patches).
      final backdrop = PdfColorants(0, 0, 0, 0,
          spots: const ['GWG Green'], tints: const [1.0]);
      expect(space.inkColorants(const [0])!.over(backdrop, 1), backdrop,
          reason: 'process zeros write, but do not name or erase the spot');
      // Against a process backdrop, those zeros knock out under both modes.
      expect(space.inkColorants(const [0])!.over(PdfColorants(0.5, 0, 1, 0), 0),
          PdfColorants(0, 0, 0, 0));
      expect(space.inkColorants(const [0])!.over(PdfColorants(0.5, 0, 1, 0), 1),
          PdfColorants(0, 0, 0, 0));
    });
  });

  group('reading a raster (pdfImageColorants)', () {
    test('a raster of one sample tuple reads as that ink', () {
      final reading = pdfImageColorants(
          cos,
          image(
              const CosName('DeviceCMYK'),
              List.filled(16, 0)
                ..[3] = 255
                ..[7] = 255
                ..[11] = 255
                ..[15] = 255))!;
      expect(reading.uniformInk!.colorants, PdfColorants(0, 0, 0, 1));
      expect(reading.coversQuad, isTrue);
      expect(reading.backdropInk, isNotNull);
    });

    test('a raster whose samples differ reads as varying, not as one ink', () {
      final reading = pdfImageColorants(
          cos, image(const CosName('DeviceGray'), [0, 64, 128, 255]))!;
      // It still *has* a reading - it can be composited onto a backdrop - but
      // it is not one vector, so the buffer cannot record it as a backdrop.
      expect(reading.uniformInk, isNull);
      expect(reading.backdropInk, isNull);
    });

    test('an /SMask keeps the reading but not the backdrop', () {
      final reading = pdfImageColorants(
          cos,
          image(const CosName('DeviceGray'), [
            128,
            128,
            128,
            128
          ], extra: {
            'SMask': image(const CosName('DeviceGray'), [0, 0, 0, 0]),
          }))!;
      expect(reading.uniformInk, isNotNull);
      // The backdrop survives wherever the mask is transparent, so recording
      // the raster's colorants over its whole quad would be a lie.
      expect(reading.coversQuad, isFalse);
      expect(reading.backdropInk, isNull);
    });

    test('an RGB raster, a stencil and a DCT stream have no reading', () {
      expect(
          pdfImageColorants(
              cos, image(const CosName('DeviceRGB'), List.filled(12, 200))),
          isNull);
      expect(
          pdfImageColorants(
              cos,
              CosStream(
                  CosDictionary({
                    'Subtype': const CosName('Image'),
                    'Width': const CosInteger(8),
                    'Height': const CosInteger(1),
                    'BitsPerComponent': const CosInteger(1),
                    'ImageMask': const CosBoolean(true),
                  }),
                  Uint8List.fromList([0xF0]))),
          isNull,
          reason: 'a stencil paints the fill colour, which is vector ink');
      expect(
          pdfImageColorants(
              cos,
              CosStream(
                  CosDictionary({
                    'Subtype': const CosName('Image'),
                    'Width': const CosInteger(2),
                    'Height': const CosInteger(2),
                    'BitsPerComponent': const CosInteger(8),
                    'ColorSpace': const CosName('DeviceCMYK'),
                    'Filter': const CosName('DCTDecode'),
                  }),
                  Uint8List.fromList([0xFF, 0xD8]))),
          isNull,
          reason: 'a DCT stream does not carry its samples in its own bytes');
    });

    test('unpacks sub-byte and 16-bit samples', () {
      // 4-bit gray, two pixels per byte, with a row that needs padding: 3 wide
      // is 2 bytes per row (12 bits rounded up), so the reader must not walk
      // straight through the buffer.
      CosStream packed(int bits, List<int> bytes, {int width = 3}) => CosStream(
          CosDictionary({
            'Subtype': const CosName('Image'),
            'Width': CosInteger(width),
            'Height': const CosInteger(2),
            'BitsPerComponent': CosInteger(bits),
            'ColorSpace': const CosName('DeviceGray'),
          }),
          Uint8List.fromList(bytes));

      // Every sample 0xF (white): rows are [0xFF, 0xF0], the low nibble of the
      // second byte being padding the reader must ignore.
      expect(
          pdfImageColorants(cos, packed(4, [0xFF, 0xF0, 0xFF, 0xF0]))!
              .uniformInk!
              .colorants,
          PdfColorants(0, 0, 0, 0),
          reason: 'DeviceGray 1.0 writes no colorant');
      // Padding that differs must not read as a differing sample.
      expect(
          pdfImageColorants(cos, packed(4, [0xFF, 0xF0, 0xFF, 0xF7]))!
              .uniformInk,
          isNotNull);
      // ...but a real sample that differs must.
      expect(
          pdfImageColorants(cos, packed(4, [0xFF, 0xF0, 0x0F, 0xF0]))!
              .uniformInk,
          isNull);
      // 1-bit: 8 samples per byte.
      expect(
          pdfImageColorants(cos, packed(1, [0x00, 0x00], width: 8))!
              .uniformInk!
              .colorants,
          PdfColorants(0, 0, 0, 1),
          reason: 'DeviceGray 0.0 writes full black');
      // 16-bit: big-endian pairs, and 0xFFFF is full scale.
      expect(
          pdfImageColorants(
                  cos,
                  packed(16, [
                    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, //
                    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF
                  ]))!
              .uniformInk!
              .colorants,
          PdfColorants(0, 0, 0, 0));
    });

    test('a truncated or unreadable raster has no reading', () {
      // Fewer bytes than width * height * components.
      expect(
          pdfImageColorants(
              cos, image(const CosName('DeviceCMYK'), List.filled(8, 0))),
          isNull);
      // A bit depth the sample reader does not model.
      expect(
          pdfImageColorants(
              cos,
              CosStream(
                  CosDictionary({
                    'Subtype': const CosName('Image'),
                    'Width': const CosInteger(2),
                    'Height': const CosInteger(2),
                    'BitsPerComponent': const CosInteger(12),
                    'ColorSpace': const CosName('DeviceGray'),
                  }),
                  Uint8List(6))),
          isNull);
    });

    test('/Decode is applied to the samples', () {
      // GWG031 states the /Decode an /Indexed image would default to anyway;
      // an inverting one must actually invert.
      final inverted = pdfImageColorants(
          cos,
          image(const CosName('DeviceGray'), List.filled(4, 0), extra: {
            'Decode': CosArray([const CosInteger(1), const CosInteger(0)]),
          }))!;
      // DeviceGray 1.0 (white) writes no colorant; the raw sample 0 would be
      // full black.
      expect(inverted.uniformInk!.colorants, PdfColorants(0, 0, 0, 0));
    });
  });

  group('the composited substitute (pdfImageOverprintStream)', () {
    final backdrop = PdfColorants(0, 0, 0, 0,
        spots: const ['GWG Green'], tints: const [1.0]);
    const backdropColor = PdfColor(0.53, 0.79, 0.27);
    final spots = {
      'GWG Green': const [0.5, 0.0, 1.0, 0.0],
    };

    CosStream? substitute(CosStream source, {int mode = 1}) =>
        pdfImageOverprintStream(cos, source,
            backdrop: backdrop,
            backdropColor: backdropColor,
            mode: mode,
            spotEquivalents: spots);

    test('a sample that writes nothing keeps the backdrop\'s exact pixels', () {
      // Indexed/DeviceCMYK white over a spot backdrop under mode 1 - GWG031.
      final source = image(
          indexed(const CosName('DeviceCMYK'), [0, 0, 0, 0, 0, 0, 0, 255]),
          [0, 0, 0, 0]);
      final pixels = decodePdfImagePixels(cos, substitute(source)!)!;
      // Not a re-conversion of the composite: the backdrop's own rendered
      // colour, so the overprint is invisible rather than a shade off.
      expect(pixels.rgba[0], (backdropColor.red * 255).round());
      expect(pixels.rgba[1], (backdropColor.green * 255).round());
      expect(pixels.rgba[2], (backdropColor.blue * 255).round());
    });

    test('a sample that knocks the backdrop out keeps the raster\'s pixels',
        () {
      final source = image(const CosName('DeviceCMYK'),
          List.generate(16, (i) => i % 4 == 3 ? 255 : 0));
      final original = decodePdfImagePixels(cos, source)!;
      // DeviceCMYK 0/0/0/1 under mode 0 writes all four process colorants, so
      // a process backdrop is knocked out entirely and the result is the ink
      // painted over nothing - the raster's own pixels, not a re-conversion.
      final composited = decodePdfImagePixels(
          cos,
          pdfImageOverprintStream(cos, source,
              backdrop: PdfColorants(0.5, 0, 1, 0),
              backdropColor: const PdfColor(0.53, 0.79, 0.27),
              mode: 0,
              spotEquivalents: const {})!)!;
      expect(composited.rgba.sublist(0, 4), original.rgba.sublist(0, 4));
    });

    test('a varying raster composites per sample', () {
      // A K ramp: white writes nothing (green survives), full K writes black.
      final source = image(
          indexed(const CosName('DeviceCMYK'),
              [0, 0, 0, 0, 0, 0, 0, 128, 0, 0, 0, 255]),
          [0, 1, 2, 2]);
      final pixels = decodePdfImagePixels(cos, substitute(source)!)!;
      expect(pixels.rgba.sublist(0, 3), [
        for (final c in [
          backdropColor.red,
          backdropColor.green,
          backdropColor.blue
        ])
          (c * 255).round()
      ]);
      // The last sample is full K over the green: darker than the green, and
      // not the green itself.
      expect(pixels.rgba[12], lessThan(pixels.rgba[0]));
    });

    test('a spot raster contributes its own equivalent to the conversion', () {
      // A Separation raster overprinting a process backdrop: the composite
      // names a colorant no paint on the page produced, so converting it back
      // to sRGB needs the *image's* own tint transform, not just the page's.
      final source = image(
          CosArray([
            const CosName('Separation'),
            const CosName('PANTONE 349'),
            const CosName('DeviceCMYK'),
            exponential(const [1.0, 0.0, 0.8, 0.2]),
          ]),
          [255, 255, 255, 255]);
      final composited = decodePdfImagePixels(
          cos,
          pdfImageOverprintStream(cos, source,
              backdrop: PdfColorants(0, 0, 0, 0.5),
              backdropColor: const PdfColor(0.5, 0.5, 0.5),
              mode: 1,
              spotEquivalents: const {})!)!;
      // The spot at full tint plus the backdrop's 50% K - darker than the
      // backdrop, and green-dominant like the spot itself.
      final expected = colorantsToSrgb(
          PdfColorants(0, 0, 0, 0.5,
              spots: const ['PANTONE 349'], tints: const [1.0]),
          const {
            'PANTONE 349': [1.0, 0.0, 0.8, 0.2]
          });
      expect(composited.rgba[0], (expected.red * 255).round());
      expect(composited.rgba[1], (expected.green * 255).round());
      expect(composited.rgba[2], (expected.blue * 255).round());
    });

    test('bare paper needs no substitute at all', () {
      expect(
          pdfImageOverprintStream(
              cos, image(const CosName('DeviceCMYK'), List.filled(16, 128)),
              backdrop: PdfColorants.none,
              backdropColor: const PdfColor(1, 1, 1),
              mode: 1,
              spotEquivalents: const {}),
          isNull,
          reason:
              'overprinting onto no colorant leaves every sample as it was');
    });

    test('a colour-key /Mask declines - its ranges are in source samples', () {
      final source =
          image(const CosName('DeviceCMYK'), List.filled(16, 0), extra: {
        'Mask': CosArray([
          for (var i = 0; i < 8; i++) const CosInteger(0),
        ]),
      });
      expect(substitute(source), isNull);
    });

    test('a raster with no packable tuple still composites, just unmemoised',
        () {
      // 16-bit samples do not pack into the 32-bit memo key, so every pixel
      // converts. The result must be the same as the 8-bit path's.
      final source = CosStream(
          CosDictionary({
            'Subtype': const CosName('Image'),
            'Width': const CosInteger(2),
            'Height': const CosInteger(1),
            'BitsPerComponent': const CosInteger(16),
            'ColorSpace': const CosName('DeviceGray'),
          }),
          Uint8List.fromList([0xFF, 0xFF, 0xFF, 0xFF]));
      final pixels = decodePdfImagePixels(cos, substitute(source)!)!;
      // White gray writes no colorant, so the spot backdrop survives whole.
      expect(pixels.rgba.sublist(0, 3), [
        for (final c in [
          backdropColor.red,
          backdropColor.green,
          backdropColor.blue
        ])
          (c * 255).round()
      ]);
    });

    test('stops building past a handful of distinct backdrops', () {
      // One raster overprinted onto many different backdrops would otherwise
      // pin a full-size composited copy per backdrop for the document's life.
      final source = image(const CosName('DeviceCMYK'), List.filled(16, 32));
      var built = 0;
      for (var i = 1; i <= 8; i++) {
        final result = pdfImageOverprintStream(cos, source,
            backdrop: PdfColorants(i / 10, 0, 0, 0),
            backdropColor: const PdfColor(0.5, 0.5, 0.5),
            mode: 0,
            spotEquivalents: const {});
        if (result != null) built++;
      }
      expect(built, lessThan(8),
          reason: 'the per-raster memo is capped; past it the buffer declines '
              'rather than serving a substitute built for another backdrop');
    });

    test('the same (raster, backdrop, mode) returns the same stream object',
        () {
      // Load-bearing: the decoded-image cache keys XObject images by stream
      // identity, and a render's collect walk decodes ahead of its paint walk.
      final source = image(const CosName('DeviceCMYK'), List.filled(16, 64));
      expect(identical(substitute(source), substitute(source)), isTrue);
    });
  });

  group('the buffer\'s decision (PdfOverprintCompositor.image)', () {
    PdfPath rect(double l, double b, double r, double t) => PdfPath([
          PdfMoveTo(l, b),
          PdfLineTo(r, b),
          PdfLineTo(r, t),
          PdfLineTo(l, t),
          const PdfClosePath(),
        ]);

    PdfOverprintCompositor buffer() =>
        PdfOverprintCompositor.forPageBox(0, 0, 100, 100)!;

    /// Resolves an image draw, reporting the backdrop the buffer offered.
    PdfColorants? resolveOver(PdfOverprintCompositor c, PdfPath path,
            {PdfInkColorants? ink,
            bool hasColorants = true,
            bool overprint = true,
            bool opaque = true}) =>
        c.image<PdfColorants>(path,
            transform: PdfMatrix.identity,
            width: 1,
            height: 1,
            ink: ink,
            color: const PdfColor(0, 0, 0),
            hasColorants: hasColorants,
            overprint: overprint,
            mode: 1,
            opaque: opaque,
            resolve: (backdrop, _) => backdrop,
            resolveSpatial: (backdrop) => backdrop.at(0, 0)?.colorants);

    test('offers the backdrop under an overprinting raster', () {
      final c = buffer();
      c.fill(
          rect(0, 0, 100, 100),
          PdfFillRule.nonzero,
          const PdfColor(0.31, 0.45, 0.13),
          PdfInkColorants.deviceCmyk(0.5, 0, 1, 0.5),
          overprint: false,
          mode: 0,
          opaque: true);
      expect(
          resolveOver(c, rect(20, 20, 80, 80)), PdfColorants(0.5, 0, 1, 0.5));
    });

    test('declines a raster with no colorant reading, and marks it unknown',
        () {
      final c = buffer();
      c.fill(
          rect(0, 0, 100, 100),
          PdfFillRule.nonzero,
          const PdfColor(0.31, 0.45, 0.13),
          PdfInkColorants.deviceCmyk(0.5, 0, 1, 0.5),
          overprint: false,
          mode: 0,
          opaque: true);
      expect(resolveOver(c, rect(20, 20, 80, 80), hasColorants: false), isNull);
      // ...and a vector overprint landing on it now declines too: an RGB
      // raster's colorants are not knowable, so nothing may composite over it.
      expect(
          c.fill(
              rect(30, 30, 70, 70),
              PdfFillRule.nonzero,
              const PdfColor(0.6, 0.6, 0.63),
              PdfInkColorants.deviceCmyk(0, 0, 0, 0.5),
              overprint: true,
              mode: 0,
              opaque: true),
          isNull);
    });

    test('offers a spatial map for a raster straddling two backdrops', () {
      final c = buffer();
      c.fill(
          rect(0, 0, 50, 100),
          PdfFillRule.nonzero,
          const PdfColor(0.31, 0.45, 0.13),
          PdfInkColorants.deviceCmyk(0.5, 0, 1, 0.5),
          overprint: false,
          mode: 0,
          opaque: true);
      c.fill(rect(50, 0, 100, 100), PdfFillRule.nonzero,
          const PdfColor(0, 0, 0), PdfInkColorants.deviceCmyk(0, 0, 0, 1),
          overprint: false, mode: 0, opaque: true);
      expect(resolveOver(c, rect(20, 20, 80, 80)), PdfColorants(0.5, 0, 1, 0.5),
          reason: 'the spatial resolver samples the left backdrop at source '
              'pixel 0; later pixels carry the right backdrop');
    });

    test('a uniform opaque raster records as a backdrop of its own', () {
      final c = buffer();
      final ink = PdfInkColorants.deviceCmyk(0, 0, 0, 1);
      // Not overprinting: the raster knocks out, and what it leaves behind is
      // its own colorants - which the next overprint composites against.
      resolveOver(c, rect(0, 0, 100, 100), ink: ink, overprint: false);
      expect(
          c.fill(
              rect(20, 20, 80, 80),
              PdfFillRule.nonzero,
              const PdfColor(0, 0.7, 0.9),
              PdfInkColorants.deviceCmyk(1, 0, 0, 0),
              overprint: true,
              mode: 1,
              opaque: true),
          isNotNull,
          reason: 'cyan over the raster\'s black keeps the black');
    });

    test('a varying raster still reads as unknown to a later overprint', () {
      final c = buffer();
      resolveOver(c, rect(0, 0, 100, 100), overprint: false);
      expect(
          c.fill(
              rect(20, 20, 80, 80),
              PdfFillRule.nonzero,
              const PdfColor(0, 0.7, 0.9),
              PdfInkColorants.deviceCmyk(1, 0, 0, 0),
              overprint: true,
              mode: 1,
              opaque: true),
          isNull,
          reason: 'the buffer holds one vector per cell, so a raster whose '
              'colorants vary cannot be a backdrop');
    });

    test('declines while a transparency group is open', () {
      final c = buffer();
      c.fill(
          rect(0, 0, 100, 100),
          PdfFillRule.nonzero,
          const PdfColor(0.31, 0.45, 0.13),
          PdfInkColorants.deviceCmyk(0.5, 0, 1, 0.5),
          overprint: false,
          mode: 0,
          opaque: true);
      c.beginIsolated();
      expect(resolveOver(c, rect(20, 20, 80, 80)), isNull);
      c.endIsolated();
    });

    group('stencils', () {
      /// Paints a spot-green backdrop and stencils [ink] over part of it.
      PdfColor? stencilOver(PdfInkColorants? ink,
          {bool overprint = true, PdfPath? backdrop}) {
        final c = buffer();
        final spot = PdfColorSpace.parse(
            cos,
            CosArray([
              const CosName('Separation'),
              const CosName('GWG Green'),
              const CosName('DeviceCMYK'),
              exponential(const [0.5, 0, 1, 0]),
            ]));
        const green = PdfColor(0.53, 0.79, 0.27);
        c.fill(backdrop ?? rect(0, 0, 100, 100), PdfFillRule.nonzero, green,
            spot.inkColorants(const [1.0]),
            overprint: false, mode: 0, opaque: true);
        return c.stencil(rect(20, 20, 80, 80), const PdfColor(0, 0, 0), ink,
            overprint: overprint, mode: 1, opaque: true);
      }

      test('a stencil paints the fill colour composited over the backdrop', () {
        // 50% K through the mask over a spot green: DeviceCMYK writes the
        // process colorants, the spot survives, and the result is a colour the
        // page never painted - so it converts through the separations model.
        final resolved = stencilOver(PdfInkColorants.deviceCmyk(0, 0, 0, 0.5));
        expect(resolved, isNotNull);
        expect(resolved, isNot(const PdfColor(0, 0, 0)),
            reason: 'the stencil must not knock the spot backdrop out');
      });

      test('a stencil writing nothing new repaints the backdrop exactly', () {
        // The GWG020 shape: the stencil colour is the backdrop's own spot at
        // the same tint, so a faithful overprint is invisible.
        final spot = PdfColorSpace.parse(
            cos,
            CosArray([
              const CosName('Separation'),
              const CosName('GWG Green'),
              const CosName('DeviceCMYK'),
              exponential(const [0.5, 0, 1, 0]),
            ]));
        expect(stencilOver(spot.inkColorants(const [1.0])),
            const PdfColor(0.53, 0.79, 0.27));
      });

      test('declines without overprint, without ink, and over two backdrops',
          () {
        expect(
            stencilOver(PdfInkColorants.deviceCmyk(0, 0, 0, 0.5),
                overprint: false),
            isNull);
        expect(stencilOver(null), isNull,
            reason: 'an RGB fill colour has no colorant reading');
        expect(
            stencilOver(PdfInkColorants.deviceCmyk(0, 0, 0, 0.5),
                backdrop: rect(0, 0, 50, 100)),
            isNull,
            reason: 'half the quad is bare paper, so "wherever the mask '
                'paints" is not one colour');
      });

      test('never becomes a backdrop of its own', () {
        final c = buffer();
        c.fill(
            rect(0, 0, 100, 100),
            PdfFillRule.nonzero,
            const PdfColor(0.31, 0.45, 0.13),
            PdfInkColorants.deviceCmyk(0.5, 0, 1, 0.5),
            overprint: false,
            mode: 0,
            opaque: true);
        c.stencil(rect(0, 0, 100, 100), const PdfColor(0, 0, 0),
            PdfInkColorants.deviceCmyk(0, 0, 0, 1),
            overprint: false, mode: 0, opaque: true);
        expect(
            c.fill(
                rect(20, 20, 80, 80),
                PdfFillRule.nonzero,
                const PdfColor(0, 0.7, 0.9),
                PdfInkColorants.deviceCmyk(1, 0, 0, 0),
                overprint: true,
                mode: 1,
                opaque: true),
            isNull,
            reason: 'the backdrop survives wherever the mask is clear, so the '
                'quad reads as unknown');
      });
    });
  });
}
