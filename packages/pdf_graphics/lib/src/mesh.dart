import 'dart:math' as math;
import 'dart:typed_data';

import 'color.dart';
import 'function.dart';
import 'matrix.dart';

/// One mesh vertex in page space.
class PdfMeshVertex {
  const PdfMeshVertex(this.x, this.y, this.color);

  final double x;
  final double y;
  final PdfColor color;
}

/// A triangle mesh with per-vertex colors - the decoded form of mesh
/// shadings (types 4–7). Patch meshes arrive pre-subdivided; devices only
/// ever see Gouraud triangles.
class PdfMesh {
  const PdfMesh(this.vertices, this.triangles);

  final List<PdfMeshVertex> vertices;

  /// Vertex indices, three per triangle.
  final List<int> triangles;

  PdfColor get averageColor {
    var r = 0.0, g = 0.0, b = 0.0;
    for (final v in vertices) {
      r += v.color.red;
      g += v.color.green;
      b += v.color.blue;
    }
    final n = vertices.isEmpty ? 1 : vertices.length;
    return PdfColor(r / n, g / n, b / n);
  }
}

/// Decodes the bit-packed vertex/patch data of mesh shadings.
class PdfMeshParser {
  PdfMeshParser({
    required Uint8List data,
    required this.shadingType,
    required this.bitsPerCoordinate,
    required this.bitsPerComponent,
    required this.bitsPerFlag,
    required this.decode,
    required this.components,
    required this.verticesPerRow,
    required this.function,
    required this.toColor,
    required this.transform,
  }) : _reader = _BitReader(data);

  final int shadingType;
  final int bitsPerCoordinate;
  final int bitsPerComponent;
  final int bitsPerFlag;
  final List<double> decode;
  final int components;
  final int verticesPerRow;
  final PdfFunction? function;

  /// Maps the vertices' colour values, in the shading's own colour space, to
  /// sRGB - the shading's [PdfColorSpace.toSrgb], so Separation/DeviceN/
  /// ICCBased/CIE mesh shadings convert the same way axial and radial ones
  /// do.
  final PdfColor Function(List<double>) toColor;
  final PdfMatrix transform;
  final _BitReader _reader;

  final List<PdfMeshVertex> _vertices = [];
  final List<int> _triangles = [];

  /// How many color values each vertex/corner carries in the stream.
  int get _valueCount => function != null ? 1 : components;

  PdfMesh? parse() {
    try {
      switch (shadingType) {
        case 4:
          _parseFreeForm();
        case 5:
          _parseLattice();
        case 6:
        case 7:
          _parsePatches(tensor: shadingType == 7);
        default:
          return null;
      }
    } on _OutOfData {
      // truncated stream: keep what decoded so far (lenient on input)
    }
    if (_triangles.isEmpty) return null;
    return PdfMesh(_vertices, _triangles);
  }

  // ---------- shared decoding ----------

  double _decodeValue(int raw, int bits, int decodeIndex) {
    final max = bits >= 32 ? 0xFFFFFFFF : (1 << bits) - 1;
    final d0 = decodeIndex * 2 < decode.length ? decode[decodeIndex * 2] : 0.0;
    final d1 = decodeIndex * 2 + 1 < decode.length
        ? decode[decodeIndex * 2 + 1]
        : 1.0;
    return d0 + raw / max * (d1 - d0);
  }

  (double, double) _readPoint() {
    final x = _decodeValue(_reader.read(bitsPerCoordinate), bitsPerCoordinate, 0);
    final y = _decodeValue(_reader.read(bitsPerCoordinate), bitsPerCoordinate, 1);
    return (transform.transformX(x, y), transform.transformY(x, y));
  }

  PdfColor _readColor() {
    final values = <double>[
      for (var i = 0; i < _valueCount; i++)
        _decodeValue(_reader.read(bitsPerComponent), bitsPerComponent, 2 + i),
    ];
    final fn = function;
    if (fn != null) {
      return toColor(fn.evaluate(values[0]));
    }
    return toColor(values);
  }

  PdfMeshVertex _readVertex() {
    final (x, y) = _readPoint();
    return PdfMeshVertex(x, y, _readColor());
  }

  int _addVertex(PdfMeshVertex v) {
    _vertices.add(v);
    return _vertices.length - 1;
  }

  void _emit(int a, int b, int c) => _triangles.addAll([a, b, c]);

  // ---------- type 4: free-form Gouraud triangles ----------

  void _parseFreeForm() {
    int? va, vb, vc;
    while (_reader.canRead(bitsPerFlag)) {
      final flag = _reader.read(bitsPerFlag);
      if (flag == 0) {
        final a = _addVertex(_readVertex());
        _reader.read(bitsPerFlag); // flags of the 2nd and 3rd vertices
        final b = _addVertex(_readVertex());
        _reader.read(bitsPerFlag);
        final c = _addVertex(_readVertex());
        _emit(a, b, c);
        va = a;
        vb = b;
        vc = c;
      } else if (vb != null && vc != null) {
        final d = _addVertex(_readVertex());
        if (flag == 1) {
          _emit(vb, vc, d);
          va = vb;
        } else {
          _emit(va!, vc, d);
        }
        vb = vc;
        vc = d;
      } else {
        return; // continuation flag with no triangle to continue
      }
    }
  }

  // ---------- type 5: lattice-form Gouraud triangles ----------

  void _parseLattice() {
    if (verticesPerRow < 2) return;
    List<int>? previousRow;
    while (_reader.canRead(
        verticesPerRow * (2 * bitsPerCoordinate + _valueCount * bitsPerComponent))) {
      final row = [
        for (var i = 0; i < verticesPerRow; i++) _addVertex(_readVertex()),
      ];
      if (previousRow != null) {
        for (var i = 0; i + 1 < verticesPerRow; i++) {
          _emit(previousRow[i], previousRow[i + 1], row[i]);
          _emit(previousRow[i + 1], row[i + 1], row[i]);
        }
      }
      previousRow = row;
    }
  }

  // ---------- types 6 and 7: Coons / tensor patch meshes ----------

  /// How finely each patch subdivides (per axis).
  static const int _patchDivisions = 8;

  void _parsePatches({required bool tensor}) {
    List<List<(double, double)>>? previous;
    List<PdfColor>? previousColors;

    while (_reader.canRead(bitsPerFlag)) {
      final flag = _reader.read(bitsPerFlag);

      // grid[i][j]: i is the s (row) direction, j the t (column) direction
      final grid = List.generate(4, (_) => List.filled(4, (0.0, 0.0)));
      final colors = List<PdfColor>.filled(4, PdfColor.black);

      var firstBoundaryIndex = 0;
      if (flag != 0) {
        if (previous == null || previousColors == null) return;
        // the shared edge becomes the new patch's first row p11..p14
        final (edge, c) = switch (flag) {
          1 => (
              [previous[0][3], previous[1][3], previous[2][3], previous[3][3]],
              [previousColors[1], previousColors[2]]
            ),
          2 => (
              [previous[3][3], previous[3][2], previous[3][1], previous[3][0]],
              [previousColors[2], previousColors[3]]
            ),
          _ => (
              [previous[3][0], previous[2][0], previous[1][0], previous[0][0]],
              [previousColors[3], previousColors[0]]
            ),
        };
        for (var j = 0; j < 4; j++) {
          grid[0][j] = edge[j];
        }
        colors[0] = c[0];
        colors[1] = c[1];
        firstBoundaryIndex = 4;
      }

      // boundary points in spec order: p11 p12 p13 p14 / p24 p34 p44 /
      // p43 p42 p41 / p31 p21
      const boundary = [
        (0, 0), (0, 1), (0, 2), (0, 3), //
        (1, 3), (2, 3), (3, 3), //
        (3, 2), (3, 1), (3, 0), //
        (2, 0), (1, 0),
      ];
      for (var k = firstBoundaryIndex; k < 12; k++) {
        final (i, j) = boundary[k];
        grid[i][j] = _readPoint();
      }
      if (tensor) {
        // interior points: p22 p23 p33 p32
        grid[1][1] = _readPoint();
        grid[1][2] = _readPoint();
        grid[2][2] = _readPoint();
        grid[2][1] = _readPoint();
      } else {
        _fillCoonsInterior(grid);
      }
      for (var k = flag == 0 ? 0 : 2; k < 4; k++) {
        colors[k] = _readColor();
      }

      _tessellatePatch(grid, colors);
      previous = grid;
      previousColors = colors;
    }
  }

  /// Computes a Coons patch's interior control points from its boundary
  /// (§8.7.4.5.7) so both patch types evaluate as tensor surfaces.
  static void _fillCoonsInterior(List<List<(double, double)>> p) {
    (double, double) combine(
        List<((double, double), double)> terms) {
      var x = 0.0, y = 0.0;
      for (final (point, weight) in terms) {
        x += point.$1 * weight;
        y += point.$2 * weight;
      }
      return (x / 9, y / 9);
    }

    p[1][1] = combine([
      (p[0][0], -4), (p[0][1], 6), (p[1][0], 6), //
      (p[0][3], -2), (p[3][0], -2), (p[3][1], 3), (p[1][3], 3), (p[3][3], -1),
    ]);
    p[1][2] = combine([
      (p[0][3], -4), (p[0][2], 6), (p[1][3], 6), //
      (p[0][0], -2), (p[3][3], -2), (p[3][2], 3), (p[1][0], 3), (p[3][0], -1),
    ]);
    p[2][1] = combine([
      (p[3][0], -4), (p[3][1], 6), (p[2][0], 6), //
      (p[3][3], -2), (p[0][0], -2), (p[0][1], 3), (p[2][3], 3), (p[0][3], -1),
    ]);
    p[2][2] = combine([
      (p[3][3], -4), (p[3][2], 6), (p[2][3], 6), //
      (p[3][0], -2), (p[0][3], -2), (p[0][2], 3), (p[2][0], 3), (p[0][0], -1),
    ]);
  }

  /// Chooses a per-patch subdivision count (#536, PDFium's adaptive
  /// Coons/tensor tessellation): a patch small on the page or nearly flat in
  /// colour needs far fewer than [_patchDivisions] cells, and a 1000-patch
  /// mesh otherwise always emits 128k triangles. Driven by the larger of two
  /// metrics so a big patch never under-tessellates its geometry even when
  /// its corners share a colour:
  ///  - screen size: the max page-space span of the four corners, one cell
  ///    per [_patchTargetEdge] units;
  ///  - colour delta: the max per-channel corner-colour difference, scaled so
  ///    a full-range transition still asks for the full division count
  ///    (PDFium's 4/255 corner-delta threshold is the floor below which a
  ///    patch reads as flat).
  /// Clamped to `[1, _patchDivisions]` - 8 stays the ceiling.
  static const double _patchTargetEdge = 12; // page units per cell
  static const double _flatColorDelta = 4 / 255;

  int _divisionsFor(
      List<List<(double, double)>> grid, List<PdfColor> colors) {
    // Four corners of the bicubic grid.
    final corners = [grid[0][0], grid[0][3], grid[3][3], grid[3][0]];
    var span = 0.0;
    for (var i = 0; i < 4; i++) {
      for (var j = i + 1; j < 4; j++) {
        final dx = corners[i].$1 - corners[j].$1;
        final dy = corners[i].$2 - corners[j].$2;
        final d = dx * dx + dy * dy;
        if (d > span) span = d;
      }
    }
    final sizeDiv = (math.sqrt(span) / _patchTargetEdge).ceil();

    var colorDelta = 0.0;
    for (var i = 0; i < 4; i++) {
      for (var j = i + 1; j < 4; j++) {
        final d = math.max(
            (colors[i].red - colors[j].red).abs(),
            math.max((colors[i].green - colors[j].green).abs(),
                (colors[i].blue - colors[j].blue).abs()));
        if (d > colorDelta) colorDelta = d;
      }
    }
    // Below the flat threshold the colour contributes nothing; above it, ramp
    // linearly to the full division count at a full-range transition.
    final colorDiv = colorDelta <= _flatColorDelta
        ? 0
        : (colorDelta * _patchDivisions).ceil();

    final n = math.max(sizeDiv, colorDiv);
    return n < 1 ? 1 : (n > _patchDivisions ? _patchDivisions : n);
  }

  /// Evaluates the bicubic Bézier surface on a regular grid and emits
  /// triangles with bilinearly interpolated corner colors.
  void _tessellatePatch(
      List<List<(double, double)>> grid, List<PdfColor> colors) {
    final n = _divisionsFor(grid, colors);
    final base = _vertices.length;
    for (var si = 0; si <= n; si++) {
      final s = si / n;
      for (var ti = 0; ti <= n; ti++) {
        final t = ti / n;
        var x = 0.0, y = 0.0;
        for (var i = 0; i < 4; i++) {
          final bs = _bernstein(i, s);
          for (var j = 0; j < 4; j++) {
            final w = bs * _bernstein(j, t);
            x += grid[i][j].$1 * w;
            y += grid[i][j].$2 * w;
          }
        }
        // corner colors: c0 at (0,0), c1 at (0,1), c2 at (1,1), c3 at (1,0)
        final color = PdfColor(
          _bilinear(colors[0].red, colors[1].red, colors[2].red,
              colors[3].red, s, t),
          _bilinear(colors[0].green, colors[1].green, colors[2].green,
              colors[3].green, s, t),
          _bilinear(colors[0].blue, colors[1].blue, colors[2].blue,
              colors[3].blue, s, t),
        );
        _vertices.add(PdfMeshVertex(x, y, color));
      }
    }
    for (var si = 0; si < n; si++) {
      for (var ti = 0; ti < n; ti++) {
        final a = base + si * (n + 1) + ti;
        final b = a + 1;
        final c = a + (n + 1);
        final d = c + 1;
        _emit(a, b, c);
        _emit(b, d, c);
      }
    }
  }

  static double _bernstein(int i, double u) {
    final v = 1 - u;
    return switch (i) {
      0 => v * v * v,
      1 => 3 * u * v * v,
      2 => 3 * u * u * v,
      _ => u * u * u,
    };
  }

  static double _bilinear(
      double c00, double c01, double c11, double c10, double s, double t) {
    final top = c00 + (c01 - c00) * t;
    final bottom = c10 + (c11 - c10) * t;
    return top + (bottom - top) * s;
  }
}

class _OutOfData implements Exception {
  const _OutOfData();
}

/// MSB-first bit reader over the mesh data stream.
class _BitReader {
  _BitReader(this.data);

  final Uint8List data;
  int _byte = 0;
  int _bit = 0;

  bool canRead(int bits) => (data.length - _byte) * 8 - _bit >= bits;

  int read(int bits) {
    var value = 0;
    for (var i = 0; i < bits; i++) {
      if (_byte >= data.length) throw const _OutOfData();
      value = (value << 1) | ((data[_byte] >> (7 - _bit)) & 1);
      _bit++;
      if (_bit == 8) {
        _bit = 0;
        _byte++;
      }
    }
    return value;
  }
}
