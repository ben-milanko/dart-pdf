import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

/// Direct tests for the shared [PdfColorSpace] - the single "how many
/// channels and how do components become sRGB" module that the interpreter,
/// shadings, mesh shadings, and image decoding all resolve through. Before
/// this module the conversion was only reachable through whole-page render
/// tests.
void main() {
  late CosDocument cos;

  setUp(() => cos = CosDocument.open(buildClassicPdf()));

  void expectColor(PdfColor color, PdfColor want, {double tol = 1 / 512}) {
    expect(color.red, closeTo(want.red, tol));
    expect(color.green, closeTo(want.green, tol));
    expect(color.blue, closeTo(want.blue, tol));
  }

  /// A type-2 (exponential) tint transform mapping one input to [c1]-scaled
  /// components, with C0 all zero.
  CosDictionary exponential(List<double> c1) => CosDictionary({
        'FunctionType': const CosInteger(2),
        'Domain': CosArray([const CosInteger(0), const CosInteger(1)]),
        'C0': CosArray([for (var _ in c1) const CosReal(0)]),
        'C1': CosArray([for (final v in c1) CosReal(v)]),
        'N': const CosInteger(1),
      });

  group('device families', () {
    test('names and abbreviations map to the right channel count', () {
      expect(PdfColorSpace.parse(cos, const CosName('DeviceGray')).channels, 1);
      expect(PdfColorSpace.parse(cos, const CosName('DeviceRGB')).channels, 3);
      expect(PdfColorSpace.parse(cos, const CosName('DeviceCMYK')).channels, 4);
      // inline-image abbreviations
      expect(PdfColorSpace.parse(cos, const CosName('G')).channels, 1);
      expect(PdfColorSpace.parse(cos, const CosName('RGB')).channels, 3);
      expect(PdfColorSpace.parse(cos, const CosName('CMYK')).channels, 4);
    });

    test('convert components straight through', () {
      expectColor(PdfColorSpace.parse(cos, const CosName('DeviceGray'))
          .toSrgb([0.5]), const PdfColor.gray(0.5));
      expectColor(PdfColorSpace.parse(cos, const CosName('DeviceRGB'))
          .toSrgb([0.1, 0.2, 0.3]), const PdfColor(0.1, 0.2, 0.3));
      expectColor(PdfColorSpace.parse(cos, const CosName('DeviceCMYK'))
          .toSrgb([0.2, 0.4, 0.6, 0.1]), PdfColor.cmyk(0.2, 0.4, 0.6, 0.1));
    });

    test('unknown / malformed spaces fall back to a device family', () {
      expect(PdfColorSpace.parse(cos, const CosName('Bogus')).channels, 3);
      expect(PdfColorSpace.parse(cos, null).channels, 1);
      expect(PdfColorSpace.parse(cos, CosArray([])).channels, 1);
    });

    test('non-ICC families carry no ICC profile', () {
      expect(PdfColorSpace.parse(cos, const CosName('DeviceRGB')).iccProfile,
          isNull);
      expect(PdfColorSpace.parse(cos, const CosName('Pattern')).iccProfile,
          isNull);
    });
  });

  test('Pattern reports zero channels', () {
    final space = PdfColorSpace.parse(cos, const CosName('Pattern'));
    expect(space.family, 'Pattern');
    expect(space.channels, 0);
  });

  test('a name resolves through the resource /ColorSpace dictionary', () {
    final resources = CosDictionary({
      'ColorSpace': CosDictionary({
        'CS0': CosArray([
          const CosName('ICCBased'),
          CosStream(CosDictionary({'N': const CosInteger(4)}), Uint8List(0)),
        ]),
      }),
    });
    final space =
        PdfColorSpace.parse(cos, const CosName('CS0'), resources: resources);
    expect(space.family, 'ICCBased');
    expect(space.channels, 4);
  });

  group('ICCBased', () {
    test('channel count comes from /N; no profile degrades to device', () {
      final space = PdfColorSpace.parse(
          cos,
          CosArray([
            const CosName('ICCBased'),
            CosStream(CosDictionary({'N': const CosInteger(3)}), Uint8List(0)),
          ]));
      expect(space.channels, 3);
      expect(space.iccProfile, isNull);
      // Falls back to a plain device reading of the components.
      expectColor(space.toSrgb([0.1, 0.2, 0.3]), const PdfColor(0.1, 0.2, 0.3));
    });

    test('a real profile is applied - the gap the shading path used to miss',
        () {
      final iccBytes = adobeRgb1998Icc();
      final space = PdfColorSpace.parse(
          cos,
          CosArray([
            const CosName('ICCBased'),
            CosStream(
                CosDictionary({'N': const CosInteger(3)}), iccBytes),
          ]));
      expect(space.iccProfile, isNotNull);
      // Same output as driving the profile directly (littleCMS reference in
      // icc_test): AdobeRGB (128,64,200) -> sRGB (146,62,205).
      final direct = IccProfile.parse(iccBytes)!.toSrgb([128 / 255, 64 / 255, 200 / 255]);
      expectColor(space.toSrgb([128 / 255, 64 / 255, 200 / 255]), direct,
          tol: 1 / 512);
    });
  });

  group('Indexed', () {
    test('a single index selects a palette entry in the base space', () {
      // palette: 0 -> red, 1 -> green, 2 -> blue (DeviceRGB base)
      final lookup = Uint8List.fromList(
          [255, 0, 0, 0, 255, 0, 0, 0, 255]);
      final space = PdfColorSpace.parse(
          cos,
          CosArray([
            const CosName('Indexed'),
            const CosName('DeviceRGB'),
            const CosInteger(2),
            CosString(lookup),
          ]));
      expect(space.channels, 1);
      expectColor(space.toSrgb([0]), const PdfColor(1, 0, 0));
      expectColor(space.toSrgb([1]), const PdfColor(0, 1, 0));
      expectColor(space.toSrgb([2]), const PdfColor(0, 0, 1));
      // out-of-range indices clamp to [0, hival]
      expectColor(space.toSrgb([9]), const PdfColor(0, 0, 1));
      expectColor(space.toSrgb([-4]), const PdfColor(1, 0, 0));
    });
  });

  group('Separation / DeviceN', () {
    test('Separation runs a one-colorant tint into the alternate space', () {
      final space = PdfColorSpace.parse(
          cos,
          CosArray([
            const CosName('Separation'),
            const CosName('All'),
            const CosName('DeviceCMYK'),
            exponential(const [1, 1, 1, 1]),
          ]));
      expect(space.family, 'Separation');
      expect(space.channels, 1);
      // tint 0.5 -> CMYK (0.5,0.5,0.5,0.5) -> the device CMYK conversion
      expectColor(space.toSrgb([0.5]), PdfColor.cmyk(0.5, 0.5, 0.5, 0.5));
    });

    test('DeviceN channel count is the colorant list length', () {
      final space = PdfColorSpace.parse(
          cos,
          CosArray([
            const CosName('DeviceN'),
            CosArray([const CosName('A'), const CosName('B')]),
            const CosName('DeviceRGB'),
            // type-4: inputs [a, b] -> [a, b, 0]
            CosStream(
              CosDictionary({
                'FunctionType': const CosInteger(4),
                'Domain': CosArray([
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
              }),
              Uint8List.fromList('{ 0 }'.codeUnits),
            ),
          ]));
      expect(space.family, 'DeviceN');
      expect(space.channels, 2);
      expectColor(space.toSrgb([0.2, 0.4]), const PdfColor(0.2, 0.4, 0));
    });
  });

  group('fallbacks and error paths', () {
    test('Pattern in array form and its toSrgb', () {
      final space = PdfColorSpace.parse(cos, CosArray([const CosName('Pattern')]));
      expect(space.family, 'Pattern');
      expect(space.channels, 0);
      expect(space.toSrgb(const []), PdfColor.black);
    });

    test('a device name in array form resolves to the device family', () {
      final space =
          PdfColorSpace.parse(cos, CosArray([const CosName('DeviceRGB')]));
      expect(space.family, 'DeviceRGB');
      expect(space.channels, 3);
    });

    test('a CIE space with invalid params degrades to its device family', () {
      // Missing /WhitePoint -> PdfCalibratedColorSpace.parse returns null.
      final calRgb = PdfColorSpace.parse(
          cos, CosArray([const CosName('CalRGB'), CosDictionary({})]));
      expect(calRgb.family, 'DeviceRGB');
      expect(calRgb.channels, 3);
      final calGray = PdfColorSpace.parse(
          cos, CosArray([const CosName('CalGray'), CosDictionary({})]));
      expect(calGray.family, 'DeviceGray');
      expect(calGray.channels, 1);
    });

    test('an ICC profile that cannot be decoded degrades to device', () {
      // A FlateDecode filter over non-flate bytes fails to decode; the parse
      // swallows it and falls back to the /N device family.
      final space = PdfColorSpace.parse(
          cos,
          CosArray([
            const CosName('ICCBased'),
            CosStream(
              CosDictionary({
                'N': const CosInteger(3),
                'Filter': const CosName('FlateDecode'),
              }),
              Uint8List.fromList([1, 2, 3, 4]),
            ),
          ]));
      expect(space.iccProfile, isNull);
      expect(space.channels, 3);
      expectColor(space.toSrgb([0.1, 0.2, 0.3]), const PdfColor(0.1, 0.2, 0.3));
    });

    test('iccCache memoises the parsed profile across parses', () {
      final iccBytes = adobeRgb1998Icc();
      final stream =
          CosStream(CosDictionary({'N': const CosInteger(3)}), iccBytes);
      final array = CosArray([const CosName('ICCBased'), stream]);
      final cache = <CosStream, IccProfile?>{};
      final first = PdfColorSpace.parse(cos, array, iccCache: cache).iccProfile;
      final second = PdfColorSpace.parse(cos, array, iccCache: cache).iccProfile;
      expect(cache, contains(stream));
      expect(identical(first, second), isTrue);
    });

    test('Indexed accepts a stream lookup table', () {
      final space = PdfColorSpace.parse(
          cos,
          CosArray([
            const CosName('Indexed'),
            const CosName('DeviceRGB'),
            const CosInteger(1),
            CosStream(CosDictionary({}),
                Uint8List.fromList([255, 0, 0, 0, 255, 0])),
          ]));
      expect(space.family, 'Indexed');
      expectColor(space.toSrgb([1]), const PdfColor(0, 1, 0));
    });

    test('an Indexed lookup stream that fails to decode degrades to device',
        () {
      final space = PdfColorSpace.parse(
          cos,
          CosArray([
            const CosName('Indexed'),
            const CosName('DeviceRGB'),
            const CosInteger(1),
            // FlateDecode over non-flate bytes throws on decode -> parse null.
            CosStream(
                CosDictionary({'Filter': const CosName('FlateDecode')}),
                Uint8List.fromList([9, 9, 9, 9])),
          ]));
      expect(space.family, isNot('Indexed'));
    });

    test('an Indexed space with a bad /hival degrades to a device family', () {
      final space = PdfColorSpace.parse(
          cos,
          CosArray([
            const CosName('Indexed'),
            const CosName('DeviceRGB'),
            const CosName('nope'), // hival must be a number
            CosString(Uint8List.fromList([0, 0, 0])),
          ]));
      expect(space.family, isNot('Indexed'));
    });
  });

  group('CIE-based', () {
    test('delegates to PdfCalibratedColorSpace', () {
      final array = CosArray([
        const CosName('Lab'),
        CosDictionary({
          'WhitePoint': CosArray(
              [const CosReal(0.9505), const CosReal(1), const CosReal(1.089)]),
          'Range': CosArray([
            const CosInteger(-128),
            const CosInteger(127),
            const CosInteger(-128),
            const CosInteger(127),
          ]),
        }),
      ]);
      final space = PdfColorSpace.parse(cos, array);
      final calibrated = PdfCalibratedColorSpace.parse(cos, array)!;
      expect(space.family, 'Lab');
      expect(space.channels, 3);
      expectColor(space.toSrgb([50, 20, -30]), calibrated.toSrgb([50, 20, -30]));
      // Lab keeps its own default sample decode (L* over [0,100]).
      expectColor(space.toSrgbFromSamples([128, 128, 128]),
          calibrated.toSrgbFromSamples([128, 128, 128]));
    });
  });
}
