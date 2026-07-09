// vello_hybrid-style sparse-strip generation: the CPU fine-rasterizes each
// fill into 4-px-tall strip rows (font-rs signed-area accumulation +
// prefix sum), then emits a compact SoA strip list where fully-covered
// runs carry no alpha bytes and mixed columns append 4 coverage bytes
// (one RGBA8888 texel) to a shared alpha atlas. A GPU consumer draws every
// strip as a quad and samples the atlas; a CPU consumer can composite the
// strips directly. Pure Dart - no dart:ui, no dart:io.
//
// Layout (all SoA, reused across pages):
//  - xy:          x | y<<16 (u16|u16), strip origin in device px, y = row top
//  - widthFlags:  width in columns (u16) | stripFlagSolid | stripFlagEvenOdd
//  - alphaOffset: column index into [StripBuffer.alphas] (4 bytes/column),
//                 or [stripSolidSentinel] for solid strips
//  - color:       premultiplied RGBA8 in memory byte order r,g,b,a
//                 (little-endian u32 r | g<<8 | b<<16 | a<<24)
//  - alphas:      column-major coverage, 4 bytes per column = one RGBA8888
//                 texel (byte k = scanline k of the strip row)
import 'dart:math' as math;
import 'dart:typed_data';

import '../color.dart';
import '../matrix.dart';
import '../path.dart';
import 'flatten.dart';
import 'stroke_contours.dart';

/// widthFlags bit: strip is fully covered - no alpha bytes, alphaOffset is
/// [stripSolidSentinel].
const int stripFlagSolid = 0x10000;

/// widthFlags bit: the fill that produced this strip used the even-odd rule
/// (informational - coverage is already resolved CPU-side).
const int stripFlagEvenOdd = 0x20000;

/// alphaOffset value for solid strips.
const int stripSolidSentinel = 0xFFFFFFFF;

/// Packs [color] at [alpha] into premultiplied RGBA8 (r | g<<8 | b<<16 |
/// a<<24 - RGBA8888 memory byte order on little-endian targets).
int premulRgba8(PdfColor color, double alpha) {
  final af = alpha < 0 ? 0.0 : (alpha > 1 ? 1.0 : alpha);
  final a = (af * 255 + 0.5).toInt();
  int chan(double c) {
    final v = c < 0 ? 0.0 : (c > 1 ? 1.0 : c);
    return ((v * 255 + 0.5).toInt() * a + 127) ~/ 255;
  }

  return chan(color.red) |
      (chan(color.green) << 8) |
      (chan(color.blue) << 16) |
      (a << 24);
}

/// The strip list under construction. Typed arrays grow geometrically and
/// are reused across pages ([reset] keeps capacity).
class StripBuffer {
  int length = 0;
  Uint32List xy = Uint32List(1024);
  Uint32List widthFlags = Uint32List(1024);
  Uint32List alphaOffset = Uint32List(1024);
  Uint32List color = Uint32List(1024);

  // Alpha atlas kept as u32 texels so solid/mixed columns append with one
  // 4-byte store; exposed as bytes for RGBA8888 upload.
  Uint32List _alphaTexels = Uint32List(4096);
  int alphaColumns = 0;

  /// Column-major coverage bytes (4 per column); length = 4 * alphaColumns.
  Uint8List get alphas => Uint8List.sublistView(_alphaTexels, 0, alphaColumns);

  /// The alpha atlas as whole texels (one u32 per column).
  Uint32List get alphaTexels =>
      Uint32List.sublistView(_alphaTexels, 0, alphaColumns);

  void reset() {
    length = 0;
    alphaColumns = 0;
  }

  void _ensureStrips(int extra) {
    if (length + extra <= xy.length) return;
    var cap = xy.length * 2;
    while (cap < length + extra) {
      cap *= 2;
    }
    xy = Uint32List(cap)..setRange(0, length, xy);
    widthFlags = Uint32List(cap)..setRange(0, length, widthFlags);
    alphaOffset = Uint32List(cap)..setRange(0, length, alphaOffset);
    color = Uint32List(cap)..setRange(0, length, color);
  }

  void _emit(int x, int y, int width, int flags, int alphaOff, int rgba) {
    _ensureStrips(1);
    final n = length;
    xy[n] = x | (y << 16);
    widthFlags[n] = width | flags;
    alphaOffset[n] = alphaOff;
    color[n] = rgba;
    length = n + 1;
  }

  void _appendTexel(int texel) {
    if (alphaColumns == _alphaTexels.length) {
      _alphaTexels = Uint32List(_alphaTexels.length * 2)
        ..setRange(0, alphaColumns, _alphaTexels);
    }
    _alphaTexels[alphaColumns++] = texel;
  }
}

/// Fine-rasterizes fills, strokes, and glyph outlines into a [StripBuffer].
///
/// Per fill: flatten to device-space edges (Wang's bound, same semantics as
/// [flattenPath]) -> clip to the viewport (x-clipping projects offscreen
/// portions onto the viewport edge so winding is preserved) -> y-slice
/// edges into 4-px strip rows via intrusive typed-array linked lists ->
/// font-rs signed-area accumulation into a reused Float32List (4 scanlines
/// x row width) -> per-column prefix sum -> fill rule (nonzero
/// `min(1,|w|)`, even-odd triangle wave `|w - 2 round(w/2)|`) -> strip
/// emission (zero runs skipped, all-255 runs of >= 2 columns become solid
/// strips, mixed columns append alpha texels). Only the touched accumulator
/// span is zeroed behind the scan.
class StripGenerator {
  final StripBuffer strips = StripBuffer();

  int _width = 0;
  int _height = 0;
  int _rowCount = 0;
  int _stride = 0;

  Float32List _accum = Float32List(0);
  Int32List _rowHead = Int32List(0);
  Int32List _rowMinX = Int32List(0);
  Int32List _rowMaxX = Int32List(0);
  Int32List _dirtyRows = Int32List(256);
  int _dirtyCount = 0;

  // Edge nodes, y-sliced per row: x0, y0, x1, y1 (y row-local 0..4, in the
  // edge's own direction so the winding sign survives slicing).
  Float32List _nodes = Float32List(4096);
  Int32List _nodeNext = Int32List(1024);
  int _nodeCount = 0;

  // Pen state for the direct flatten-into-edges path.
  double _penX = 0, _penY = 0, _startX = 0, _startY = 0;
  bool _subpathOpen = false;

  final StrokeContours _contours = StrokeContours();

  int get width => _width;
  int get height => _height;

  /// Number of 4-px strip rows covering the viewport.
  int get rowCount => _rowCount;

  /// Starts a new page/batch: sets the device viewport (pixels) and clears
  /// the strip buffer. Scratch buffers are kept and only grow.
  void begin(int width, int height) {
    _width = width;
    _height = height;
    _rowCount = (height + 3) >> 2;
    _stride = width + 2;
    if (_accum.length < 4 * _stride) {
      _accum = Float32List(4 * _stride);
    } else {
      _accum.fillRange(0, 4 * _stride, 0); // defensive: restore invariant
    }
    if (_rowHead.length < _rowCount) {
      _rowHead = Int32List(_rowCount);
      _rowMinX = Int32List(_rowCount);
      _rowMaxX = Int32List(_rowCount);
    }
    _rowHead.fillRange(0, _rowCount, -1);
    _dirtyCount = 0;
    _nodeCount = 0;
    strips.reset();
  }

  /// Fills [path] (page space) mapped through [transform] into device
  /// space. [rgba] is a premultiplied color from [premulRgba8].
  void fillPath(PdfPath path, PdfMatrix transform, PdfFillRule rule, int rgba,
      {double tolerance = 0.25}) {
    if (path.isEmpty || _rowCount == 0) return;
    if (_cullPath(path, transform)) return;
    _flattenEdges(path, transform, tolerance);
    _finishShape(rule, rgba);
  }

  /// Strokes [path] (page space, stroke parameters in page space like
  /// [PdfDevice.strokePath]) by expanding to closed contours and filling
  /// them nonzero.
  void strokePath(
      PdfPath path, PdfMatrix transform, PdfStroke stroke, int rgba,
      {double tolerance = 0.25}) {
    if (path.isEmpty || _rowCount == 0) return;
    final sf = transform.scaleFactor;
    var subs = flattenPath(path, transform, tolerance: tolerance);
    if (subs.isEmpty) return;
    if (stroke.dashArray.isNotEmpty &&
        stroke.dashArray.any((d) => d > 0)) {
      subs = dashSubpaths(subs, [for (final d in stroke.dashArray) d * sf],
          stroke.dashPhase * sf);
    }
    _contours.clear();
    strokeToContours(subs,
        width: stroke.width * sf,
        cap: stroke.cap,
        join: stroke.join,
        miterLimit: stroke.miterLimit,
        out: _contours);
    fillContours(_contours, rgba);
  }

  /// Fills already-flattened device-space subpaths (each implicitly
  /// closed - PDF fill semantics).
  void fillSubpaths(List<FlatSubpath> subpaths, PdfFillRule rule, int rgba) {
    if (subpaths.isEmpty || _rowCount == 0) return;
    for (final sub in subpaths) {
      _addRing(sub.points, 0, sub.points.length);
    }
    _finishShape(rule, rgba);
  }

  /// Fills stroke-expansion [contours] (device space) with the nonzero rule.
  void fillContours(StrokeContours contours, int rgba) {
    if (contours.isEmpty || _rowCount == 0) return;
    for (var i = 0; i < contours.ringCount; i++) {
      _addRingBuilder(
          contours.points, contours.ringStart(i), contours.ringEnd(i));
    }
    _finishShape(PdfFillRule.nonzero, rgba);
  }

  /// Fills a cached em-space glyph [outline] through [emToDevice]
  /// (em space -> device pixels): transform-and-bin, no re-flattening.
  /// Glyph outlines fill nonzero (§9.4).
  void fillOutline(FlattenedOutline outline, PdfMatrix emToDevice, int rgba) {
    if (_rowCount == 0) return;
    final a = emToDevice.a, b = emToDevice.b, c = emToDevice.c;
    final d = emToDevice.d, e = emToDevice.e, f = emToDevice.f;
    var any = false;
    for (final sub in outline.subpaths) {
      final p = sub.points;
      final n = p.length;
      if (n < 4) continue;
      var firstX = 0.0, firstY = 0.0, prevX = 0.0, prevY = 0.0;
      for (var i = 0; i < n; i += 2) {
        final px = p[i], py = p[i + 1];
        final x = a * px + c * py + e;
        final y = b * px + d * py + f;
        if (i == 0) {
          firstX = prevX = x;
          firstY = prevY = y;
        } else {
          _edge(prevX, prevY, x, y);
          prevX = x;
          prevY = y;
        }
      }
      if (prevX != firstX || prevY != firstY) {
        _edge(prevX, prevY, firstX, firstY);
      }
      any = true;
    }
    if (any) _finishShape(PdfFillRule.nonzero, rgba);
  }

  // ---- culling ---------------------------------------------------------

  /// True when the path's transformed control-point bbox (contains the
  /// curves) cannot affect any visible column: fully above/below the
  /// viewport, or fully to one side (a closed shape entirely off one side
  /// contributes zero winding to visible columns).
  bool _cullPath(PdfPath path, PdfMatrix m) {
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    void pt(double x, double y) {
      final dx = m.transformX(x, y), dy = m.transformY(x, y);
      if (dx < minX) minX = dx;
      if (dx > maxX) maxX = dx;
      if (dy < minY) minY = dy;
      if (dy > maxY) maxY = dy;
    }

    for (final s in path.segments) {
      switch (s) {
        case PdfMoveTo(:final x, :final y):
          pt(x, y);
        case PdfLineTo(:final x, :final y):
          pt(x, y);
        case PdfCubicTo():
          pt(s.x1, s.y1);
          pt(s.x2, s.y2);
          pt(s.x3, s.y3);
        case PdfClosePath():
          break;
      }
    }
    if (maxX < minX) return true; // no points
    return maxY <= 0 ||
        minY >= _rowCount * 4.0 ||
        maxX <= 0 ||
        minX >= _width.toDouble();
  }

  // ---- flattening straight into edges ----------------------------------

  void _flattenEdges(PdfPath path, PdfMatrix m, double tolerance) {
    _subpathOpen = false;
    for (final segment in path.segments) {
      switch (segment) {
        case PdfMoveTo(:final x, :final y):
          _closeSubpath();
          _penX = _startX = m.transformX(x, y);
          _penY = _startY = m.transformY(x, y);
          _subpathOpen = true;
        case PdfLineTo(:final x, :final y):
          if (!_subpathOpen) continue;
          final dx = m.transformX(x, y), dy = m.transformY(x, y);
          _edge(_penX, _penY, dx, dy);
          _penX = dx;
          _penY = dy;
        case PdfCubicTo():
          if (!_subpathOpen) continue;
          final x1 = m.transformX(segment.x1, segment.y1);
          final y1 = m.transformY(segment.x1, segment.y1);
          final x2 = m.transformX(segment.x2, segment.y2);
          final y2 = m.transformY(segment.x2, segment.y2);
          final x3 = m.transformX(segment.x3, segment.y3);
          final y3 = m.transformY(segment.x3, segment.y3);
          final d1 = math.max((_penX - 2 * x1 + x2).abs(),
              (_penY - 2 * y1 + y2).abs());
          final d2 =
              math.max((x1 - 2 * x2 + x3).abs(), (y1 - 2 * y2 + y3).abs());
          final d = math.max(d1, d2);
          final n = d <= tolerance
              ? 1
              : math.sqrt(3 * d / (4 * tolerance)).ceil().clamp(1, 128);
          var px = _penX, py = _penY;
          for (var i = 1; i <= n; i++) {
            final t = i / n;
            final mt = 1 - t;
            final ba = mt * mt * mt,
                bb = 3 * mt * mt * t,
                bc = 3 * mt * t * t;
            final be = t * t * t;
            final qx = ba * _penX + bb * x1 + bc * x2 + be * x3;
            final qy = ba * _penY + bb * y1 + bc * y2 + be * y3;
            _edge(px, py, qx, qy);
            px = qx;
            py = qy;
          }
          _penX = x3;
          _penY = y3;
        case PdfClosePath():
          if (!_subpathOpen) continue;
          _closeSubpath();
          _penX = _startX;
          _penY = _startY;
          _subpathOpen = true; // pen stays; a following lineTo reopens
      }
    }
    _closeSubpath();
  }

  void _closeSubpath() {
    if (!_subpathOpen) return;
    if (_penX != _startX || _penY != _startY) {
      _edge(_penX, _penY, _startX, _startY);
    }
    _subpathOpen = false;
  }

  void _addRing(Float64List pts, int start, int end) {
    final n = end - start;
    if (n < 6) return;
    final firstX = pts[start], firstY = pts[start + 1];
    var prevX = firstX, prevY = firstY;
    for (var i = start + 2; i < end; i += 2) {
      _edge(prevX, prevY, pts[i], pts[i + 1]);
      prevX = pts[i];
      prevY = pts[i + 1];
    }
    if (prevX != firstX || prevY != firstY) {
      _edge(prevX, prevY, firstX, firstY);
    }
  }

  void _addRingBuilder(DoubleBuilder pts, int start, int end) {
    final n = end - start;
    if (n < 6) return;
    final firstX = pts[start], firstY = pts[start + 1];
    var prevX = firstX, prevY = firstY;
    for (var i = start + 2; i < end; i += 2) {
      _edge(prevX, prevY, pts[i], pts[i + 1]);
      prevX = pts[i];
      prevY = pts[i + 1];
    }
    if (prevX != firstX || prevY != firstY) {
      _edge(prevX, prevY, firstX, firstY);
    }
  }

  // ---- clipping + binning ----------------------------------------------

  /// Adds one device-space edge: clips y to the strip range, projects
  /// out-of-viewport x onto the boundary (splitting at x = 0 / x = width so
  /// winding is preserved exactly), and y-slices the pieces into rows.
  void _edge(double x0, double y0, double x1, double y1) {
    if (y0 == y1) return; // horizontal: no winding
    if (!x0.isFinite || !y0.isFinite || !x1.isFinite || !y1.isFinite) {
      return; // broken transforms produce NaN/inf geometry - drop it
    }
    final yLimit = _rowCount * 4.0;

    // Parametric y-clip to [0, yLimit].
    var t0 = 0.0, t1 = 1.0;
    final dy = y1 - y0;
    final ta = (0 - y0) / dy, tb = (yLimit - y0) / dy;
    final tenter = ta < tb ? ta : tb, texit = ta < tb ? tb : ta;
    if (tenter > t0) t0 = tenter;
    if (texit < t1) t1 = texit;
    if (t0 >= t1) return;
    final dx = x1 - x0;
    var ax = x0 + dx * t0, ay = y0 + dy * t0;
    final bx = x0 + dx * t1, by = y0 + dy * t1;

    // Split at x = 0 and x = width crossings (at most two interior
    // breakpoints); out-of-range pieces become vertical edges on the
    // boundary, preserving their winding contribution.
    final w = _width.toDouble();
    if (ax == bx) {
      var cx = ax;
      if (cx < 0) cx = 0;
      if (cx > w) cx = w;
      _binSegment(cx, ay, cx, by);
      return;
    }
    // Breakpoint parameters along (ax..bx).
    final inv = 1.0 / (bx - ax);
    var s0 = (0 - ax) * inv; // crossing of x=0
    var s1 = (w - ax) * inv; // crossing of x=width
    if (s0 > s1) {
      final tmp = s0;
      s0 = s1;
      s1 = tmp;
    }
    var prevS = 0.0;
    var px = ax, py = ay;
    void piece(double s) {
      if (s <= prevS) return;
      final cs = s < 1 ? s : 1.0;
      if (cs <= prevS) return;
      final qx = ax + (bx - ax) * cs, qy = ay + (by - ay) * cs;
      final midX = (px + qx) * 0.5;
      if (midX < 0) {
        _binSegment(0, py, 0, qy);
      } else if (midX > w) {
        _binSegment(w, py, w, qy);
      } else {
        _binSegment(px, py, qx, qy);
      }
      px = qx;
      py = qy;
      prevS = cs;
    }

    if (s0 > 0 && s0 < 1) piece(s0);
    if (s1 > 0 && s1 < 1) piece(s1);
    piece(1);
  }

  /// Y-slices an in-viewport edge into 4-px rows and links the nodes.
  void _binSegment(double x0, double y0, double x1, double y1) {
    if (y0 == y1) return;
    final down = y1 > y0;
    final ymin = down ? y0 : y1, ymax = down ? y1 : y0;
    final xAtMin = down ? x0 : x1, xAtMax = down ? x1 : x0;
    final slope = (xAtMax - xAtMin) / (ymax - ymin); // dx/dy
    final w = _width.toDouble();
    var r0 = (ymin * 0.25).floor();
    var r1 = (ymax * 0.25).ceil() - 1;
    if (r0 < 0) r0 = 0;
    if (r1 >= _rowCount) r1 = _rowCount - 1;
    for (var r = r0; r <= r1; r++) {
      final slabTop = r * 4.0;
      final ys = ymin > slabTop ? ymin : slabTop;
      final ye = ymax < slabTop + 4 ? ymax : slabTop + 4;
      if (ye <= ys) continue;
      // clamp against fp drift at the x-split breakpoints
      var xs = xAtMin + (ys - ymin) * slope;
      var xe = xAtMin + (ye - ymin) * slope;
      if (xs < 0) {
        xs = 0;
      } else if (xs > w) {
        xs = w;
      }
      if (xe < 0) {
        xe = 0;
      } else if (xe > w) {
        xe = w;
      }
      // node in original direction so dy keeps its sign
      if (down) {
        _pushNode(r, xs, ys - slabTop, xe, ye - slabTop);
      } else {
        _pushNode(r, xe, ye - slabTop, xs, ys - slabTop);
      }
    }
  }

  void _pushNode(int r, double x0, double y0, double x1, double y1) {
    var nc = _nodeCount;
    if (4 * nc + 4 > _nodes.length) {
      _nodes = Float32List(_nodes.length * 2)..setRange(0, 4 * nc, _nodes);
      _nodeNext = Int32List(_nodeNext.length * 2)
        ..setRange(0, nc, _nodeNext);
    }
    final base = 4 * nc;
    _nodes[base] = x0;
    _nodes[base + 1] = y0;
    _nodes[base + 2] = x1;
    _nodes[base + 3] = y1;
    final head = _rowHead[r];
    _nodeNext[nc] = head;
    _rowHead[r] = nc;
    _nodeCount = nc + 1;

    final lo = x0 < x1 ? x0 : x1;
    final hi = x0 < x1 ? x1 : x0;
    final mn = lo.floor();
    final mx = hi.ceil();
    if (head == -1) {
      if (_dirtyCount == _dirtyRows.length) {
        _dirtyRows = Int32List(_dirtyRows.length * 2)
          ..setRange(0, _dirtyCount, _dirtyRows);
      }
      _dirtyRows[_dirtyCount++] = r;
      _rowMinX[r] = mn;
      _rowMaxX[r] = mx;
    } else {
      if (mn < _rowMinX[r]) _rowMinX[r] = mn;
      if (mx > _rowMaxX[r]) _rowMaxX[r] = mx;
    }
  }

  // ---- fine raster + emission ------------------------------------------

  void _finishShape(PdfFillRule rule, int rgba) {
    final evenOdd = rule == PdfFillRule.evenOdd;
    for (var d = 0; d < _dirtyCount; d++) {
      final r = _dirtyRows[d];
      _rasterizeRow(r, evenOdd, rgba);
      _rowHead[r] = -1;
    }
    _dirtyCount = 0;
    _nodeCount = 0;
  }

  void _rasterizeRow(int r, bool evenOdd, int rgba) {
    final a = _accum;
    final stride = _stride;
    final nodes = _nodes;
    final next = _nodeNext;

    // font-rs signed-area accumulation, one unit scanline at a time.
    var node = _rowHead[r];
    while (node != -1) {
      final base = 4 * node;
      var xA = nodes[base];
      final yA = nodes[base + 1];
      var xB = nodes[base + 2];
      final yB = nodes[base + 3];
      node = next[node];
      if (yA == yB) continue;
      double p0y, p1y, dir;
      if (yB > yA) {
        p0y = yA;
        p1y = yB;
        dir = 1.0;
      } else {
        p0y = yB;
        p1y = yA;
        dir = -1.0;
        final t = xA;
        xA = xB;
        xB = t;
      }
      final dxdy = (xB - xA) / (p1y - p0y);
      var x = xA;
      var yCur = p0y;
      var yi = p0y.floor();
      final yiLast = p1y.ceil() - 1;
      if (yi < 0) yi = 0;
      for (; yi <= yiLast && yi < 4; yi++) {
        final rowBase = yi * stride;
        final yNext = (yi + 1.0) < p1y ? (yi + 1.0) : p1y;
        final dy = yNext - yCur;
        final xnext = x + dxdy * dy;
        final d = dy * dir;
        double xx0, xx1;
        if (x < xnext) {
          xx0 = x;
          xx1 = xnext;
        } else {
          xx0 = xnext;
          xx1 = x;
        }
        final x0floor = xx0.floorToDouble();
        final x0i = x0floor.toInt();
        final x1ceil = xx1.ceilToDouble();
        final x1i = x1ceil.toInt();
        if (x1i <= x0i + 1) {
          // the crossing stays within one column
          final xmf = 0.5 * (x + xnext) - x0floor;
          a[rowBase + x0i] += d * (1 - xmf);
          a[rowBase + x0i + 1] += d * xmf;
        } else {
          final s = 1 / (xx1 - xx0);
          final x0f = xx0 - x0floor;
          final a0 = 0.5 * s * (1 - x0f) * (1 - x0f);
          final x1f = xx1 - x1ceil + 1;
          final am = 0.5 * s * x1f * x1f;
          a[rowBase + x0i] += d * a0;
          if (x1i == x0i + 2) {
            a[rowBase + x0i + 1] += d * (1 - a0 - am);
          } else {
            final a1 = s * (1.5 - x0f);
            a[rowBase + x0i + 1] += d * (a1 - a0);
            for (var xi = x0i + 2; xi < x1i - 1; xi++) {
              a[rowBase + xi] += d * s;
            }
            final a2 = a1 + (x1i - x0i - 3) * s;
            a[rowBase + x1i - 1] += d * (1 - a2 - am);
          }
          a[rowBase + x1i] += d * am;
        }
        x = xnext;
        yCur = yNext;
      }
    }

    // Prefix-sum + fill rule + strip emission over the touched span.
    final x0 = _rowMinX[r];
    final xMax = _rowMaxX[r];
    var xEnd = xMax;
    if (xEnd >= _width) xEnd = _width - 1;
    final y = r << 2;
    final buf = strips;
    final baseFlags = evenOdd ? stripFlagEvenOdd : 0;

    var acc0 = 0.0, acc1 = 0.0, acc2 = 0.0, acc3 = 0.0;
    var mode = 0; // 0 none, 1 solid run, 2 mixed strip
    var runStart = 0;
    var alphaStart = 0;
    var pending = 0; // trailing all-255 columns inside a mixed strip

    for (var x = x0; x <= xEnd; x++) {
      acc0 += a[x];
      acc1 += a[stride + x];
      acc2 += a[2 * stride + x];
      acc3 += a[3 * stride + x];
      // fill rule, manually inlined per scanline (hot loop)
      var v0 = acc0, v1 = acc1, v2 = acc2, v3 = acc3;
      if (evenOdd) {
        v0 -= 2 * (v0 * 0.5).roundToDouble();
        v1 -= 2 * (v1 * 0.5).roundToDouble();
        v2 -= 2 * (v2 * 0.5).roundToDouble();
        v3 -= 2 * (v3 * 0.5).roundToDouble();
      }
      if (v0 < 0) v0 = -v0;
      if (v1 < 0) v1 = -v1;
      if (v2 < 0) v2 = -v2;
      if (v3 < 0) v3 = -v3;
      if (v0 > 1) v0 = 1;
      if (v1 > 1) v1 = 1;
      if (v2 > 1) v2 = 1;
      if (v3 > 1) v3 = 1;
      final a32 = (v0 * 255 + 0.5).toInt() |
          ((v1 * 255 + 0.5).toInt() << 8) |
          ((v2 * 255 + 0.5).toInt() << 16) |
          ((v3 * 255 + 0.5).toInt() << 24);

      if (a32 == 0) {
        if (mode == 1) {
          buf._emit(runStart, y, x - runStart, baseFlags | stripFlagSolid,
              stripSolidSentinel, rgba);
        } else if (mode == 2) {
          if (pending >= 2) {
            buf._emit(runStart, y, x - pending - runStart, baseFlags,
                alphaStart, rgba);
            buf._emit(x - pending, y, pending, baseFlags | stripFlagSolid,
                stripSolidSentinel, rgba);
          } else {
            if (pending == 1) buf._appendTexel(0xFFFFFFFF);
            buf._emit(runStart, y, x - runStart, baseFlags, alphaStart, rgba);
          }
        }
        mode = 0;
        pending = 0;
      } else if (a32 == 0xFFFFFFFF) {
        if (mode == 0) {
          runStart = x;
          mode = 1;
        } else if (mode == 2) {
          pending++;
        }
      } else {
        if (mode == 0) {
          runStart = x;
          mode = 2;
          alphaStart = buf.alphaColumns;
          buf._appendTexel(a32);
        } else if (mode == 1) {
          final solidLen = x - runStart;
          if (solidLen >= 2) {
            buf._emit(runStart, y, solidLen, baseFlags | stripFlagSolid,
                stripSolidSentinel, rgba);
            runStart = x;
            alphaStart = buf.alphaColumns;
          } else {
            // a single solid column joins the mixed strip as a 255-texel
            alphaStart = buf.alphaColumns;
            buf._appendTexel(0xFFFFFFFF);
          }
          mode = 2;
          pending = 0;
          buf._appendTexel(a32);
        } else {
          if (pending > 0) {
            if (pending >= 2) {
              buf._emit(runStart, y, x - pending - runStart, baseFlags,
                  alphaStart, rgba);
              buf._emit(x - pending, y, pending, baseFlags | stripFlagSolid,
                  stripSolidSentinel, rgba);
              runStart = x;
              alphaStart = buf.alphaColumns;
            } else {
              buf._appendTexel(0xFFFFFFFF);
            }
            pending = 0;
          }
          buf._appendTexel(a32);
        }
      }
    }
    // end-of-row flush
    final xAfter = xEnd + 1;
    if (mode == 1) {
      buf._emit(runStart, y, xAfter - runStart, baseFlags | stripFlagSolid,
          stripSolidSentinel, rgba);
    } else if (mode == 2) {
      if (pending >= 2) {
        buf._emit(runStart, y, xAfter - pending - runStart, baseFlags,
            alphaStart, rgba);
        buf._emit(xAfter - pending, y, pending, baseFlags | stripFlagSolid,
            stripSolidSentinel, rgba);
      } else {
        if (pending == 1) buf._appendTexel(0xFFFFFFFF);
        buf._emit(runStart, y, xAfter - runStart, baseFlags, alphaStart, rgba);
      }
    }

    // Zero only the touched span (accumulation writes at most one cell past
    // ceil(max x)).
    var zEnd = xMax + 2;
    if (zEnd > stride) zEnd = stride;
    a.fillRange(x0, zEnd, 0);
    a.fillRange(stride + x0, stride + zEnd, 0);
    a.fillRange(2 * stride + x0, 2 * stride + zEnd, 0);
    a.fillRange(3 * stride + x0, 3 * stride + zEnd, 0);
  }
}
