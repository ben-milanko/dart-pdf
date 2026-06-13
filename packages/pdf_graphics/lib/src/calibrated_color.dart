import 'dart:math' as math;

import 'package:pdf_cos/pdf_cos.dart';

import 'color.dart';

/// CIE-based calibrated color spaces used by PDF graphics operators.
///
/// The conversion follows PDF.js's renderer formulas so the Dart rasters are
/// directly comparable to the checked-in PDF.js corpus baselines.
abstract class PdfCalibratedColorSpace {
  const PdfCalibratedColorSpace._(this.components);

  final int components;

  PdfColor toSrgb(List<double> values);

  static PdfCalibratedColorSpace? parse(CosDocument cos, CosObject? object) {
    final resolved = cos.resolve(object);
    if (resolved is! CosArray || resolved.length < 2) return null;
    final family = cos.resolve(resolved[0]);
    final params = cos.resolve(resolved[1]);
    if (family is! CosName || params is! CosDictionary) return null;
    return switch (family.value) {
      'CalGray' => _CalGrayColorSpace._parse(cos, params),
      'CalRGB' => _CalRgbColorSpace._parse(cos, params),
      'Lab' => _LabColorSpace._parse(cos, params),
      _ => null,
    };
  }
}

class _CalGrayColorSpace extends PdfCalibratedColorSpace {
  const _CalGrayColorSpace(this.whitePoint, this.gamma) : super._(1);

  final List<double> whitePoint;
  final double gamma;

  static _CalGrayColorSpace? _parse(CosDocument cos, CosDictionary params) {
    final whitePoint = _numbers(cos, params['WhitePoint']);
    if (whitePoint.length < 3 || whitePoint[0] < 0 || whitePoint[2] < 0) {
      return null;
    }
    final gamma = _num(cos.resolve(params['Gamma']), fallback: 1);
    return _CalGrayColorSpace(
      whitePoint,
      gamma < 1 ? 1 : gamma,
    );
  }

  @override
  PdfColor toSrgb(List<double> values) {
    final a = values.isEmpty ? 0.0 : values[0].clamp(0.0, 1.0).toDouble();
    final l = whitePoint[1] * math.pow(a, gamma);
    final v = math.max(295.8 * math.pow(l, 1 / 3) - 40.8, 0) / 255;
    return PdfColor.gray(v.clamp(0.0, 1.0).toDouble());
  }
}

class _CalRgbColorSpace extends PdfCalibratedColorSpace {
  const _CalRgbColorSpace(
    this.whitePoint,
    this.blackPoint,
    this.gamma,
    this.matrix,
  ) : super._(3);

  final List<double> whitePoint;
  final List<double> blackPoint;
  final List<double> gamma;
  final List<double> matrix;

  static const _bradford = [
    0.8951,
    0.2664,
    -0.1614,
    -0.7502,
    1.7135,
    0.0367,
    0.0389,
    -0.0685,
    1.0296,
  ];
  static const _bradfordInverse = [
    0.9869929,
    -0.1470543,
    0.1599627,
    0.4323053,
    0.5183603,
    0.0492912,
    -0.0085287,
    0.0400428,
    0.9684867,
  ];
  static const _srgbD65XyzToRgb = [
    3.2404542,
    -1.5371385,
    -0.4985314,
    -0.9692660,
    1.8760108,
    0.0415560,
    0.0556434,
    -0.2040259,
    1.0572252,
  ];
  static const _flatWhitePoint = [1.0, 1.0, 1.0];
  static final _decodeLConstant = math.pow((8 + 16) / 116, 3) / 8;

  static _CalRgbColorSpace? _parse(CosDocument cos, CosDictionary params) {
    final whitePoint = _numbers(cos, params['WhitePoint']);
    if (whitePoint.length < 3 || whitePoint[0] < 0 || whitePoint[2] < 0) {
      return null;
    }
    var blackPoint = _numbers(cos, params['BlackPoint']);
    if (blackPoint.length < 3 ||
        blackPoint[0] < 0 ||
        blackPoint[1] < 0 ||
        blackPoint[2] < 0) {
      blackPoint = const [0.0, 0.0, 0.0];
    }
    var gamma = _numbers(cos, params['Gamma']);
    if (gamma.length < 3 || gamma.any((v) => v < 0)) {
      gamma = const [1.0, 1.0, 1.0];
    }
    var matrix = _numbers(cos, params['Matrix']);
    if (matrix.length < 9) {
      matrix = const [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0];
    }
    return _CalRgbColorSpace(whitePoint, blackPoint, gamma, matrix);
  }

  @override
  PdfColor toSrgb(List<double> values) {
    final a = _component(values, 0);
    final b = _component(values, 1);
    final c = _component(values, 2);
    final agr = a == 1 ? 1.0 : math.pow(a, gamma[0]).toDouble();
    final bgg = b == 1 ? 1.0 : math.pow(b, gamma[1]).toDouble();
    final cgb = c == 1 ? 1.0 : math.pow(c, gamma[2]).toDouble();

    final xyz = [
      matrix[0] * agr + matrix[3] * bgg + matrix[6] * cgb,
      matrix[1] * agr + matrix[4] * bgg + matrix[7] * cgb,
      matrix[2] * agr + matrix[5] * bgg + matrix[8] * cgb,
    ];
    final xyzFlat = _normalizeWhitePointToFlat(whitePoint, xyz);
    final xyzBlack = _compensateBlackPoint(blackPoint, xyzFlat);
    final xyzD65 = _normalizeWhitePointToD65(_flatWhitePoint, xyzBlack);
    final srgb = _matrixProduct(_srgbD65XyzToRgb, xyzD65);
    return PdfColor(
      _srgbTransfer(srgb[0]),
      _srgbTransfer(srgb[1]),
      _srgbTransfer(srgb[2]),
    );
  }

  static double _component(List<double> values, int index) =>
      (index < values.length ? values[index] : 0.0).clamp(0.0, 1.0).toDouble();

  static List<double> _matrixProduct(List<double> a, List<double> b) => [
        a[0] * b[0] + a[1] * b[1] + a[2] * b[2],
        a[3] * b[0] + a[4] * b[1] + a[5] * b[2],
        a[6] * b[0] + a[7] * b[1] + a[8] * b[2],
      ];

  static List<double> _toFlat(
          List<double> sourceWhitePoint, List<double> lms) =>
      [
        lms[0] / sourceWhitePoint[0],
        lms[1] / sourceWhitePoint[1],
        lms[2] / sourceWhitePoint[2],
      ];

  static List<double> _toD65(List<double> sourceWhitePoint, List<double> lms) =>
      [
        lms[0] * 0.95047 / sourceWhitePoint[0],
        lms[1] / sourceWhitePoint[1],
        lms[2] * 1.08883 / sourceWhitePoint[2],
      ];

  static double _srgbTransfer(double color) {
    if (color <= 0.0031308) return (12.92 * color).clamp(0.0, 1.0);
    if (color >= 0.99554525) return 1;
    return (1.055 * math.pow(color, 1 / 2.4) - 0.055).clamp(0.0, 1.0);
  }

  static double _decodeL(double l) {
    if (l < 0) return -_decodeL(-l);
    if (l > 8) return math.pow((l + 16) / 116, 3).toDouble();
    return l * _decodeLConstant;
  }

  static List<double> _compensateBlackPoint(
    List<double> sourceBlackPoint,
    List<double> xyzFlat,
  ) {
    if (sourceBlackPoint[0] == 0 &&
        sourceBlackPoint[1] == 0 &&
        sourceBlackPoint[2] == 0) {
      return xyzFlat;
    }
    final zeroDecodeL = _decodeL(0);
    final xScale = (1 - zeroDecodeL) / (1 - _decodeL(sourceBlackPoint[0]));
    final yScale = (1 - zeroDecodeL) / (1 - _decodeL(sourceBlackPoint[1]));
    final zScale = (1 - zeroDecodeL) / (1 - _decodeL(sourceBlackPoint[2]));
    return [
      xyzFlat[0] * xScale + 1 - xScale,
      xyzFlat[1] * yScale + 1 - yScale,
      xyzFlat[2] * zScale + 1 - zScale,
    ];
  }

  static List<double> _normalizeWhitePointToFlat(
    List<double> sourceWhitePoint,
    List<double> xyz,
  ) {
    if (sourceWhitePoint[0] == 1 && sourceWhitePoint[2] == 1) return xyz;
    final lms = _matrixProduct(_bradford, xyz);
    final lmsFlat = _toFlat(sourceWhitePoint, lms);
    return _matrixProduct(_bradfordInverse, lmsFlat);
  }

  static List<double> _normalizeWhitePointToD65(
    List<double> sourceWhitePoint,
    List<double> xyz,
  ) {
    final lms = _matrixProduct(_bradford, xyz);
    final lmsD65 = _toD65(sourceWhitePoint, lms);
    return _matrixProduct(_bradfordInverse, lmsD65);
  }
}

class _LabColorSpace extends PdfCalibratedColorSpace {
  const _LabColorSpace(this.whitePoint, this.range) : super._(3);

  final List<double> whitePoint;
  final List<double> range;

  static _LabColorSpace? _parse(CosDocument cos, CosDictionary params) {
    final whitePoint = _numbers(cos, params['WhitePoint']);
    if (whitePoint.length < 3 || whitePoint[0] < 0 || whitePoint[2] < 0) {
      return null;
    }
    var range = _numbers(cos, params['Range']);
    if (range.length < 4) range = const [-100.0, 100.0, -100.0, 100.0];
    return _LabColorSpace(whitePoint, range);
  }

  @override
  PdfColor toSrgb(List<double> values) {
    final l = (values.isNotEmpty ? values[0] : 0.0).clamp(0.0, 100.0);
    final a = (values.length > 1 ? values[1] : 0.0)
        .clamp(range[0], range[1])
        .toDouble();
    final b = (values.length > 2 ? values[2] : 0.0)
        .clamp(range[2], range[3])
        .toDouble();
    final fy = (l + 16) / 116;
    final fx = fy + a / 500;
    final fz = fy - b / 200;
    final xyz = [
      whitePoint[0] * _labInverse(fx),
      whitePoint[1] * _labInverse(fy),
      whitePoint[2] * _labInverse(fz),
    ];
    final xyzD65 = _CalRgbColorSpace._normalizeWhitePointToD65(
      whitePoint,
      xyz,
    );
    final srgb = _CalRgbColorSpace._matrixProduct(
      _CalRgbColorSpace._srgbD65XyzToRgb,
      xyzD65,
    );
    return PdfColor(
      _CalRgbColorSpace._srgbTransfer(srgb[0]),
      _CalRgbColorSpace._srgbTransfer(srgb[1]),
      _CalRgbColorSpace._srgbTransfer(srgb[2]),
    );
  }

  static double _labInverse(double v) {
    const e = 216 / 24389;
    const k = 24389 / 27;
    final cube = v * v * v;
    return cube > e ? cube : (116 * v - 16) / k;
  }
}

List<double> _numbers(CosDocument cos, CosObject? object) {
  final value = cos.resolve(object);
  if (value is! CosArray) return const [];
  return [
    for (final item in value.items)
      switch (cos.resolve(item)) {
        CosInteger(:final value) => value.toDouble(),
        CosReal(:final value) => value,
        _ => 0.0,
      },
  ];
}

double _num(CosObject? object, {required double fallback}) => switch (object) {
      CosInteger(:final value) => value.toDouble(),
      CosReal(:final value) => value,
      _ => fallback,
    };
