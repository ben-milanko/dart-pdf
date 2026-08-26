// Unit coverage for the CMYK/spot colorant buffer that makes overprint
// faithful (issue #502).
//
// Three layers, each pinned directly rather than through a rendered page:
//
//   1. the ink-space composite rule ([PdfInkColorants.over]) - which colorants
//      a colour space writes, and what the overprint mode does to that;
//   2. the colorant reading of real PDF colour spaces
//      ([PdfColorSpace.inkColorants]), including a DeviceN naming a spot;
//   3. the compositor itself ([PdfOverprintCompositor]) - the rasterized
//      backdrop lookup and the "reuse the exact colour this reproduces" rule
//      that keeps a resolved overprint pixel-identical to the paint it
//      matches.
//
// The GWG030 render guard (dart_pdf_editor overprint_render_test.dart) covers
// the same ground end to end; these are the pieces, so a failure names one.
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

  /// `[/Separation name /DeviceCMYK tint]`.
  PdfColorSpace separation(String name, List<double> full) =>
      PdfColorSpace.parse(
          cos,
          CosArray([
            const CosName('Separation'),
            CosName(name),
            const CosName('DeviceCMYK'),
            exponential(full),
          ]));

  group('the composite rule (PdfInkColorants.over)', () {
    // The GWG030 backdrops: a DeviceN spot green (Black 50% + a spot at full
    // tint) and a DeviceCMYK green that renders as the same colour.
    final spotGreen = PdfColorants(0, 0, 0, 0.5,
        spots: const ['GWG Green'], tints: const [1.0]);
    final cmykGreen = PdfColorants(0.5, 0, 1, 0.5);

    test('DeviceCMYK writes all four components under overprint mode 0', () {
      final ink = PdfInkColorants.deviceCmyk(0, 0, 0, 0.5);
      // Over the spot backdrop the spot colorant is untouched and the process
      // colorants it writes match what was there - nothing changes.
      expect(ink.over(spotGreen, 0), spotGreen);
      // Over the process backdrop the same ink knocks C/M/Y out to zero.
      expect(ink.over(cmykGreen, 0), PdfColorants(0, 0, 0, 0.5));
    });

    test('overprint mode 1 leaves a DeviceCMYK zero component alone', () {
      final ink = PdfInkColorants.deviceCmyk(0, 0, 0, 0.5);
      // The very distinction the mode exists for: the same ink over the same
      // backdrop, differing only in OPM.
      expect(ink.over(cmykGreen, 1), cmykGreen);
      expect(ink.over(cmykGreen, 0), PdfColorants(0, 0, 0, 0.5));
    });

    test('DeviceGray writes (0, 0, 0, 1 - gray) whatever the mode', () {
      final ink = PdfInkColorants.deviceGray(0.5);
      expect(ink.colorants, PdfColorants(0, 0, 0, 0.5));
      // §8.6.7.3 scopes the mode-1 zero rule to DeviceCMYK, so a neutral grey
      // knocks a process backdrop out under either mode (GWG030 e and k).
      for (final mode in [0, 1]) {
        expect(ink.over(cmykGreen, mode), PdfColorants(0, 0, 0, 0.5),
            reason: 'gray over CMYK, OPM $mode');
        expect(ink.over(spotGreen, mode), spotGreen,
            reason: 'gray over spot, OPM $mode');
      }
    });

    test('a Separation writes only the colorant it names', () {
      final ink = separation('Black', const [0, 0, 0, 1]).inkColorants([0.5])!;
      expect(ink.colorants, PdfColorants(0, 0, 0, 0.5));
      // C, M and Y are not this space's to write, so the process backdrop
      // survives (GWG030 f and l).
      expect(ink.over(cmykGreen, 0), cmykGreen);
      expect(ink.over(spotGreen, 0), spotGreen);
    });

    test('a Separation writes a zero tint under either mode', () {
      // The mode-1 rule is DeviceCMYK's alone; treating a DeviceN as if it had
      // been converted to DeviceCMYK upfront is what GWG190's patch c grades.
      final ink = separation('Black', const [0, 0, 0, 1]).inkColorants([0])!;
      for (final mode in [0, 1]) {
        expect(ink.over(cmykGreen, mode), PdfColorants(0.5, 0, 1, 0),
            reason: 'OPM $mode');
      }
    });

    test('/All writes every colorant the device has, /None writes nothing', () {
      final all = separation('All', const [0, 0, 0, 1]).inkColorants([0.4])!;
      expect(
          all.over(spotGreen, 0),
          PdfColorants(0.4, 0.4, 0.4, 0.4,
              spots: const ['GWG Green'], tints: const [0.4]));
      final none = separation('None', const [0, 0, 0, 1]).inkColorants([0.7])!;
      expect(none.writesNothing, isTrue);
    });

    test('an ink and a backdrop naming different spots keep both', () {
      // The merge of two sorted spot lists, which is what lets a page's
      // second spot colour overprint the first without either erasing it.
      final ink = PdfInkColorants(
        colorants: PdfColorants(0, 0, 0, 0,
            spots: const ['Spot B'], tints: const [0.6]),
        processMask: 0,
        overprintModeApplies: false,
      );
      expect(
          ink.over(
              PdfColorants(0.1, 0, 0, 0,
                  spots: const ['Spot A'], tints: const [0.3]),
              0),
          PdfColorants(0.1, 0, 0, 0,
              spots: const ['Spot A', 'Spot B'], tints: const [0.3, 0.6]),
          reason: 'neither spot is the other\'s to write');
      // Where they name the same colorant, the ink wins - that is the one
      // channel it is painting.
      expect(
          ink.over(
              PdfColorants(0, 0, 0, 0,
                  spots: const ['Spot B'], tints: const [0.3]),
              0),
          PdfColorants(0, 0, 0, 0,
              spots: const ['Spot B'], tints: const [0.6]));
    });
  });

  group('converting a composite back to sRGB', () {
    // Only reached for a colorant combination no single paint produced - the
    // compositor reuses the backdrop's or the ink's own rendered colour
    // otherwise - so nothing else exercises it.
    test('a spot contributes its CMYK equivalent, scaled by tint', () {
      final vector = PdfColorants(0, 0, 0, 0.2,
          spots: const ['GWG Green'], tints: const [0.5]);
      // Half a tint of a spot that is full yellow + half cyan, over 20% black.
      final rendered = colorantsToSrgb(vector, {
        'GWG Green': const [1.0, 0, 1.0, 0],
      });
      expect(rendered, PdfColor.cmyk(0.5, 0, 0.5, 0.2));
    });

    test('overlapping inks accumulate and clamp at full ink', () {
      final vector =
          PdfColorants(0.7, 0, 0, 0, spots: const ['Spot'], tints: const [1.0]);
      expect(
          colorantsToSrgb(vector, {
            'Spot': const [0.8, 0, 0, 0]
          }),
          PdfColor.cmyk(1, 0, 0, 0));
    });

    test('a spot with no known equivalent contributes nothing', () {
      // A composite can name a spot whose space never reached this compositor
      // (it came from the backdrop). Dropping it is the honest fallback.
      final vector = PdfColorants(0, 0, 0, 0.4,
          spots: const ['Unknown'], tints: const [1]);
      expect(colorantsToSrgb(vector, const {}), PdfColor.cmyk(0, 0, 0, 0.4));
    });
  });

  group('colorant readings of colour spaces', () {
    test('DeviceRGB and ICCBased have none', () {
      expect(
          PdfColorSpace.parse(cos, const CosName('DeviceRGB'))
              .inkColorants(const [1, 0, 0]),
          isNull);
      expect(
          PdfColorSpace.parse(
              cos,
              CosArray([
                const CosName('ICCBased'),
                CosStream(
                    CosDictionary({'N': const CosInteger(4)}), Uint8List(0)),
              ])).inkColorants(const [0, 0, 0, 1]),
          isNull,
          reason: 'an ICC colour is managed, not a colorant list');
    });

    test('a DeviceN splits process colorants from spots', () {
      final space = PdfColorSpace.parse(
          cos,
          CosArray([
            const CosName('DeviceN'),
            CosArray([const CosName('Black'), const CosName('GWG Green')]),
            const CosName('DeviceCMYK'),
            exponential(const [0, 0, 0, 1]),
          ]));
      final ink = space.inkColorants(const [0.5, 1])!;
      expect(
          ink.colorants,
          PdfColorants(0, 0, 0, 0.5,
              spots: const ['GWG Green'], tints: const [1.0]));
      // Only Black is a process colorant here, so C/M/Y stay the backdrop's.
      expect(
          ink.over(PdfColorants(0.5, 0, 1, 0.2), 0),
          PdfColorants(0.5, 0, 1, 0.5,
              spots: const ['GWG Green'], tints: const [1.0]));
    });

    test('spot names are sorted so equal colorants compare equal', () {
      CosObject deviceN(List<String> names) => CosArray([
            const CosName('DeviceN'),
            CosArray([for (final n in names) CosName(n)]),
            const CosName('DeviceCMYK'),
            exponential(const [0, 0, 0, 1]),
          ]);
      final ab = PdfColorSpace.parse(cos, deviceN(['Spot A', 'Spot B']))
          .inkColorants(const [0.25, 0.75])!;
      final ba = PdfColorSpace.parse(cos, deviceN(['Spot B', 'Spot A']))
          .inkColorants(const [0.75, 0.25])!;
      expect(ab.colorants, ba.colorants);
    });
  });

  group('the compositor', () {
    /// A 100x100pt page's buffer.
    PdfOverprintCompositor buffer() =>
        PdfOverprintCompositor.forPageBox(0, 0, 100, 100)!;

    PdfPath rect(double l, double b, double r, double t) => PdfPath([
          PdfMoveTo(l, b),
          PdfLineTo(r, b),
          PdfLineTo(r, t),
          PdfLineTo(l, t),
          const PdfClosePath(),
        ]);

    PdfColor? fill(PdfOverprintCompositor c, PdfPath path, PdfColor color,
            PdfInkColorants? ink, {bool overprint = false, int mode = 0}) =>
        c.fill(path, PdfFillRule.nonzero, color, ink,
            overprint: overprint, mode: mode, opaque: true);

    test('an ink that changes no colorant repaints the backdrop exactly', () {
      final c = buffer();
      final spot = PdfColorSpace.parse(
          cos,
          CosArray([
            const CosName('DeviceN'),
            CosArray([const CosName('Black'), const CosName('GWG Green')]),
            const CosName('DeviceCMYK'),
            exponential(const [0, 0, 0, 1]),
          ]));
      const backdropColor = PdfColor(0.31, 0.45, 0.13);
      fill(c, rect(0, 0, 100, 100), backdropColor,
          spot.inkColorants(const [0.5, 1]));
      // 50% K overprinting the spot green writes only colorants it already
      // carries, so the result must be the backdrop's own rendered colour -
      // not a re-conversion that would land a shade away and show as a marker.
      final resolved = fill(
          c,
          rect(20, 20, 80, 80),
          const PdfColor(0.6, 0.6, 0.63),
          PdfInkColorants.deviceCmyk(0, 0, 0, 0.5),
          overprint: true);
      expect(resolved, backdropColor);
    });

    test('a neutral ink knocks a DeviceCMYK backdrop out to its own colour',
        () {
      final c = buffer();
      fill(c, rect(0, 0, 100, 100), const PdfColor(0.31, 0.45, 0.13),
          PdfInkColorants.deviceCmyk(0.5, 0, 1, 0.5));
      const inkColor = PdfColor(0.5, 0.5, 0.5);
      final resolved = fill(
          c, rect(20, 20, 80, 80), inkColor, PdfInkColorants.deviceGray(0.5),
          overprint: true);
      expect(resolved, inkColor);
    });

    test('overprint mode 1 keeps the process backdrop the same ink knocks out',
        () {
      PdfColor? run(int mode) {
        final c = buffer();
        const backdropColor = PdfColor(0.31, 0.45, 0.13);
        fill(c, rect(0, 0, 100, 100), backdropColor,
            PdfInkColorants.deviceCmyk(0.5, 0, 1, 0.5));
        return fill(c, rect(20, 20, 80, 80), const PdfColor(0.6, 0.6, 0.63),
            PdfInkColorants.deviceCmyk(0, 0, 0, 0.5),
            overprint: true, mode: mode);
      }

      expect(run(1), const PdfColor(0.31, 0.45, 0.13));
      expect(run(0), const PdfColor(0.6, 0.6, 0.63));
    });

    test('declines over a backdrop it has no colorant reading for', () {
      final c = buffer();
      // An image, a shading or an RGB paint leaves "unknown" behind.
      c.markUnknownBox(0, 0, 100, 100);
      expect(
          fill(c, rect(20, 20, 80, 80), const PdfColor(0.6, 0.6, 0.63),
              PdfInkColorants.deviceCmyk(0, 0, 0, 0.5),
              overprint: true),
          isNull);
    });

    test('declines while a transparency group is open', () {
      final c = buffer();
      fill(c, rect(0, 0, 100, 100), const PdfColor(0.31, 0.45, 0.13),
          PdfInkColorants.deviceCmyk(0.5, 0, 1, 0.5));
      c.beginIsolated();
      expect(
          fill(c, rect(10, 10, 45, 90), const PdfColor(0.5, 0.5, 0.5),
              PdfInkColorants.deviceGray(0.5),
              overprint: true),
          isNull,
          reason: 'group content composites through its own buffer');
      c.endIsolated();
      // The group's own area is now unknown (what it composited to is the
      // group's business), but the page outside it still has its colorants.
      expect(
          fill(c, rect(10, 10, 45, 90), const PdfColor(0.5, 0.5, 0.5),
              PdfInkColorants.deviceGray(0.5),
              overprint: true),
          isNull);
      expect(
          fill(c, rect(55, 10, 90, 90), const PdfColor(0.5, 0.5, 0.5),
              PdfInkColorants.deviceGray(0.5),
              overprint: true),
          const PdfColor(0.5, 0.5, 0.5));
    });

    test('a clip keeps a draw from recording colorants outside it', () {
      final c = buffer();
      c.save();
      c.clipPath(rect(0, 0, 50, 100), PdfFillRule.nonzero);
      // The backdrop paint is clipped to the left half...
      fill(c, rect(0, 0, 100, 100), const PdfColor(0.31, 0.45, 0.13),
          PdfInkColorants.deviceCmyk(0.5, 0, 1, 0.5));
      c.restore();
      // ...so an overprint entirely in the right half lands on bare paper,
      // where 50% grey simply is 50% grey.
      const inkColor = PdfColor(0.5, 0.5, 0.5);
      expect(
          fill(c, rect(60, 20, 90, 80), inkColor,
              PdfInkColorants.deviceGray(0.5),
              overprint: true),
          inkColor);
    });

    test('a non-rectangular clip keeps its full scanline extent', () {
      final c = buffer();
      // In raster order the first scanline is the triangle's narrow tip. A
      // clip bound derived from that first run alone collapses the mask to a
      // one-cell strip and loses the wide body (GWG020's X exposed this).
      final triangle = PdfPath([
        const PdfMoveTo(50, 100),
        const PdfLineTo(100, 0),
        const PdfLineTo(0, 0),
        const PdfClosePath(),
      ]);
      const backdrop = PdfColor(0.31, 0.45, 0.13);
      c.save();
      c.clipPath(triangle, PdfFillRule.nonzero);
      fill(c, rect(0, 0, 100, 100), backdrop,
          PdfInkColorants.deviceCmyk(0.5, 0, 1, 0));
      c.restore();

      // This box is well inside the wide lower body but far outside the
      // first scanline's tip. OPM 1 white preserves the recorded backdrop.
      expect(
          fill(c, rect(20, 10, 30, 20), const PdfColor(1, 1, 1),
              PdfInkColorants.deviceCmyk(0, 0, 0, 0),
              overprint: true, mode: 1),
          backdrop);
    });

    test('a gradient over one backdrop is precomposited smoothly', () {
      final c = buffer();
      const backdrop = PdfColor(0.31, 0.45, 0.13);
      fill(c, rect(0, 0, 100, 100), backdrop,
          PdfInkColorants.deviceCmyk(0.5, 0, 1, 0));
      final gradient = PdfGradient(
        isRadial: false,
        coords: const [0, 0, 100, 0],
        colors: const [PdfColor(1, 1, 1), PdfColor(0.99, 0.99, 0.98)],
        stops: const [0, 1],
        transform: PdfMatrix.identity,
        inkAt: (t) => PdfInkColorants(
          colorants: PdfColorants(0, 0, 0, 0,
              spots: const ['Spot'], tints: [0.01 + 0.01 * t]),
          processMask: 0,
          overprintModeApplies: false,
          spotEquivalents: const [
            [0.5, 0, 1, 0]
          ],
        ),
      );
      expect(
          c.gradient(rect(0, 0, 100, 100), gradient,
              overprint: true, mode: 1, opaque: true),
          isTrue);
      final substitute = c.takeGradientSubstitute();
      expect(substitute, isNotNull);
      expect(substitute!.colors, hasLength(2));
      expect(substitute.colors.first, isNot(const PdfColor(1, 1, 1)));
      expect(c.takeGradientSpatialPaint(), isNull,
          reason: 'a uniform backdrop needs no cell-sized correction paths');
    });

    test('a spot backdrop and a process backdrop of one colour diverge', () {
      // The whole reason for the buffer, stated as one assertion: identical
      // pixels, identical ink, opposite outcomes.
      const green = PdfColor(0.31, 0.45, 0.13);
      const inkColor = PdfColor(0.5, 0.5, 0.5);
      final spot = PdfColorSpace.parse(
          cos,
          CosArray([
            const CosName('DeviceN'),
            CosArray([const CosName('Black'), const CosName('GWG Green')]),
            const CosName('DeviceCMYK'),
            exponential(const [0, 0, 0, 1]),
          ]));

      final overSpot = buffer();
      fill(overSpot, rect(0, 0, 100, 100), green,
          spot.inkColorants(const [0.5, 1]));
      final overProcess = buffer();
      fill(overProcess, rect(0, 0, 100, 100), green,
          PdfInkColorants.deviceCmyk(0.5, 0, 1, 0.5));

      for (final c in [overSpot, overProcess]) {
        expect(
            fill(c, rect(20, 20, 80, 80), inkColor,
                PdfInkColorants.deviceGray(0.5),
                overprint: true),
            c == overSpot ? green : inkColor);
      }
    });

    test('a stroke exposes exact regions when its backdrop varies', () {
      const green = PdfColor(0.31, 0.45, 0.13);
      const inkColor = PdfColor(0.5, 0.5, 0.5);
      final spot = PdfColorSpace.parse(
          cos,
          CosArray([
            const CosName('DeviceN'),
            CosArray([const CosName('Black'), const CosName('GWG Green')]),
            const CosName('DeviceCMYK'),
            exponential(const [0, 0, 0, 1]),
          ]));
      final c = buffer();
      fill(c, rect(0, 0, 50, 100), green, spot.inkColorants(const [0.5, 1]));
      fill(c, rect(50, 0, 100, 100), green,
          PdfInkColorants.deviceCmyk(0.5, 0, 1, 0.5));
      final path = PdfPath([
        const PdfMoveTo(10, 50),
        const PdfLineTo(90, 50),
      ]);

      expect(
        c.strokeShape(
          path,
          const PdfStroke(width: 20),
          inkColor,
          PdfInkColorants.deviceGray(0.5),
          overprint: true,
          mode: 0,
          opaque: true,
        ),
        isNull,
      );
      final regions = c.takeSpatialPaint();
      expect(regions, isNotNull);
      expect(
        {for (final region in regions!) region.color},
        containsAll([green, inkColor]),
      );

      // A later stroke must not inherit the previous one-shot region list.
      expect(
        c.strokeShape(
          PdfPath([
            const PdfMoveTo(10, 20),
            const PdfLineTo(40, 20),
          ]),
          const PdfStroke(width: 10),
          inkColor,
          PdfInkColorants.deviceGray(0.5),
          overprint: true,
          mode: 0,
          opaque: true,
        ),
        green,
      );
      expect(c.takeSpatialPaint(), isNull);
    });
  });
}
