import 'dart:math' as math;

/// A 2D affine transform in PDF convention: row vectors, so a point maps as
/// `x' = a·x + c·y + e`, `y' = b·x + d·y + f` (ISO 32000-1 §8.3.3).
///
/// Lives in `pdf_cos` (the lowest layer) so every package - COS-level
/// geometry, the page/annotation model, the graphics interpreter, and the
/// Flutter renderer - shares one representation of `[a b c d e f]` instead of
/// re-implementing the multiply/apply/bounds math over record tuples, six
/// locals, or `List<double>`.
class PdfMatrix {
  const PdfMatrix(this.a, this.b, this.c, this.d, this.e, this.f);

  const PdfMatrix.translation(double dx, double dy) : this(1, 0, 0, 1, dx, dy);

  const PdfMatrix.scaled(double sx, double sy) : this(sx, 0, 0, sy, 0, 0);

  /// Reads an `[a b c d e f]` row (as stored in a /Matrix array). Missing or
  /// short input falls back to [identity]; a diagonal defaults to 1, an
  /// off-diagonal or translation to 0.
  factory PdfMatrix.row(List<double>? values) {
    if (values == null || values.length < 6) return identity;
    return PdfMatrix(
      values[0],
      values[1],
      values[2],
      values[3],
      values[4],
      values[5],
    );
  }

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

  /// Maps the point ([x], [y]) through this transform, as a record.
  (double, double) apply(double x, double y) =>
      (a * x + c * y + e, b * x + d * y + f);

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

  /// The transform as an `[a b c d e f]` row, ready to serialize into a
  /// /Matrix array.
  List<double> toList() => [a, b, c, d, e, f];

  @override
  bool operator ==(Object other) =>
      other is PdfMatrix &&
      a == other.a &&
      b == other.b &&
      c == other.c &&
      d == other.d &&
      e == other.e &&
      f == other.f;

  @override
  int get hashCode => Object.hash(a, b, c, d, e, f);

  @override
  String toString() => 'PdfMatrix($a, $b, $c, $d, $e, $f)';
}
