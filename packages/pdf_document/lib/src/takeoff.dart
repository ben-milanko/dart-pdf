import 'package:pdf_cos/pdf_cos.dart';

import 'annotation.dart';
import 'document.dart';
import 'measure.dart';

/// The takeoff metadata an annotation carries beyond the standard /Measure
/// and geometry: which [PdfMeasurementKind] it represents, plus the extra
/// inputs the kind needs (a [depth] for volume, [holes] for a net-area
/// cutout) and a [label] used to group it into a running total.
///
/// Stored under the annotation's non-standard /Takeoff dictionary so it
/// round-trips through a save/reopen without disturbing other viewers. The
/// classic distance/perimeter/area kinds don't need it - they're inferred
/// from the subtype - but the takeoff kinds (count, volume, angle, arc,
/// slope, area cutout) all do, because several share a subtype.
class PdfTakeoffData {
  const PdfTakeoffData({
    required this.kind,
    this.depth,
    this.holes = const [],
    this.label,
  });

  /// The measurement kind this annotation represents.
  final PdfMeasurementKind kind;

  /// The extrusion depth, in the measure's real-world distance unit, for a
  /// [PdfMeasurementKind.volume] takeoff (area × depth). Null otherwise.
  final double? depth;

  /// The holes cut out of a [PdfMeasurementKind.areaCutout] polygon, each a
  /// closed ring in page space. The net area is the outer boundary minus
  /// these.
  final List<List<(double, double)>> holes;

  /// The group label used to bucket this measurement in a running total
  /// (and, later, to drive tool presets). Null falls back to the kind +
  /// unit.
  final String? label;

  /// Reads the /Takeoff dictionary off [annotation]; returns null when the
  /// annotation carries none.
  static PdfTakeoffData? read(PdfAnnotation annotation) {
    final cos = annotation.document.cos;
    final dict = cos.resolve(annotation.dict['Takeoff']);
    if (dict is! CosDictionary) return null;
    final k = cos.resolve(dict['K']);
    final kind = k is CosName ? _kindByName(k.value) : null;
    if (kind == null) return null;
    final depthRaw = cos.resolve(dict['Depth']);
    final depth = depthRaw is CosInteger
        ? depthRaw.value.toDouble()
        : depthRaw is CosReal
            ? depthRaw.value
            : null;
    final labelRaw = cos.resolve(dict['Label']);
    final label = labelRaw is CosString ? labelRaw.text : null;
    final holes = <List<(double, double)>>[];
    final holesRaw = cos.resolve(dict['Holes']);
    if (holesRaw is CosArray) {
      for (final ring in holesRaw.items) {
        final r = cos.resolve(ring);
        if (r is! CosArray) continue;
        final points = <(double, double)>[];
        for (var i = 0; i + 1 < r.items.length; i += 2) {
          final x = _num(cos.resolve(r.items[i]));
          final y = _num(cos.resolve(r.items[i + 1]));
          if (x == null || y == null) {
            points.clear();
            break;
          }
          points.add((x, y));
        }
        if (points.isNotEmpty) holes.add(points);
      }
    }
    return PdfTakeoffData(kind: kind, depth: depth, holes: holes, label: label);
  }

  CosDictionary toCosDictionary() {
    final dict = CosDictionary({'K': CosName(kind.name)});
    if (depth != null) dict['Depth'] = CosReal(depth!);
    if (label != null && label!.isNotEmpty) {
      dict['Label'] = CosString.fromText(label!);
    }
    if (holes.isNotEmpty) {
      dict['Holes'] = CosArray([
        for (final ring in holes)
          CosArray([
            for (final (x, y) in ring) ...[CosReal(x), CosReal(y)],
          ]),
      ]);
    }
    return dict;
  }

  static double? _num(CosObject? v) => switch (v) {
        CosInteger(:final value) => value.toDouble(),
        CosReal(:final value) => value,
        _ => null,
      };

  static PdfMeasurementKind? _kindByName(String name) {
    for (final k in PdfMeasurementKind.values) {
      if (k.name == name) return k;
    }
    return null;
  }
}

/// A computed takeoff measurement: the kind, the real-world numeric [value]
/// in [unit], the formatted display [text], and the [count] of items this
/// entry represents (1 for everything but a count marker, which may bundle
/// several). Returned by [PdfAnnotation.measurementResult].
class PdfMeasurementResult {
  const PdfMeasurementResult({
    required this.kind,
    required this.value,
    required this.unit,
    required this.text,
    this.count = 1,
  });

  final PdfMeasurementKind kind;
  final double value;
  final String unit;
  final String text;
  final int count;
}

/// One bucket in a [PdfTakeoffSummary]: every measurement of the same
/// [kind] and [unit] sharing a [label], with the running [total] and item
/// [count]. The bucket of count markers reports its tally in [count] and
/// mirrors it in [total].
class PdfTakeoffGroup {
  PdfTakeoffGroup({
    required this.label,
    required this.kind,
    required this.unit,
  });

  /// The group label (the annotations' /Takeoff /Label, or a default).
  final String label;
  final PdfMeasurementKind kind;
  final String unit;

  /// The summed real-world value across the group's measurements.
  double total = 0;

  /// The number of measurements (markers, lines, polygons) in the group.
  int count = 0;

  /// The formatted running total, rendered through [measure] when given so
  /// it matches the on-page captions (otherwise a plain number + unit).
  String formattedTotal([PdfMeasure? measure]) {
    if (kind == PdfMeasurementKind.count) return '$count';
    if (measure != null) {
      switch (kind) {
        case PdfMeasurementKind.area:
        case PdfMeasurementKind.areaCutout:
          return measure.area.first.format(total);
        case PdfMeasurementKind.volume:
          return (measure.volume?.first ?? measure.area.first).format(total);
        case PdfMeasurementKind.angle:
        case PdfMeasurementKind.slope:
          return measure.formatAngle(total);
        case PdfMeasurementKind.distance:
        case PdfMeasurementKind.perimeter:
        case PdfMeasurementKind.arc:
          return measure.distance.first.format(total);
        case PdfMeasurementKind.count:
          break;
      }
    }
    final n = total == total.roundToDouble()
        ? total.toStringAsFixed(0)
        : total.toStringAsFixed(2);
    return unit.isEmpty ? n : '$n $unit';
  }
}

/// Per-kind running totals over a document's measurement annotations - the
/// data behind the takeoff tool's tallies and (later) the markups list.
///
/// Measurements are bucketed by their /Takeoff /Label (falling back to a
/// `kind · unit` key), so two area takeoffs labelled "Slab" accumulate
/// together while a "Roof" area stays separate. Pure Dart: no rendering, so
/// it runs on the VM/server and the web alike.
class PdfTakeoffSummary {
  PdfTakeoffSummary._(this.groups);

  final List<PdfTakeoffGroup> groups;

  /// Builds the summary by walking every page's annotations. [pages] limits
  /// the scan to specific page indices; null scans the whole document.
  factory PdfTakeoffSummary.of(PdfDocument document, {Iterable<int>? pages}) {
    final indices = pages ?? Iterable<int>.generate(document.pageCount);
    final byKey = <String, PdfTakeoffGroup>{};
    final order = <String>[];
    for (final pageIndex in indices) {
      if (pageIndex < 0 || pageIndex >= document.pageCount) continue;
      for (final annot in document.page(pageIndex).annotations) {
        final result = annot.measurementResult;
        if (result == null) continue;
        final takeoff = annot.takeoff;
        final label = takeoff?.label?.isNotEmpty == true
            ? takeoff!.label!
            : '${result.kind.name} · ${result.unit}';
        final key = '${result.kind.name}|${result.unit}|$label';
        final group = byKey.putIfAbsent(key, () {
          order.add(key);
          return PdfTakeoffGroup(
            label: label,
            kind: result.kind,
            unit: result.unit,
          );
        });
        group.total += result.value;
        group.count += result.count;
      }
    }
    return PdfTakeoffSummary._([for (final key in order) byKey[key]!]);
  }

  /// The grand total of every distance-like group (distance/perimeter/arc)
  /// in [unit], or 0 when none match - a convenience for a status line.
  double get totalLength => _sumWhere(const {
        PdfMeasurementKind.distance,
        PdfMeasurementKind.perimeter,
        PdfMeasurementKind.arc,
      });

  /// The grand total of every area-like group (area + net area).
  double get totalArea => _sumWhere(const {
        PdfMeasurementKind.area,
        PdfMeasurementKind.areaCutout,
      });

  /// The grand total of every count group.
  int get totalCount {
    var n = 0;
    for (final g in groups) {
      if (g.kind == PdfMeasurementKind.count) n += g.count;
    }
    return n;
  }

  double _sumWhere(Set<PdfMeasurementKind> kinds) {
    var sum = 0.0;
    for (final g in groups) {
      if (kinds.contains(g.kind)) sum += g.total;
    }
    return sum;
  }
}

/// The interior angle, in degrees, of an angle measurement whose three
/// page-space [vertices] are (arm-end, vertex, arm-end). Exposed for the
/// editor's live readout. Returns 0 for fewer than three vertices.
double pdfMeasurementAngle(List<(double, double)> vertices) {
  if (vertices.length < 3) return 0;
  return pdfAngleDegrees(vertices[1], vertices[0], vertices[2]);
}
