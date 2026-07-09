// Adaptive path flattening for the CPU strip rasterizer, ported from the
// flutter_gpu experiment's gpu_geometry.dart (semantics identical - Wang's
// bound on the cubic's second differences picks the subdivision count).
//
// Everything here is pure Dart (no dart:ui, no dart:io) so it runs on the
// VM, on the web, and inside worker isolates. All accumulation goes through
// typed-array builders: the Dart VM boxes every element of a growable
// List<double>, which made geometry generation the dominant CPU cost on
// CAD-heavy pages before these existed.
import 'dart:math' as math;
import 'dart:typed_data';

import '../matrix.dart';
import '../path.dart';

/// Growable Float64List: unboxed accumulation for geometry in device pixels.
class DoubleBuilder {
  Float64List _data;
  int length = 0;

  DoubleBuilder([int capacity = 256]) : _data = Float64List(capacity);

  bool get isEmpty => length == 0;

  void _ensure(int extra) {
    if (length + extra <= _data.length) return;
    var cap = _data.length * 2;
    while (cap < length + extra) {
      cap *= 2;
    }
    _data = Float64List(cap)..setRange(0, length, _data);
  }

  void add2(double a, double b) {
    _ensure(2);
    _data[length] = a;
    _data[length + 1] = b;
    length += 2;
  }

  void add6(double a, double b, double c, double d, double e, double f) {
    _ensure(6);
    final p = _data, n = length;
    p[n] = a;
    p[n + 1] = b;
    p[n + 2] = c;
    p[n + 3] = d;
    p[n + 4] = e;
    p[n + 5] = f;
    length += 6;
  }

  double operator [](int i) => _data[i];

  void operator []=(int i, double v) => _data[i] = v;

  /// A view of the filled prefix. Valid until the next add.
  Float64List get view => Float64List.sublistView(_data, 0, length);

  void clear() => length = 0;
}

/// Growable Float32List: vertex/segment data in its final upload layout,
/// emplaced without a conversion copy.
class FloatBuilder {
  Float32List _data;
  int length = 0;

  FloatBuilder([int capacity = 1024]) : _data = Float32List(capacity);

  bool get isEmpty => length == 0;

  double operator [](int i) => _data[i];

  void _ensure(int extra) {
    if (length + extra <= _data.length) return;
    var cap = _data.length * 2;
    while (cap < length + extra) {
      cap *= 2;
    }
    _data = Float32List(cap)..setRange(0, length, _data);
  }

  void add2(double a, double b) {
    _ensure(2);
    _data[length] = a;
    _data[length + 1] = b;
    length += 2;
  }

  void add4(double a, double b, double c, double d) {
    _ensure(4);
    final p = _data, n = length;
    p[n] = a;
    p[n + 1] = b;
    p[n + 2] = c;
    p[n + 3] = d;
    length += 4;
  }

  void add6(double a, double b, double c, double d, double e, double f) {
    _ensure(6);
    final p = _data, n = length;
    p[n] = a;
    p[n + 1] = b;
    p[n + 2] = c;
    p[n + 3] = d;
    p[n + 4] = e;
    p[n + 5] = f;
    length += 6;
  }

  /// The filled bytes; hand straight to a texture/buffer upload (which
  /// copies). sublistView bounds are element indices, not bytes.
  ByteData get bytes => ByteData.sublistView(_data, 0, length);

  /// A view of the filled prefix. Valid until the next add.
  Float32List get view => Float32List.sublistView(_data, 0, length);

  void clear() => length = 0;
}

/// One flattened subpath: `[x0,y0, x1,y1, ...]`.
/// [points] is Float64List-backed (unboxed indexing).
class FlatSubpath {
  FlatSubpath(this.points, {required this.closed});

  final Float64List points;
  final bool closed;

  int get pointCount => points.length ~/ 2;
}

/// Axis-aligned bounds of [subpaths], or null when empty.
class FlatBounds {
  FlatBounds(this.left, this.top, this.right, this.bottom);

  double left, top, right, bottom;

  void include(double x, double y) {
    if (x < left) left = x;
    if (x > right) right = x;
    if (y < top) top = y;
    if (y > bottom) bottom = y;
  }

  static FlatBounds? of(List<FlatSubpath> subpaths) {
    FlatBounds? b;
    for (final sub in subpaths) {
      final p = sub.points;
      for (var i = 0; i < p.length; i += 2) {
        if (b == null) {
          b = FlatBounds(p[i], p[i + 1], p[i], p[i + 1]);
        } else {
          b.include(p[i], p[i + 1]);
        }
      }
    }
    return b;
  }
}

/// Flattens [path] through [transform] (page space -> device pixels) into
/// polylines. Cubics subdivide adaptively to stay within [tolerance] device
/// pixels of the true curve (Wang's bound on the second differences).
List<FlatSubpath> flattenPath(PdfPath path, PdfMatrix transform,
    {double tolerance = 0.25}) {
  final out = <FlatSubpath>[];
  DoubleBuilder? current;
  var closed = false;
  var startX = 0.0, startY = 0.0;
  var lastX = 0.0, lastY = 0.0;

  void finish() {
    final done = current;
    if (done != null && done.length >= 4) {
      out.add(FlatSubpath(Float64List.fromList(done.view), closed: closed));
    }
    current = null;
    closed = false;
  }

  for (final segment in path.segments) {
    final cur = current;
    switch (segment) {
      case PdfMoveTo(:final x, :final y):
        finish();
        lastX = startX = transform.transformX(x, y);
        lastY = startY = transform.transformY(x, y);
        current = DoubleBuilder(64)..add2(startX, startY);
      case PdfLineTo(:final x, :final y):
        if (cur == null) continue;
        lastX = transform.transformX(x, y);
        lastY = transform.transformY(x, y);
        cur.add2(lastX, lastY);
      case PdfCubicTo():
        if (cur == null) continue;
        final x1 = transform.transformX(segment.x1, segment.y1);
        final y1 = transform.transformY(segment.x1, segment.y1);
        final x2 = transform.transformX(segment.x2, segment.y2);
        final y2 = transform.transformY(segment.x2, segment.y2);
        final x3 = transform.transformX(segment.x3, segment.y3);
        final y3 = transform.transformY(segment.x3, segment.y3);
        final d1 =
            math.max((lastX - 2 * x1 + x2).abs(), (lastY - 2 * y1 + y2).abs());
        final d2 =
            math.max((x1 - 2 * x2 + x3).abs(), (y1 - 2 * y2 + y3).abs());
        final d = math.max(d1, d2);
        final n = d <= tolerance
            ? 1
            : math.sqrt(3 * d / (4 * tolerance)).ceil().clamp(1, 128);
        for (var i = 1; i <= n; i++) {
          final t = i / n;
          final mt = 1 - t;
          final a = mt * mt * mt, b = 3 * mt * mt * t, c = 3 * mt * t * t;
          final e = t * t * t;
          cur.add2(a * lastX + b * x1 + c * x2 + e * x3,
              a * lastY + b * y1 + c * y2 + e * y3);
        }
        lastX = x3;
        lastY = y3;
      case PdfClosePath():
        if (cur == null) continue;
        if (lastX != startX || lastY != startY) {
          cur.add2(startX, startY);
        }
        closed = true;
        lastX = startX;
        lastY = startY;
        // `m ... h m ...` reuses the pen; a close ends the subpath here and
        // a following lineTo would be malformed input - treat close as final.
        finish();
    }
  }
  finish();
  return out;
}

/// Re-cuts [subpaths] into dash segments (§8.4.3.6). [pattern] and [phase]
/// are already in device pixels. Zero-length "on" dashes survive as
/// single-point subpaths so round caps still paint dots.
List<FlatSubpath> dashSubpaths(
    List<FlatSubpath> subpaths, List<double> pattern, double phase) {
  final dashes = [
    for (final d in pattern)
      if (d >= 0) d,
  ];
  if (dashes.length.isOdd) dashes.addAll(List.of(dashes));
  final cycle = dashes.fold(0.0, (a, b) => a + b);
  if (dashes.isEmpty || cycle <= 0) return subpaths;

  final out = <FlatSubpath>[];
  void emit(DoubleBuilder b) {
    if (b.length >= 2) {
      out.add(FlatSubpath(Float64List.fromList(b.view), closed: false));
    }
  }

  for (final sub in subpaths) {
    final p = sub.points;
    var index = 0;
    var on = true;
    var remaining = dashes[0];
    var toSkip = phase.abs() % cycle;
    while (toSkip > 0) {
      if (toSkip >= remaining) {
        toSkip -= remaining;
        index = (index + 1) % dashes.length;
        on = !on;
        remaining = dashes[index];
      } else {
        remaining -= toSkip;
        toSkip = 0;
      }
    }
    DoubleBuilder? current = on ? (DoubleBuilder(32)..add2(p[0], p[1])) : null;
    for (var i = 0; i + 3 < p.length; i += 2) {
      var ax = p[i], ay = p[i + 1];
      final bx = p[i + 2], by = p[i + 3];
      var segLen = math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay));
      while (segLen > 1e-12) {
        if (remaining >= segLen) {
          remaining -= segLen;
          segLen = 0;
          if (on) {
            current!.add2(bx, by);
          }
        } else {
          final t = remaining / segLen;
          final mx = ax + (bx - ax) * t, my = ay + (by - ay) * t;
          if (on) {
            current!.add2(mx, my);
            emit(current);
            current = null;
          } else {
            current = DoubleBuilder(32)..add2(mx, my);
          }
          ax = mx;
          ay = my;
          segLen -= remaining;
          remaining = 0;
        }
        if (remaining <= 1e-12) {
          index = (index + 1) % dashes.length;
          on = !on;
          remaining = dashes[index];
          if (remaining <= 0 && cycle <= 1e-9) break;
          if (on && current == null) current = DoubleBuilder(32)..add2(ax, ay);
          if (!on && current != null) {
            emit(current);
            current = null;
          }
        }
      }
    }
    if (current != null) emit(current);
  }
  return out;
}

/// Flattening tolerance for cached em-space glyph outlines, in em units.
///
/// The cache is scale-free (one flatten serves every occurrence of the
/// glyph), so the tolerance is picked for the common text range: 1/256 em
/// keeps the polyline within 0.25 device px of the true curve up to a
/// 64-px em (32 pt text at pixel ratio 2) and within 0.5 px at a 128-px em.
/// Display-sized text trades a slightly softer curve for never re-flattening.
const double glyphFlattenTolerance = 1 / 256;

/// A glyph outline flattened once in em space (y-up, origin on the
/// baseline) and cached per outline identity.
///
/// The font engine hands back the same [PdfPath] instance for every
/// occurrence of a glyph ([PdfFontInfo.outlineFor] memoizes), so an
/// [Expando] keyed by that identity gives a process-wide cache that dies
/// with the font - the same pattern as the canvas device's `_glyphPaths`
/// ui.Path cache. Callers transform the cached polylines straight into
/// device space (see `StripGenerator.fillOutline`) instead of re-running
/// adaptive flattening per occurrence.
class FlattenedOutline {
  FlattenedOutline._(this.subpaths);

  /// Em-space polylines. Fill semantics: every subpath is implicitly closed.
  final List<FlatSubpath> subpaths;

  bool _boundsDone = false;
  FlatBounds? _bounds;

  /// Em-space bounds of the flattened outline (memoized), or null when the
  /// outline is empty.
  FlatBounds? get bounds {
    if (!_boundsDone) {
      _bounds = FlatBounds.of(subpaths);
      _boundsDone = true;
    }
    return _bounds;
  }

  static final Expando<FlattenedOutline> _cache = Expando('FlattenedOutline');

  /// The cached flattening of [outline], flattening on first sight.
  static FlattenedOutline of(PdfPath outline) =>
      _cache[outline] ??= FlattenedOutline._(flattenPath(
          outline, PdfMatrix.identity,
          tolerance: glyphFlattenTolerance));
}
