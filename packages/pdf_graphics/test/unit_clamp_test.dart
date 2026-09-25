import 'package:pdf_graphics/src/unit_clamp.dart';
import 'package:test/test.dart';

/// The colour loops swap `num.clamp` for these helpers on the promise that
/// they return exactly what `clamp` does, specials included. Pin that.
void main() {
  test('clampUnit is double.clamp(0.0, 1.0), specials included', () {
    const inputs = [
      double.nan,
      double.infinity,
      double.negativeInfinity,
      -0.0,
      0.0,
      double.minPositive,
      -double.minPositive,
      0.5,
      0.9999999999999999,
      1.0,
      1.0000000000000002,
      -1e300,
      1e300,
    ];
    for (final v in inputs) {
      final want = v.clamp(0.0, 1.0);
      final got = clampUnit(v);
      expect(got, want, reason: '$v');
      expect(got.isNegative, want.isNegative, reason: 'sign of $v');
    }
    expect(clampUnit(double.nan), 1.0);
    expect(clampUnit(-0.0).isNegative, isFalse);
  });

  test('clampByte is int.clamp(0, 255)', () {
    for (var v = -600; v <= 600; v++) {
      expect(clampByte(v), v.clamp(0, 255), reason: '$v');
    }
    for (final v in [-(1 << 40), 1 << 40]) {
      expect(clampByte(v), v.clamp(0, 255));
    }
  });

  test('clampIndex is int.clamp(lo, hi) whenever lo <= hi', () {
    for (var hi = 0; hi < 5; hi++) {
      for (var v = -3; v < 9; v++) {
        expect(clampIndex(v, 0, hi), v.clamp(0, hi), reason: '$v in 0..$hi');
      }
    }
  });
}
