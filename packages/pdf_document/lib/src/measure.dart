import 'dart:math' as math;

import 'package:pdf_cos/pdf_cos.dart';

import 'document.dart';

/// The kind of measurement [PdfAnnotationEditing.addMeasurement] creates.
///
/// The first three are the classic dimensions: a /Line [distance], a
/// /PolyLine [perimeter] (sum of segment lengths), and a /Polygon [area]
/// (shoelace). The takeoff suite adds:
///
/// - [count] - a point marker; each contributes 1 to a running tally.
/// - [volume] - a /Polygon area multiplied by a stored depth (area × depth).
/// - [angle] - three vertices; the interior angle at the middle one.
/// - [arc] - three vertices on a circular arc; its swept length.
/// - [slope] - a /Line read as rise/run; the inclination from horizontal.
/// - [areaCutout] - a /Polygon with holes; the net (outer − holes) area.
enum PdfMeasurementKind {
  distance,
  perimeter,
  area,
  count,
  volume,
  angle,
  arc,
  slope,
  areaCutout,
}

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

/// The total length of the open polyline through [points], in the same
/// units as the coordinates. Used by perimeter and arc measurements.
double pdfPolylineLength(List<(double, double)> points) {
  var total = 0.0;
  for (var i = 0; i + 1 < points.length; i++) {
    final dx = points[i + 1].$1 - points[i].$1;
    final dy = points[i + 1].$2 - points[i].$2;
    total += math.sqrt(dx * dx + dy * dy);
  }
  return total;
}

/// The net area of a polygon with [holes] cut out: the outer [boundary]
/// shoelace area minus the shoelace area of every hole. Negative results
/// (holes larger than the boundary) clamp to zero. Used by area-cutout
/// (net area) measurements.
double pdfNetPolygonArea(
  List<(double, double)> boundary,
  Iterable<List<(double, double)>> holes,
) {
  var net = pdfShoelaceArea(boundary);
  for (final hole in holes) {
    net -= pdfShoelaceArea(hole);
  }
  return net < 0 ? 0 : net;
}

/// The interior angle at [vertex], in degrees, between the arms running to
/// [a] and [b]. Returns 0 when either arm has zero length. Shared by angle
/// measurements.
double pdfAngleDegrees(
  (double, double) vertex,
  (double, double) a,
  (double, double) b,
) {
  final ax = a.$1 - vertex.$1, ay = a.$2 - vertex.$2;
  final bx = b.$1 - vertex.$1, by = b.$2 - vertex.$2;
  final la = math.sqrt(ax * ax + ay * ay);
  final lb = math.sqrt(bx * bx + by * by);
  if (la == 0 || lb == 0) return 0;
  final cos = ((ax * bx + ay * by) / (la * lb)).clamp(-1.0, 1.0);
  return math.acos(cos) * 180 / math.pi;
}

/// The inclination of the segment from [a] to [b] above the horizontal, in
/// degrees in the range 0–90 (the absolute slope angle). Shared by slope
/// measurements; the rise/run ratio is `tan` of this. Returns 0 for a
/// degenerate segment.
double pdfSlopeDegrees((double, double) a, (double, double) b) {
  final dx = (b.$1 - a.$1).abs();
  final dy = (b.$2 - a.$2).abs();
  if (dx == 0 && dy == 0) return 0;
  return math.atan2(dy, dx) * 180 / math.pi;
}

/// The metrics of the circular arc through three points: the circle
/// [radius], the swept arc [length], and the [sweep] angle in degrees.
/// Returns null when the points are collinear (no finite circle). [start]
/// and [end] are the arc endpoints; [mid] is a point on the arc between
/// them. Shared by arc measurements.
({double radius, double length, double sweep})? pdfArcMetrics(
  (double, double) start,
  (double, double) mid,
  (double, double) end,
) {
  // Circumcentre of the triangle (start, mid, end).
  final ax = start.$1, ay = start.$2;
  final bx = mid.$1, by = mid.$2;
  final cx = end.$1, cy = end.$2;
  final d = 2 * (ax * (by - cy) + bx * (cy - ay) + cx * (ay - by));
  if (d.abs() < 1e-9) return null; // collinear
  final a2 = ax * ax + ay * ay;
  final b2 = bx * bx + by * by;
  final c2 = cx * cx + cy * cy;
  final ux = (a2 * (by - cy) + b2 * (cy - ay) + c2 * (ay - by)) / d;
  final uy = (a2 * (cx - bx) + b2 * (ax - cx) + c2 * (bx - ax)) / d;
  final radius = math.sqrt((ax - ux) * (ax - ux) + (ay - uy) * (ay - uy));
  if (radius == 0) return null;

  double ang((double, double) p) => math.atan2(p.$2 - uy, p.$1 - ux);
  final a0 = ang(start);
  final am = ang(mid);
  final a1 = ang(end);

  // Sweep from start to end passing through mid: normalise both legs to a
  // consistent winding by going start→mid→end.
  double norm(double from, double to) {
    var delta = to - from;
    while (delta <= -math.pi) {
      delta += 2 * math.pi;
    }
    while (delta > math.pi) {
      delta -= 2 * math.pi;
    }
    return delta;
  }

  final leg1 = norm(a0, am);
  final leg2 = norm(am, a1);
  // If the two legs disagree in sign the mid point isn't between; fall back
  // to the direct sweep.
  final sweepRad = (leg1.sign == leg2.sign)
      ? (leg1.abs() + leg2.abs())
      : norm(a0, a1).abs();
  return (
    radius: radius,
    length: radius * sweepRad,
    sweep: sweepRad * 180 / math.pi,
  );
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
/// `60 ft` rather than `60.00 ft` - the product choice the measurement
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

  /// /U - the unit label ('ft', 'm', 'ft²', ...).
  final String unit;

  /// /C - the factor a value is multiplied by to reach [unit].
  final double conversion;

  /// /D - the rounding granularity: the value is shown to the nearest
  /// `1 / precision` (so 100 → two decimals, 1 → whole numbers) for the
  /// decimal formats, or used as the denominator for [fractionFormat] 'F'.
  final int precision;

  /// /F - 'D' decimal (default), 'F' fraction with denominator [precision],
  /// 'R' round, 'T' truncate.
  final String fractionFormat;

  /// /RD - the decimal separator.
  final String decimalSeparator;

  /// /RT - the thousands separator.
  final String thousandsSeparator;

  /// /PS - text concatenated to the start of the display.
  final String prefix;

  /// /SS - text concatenated to the end of the display.
  final String suffix;

  /// /O - 'S' to place [unit] after the number (default), 'P' before.
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
    this.volume,
    this.subtype = 'RL',
  });

  /// Builds a rectilinear scale: [unitsPerPoint] real-world units per PDF
  /// point along each axis, labelled [unitLabel] (and [areaUnitLabel] for
  /// areas, defaulting to `unitLabel²`).
  factory PdfMeasure.scale({
    required double unitsPerPoint,
    required String unitLabel,
    String? areaUnitLabel,
    String? volumeUnitLabel,
    int precision = 100,
    String? ratioLabel,
  }) {
    final areaUnit = areaUnitLabel ?? '$unitLabel²';
    final volumeUnit = volumeUnitLabel ?? '$unitLabel³';
    return PdfMeasure(
      ratio: ratioLabel ?? _defaultRatioLabel(unitsPerPoint, unitLabel),
      x: [PdfNumberFormat(unit: unitLabel, conversion: unitsPerPoint, precision: precision)],
      distance: [PdfNumberFormat(unit: unitLabel, precision: precision)],
      area: [PdfNumberFormat(unit: areaUnit, precision: precision)],
      volume: [PdfNumberFormat(unit: volumeUnit, precision: precision)],
      angle: [PdfNumberFormat(unit: '°', precision: precision)],
    );
  }

  static String _defaultRatioLabel(double unitsPerPoint, String unitLabel) {
    // express as "1 in = N unit" (72 points = 1 inch)
    final perInch = PdfNumberFormat(unit: '', precision: 100).format(unitsPerPoint * 72);
    return '1 in = $perInch $unitLabel';
  }

  /// /Subtype - 'RL' (rectilinear) is the only kind written here.
  final String subtype;

  /// /R - the user-facing ratio label (e.g. `1 in = 20 ft`).
  final String ratio;

  /// /X - the number formats converting an x-axis page distance to the
  /// measured unit. The first entry's [PdfNumberFormat.conversion] is the
  /// per-point scale factor.
  final List<PdfNumberFormat> x;

  /// /Y - the y-axis formats; falls back to [x] when absent.
  final List<PdfNumberFormat>? y;

  /// /D - the formats rendering a distance.
  final List<PdfNumberFormat> distance;

  /// /A - the formats rendering an area.
  final List<PdfNumberFormat> area;

  /// /T - the formats rendering an angle, if present.
  final List<PdfNumberFormat>? angle;

  /// The formats rendering a volume (area × depth), if present. Persisted
  /// under the non-standard /V key - viewers that don't know it ignore it;
  /// this library round-trips it so volume takeoffs survive a reopen.
  final List<PdfNumberFormat>? volume;

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

  /// The real-world area for a raw page-space [pointArea], used by volume
  /// and net-area takeoffs that need the numeric value, not the label.
  double realArea(double pointArea) => pointArea * _xFactor * _yFactor;

  /// The real-world length for a raw page-space [pointLength].
  double realDistance(double pointLength) => pointLength * _xFactor;

  /// Formats a volume: a raw page-space [pointArea] multiplied by a real-
  /// world [depth] (already in the distance unit). Falls back to the area
  /// formats with a `³` unit when no /V formats are present.
  String formatVolume(double pointArea, double depth) {
    final value = realArea(pointArea) * depth;
    final formats = volume;
    if (formats != null && formats.isNotEmpty) return _walk(formats, value);
    final unit = area.isNotEmpty ? '${area.first.unit}·d' : '';
    return PdfNumberFormat(unit: unit).format(value);
  }

  /// Formats an angle of [degrees] through the /T formats, defaulting to a
  /// whole-degree `°` label.
  String formatAngle(double degrees) {
    final formats = angle;
    if (formats != null && formats.isNotEmpty) return _walk(formats, degrees);
    return const PdfNumberFormat(unit: '°', precision: 10).format(degrees);
  }

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
      volume: formats('V'),
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
    if (volume != null) dict['V'] = array(volume!);
    return dict;
  }
}
