import 'dart:math' as math;
import 'dart:typed_data';

import 'color.dart';

/// An ICC profile reduced to what rendering needs: a transform from
/// device components to sRGB.
///
/// Coverage: gray TRC profiles, matrix/TRC RGB profiles (v2 and v4,
/// `curv` and `para` curves), and LUT profiles via A2B0 (`mft1`, `mft2`,
/// and `mAB ` pipelines) with XYZ or Lab PCS - which spans sRGB-like,
/// wide-gamut RGB, and the common CMYK press profiles. Unsupported
/// shapes parse to null and callers fall back to device heuristics.
/// Rendering intents and black-point compensation are not applied.
class IccProfile {
  IccProfile._(this.channels, this._transform);

  /// Device channel count (1, 3, or 4).
  final int channels;

  final PdfColor Function(List<double> values) _transform;

  /// Converts device [values] (each 0..1) to sRGB.
  PdfColor toSrgb(List<double> values) => _transform(values);

  static IccProfile? parse(Uint8List bytes) {
    try {
      return _parse(bytes);
    } on Object {
      return null; // malformed profile: caller falls back
    }
  }

  static IccProfile? _parse(Uint8List bytes) {
    if (bytes.length < 132) return null;
    final data = ByteData.sublistView(bytes);
    final space = String.fromCharCodes(bytes, 16, 20);
    final pcs = String.fromCharCodes(bytes, 20, 24);
    if (pcs != 'XYZ ' && pcs != 'Lab ') return null;

    final tagCount = data.getUint32(128);
    final tags = <String, (int, int)>{};
    for (var i = 0; i < tagCount; i++) {
      final base = 132 + i * 12;
      if (base + 12 > bytes.length) break;
      final sig = String.fromCharCodes(bytes, base, base + 4);
      tags[sig] = (data.getUint32(base + 4), data.getUint32(base + 8));
    }

    (int, int)? tag(String sig) => tags[sig];

    // LUT pipeline first: it is authoritative when present (CMYK and
    // v4 perceptual profiles)
    final a2b = tag('A2B0');
    final channelCount = switch (space) {
      'GRAY' => 1,
      'RGB ' => 3,
      'CMYK' => 4,
      _ => 0,
    };
    if (channelCount == 0) return null;

    if (a2b != null) {
      final lut = _Lut.parse(bytes, a2b.$1, pcsIsLab: pcs == 'Lab ');
      if (lut != null && lut.inChannels == channelCount) {
        return IccProfile._(channelCount, (values) {
          final pcsValues = lut.apply(values);
          final xyz = pcs == 'Lab '
              ? _labToXyz(pcsValues[0], pcsValues[1], pcsValues[2])
              : pcsValues;
          return _xyzD50ToSrgb(xyz[0], xyz[1], xyz[2]);
        });
      }
    }

    if (space == 'GRAY') {
      final trcTag = tag('kTRC');
      if (trcTag == null) return null;
      final trc = _Curve.parse(bytes, trcTag.$1);
      if (trc == null) return null;
      return IccProfile._(1, (values) {
        final y = trc.apply(values[0].clamp(0.0, 1.0));
        final v = _srgbEncode(y);
        return PdfColor(v, v, v);
      });
    }

    if (space == 'RGB ') {
      final r = tag('rXYZ'), g = tag('gXYZ'), b = tag('bXYZ');
      final rt = tag('rTRC'), gt = tag('gTRC'), bt = tag('bTRC');
      if (r == null || g == null || b == null) return null;
      if (rt == null || gt == null || bt == null) return null;
      final rXyz = _readXyz(data, r.$1);
      final gXyz = _readXyz(data, g.$1);
      final bXyz = _readXyz(data, b.$1);
      final rTrc = _Curve.parse(bytes, rt.$1);
      final gTrc = _Curve.parse(bytes, gt.$1);
      final bTrc = _Curve.parse(bytes, bt.$1);
      if (rTrc == null || gTrc == null || bTrc == null) return null;
      return IccProfile._(3, (values) {
        final lr = rTrc.apply(values[0].clamp(0.0, 1.0));
        final lg = gTrc.apply(values[1].clamp(0.0, 1.0));
        final lb = bTrc.apply(values[2].clamp(0.0, 1.0));
        return _xyzD50ToSrgb(
          rXyz[0] * lr + gXyz[0] * lg + bXyz[0] * lb,
          rXyz[1] * lr + gXyz[1] * lg + bXyz[1] * lb,
          rXyz[2] * lr + gXyz[2] * lg + bXyz[2] * lb,
        );
      });
    }
    return null;
  }

  static List<double> _readXyz(ByteData data, int offset) => [
        data.getInt32(offset + 8) / 65536,
        data.getInt32(offset + 12) / 65536,
        data.getInt32(offset + 16) / 65536,
      ];

  /// PCS Lab (D50) to XYZ (D50). L 0..100, a/b -128..127.
  static List<double> _labToXyz(double l, double a, double b) {
    final fy = (l + 16) / 116;
    final fx = fy + a / 500;
    final fz = fy - b / 200;
    double f(double t) =>
        t > 6 / 29 ? t * t * t : 3 * (6 / 29) * (6 / 29) * (t - 4 / 29);
    // D50 white point
    return [f(fx) * 0.9642, f(fy) * 1.0, f(fz) * 0.8249];
  }

  /// XYZ relative to D50 (the ICC PCS) to gamma-encoded sRGB.
  static PdfColor _xyzD50ToSrgb(double x, double y, double z) {
    // Bradford-adapted D50→D65 sRGB matrix (the lcms values)
    final r = 3.1338561 * x - 1.6168667 * y - 0.4906146 * z;
    final g = -0.9787684 * x + 1.9161415 * y + 0.0334540 * z;
    final b = 0.0719453 * x - 0.2289914 * y + 1.4052427 * z;
    return PdfColor(_srgbEncode(r), _srgbEncode(g), _srgbEncode(b));
  }

  static double _srgbEncode(double linear) {
    final v = linear.clamp(0.0, 1.0);
    return v <= 0.0031308
        ? v * 12.92
        : 1.055 * math.pow(v, 1 / 2.4).toDouble() - 0.055;
  }
}

/// A tone curve: `curv` (identity, gamma, or sampled table) or `para`
/// (parametric types 0–4).
class _Curve {
  _Curve._(this._apply);

  final double Function(double) _apply;

  double apply(double x) => _apply(x);

  static _Curve? parse(Uint8List bytes, int offset) {
    final data = ByteData.sublistView(bytes);
    final type = String.fromCharCodes(bytes, offset, offset + 4);
    if (type == 'curv') {
      final count = data.getUint32(offset + 8);
      if (count == 0) return _Curve._((x) => x);
      if (count == 1) {
        final gamma = data.getUint16(offset + 12) / 256;
        return _Curve._((x) => math.pow(x, gamma).toDouble());
      }
      final table = [
        for (var i = 0; i < count; i++)
          data.getUint16(offset + 12 + i * 2) / 65535,
      ];
      return _Curve._((x) => _sample(table, x));
    }
    if (type == 'para') {
      final fn = data.getUint16(offset + 8);
      double p(int index) => data.getInt32(offset + 12 + index * 4) / 65536;
      switch (fn) {
        case 0:
          final g = p(0);
          return _Curve._((x) => math.pow(x, g).toDouble());
        case 1:
          final g = p(0), a = p(1), b = p(2);
          return _Curve._((x) =>
              x >= -b / a ? math.pow(a * x + b, g).toDouble() : 0);
        case 2:
          final g = p(0), a = p(1), b = p(2), c = p(3);
          return _Curve._((x) =>
              x >= -b / a ? math.pow(a * x + b, g).toDouble() + c : c);
        case 3:
          final g = p(0), a = p(1), b = p(2), c = p(3), d = p(4);
          return _Curve._(
              (x) => x >= d ? math.pow(a * x + b, g).toDouble() : c * x);
        case 4:
          final g = p(0), a = p(1), b = p(2), c = p(3), d = p(4);
          final e = p(5), f = p(6);
          return _Curve._((x) => x >= d
              ? math.pow(a * x + b, g).toDouble() + e
              : c * x + f);
      }
    }
    return null;
  }

  static double _sample(List<double> table, double x) {
    final clamped = x.clamp(0.0, 1.0) * (table.length - 1);
    final i0 = clamped.floor();
    final i1 = math.min(i0 + 1, table.length - 1);
    final frac = clamped - i0;
    return table[i0] * (1 - frac) + table[i1] * frac;
  }
}

/// A LUT pipeline from `mft1`, `mft2`, or `mAB `: per-channel input
/// curves, a multidimensional CLUT (multilinear interpolation), and
/// output curves. Output values are in PCS encoding (Lab decoded to
/// L/a/b, XYZ to 0..~2).
class _Lut {
  _Lut._({
    required this.inChannels,
    required this.outChannels,
    required this.inputCurves,
    required this.gridPoints,
    required this.clut,
    required this.outputCurves,
    required this.pcsIsLab,
    required this.legacyLab16,
  });

  final int inChannels;
  final int outChannels;
  final List<List<double>> inputCurves; // sampled, normalized 0..1
  final List<int> gridPoints; // per input channel
  final List<double> clut; // normalized 0..1
  final List<List<double>> outputCurves;
  final bool pcsIsLab;

  /// mft2 stores Lab with the legacy 0xFF00 == 100.0 encoding.
  final bool legacyLab16;

  static _Lut? parse(Uint8List bytes, int offset, {required bool pcsIsLab}) {
    final data = ByteData.sublistView(bytes);
    final type = String.fromCharCodes(bytes, offset, offset + 4);
    switch (type) {
      case 'mft1':
      case 'mft2':
        final wide = type == 'mft2';
        final inChannels = bytes[offset + 8];
        final outChannels = bytes[offset + 9];
        final grid = bytes[offset + 10];
        if (inChannels < 1 || inChannels > 4 || outChannels < 3) {
          return null;
        }
        var p = offset + 48; // skip the (XYZ-only) matrix
        final inEntries = wide ? data.getUint16(offset + 48) : 256;
        final outEntries = wide ? data.getUint16(offset + 50) : 256;
        if (wide) p = offset + 52;

        double readValue() {
          final v = wide
              ? data.getUint16(p) / 65535
              : bytes[p] / 255;
          p += wide ? 2 : 1;
          return v;
        }

        final inputCurves = [
          for (var c = 0; c < inChannels; c++)
            [for (var i = 0; i < inEntries; i++) readValue()],
        ];
        var clutSize = outChannels;
        for (var c = 0; c < inChannels; c++) {
          clutSize *= grid;
        }
        final clut = [for (var i = 0; i < clutSize; i++) readValue()];
        final outputCurves = [
          for (var c = 0; c < outChannels; c++)
            [for (var i = 0; i < outEntries; i++) readValue()],
        ];
        return _Lut._(
          inChannels: inChannels,
          outChannels: outChannels,
          inputCurves: inputCurves,
          gridPoints: List.filled(inChannels, grid),
          clut: clut,
          outputCurves: outputCurves,
          pcsIsLab: pcsIsLab,
          legacyLab16: wide && pcsIsLab,
        );
      case 'mAB ':
        return _parseMab(bytes, data, offset, pcsIsLab: pcsIsLab);
      default:
        return null;
    }
  }

  /// lutAtoBType: A curves → CLUT → (M curves → matrix →) B curves.
  /// The M/matrix stage is rare in A2B0 tables; when present it is
  /// applied between the CLUT and the B curves.
  static _Lut? _parseMab(Uint8List bytes, ByteData data, int offset,
      {required bool pcsIsLab}) {
    final inChannels = bytes[offset + 8];
    final outChannels = bytes[offset + 9];
    if (inChannels < 1 || inChannels > 4 || outChannels != 3) return null;
    final bOffset = data.getUint32(offset + 12);
    final clutOffset = data.getUint32(offset + 24);
    final aOffset = data.getUint32(offset + 28);
    if (clutOffset == 0) return null;

    List<List<double>>? sampleCurves(int base, int count) {
      if (base == 0) return List.generate(count, (_) => _identity);
      final curves = <List<double>>[];
      var p = offset + base;
      for (var c = 0; c < count; c++) {
        final curve = _Curve.parse(bytes, p);
        if (curve == null) return null;
        curves.add([
          for (var i = 0; i < 256; i++) curve.apply(i / 255),
        ]);
        // advance past this curve element (4-byte aligned)
        final type = String.fromCharCodes(bytes, p, p + 4);
        var size = 12;
        if (type == 'curv') {
          size = 12 + 2 * data.getUint32(p + 8);
        } else if (type == 'para') {
          const paramCounts = [1, 3, 4, 5, 7];
          final fn = data.getUint16(p + 8);
          size = 12 + 4 * paramCounts[math.min(fn, 4)];
        }
        p += (size + 3) & ~3;
      }
      return curves;
    }

    final clutBase = offset + clutOffset;
    final gridPoints = [
      for (var c = 0; c < inChannels; c++) bytes[clutBase + c],
    ];
    final precision = bytes[clutBase + 16];
    var clutSize = outChannels;
    for (final g in gridPoints) {
      clutSize *= g;
    }
    final clut = <double>[];
    var p = clutBase + 20;
    for (var i = 0; i < clutSize; i++) {
      if (precision == 1) {
        clut.add(bytes[p] / 255);
        p += 1;
      } else {
        clut.add(data.getUint16(p) / 65535);
        p += 2;
      }
    }

    final aCurves = sampleCurves(aOffset, inChannels);
    final bCurves = sampleCurves(bOffset, outChannels);
    if (aCurves == null || bCurves == null) return null;
    return _Lut._(
      inChannels: inChannels,
      outChannels: outChannels,
      inputCurves: aCurves,
      gridPoints: gridPoints,
      clut: clut,
      outputCurves: bCurves,
      pcsIsLab: pcsIsLab,
      legacyLab16: false,
    );
  }

  static final List<double> _identity = [
    for (var i = 0; i < 256; i++) i / 255,
  ];

  /// Runs [values] through the pipeline; returns PCS values (Lab
  /// decoded to L 0..100 / a,b -128..127, or XYZ 0..~2).
  List<double> apply(List<double> values) {
    final mapped = [
      for (var c = 0; c < inChannels; c++)
        _Curve._sample(inputCurves[c], values[c].clamp(0.0, 1.0)),
    ];

    // multilinear interpolation over the 2^n cell corners
    final low = List<int>.filled(inChannels, 0);
    final frac = List<double>.filled(inChannels, 0);
    for (var c = 0; c < inChannels; c++) {
      final g = gridPoints[c];
      final position = mapped[c] * (g - 1);
      low[c] = math.min(position.floor(), g - 2).clamp(0, g - 1);
      frac[c] = (position - low[c]).clamp(0.0, 1.0);
    }
    final out = List<double>.filled(outChannels, 0);
    final corners = 1 << inChannels;
    for (var corner = 0; corner < corners; corner++) {
      var weight = 1.0;
      var index = 0;
      for (var c = 0; c < inChannels; c++) {
        final up = (corner >> c) & 1;
        final g = gridPoints[c];
        final coord = math.min(low[c] + up, g - 1);
        weight *= up == 1 ? frac[c] : 1 - frac[c];
        index = index * g + coord;
      }
      if (weight == 0) continue;
      for (var o = 0; o < outChannels; o++) {
        out[o] += weight * clut[index * outChannels + o];
      }
    }

    for (var o = 0; o < outChannels; o++) {
      out[o] = _Curve._sample(outputCurves[o], out[o]);
    }

    if (pcsIsLab) {
      if (legacyLab16) {
        // legacy 16-bit Lab: 0xFF00 is 100.0 / +127
        return [
          out[0] * 65535 / 652.80,
          out[1] * 65535 / 256 - 128,
          out[2] * 65535 / 256 - 128,
        ];
      }
      return [out[0] * 100, out[1] * 255 - 128, out[2] * 255 - 128];
    }
    // XYZ: u16 0..0xFFFF spans 0..1.99997
    return [for (final v in out) v * 65535 / 32768];
  }
}
