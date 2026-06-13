import 'dart:math' as math;

import 'package:pdf_cos/pdf_cos.dart';

import 'document.dart';

/// The unsigned shoelace area of the polygon through [points], in the
/// same squared units as the point coordinates. Shared by area
/// measurements and [PdfAnnotation.measurementText].
double pdfShoelaceArea(List<(double, double)> points) {
  if (points.length < 3) return 0;
  var sum = 0.0;
  for (var i = 0; i < points.length; i++) {
    final (x0, y0) = points[i];
    final (x1, y1) = points[(i + 1) % points.length];
    sum += x0 * y1 - x1 * y0;
  }
  return sum.abs() / 2;
}

/// A number-format dictionary (§12.9.2, Table 22.7): how one component of
/// a measured value is converted and displayed.
///
/// A value `v` (expressed in the units this format consumes) is shown as
/// `v × [conversion]`, rounded per [fractionFormat]/[precision], with the
/// [unit] label placed before or after the number ([labelPosition]).
///
/// The display always strips trailing fractional zeros (and a dangling
/// decimal separator), so the default `1 in = 20 ft` calibration shows
/// `60 ft` rather than `60.00 ft` — the product choice the measurement
/// tools rely on.
class PdfNumberFormat {
  const PdfNumberFormat({
    required this.unit,
    this.conversion = 1,
    this.precision = 100,
    this.fractionFormat = 'D',
    this.decimalSeparator = '.',
    this.thousandsSeparator = ',',
    this.prefix = '',
    this.suffix = '',
    this.labelPosition = 'S',
  });

  /// /U — the unit label ('ft', 'm', 'ft²', ...).
  final String unit;

  /// /C — the factor a value is multiplied by to reach [unit].
  final double conversion;

  /// /D — the rounding granularity: the value is shown to the nearest
  /// `1 / precision` (so 100 → two decimals, 1 → whole numbers) for the
  /// decimal formats, or used as the denominator for [fractionFormat] 'F'.
  final int precision;

  /// /F — 'D' decimal (default), 'F' fraction with denominator [precision],
  /// 'R' round, 'T' truncate.
  final String fractionFormat;

  /// /RD — the decimal separator.
  final String decimalSeparator;

  /// /RT — the thousands separator.
  final String thousandsSeparator;

  /// /PS — text concatenated to the start of the display.
  final String prefix;

  /// /SS — text concatenated to the end of the display.
  final String suffix;

  /// /O — 'S' to place [unit] after the number (default), 'P' before.
  final String labelPosition;

  /// Formats [value] (in this format's input units) as a display string.
  String format(double value) {
    final scaled = value * conversion;
    final number = _formatNumber(scaled);
    final u = unit;
    final body = u.isEmpty
        ? number
        : labelPosition == 'P'
            ? '$u $number'
            : '$number $u';
    return '$prefix$body$suffix';
  }

  String _formatNumber(double scaled) {
    if (fractionFormat == 'F' && precision > 0) return _formatFraction(scaled);

    final step = precision > 0 ? 1 / precision : 1;
    final double rounded;
    if (fractionFormat == 'T') {
      rounded = (scaled / step).truncateToDouble() * step;
    } else {
      rounded = (scaled / step).roundToDouble() * step;
    }
    final decimals = precision <= 1
        ? 0
        : math.max(0, (math.log(precision) / math.ln10).round());
    var text = rounded.toStringAsFixed(decimals);
    if (text.contains('.')) {
      text = text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    }
    return _applySeparators(text);
  }

  String _formatFraction(double scaled) {
    final negative = scaled < 0;
    final magnitude = scaled.abs();
    final whole = magnitude.floor();
    var numerator = ((magnitude - whole) * precision).round();
    var denominator = precision;
    if (numerator == denominator) {
      return _applySeparators('${negative ? '-' : ''}${whole + 1}');
    }
    if (numerator == 0) {
      return _applySeparators('${negative ? '-' : ''}$whole');
    }
    // reduce the fraction to lowest terms
    final divisor = _gcd(numerator, denominator);
    numerator ~/= divisor;
    denominator ~/= divisor;
    final sign = negative ? '-' : '';
    return whole == 0
        ? '$sign$numerator/$denominator'
        : '$sign${_applySeparators('$whole')} $numerator/$denominator';
  }

  String _applySeparators(String text) {
    var sign = '';
    var body = text;
    if (body.startsWith('-')) {
      sign = '-';
      body = body.substring(1);
    }
    final dot = body.indexOf('.');
    var intPart = dot < 0 ? body : body.substring(0, dot);
    final fracPart = dot < 0 ? '' : body.substring(dot + 1);
    if (thousandsSeparator.isNotEmpty && intPart.length > 3) {
      final buffer = StringBuffer();
      final lead = intPart.length % 3;
      if (lead > 0) buffer.write(intPart.substring(0, lead));
      for (var i = lead; i < intPart.length; i += 3) {
        if (buffer.isNotEmpty) buffer.write(thousandsSeparator);
        buffer.write(intPart.substring(i, i + 3));
      }
      intPart = buffer.toString();
    }
    return fracPart.isEmpty
        ? '$sign$intPart'
        : '$sign$intPart$decimalSeparator$fracPart';
  }

  static int _gcd(int a, int b) {
    while (b != 0) {
      final t = b;
      b = a % b;
      a = t;
    }
    return a == 0 ? 1 : a;
  }

  /// Parses a /NumberFormat dictionary; returns null for non-dictionaries
  /// or a dictionary with no usable /U.
  static PdfNumberFormat? fromDict(PdfDocument document, CosObject? raw) {
    final cos = document.cos;
    final dict = cos.resolve(raw);
    if (dict is! CosDictionary) return null;
    final u = cos.resolve(dict['U']);
    final unit = u is CosString ? u.text : '';

    double number(String key, double fallback) {
      final v = cos.resolve(dict[key]);
      if (v is CosInteger) return v.value.toDouble();
      if (v is CosReal) return v.value;
      return fallback;
    }

    String text(String key, String fallback) {
      final v = cos.resolve(dict[key]);
      return v is CosString ? v.text : fallback;
    }

    String nameOf(String key, String fallback) {
      final v = cos.resolve(dict[key]);
      return v is CosName ? v.value : fallback;
    }

    return PdfNumberFormat(
      unit: unit,
      conversion: number('C', 1),
      precision: number('D', 100).round(),
      fractionFormat: nameOf('F', 'D'),
      decimalSeparator: text('RD', '.'),
      thousandsSeparator: text('RT', ','),
      prefix: text('PS', ''),
      suffix: text('SS', ''),
      labelPosition: nameOf('O', 'S'),
    );
  }

  CosDictionary toCosDictionary() {
    final dict = CosDictionary({
      'Type': const CosName('NumberFormat'),
      'U': CosString.fromText(unit),
      'C': CosReal(conversion),
      'D': CosInteger(precision),
      'F': CosName(fractionFormat),
    });
    if (decimalSeparator != '.') {
      dict['RD'] = CosString.fromText(decimalSeparator);
    }
    if (thousandsSeparator != ',') {
      dict['RT'] = CosString.fromText(thousandsSeparator);
    }
    if (prefix.isNotEmpty) dict['PS'] = CosString.fromText(prefix);
    if (suffix.isNotEmpty) dict['SS'] = CosString.fromText(suffix);
    if (labelPosition != 'S') dict['O'] = CosName(labelPosition);
    return dict;
  }
}

/// A measurement dictionary (§12.9.2): the scale and unit formats that
/// turn a measurement annotation's page-space geometry into a real-world
/// distance, perimeter, or area.
///
/// The conversion chain mirrors Acrobat's: a length in page points is
/// multiplied by the [x] format's factor to reach the measured unit, then
/// the [distance] format renders it; an area is multiplied by the [x] and
/// [y] factors before the [area] format renders it.
class PdfMeasure {
  const PdfMeasure({
    required this.ratio,
    required this.x,
    required this.distance,
    required this.area,
    this.y,
    this.angle,
    this.subtype = 'RL',
  });

  /// Builds a rectilinear scale: [unitsPerPoint] real-world units per PDF
  /// point along each axis, labelled [unitLabel] (and [areaUnitLabel] for
  /// areas, defaulting to `unitLabel²`).
  factory PdfMeasure.scale({
    required double unitsPerPoint,
    required String unitLabel,
    String? areaUnitLabel,
    int precision = 100,
    String? ratioLabel,
  }) {
    final areaUnit = areaUnitLabel ?? '$unitLabel²';
    return PdfMeasure(
      ratio: ratioLabel ?? _defaultRatioLabel(unitsPerPoint, unitLabel),
      x: [PdfNumberFormat(unit: unitLabel, conversion: unitsPerPoint, precision: precision)],
      distance: [PdfNumberFormat(unit: unitLabel, precision: precision)],
      area: [PdfNumberFormat(unit: areaUnit, precision: precision)],
    );
  }

  static String _defaultRatioLabel(double unitsPerPoint, String unitLabel) {
    // express as "1 in = N unit" (72 points = 1 inch)
    final perInch = PdfNumberFormat(unit: '', precision: 100).format(unitsPerPoint * 72);
    return '1 in = $perInch $unitLabel';
  }

  /// /Subtype — 'RL' (rectilinear) is the only kind written here.
  final String subtype;

  /// /R — the user-facing ratio label (e.g. `1 in = 20 ft`).
  final String ratio;

  /// /X — the number formats converting an x-axis page distance to the
  /// measured unit. The first entry's [PdfNumberFormat.conversion] is the
  /// per-point scale factor.
  final List<PdfNumberFormat> x;

  /// /Y — the y-axis formats; falls back to [x] when absent.
  final List<PdfNumberFormat>? y;

  /// /D — the formats rendering a distance.
  final List<PdfNumberFormat> distance;

  /// /A — the formats rendering an area.
  final List<PdfNumberFormat> area;

  /// /T — the formats rendering an angle, if present.
  final List<PdfNumberFormat>? angle;

  /// The per-point distance scale factor: real units per page point.
  double get scaleFactor => x.isNotEmpty ? x.first.conversion : 1;

  double get _xFactor => x.isNotEmpty ? x.first.conversion : 1;
  double get _yFactor =>
      (y != null && y!.isNotEmpty) ? y!.first.conversion : _xFactor;

  /// Formats a distance whose raw page-space length is [pointLength].
  String formatDistance(double pointLength) =>
      _walk(distance, pointLength * _xFactor);

  /// Formats an area whose raw page-space value is [pointArea] (in
  /// points²).
  String formatArea(double pointArea) =>
      _walk(area, pointArea * _xFactor * _yFactor);

  static String _walk(List<PdfNumberFormat> formats, double value) {
    if (formats.isEmpty) {
      return PdfNumberFormat(unit: '').format(value);
    }
    if (formats.length == 1) return formats.first.format(value);
    // a cascade of sub-units (feet then inches): each non-final unit shows
    // its whole part, the remainder feeds the next
    final parts = <String>[];
    var remaining = value;
    for (var i = 0; i < formats.length; i++) {
      final f = formats[i];
      final scaled = remaining * f.conversion;
      if (i == formats.length - 1) {
        parts.add(f.format(remaining));
      } else {
        final whole = scaled.truncateToDouble();
        if (whole != 0) parts.add(f.format(whole / f.conversion));
        remaining = (scaled - whole) / f.conversion;
      }
    }
    return parts.join(' ');
  }

  /// Parses a /Measure dictionary; returns null for non-dictionaries.
  static PdfMeasure? fromDict(PdfDocument document, CosObject? raw) {
    final cos = document.cos;
    final dict = cos.resolve(raw);
    if (dict is! CosDictionary) return null;

    List<PdfNumberFormat>? formats(String key) {
      final array = cos.resolve(dict[key]);
      if (array is! CosArray) return null;
      final out = <PdfNumberFormat>[];
      for (final item in array.items) {
        final f = PdfNumberFormat.fromDict(document, item);
        if (f != null) out.add(f);
      }
      return out.isEmpty ? null : out;
    }

    final r = cos.resolve(dict['R']);
    final subtypeName = cos.resolve(dict['Subtype']);
    final xFormats = formats('X');
    final distanceFormats = formats('D');
    final areaFormats = formats('A');
    return PdfMeasure(
      subtype: subtypeName is CosName ? subtypeName.value : 'RL',
      ratio: r is CosString ? r.text : '',
      x: xFormats ?? const [PdfNumberFormat(unit: '')],
      y: formats('Y'),
      distance: distanceFormats ?? xFormats ?? const [PdfNumberFormat(unit: '')],
      area: areaFormats ?? const [PdfNumberFormat(unit: '')],
      angle: formats('T'),
    );
  }

  CosDictionary toCosDictionary() {
    CosArray array(List<PdfNumberFormat> formats) =>
        CosArray([for (final f in formats) f.toCosDictionary()]);
    final dict = CosDictionary({
      'Type': const CosName('Measure'),
      'Subtype': CosName(subtype),
      'R': CosString.fromText(ratio),
      'X': array(x),
      'D': array(distance),
      'A': array(area),
    });
    if (y != null) dict['Y'] = array(y!);
    if (angle != null) dict['T'] = array(angle!);
    return dict;
  }
}
