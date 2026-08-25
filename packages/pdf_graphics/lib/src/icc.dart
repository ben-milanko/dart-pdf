import 'dart:math' as math;
import 'dart:typed_data';

import 'color.dart';

/// PDF/ICC rendering intents, in the ICC transform-table order.
enum PdfRenderingIntent {
  perceptual,
  relativeColorimetric,
  saturation,
  absoluteColorimetric,
}

/// An ICC profile reduced to what rendering needs: a transform from
/// device components to sRGB.
///
/// Coverage: gray TRC profiles, matrix/TRC RGB profiles (v2 and v4,
/// `curv` and `para` curves), and LUT profiles via A2B0 (`mft1`, `mft2`,
/// and `mAB ` pipelines) with XYZ or Lab PCS - which spans sRGB-like,
/// wide-gamut RGB, and the common CMYK press profiles. Unsupported
/// shapes parse to null and callers fall back to device heuristics.
class IccProfile {
  IccProfile._(this.channels, this._transform,
      {this.isSrgb = false,
      this.rgb8Transform,
      this.mediaWhitePoint = const [0.9642, 1.0, 0.8249],
      this.mediaBlackPoint = const [0.0, 0.0, 0.0],
      List<double> Function(List<double>, PdfRenderingIntent)? pcsTransform,
      List<double>? Function(List<double>, PdfRenderingIntent)? deviceFromPcs})
      : _pcsTransform = pcsTransform,
        _deviceFromPcs = deviceFromPcs;

  /// Device channel count (1, 3, or 4).
  final int channels;

  /// ICC `wtpt`, decoded as XYZ. Defaults to the D50 PCS illuminant.
  final List<double> mediaWhitePoint;

  /// ICC `bkpt`, decoded as XYZ. Defaults to ideal black when omitted.
  final List<double> mediaBlackPoint;

  final PdfColor Function(List<double> values) _transform;
  final List<double> Function(List<double>, PdfRenderingIntent)? _pcsTransform;
  final List<double>? Function(List<double>, PdfRenderingIntent)?
      _deviceFromPcs;

  /// True when this profile's transform is the identity at 8-bit precision
  /// (#531, PDFium's DetectSRGB shape, decided behaviourally): applying it
  /// and re-encoding changes no 8-bit component by more than 1. sRGB-tagged
  /// ICCBased RGB is the single most common profile in scanned/photo PDFs,
  /// so consumers skip the per-pixel transform entirely when this is set.
  /// Only claimed for matrix/TRC and gray-TRC profiles, where the per-channel
  /// probe set below is mathematically sufficient; LUT pipelines never claim
  /// it.
  final bool isSrgb;

  /// Allocation-free 8-bit RGB fast path for matrix/TRC profiles (#531):
  /// reads `rgb[s..s+2]`, writes sRGB into `out[o..o+2]` - no per-pixel
  /// list or colour allocation, TRC linearisation and gamma re-encode via
  /// lookup tables. Null for LUT-pipeline and non-RGB profiles, where the
  /// general [toSrgb] path applies.
  final void Function(Uint8List rgb, int s, Uint8List out, int o)?
      rgb8Transform;

  /// Converts device [values] (each 0..1) to sRGB.
  PdfColor toSrgb(List<double> values,
      {PdfRenderingIntent intent = PdfRenderingIntent.perceptual}) {
    final pcs = _pcsTransform?.call(values, intent);
    return pcs == null
        ? _transform(values)
        : _xyzD50ToSrgb(pcs[0], pcs[1], pcs[2]);
  }

  /// Converts device components to the profile-connection space, normalized
  /// here as XYZ D50. Falls back through sRGB for legacy/unsupported profiles.
  List<double> toPcs(List<double> values,
      {PdfRenderingIntent intent = PdfRenderingIntent.perceptual}) {
    final pcs = _pcsTransform?.call(values, intent);
    if (pcs != null) return pcs;
    return _srgbToXyzD50(_transform(values));
  }

  /// Converts XYZ D50 PCS values into this profile's device components using
  /// its B2A intent table. Null when the profile supplies no usable reverse
  /// table; callers may use a bounded numerical inverse then.
  List<double>? fromPcs(List<double> xyz,
          {PdfRenderingIntent intent = PdfRenderingIntent.perceptual}) =>
      _deviceFromPcs?.call(xyz, intent);

  /// Source-side black point in the relative XYZ PCS. RGB/gray black is the
  /// zero device tuple; for subtractive profiles it is the darkest all-ink
  /// endpoint. This mirrors the endpoint used by ICC BPC black detection.
  List<double> sourceBlackPoint(
      {PdfRenderingIntent intent = PdfRenderingIntent.relativeColorimetric}) {
    final black = List<double>.filled(channels, channels == 4 ? 1.0 : 0.0);
    return List<double>.unmodifiable(toPcs(black, intent: intent));
  }

  /// Destination-side printable black in the relative XYZ PCS.
  ///
  /// Output profiles define this by round-tripping PCS black through B2A and
  /// A2B, rather than by trusting the often-absent/zero `bkpt` tag. This is
  /// the ICC CMM behavior relevant to press profiles.
  List<double> destinationBlackPoint(
      {PdfRenderingIntent intent = PdfRenderingIntent.relativeColorimetric}) {
    final device = fromPcs(const [0.0, 0.0, 0.0], intent: intent);
    return device == null
        ? sourceBlackPoint(intent: intent)
        : List<double>.unmodifiable(toPcs(device, intent: intent));
  }

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

    final whiteTag = tag('wtpt');
    final blackTag = tag('bkpt');
    final whitePoint = whiteTag == null
        ? const <double>[0.9642, 1.0, 0.8249]
        : List<double>.unmodifiable(_readXyz(data, whiteTag.$1));
    final blackPoint = blackTag == null
        ? const <double>[0.0, 0.0, 0.0]
        : List<double>.unmodifiable(_readXyz(data, blackTag.$1));

    // LUT pipelines are intent-specific. A2B0/1/2 are respectively
    // perceptual, colorimetric and saturation; B2A0/1/2 are their reverse
    // destination transforms. Falling back to table 0 is required for many
    // v2 profiles that expose only a perceptual transform.
    final channelCount = switch (space) {
      'GRAY' => 1,
      'RGB ' => 3,
      'CMYK' => 4,
      _ => 0,
    };
    if (channelCount == 0) return null;

    final a2b = <int, _Lut>{};
    final b2a = <int, _Lut>{};
    for (var intent = 0; intent < 3; intent++) {
      final forward = tag('A2B$intent');
      if (forward != null) {
        final lut = _Lut.parse(bytes, forward.$1, pcsIsLab: pcs == 'Lab ');
        if (lut != null && lut.inChannels == channelCount) a2b[intent] = lut;
      }
      final reverse = tag('B2A$intent');
      if (reverse != null) {
        final lut = _Lut.parse(bytes, reverse.$1,
            pcsIsLab: false, inputPcsIsLab: pcs == 'Lab ');
        if (lut != null &&
            lut.inChannels == 3 &&
            lut.outChannels == channelCount) {
          b2a[intent] = lut;
        }
      }
    }
    if (a2b.isNotEmpty) {
      int intentIndex(PdfRenderingIntent intent) => switch (intent) {
            PdfRenderingIntent.perceptual => 0,
            PdfRenderingIntent.relativeColorimetric ||
            PdfRenderingIntent.absoluteColorimetric =>
              1,
            PdfRenderingIntent.saturation => 2,
          };
      _Lut forward(PdfRenderingIntent intent) =>
          a2b[intentIndex(intent)] ?? a2b[0] ?? a2b.values.first;
      List<double> toXyz(List<double> values, PdfRenderingIntent intent) {
        final pcsValues = forward(intent).apply(values);
        return pcs == 'Lab '
            ? _labToXyz(pcsValues[0], pcsValues[1], pcsValues[2])
            : [pcsValues[0], pcsValues[1], pcsValues[2]];
      }

      List<double>? fromXyz(List<double> xyz, PdfRenderingIntent intent) {
        final lut = b2a[intentIndex(intent)] ?? b2a[0];
        if (lut == null) return null;
        final encoded = pcs == 'Lab ' ? _xyzToLab(xyz[0], xyz[1], xyz[2]) : xyz;
        return lut.applyDevice(encoded, pcsIsLab: pcs == 'Lab ');
      }

      return IccProfile._(
        channelCount,
        (values) {
          final xyz = toXyz(values, PdfRenderingIntent.perceptual);
          return _xyzD50ToSrgb(xyz[0], xyz[1], xyz[2]);
        },
        pcsTransform: toXyz,
        deviceFromPcs: b2a.isEmpty ? null : fromXyz,
        mediaWhitePoint: whitePoint,
        mediaBlackPoint: blackPoint,
      );
    }

    if (space == 'GRAY') {
      final trcTag = tag('kTRC');
      if (trcTag == null) return null;
      final trc = _Curve.parse(bytes, trcTag.$1);
      if (trc == null) return null;
      PdfColor transform(List<double> values) {
        final y = trc.apply(values[0].clamp(0.0, 1.0));
        final v = _srgbEncode(y);
        return PdfColor(v, v, v);
      }

      List<double> pcsTransform(
          List<double> values, PdfRenderingIntent intent) {
        final y = trc.apply(values[0].clamp(0.0, 1.0));
        return [y * 0.9642, y, y * 0.8249];
      }

      // Behavioural identity probe: for a single-channel TRC profile the
      // sampled points are sufficient - if decode+re-encode moves no 8-bit
      // value by more than 1, the transform is a no-op at our precision.
      var identity = true;
      for (var v = 0; v <= 255 && identity; v += 5) {
        final out = transform([v / 255]).red * 255;
        if ((out - v).abs() > 1) identity = false;
      }
      return IccProfile._(1, transform,
          isSrgb: identity,
          pcsTransform: pcsTransform,
          mediaWhitePoint: whitePoint,
          mediaBlackPoint: blackPoint);
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
      PdfColor transform(List<double> values) {
        final lr = rTrc.apply(values[0].clamp(0.0, 1.0));
        final lg = gTrc.apply(values[1].clamp(0.0, 1.0));
        final lb = bTrc.apply(values[2].clamp(0.0, 1.0));
        return _xyzD50ToSrgb(
          rXyz[0] * lr + gXyz[0] * lg + bXyz[0] * lb,
          rXyz[1] * lr + gXyz[1] * lg + bXyz[1] * lb,
          rXyz[2] * lr + gXyz[2] * lg + bXyz[2] * lb,
        );
      }

      List<double> pcsTransform(
          List<double> values, PdfRenderingIntent intent) {
        final lr = rTrc.apply(values[0].clamp(0.0, 1.0));
        final lg = gTrc.apply(values[1].clamp(0.0, 1.0));
        final lb = bTrc.apply(values[2].clamp(0.0, 1.0));
        return [
          rXyz[0] * lr + gXyz[0] * lg + bXyz[0] * lb,
          rXyz[1] * lr + gXyz[1] * lg + bXyz[1] * lb,
          rXyz[2] * lr + gXyz[2] * lg + bXyz[2] * lb,
        ];
      }

      // Behavioural identity probe. A matrix/TRC transform is linear between
      // the per-channel curves, so single-channel sweeps plus white decide
      // it: if no probed 8-bit component moves by more than 1, the profile
      // is sRGB-equivalent at our precision (covers the real sRGB profile
      // and its many byte-different re-issues; a gamma-2.2 or wide-gamut
      // profile fails the probe and keeps the transform).
      var identity = true;
      for (var v = 0; v <= 255 && identity; v += 5) {
        final x = v / 255;
        final r = transform([x, 0, 0]);
        final g = transform([0, x, 0]);
        final b = transform([0, 0, x]);
        final w = transform([x, x, x]);
        if ((r.red * 255 - v).abs() > 1 ||
            r.green * 255 > 1.5 ||
            r.blue * 255 > 1.5 ||
            (g.green * 255 - v).abs() > 1 ||
            g.red * 255 > 1.5 ||
            g.blue * 255 > 1.5 ||
            (b.blue * 255 - v).abs() > 1 ||
            b.red * 255 > 1.5 ||
            b.green * 255 > 1.5 ||
            (w.red * 255 - v).abs() > 1 ||
            (w.green * 255 - v).abs() > 1 ||
            (w.blue * 255 - v).abs() > 1) {
          identity = false;
        }
      }

      // 8-bit fast path: linearise each channel through a 256-entry table,
      // one 3x3 matrix multiply, and re-encode through a 4096-entry gamma
      // table - no per-pixel allocation, no pow().
      final linR = Float64List(256);
      final linG = Float64List(256);
      final linB = Float64List(256);
      for (var v = 0; v < 256; v++) {
        linR[v] = rTrc.apply(v / 255);
        linG[v] = gTrc.apply(v / 255);
        linB[v] = bTrc.apply(v / 255);
      }
      final encode = _srgbEncodeLut;
      void rgb8(Uint8List rgb, int s, Uint8List out, int o) {
        final lr = linR[rgb[s]], lg = linG[rgb[s + 1]], lb = linB[rgb[s + 2]];
        final x = rXyz[0] * lr + gXyz[0] * lg + bXyz[0] * lb;
        final y = rXyz[1] * lr + gXyz[1] * lg + bXyz[1] * lb;
        final z = rXyz[2] * lr + gXyz[2] * lg + bXyz[2] * lb;
        final r = 3.1338561 * x - 1.6168667 * y - 0.4906146 * z;
        final g = -0.9787684 * x + 1.9161415 * y + 0.0334540 * z;
        final b = 0.0719453 * x - 0.2289914 * y + 1.4052427 * z;
        out[o] = encode[(r.clamp(0.0, 1.0) * 4095).round()];
        out[o + 1] = encode[(g.clamp(0.0, 1.0) * 4095).round()];
        out[o + 2] = encode[(b.clamp(0.0, 1.0) * 4095).round()];
      }

      return IccProfile._(3, transform,
          isSrgb: identity,
          rgb8Transform: identity ? null : rgb8,
          pcsTransform: pcsTransform,
          mediaWhitePoint: whitePoint,
          mediaBlackPoint: blackPoint);
    }
    return null;
  }

  /// Linear-light (0..1 in 1/4095 steps) to 8-bit gamma-encoded sRGB.
  static final Uint8List _srgbEncodeLut = (() {
    final lut = Uint8List(4096);
    for (var i = 0; i < 4096; i++) {
      lut[i] = (_srgbEncode(i / 4095) * 255).round();
    }
    return lut;
  })();

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

  /// XYZ D50 to PCS Lab (L 0..100, a/b nominally -128..127).
  static List<double> _xyzToLab(double x, double y, double z) {
    double f(double t) => t > math.pow(6 / 29, 3)
        ? math.pow(t, 1 / 3).toDouble()
        : t / (3 * math.pow(6 / 29, 2)) + 4 / 29;
    final fx = f(x / 0.9642), fy = f(y), fz = f(z / 0.8249);
    return [116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)];
  }

  /// Gamma-encoded sRGB to the ICC XYZ D50 connection space.
  static List<double> _srgbToXyzD50(PdfColor color) {
    double decode(double value) => value <= 0.04045
        ? value / 12.92
        : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
    final r = decode(color.red),
        g = decode(color.green),
        b = decode(color.blue);
    // Inverse of the Bradford-adapted D50→sRGB matrix below.
    return [
      0.4360747 * r + 0.3850649 * g + 0.1430804 * b,
      0.2225045 * r + 0.7168786 * g + 0.0606169 * b,
      0.0139322 * r + 0.0971045 * g + 0.7141733 * b,
    ];
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
          return _Curve._(
              (x) => x >= -b / a ? math.pow(a * x + b, g).toDouble() : 0);
        case 2:
          final g = p(0), a = p(1), b = p(2), c = p(3);
          return _Curve._(
              (x) => x >= -b / a ? math.pow(a * x + b, g).toDouble() + c : c);
        case 3:
          final g = p(0), a = p(1), b = p(2), c = p(3), d = p(4);
          return _Curve._(
              (x) => x >= d ? math.pow(a * x + b, g).toDouble() : c * x);
        case 4:
          final g = p(0), a = p(1), b = p(2), c = p(3), d = p(4);
          final e = p(5), f = p(6);
          return _Curve._((x) =>
              x >= d ? math.pow(a * x + b, g).toDouble() + e : c * x + f);
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
    required this.inputLegacyLab16,
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

  /// A v2 `mft2` B2A table receives PCS Lab in the legacy 0xFF00 encoding,
  /// even though its output is device components rather than Lab.
  final bool inputLegacyLab16;

  /// Per-call scratch, allocated once per profile rather than per pixel.
  /// [apply] runs on every pixel of an ICC-managed image - a CMYK press
  /// profile made it the single most expensive step in a record serialize
  /// (issue #451) - and it used to allocate four lists each time. It reads
  /// its input and hands its output straight to the caller's conversion, so
  /// one set of buffers serves the whole image. Not re-entrant, which
  /// [apply]'s straight-line body guarantees.
  late final Float64List _mapped = Float64List(inChannels);
  late final Int32List _low = Int32List(inChannels);
  late final Float64List _frac = Float64List(inChannels);
  late final Float64List _out = Float64List(outChannels);
  late final Float64List _tetraLow = Float64List(outChannels);
  late final Float64List _tetraHigh = Float64List(outChannels);
  // The Lab branch writes three components regardless of outChannels.
  late final Float64List _pcs = Float64List(math.max(outChannels, 3));

  static _Lut? parse(Uint8List bytes, int offset,
      {required bool pcsIsLab, bool inputPcsIsLab = false}) {
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
          final v = wide ? data.getUint16(p) / 65535 : bytes[p] / 255;
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
          inputLegacyLab16: wide && inputPcsIsLab,
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
      inputLegacyLab16: false,
    );
  }

  static final List<double> _identity = [
    for (var i = 0; i < 256; i++) i / 255,
  ];

  /// Runs [values] through the pipeline; returns PCS values (Lab
  /// decoded to L 0..100 / a,b -128..127, or XYZ 0..~2).
  List<double> apply(List<double> values) {
    final mapped = _mapped;
    final low = _low;
    final frac = _frac;
    final out = _out;
    for (var c = 0; c < inChannels; c++) {
      mapped[c] = _Curve._sample(inputCurves[c], values[c].clamp(0.0, 1.0));
    }

    // ICC leaves the CLUT interpolation algorithm to the CMM. Use the
    // de-facto reference shape used by LittleCMS: tetrahedral interpolation
    // for three inputs, and for CMYK two 3-D tetrahedral slices followed by a
    // linear interpolation along the first component. Plain 4-D multilinear
    // interpolation visibly misses the paired source/output colors in GWG130.
    if (inChannels == 3) {
      _tetrahedral(mapped, 0, 0, out);
    } else if (inChannels == 4) {
      final grid = gridPoints[0];
      final position = mapped[0] * (grid - 1);
      final lower = math.min(position.floor(), grid - 2).clamp(0, grid - 1);
      final upper = math.min(lower + 1, grid - 1);
      final amount = (position - lower).clamp(0.0, 1.0);
      _tetrahedral(mapped, 1, lower, _tetraLow);
      _tetrahedral(mapped, 1, upper, _tetraHigh);
      for (var o = 0; o < outChannels; o++) {
        out[o] = _tetraLow[o] + (_tetraHigh[o] - _tetraLow[o]) * amount;
      }
    } else {
      _multilinear(mapped, low, frac, out);
    }

    for (var o = 0; o < outChannels; o++) {
      out[o] = _Curve._sample(outputCurves[o], out[o]);
    }

    final pcs = _pcs;
    if (pcsIsLab) {
      if (legacyLab16) {
        // legacy 16-bit Lab: 0xFF00 is 100.0 / +127
        pcs[0] = out[0] * 65535 / 652.80;
        pcs[1] = out[1] * 65535 / 256 - 128;
        pcs[2] = out[2] * 65535 / 256 - 128;
        return pcs;
      }
      pcs[0] = out[0] * 100;
      pcs[1] = out[1] * 255 - 128;
      pcs[2] = out[2] * 255 - 128;
      return pcs;
    }
    // XYZ: u16 0..0xFFFF spans 0..1.99997
    for (var o = 0; o < outChannels; o++) {
      pcs[o] = out[o] * 65535 / 32768;
    }
    return pcs;
  }

  void _multilinear(
      Float64List mapped, Int32List low, Float64List frac, Float64List out) {
    for (var c = 0; c < inChannels; c++) {
      final g = gridPoints[c];
      final position = mapped[c] * (g - 1);
      low[c] = math.min(position.floor(), g - 2).clamp(0, g - 1);
      frac[c] = (position - low[c]).clamp(0.0, 1.0);
    }
    for (var o = 0; o < outChannels; o++) {
      out[o] = 0;
    }
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
  }

  /// Tetrahedral interpolation of three adjacent CLUT dimensions. For a
  /// four-channel table [slice] selects the already-discretized first input;
  /// for a three-channel table it is ignored.
  void _tetrahedral(
      Float64List mapped, int start, int slice, Float64List result) {
    final gx = gridPoints[start];
    final gy = gridPoints[start + 1];
    final gz = gridPoints[start + 2];
    final px = mapped[start] * (gx - 1);
    final py = mapped[start + 1] * (gy - 1);
    final pz = mapped[start + 2] * (gz - 1);
    final x0 = math.min(px.floor(), gx - 2).clamp(0, gx - 1);
    final y0 = math.min(py.floor(), gy - 2).clamp(0, gy - 1);
    final z0 = math.min(pz.floor(), gz - 2).clamp(0, gz - 1);
    final x1 = math.min(x0 + 1, gx - 1);
    final y1 = math.min(y0 + 1, gy - 1);
    final z1 = math.min(z0 + 1, gz - 1);
    final rx = (px - x0).clamp(0.0, 1.0);
    final ry = (py - y0).clamp(0.0, 1.0);
    final rz = (pz - z0).clamp(0.0, 1.0);

    int base(int x, int y, int z) => inChannels == 3
        ? ((x * gy + y) * gz + z) * outChannels
        : (((slice * gx + x) * gy + y) * gz + z) * outChannels;

    final i000 = base(x0, y0, z0);
    final i100 = base(x1, y0, z0);
    final i010 = base(x0, y1, z0);
    final i001 = base(x0, y0, z1);
    final i110 = base(x1, y1, z0);
    final i101 = base(x1, y0, z1);
    final i011 = base(x0, y1, z1);
    final i111 = base(x1, y1, z1);

    for (var o = 0; o < outChannels; o++) {
      final c0 = clut[i000 + o];
      late final double c1, c2, c3;
      if (rx >= ry && ry >= rz) {
        c1 = clut[i100 + o] - c0;
        c2 = clut[i110 + o] - clut[i100 + o];
        c3 = clut[i111 + o] - clut[i110 + o];
      } else if (rx >= rz && rz >= ry) {
        c1 = clut[i100 + o] - c0;
        c2 = clut[i111 + o] - clut[i101 + o];
        c3 = clut[i101 + o] - clut[i100 + o];
      } else if (rz >= rx && rx >= ry) {
        c1 = clut[i101 + o] - clut[i001 + o];
        c2 = clut[i111 + o] - clut[i101 + o];
        c3 = clut[i001 + o] - c0;
      } else if (ry >= rx && rx >= rz) {
        c1 = clut[i110 + o] - clut[i010 + o];
        c2 = clut[i010 + o] - c0;
        c3 = clut[i111 + o] - clut[i110 + o];
      } else if (ry >= rz && rz >= rx) {
        c1 = clut[i111 + o] - clut[i011 + o];
        c2 = clut[i010 + o] - c0;
        c3 = clut[i011 + o] - clut[i010 + o];
      } else {
        c1 = clut[i111 + o] - clut[i011 + o];
        c2 = clut[i011 + o] - clut[i001 + o];
        c3 = clut[i001 + o] - c0;
      }
      result[o] = c0 + c1 * rx + c2 * ry + c3 * rz;
    }
  }

  /// Runs a PCS→device (B2A) LUT. [pcsValues] are decoded Lab or XYZ values;
  /// the LUT input uses ICC's encoded representation and its output is plain
  /// normalized device components.
  List<double> applyDevice(List<double> pcsValues, {required bool pcsIsLab}) {
    final encoded = pcsIsLab
        ? inputLegacyLab16
            ? [
                (pcsValues[0] * 652.80 / 65535).clamp(0.0, 1.0).toDouble(),
                ((pcsValues[1] + 128) * 256 / 65535).clamp(0.0, 1.0).toDouble(),
                ((pcsValues[2] + 128) * 256 / 65535).clamp(0.0, 1.0).toDouble(),
              ]
            : [
                (pcsValues[0] / 100).clamp(0.0, 1.0).toDouble(),
                ((pcsValues[1] + 128) / 255).clamp(0.0, 1.0).toDouble(),
                ((pcsValues[2] + 128) / 255).clamp(0.0, 1.0).toDouble(),
              ]
        : [
            for (var i = 0; i < 3; i++)
              (pcsValues[i] * 32768 / 65535).clamp(0.0, 1.0).toDouble(),
          ];
    // B2A LUTs were parsed with pcsIsLab=false so [apply] leaves their device
    // outputs in the XYZ numeric scaling. Undo that final presentation scale;
    // the interpolation/curve stages themselves are shared exactly.
    final scaled = apply(encoded);
    return [
      for (var i = 0; i < outChannels; i++)
        (scaled[i] * 32768 / 65535).clamp(0.0, 1.0).toDouble(),
    ];
  }
}
