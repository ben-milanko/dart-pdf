import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart';

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

  /// The on-page reference unit the scale is quoted against — the
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
        areaUnitLabel:
            measure.area.isNotEmpty ? measure.area.first.unit : null,
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
    final perPageUnit = unitsPerPoint * _pointsPerPageUnit(pageUnitLabel);
    var text = perPageUnit.toStringAsFixed(2);
    if (text.contains('.')) {
      text = text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
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

/// The real-world unit labels offered by [showPdfScaleDialog].
const _pdfScaleUnits = ['ft', 'in', 'yd', 'mi', 'm', 'cm', 'mm', 'km'];

/// The on-page reference units offered for the left-hand side of the ratio.
/// These are physical lengths on the printed page, so only the small units
/// make sense.
const _pdfPageUnits = ['in', 'cm', 'mm'];

/// PDF points per one [pageUnit] (72 points = 1 inch). Falls back to inches
/// for an unknown label.
double _pointsPerPageUnit(String pageUnit) {
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
/// (`platformDispatcher.locale` — the browser language on the web).
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

/// Asks the user for a drawing scale (`1 in on the page = N unit in the
/// world`) and returns the calibrated [PdfMeasurementScale], or null when
/// dismissed. [initial] pre-fills the fields. When [onCalibrate] is given,
/// the dialog offers a "Calibrate" action that dismisses the dialog and
/// invokes the callback (typically to arm the draw-a-reference-segment
/// flow) instead of returning a typed ratio.
Future<PdfMeasurementScale?> showPdfScaleDialog(
  BuildContext context, {
  PdfMeasurementScale? initial,
  VoidCallback? onCalibrate,
}) =>
    showDialog<PdfMeasurementScale>(
      context: context,
      builder: (context) =>
          PdfScaleDialog(initial: initial, onCalibrate: onCalibrate),
    );

/// The scale-calibration dialog shown by [showPdfScaleDialog]. The user
/// expresses the drawing's scale as "1 inch on the page equals N real
/// units" — the most common way drawing scales are quoted — or taps
/// "Calibrate" (when [onCalibrate] is set) to measure a known length on
/// the page instead.
class PdfScaleDialog extends StatefulWidget {
  const PdfScaleDialog({super.key, this.initial, this.onCalibrate});

  final PdfMeasurementScale? initial;

  /// Called when the user chooses to calibrate by drawing a reference
  /// segment; the dialog dismisses first. Null hides the action.
  final VoidCallback? onCalibrate;

  @override
  State<PdfScaleDialog> createState() => _PdfScaleDialogState();
}

class _PdfScaleDialogState extends State<PdfScaleDialog> {
  late final TextEditingController _value;
  late String _unit;
  late String _pageUnit;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    // Carry over the on-page reference unit (the left-hand side) from an
    // existing scale; otherwise default to the device region's measurement
    // system (inches vs centimetres).
    _pageUnit = (initial != null && _pdfPageUnits.contains(initial.pageUnitLabel))
        ? initial.pageUnitLabel
        : pdfDefaultPageUnit();
    final perPageUnit =
        initial == null ? 1.0 : initial.unitsPerPoint * _pointsPerPageUnit(_pageUnit);
    var text = perPageUnit.toStringAsFixed(2);
    if (text.contains('.')) {
      text =
          text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    }
    _value = TextEditingController(text: text);
    // Carry over the real-world unit from an existing scale; otherwise
    // default to the device region's measurement system (feet vs metres).
    _unit = (initial != null && _pdfScaleUnits.contains(initial.unitLabel))
        ? initial.unitLabel
        : pdfDefaultMeasurementUnit();
  }

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  void _submit() {
    final perPageUnit = double.tryParse(_value.text.trim());
    if (perPageUnit == null || perPageUnit <= 0) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop(PdfMeasurementScale(
      unitsPerPoint: perPageUnit / _pointsPerPageUnit(_pageUnit),
      unitLabel: _unit,
      pageUnitLabel: _pageUnit,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Set measurement scale'),
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('1  '),
          DropdownButton<String>(
            key: const ValueKey('pdf-scale-page-unit'),
            value: _pageUnit,
            onChanged: (value) {
              if (value != null) setState(() => _pageUnit = value);
            },
            items: [
              for (final unit in _pdfPageUnits)
                DropdownMenuItem(value: unit, child: Text(unit)),
            ],
          ),
          const Text('  =  '),
          SizedBox(
            width: 80,
            child: TextField(
              key: const ValueKey('pdf-scale-value'),
              controller: _value,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.end,
              onSubmitted: (_) => _submit(),
            ),
          ),
          const SizedBox(width: 8),
          DropdownButton<String>(
            key: const ValueKey('pdf-scale-unit'),
            value: _unit,
            onChanged: (value) {
              if (value != null) setState(() => _unit = value);
            },
            items: [
              for (final unit in _pdfScaleUnits)
                DropdownMenuItem(value: unit, child: Text(unit)),
            ],
          ),
        ],
      ),
      actions: [
        if (widget.onCalibrate != null)
          TextButton(
            key: const ValueKey('pdf-scale-calibrate'),
            onPressed: () {
              Navigator.of(context).pop();
              widget.onCalibrate!();
            },
            child: const Text('Calibrate'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('pdf-scale-apply'),
          onPressed: _submit,
          child: const Text('Set scale'),
        ),
      ],
    );
  }
}

/// Asks how long the just-drawn reference segment is in the real world,
/// returning `(realLength, unitLabel)` or null when dismissed. Used by the
/// draw-a-segment calibration flow after the user releases the drag.
/// [initialUnit] pre-selects the unit (defaults to the device region's).
Future<(double, String)?> showPdfCalibrationLengthDialog(
  BuildContext context, {
  String? initialUnit,
}) =>
    showDialog<(double, String)>(
      context: context,
      builder: (context) => _PdfCalibrationLengthDialog(initialUnit: initialUnit),
    );

/// Asks for the extrusion depth of a volume measurement, in the scale's
/// distance unit ([unitLabel], shown as a suffix). Returns the depth, or
/// null when dismissed. Used by the volume tool after the footprint polygon
/// is drawn.
Future<double?> showPdfDepthDialog(
  BuildContext context, {
  String? unitLabel,
}) =>
    showDialog<double>(
      context: context,
      builder: (context) => _PdfDepthDialog(unitLabel: unitLabel),
    );

class _PdfDepthDialog extends StatefulWidget {
  const _PdfDepthDialog({this.unitLabel});

  final String? unitLabel;

  @override
  State<_PdfDepthDialog> createState() => _PdfDepthDialogState();
}

class _PdfDepthDialogState extends State<_PdfDepthDialog> {
  final _value = TextEditingController();

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  void _submit() {
    final depth = double.tryParse(_value.text.trim());
    if (depth == null || depth <= 0) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop(depth);
  }

  @override
  Widget build(BuildContext context) {
    final unit = widget.unitLabel;
    return AlertDialog(
      title: const Text('Volume depth'),
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Depth: '),
          SizedBox(
            width: 100,
            child: TextField(
              key: const ValueKey('pdf-depth-value'),
              controller: _value,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.end,
              onSubmitted: (_) => _submit(),
            ),
          ),
          if (unit != null && unit.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(unit),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('pdf-depth-apply'),
          onPressed: _submit,
          child: const Text('Measure'),
        ),
      ],
    );
  }
}

class _PdfCalibrationLengthDialog extends StatefulWidget {
  const _PdfCalibrationLengthDialog({this.initialUnit});

  final String? initialUnit;

  @override
  State<_PdfCalibrationLengthDialog> createState() =>
      _PdfCalibrationLengthDialogState();
}

class _PdfCalibrationLengthDialogState
    extends State<_PdfCalibrationLengthDialog> {
  final _value = TextEditingController();
  late String _unit;

  @override
  void initState() {
    super.initState();
    _unit = (widget.initialUnit != null &&
            _pdfScaleUnits.contains(widget.initialUnit))
        ? widget.initialUnit!
        : pdfDefaultMeasurementUnit();
  }

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  void _submit() {
    final length = double.tryParse(_value.text.trim());
    if (length == null || length <= 0) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop((length, _unit));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Calibrate scale'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('The line you drew represents:'),
          const SizedBox(height: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 100,
                child: TextField(
                  key: const ValueKey('pdf-calibrate-value'),
                  controller: _value,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.end,
                  onSubmitted: (_) => _submit(),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<String>(
                key: const ValueKey('pdf-calibrate-unit'),
                value: _unit,
                onChanged: (value) {
                  if (value != null) setState(() => _unit = value);
                },
                items: [
                  for (final unit in _pdfScaleUnits)
                    DropdownMenuItem(value: unit, child: Text(unit)),
                ],
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('pdf-calibrate-apply'),
          onPressed: _submit,
          child: const Text('Set scale'),
        ),
      ],
    );
  }
}
