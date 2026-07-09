// Slug-style glyph foundations (JCGT 2017, Lengyel: "GPU-Centered Font
// Rendering Directly from Glyph Outlines"): cubic->quadratic conversion
// with an em-space error bound, per-glyph horizontal band lists, and the
// rgba8888 texel encoding a fragment shader reads the curves from.
//
// Pure Dart. The Dart-side winding evaluator ([glyphWindingAt]) mirrors
// the eventual GLSL evaluation step by step and is the reference the B3
// shader must match.
//
// ## Texel encoding (consumed by the B3 shader; byte-exact reads of
// rgba8888 textures via nearest-sampled texture() are M0-verified)
//
// Every texel (4 bytes) holds two 16-bit little-endian values:
// `r = lo(u), g = hi(u), b = lo(v), a = hi(v)`.
//
// Coordinates are 16-bit fixed point: `u16 = round(em * 8192) + 32768`,
// i.e. range [-4, +4) em with 1/8192 em resolution (~0.003 px at a 24-px
// em); decode as `(u16 - 32768) / 8192`. Counts and offsets are raw u16
// (no bias). Layout, by texel index:
//
//   0                      header: (bandCount, curveCount) raw
//   1 .. bandCount         band table: (listOffset, curveCount) raw -
//                          listOffset is the absolute texel index of the
//                          band's reference list
//   ...                    band reference lists: one texel per entry,
//                          (curveTexelOffset, 0) raw - the absolute texel
//                          index of the curve's first control point;
//                          entries sorted by descending curve max-x so the
//                          shader can early-out
//   ...                    curve data: 3 texels per curve - p0, control,
//                          p1 as fixed-point pairs
//
// Band geometry (bandCount, minY, bandHeight and the glyph bbox) travels
// as uniforms/vertex data, not texels - see [GlyphCurveTexture].
import 'dart:math' as math;
import 'dart:typed_data';

import '../path.dart';

/// One quadratic Bezier segment in em space (y-up, origin on the
/// baseline): `p0 = (x0,y0)`, control `(cx,cy)`, `p1 = (x1,y1)`.
class QuadCurve {
  const QuadCurve(this.x0, this.y0, this.cx, this.cy, this.x1, this.y1);

  final double x0, y0, cx, cy, x1, y1;

  double get minX => math.min(x0, math.min(cx, x1));
  double get maxX => math.max(x0, math.max(cx, x1));
  double get minY => math.min(y0, math.min(cy, y1));
  double get maxY => math.max(y0, math.max(cy, y1));

  @override
  String toString() => 'QuadCurve(($x0,$y0) ($cx,$cy) ($x1,$y1))';
}

/// Converts a glyph [outline] (em space; lines and cubics) into quadratic
/// curves within [tolerance] em of the original geometry.
///
/// Lines become degenerate quads (control point at the midpoint), so one
/// uniform curve type feeds the band evaluator. Subpaths close implicitly
/// (fill semantics) - the returned set always forms closed loops, which
/// the winding evaluation depends on.
///
/// Cubic->quad: the cubic is split into `n = ceil(cbrt(err0 / tolerance))`
/// equal-parameter pieces, where `err0 = sqrt(3)/36 * |P3 - 3P2 + 3P1 - P0|`
/// is the standard midpoint-parabola error bound for approximating the
/// whole cubic with a single quadratic; per-piece error then falls as
/// 1/n^3. Each piece's control point is `(3Q1 + 3Q2 - Q0 - Q3) / 4`.
List<QuadCurve> outlineToQuads(PdfPath outline, {double tolerance = 1e-3}) {
  final out = <QuadCurve>[];
  var penX = 0.0, penY = 0.0, startX = 0.0, startY = 0.0;
  var open = false;

  void line(double x0, double y0, double x1, double y1) {
    if (x0 == x1 && y0 == y1) return;
    out.add(QuadCurve(x0, y0, (x0 + x1) / 2, (y0 + y1) / 2, x1, y1));
  }

  void close() {
    if (!open) return;
    line(penX, penY, startX, startY);
    open = false;
  }

  for (final segment in outline.segments) {
    switch (segment) {
      case PdfMoveTo(:final x, :final y):
        close();
        penX = startX = x;
        penY = startY = y;
        open = true;
      case PdfLineTo(:final x, :final y):
        if (!open) continue;
        line(penX, penY, x, y);
        penX = x;
        penY = y;
      case PdfCubicTo():
        if (!open) continue;
        final p0x = penX, p0y = penY;
        final p1x = segment.x1, p1y = segment.y1;
        final p2x = segment.x2, p2y = segment.y2;
        final p3x = segment.x3, p3y = segment.y3;
        final dx = p3x - 3 * p2x + 3 * p1x - p0x;
        final dy = p3y - 3 * p2y + 3 * p1y - p0y;
        final err0 = math.sqrt(3) / 36 * math.sqrt(dx * dx + dy * dy);
        final n = err0 <= tolerance
            ? 1
            : math.pow(err0 / tolerance, 1 / 3).ceil().clamp(1, 64);
        // piece [t0,t1] endpoints and derivative-based inner Beziers
        double bx(double t) {
          final mt = 1 - t;
          return mt * mt * mt * p0x +
              3 * mt * mt * t * p1x +
              3 * mt * t * t * p2x +
              t * t * t * p3x;
        }

        double by(double t) {
          final mt = 1 - t;
          return mt * mt * mt * p0y +
              3 * mt * mt * t * p1y +
              3 * mt * t * t * p2y +
              t * t * t * p3y;
        }

        double dbx(double t) {
          final mt = 1 - t;
          return 3 * mt * mt * (p1x - p0x) +
              6 * mt * t * (p2x - p1x) +
              3 * t * t * (p3x - p2x);
        }

        double dby(double t) {
          final mt = 1 - t;
          return 3 * mt * mt * (p1y - p0y) +
              6 * mt * t * (p2y - p1y) +
              3 * t * t * (p3y - p2y);
        }

        var qx0 = p0x, qy0 = p0y;
        for (var i = 1; i <= n; i++) {
          final t0 = (i - 1) / n, t1 = i / n;
          final qx3 = i == n ? p3x : bx(t1), qy3 = i == n ? p3y : by(t1);
          final dt = (t1 - t0) / 3;
          // cubic piece inner controls from endpoint derivatives
          final q1x = qx0 + dt * dbx(t0), q1y = qy0 + dt * dby(t0);
          final q2x = qx3 - dt * dbx(t1), q2y = qy3 - dt * dby(t1);
          // midpoint-parabola control for the piece
          final cx = (3 * (q1x + q2x) - qx0 - qx3) / 4;
          final cy = (3 * (q1y + q2y) - qy0 - qy3) / 4;
          out.add(QuadCurve(qx0, qy0, cx, cy, qx3, qy3));
          qx0 = qx3;
          qy0 = qy3;
        }
        penX = p3x;
        penY = p3y;
      case PdfClosePath():
        close();
        penX = startX;
        penY = startY;
        open = true;
    }
  }
  close();
  return out;
}

/// Per-glyph horizontal band lists over a quadratic curve set.
///
/// The glyph's y-extent divides into [bandCount] uniform bands; each band
/// lists the indices of every curve whose control-point y-range overlaps
/// it, sorted by descending curve max-x (the shader walks the list and
/// early-outs once curves lie entirely left of the sample). A band holding
/// more than [maxCurvesPerBandDefault] (or the given cap) curves sets
/// [overflow] - callers fall back to outline strips for that glyph.
class GlyphBands {
  GlyphBands._(this.bandCount, this.minX, this.minY, this.maxX, this.maxY,
      this.bands, this.overflow);

  static const int maxCurvesPerBandDefault = 16;

  final int bandCount;
  final double minX, minY, maxX, maxY;

  /// Curve indices per band, sorted by descending max-x.
  final List<Uint16List> bands;

  /// True when some band exceeds the per-band curve cap.
  final bool overflow;

  double get bandHeight =>
      bandCount == 0 ? 0 : (maxY - minY) / bandCount;

  /// The band index sampling row [y] (em space) falls into, clamped.
  int bandFor(double y) {
    if (bandCount == 0) return 0;
    final b = ((y - minY) / bandHeight).floor();
    return b < 0 ? 0 : (b >= bandCount ? bandCount - 1 : b);
  }
}

/// Builds [GlyphBands] for [curves]. Empty input yields zero bands.
GlyphBands buildBands(List<QuadCurve> curves,
    {int bandCount = 8,
    int maxCurvesPerBand = GlyphBands.maxCurvesPerBandDefault}) {
  if (curves.isEmpty) {
    return GlyphBands._(0, 0, 0, 0, 0, const [], false);
  }
  var minX = double.infinity, minY = double.infinity;
  var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
  for (final c in curves) {
    minX = math.min(minX, c.minX);
    maxX = math.max(maxX, c.maxX);
    minY = math.min(minY, c.minY);
    maxY = math.max(maxY, c.maxY);
  }
  if (maxY <= minY) maxY = minY + 1e-6;
  final bandH = (maxY - minY) / bandCount;
  final lists = List.generate(bandCount, (_) => <int>[]);
  for (var i = 0; i < curves.length; i++) {
    final c = curves[i];
    var b0 = ((c.minY - minY) / bandH).floor();
    var b1 = ((c.maxY - minY) / bandH).ceil() - 1;
    if (b0 < 0) b0 = 0;
    if (b1 >= bandCount) b1 = bandCount - 1;
    for (var b = b0; b <= b1; b++) {
      lists[b].add(i);
    }
  }
  var overflow = false;
  final bands = <Uint16List>[];
  for (final list in lists) {
    if (list.length > maxCurvesPerBand) overflow = true;
    list.sort((a, b) => curves[b].maxX.compareTo(curves[a].maxX));
    bands.add(Uint16List.fromList(list));
  }
  return GlyphBands._(bandCount, minX, minY, maxX, maxY, bands, overflow);
}

/// Winding number of the horizontal ray `x' > x` at em-space point
/// (x, y), evaluated exactly the way the B3 shader will: pick the band
/// for y, walk its (max-x descending) curve list with the early-out, and
/// accumulate signed ray crossings from the quadratic roots of
/// `Y(t) = y`, t in [0, 1).
int glyphWindingAt(
    List<QuadCurve> curves, GlyphBands bands, double x, double y) {
  if (bands.bandCount == 0) return 0;
  if (y < bands.minY || y > bands.maxY) return 0;
  var winding = 0;
  for (final index in bands.bands[bands.bandFor(y)]) {
    final c = curves[index];
    if (c.maxX <= x) break; // sorted descending: nothing further can cross
    if (y < c.minY || y >= c.maxY) continue;
    // Y(t) - y = a t^2 + b t + cc
    final a = c.y0 - 2 * c.cy + c.y1;
    final b = 2 * (c.cy - c.y0);
    final cc = c.y0 - y;
    if (a.abs() < 1e-12) {
      // (near-)linear in y
      if (b.abs() < 1e-12) continue; // horizontal: no crossing
      final t = -cc / b;
      if (t >= 0 && t < 1) {
        final xt = _quadX(c, t);
        if (xt > x) winding += b > 0 ? 1 : -1;
      }
      continue;
    }
    final disc = b * b - 4 * a * cc;
    if (disc < 0) continue;
    final sq = math.sqrt(disc);
    for (final t in [(-b - sq) / (2 * a), (-b + sq) / (2 * a)]) {
      if (t < 0 || t >= 1) continue;
      final xt = _quadX(c, t);
      if (xt <= x) continue;
      final dy = 2 * a * t + b;
      if (dy > 0) {
        winding += 1;
      } else if (dy < 0) {
        winding -= 1;
      }
    }
  }
  return winding;
}

double _quadX(QuadCurve c, double t) {
  final mt = 1 - t;
  return mt * mt * c.x0 + 2 * mt * t * c.cx + t * t * c.x1;
}

/// A glyph's curves + band tables packed for GPU consumption (layout in
/// the library header). [pixels] is rgba8888 at [width] x [height] with
/// zero padding; band geometry rides as plain fields for uniforms.
class GlyphCurveTexture {
  GlyphCurveTexture._(this.pixels, this.width, this.height, this.texelCount,
      this.bandCount, this.minX, this.minY, this.maxX, this.maxY,
      this.overflow);

  final Uint8List pixels;
  final int width;
  final int height;
  final int texelCount;
  final int bandCount;
  final double minX, minY, maxX, maxY;
  final bool overflow;

  double get bandHeight => bandCount == 0 ? 0 : (maxY - minY) / bandCount;
}

/// Fixed-point encode: em coordinate -> biased u16 (see library header).
int emToFixed(double v) {
  final f = (v * 8192).round() + 32768;
  return f < 0 ? 0 : (f > 0xFFFF ? 0xFFFF : f);
}

/// Fixed-point decode.
double fixedToEm(int u16) => (u16 - 32768) / 8192;

/// Packs [curves] + [bands] into texels (see the library header for the
/// layout). Throws [ArgumentError] when the stream exceeds u16
/// addressability (65535 texels) - callers fall back to outline strips.
GlyphCurveTexture encodeGlyphTexels(List<QuadCurve> curves, GlyphBands bands,
    {int width = 256}) {
  final bandCount = bands.bandCount;
  var refEntries = 0;
  for (final b in bands.bands) {
    refEntries += b.length;
  }
  final texelCount = 1 + bandCount + refEntries + 3 * curves.length;
  if (texelCount > 0xFFFF) {
    throw ArgumentError('glyph curve stream too large: $texelCount texels');
  }
  final height = math.max(1, (texelCount + width - 1) ~/ width);
  final pixels = Uint8List(width * height * 4);
  final u16 = ByteData.sublistView(pixels);

  void put(int texel, int lo, int hi) {
    u16.setUint16(texel * 4, lo, Endian.little);
    u16.setUint16(texel * 4 + 2, hi, Endian.little);
  }

  final curveBase = 1 + bandCount + refEntries;
  put(0, bandCount, curves.length);
  var refAt = 1 + bandCount;
  for (var b = 0; b < bandCount; b++) {
    put(1 + b, refAt, bands.bands[b].length);
    for (final curveIndex in bands.bands[b]) {
      put(refAt++, curveBase + 3 * curveIndex, 0);
    }
  }
  for (var i = 0; i < curves.length; i++) {
    final c = curves[i];
    put(curveBase + 3 * i, emToFixed(c.x0), emToFixed(c.y0));
    put(curveBase + 3 * i + 1, emToFixed(c.cx), emToFixed(c.cy));
    put(curveBase + 3 * i + 2, emToFixed(c.x1), emToFixed(c.y1));
  }
  return GlyphCurveTexture._(pixels, width, height, texelCount, bandCount,
      bands.minX, bands.minY, bands.maxX, bands.maxY, bands.overflow);
}
