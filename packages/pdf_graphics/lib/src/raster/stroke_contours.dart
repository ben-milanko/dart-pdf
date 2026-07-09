// Stroke expansion for the CPU strip rasterizer: turns stroked polylines
// into closed polygon contours (per-segment quads, join wedges, caps) that
// feed the nonzero fill kernel. Contours from one stroke overlap freely at
// joins - every ring is normalized to the same winding orientation, so
// overlap only pushes the nonzero winding count above 1, which
// `min(1, |w|)` flattens back to full coverage (no cancellation).
//
// Geometry semantics match the flutter_gpu experiment's
// appendStrokeTriangles except for hairlines: width is the full stroke
// width in device pixels, drawn EXACTLY - a 0.5-px stroke becomes a
// 0.5-px contour whose antialiased coverage is a half-covered band, the
// same as Skia's sub-pixel stroking (the GPU experiment clamped to >= 1 px
// because its aliased raster would otherwise drop thin strokes; a
// coverage-based consumer must not - Ghent's 0.25-pt X patches showed the
// clamp as a fat-stroke parity failure). Width <= 0 is the PDF hairline
// ("thinnest renderable", §8.4.3.2) and draws 1 device px. Joins are
// 0 miter (falling back to bevel past the miter limit), 1 round, 2 bevel;
// caps are 0 butt, 1 round, 2 projecting square (§8.4.3.3-4). Dashing is
// the caller's job via [dashSubpaths] - dashes are re-cut polylines, so
// they flow through here unchanged.
import 'dart:math' as math;
import 'dart:typed_data';

import 'flatten.dart';

/// Closed polygon contours accumulated as one flat point list plus ring
/// boundaries; reused across strokes (clear + refill, no reallocation).
class StrokeContours {
  final DoubleBuilder points = DoubleBuilder(512);
  Int32List _ringEnds = Int32List(64);
  int ringCount = 0;

  int _ringStart = 0;

  /// Start offset (in doubles) of ring [i] within [points].
  int ringStart(int i) => i == 0 ? 0 : _ringEnds[i - 1];

  /// End offset (exclusive, in doubles) of ring [i] within [points].
  int ringEnd(int i) => _ringEnds[i];

  bool get isEmpty => ringCount == 0;

  void clear() {
    points.clear();
    ringCount = 0;
    _ringStart = 0;
  }

  void _beginRing() {
    _ringStart = points.length;
  }

  void _add(double x, double y) => points.add2(x, y);

  /// Closes the ring under construction: drops degenerate rings, normalizes
  /// winding so every ring in the set turns the same way (shoelace-positive),
  /// and records the ring boundary.
  void _endRing() {
    final start = _ringStart;
    final end = points.length;
    final n = (end - start) ~/ 2;
    if (n < 3) {
      points.length = start; // degenerate: drop
      return;
    }
    // Shoelace signed area; normalize to positive so nonzero winding of
    // overlapping rings accumulates instead of cancelling.
    var area = 0.0;
    for (var i = 0, j = n - 1; i < n; j = i++) {
      area += points[start + 2 * j] * points[start + 2 * i + 1] -
          points[start + 2 * i] * points[start + 2 * j + 1];
    }
    if (area.abs() < 1e-12) {
      points.length = start; // zero-area sliver: drop
      return;
    }
    if (area < 0) {
      // reverse the ring in place
      for (var i = 0, j = n - 1; i < j; i++, j--) {
        final xi = points[start + 2 * i];
        final yi = points[start + 2 * i + 1];
        points[start + 2 * i] = points[start + 2 * j];
        points[start + 2 * i + 1] = points[start + 2 * j + 1];
        points[start + 2 * j] = xi;
        points[start + 2 * j + 1] = yi;
      }
    }
    if (ringCount == _ringEnds.length) {
      _ringEnds = Int32List(_ringEnds.length * 2)
        ..setRange(0, ringCount, _ringEnds);
    }
    _ringEnds[ringCount++] = end;
  }
}

/// Expands stroked [subpaths] (already flattened, already dashed, device
/// pixels) into closed contours appended to [out]. See the library comment
/// for parameter semantics.
void strokeToContours(
  List<FlatSubpath> subpaths, {
  required double width,
  required int cap,
  required int join,
  required double miterLimit,
  required StrokeContours out,
}) {
  final hw = (width <= 0 ? 1.0 : width) / 2;

  void wedge(double px, double py, double ax, double ay, double bx, double by) {
    out._beginRing();
    out._add(px, py);
    out._add(ax, ay);
    out._add(bx, by);
    out._endRing();
  }

  // Circular-arc polygon fanned from (cx, cy); same step density as the GPU
  // triangle fan (<= 0.35 rad per step).
  void fan(double cx, double cy, double fromAngle, double sweep) {
    final steps = math.max(2, (sweep.abs() / 0.35).ceil());
    out._beginRing();
    out._add(cx, cy);
    for (var i = 0; i <= steps; i++) {
      final a = fromAngle + sweep * i / steps;
      out._add(cx + hw * math.cos(a), cy + hw * math.sin(a));
    }
    out._endRing();
  }

  void joinAt(double x, double y, double d0x, double d0y, double d1x,
      double d1y, double n0x, double n0y, double n1x, double n1y) {
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
        wedge(x, y, x + outer0x, y + outer0y, x + outer1x, y + outer1y);
      default: // miter, bevel past the limit
        final mx = outer0x + outer1x, my = outer0y + outer1y;
        final mlen2 = mx * mx + my * my;
        if (mlen2 < 1e-12) {
          wedge(x, y, x + outer0x, y + outer0y, x + outer1x, y + outer1y);
          return;
        }
        // miter point: along (m) scaled so its projection touches both
        // offset lines
        final scale = 2 * hw * hw / mlen2;
        final px = mx * scale, py = my * scale;
        final miterRatio = math.sqrt(px * px + py * py) / hw;
        if (miterRatio > miterLimit) {
          wedge(x, y, x + outer0x, y + outer0y, x + outer1x, y + outer1y);
        } else {
          out._beginRing();
          out._add(x, y);
          out._add(x + outer0x, y + outer0y);
          out._add(x + px, y + py);
          out._add(x + outer1x, y + outer1y);
          out._endRing();
        }
    }
  }

  void squareCap(double x, double y, double dx, double dy) {
    final nx = -dy * hw, ny = dx * hw;
    final ex = x + dx * hw, ey = y + dy * hw;
    out._beginRing();
    out._add(x + nx, y + ny);
    out._add(ex + nx, ey + ny);
    out._add(ex - nx, ey - ny);
    out._add(x - nx, y - ny);
    out._endRing();
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
        fan(pts[0], pts[1], 0, math.pi);
        fan(pts[0], pts[1], math.pi, math.pi);
      } else if (cap == 2) {
        out._beginRing();
        out._add(pts[0] - hw, pts[1] - hw);
        out._add(pts[0] + hw, pts[1] - hw);
        out._add(pts[0] + hw, pts[1] + hw);
        out._add(pts[0] - hw, pts[1] + hw);
        out._endRing();
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

      // segment body quad
      out._beginRing();
      out._add(ax + nx, ay + ny);
      out._add(bx + nx, by + ny);
      out._add(bx - nx, by - ny);
      out._add(ax - nx, ay - ny);
      out._endRing();

      // join with the previous segment at (ax, ay)
      if (s > 0 || closed) {
        if (s == 0 && closed) {
          // the wrap join is emitted after the loop when prev* is known
        } else {
          joinAt(ax, ay, prevDirX, prevDirY, dx, dy, prevNx, prevNy, nx, ny);
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
          joinAt(pts[0], pts[1], dx, dy, fdx, fdy, nx, ny, -fdy * hw,
              fdx * hw);
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
          squareCap(pts[0], pts[1], -sdx, -sdy);
          squareCap(pts[2 * n - 2], pts[2 * n - 1], edx, edy);
        }
      }
    }
  }
}
