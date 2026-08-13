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
