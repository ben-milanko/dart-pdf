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
      expect(all.over(spotGreen, 0),
          PdfColorants(0.4, 0.4, 0.4, 0.4, spots: const ['GWG Green'], tints: const [0.4]));
      final none = separation('None', const [0, 0, 0, 1]).inkColorants([0.7])!;
      expect(none.writesNothing, isTrue);
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
                    CosStream(CosDictionary({'N': const CosInteger(4)}),
                        Uint8List(0)),
                  ]))
              .inkColorants(const [0, 0, 0, 1]),
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
      expect(ink.colorants,
          PdfColorants(0, 0, 0, 0.5, spots: const ['GWG Green'], tints: const [1.0]));
      // Only Black is a process colorant here, so C/M/Y stay the backdrop's.
      expect(ink.over(PdfColorants(0.5, 0, 1, 0.2), 0),
          PdfColorants(0.5, 0, 1, 0.5, spots: const ['GWG Green'], tints: const [1.0]));
    });

    test('spot names are sorted so equal colorants compare equal', () {
      CosObject deviceN(List<String> names) => CosArray([
            const CosName('DeviceN'),
            CosArray([for (final n in names) CosName(n)]),
            const CosName('DeviceCMYK'),
            exponential(const [0, 0, 0, 1]),
          ]);
      final ab =
          PdfColorSpace.parse(cos, deviceN(['Spot A', 'Spot B'])).inkColorants(
              const [0.25, 0.75])!;
      final ba =
          PdfColorSpace.parse(cos, deviceN(['Spot B', 'Spot A'])).inkColorants(
              const [0.75, 0.25])!;
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
            PdfInkColorants? ink,
            {bool overprint = false, int mode = 0}) =>
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
      final resolved = fill(c, rect(20, 20, 80, 80),
          const PdfColor(0.6, 0.6, 0.63), PdfInkColorants.deviceCmyk(0, 0, 0, 0.5),
          overprint: true);
      expect(resolved, backdropColor);
    });

    test('a neutral ink knocks a DeviceCMYK backdrop out to its own colour',
        () {
      final c = buffer();
      fill(c, rect(0, 0, 100, 100), const PdfColor(0.31, 0.45, 0.13),
          PdfInkColorants.deviceCmyk(0.5, 0, 1, 0.5));
      const inkColor = PdfColor(0.5, 0.5, 0.5);
      final resolved = fill(c, rect(20, 20, 80, 80), inkColor,
          PdfInkColorants.deviceGray(0.5),
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
  });
}
