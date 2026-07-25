import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

/// Builds a minimal but valid RGB matrix/TRC ICC profile whose transform is,
/// by construction, the identity to sRGB: its primaries are the linear-sRGB→
/// XYZ(D50) matrix that inverts the profile's own XYZ→sRGB step, and its TRC
/// is the sRGB decode curve (gamma → linear). Decoding then re-encoding a
/// value therefore returns it unchanged - the shape #531's DetectSRGB probe
/// must recognise. Deterministic and license-free (no third-party bytes).
Uint8List buildSrgbIccProfile() {
  // rXYZ/gXYZ/bXYZ columns = the bradford-adapted linear-sRGB→XYZ(D50) matrix
  // (inverse of the matrix in icc.dart's _xyzD50ToSrgb).
  const cols = [
    [0.4360747, 0.2225045, 0.0139322], // rXYZ
    [0.3850649, 0.7168786, 0.0971045], // gXYZ
    [0.1430804, 0.0606169, 0.7141733], // bXYZ
  ];
  // sRGB decode (gamma-encoded → linear), sampled into a 1024-entry curv.
  double decode(double v) =>
      v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();

  final tags = <String, Uint8List>{};
  for (final (i, sig) in ['rXYZ', 'gXYZ', 'bXYZ'].indexed) {
    final b = ByteData(20);
    b.setUint32(0, 0x58595A20); // 'XYZ '
    for (var c = 0; c < 3; c++) {
      b.setInt32(8 + c * 4, (cols[i][c] * 65536).round());
    }
    tags[sig] = b.buffer.asUint8List();
  }
  const n = 1024;
  final curv = ByteData(12 + n * 2);
  curv.setUint32(0, 0x63757276); // 'curv'
  curv.setUint32(8, n);
  for (var i = 0; i < n; i++) {
    curv.setUint16(12 + i * 2, (decode(i / (n - 1)) * 65535).round());
  }
  final curvBytes = curv.buffer.asUint8List();
  for (final sig in ['rTRC', 'gTRC', 'bTRC']) {
    tags[sig] = curvBytes;
  }

  final entries = tags.entries.toList();
  final tableSize = 132 + entries.length * 12;
  var dataOffset = tableSize;
  final offsets = <String, int>{};
  for (final e in entries) {
    offsets[e.key] = dataOffset;
    dataOffset += e.value.length;
    if (dataOffset % 4 != 0) dataOffset += 4 - (dataOffset % 4);
  }
  final out = Uint8List(dataOffset);
  final view = ByteData.sublistView(out);
  view.setUint32(16, 0x52474220); // 'RGB '
  view.setUint32(20, 0x58595A20); // 'XYZ '
  view.setUint32(128, entries.length);
  for (final (i, e) in entries.indexed) {
    final base = 132 + i * 12;
    out.setRange(base, base + 4, e.key.codeUnits);
    view.setUint32(base + 4, offsets[e.key]!);
    view.setUint32(base + 8, e.value.length);
  }
  for (final e in entries) {
    out.setRange(offsets[e.key]!, offsets[e.key]! + e.value.length, e.value);
  }
  return out;
}

/// Reference values produced by littleCMS (via ImageMagick) for the same
/// profiles and inputs.
void expectSrgb(PdfColor color, List<int> want) {
  expect((color.red * 255).round(), closeTo(want[0], 3));
  expect((color.green * 255).round(), closeTo(want[1], 3));
  expect((color.blue * 255).round(), closeTo(want[2], 3));
}

void main() {
  test('v2 matrix/TRC RGB profiles (AdobeRGB1998) match littleCMS', () {
    final profile = IccProfile.parse(adobeRgb1998Icc())!;
    expect(profile.channels, 3);
    expectSrgb(
        profile.toSrgb([128 / 255, 64 / 255, 200 / 255]), [146, 62, 205]);
    expectSrgb(
        profile.toSrgb([200 / 255, 180 / 255, 30 / 255]), [209, 181, 0]);
    expectSrgb(
        profile.toSrgb([40 / 255, 150 / 255, 90 / 255]), [0, 151, 86]);
  });

  test('v4 parametric-curve RGB profiles (Display P3) match littleCMS', () {
    final profile = IccProfile.parse(displayP3Icc())!;
    expectSrgb(
        profile.toSrgb([128 / 255, 64 / 255, 200 / 255]), [138, 59, 207]);
    expectSrgb(
        profile.toSrgb([40 / 255, 150 / 255, 90 / 255]), [0, 153, 84]);
  });

  test('gray TRC profiles match littleCMS', () {
    final profile = IccProfile.parse(genericGrayIcc())!;
    expect(profile.channels, 1);
    expectSrgb(profile.toSrgb([64 / 255]), [81, 81, 81]);
    expectSrgb(profile.toSrgb([128 / 255]), [146, 146, 146]);
    expectSrgb(profile.toSrgb([192 / 255]), [203, 203, 203]);
  });

  test('LUT CMYK profiles with Lab PCS match littleCMS', () {
    final profile = IccProfile.parse(genericCmykIcc())!;
    expect(profile.channels, 4);
    expectSrgb(profile.toSrgb([1, 0, 0, 0]), [0, 164, 219]); // cyan
    expectSrgb(profile.toSrgb([0, 0, 0, 1]), [25, 26, 25]); // rich black
    expectSrgb(profile.toSrgb([50 / 255, 100 / 255, 150 / 255, 20 / 255]),
        [180, 142, 105]);
  });

  test('a LUT profile stays correct across interleaved calls (#451)', () {
    // The LUT pipeline reuses per-profile scratch buffers instead of
    // allocating five lists per pixel. That is only sound if nothing survives
    // one call into the next, and a leak would be invisible to a test that
    // converts a single colour: the first call would still be right.
    //
    // So drive the profile the way an image does - the same instance, many
    // colours, out of order, revisited - and require the pinned littleCMS
    // values to hold every time regardless of what was converted in between.
    final profile = IccProfile.parse(genericCmykIcc())!;
    const cases = <(List<double>, List<int>)>[
      ([1, 0, 0, 0], [0, 164, 219]), // cyan
      ([0, 0, 0, 1], [25, 26, 25]), // rich black
      ([50 / 255, 100 / 255, 150 / 255, 20 / 255], [180, 142, 105]),
    ];

    for (var round = 0; round < 4; round++) {
      // Interleave in both directions, and push unrelated colours through
      // between the pinned ones so any retained state would be the wrong one.
      for (final (input, want) in cases) {
        profile.toSrgb([0.2, 0.4, 0.6, 0.8]);
        expectSrgb(profile.toSrgb(input), want);
      }
      for (final (input, want) in cases.reversed) {
        expectSrgb(profile.toSrgb(input), want);
      }
    }

    // The caller passes a reused buffer too; the profile must not retain it.
    final scratch = Float64List(4);
    for (final (input, want) in cases) {
      scratch.setAll(0, input);
      final color = profile.toSrgb(scratch);
      scratch.fillRange(0, 4, 0); // clobber after the call
      expectSrgb(color, want);
    }
  });

  test('sRGB-equivalent profiles are detected and bypassed (#531)', () {
    final profile = IccProfile.parse(buildSrgbIccProfile())!;
    expect(profile.channels, 3);
    expect(profile.isSrgb, isTrue,
        reason: 'an identity-to-sRGB profile must be flagged');
    expect(profile.rgb8Transform, isNull,
        reason: 'a bypassed profile needs no 8-bit fast path');
    // Sanity: it really is (near-)identity where the flag promises no-op.
    for (final v in [0, 40, 128, 200, 255]) {
      final c = profile.toSrgb([v / 255, v / 255, v / 255]);
      expect((c.red * 255 - v).abs(), lessThanOrEqualTo(1));
    }
  });

  test('non-sRGB matrix/TRC profiles keep their transform (#531)', () {
    // Detection precision: wide-gamut profiles must NOT be flagged, or their
    // colours would decode wrong.
    final adobe = IccProfile.parse(adobeRgb1998Icc())!;
    final p3 = IccProfile.parse(displayP3Icc())!;
    expect(adobe.isSrgb, isFalse);
    expect(p3.isSrgb, isFalse);
    // The allocation-free 8-bit fast path matches the scalar transform.
    final fast = adobe.rgb8Transform!;
    for (final (r, g, b) in [(128, 64, 200), (200, 180, 30), (40, 150, 90)]) {
      final rgb = Uint8List.fromList([r, g, b]);
      final out = Uint8List(4);
      fast(rgb, 0, out, 0);
      final scalar = adobe.toSrgb([r / 255, g / 255, b / 255]);
      expect((out[0] - (scalar.red * 255).round()).abs(), lessThanOrEqualTo(1));
      expect((out[1] - (scalar.green * 255).round()).abs(),
          lessThanOrEqualTo(1));
      expect(
          (out[2] - (scalar.blue * 255).round()).abs(), lessThanOrEqualTo(1));
    }
  });

  test('gray sRGB-equivalent profiles are also detected (#531)', () {
    // The generic gray profile is a distinct dot-gain curve, so it must keep
    // its transform (regression guard on the gray probe).
    expect(IccProfile.parse(genericGrayIcc())!.isSrgb, isFalse);
  });

  test('garbage parses to null, not an exception', () {
    expect(IccProfile.parse(ascii('not a profile at all')), isNull);
    final truncated = adobeRgb1998Icc().sublist(0, 200);
    expect(IccProfile.parse(truncated), isNull);
  });
}
