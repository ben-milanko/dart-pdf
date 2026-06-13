import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';

import 'calibrated_color.dart';
import 'color.dart';
import 'function.dart';
import 'matrix.dart';
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
    final type = cos.resolve(dict['ShadingType']);
    final coords = _numbers(cos, dict['Coords']);
    final domain = _numbers(cos, dict['Domain']);
    final extend = cos.resolve(dict['Extend']);
    return PdfShading._(
      shadingType: type is CosInteger ? type.value : 0,
      coords: coords,
      function: PdfFunction.parse(cos, dict['Function']),
      components: _componentCount(cos, dict['ColorSpace']),
      toColor: _colorConverterFor(cos, dict['ColorSpace']),
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
  /// types other than axial (2) and radial (3) — mesh shadings (4-7)
  /// decode via [toMesh]; function-based (1) decodes via
  /// [toFunctionMesh].
  PdfGradient? toGradient(PdfMatrix transform) {
    final fn = function;
    if (fn == null) return null;
    if (shadingType == 2 && coords.length >= 4) {
      return _sampled(fn, isRadial: false, transform: transform);
    }
    if (shadingType == 3 && coords.length >= 6) {
      return _sampled(fn, isRadial: true, transform: transform);
    }
    return null;
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

  /// Builds a converter from the shading's colour space to sRGB. Device
  /// spaces map their components directly; Separation/DeviceN run the tint
  /// transform into the alternate space (§8.6.6.4); ICCBased/CalRGB/
  /// CalGray/Lab apply the calibrated conversion. Falls back to a plain
  /// component conversion for anything unrecognised.
  static PdfColor Function(List<double>) _colorConverterFor(
      CosDocument cos, CosObject? space) {
    final resolved = cos.resolve(space);
    if (resolved is CosArray && resolved.length > 0) {
      final family = cos.resolve(resolved[0]);
      if (family is CosName) {
        switch (family.value) {
          case 'Separation':
          case 'DeviceN':
            // [/Separation name alt tint] or [/DeviceN names alt tint attrs]
            if (resolved.length >= 4) {
              final tint = PdfFunction.parse(cos, resolved[3]);
              if (tint != null) {
                final alternate = _colorConverterFor(cos, resolved[2]);
                return (values) => alternate(tint.evaluateAt(values));
              }
            }
          case 'ICCBased':
          case 'CalRGB':
          case 'CalGray':
          case 'Lab':
            final calibrated = PdfCalibratedColorSpace.parse(cos, resolved);
            if (calibrated != null) return calibrated.toSrgb;
        }
      }
    }
    final n = _componentCount(cos, space);
    return (values) => colorFromComponents(values, n);
  }

  /// Component count of a color-space object (name or array form).
  static int _componentCount(CosDocument cos, CosObject? space) {
    final resolved = cos.resolve(space);
    if (resolved is CosName) {
      return switch (resolved.value) {
        'DeviceGray' || 'CalGray' || 'G' => 1,
        'DeviceCMYK' || 'CMYK' => 4,
        _ => 3,
      };
    }
    if (resolved is CosArray && resolved.length > 0) {
      final family = cos.resolve(resolved[0]);
      if (family is CosName) {
        switch (family.value) {
          case 'ICCBased':
            if (resolved.length > 1) {
              final profile = cos.resolve(resolved[1]);
              if (profile is CosStream) {
                final n = cos.resolve(profile.dictionary['N']);
                if (n is CosInteger) return n.value;
              }
            }
            return 3;
          case 'Indexed':
          case 'Separation':
            return 1;
          case 'CalRGB':
          case 'Lab':
            return 3;
          case 'DeviceN':
            if (resolved.length > 1) {
              final names = cos.resolve(resolved[1]);
              if (names is CosArray) return names.length;
            }
            return 1;
        }
      }
    }
    return 3;
  }
}
