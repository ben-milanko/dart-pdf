// CPU geometry for the experimental flutter_gpu backend: flattens PdfPaths
// into device-space polylines, fan-triangulates them for stencil-then-cover
// fills, and expands strokes (joins/caps/dashes) into triangles.
//
// All accumulation goes through typed-array builders: the Dart VM boxes
// every element of a growable List<double>, which made vertex generation the
// dominant CPU cost on CAD-heavy pages before these existed.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf_graphics/pdf_graphics.dart';

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

  /// A view of the filled prefix. Valid until the next add.
  Float64List get view => Float64List.sublistView(_data, 0, length);

  void clear() => length = 0;
}

/// Growable Float32List: vertex data in its final GPU layout, emplaced
/// without a conversion copy.
class FloatBuilder {
  Float32List _data;
  int length = 0;

  FloatBuilder([int capacity = 1024]) : _data = Float32List(capacity);

  bool get isEmpty => length == 0;

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

  /// The filled bytes; hand straight to HostBuffer.emplace (which copies).
  /// sublistView bounds are element indices, not bytes.
  ByteData get bytes => ByteData.sublistView(_data, 0, length);

  void clear() => length = 0;
}

/// One flattened subpath in device pixels: `[x0,y0, x1,y1, ...]`.
/// [points] is Float64List-backed (unboxed indexing).
class FlatSubpath {
  FlatSubpath(this.points, {required this.closed});

  final Float64List points;
  final bool closed;

  int get pointCount => points.length ~/ 2;
}

/// Axis-aligned device-space bounds of [subpaths], or null when empty.
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

/// True when [subpaths] is a single convex, non-self-intersecting loop, so a
/// triangle fan draws it directly and the stencil pass can be skipped
/// (rectangles - the dominant PDF fill - always pass).
bool isConvexPolygon(List<FlatSubpath> subpaths) {
  if (subpaths.length != 1) return false;
  final p = subpaths[0].points;
  var n = p.length ~/ 2;
  if (n < 3) return false;
  // drop a duplicated closing point
  if (p[0] == p[2 * n - 2] && p[1] == p[2 * n - 1]) n--;
  if (n < 3) return false;
  var sign = 0.0;
  var turning = 0.0;
  for (var i = 0; i < n; i++) {
    final ax = p[2 * i], ay = p[2 * i + 1];
    final bx = p[2 * ((i + 1) % n)], by = p[2 * ((i + 1) % n) + 1];
    final cx = p[2 * ((i + 2) % n)], cy = p[2 * ((i + 2) % n) + 1];
    final ux = bx - ax, uy = by - ay;
    final vx = cx - bx, vy = cy - by;
    final cross = ux * vy - uy * vx;
    if (cross.abs() > 1e-9) {
      if (sign == 0.0) {
        sign = cross.sign;
      } else if (cross.sign != sign) {
        return false;
      }
    }
    turning += math.atan2(cross, ux * vx + uy * vy);
  }
  // A convex loop turns exactly once; star-like consistent-sign loops turn
  // more and must go through the stencil path.
  return (turning.abs() - 2 * math.pi).abs() < 0.1;
}

/// Twice the signed area of the polygon (positive = counter-clockwise in
/// y-down device space per the shoelace sign convention used here).
double signedArea2(Float64List pts) {
  var n = pts.length ~/ 2;
  if (n >= 2 && pts[0] == pts[2 * n - 2] && pts[1] == pts[2 * n - 1]) n--;
  var area = 0.0;
  for (var i = 0, j = n - 1; i < n; j = i++) {
    area += pts[2 * j] * pts[2 * i + 1] - pts[2 * i] * pts[2 * j + 1];
  }
  return area;
}

/// Triangulates a small simple polygon by ear clipping, appending `[x,y]`
/// triangle pairs to [out]. Unlike a stencil fan, the triangles cover
/// exactly the shape - no hull overdraw and no cover pass - so qualifying
/// fills can join the batched solid geometry.
///
/// Returns false (appending nothing) when the polygon is too big, degenerate,
/// self-intersecting, or clipping stalls; the caller falls back to
/// stencil-then-cover. [pts] may carry a duplicated closing point.
bool earClipPolygon(Float64List pts, DoubleBuilder out, {int maxPoints = 160}) {
  var n = pts.length ~/ 2;
  if (n >= 2 && pts[0] == pts[2 * n - 2] && pts[1] == pts[2 * n - 1]) n--;
  if (n < 3 || n > maxPoints) return false;

  // reject self-intersecting outlines: ear clipping would mis-fill them
  for (var i = 0; i < n; i++) {
    final a1x = pts[2 * i], a1y = pts[2 * i + 1];
    final a2x = pts[2 * ((i + 1) % n)], a2y = pts[2 * ((i + 1) % n) + 1];
    for (var j = i + 2; j < n; j++) {
      if (i == 0 && j == n - 1) continue; // shares the start vertex
      final b1x = pts[2 * j], b1y = pts[2 * j + 1];
      final b2x = pts[2 * ((j + 1) % n)], b2y = pts[2 * ((j + 1) % n) + 1];
      if (_segmentsCross(a1x, a1y, a2x, a2y, b1x, b1y, b2x, b2y)) {
        return false;
      }
    }
  }

  var area = 0.0;
  for (var i = 0, j = n - 1; i < n; j = i++) {
    area += pts[2 * j] * pts[2 * i + 1] - pts[2 * i] * pts[2 * j + 1];
  }
  if (area.abs() < 1e-12) return false;
  final winding = area > 0 ? 1.0 : -1.0;

  final idx = List<int>.generate(n, (i) => i);
  final startLength = out.length;
  var remaining = n;
  var cursor = 0;
  var sinceLastClip = 0;
  while (remaining > 3) {
    if (sinceLastClip++ > remaining) {
      out.length = startLength; // stalled - undo partial output
      return false;
    }
    final p = cursor % remaining;
    final i0 = idx[p], i1 = idx[(p + 1) % remaining], i2 = idx[(p + 2) % remaining];
    final ax = pts[2 * i0], ay = pts[2 * i0 + 1];
    final bx = pts[2 * i1], by = pts[2 * i1 + 1];
    final cx = pts[2 * i2], cy = pts[2 * i2 + 1];
    final cross = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
    var isEar = cross * winding > 1e-12; // convex corner in polygon winding
    if (isEar) {
      for (var k = 0; k < remaining && isEar; k++) {
        final vi = idx[k];
        if (vi == i0 || vi == i1 || vi == i2) continue;
        if (_pointInTriangle(pts[2 * vi], pts[2 * vi + 1], ax, ay, bx, by,
            cx, cy)) {
          isEar = false;
        }
      }
    }
    if (isEar) {
      out.add6(ax, ay, bx, by, cx, cy);
      idx.removeAt((p + 1) % remaining);
      remaining--;
      sinceLastClip = 0;
    } else {
      cursor++;
    }
  }
  out.add6(pts[2 * idx[0]], pts[2 * idx[0] + 1], pts[2 * idx[1]],
      pts[2 * idx[1] + 1], pts[2 * idx[2]], pts[2 * idx[2] + 1]);
  return true;
}

bool _segmentsCross(double a1x, double a1y, double a2x, double a2y,
    double b1x, double b1y, double b2x, double b2y) {
  double orient(double px, double py, double qx, double qy, double rx,
          double ry) =>
      (qx - px) * (ry - py) - (qy - py) * (rx - px);
  final o1 = orient(a1x, a1y, a2x, a2y, b1x, b1y);
  final o2 = orient(a1x, a1y, a2x, a2y, b2x, b2y);
  final o3 = orient(b1x, b1y, b2x, b2y, a1x, a1y);
  final o4 = orient(b1x, b1y, b2x, b2y, a2x, a2y);
  return o1 * o2 < 0 && o3 * o4 < 0; // proper crossing only
}

bool _pointInTriangle(double px, double py, double ax, double ay, double bx,
    double by, double cx, double cy) {
  final d1 = (px - bx) * (ay - by) - (ax - bx) * (py - by);
  final d2 = (px - cx) * (by - cy) - (bx - cx) * (py - cy);
  final d3 = (px - ax) * (cy - ay) - (cx - ax) * (py - ay);
  final hasNeg = d1 < 0 || d2 < 0 || d3 < 0;
  final hasPos = d1 > 0 || d2 > 0 || d3 > 0;
  return !(hasNeg && hasPos);
}

/// Appends fan triangles (each subpath fanned from its own first point) to
/// [out] as `[x,y]` pairs - the stencil-pass geometry for a filled path.
void appendFanTriangles(List<FlatSubpath> subpaths, DoubleBuilder out) {
  for (final sub in subpaths) {
    final p = sub.points;
    final n = p.length ~/ 2;
    final x0 = n > 0 ? p[0] : 0.0, y0 = n > 0 ? p[1] : 0.0;
    for (var i = 1; i + 1 < n; i++) {
      out.add6(x0, y0, p[2 * i], p[2 * i + 1], p[2 * i + 2], p[2 * i + 3]);
    }
  }
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

/// Expands stroked [subpaths] into triangles appended to [out] as `[x,y]`
/// pairs. [width] is the full stroke width in device pixels. Joins:
/// 0 miter (falling back to bevel past [miterLimit]), 1 round, 2 bevel.
/// Caps: 0 butt, 1 round, 2 square. The output triangles overlap at joins,
/// so translucent strokes must composite through a stencil-union pass.
void appendStrokeTriangles(
  List<FlatSubpath> subpaths,
  double width,
  int cap,
  int join,
  double miterLimit,
  DoubleBuilder out,
) {
  final hw = math.max(width, 1.0) / 2;

  void tri(double ax, double ay, double bx, double by, double cx, double cy) {
    out.add6(ax, ay, bx, by, cx, cy);
  }

  void fan(double cx, double cy, double fromAngle, double sweep) {
    final steps = math.max(2, (sweep.abs() / 0.35).ceil());
    for (var i = 0; i < steps; i++) {
      final a0 = fromAngle + sweep * i / steps;
      final a1 = fromAngle + sweep * (i + 1) / steps;
      tri(cx, cy, cx + hw * math.cos(a0), cy + hw * math.sin(a0),
          cx + hw * math.cos(a1), cy + hw * math.sin(a1));
    }
  }

  for (final sub in subpaths) {
    // strip consecutive duplicates
    final raw = sub.points;
    final p = DoubleBuilder(raw.length);
    for (var i = 0; i < raw.length; i += 2) {
      final x = raw[i], y = raw[i + 1];
      if (p.length >= 2 &&
          (x - p[p.length - 2]).abs() < 1e-9 &&
          (y - p[p.length - 1]).abs() < 1e-9) {
        continue;
      }
      p.add2(x, y);
    }
    final pts = p.view;
    var n = pts.length ~/ 2;
    final closed = sub.closed && n > 2;
    if (closed && pts[0] == pts[2 * n - 2] && pts[1] == pts[2 * n - 1]) n--;

    if (n == 1) {
      // isolated point: round/square caps paint a dot, butt paints nothing
      if (cap == 1) {
        fan(pts[0], pts[1], 0, 2 * math.pi);
      } else if (cap == 2) {
        tri(pts[0] - hw, pts[1] - hw, pts[0] + hw, pts[1] - hw, pts[0] + hw,
            pts[1] + hw);
        tri(pts[0] - hw, pts[1] - hw, pts[0] + hw, pts[1] + hw, pts[0] - hw,
            pts[1] + hw);
      }
      continue;
    }
    if (n < 2) continue;

    final segs = closed ? n : n - 1;
    var prevNx = 0.0, prevNy = 0.0, prevDirX = 0.0, prevDirY = 0.0;
    for (var s = 0; s < segs; s++) {
      final ax = pts[2 * s], ay = pts[2 * s + 1];
      final bi = (s + 1) % n;
      final bx = pts[2 * bi], by = pts[2 * bi + 1];
      var dx = bx - ax, dy = by - ay;
      final len = math.sqrt(dx * dx + dy * dy);
      if (len < 1e-12) continue;
      dx /= len;
      dy /= len;
      final nx = -dy * hw, ny = dx * hw;

      // segment body
      tri(ax + nx, ay + ny, bx + nx, by + ny, bx - nx, by - ny);
      tri(ax + nx, ay + ny, bx - nx, by - ny, ax - nx, ay - ny);

      // join with the previous segment at (ax, ay)
      if (s > 0 || closed) {
        if (s == 0 && closed) {
          // defer the wrap join to the end of the loop when prev* is known
        } else {
          _joinAt(ax, ay, prevDirX, prevDirY, dx, dy, prevNx, prevNy, nx, ny,
              hw, join, miterLimit, tri, fan);
        }
      }
      prevNx = nx;
      prevNy = ny;
      prevDirX = dx;
      prevDirY = dy;

      if (closed && s == segs - 1) {
        // wrap join at the start point between the last and first segments
        var fdx = pts[2] - pts[0], fdy = pts[3] - pts[1];
        final flen = math.sqrt(fdx * fdx + fdy * fdy);
        if (flen > 1e-12) {
          fdx /= flen;
          fdy /= flen;
          _joinAt(pts[0], pts[1], dx, dy, fdx, fdy, nx, ny, -fdy * hw,
              fdx * hw, hw, join, miterLimit, tri, fan);
        }
      }
    }

    if (!closed) {
      // caps at both open ends
      var sdx = pts[2] - pts[0], sdy = pts[3] - pts[1];
      final sl = math.sqrt(sdx * sdx + sdy * sdy);
      var edx = pts[2 * n - 2] - pts[2 * n - 4],
          edy = pts[2 * n - 1] - pts[2 * n - 3];
      final el = math.sqrt(edx * edx + edy * edy);
      if (sl > 1e-12 && el > 1e-12) {
        sdx /= sl;
        sdy /= sl;
        edx /= el;
        edy /= el;
        if (cap == 1) {
          final a = math.atan2(sdy, sdx);
          fan(pts[0], pts[1], a + math.pi / 2, math.pi);
          final b = math.atan2(edy, edx);
          fan(pts[2 * n - 2], pts[2 * n - 1], b - math.pi / 2, math.pi);
        } else if (cap == 2) {
          _squareCap(pts[0], pts[1], -sdx, -sdy, hw, tri);
          _squareCap(pts[2 * n - 2], pts[2 * n - 1], edx, edy, hw, tri);
        }
      }
    }
  }
}

void _squareCap(
    double x,
    double y,
    double dx,
    double dy,
    double hw,
    void Function(double, double, double, double, double, double) tri) {
  final nx = -dy * hw, ny = dx * hw;
  final ex = x + dx * hw, ey = y + dy * hw;
  tri(x + nx, y + ny, ex + nx, ey + ny, ex - nx, ey - ny);
  tri(x + nx, y + ny, ex - nx, ey - ny, x - nx, y - ny);
}

void _joinAt(
  double x,
  double y,
  double d0x,
  double d0y,
  double d1x,
  double d1y,
  double n0x,
  double n0y,
  double n1x,
  double n1y,
  double hw,
  int join,
  double miterLimit,
  void Function(double, double, double, double, double, double) tri,
  void Function(double, double, double, double) fan,
) {
  final cross = d0x * d1y - d0y * d1x;
  if (cross.abs() < 1e-9) return; // collinear: quads already meet
  // outer side is the turn's convex side
  final outer0x = cross > 0 ? -n0x : n0x, outer0y = cross > 0 ? -n0y : n0y;
  final outer1x = cross > 0 ? -n1x : n1x, outer1y = cross > 0 ? -n1y : n1y;
  switch (join) {
    case 1: // round
      final a0 = math.atan2(outer0y, outer0x);
      var sweep = math.atan2(outer1y, outer1x) - a0;
      while (sweep > math.pi) {
        sweep -= 2 * math.pi;
      }
      while (sweep < -math.pi) {
        sweep += 2 * math.pi;
      }
      fan(x, y, a0, sweep);
    case 2: // bevel
      tri(x, y, x + outer0x, y + outer0y, x + outer1x, y + outer1y);
    default: // miter, bevel past the limit
      final mx = outer0x + outer1x, my = outer0y + outer1y;
      final mlen2 = mx * mx + my * my;
      if (mlen2 < 1e-12) {
        tri(x, y, x + outer0x, y + outer0y, x + outer1x, y + outer1y);
        return;
      }
      // miter point: along (m) scaled so its projection touches both offsets
      final scale = 2 * hw * hw / mlen2;
      final px = mx * scale, py = my * scale;
      final miterRatio = math.sqrt(px * px + py * py) / hw;
      if (miterRatio > miterLimit) {
        tri(x, y, x + outer0x, y + outer0y, x + outer1x, y + outer1y);
      } else {
        tri(x, y, x + outer0x, y + outer0y, x + px, y + py);
        tri(x, y, x + px, y + py, x + outer1x, y + outer1y);
      }
  }
}
