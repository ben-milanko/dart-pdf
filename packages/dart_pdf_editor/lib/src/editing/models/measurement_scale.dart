// The headless measurement model, kept apart from the Material scale,
// calibration and depth dialogs in editing_measure.dart (which re-exports the
// public names), so the editing controller's import closure stays free of
// flutter/material. See tool/check_design_imports.dart.

import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:pdf_document/pdf_document.dart' show PdfMeasure;

/// A measurement calibration the editing UI carries: how many real-world
/// units one PDF point represents, the unit label, and the display
/// precision. Persisted in [PdfEditingPreferences] so a drawing's scale
/// survives reopening the file.
///
/// Build one directly, or from a calibration gesture with
/// [PdfMeasurementScale.fromReference]: the user draws a segment of known
/// real length, and the scale is its real length divided by its
/// page-space length.
@immutable
class PdfMeasurementScale {
  const PdfMeasurementScale({
    required this.unitsPerPoint,
    required this.unitLabel,
    this.pageUnitLabel = 'in',
    this.areaUnitLabel,
    this.precision = 100,
  });

  /// Calibrates from a reference segment of [pointLength] PDF points that
  /// represents [realLength] [unitLabel]s. [pageUnitLabel] is the on-page
  /// reference unit the ratio is quoted against ('in', 'cm', 'mm').
  factory PdfMeasurementScale.fromReference({
    required double pointLength,
    required double realLength,
    required String unitLabel,
    String pageUnitLabel = 'in',
    String? areaUnitLabel,
    int precision = 100,
  }) {
    final perPoint = pointLength <= 0 ? 0.0 : realLength / pointLength;
    return PdfMeasurementScale(
      unitsPerPoint: perPoint,
      unitLabel: unitLabel,
      pageUnitLabel: pageUnitLabel,
      areaUnitLabel: areaUnitLabel,
      precision: precision,
    );
  }

  /// Real-world units per PDF point.
  final double unitsPerPoint;

  /// The distance unit label ('ft', 'm', ...).
  final String unitLabel;

  /// The on-page reference unit the scale is quoted against - the
  /// left-hand side of the `1 <pageUnit> = N <unit>` ratio ('in', 'cm',
  /// 'mm'). Defaults to inches, the traditional drawing-scale reference.
  final String pageUnitLabel;

  /// The area unit label, or null to default to `unitLabel²`.
  final String? areaUnitLabel;

  /// The display precision passed to [PdfNumberFormat] (nearest
  /// `1 / precision`).
  final int precision;

  /// Recovers a scale from a document-borne [PdfMeasure] (a page /VP
  /// viewport's /Measure, or an annotation's), so the editor can adopt the
  /// drawing scale a reopened or shared file already carries. The on-page
  /// reference unit isn't stored in /Measure, so it defaults to inches.
  static PdfMeasurementScale fromMeasure(PdfMeasure measure) =>
      PdfMeasurementScale(
        unitsPerPoint: measure.scaleFactor,
        unitLabel: measure.distance.isNotEmpty
            ? measure.distance.first.unit
            : measure.x.first.unit,
        areaUnitLabel: measure.area.isNotEmpty ? measure.area.first.unit : null,
        precision: measure.distance.isNotEmpty
            ? measure.distance.first.precision
            : 100,
      );

  /// The /Measure dictionary model this scale stamps onto annotations.
  PdfMeasure toMeasure() => PdfMeasure.scale(
        unitsPerPoint: unitsPerPoint,
        unitLabel: unitLabel,
        areaUnitLabel: areaUnitLabel,
        precision: precision,
        ratioLabel: ratioLabel,
      );

  /// A short user-facing label, e.g. `1 in = 20 ft` or `1 cm = 5 m`, quoted
  /// against [pageUnitLabel] as the on-page reference unit.
  String get ratioLabel {
    final perPageUnit = unitsPerPoint * pdfPointsPerPageUnit(pageUnitLabel);
    var text = perPageUnit.toStringAsFixed(2);
    if (text.contains('.')) {
      text = text
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
    }
    return '1 $pageUnitLabel = $text $unitLabel';
  }

  String encode() => jsonEncode({
        'u': unitsPerPoint,
        'l': unitLabel,
        if (pageUnitLabel != 'in') 'f': pageUnitLabel,
        if (areaUnitLabel != null) 'a': areaUnitLabel,
        'p': precision,
      });

  static PdfMeasurementScale? decode(String source) {
    try {
      final json = jsonDecode(source);
      if (json is! Map) return null;
      final perPoint = (json['u'] as num?)?.toDouble();
      final label = json['l'] as String?;
      if (perPoint == null || label == null) return null;
      return PdfMeasurementScale(
        unitsPerPoint: perPoint,
        unitLabel: label,
        pageUnitLabel: json['f'] as String? ?? 'in',
        areaUnitLabel: json['a'] as String?,
        precision: (json['p'] as num?)?.toInt() ?? 100,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is PdfMeasurementScale &&
      other.unitsPerPoint == unitsPerPoint &&
      other.unitLabel == unitLabel &&
      other.pageUnitLabel == pageUnitLabel &&
      other.areaUnitLabel == areaUnitLabel &&
      other.precision == precision;

  @override
  int get hashCode => Object.hash(
      unitsPerPoint, unitLabel, pageUnitLabel, areaUnitLabel, precision);
}

/// PDF points per one [pageUnit] (72 points = 1 inch). Falls back to inches
/// for an unknown label.
double pdfPointsPerPageUnit(String pageUnit) {
  switch (pageUnit) {
    case 'cm':
      return 72 / 2.54;
    case 'mm':
      return 72 / 25.4;
    case 'in':
    default:
      return 72;
  }
}

/// The three countries that have not adopted the metric system and so
/// default to imperial units: the United States, Liberia, and Myanmar.
const _imperialCountries = {'US', 'LR', 'MM'};

/// Whether [locale]'s region uses the imperial measurement system. The
/// measurement system is a regional preference, so the country comes from
/// [locale] when it carries one, otherwise from the device locale
/// (`platformDispatcher.locale` - the browser language on the web).
bool _isImperialRegion([Locale? locale]) {
  final country = (locale?.countryCode ??
          WidgetsBinding.instance.platformDispatcher.locale.countryCode)
      ?.toUpperCase();
  return country != null && _imperialCountries.contains(country);
}

/// The default real-world distance unit for [locale]: feet in the
/// imperial-system regions (the US, Liberia, Myanmar), metres everywhere
/// else. The scale dialog passes no argument, so it follows the device
/// region a user expects rather than the app's (possibly English-only) UI
/// locale.
String pdfDefaultMeasurementUnit([Locale? locale]) =>
    _isImperialRegion(locale) ? 'ft' : 'm';

/// The default on-page reference unit (the ratio's left-hand side) for
/// [locale]: inches in the imperial-system regions, centimetres everywhere
/// else. Like [pdfDefaultMeasurementUnit], this follows the device region.
String pdfDefaultPageUnit([Locale? locale]) =>
    _isImperialRegion(locale) ? 'in' : 'cm';
