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

  group('spatial image overprint (a per-pixel backdrop map)', () {
    final process = PdfColorants(0.5, 0, 1, 0);
    const processColor = PdfColor(0.31, 0.45, 0.13);
    final spot = PdfColorants(0, 0, 0, 0,
        spots: const ['GWG Green'], tints: const [1.0]);
    const spotColor = PdfColor(0.53, 0.79, 0.27);
    final spots = {
      'GWG Green': const [0.5, 0.0, 1.0, 0.0],
    };

    /// A map over [process] (entry 1) and [spot] (entry 2); entry 0 is the
    /// unknown cell.
    PdfColorantBackdropMap backdropMap(
            int width, int height, List<int> entries) =>
        PdfColorantBackdropMap(
          width: width,
          height: height,
          indices: Uint16List.fromList(entries),
          colorants: [null, process, spot],
          colors: const [PdfColor(1, 1, 1), processColor, spotColor],
        );

    CosStream? spatial(CosStream source, PdfColorantBackdropMap map,
            {int mode = 1}) =>
        pdfImageOverprintStream(cos, source,
            spatialBackdrop: map, mode: mode, spotEquivalents: spots);

    PdfPath rect(double l, double b, double r, double t) => PdfPath([
          PdfMoveTo(l, b),
          PdfLineTo(r, b),
          PdfLineTo(r, t),
          PdfLineTo(l, t),
          const PdfClosePath(),
        ]);

    test('the compositor gives each backdrop one entry, in first-seen order',
        () {
      final c = PdfOverprintCompositor.forPageBox(0, 0, 100, 100)!;
      final processInk = PdfInkColorants.deviceCmyk(0.5, 0, 1, 0);
      final spotInk = PdfInkColorants(
          colorants: spot,
          processMask: 0,
          overprintModeApplies: false,
          spotEquivalents: const [
            [0.5, 0.0, 1.0, 0.0]
          ]);
      // Process | paper | spot | paper | process, one column per source pixel.
      for (final (l, r, ink, color) in [
        (0.0, 20.0, processInk, processColor),
        (40.0, 60.0, spotInk, spotColor),
        (80.0, 100.0, processInk, processColor),
      ]) {
        c.fill(rect(l, 0, r, 100), PdfFillRule.nonzero, color, ink,
            overprint: false, mode: 0, opaque: true);
      }
      PdfColorantBackdropMap? sampled;
      c.image<Object>(rect(0, 0, 100, 100),
          transform: const PdfMatrix(100, 0, 0, 100, 0, 0),
          width: 5,
          height: 1,
          ink: null,
          color: const PdfColor(0, 0, 0),
          hasColorants: true,
          overprint: true,
          mode: 1,
          opaque: true,
          resolve: (_, __) => null,
          resolveSpatial: (map) {
            sampled = map;
            return null;
          });
      expect(sampled, isNotNull);
      expect(sampled!.indices, [1, 2, 3, 2, 1],
          reason: 'both process columns share one entry, as do both paper '
              'columns');
      expect(sampled!.colorants, [null, process, PdfColorants.none, spot]);
      expect(sampled!.colors[1], processColor);
      expect(sampled!.colors[3], spotColor);
    });

    test('equal maps built apart hash alike and share one substitute', () {
      // The collect and paint walks each sample their own map. The substitute
      // memo must see the two as one key, or the paint walk would draw a
      // stream the collect walk never decoded.
      final entries = [1, 2, 2, 1, 1, 2];
      final a = backdropMap(3, 2, entries);
      final b = backdropMap(3, 2, List.of(entries));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(backdropMap(3, 2, [1, 2, 2, 1, 2, 2])));
      final source = image(
          const CosName('DeviceCMYK'),
          [
            for (var i = 0; i < 6; i++) ...[0, 0, 0, 128]
          ],
          width: 3);
      final first = spatial(source, a);
      expect(first, isNotNull);
      expect(identical(spatial(source, b), first), isTrue);
    });

    /// [source]'s substitute over one uniform backdrop: the oracle for every
    /// spatial pixel that sits on that backdrop.
    Uint8List uniformOver(CosStream source, PdfColorants backdrop,
            PdfColor backdropColor, int mode) =>
        pdfImageOverprintStream(cos, source,
                backdrop: backdrop,
                backdropColor: backdropColor,
                mode: mode,
                spotEquivalents: spots)!
            .rawBytes;

    /// Composites [source] over a [width] x [height] map of [entries] and
    /// checks every pixel against the uniform substitute for its own entry,
    /// and the whole raster against the builder's unmemoised walk.
    void expectPerEntry(
        CosStream Function() source, int width, int height, List<int> entries) {
      for (final mode in [0, 1]) {
        final memoised =
            spatial(source(), backdropMap(width, height, entries), mode: mode)!
                .rawBytes;
        // A map one column wider than the image no longer matches it pixel
        // for pixel, so the builder takes its unmemoised walk - and never
        // samples the extra column, so the answer must be the same bytes.
        final wide = [
          for (var y = 0; y < height; y++) ...[
            ...entries.sublist(y * width, (y + 1) * width),
            1,
          ]
        ];
        final unmemoised =
            spatial(source(), backdropMap(width + 1, height, wide), mode: mode)!
                .rawBytes;
        expect(memoised, unmemoised, reason: 'mode $mode');
        final overProcess = uniformOver(source(), process, processColor, mode);
        final overSpot = uniformOver(source(), spot, spotColor, mode);
        for (var i = 0; i < width * height; i++) {
          final oracle = entries[i] == 1 ? overProcess : overSpot;
          expect(memoised.sublist(i * 3, i * 3 + 3),
              oracle.sublist(i * 3, i * 3 + 3),
              reason: 'mode $mode, pixel $i over entry ${entries[i]}');
        }
      }
    }

    /// `[/DeviceN [/Cyan /PANTONE 349] /DeviceCMYK {0 0}]` - a process
    /// colorant and a spot the page has no equivalent for yet, so the image
    /// teaches the builder one.
    CosArray cyanAndSpot() => CosArray([
          const CosName('DeviceN'),
          CosArray([const CosName('Cyan'), const CosName('PANTONE 349')]),
          const CosName('DeviceCMYK'),
          CosStream(
              CosDictionary({
                'FunctionType': const CosInteger(4),
                'Domain': CosArray([
                  for (var i = 0; i < 2; i++) ...[
                    const CosInteger(0),
                    const CosInteger(1)
                  ]
                ]),
                'Range': CosArray([
                  for (var i = 0; i < 4; i++) ...[
                    const CosInteger(0),
                    const CosInteger(1)
                  ]
                ]),
              }),
              Uint8List.fromList('{ 0 0 }'.codeUnits)),
        ]);

    const entries = [
      1, 2, 2, 1, //
      2, 1, 1, 2, //
      1, 1, 2, 2,
    ];

    test('an Indexed raster composites each pixel over its own backdrop', () {
      // GWG080-082's shape: a small palette repeated across two backdrops.
      expectPerEntry(
          () => image(indexed(cyanAndSpot(), [0, 0, 255, 0, 128, 255]),
              [0, 1, 2, 1, 2, 2, 0, 1, 1, 0, 2, 2],
              width: 4, height: 3),
          4,
          3,
          entries);
    });

    test('a DeviceN raster composites each pixel over its own backdrop', () {
      expectPerEntry(
          () => image(
              cyanAndSpot(),
              [
                for (final t in [0, 1, 2, 1, 2, 2, 0, 1, 1, 0, 2, 2])
                  ...[
                    [0, 0],
                    [255, 0],
                    [128, 255]
                  ][t]
              ],
              width: 4,
              height: 3),
          4,
          3,
          entries);
    });

    test('four 8-bit components with high bytes stay distinct keys', () {
      // Packed tuples at and past 2^31: a key that wrapped (as bitwise
      // packing does on the web) would alias two of these.
      const tuples = [
        [0xFF, 0xF0, 0x80, 0xFF],
        [0xFF, 0xFF, 0xFF, 0xFF],
        [0x00, 0x00, 0x00, 0xFF],
        [0x80, 0x00, 0xF7, 0x00],
      ];
      expectPerEntry(
          () => image(const CosName('DeviceCMYK'),
              [for (var i = 0; i < 12; i++) ...tuples[(i * 3 + i ~/ 4) % 4]],
              width: 4, height: 3),
          4,
          3,
          entries);
    });

    test('an unknown cell declines even when its tuple is already memoised',
        () {
      CosStream uniformRaster() => image(
          const CosName('DeviceCMYK'),
          [
            for (var i = 0; i < 3; i++) ...[0, 0, 0, 128]
          ],
          width: 3,
          height: 1);
      expect(spatial(uniformRaster(), backdropMap(3, 1, [1, 2, 1])), isNotNull);
      expect(spatial(uniformRaster(), backdropMap(3, 1, [1, 1, 0])), isNull);
      expect(spatial(uniformRaster(), backdropMap(3, 1, [2, 0, 2])), isNull);
      expect(spatial(uniformRaster(), backdropMap(3, 1, [1, 3, 1])), isNull,
          reason: 'an entry past the palette is unknown too');
    });
  });

  group('single-component rasters (the per-sample table)', () {
    final backdrop = PdfColorants(0, 0, 0, 0,
        spots: const ['GWG Green'], tints: const [1.0]);
    const backdropColor = PdfColor(0.53, 0.79, 0.27);
    final spots = {
      'GWG Green': const [0.5, 0.0, 1.0, 0.0],
    };

    /// A [bits]-deep one-component raster over [space] holding [samples] row
    /// by row, each row padded out to a whole byte as the format stores it.
    CosStream raster(CosObject space, int bits, int width, List<int> samples,
        {CosArray? decode}) {
      final height = samples.length ~/ width;
      final rowBytes = (width * bits + 7) ~/ 8;
      final data = Uint8List(rowBytes * height);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final bit = x * bits;
          data[y * rowBytes + (bit >> 3)] |=
              samples[y * width + x] << (8 - bits - (bit & 7));
        }
      }
      return CosStream(
          CosDictionary({
            'Type': const CosName('XObject'),
            'Subtype': const CosName('Image'),
            'Width': CosInteger(width),
            'Height': CosInteger(height),
            'BitsPerComponent': CosInteger(bits),
            'ColorSpace': space,
            if (decode != null) 'Decode': decode,
          }),
          data);
    }

    Uint8List composited(CosStream source, int mode) =>
        pdfImageOverprintStream(cos, source,
                backdrop: backdrop,
                backdropColor: backdropColor,
                mode: mode,
                spotEquivalents: spots)!
            .rawBytes;

    /// Checks a [width] x 3 raster of every [bits]-deep value against a
    /// per-sample reference: a one-pixel raster holding just that sample,
    /// which no table can answer from another pixel.
    void expectPerSample(CosObject Function() space, int bits, int width,
        {CosArray? decode}) {
      final count = width * 3;
      final samples = [
        for (var i = 0; i < count; i++) (i * 7 + i ~/ 3) % (1 << bits)
      ];
      for (final mode in [0, 1]) {
        final whole = composited(
            raster(space(), bits, width, samples, decode: decode), mode);
        for (var i = 0; i < count; i++) {
          expect(
              whole.sublist(i * 3, i * 3 + 3),
              composited(
                  raster(space(), bits, 1, [samples[i]], decode: decode), mode),
              reason: '$bits-bit mode $mode, sample $i = ${samples[i]}');
        }
      }
    }

    CosArray inverted(int top) =>
        CosArray([CosInteger(top), const CosInteger(0)]);

    for (final (bits, width) in [(1, 5), (2, 3), (4, 3), (8, 5)]) {
      test('$bits-bit gray at an odd width matches a per-sample composite', () {
        expectPerSample(() => const CosName('DeviceGray'), bits, width);
        expectPerSample(() => const CosName('DeviceGray'), bits, width,
            decode: inverted(1));
      });

      test('$bits-bit Indexed at an odd width matches a per-sample composite',
          () {
        final top = (1 << bits) - 1;
        CosObject space() => CosArray([
              const CosName('Indexed'),
              const CosName('DeviceCMYK'),
              CosInteger(top),
              CosString(Uint8List.fromList([
                for (var i = 0; i <= top; i++) ...[
                  (i * 37) & 0xff,
                  0,
                  (i * 11) & 0xff,
                  255 - i
                ]
              ])),
            ]);
        expectPerSample(space, bits, width);
        expectPerSample(space, bits, width, decode: inverted(top));
      });
    }

    test('a 4-bit Separation learns its spot before any sample is reused', () {
      // The spot is not among the page's equivalents, so the first composite
      // teaches the builder one; every later sample must convert with it.
      expectPerSample(
          () => CosArray([
                const CosName('Separation'),
                const CosName('PANTONE 349'),
                const CosName('DeviceCMYK'),
                exponential(const [1.0, 0.0, 0.8, 0.2]),
              ]),
          4,
          7);
    });
  });
}
