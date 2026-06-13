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
    this.areaUnitLabel,
    this.precision = 100,
  });

  /// Calibrates from a reference segment of [pointLength] PDF points that
  /// represents [realLength] [unitLabel]s.
  factory PdfMeasurementScale.fromReference({
    required double pointLength,
    required double realLength,
    required String unitLabel,
    String? areaUnitLabel,
    int precision = 100,
  }) {
    final perPoint = pointLength <= 0 ? 0.0 : realLength / pointLength;
    return PdfMeasurementScale(
      unitsPerPoint: perPoint,
      unitLabel: unitLabel,
      areaUnitLabel: areaUnitLabel,
      precision: precision,
    );
  }

  /// Real-world units per PDF point.
  final double unitsPerPoint;

  /// The distance unit label ('ft', 'm', ...).
  final String unitLabel;

  /// The area unit label, or null to default to `unitLabel²`.
  final String? areaUnitLabel;

  /// The display precision passed to [PdfNumberFormat] (nearest
  /// `1 / precision`).
  final int precision;

  /// The /Measure dictionary model this scale stamps onto annotations.
  PdfMeasure toMeasure() => PdfMeasure.scale(
        unitsPerPoint: unitsPerPoint,
        unitLabel: unitLabel,
        areaUnitLabel: areaUnitLabel,
        precision: precision,
        ratioLabel: ratioLabel,
      );

  /// A short user-facing label, e.g. `1 in = 20 ft` (assuming a 72 dpi
  /// inch as the on-page reference unit).
  String get ratioLabel {
    final perInch = unitsPerPoint * 72;
    var text = perInch.toStringAsFixed(2);
    if (text.contains('.')) {
      text = text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    }
    return '1 in = $text $unitLabel';
  }

  String encode() => jsonEncode({
        'u': unitsPerPoint,
        'l': unitLabel,
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
      other.areaUnitLabel == areaUnitLabel &&
      other.precision == precision;

  @override
  int get hashCode =>
      Object.hash(unitsPerPoint, unitLabel, areaUnitLabel, precision);
}

/// The unit labels offered by [showPdfScaleDialog].
const _pdfScaleUnits = ['ft', 'in', 'yd', 'mi', 'm', 'cm', 'mm', 'km'];

/// Asks the user for a drawing scale (`1 in on the page = N unit in the
/// world`) and returns the calibrated [PdfMeasurementScale], or null when
/// dismissed. [initial] pre-fills the fields.
Future<PdfMeasurementScale?> showPdfScaleDialog(
  BuildContext context, {
  PdfMeasurementScale? initial,
}) =>
    showDialog<PdfMeasurementScale>(
      context: context,
      builder: (context) => PdfScaleDialog(initial: initial),
    );

/// The scale-calibration dialog shown by [showPdfScaleDialog]. The user
/// expresses the drawing's scale as "1 inch on the page equals N real
/// units" — the most common way drawing scales are quoted.
class PdfScaleDialog extends StatefulWidget {
  const PdfScaleDialog({super.key, this.initial});

  final PdfMeasurementScale? initial;

  @override
  State<PdfScaleDialog> createState() => _PdfScaleDialogState();
}

class _PdfScaleDialogState extends State<PdfScaleDialog> {
  late final TextEditingController _value;
  late String _unit;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    final perInch = initial == null ? 1.0 : initial.unitsPerPoint * 72;
    var text = perInch.toStringAsFixed(2);
    if (text.contains('.')) {
      text =
          text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    }
    _value = TextEditingController(text: text);
    _unit = (initial != null && _pdfScaleUnits.contains(initial.unitLabel))
        ? initial.unitLabel
        : 'ft';
  }

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  void _submit() {
    final perInch = double.tryParse(_value.text.trim());
    if (perInch == null || perInch <= 0) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop(PdfMeasurementScale(
      unitsPerPoint: perInch / 72,
      unitLabel: _unit,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Set measurement scale'),
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('1 in  =  '),
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
