import 'dart:math' as math;

/// A 2D affine transform in PDF convention: row vectors, so a point maps as
/// `x' = a·x + c·y + e`, `y' = b·x + d·y + f` (ISO 32000-1 §8.3.3).
class PdfMatrix {
  const PdfMatrix(this.a, this.b, this.c, this.d, this.e, this.f);

  const PdfMatrix.translation(double dx, double dy) : this(1, 0, 0, 1, dx, dy);

  const PdfMatrix.scaled(double sx, double sy) : this(sx, 0, 0, sy, 0, 0);

  static const PdfMatrix identity = PdfMatrix(1, 0, 0, 1, 0, 0);

  final double a;
  final double b;
  final double c;
  final double d;
  final double e;
  final double f;

  /// Returns the transform that applies `this` first, then [after] -
  /// the matrix product `this × after` in row-vector convention.
  PdfMatrix concat(PdfMatrix after) => PdfMatrix(
        a * after.a + b * after.c,
        a * after.b + b * after.d,
        c * after.a + d * after.c,
        c * after.b + d * after.d,
        e * after.a + f * after.c + after.e,
        e * after.b + f * after.d + after.f,
      );

  double transformX(double x, double y) => a * x + c * y + e;

  double transformY(double x, double y) => b * x + d * y + f;

  /// The inverse transform, or null when this matrix is degenerate.
  PdfMatrix? inverted() {
    final det = a * d - b * c;
    if (det.abs() < 1e-12) return null;
    final ia = d / det;
    final ib = -b / det;
    final ic = -c / det;
    final id = a / det;
    return PdfMatrix(ia, ib, ic, id, -(e * ia + f * ic), -(e * ib + f * id));
  }

  /// Average scale factor: how much this transform magnifies lengths.
  double get scaleFactor => math.sqrt((a * d - b * c).abs());

  @override
  String toString() => 'PdfMatrix($a, $b, $c, $d, $e, $f)';
}
