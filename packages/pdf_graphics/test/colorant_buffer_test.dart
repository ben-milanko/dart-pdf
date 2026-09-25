// Unit coverage for the CMYK/spot colorant buffer that makes overprint
// faithful (issue #502).
//
// Four layers, each pinned directly rather than through a rendered page:
//
//   1. the ink-space composite rule ([PdfInkColorants.over]) - which colorants
//      a colour space writes, and what the overprint mode does to that;
//   2. the colorant reading of real PDF colour spaces
//      ([PdfColorSpace.inkColorants]), including a DeviceN naming a spot;
//   3. the compositor itself ([PdfOverprintCompositor]) - the rasterized
//      backdrop lookup and the "reuse the exact colour this reproduces" rule
//      that keeps a resolved overprint pixel-identical to the paint it
//      matches.
//   4. the scanline rasterizer under it ([PdfColorantRaster]) - geometry a
//      broken generator can emit, and the rectangle fast path.
//
// The GWG030 render guard (dart_pdf_editor overprint_render_test.dart) covers
// the same ground end to end; these are the pieces, so a failure names one.
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart' show PdfRect;
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_graphics/src/raster/colorant_raster.dart';
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

    test('a sub-cell stroke still discovers every backdrop it crosses', () {
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
      // At this buffer scale 0.1pt covers less than half a cell and its
      // centreline lies exactly between two sample rows. The colorant grid
      // must retain one cell of coverage; the renderer later clips the
      // substitute regions through this original vector stroke.
      const stroke = PdfStroke(width: 0.1);
      expect(
        c.strokeShape(
          PdfPath([
            const PdfMoveTo(10, 50),
            const PdfLineTo(90, 50),
          ]),
          stroke,
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
    });

    test('a multi-segment sub-cell stroke stays conservative', () {
      const green = PdfColor(0.31, 0.45, 0.13);
      const inkColor = PdfColor(0.5, 0.5, 0.5);
      final c = buffer();
      fill(c, rect(0, 0, 100, 100), green,
          PdfInkColorants.deviceCmyk(0.5, 0, 1, 0.5));

      // Both exact 0.1pt segments lie between sample rows and cover no
      // colorant cell centre. Inflating the whole compound path resolves it
      // as [inkColor], even though joins/caps and neighbouring backdrops are
      // unknowable at this grid resolution. Declining keeps the device's
      // conservative overprint path; the Ghent composite pages expose the
      // forced resolution as a visible X.
      expect(
        c.strokeShape(
          PdfPath([
            const PdfMoveTo(10, 50),
            const PdfLineTo(40, 50),
            const PdfMoveTo(60, 50),
            const PdfLineTo(90, 50),
          ]),
          const PdfStroke(width: 0.1),
          inkColor,
          PdfInkColorants.deviceGray(0.5),
          overprint: true,
          mode: 0,
          opaque: true,
        ),
        isNull,
      );
      expect(c.takeSpatialPaint(), isNull);
    });

    test('explicit bounds preserve a sub-cell fill for spatial replay', () {
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
      final skinny = rect(49.95, 10, 50.05, 90);

      expect(
        c.fill(
          skinny,
          PdfFillRule.nonzero,
          inkColor,
          PdfInkColorants.deviceGray(0.5),
          subCellBounds: const PdfRect(49.95, 10, 50.05, 90),
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
    });
  });

  group('the colorant rasterizer', () {
    // An identity mapping, so the coordinates below are cells.
    PdfColorantRaster raster() => PdfColorantRaster(
          width: 100,
          height: 100,
          mapping: const ColorantPageMapping(PdfMatrix.identity, 1),
        );

    List<(int, int, int)> spansOf(ColorantSpans spans) => [
          for (var i = 0; i < spans.length; i++)
            (spans.yAt(i), spans.startAt(i), spans.endAt(i)),
        ];

    const triangle = [
      PdfMoveTo(10, 10),
      PdfLineTo(80, 20),
      PdfLineTo(40, 90),
      PdfClosePath(),
    ];

    test('geometry far off the page neither drops nor wraps the rest', () {
      // Broken generators print FLT_MAX with %f and pdf_cos parses it, so an
      // edge can sit anywhere. The scan keeps such an edge as it is - no
      // integer row index for it to overflow: a subpath out there covers no
      // row, and a spike out to it is a vertical edge on the page.
      final r = raster();
      final alone =
          spansOf(r.fillSpans(const PdfPath(triangle), evenOdd: false));
      expect(alone, isNotEmpty);
      for (final far in [
        1e12,
        -1e12,
        3e9,
        -4294967396.0, // 2^32 rows up: wraps to row 300 in 32 bits
        1e19, // past the VM's int range
        -1e19,
        3.4028234663852886e38, // FLT_MAX
      ]) {
        for (final evenOdd in [false, true]) {
          final offPage = PdfPath([
            ...triangle,
            PdfMoveTo(0, far),
            PdfLineTo(50, far * 1.001),
            PdfLineTo(100, far),
            const PdfClosePath(),
          ]);
          expect(spansOf(r.fillSpans(offPage, evenOdd: evenOdd)), alone,
              reason: 'subpath at y = $far');
          final spike = PdfPath([
            const PdfMoveTo(10, 50),
            const PdfLineTo(80, 50),
            PdfLineTo(40, far),
            const PdfClosePath(),
          ]);
          expect(
              spansOf(r.fillSpans(spike, evenOdd: evenOdd)),
              spansOf(far > 0
                  ? r.boxSpans(10, 50, 80, 100)
                  : r.boxSpans(10, 0, 80, 50)),
              reason: 'spike to y = $far');
        }
      }
    });

    test('a vertex at infinite x drops out without disturbing the rest', () {
      // The page mapping has no shear, so an infinite x maps to a NaN cell y
      // (0 x infinity) and every crossing of the two edges meeting there is
      // NaN. Edges are gathered in path order, so on every row those NaNs
      // come after the finite crossings, where the insertion sort leaves them
      // and no run reads them: the fill is the one without the vertex.
      // Gathered any earlier, a NaN would open or close a run instead.
      const square = [
        PdfMoveTo(10, 10),
        PdfLineTo(70, 10),
        PdfLineTo(70, 90),
        PdfLineTo(10, 90),
        PdfClosePath(),
      ];
      const sliver = [PdfMoveTo(80, 60), PdfLineTo(90, 20), PdfLineTo(85, 60)];
      final r = raster();
      for (final evenOdd in [false, true]) {
        final without = spansOf(r.fillSpans(
            const PdfPath([...square, ...sliver, PdfClosePath()]),
            evenOdd: evenOdd));
        expect(without, isNotEmpty);
        for (final x in [double.infinity, double.negativeInfinity]) {
          final withVertex = PdfPath([
            ...square,
            ...sliver,
            PdfLineTo(x, 40),
            const PdfClosePath(),
          ]);
          expect(spansOf(r.fillSpans(withVertex, evenOdd: evenOdd)), without,
              reason: 'x = $x, evenOdd: $evenOdd');
        }
      }
    });

    test('a packed rectangle of coincident-control cubics is still a box', () {
      // The interpreter builds packed paths, and rectangles drawn as `v`/`y`
      // cubics with their controls on their own endpoints are what the Ghent
      // overprint patches are made of. The box fast path reads them through
      // the path cursor and must still recognise them.
      final packed = (PdfPathBuilder()
            ..moveTo(10, 20)
            ..cubicTo(10, 20, 60, 20, 60, 20)
            ..cubicTo(60, 20, 60, 70, 60, 70)
            ..cubicTo(60, 70, 10, 70, 10, 70)
            ..cubicTo(10, 70, 10, 20, 10, 20)
            ..close())
          .takePath();
      expect(packed.segmentCount, 6);
      expect(PdfColorantRaster.debugIsAxisAlignedRect(packed), isTrue);
      final r = raster();
      expect(spansOf(r.fillSpans(packed, evenOdd: false)),
          spansOf(r.boxSpans(10, 20, 60, 70)));
      // The render-command decoder's float32 packing, as a plain `re`.
      final decoded = PdfPath.packedFloat32(Uint8List.fromList([0, 1, 1, 1, 3]),
          Float32List.fromList([10, 20, 60, 20, 60, 70, 10, 70]), 5);
      expect(PdfColorantRaster.debugIsAxisAlignedRect(decoded), isTrue);

      // A control off the line makes a curve, and a path must open with a
      // moveTo to be a rectangle at all.
      final curved = (PdfPathBuilder()
            ..moveTo(10, 20)
            ..cubicTo(10, 20, 60, 25, 60, 20)
            ..lineTo(60, 70)
            ..lineTo(10, 70)
            ..close())
          .takePath();
      expect(PdfColorantRaster.debugIsAxisAlignedRect(curved), isFalse);
      final noMove = (PdfPathBuilder()
            ..lineTo(10, 20)
            ..lineTo(60, 20)
            ..lineTo(60, 70)
            ..lineTo(10, 70)
            ..close())
          .takePath();
      expect(PdfColorantRaster.debugIsAxisAlignedRect(noMove), isFalse);
    });
  });
}
