import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';

import 'color.dart';
import 'color_space.dart';
import 'function.dart';
import 'mesh.dart';

/// A gradient ready for a device: stops pre-sampled from the shading's
/// function, with geometry in the space mapped by [transform].
class PdfGradient {
  const PdfGradient({
    required this.isRadial,
    required this.coords,
    required this.colors,
    required this.stops,
    required this.transform,
    this.extendStart = true,
    this.extendEnd = true,
  });

  final bool isRadial;

  /// Axial: `[x0, y0, x1, y1]`. Radial: `[x0, y0, r0, x1, y1, r1]`.
  final List<double> coords;

  final List<PdfColor> colors;
  final List<double> stops;

  /// Maps gradient (pattern/shading) space to page space.
  final PdfMatrix transform;

  /// PDF /Extend semantics: an extended end clamps to its terminal color,
  /// an unextended end paints nothing beyond the gradient geometry.
  final bool extendStart;
  final bool extendEnd;

  PdfColor get averageColor {
    var r = 0.0, g = 0.0, b = 0.0;
    for (final c in colors) {
      r += c.red;
      g += c.green;
      b += c.blue;
    }
    final n = colors.isEmpty ? 1 : colors.length;
    return PdfColor(r / n, g / n, b / n);
  }
}

/// A parsed shading dictionary (§8.7.4.5).
class PdfShading {
  const PdfShading._({
    required this.shadingType,
    required this.coords,
    required this.function,
    required this.components,
    required this.toColor,
    required this.domain,
    required this.extendStart,
    required this.extendEnd,
    CosDocument? cos,
    CosStream? stream,
    CosDictionary? dict,
  })  : _cos = cos,
        _stream = stream,
        _dict = dict;

  final int shadingType;
  final List<double> coords;
  final PdfFunction? function;
  final int components;

  /// Maps a raw color value (the shading function's output, in the
  /// shading's own colour space) to sRGB. For device spaces this is a
  /// plain [colorFromComponents]; for Separation/DeviceN it runs the tint
  /// transform into the alternate space (§8.6.6.4); for ICCBased/Cal*/Lab
  /// it applies the calibrated conversion.
  final PdfColor Function(List<double>) toColor;
  final List<double> domain;
  final bool extendStart;
  final bool extendEnd;

  /// Kept for mesh shadings, whose geometry lives in the stream payload.
  final CosDocument? _cos;
  final CosStream? _stream;
  final CosDictionary? _dict;

  static PdfShading? parse(CosDocument cos, CosObject? object) {
    final resolved = cos.resolve(object);
    final CosDictionary dict;
    if (resolved is CosStream) {
      dict = resolved.dictionary;
    } else if (resolved is CosDictionary) {
      dict = resolved;
    } else {
      return null;
    }
    // Doc-level parse cache (#534): `sh` and shading-pattern fills re-parse
    // the same shading object (and its function's sample stream) on every
    // operator selection, every render. Parsed shadings are immutable -
    // geometry transforms apply per call - and identity keying makes
    // invalidation free (edits build new COS objects).
    final hit = _parsed[dict];
    if (hit != null) return hit;
    final shading = _parse(cos, resolved, dict);
    if (shading != null) _parsed[dict] = shading;
    return shading;
  }

  static final Expando<PdfShading> _parsed = Expando();

  static PdfShading? _parse(
      CosDocument cos, CosObject resolved, CosDictionary dict) {
    final type = cos.resolve(dict['ShadingType']);
    final coords = _numbers(cos, dict['Coords']);
    final domain = _numbers(cos, dict['Domain']);
    final extend = cos.resolve(dict['Extend']);
    final colorSpace = PdfColorSpace.parse(cos, dict['ColorSpace']);
    return PdfShading._(
      shadingType: type is CosInteger ? type.value : 0,
      coords: coords,
      function: PdfFunction.parse(cos, dict['Function']),
      components: colorSpace.channels,
      toColor: colorSpace.toSrgb,
      domain: domain.length >= 2 ? domain : const [0, 1],
      extendStart: extend is CosArray &&
          extend.length > 0 &&
          extend[0] == const CosBoolean(true),
      extendEnd: extend is CosArray &&
          extend.length > 1 &&
          extend[1] == const CosBoolean(true),
      cos: cos,
      stream: resolved is CosStream ? resolved : null,
      dict: dict,
    );
  }

  /// Decodes a mesh shading (types 4–7) into triangles in the space
  /// mapped by [transform]. Null for non-mesh types or broken data.
  PdfMesh? toMesh(PdfMatrix transform) {
    final cos = _cos;
    final stream = _stream;
    final dict = _dict;
    if (shadingType < 4 || shadingType > 7) return null;
    if (cos == null || stream == null || dict == null) return null;

    int intOf(String key, int fallback) {
      final v = cos.resolve(dict[key]);
      return v is CosInteger ? v.value : fallback;
    }

    final Uint8List data;
    try {
      data = cos.decodeStreamData(stream);
    } on Exception {
      return null;
    }
    return PdfMeshParser(
      data: data,
      shadingType: shadingType,
      bitsPerCoordinate: intOf('BitsPerCoordinate', 16),
      bitsPerComponent: intOf('BitsPerComponent', 8),
      bitsPerFlag: intOf('BitsPerFlag', 8),
      decode: _numbers(cos, dict['Decode']),
      components: components,
      verticesPerRow: intOf('VerticesPerRow', 0),
      function: function,
      toColor: toColor,
      transform: transform,
    ).parse();
  }

  /// Samples a function-based shading (type 1) into a Gouraud triangle
  /// grid in the space mapped by [transform]. The shading's own /Matrix
  /// (domain space → target space) composes in. Null for other types.
  PdfMesh? toFunctionMesh(PdfMatrix transform) {
    final cos = _cos;
    final dict = _dict;
    final fn = function;
    if (shadingType != 1 || cos == null || dict == null || fn == null) {
      return null;
    }
    final d = domain.length >= 4 ? domain : const [0.0, 1.0, 0.0, 1.0];
    final m = _numbers(cos, dict['Matrix']);
    final matrix = m.length >= 6
        ? PdfMatrix(m[0], m[1], m[2], m[3], m[4], m[5]).concat(transform)
        : transform;
    // 24×24 cells ≈ 1150 triangles: smooth enough for 2D color fields
    // at print sizes, cheap enough to sample the function 625 times.
    const cells = 24;
    final vertices = <PdfMeshVertex>[];
    final triangles = <int>[];
    for (var j = 0; j <= cells; j++) {
      final y = d[2] + (d[3] - d[2]) * j / cells;
      for (var i = 0; i <= cells; i++) {
        final x = d[0] + (d[1] - d[0]) * i / cells;
        final color = toColor(fn.evaluateAt([x, y]));
        vertices.add(PdfMeshVertex(
            matrix.transformX(x, y), matrix.transformY(x, y), color));
      }
    }
    for (var j = 0; j < cells; j++) {
      for (var i = 0; i < cells; i++) {
        final a = j * (cells + 1) + i;
        final b = a + 1;
        final c = a + cells + 1;
        triangles
          ..add(a)
          ..add(b)
          ..add(c)
          ..add(b)
          ..add(c + 1)
          ..add(c);
      }
    }
    return PdfMesh(vertices, triangles);
  }

  /// Samples the shading into gradient stops. Returns null for shading
  /// types other than axial (2) and radial (3) - mesh shadings (4-7)
  /// decode via [toMesh]; function-based (1) decodes via
  /// [toFunctionMesh].
  PdfGradient? toGradient(PdfMatrix transform) {
    final fn = function;
    if (fn == null) return null;
    if (shadingType == 2 && coords.length >= 4) {
      return _sampled(fn, isRadial: false, transform: transform);
    }
    if (shadingType == 3 && coords.length >= 6) {
      // Non-nested radial circles form a swept cone a single two-point
      // conical gradient can't express (the /Extend=false boundary isn't a
      // plain clamp edge, and a focal outside the end circle degenerates in
      // Skia). Those decode through [toRadialConeMesh] instead; only the
      // nested case - which maps cleanly onto a device radial gradient -
      // returns here.
      if (!_radialCirclesNested()) return null;
      return _sampled(fn, isRadial: true, transform: transform);
    }
    return null;
  }

  /// Whether a radial shading's two circles are nested (one inside the
  /// other, including concentric), the case a device radial gradient renders
  /// faithfully.
  bool _radialCirclesNested() {
    if (coords.length < 6) return true;
    final dx = coords[3] - coords[0], dy = coords[4] - coords[1];
    final d = math.sqrt(dx * dx + dy * dy);
    return d <= (coords[2] - coords[5]).abs() + 1e-6;
  }

  /// A radial shading (type 3) with non-nested circles, decoded into a
  /// Gouraud mesh in the space mapped by [transform]; null for other shading
  /// types or nested circles (which [toGradient] handles).
  ///
  /// A radial shading (§8.7.4.5.4) sweeps a circle whose centre and radius
  /// interpolate from `(c0, r0)` at s=0 to `(c1, r1)` at s=1; a point takes
  /// the colour of the greatest s whose circle passes through it. When the
  /// circles are not nested that swept region is a cone the device can't get
  /// from `Gradient.radial`, so we foliate it: one constant-colour ring per
  /// sampled s, joined into quad strips and emitted in increasing-s order so
  /// a later (larger-s) ring paints over an earlier one - exactly the
  /// "greatest s wins" rule. /Extend widens the s-range (toward the radius-0
  /// apex on one side, out past [clip] on the growing side); unextended ends
  /// stop at s=0 / s=1, leaving the correct hard edge.
  PdfMesh? toRadialConeMesh(PdfMatrix transform, {PdfRect? clip}) {
    final fn = function;
    if (shadingType != 3 || fn == null || coords.length < 6) return null;
    final x0 = coords[0], y0 = coords[1], r0 = coords[2];
    final x1 = coords[3], y1 = coords[4], r1 = coords[5];
    if (r0 < 0 || r1 < 0) return null;
    final dx = x1 - x0, dy = y1 - y0;
    final d = math.sqrt(dx * dx + dy * dy);
    const eps = 1e-6;
    if (d <= (r0 - r1).abs() + eps) return null; // nested - not our case
    final dr = r1 - r0;

    // The largest circle radius the mesh must reach so the growing (extended)
    // side covers the fill. Derived from the clip corners mapped back into the
    // shading's own space; a generous geometry-based floor otherwise.
    var reach = (d + r0 + r1) * 4 + 1;
    final inv = transform.inverted();
    if (clip != null && inv != null) {
      for (final (cx, cy) in [
        (clip.left, clip.bottom),
        (clip.right, clip.bottom),
        (clip.right, clip.top),
        (clip.left, clip.top),
      ]) {
        final gx = inv.transformX(cx, cy), gy = inv.transformY(cx, cy);
        final d0 = math.sqrt((gx - x0) * (gx - x0) + (gy - y0) * (gy - y0));
        final d1 = math.sqrt((gx - x1) * (gx - x1) + (gy - y1) * (gy - y1));
        reach = math.max(reach, math.max(d0, d1) + r0 + r1);
      }
    }

    // s-range of the sweep. rad(s) = r0 + s*dr; the domain [0,1] is widened
    // for /Extend toward the radius-0 apex (a finite tip) or out to [reach].
    double sLo, sHi;
    if (!extendStart) {
      sLo = 0;
    } else if (dr > eps) {
      sLo = -r0 / dr; // radius shrinks to the apex
    } else if (dr < -eps) {
      sLo = (reach - r0) / dr; // radius grows; dr<0 makes this negative
    } else {
      sLo = -reach / d; // parallel: translate out by [reach]
    }
    if (!extendEnd) {
      sHi = 1;
    } else if (dr > eps) {
      sHi = (reach - r0) / dr;
    } else if (dr < -eps) {
      sHi = -r0 / dr; // radius shrinks to the apex past s=1
    } else {
      sHi = 1 + reach / d;
    }
    if (!(sHi > sLo)) return null;

    final t0 = domain[0], t1 = domain[1];
    PdfColor colorAt(double s) =>
        toColor(fn.evaluate(t0 + s.clamp(0.0, 1.0) * (t1 - t0)));

    // Sample s: fine across the in-domain [0,1] band where colour varies,
    // coarse over the extended tails (constant terminal colour, but the
    // geometry still moves).
    final sList = <double>[];
    void addBand(double a, double b, int steps) {
      if (b <= a) return;
      final from = sList.isEmpty ? 0 : 1; // skip the shared boundary
      for (var i = from; i <= steps; i++) {
        sList.add(a + (b - a) * i / steps);
      }
    }

    if (sLo < 0) addBand(sLo, 0, 14);
    addBand(math.max(sLo, 0), math.min(sHi, 1), 48);
    if (sHi > 1) addBand(1, sHi, 14);
    if (sList.length < 2) return null;

    const angular = 96;
    final vertices = <PdfMeshVertex>[];
    for (final s in sList) {
      final cx = x0 + s * dx, cy = y0 + s * dy;
      final rad = r0 + s * dr;
      final color = colorAt(s);
      for (var j = 0; j <= angular; j++) {
        final a = 2 * math.pi * j / angular;
        final px = cx + rad * math.cos(a), py = cy + rad * math.sin(a);
        vertices.add(PdfMeshVertex(
            transform.transformX(px, py), transform.transformY(px, py), color));
      }
    }

    final ringStride = angular + 1;
    final triangles = <int>[];
    for (var i = 0; i < sList.length - 1; i++) {
      final base = i * ringStride;
      final next = base + ringStride;
      for (var j = 0; j < angular; j++) {
        final a = base + j, b = base + j + 1;
        final c = next + j, e = next + j + 1;
        triangles
          ..add(a)
          ..add(b)
          ..add(c)
          ..add(b)
          ..add(e)
          ..add(c);
      }
    }
    return PdfMesh(vertices, triangles);
  }

  PdfGradient _sampled(PdfFunction fn,
      {required bool isRadial, required PdfMatrix transform}) {
    const sampleCount = 32;
    final colors = <PdfColor>[];
    final stops = <double>[];
    for (var i = 0; i <= sampleCount; i++) {
      final s = i / sampleCount;
      final t = domain[0] + s * (domain[1] - domain[0]);
      colors.add(toColor(fn.evaluate(t)));
      stops.add(s);
    }
    return PdfGradient(
      isRadial: isRadial,
      coords: coords,
      colors: colors,
      stops: stops,
      transform: transform,
      extendStart: extendStart,
      extendEnd: extendEnd,
    );
  }

  static List<double> _numbers(CosDocument cos, CosObject? object) {
    final v = cos.resolve(object);
    if (v is! CosArray) return const [];
    return [
      for (final item in v.items)
        switch (cos.resolve(item)) {
          CosInteger(:final value) => value.toDouble(),
          CosReal(:final value) => value,
          _ => 0.0,
        },
    ];
  }
}
