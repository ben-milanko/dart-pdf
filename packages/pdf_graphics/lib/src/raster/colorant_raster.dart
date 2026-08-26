// The colorant buffer's storage and rasterizer (issue #502).
//
// A page-sized grid of palette indices, one per cell, recording which device
// colorant vector each part of the page currently carries. It is deliberately
// *not* the rendered raster: it needs no anti-aliasing, no colour, and no
// resolution beyond "enough to tell one painted region from its neighbours",
// because nothing is ever displayed from it - it only answers "what colorants
// is this draw landing on".
//
// Coverage is binary and sampled at cell centres, using the same adaptive
// flattener and stroke expander as the CPU strip rasterizer, so curves and
// stroke geometry agree with what actually gets painted. Pure Dart (no
// dart:ui), so it runs on the VM, in a render worker, and on the web.
import 'dart:typed_data';

import '../matrix.dart';
import '../path.dart';
import 'flatten.dart';
import 'stroke_contours.dart';

/// The cells one draw covers, as a list of horizontal `(y, x0, x1)` spans.
class ColorantSpans {
  ColorantSpans._(this._data, this._count);

  static final ColorantSpans empty = ColorantSpans._(Int32List(0), 0);

  final Int32List _data;
  final int _count;

  /// Number of spans.
  int get length => _count;

  int yAt(int i) => _data[i * 3];

  int startAt(int i) => _data[i * 3 + 1];

  /// Exclusive end cell of span [i].
  int endAt(int i) => _data[i * 3 + 2];

  bool get isEmpty => _count == 0;
}

/// Page space (PDF user space) to colorant-cell space, kept together with the
/// uniform scale so stroke widths and dash lengths convert without
/// re-deriving it.
class ColorantPageMapping {
  const ColorantPageMapping(this.matrix, this.scale);

  final PdfMatrix matrix;
  final double scale;
}

/// A grid of colorant palette indices covering the page box.
class PdfColorantRaster {
  PdfColorantRaster({
    required this.width,
    required this.height,
    required this.mapping,
  }) : cells = Uint16List(width * height);

  /// Cell columns / rows.
  final int width;
  final int height;

  final ColorantPageMapping mapping;

  /// Palette index per cell, row-major. 0 is the initial (bare paper) entry.
  final Uint16List cells;

  // The clip is a box plus, only when a clip path is not a plain rectangle, a
  // 0/1 mask. Real content clips to rectangles almost exclusively (`re W n`
  // around a group, a form's /BBox), and a mask costs a page-sized allocation
  // per clip - which on a page that clips per element dominated everything
  // else this buffer does.
  int _clipX0 = 0, _clipY0 = 0;
  late int _clipX1 = width, _clipY1 = height;
  Uint8List? _clipMask;
  final List<int> _clipStack = [];
  final List<Uint8List?> _clipMaskStack = [];

  void save() {
    _clipStack
      ..add(_clipX0)
      ..add(_clipY0)
      ..add(_clipX1)
      ..add(_clipY1);
    _clipMaskStack.add(_clipMask);
  }

  void restore() {
    if (_clipMaskStack.isEmpty) return;
    _clipMask = _clipMaskStack.removeLast();
    _clipY1 = _clipStack.removeLast();
    _clipX1 = _clipStack.removeLast();
    _clipY0 = _clipStack.removeLast();
    _clipX0 = _clipStack.removeLast();
  }

  /// Intersects the clip with [spans].
  void clipTo(ColorantSpans spans) {
    if (spans.isEmpty) {
      _clipX1 = _clipX0;
      _clipY1 = _clipY0;
      return;
    }
    // A non-rectangular clip's first scanline may be its narrowest (a
    // triangle tip, or either diagonal arm of GWG020's X). Its coarse bounds
    // must cover every scanline; using only the first run silently reduced
    // the active clip to that one column before the mask was even consulted.
    var x0 = spans.startAt(0), x1 = spans.endAt(0);
    for (var i = 1; i < spans.length; i++) {
      if (spans.startAt(i) < x0) x0 = spans.startAt(i);
      if (spans.endAt(i) > x1) x1 = spans.endAt(i);
    }
    final y0 = spans.yAt(0), y1 = spans.yAt(spans.length - 1) + 1;
    var isRect = spans.length == y1 - y0;
    for (var i = 0; isRect && i < spans.length; i++) {
      isRect = spans.yAt(i) == y0 + i &&
          spans.startAt(i) == x0 &&
          spans.endAt(i) == x1;
    }
    if (isRect) {
      if (x0 > _clipX0) _clipX0 = x0;
      if (y0 > _clipY0) _clipY0 = y0;
      if (x1 < _clipX1) _clipX1 = x1;
      if (y1 < _clipY1) _clipY1 = y1;
      return;
    }
    final next = Uint8List(width * height);
    final current = _clipMask;
    for (var i = 0; i < spans.length; i++) {
      final y = spans.yAt(i);
      if (y < _clipY0 || y >= _clipY1) continue;
      final row = y * width;
      var from = spans.startAt(i), to = spans.endAt(i);
      if (from < _clipX0) from = _clipX0;
      if (to > _clipX1) to = _clipX1;
      for (var x = from; x < to; x++) {
        if (current == null || current[row + x] != 0) next[row + x] = 1;
      }
    }
    _clipMask = next;
    if (x0 > _clipX0) _clipX0 = x0;
    if (y0 > _clipY0) _clipY0 = y0;
    if (x1 < _clipX1) _clipX1 = x1;
    if (y1 < _clipY1) _clipY1 = y1;
  }

  /// The palette indices meaningfully present under [spans].
  ///
  /// Counted, not merely collected, and indices covering less than
  /// [_bleedFraction] of the draw are dropped: a shape butted exactly against
  /// its neighbour picks the neighbour's colorants up through the cells its
  /// boundary shares, and that contamination is by definition a thin rim of a
  /// large shape. Thresholding on area is what makes the answer independent of
  /// the buffer's resolution - a fixed one-cell erosion ate small shapes whole
  /// as the grid got coarser. A shape only a few cells across keeps everything
  /// it covers, which is correct: there is no rim to discount.
  ///
  /// Returns null when [spans] covers no cell inside the clip, or when more
  /// than [limit] distinct vectors survive - a backdrop that varied that much
  /// is one the caller should not try to resolve to a single colour.
  List<int>? backdropUnder(ColorantSpans spans,
      {int limit = 8, double bleedFraction = _bleedFraction}) {
    if (spans.isEmpty) return null;
    final found = _found..clear();
    final counts = _counts..clear();
    final mask = _clipMask;
    var total = 0;
    for (var i = 0; i < spans.length; i++) {
      final y = spans.yAt(i);
      if (y < _clipY0 || y >= _clipY1) continue;
      var x0 = spans.startAt(i), x1 = spans.endAt(i);
      if (x0 < _clipX0) x0 = _clipX0;
      if (x1 > _clipX1) x1 = _clipX1;
      final row = y * width;
      for (var x = x0; x < x1; x++) {
        final index = row + x;
        if (mask != null && mask[index] == 0) continue;
        total++;
        final value = cells[index];
        final at = found.indexOf(value);
        if (at >= 0) {
          counts[at]++;
        } else {
          if (found.length >= limit * 4) return null;
          found.add(value);
          counts.add(1);
        }
      }
    }
    if (total == 0) return null;
    final floor = total * bleedFraction;
    final kept = <int>[];
    for (var i = 0; i < found.length; i++) {
      if (counts[i] >= floor) kept.add(found[i]);
    }
    if (kept.isEmpty || kept.length > limit) return null;
    return kept;
  }

  /// Share of a draw's coverage below which a backdrop index is treated as
  /// boundary bleed from an adjacent region rather than a backdrop of its own.
  static const double _bleedFraction = 0.04;

  final List<int> _found = [];
  final List<int> _counts = [];

  /// Palette index at page-space point ([x], [y]), respecting the active
  /// clip, or null outside the raster/clip. Used only by the spatial image
  /// overprint path; ordinary shapes stay on the much cheaper span API.
  int? paletteAtPage(double x, double y) {
    final mappedX = mapping.matrix.transformX(x, y);
    final mappedY = mapping.matrix.transformY(x, y);
    final cellX = _cellFrom(mappedX);
    final cellY = _cellFrom(mappedY);
    if (cellX < _clipX0 ||
        cellX >= _clipX1 ||
        cellY < _clipY0 ||
        cellY >= _clipY1) {
      return null;
    }
    final index = cellY * width + cellX;
    final mask = _clipMask;
    if (mask != null && mask[index] == 0) return null;
    return cells[index];
  }

  /// Writes the result of a draw into the buffer. [resultFor] maps the
  /// backdrop index of each covered cell to the index the draw leaves behind.
  void paint(ColorantSpans spans, int Function(int backdrop) resultFor) {
    final mask = _clipMask;
    for (var i = 0; i < spans.length; i++) {
      final y = spans.yAt(i);
      if (y < _clipY0 || y >= _clipY1) continue;
      final row = y * width;
      var from = spans.startAt(i), to = spans.endAt(i);
      if (from < _clipX0) from = _clipX0;
      if (to > _clipX1) to = _clipX1;
      for (var x = from; x < to; x++) {
        final index = row + x;
        if (mask != null && mask[index] == 0) continue;
        cells[index] = resultFor(cells[index]);
      }
    }
  }

  /// Fills every covered cell with [value] - the knockout case, where the
  /// draw replaces whatever colorants were underneath.
  void paintFlat(ColorantSpans spans, int value) {
    final mask = _clipMask;
    for (var i = 0; i < spans.length; i++) {
      final y = spans.yAt(i);
      if (y < _clipY0 || y >= _clipY1) continue;
      final row = y * width;
      var from = spans.startAt(i), to = spans.endAt(i);
      if (from < _clipX0) from = _clipX0;
      if (to > _clipX1) to = _clipX1;
      if (mask == null) {
        cells.fillRange(row + from, row + to, value);
        continue;
      }
      for (var x = from; x < to; x++) {
        final index = row + x;
        if (mask[index] != 0) cells[index] = value;
      }
    }
  }

  /// Marks every clipped cell covered by [spans] in [mask].
  ///
  /// Transparency-group compositing uses this alongside the colorant cells to
  /// distinguish an unpainted (transparent) part of a group from a painted
  /// pixel whose result happens to equal the group's initial backdrop. The
  /// latter distinction is essential for knockout groups: an object that
  /// paints the initial-backdrop colour must still replace an earlier sibling.
  void markCovered(ColorantSpans spans, Uint8List mask) {
    if (mask.length != cells.length) return;
    final clip = _clipMask;
    for (var i = 0; i < spans.length; i++) {
      final y = spans.yAt(i);
      if (y < _clipY0 || y >= _clipY1) continue;
      final row = y * width;
      var from = spans.startAt(i), to = spans.endAt(i);
      if (from < _clipX0) from = _clipX0;
      if (to > _clipX1) to = _clipX1;
      if (clip == null) {
        mask.fillRange(row + from, row + to, 1);
        continue;
      }
      for (var x = from; x < to; x++) {
        final index = row + x;
        if (clip[index] != 0) mask[index] = 1;
      }
    }
  }

  /// Paints [spans] while exposing each covered cell's page-space centre.
  ///
  /// Variable-color shadings need this slower path: their DeviceN/Separation
  /// tint is a function of position, so one palette entry cannot describe the
  /// whole draw. Ordinary paths and images stay on [paint]/[paintFlat].
  void paintSampled(ColorantSpans spans,
      int Function(double pageX, double pageY, int backdrop) resultFor) {
    final inverse = mapping.matrix.inverted();
    if (inverse == null) return;
    final mask = _clipMask;
    for (var i = 0; i < spans.length; i++) {
      final y = spans.yAt(i);
      if (y < _clipY0 || y >= _clipY1) continue;
      final row = y * width;
      var from = spans.startAt(i), to = spans.endAt(i);
      if (from < _clipX0) from = _clipX0;
      if (to > _clipX1) to = _clipX1;
      final cellY = y + 0.5;
      for (var x = from; x < to; x++) {
        final index = row + x;
        if (mask != null && mask[index] == 0) continue;
        final cellX = x + 0.5;
        final pageX = inverse.transformX(cellX, cellY);
        final pageY = inverse.transformY(cellX, cellY);
        cells[index] = resultFor(pageX, pageY, cells[index]);
      }
    }
  }

  /// Page-space run regions for the result [resultFor] would produce over the
  /// current cells covered by [spans]. Adjacent cells of one result are joined
  /// horizontally; callers still clip these coarse internal regions through
  /// the original vector path, so only backdrop boundaries are quantized.
  Map<int, PdfPath> resultRegions(
      ColorantSpans spans, int Function(int backdrop) resultFor) {
    final inverse = mapping.matrix.inverted();
    if (inverse == null) return const {};
    final byResult = <int, List<PdfPathSegment>>{};
    final mask = _clipMask;

    void addRun(int result, int x0, int x1, int y) {
      if (x1 <= x0) return;
      final segments = byResult.putIfAbsent(result, () => []);
      final left = x0.toDouble(), right = x1.toDouble();
      final top = y.toDouble(), bottom = (y + 1).toDouble();
      segments
        ..add(PdfMoveTo(
            inverse.transformX(left, top), inverse.transformY(left, top)))
        ..add(PdfLineTo(
            inverse.transformX(right, top), inverse.transformY(right, top)))
        ..add(PdfLineTo(inverse.transformX(right, bottom),
            inverse.transformY(right, bottom)))
        ..add(PdfLineTo(
            inverse.transformX(left, bottom), inverse.transformY(left, bottom)))
        ..add(const PdfClosePath());
    }

    for (var i = 0; i < spans.length; i++) {
      final y = spans.yAt(i);
      if (y < _clipY0 || y >= _clipY1) continue;
      var from = spans.startAt(i), to = spans.endAt(i);
      if (from < _clipX0) from = _clipX0;
      if (to > _clipX1) to = _clipX1;
      final row = y * width;
      int? current;
      var runStart = from;
      for (var x = from; x < to; x++) {
        final index = row + x;
        final result =
            mask != null && mask[index] == 0 ? null : resultFor(cells[index]);
        if (result == current) continue;
        if (current != null) addRun(current, runStart, x, y);
        current = result;
        runStart = x;
      }
      if (current != null) addRun(current, runStart, to, y);
    }
    return {
      for (final entry in byResult.entries) entry.key: PdfPath(entry.value),
    };
  }

  /// Spatial counterpart of [resultRegions]. [resultAt] may omit a cell by
  /// returning null; otherwise adjacent equal results are joined per row.
  Map<int, PdfPath> sampledResultRegions(ColorantSpans spans,
      int? Function(double pageX, double pageY, int current) resultAt) {
    final inverse = mapping.matrix.inverted();
    if (inverse == null) return const {};
    final byResult = <int, List<PdfPathSegment>>{};
    final mask = _clipMask;

    void addRun(int result, int x0, int x1, int y) {
      if (x1 <= x0) return;
      final segments = byResult.putIfAbsent(result, () => []);
      final left = x0.toDouble(), right = x1.toDouble();
      final top = y.toDouble(), bottom = (y + 1).toDouble();
      segments
        ..add(PdfMoveTo(
            inverse.transformX(left, top), inverse.transformY(left, top)))
        ..add(PdfLineTo(
            inverse.transformX(right, top), inverse.transformY(right, top)))
        ..add(PdfLineTo(inverse.transformX(right, bottom),
            inverse.transformY(right, bottom)))
        ..add(PdfLineTo(
            inverse.transformX(left, bottom), inverse.transformY(left, bottom)))
        ..add(const PdfClosePath());
    }

    for (var i = 0; i < spans.length; i++) {
      final y = spans.yAt(i);
      if (y < _clipY0 || y >= _clipY1) continue;
      var from = spans.startAt(i), to = spans.endAt(i);
      if (from < _clipX0) from = _clipX0;
      if (to > _clipX1) to = _clipX1;
      final row = y * width;
      final cellY = y + 0.5;
      int? current;
      var runStart = from;
      for (var x = from; x < to; x++) {
        final index = row + x;
        int? result;
        if (mask == null || mask[index] != 0) {
          final cellX = x + 0.5;
          result = resultAt(inverse.transformX(cellX, cellY),
              inverse.transformY(cellX, cellY), cells[index]);
        }
        if (result == current) continue;
        if (current != null) addRun(current, runStart, x, y);
        current = result;
        runStart = x;
      }
      if (current != null) addRun(current, runStart, to, y);
    }
    return {
      for (final entry in byResult.entries) entry.key: PdfPath(entry.value),
    };
  }

  /// Spans covered by filling [path] (page space) under the given rule.
  ColorantSpans fillSpans(PdfPath path, {required bool evenOdd}) {
    // Axis-aligned rectangles are most of what a page fills and almost all of
    // what it clips to (`re W n`, a form's /BBox, a patch background), and
    // they are also the only shape whose spans need no geometry at all. Taking
    // them straight to a box skips the flattener's per-subpath allocations and
    // the edge table - which measured as the dominant per-draw cost, well
    // ahead of writing the cells themselves.
    final rect = _axisAlignedRect(path);
    if (rect != null) {
      return boxSpans(rect[0], rect[1], rect[2], rect[3]);
    }
    return _spansOf(flattenPath(path, mapping.matrix), evenOdd);
  }

  /// `[left, bottom, right, top]` when [path] is one axis-aligned rectangle,
  /// else null. Both winding rules agree on a simple rectangle, so the caller
  /// need not pass one.
  static List<double>? _axisAlignedRect(PdfPath path) {
    final segments = path.segments;
    if (segments.length < 4 || segments.length > 6) return null;
    if (segments.first is! PdfMoveTo) return null;
    final xs = <double>[], ys = <double>[];
    for (final segment in segments) {
      switch (segment) {
        case PdfMoveTo(:final x, :final y) || PdfLineTo(:final x, :final y):
          xs.add(x);
          ys.add(y);
        case PdfClosePath():
          break;
        case PdfCubicTo(:final x1, :final y1, :final x2, :final y2):
          // A cubic whose control points sit on its own endpoints is a
          // straight line. Producers emit rectangles this way all the time -
          // `v`/`y` with coincident controls - and the Ghent overprint patches
          // build every patch box and clip out of them, so rejecting the whole
          // path on sight would send exactly the pages that use this buffer
          // down the slow path.
          final px = xs.last, py = ys.last;
          final endX = segment.x3, endY = segment.y3;
          final firstOnEnd =
              (x1 == px && y1 == py) || (x1 == endX && y1 == endY);
          final secondOnEnd =
              (x2 == px && y2 == py) || (x2 == endX && y2 == endY);
          if (!firstOnEnd || !secondOnEnd) return null;
          xs.add(endX);
          ys.add(endY);
      }
    }
    if (xs.length < 4 || xs.length > 5) return null;
    // Closing back to the start is allowed as an explicit final lineTo.
    if (xs.length == 5 && (xs[4] != xs[0] || ys[4] != ys[0])) return null;
    // Corners must alternate: each edge changes exactly one coordinate.
    for (var i = 0; i < 4; i++) {
      final j = (i + 1) & 3;
      final horizontal = ys[i] == ys[j];
      final vertical = xs[i] == xs[j];
      if (horizontal == vertical) return null; // degenerate or diagonal
    }
    var left = xs[0], right = xs[0], bottom = ys[0], top = ys[0];
    for (var i = 1; i < 4; i++) {
      if (xs[i] < left) left = xs[i];
      if (xs[i] > right) right = xs[i];
      if (ys[i] < bottom) bottom = ys[i];
      if (ys[i] > top) top = ys[i];
    }
    return [left, bottom, right, top];
  }

  /// Spans covered by stroking [path] (page space) with a page-space [width]
  /// and the given cap/join/dash geometry.
  ColorantSpans strokeSpans(PdfPath path,
      {required double width,
      required int cap,
      required int join,
      required double miterLimit,
      List<double> dashArray = const [],
      double dashPhase = 0}) {
    final scale = mapping.scale;
    var subpaths = flattenPath(path, mapping.matrix);
    if (subpaths.isEmpty) return ColorantSpans.empty;
    if (dashArray.isNotEmpty) {
      subpaths = dashSubpaths(
          subpaths, [for (final d in dashArray) d * scale], dashPhase * scale);
    }
    final contours = StrokeContours();
    final mappedWidth = width * scale;
    strokeToContours(subpaths,
        // The colorant grid cannot represent a stroke narrower than one cell.
        // Preserve one sample cell here; spatial replay still clips the result
        // through the original vector stroke, so its visible width is exact.
        width: mappedWidth < 1 ? 1 : mappedWidth,
        cap: cap,
        join: join,
        miterLimit: miterLimit,
        out: contours);
    final points = contours.points.view;
    final rings = <FlatSubpath>[
      for (var i = 0; i < contours.ringCount; i++)
        if (contours.ringEnd(i) - contours.ringStart(i) >= 6)
          FlatSubpath(
              Float64List.sublistView(
                  points, contours.ringStart(i), contours.ringEnd(i)),
              closed: true),
    ];
    return _spansOf(rings, false);
  }

  /// Spans covering an axis-aligned page-space box - text runs, images and
  /// other draws whose exact coverage the buffer does not model.
  ColorantSpans boxSpans(double left, double bottom, double right, double top) {
    final m = mapping.matrix;
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (var corner = 0; corner < 4; corner++) {
      final px = corner.isEven ? left : right;
      final py = corner < 2 ? bottom : top;
      final x = m.transformX(px, py), y = m.transformY(px, py);
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
    final y0 = _cellFrom(minY).clamp(0, height);
    final y1 = _cellFrom(maxY).clamp(0, height);
    final x0 = _cellFrom(minX).clamp(0, width);
    final x1 = _cellFrom(maxX).clamp(0, width);
    if (x1 <= x0 || y1 <= y0) return ColorantSpans.empty;
    final out = Int32List((y1 - y0) * 3);
    var n = 0;
    for (var y = y0; y < y1; y++) {
      out[n++] = y;
      out[n++] = x0;
      out[n++] = x1;
    }
    return ColorantSpans._(out, n ~/ 3);
  }

  /// First cell whose centre (`x + 0.5`) is at or past [edge].
  static int _cellFrom(double edge) => (edge - 0.5).ceil();

  /// Scanline fill of already-flattened, cell-space [subpaths]. Coverage is
  /// binary, sampled at cell centres; a fill treats every subpath as closed
  /// (§8.5.3.3.2), which is what the modulo wrap of the segment loop does.
  // Edge table and per-scanline crossing lists, reused across draws: a page
  // issues thousands of them and a fresh growable list per draw was pure
  // allocation churn.
  final List<double> _xTop = [];
  final List<double> _slope = [];
  final List<double> _yTop = [];
  final List<double> _yBottom = [];
  final List<int> _winding = [];
  final List<double> _crossings = [];
  final List<int> _crossingWinding = [];
  final _SpanBuilder _spans = _SpanBuilder();

  ColorantSpans _spansOf(List<FlatSubpath> subpaths, bool evenOdd) {
    final xTop = _xTop..clear();
    final slope = _slope..clear();
    final yTop = _yTop..clear();
    final yBottom = _yBottom..clear();
    final winding = _winding..clear();
    var minY = double.infinity, maxY = double.negativeInfinity;
    for (final sub in subpaths) {
      final p = sub.points;
      final count = p.length ~/ 2;
      if (count < 2) continue;
      for (var i = 0; i < count; i++) {
        final j = i + 1 == count ? 0 : i + 1;
        final ax = p[i * 2], ay = p[i * 2 + 1];
        final bx = p[j * 2], by = p[j * 2 + 1];
        if (ay == by) continue;
        final up = ay < by;
        yTop.add(up ? ay : by);
        yBottom.add(up ? by : ay);
        xTop.add(up ? ax : bx);
        slope.add((bx - ax) / (by - ay));
        winding.add(up ? 1 : -1);
        if (ay < minY) minY = ay;
        if (by < minY) minY = by;
        if (ay > maxY) maxY = ay;
        if (by > maxY) maxY = by;
      }
    }
    if (xTop.isEmpty) return ColorantSpans.empty;
    final yStart = _cellFrom(minY).clamp(0, height);
    final yEnd = _cellFrom(maxY).clamp(0, height);
    if (yEnd <= yStart) return ColorantSpans.empty;
    final out = _spans..reset();
    final xs = _crossings;
    final ws = _crossingWinding;
    for (var y = yStart; y < yEnd; y++) {
      final sampleY = y + 0.5;
      xs.clear();
      ws.clear();
      for (var e = 0; e < xTop.length; e++) {
        if (sampleY < yTop[e] || sampleY >= yBottom[e]) continue;
        xs.add(xTop[e] + (sampleY - yTop[e]) * slope[e]);
        ws.add(winding[e]);
      }
      if (xs.length < 2) continue;
      // Insertion sort keeps the parallel winding list in step; crossing
      // counts per scanline stay tiny even on dense art.
      for (var i = 1; i < xs.length; i++) {
        final x = xs[i], w = ws[i];
        var j = i - 1;
        while (j >= 0 && xs[j] > x) {
          xs[j + 1] = xs[j];
          ws[j + 1] = ws[j];
          j--;
        }
        xs[j + 1] = x;
        ws[j + 1] = w;
      }
      var count = 0;
      for (var i = 0; i < xs.length - 1; i++) {
        count += evenOdd ? 1 : ws[i];
        if (evenOdd ? count.isEven : count == 0) continue;
        final x0 = _cellFrom(xs[i]).clamp(0, width);
        final x1 = _cellFrom(xs[i + 1]).clamp(0, width);
        if (x1 > x0) out.add(y, x0, x1);
      }
    }
    return out.build();
  }
}

class _SpanBuilder {
  Int32List _data = Int32List(192);
  int _length = 0;

  void reset() => _length = 0;

  void add(int y, int x0, int x1) {
    if (_length + 3 > _data.length) {
      _data = Int32List(_data.length * 2)..setRange(0, _length, _data);
    }
    _data[_length++] = y;
    _data[_length++] = x0;
    _data[_length++] = x1;
  }

  /// A view of the accumulated spans, valid until the next rasterization.
  ///
  /// Not a copy: the builder is reused across draws, which is the point. Every
  /// consumer reads and writes its spans before rasterizing anything else (a
  /// resolved overprint reads the backdrop under them, then paints through the
  /// same list), so no span list is ever held across the next draw.
  ColorantSpans build() =>
      ColorantSpans._(Int32List.sublistView(_data, 0, _length), _length ~/ 3);
}
