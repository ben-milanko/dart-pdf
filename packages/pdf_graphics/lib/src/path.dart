import 'dart:typed_data';

/// Path geometry emitted by the interpreter. Coordinates are already
/// transformed into page space (PDF default user space, y-up), because PDF
/// applies the CTM at path-construction time.
sealed class PdfPathSegment {
  const PdfPathSegment();
}

class PdfMoveTo extends PdfPathSegment {
  const PdfMoveTo(this.x, this.y);
  final double x;
  final double y;
}

class PdfLineTo extends PdfPathSegment {
  const PdfLineTo(this.x, this.y);
  final double x;
  final double y;
}

class PdfCubicTo extends PdfPathSegment {
  const PdfCubicTo(this.x1, this.y1, this.x2, this.y2, this.x3, this.y3);
  final double x1, y1, x2, y2, x3, y3;
}

class PdfClosePath extends PdfPathSegment {
  const PdfClosePath();
}

class PdfPath {
  const PdfPath(List<PdfPathSegment> segments)
      : _segments = segments,
        _verbs = null,
        _coordinates = null,
        _packedSegmentCount = 0;

  PdfPath._packed(this._verbs, this._coordinates, this._packedSegmentCount)
      : _segments = null;

  /// Constructs the compact float32 path representation used by the render
  /// command decoder.
  ///
  /// Command coordinates are already float32 on the wire. Retaining them in a
  /// [Float32List] avoids widening every point back to an 8-byte double while
  /// preserving the exact values replay received historically. [verbs] uses
  /// the command codec's 0=move, 1=line, 2=cubic, 3=close tags.
  PdfPath.packedFloat32(
      Uint8List verbs, Float32List coordinates, int segmentCount)
      : _segments = null,
        _verbs = verbs,
        _coordinates = coordinates,
        _packedSegmentCount = segmentCount;

  final List<PdfPathSegment>? _segments;
  final Uint8List? _verbs;
  final List<double>? _coordinates;
  final int _packedSegmentCount;

  static final Expando<List<PdfPathSegment>> _materialized =
      Expando<List<PdfPathSegment>>('PdfPath.segments');

  /// The path as segment objects.
  ///
  /// Interpreter-built paths use a packed representation internally so dense
  /// CAD streams do not allocate one Dart object per segment. This getter
  /// materializes that representation lazily for compatibility with callers
  /// that need the object model. Rendering and serialization should use
  /// [cursor] to retain the allocation win.
  List<PdfPathSegment> get segments {
    final direct = _segments;
    if (direct != null) return direct;
    final cached = _materialized[this];
    if (cached != null) return cached;
    final result = <PdfPathSegment>[];
    final reader = cursor();
    while (reader.moveNext()) {
      result.add(switch (reader.verb) {
        PdfPathVerb.moveTo => PdfMoveTo(reader.x1, reader.y1),
        PdfPathVerb.lineTo => PdfLineTo(reader.x1, reader.y1),
        PdfPathVerb.cubicTo => PdfCubicTo(
            reader.x1, reader.y1, reader.x2, reader.y2, reader.x3, reader.y3),
        PdfPathVerb.close => const PdfClosePath(),
      });
    }
    _materialized[this] = result;
    return result;
  }

  int get segmentCount => _segments?.length ?? _packedSegmentCount;

  bool get isEmpty => segmentCount == 0;

  /// Opens a non-allocating sequential reader over this path.
  PdfPathCursor cursor() => PdfPathCursor._(this);
}

/// The axis-aligned rectangles [path] is made of, as `left, bottom, right,
/// top` quadruples in page space, or null when any subpath is something
/// else (a curve, a slanted edge, anything but four corners).
///
/// Producers draw rules and table borders as filled rectangles (`re f`)
/// rather than strokes - Word's table borders are 0.5 pt fills - and a fill
/// gets no stroke's one-device-pixel floor, so zoomed out those borders fade
/// to nothing. The devices use this to give thin rectangle fills the same
/// floor ([pdfThinRectFillMaxThickness]).
List<double>? pdfPathAxisAlignedRects(PdfPath path) {
  const eps = 1e-4;
  final rects = <double>[];
  // corners of the open subpath; a fifth point may repeat the first
  final xs = List<double>.filled(5, 0), ys = List<double>.filled(5, 0);
  var n = 0;
  bool finish() {
    if (n == 0) return true;
    if (n == 5) {
      if ((xs[4] - xs[0]).abs() > eps || (ys[4] - ys[0]).abs() > eps) {
        return false;
      }
      n = 4;
    }
    if (n != 4) return false;
    bool sameX(int a, int b) => (xs[a] - xs[b]).abs() <= eps;
    bool sameY(int a, int b) => (ys[a] - ys[b]).abs() <= eps;
    final horizontalFirst =
        sameY(0, 1) && sameX(1, 2) && sameY(2, 3) && sameX(3, 0);
    final verticalFirst =
        sameX(0, 1) && sameY(1, 2) && sameX(2, 3) && sameY(3, 0);
    if (!horizontalFirst && !verticalFirst) return false;
    final x0 = xs[0], y0 = ys[0], x2 = xs[2], y2 = ys[2];
    rects
      ..add(x0 < x2 ? x0 : x2)
      ..add(y0 < y2 ? y0 : y2)
      ..add(x0 < x2 ? x2 : x0)
      ..add(y0 < y2 ? y2 : y0);
    n = 0;
    return true;
  }

  final cursor = path.cursor();
  var closed = false;
  while (cursor.moveNext()) {
    switch (cursor.verb) {
      case PdfPathVerb.moveTo:
        if (!finish()) return null;
        n = 0;
        closed = false;
        xs[n] = cursor.x1;
        ys[n++] = cursor.y1;
      case PdfPathVerb.lineTo:
        // a line after `h` opens a new subpath at the old start: not a rect
        if (closed || n == 0 || n == 5) return null;
        xs[n] = cursor.x1;
        ys[n++] = cursor.y1;
      case PdfPathVerb.close:
        if (!finish()) return null;
        closed = true;
      case PdfPathVerb.cubicTo:
        return null;
    }
  }
  if (!finish()) return null;
  return rects.isEmpty ? null : rects;
}

/// How thin, in device pixels at the scale a device records for, a filled
/// rectangle has to be before devices floor it like a stroke.
///
/// Below one pixel is where the fill fades; the margin above it is for a
/// picture recorded at one scale and replayed smaller (the canvas device's
/// hairline only ever *adds* ink, so a generous threshold costs nothing at
/// the scales where the fill already covers it).
const pdfThinRectFillMaxThickness = 2.0;

/// Whether a [w] x [h] filled rectangle is a rule - clearly longer than it
/// is thick - rather than a speck, which devices leave exact even when it is
/// thin: there is no direction to floor it along, and a traced bitmap's
/// near-square cells (Ghent GWG080's checkmarks, one `re f` per cell) must
/// not each grow a line.
bool pdfRectIsRule(double w, double h) =>
    w > h ? w >= 3 * h && w > 0 : h >= 3 * w && h > 0;

/// The rectangles of [path] (as [pdfPathAxisAlignedRects]) when the fill is
/// rules a device may floor to one pixel, or null when it must stay exact.
///
/// Every rectangle must be at most [maxThickness] across its short side: a
/// thick one may be the outside of a nonzero/even-odd frame whose thin
/// "rectangle" is really a hole. And no two parallel ones may touch across
/// their short sides - stacked rows like that are an *area* drawn as a
/// mosaic (a bitmap traced to vectors, e.g. the Ghent GWG080 checkmarks), and
/// flooring each row would embolden it. Specks (not [pdfRectIsRule]) may be
/// included; devices leave them exact.
List<double>? pdfThinRectFill(PdfPath path, double maxThickness) {
  const eps = 1e-4;
  // the pairwise mosaic check is quadratic; a path this busy is not rules
  const maxRects = 64;
  final rects = pdfPathAxisAlignedRects(path);
  if (rects == null || rects.length > maxRects * 4) return null;
  for (var i = 0; i < rects.length; i += 4) {
    final w = rects[i + 2] - rects[i], h = rects[i + 3] - rects[i + 1];
    if ((w < h ? w : h) > maxThickness) return null;
    if (!pdfRectIsRule(w, h)) continue;
    // axis 1: a horizontal rule, thin in y; axis 0: vertical, thin in x
    final thin = w > h ? 1 : 0, long = 1 - thin;
    for (var j = i + 4; j < rects.length; j += 4) {
      final wj = rects[j + 2] - rects[j], hj = rects[j + 3] - rects[j + 1];
      if (!pdfRectIsRule(wj, hj) || (wj > hj) != (w > h)) continue;
      final overlapLong = (rects[i + long + 2] < rects[j + long + 2]
              ? rects[i + long + 2]
              : rects[j + long + 2]) -
          (rects[i + long] > rects[j + long]
              ? rects[i + long]
              : rects[j + long]);
      if (overlapLong <= eps) continue;
      if (rects[j + thin] <= rects[i + thin + 2] + eps &&
          rects[j + thin + 2] >= rects[i + thin] - eps) {
        return null;
      }
    }
  }
  return rects;
}

/// The operation exposed by [PdfPathCursor].
enum PdfPathVerb { moveTo, lineTo, cubicTo, close }

/// Sequential path reader that works over both object and packed paths.
///
/// One cursor is allocated per traversal; advancing it does not allocate a
/// [PdfPathSegment]. Coordinates for move/line operations are in [x1]/[y1],
/// while cubic operations fill all six coordinate fields.
class PdfPathCursor {
  PdfPathCursor._(this._path);

  final PdfPath _path;
  var _segmentIndex = 0;
  var _coordinateIndex = 0;

  PdfPathVerb verb = PdfPathVerb.close;
  double x1 = 0;
  double y1 = 0;
  double x2 = 0;
  double y2 = 0;
  double x3 = 0;
  double y3 = 0;

  bool moveNext() {
    if (_segmentIndex >= _path.segmentCount) return false;
    final direct = _path._segments;
    if (direct != null) {
      final segment = direct[_segmentIndex++];
      switch (segment) {
        case PdfMoveTo(:final x, :final y):
          verb = PdfPathVerb.moveTo;
          x1 = x;
          y1 = y;
        case PdfLineTo(:final x, :final y):
          verb = PdfPathVerb.lineTo;
          x1 = x;
          y1 = y;
        case PdfCubicTo(
            :final x1,
            :final y1,
            :final x2,
            :final y2,
            :final x3,
            :final y3
          ):
          verb = PdfPathVerb.cubicTo;
          this.x1 = x1;
          this.y1 = y1;
          this.x2 = x2;
          this.y2 = y2;
          this.x3 = x3;
          this.y3 = y3;
        case PdfClosePath():
          verb = PdfPathVerb.close;
      }
      return true;
    }

    final tag = _path._verbs![_segmentIndex++];
    final coordinates = _path._coordinates!;
    switch (tag) {
      case _moveTag:
        verb = PdfPathVerb.moveTo;
        x1 = coordinates[_coordinateIndex++];
        y1 = coordinates[_coordinateIndex++];
      case _lineTag:
        verb = PdfPathVerb.lineTo;
        x1 = coordinates[_coordinateIndex++];
        y1 = coordinates[_coordinateIndex++];
      case _cubicTag:
        verb = PdfPathVerb.cubicTo;
        x1 = coordinates[_coordinateIndex++];
        y1 = coordinates[_coordinateIndex++];
        x2 = coordinates[_coordinateIndex++];
        y2 = coordinates[_coordinateIndex++];
        x3 = coordinates[_coordinateIndex++];
        y3 = coordinates[_coordinateIndex++];
      case _closeTag:
        verb = PdfPathVerb.close;
      default:
        throw StateError('invalid packed path verb $tag');
    }
    return true;
  }
}

const int _moveTag = 0;
const int _lineTag = 1;
const int _cubicTag = 2;
const int _closeTag = 3;

/// Writes [path] as the render-command codec's path block: its verb tags (the
/// packed 0=move, 1=line, 2=cubic, 3=close) into [bytes] from [verbOffset],
/// and its coordinates, narrowed to float32, into [floats] from element
/// [floatOffset]. Returns how many coordinates it wrote.
///
/// The count comes from the verbs, not from the coordinate storage's length,
/// so a packed path carrying spare coordinates writes exactly what its cursor
/// would read. Packed paths copy straight out of their typed storage instead
/// of going through [PdfPathCursor] one scalar at a time.
///
/// Internal to the codec: the package barrel hides it, so [PdfPath]'s packed
/// storage stays unreachable (and immutable) from outside the package.
int writePdfPathBlock(PdfPath path, Uint8List bytes, int verbOffset,
    Float32List floats, int floatOffset) {
  final verbs = path._verbs;
  if (verbs == null) {
    return _writeSegmentBlock(path, bytes, verbOffset, floats, floatOffset);
  }
  final n = path._packedSegmentCount;
  var count = 0;
  for (var i = 0; i < n; i++) {
    final tag = bytes[verbOffset + i] = verbs[i];
    switch (tag) {
      case _moveTag || _lineTag:
        count += 2;
      case _cubicTag:
        count += 6;
      case _closeTag:
        break;
      default:
        throw StateError('invalid packed path verb $tag');
    }
  }
  final coordinates = path._coordinates!;
  if (coordinates is Float64List) {
    // Interpreter paths: the float32 narrowing happens on the store.
    for (var i = 0; i < count; i++) {
      floats[floatOffset + i] = coordinates[i];
    }
  } else if (coordinates is Float32List) {
    // A decoded path re-serialized (the strip binner's round trip): long runs
    // are one memmove. Short runs stay element-wise - on dart2js a ranged
    // setRange allocates a typed-array view, which costs more than a 2-point
    // stroke's copy.
    if (count >= 64) {
      floats.setRange(floatOffset, floatOffset + count, coordinates);
    } else {
      for (var i = 0; i < count; i++) {
        floats[floatOffset + i] = coordinates[i];
      }
    }
  } else {
    for (var i = 0; i < count; i++) {
      floats[floatOffset + i] = coordinates[i];
    }
  }
  return count;
}

int _writeSegmentBlock(PdfPath path, Uint8List bytes, int verbOffset,
    Float32List floats, int floatOffset) {
  var v = verbOffset;
  var f = floatOffset;
  for (final segment in path._segments!) {
    switch (segment) {
      case PdfMoveTo(:final x, :final y):
        bytes[v++] = _moveTag;
        floats[f++] = x;
        floats[f++] = y;
      case PdfLineTo(:final x, :final y):
        bytes[v++] = _lineTag;
        floats[f++] = x;
        floats[f++] = y;
      case PdfCubicTo(
          :final x1,
          :final y1,
          :final x2,
          :final y2,
          :final x3,
          :final y3
        ):
        bytes[v++] = _cubicTag;
        floats[f++] = x1;
        floats[f++] = y1;
        floats[f++] = x2;
        floats[f++] = y2;
        floats[f++] = x3;
        floats[f++] = y3;
      case PdfClosePath():
        bytes[v++] = _closeTag;
    }
  }
  return f - floatOffset;
}

/// Allocation-conscious path builder used by the content interpreter and
/// command decoder.
///
/// [takePath] copies the used prefix into exact-size typed buffers and reuses
/// the builder's scratch storage. Dense CAD files commonly emit tens of
/// thousands of one- or two-segment paths; retaining the default 16-verb /
/// 48-coordinate capacity for every one costs far more than the geometry.
/// Exact copies keep captured paths immutable while amortizing builder growth.
class PdfPathBuilder {
  PdfPathBuilder({int verbCapacity = 16, int coordinateCapacity = 48})
      : _verbs = Uint8List(verbCapacity < 1 ? 1 : verbCapacity),
        _coordinates =
            Float64List(coordinateCapacity < 2 ? 2 : coordinateCapacity);

  Uint8List _verbs;
  Float64List _coordinates;
  var _verbCount = 0;
  var _coordinateCount = 0;

  int get length => _verbCount;
  bool get isEmpty => _verbCount == 0;

  void moveTo(double x, double y) => _addPoint(_moveTag, x, y);

  void lineTo(double x, double y) => _addPoint(_lineTag, x, y);

  void cubicTo(
      double x1, double y1, double x2, double y2, double x3, double y3) {
    _ensure(1, 6);
    _verbs[_verbCount++] = _cubicTag;
    final coordinates = _coordinates;
    var i = _coordinateCount;
    coordinates[i++] = x1;
    coordinates[i++] = y1;
    coordinates[i++] = x2;
    coordinates[i++] = y2;
    coordinates[i++] = x3;
    coordinates[i++] = y3;
    _coordinateCount = i;
  }

  void close() {
    _ensure(1, 0);
    _verbs[_verbCount++] = _closeTag;
  }

  void addSegment(PdfPathSegment segment) {
    switch (segment) {
      case PdfMoveTo(:final x, :final y):
        moveTo(x, y);
      case PdfLineTo(:final x, :final y):
        lineTo(x, y);
      case PdfCubicTo(
          :final x1,
          :final y1,
          :final x2,
          :final y2,
          :final x3,
          :final y3
        ):
        cubicTo(x1, y1, x2, y2, x3, y3);
      case PdfClosePath():
        close();
    }
  }

  PdfPath takePath() {
    if (_verbCount == 0) return const PdfPath(<PdfPathSegment>[]);
    final verbs = Uint8List(_verbCount)..setRange(0, _verbCount, _verbs);
    final coordinates = Float64List(_coordinateCount)
      ..setRange(0, _coordinateCount, _coordinates);
    final count = _verbCount;
    _verbCount = 0;
    _coordinateCount = 0;
    return PdfPath._packed(verbs, coordinates, count);
  }

  void clear() {
    _verbCount = 0;
    _coordinateCount = 0;
  }

  void _addPoint(int tag, double x, double y) {
    _ensure(1, 2);
    _verbs[_verbCount++] = tag;
    _coordinates[_coordinateCount++] = x;
    _coordinates[_coordinateCount++] = y;
  }

  void _ensure(int verbs, int coordinates) {
    final neededVerbs = _verbCount + verbs;
    if (neededVerbs > _verbs.length) {
      var capacity = _verbs.length;
      while (capacity < neededVerbs) {
        capacity += capacity > 1 ? capacity >> 1 : 1;
      }
      final grown = Uint8List(capacity);
      grown.setRange(0, _verbCount, _verbs);
      _verbs = grown;
    }
    final neededCoordinates = _coordinateCount + coordinates;
    if (neededCoordinates > _coordinates.length) {
      var capacity = _coordinates.length;
      while (capacity < neededCoordinates) {
        capacity += capacity > 1 ? capacity >> 1 : 1;
      }
      final grown = Float64List(capacity);
      grown.setRange(0, _coordinateCount, _coordinates);
      _coordinates = grown;
    }
  }
}

enum PdfFillRule { nonzero, evenOdd }

/// Stroke parameters, with width already scaled into page space.
class PdfStroke {
  const PdfStroke({
    this.width = 1,
    this.cap = 0,
    this.join = 0,
    this.miterLimit = 10,
    this.dashArray = const [],
    this.dashPhase = 0,
  });

  final double width;

  /// 0 = butt, 1 = round, 2 = projecting square (§8.4.3.3).
  final int cap;

  /// 0 = miter, 1 = round, 2 = bevel (§8.4.3.4).
  final int join;

  final double miterLimit;
  final List<double> dashArray;
  final double dashPhase;

  PdfStroke copyWith({
    double? width,
    int? cap,
    int? join,
    double? miterLimit,
    List<double>? dashArray,
    double? dashPhase,
  }) =>
      PdfStroke(
        width: width ?? this.width,
        cap: cap ?? this.cap,
        join: join ?? this.join,
        miterLimit: miterLimit ?? this.miterLimit,
        dashArray: dashArray ?? this.dashArray,
        dashPhase: dashPhase ?? this.dashPhase,
      );
}
