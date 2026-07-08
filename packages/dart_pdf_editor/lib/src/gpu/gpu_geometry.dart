// CPU geometry for the experimental flutter_gpu backend: flattens PdfPaths
// into device-space polylines, fan-triangulates them for stencil-then-cover
// fills, and expands strokes (joins/caps/dashes) into triangles.
import 'dart:math' as math;

import 'package:pdf_graphics/pdf_graphics.dart';

/// One flattened subpath in device pixels: `[x0,y0, x1,y1, ...]`.
class FlatSubpath {
  FlatSubpath(this.points, {required this.closed});

  final List<double> points;
  final bool closed;

  int get pointCount => points.length ~/ 2;
}

/// Axis-aligned device-space bounds of [subpaths], or null when empty.
class FlatBounds {
  FlatBounds(this.left, this.top, this.right, this.bottom);

  double left, top, right, bottom;

  static FlatBounds? of(List<FlatSubpath> subpaths) {
    FlatBounds? b;
    for (final sub in subpaths) {
      final p = sub.points;
      for (var i = 0; i < p.length; i += 2) {
        if (b == null) {
          b = FlatBounds(p[i], p[i + 1], p[i], p[i + 1]);
        } else {
          if (p[i] < b.left) b.left = p[i];
          if (p[i] > b.right) b.right = p[i];
          if (p[i + 1] < b.top) b.top = p[i + 1];
          if (p[i + 1] > b.bottom) b.bottom = p[i + 1];
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
  List<double>? current;
  var closed = false;
  var startX = 0.0, startY = 0.0;
  var lastX = 0.0, lastY = 0.0;

  void finish() {
    final done = current;
    if (done != null && done.length >= 4) {
      out.add(FlatSubpath(done, closed: closed));
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
        current = [startX, startY];
      case PdfLineTo(:final x, :final y):
        if (cur == null) continue;
        lastX = transform.transformX(x, y);
        lastY = transform.transformY(x, y);
        cur.add(lastX);
        cur.add(lastY);
      case PdfCubicTo():
        if (cur == null) continue;
        final x1 = transform.transformX(segment.x1, segment.y1);
        final y1 = transform.transformY(segment.x1, segment.y1);
        final x2 = transform.transformX(segment.x2, segment.y2);
        final y2 = transform.transformY(segment.x2, segment.y2);
        final x3 = transform.transformX(segment.x3, segment.y3);
        final y3 = transform.transformY(segment.x3, segment.y3);
        final d1 = math.max((lastX - 2 * x1 + x2).abs(), (lastY - 2 * y1 + y2).abs());
        final d2 = math.max((x1 - 2 * x2 + x3).abs(), (y1 - 2 * y2 + y3).abs());
        final d = math.max(d1, d2);
        final n = d <= tolerance
            ? 1
            : math.sqrt(3 * d / (4 * tolerance)).ceil().clamp(1, 128);
        for (var i = 1; i <= n; i++) {
          final t = i / n;
          final mt = 1 - t;
          final a = mt * mt * mt, b = 3 * mt * mt * t, c = 3 * mt * t * t;
          final e = t * t * t;
          cur.add(a * lastX + b * x1 + c * x2 + e * x3);
          cur.add(a * lastY + b * y1 + c * y2 + e * y3);
        }
        lastX = x3;
        lastY = y3;
      case PdfClosePath():
        if (cur == null) continue;
        if (lastX != startX || lastY != startY) {
          cur.add(startX);
          cur.add(startY);
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

/// Appends fan triangles (each subpath fanned from its own first point) to
/// [out] as `[x,y]` pairs - the stencil-pass geometry for a filled path.
void appendFanTriangles(List<FlatSubpath> subpaths, List<double> out) {
  for (final sub in subpaths) {
    final p = sub.points;
    final n = p.length ~/ 2;
    for (var i = 1; i + 1 < n; i++) {
      out
        ..add(p[0])
        ..add(p[1])
        ..add(p[2 * i])
        ..add(p[2 * i + 1])
        ..add(p[2 * i + 2])
        ..add(p[2 * i + 3]);
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
    List<double>? current = on ? [p[0], p[1]] : null;
    for (var i = 0; i + 3 < p.length; i += 2) {
      var ax = p[i], ay = p[i + 1];
      final bx = p[i + 2], by = p[i + 3];
      var segLen = math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay));
      while (segLen > 1e-12) {
        if (remaining >= segLen) {
          remaining -= segLen;
          segLen = 0;
          if (on) {
            current!
              ..add(bx)
              ..add(by);
          }
        } else {
          final t = remaining / segLen;
          final mx = ax + (bx - ax) * t, my = ay + (by - ay) * t;
          if (on) {
            current!
              ..add(mx)
              ..add(my);
            out.add(FlatSubpath(current, closed: false));
            current = null;
          } else {
            current = [mx, my];
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
          if (on && current == null) current = [ax, ay];
          if (!on && current != null) {
            out.add(FlatSubpath(current, closed: false));
            current = null;
          }
        }
      }
    }
    if (current != null && current.length >= 2) {
      out.add(FlatSubpath(current, closed: false));
    }
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
  List<double> out,
) {
  final hw = math.max(width, 1.0) / 2;

  void tri(double ax, double ay, double bx, double by, double cx, double cy) {
    out
      ..add(ax)
      ..add(ay)
      ..add(bx)
      ..add(by)
      ..add(cx)
      ..add(cy);
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
    final p = <double>[];
    for (var i = 0; i < sub.points.length; i += 2) {
      final x = sub.points[i], y = sub.points[i + 1];
      if (p.length >= 2 &&
          (x - p[p.length - 2]).abs() < 1e-9 &&
          (y - p[p.length - 1]).abs() < 1e-9) {
        continue;
      }
      p
        ..add(x)
        ..add(y);
    }
    var n = p.length ~/ 2;
    final closed = sub.closed && n > 2;
    if (closed && p[0] == p[2 * n - 2] && p[1] == p[2 * n - 1]) n--;

    if (n == 1) {
      // isolated point: round/square caps paint a dot, butt paints nothing
      if (cap == 1) {
        fan(p[0], p[1], 0, 2 * math.pi);
      } else if (cap == 2) {
        tri(p[0] - hw, p[1] - hw, p[0] + hw, p[1] - hw, p[0] + hw, p[1] + hw);
        tri(p[0] - hw, p[1] - hw, p[0] + hw, p[1] + hw, p[0] - hw, p[1] + hw);
      }
      continue;
    }
    if (n < 2) continue;

    final segs = closed ? n : n - 1;
    var prevNx = 0.0, prevNy = 0.0, prevDirX = 0.0, prevDirY = 0.0;
    for (var s = 0; s < segs; s++) {
      final ax = p[2 * s], ay = p[2 * s + 1];
      final bi = (s + 1) % n;
      final bx = p[2 * bi], by = p[2 * bi + 1];
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
        var fdx = p[2] - p[0], fdy = p[3] - p[1];
        final flen = math.sqrt(fdx * fdx + fdy * fdy);
        if (flen > 1e-12) {
          fdx /= flen;
          fdy /= flen;
          _joinAt(p[0], p[1], dx, dy, fdx, fdy, nx, ny, -fdy * hw, fdx * hw,
              hw, join, miterLimit, tri, fan);
        }
      }
    }

    if (!closed) {
      // caps at both open ends
      var sdx = p[2] - p[0], sdy = p[3] - p[1];
      final sl = math.sqrt(sdx * sdx + sdy * sdy);
      var edx = p[2 * n - 2] - p[2 * n - 4], edy = p[2 * n - 1] - p[2 * n - 3];
      final el = math.sqrt(edx * edx + edy * edy);
      if (sl > 1e-12 && el > 1e-12) {
        sdx /= sl;
        sdy /= sl;
        edx /= el;
        edy /= el;
        if (cap == 1) {
          final a = math.atan2(sdy, sdx);
          fan(p[0], p[1], a + math.pi / 2, math.pi);
          final b = math.atan2(edy, edx);
          fan(p[2 * n - 2], p[2 * n - 1], b - math.pi / 2, math.pi);
        } else if (cap == 2) {
          _squareCap(p[0], p[1], -sdx, -sdy, hw, tri);
          _squareCap(p[2 * n - 2], p[2 * n - 1], edx, edy, hw, tri);
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
