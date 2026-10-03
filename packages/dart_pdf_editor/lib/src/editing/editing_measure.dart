import 'package:material_ui/material_ui.dart';

import '../design/material_host.dart';
import '../dialog.dart';
import '../l10n/pdf_l10n.dart';
import 'models/measurement_scale.dart';
import '../design/editor_presenter.dart';

export 'models/measurement_scale.dart'
    show PdfMeasurementScale, pdfDefaultMeasurementUnit, pdfDefaultPageUnit;

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
    pdfPresentDialog<PdfMeasurementScale>(
      context,
      builder: (context) =>
          PdfScaleDialog(initial: initial, onCalibrate: onCalibrate),
    );

/// The scale-calibration dialog shown by [showPdfScaleDialog]. The user
/// expresses the drawing's scale as "1 inch on the page equals N real
/// units" - the most common way drawing scales are quoted - or taps
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
    _pageUnit =
        (initial != null && pdfPageUnits.contains(initial.pageUnitLabel))
            ? initial.pageUnitLabel
            : pdfDefaultPageUnit();
    final perPageUnit = initial == null
        ? 1.0
        : initial.unitsPerPoint * pdfPointsPerPageUnit(_pageUnit);
    var text = perPageUnit.toStringAsFixed(2);
    if (text.contains('.')) {
      text = text
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
    }
    _value = TextEditingController(text: text);
    // Carry over the real-world unit from an existing scale; otherwise
    // default to the device region's measurement system (feet vs metres).
    _unit = (initial != null && pdfScaleUnits.contains(initial.unitLabel))
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
      unitsPerPoint: perPageUnit / pdfPointsPerPageUnit(_pageUnit),
      unitLabel: _unit,
      pageUnitLabel: _pageUnit,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(pdfL10n(context).measSetScale),
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('1  '),
          PdfDropdown<String>(
            key: const ValueKey('pdf-scale-page-unit'),
            value: _pageUnit,
            onChanged: (value) => setState(() => _pageUnit = value),
            items: [
              for (final unit in pdfPageUnits)
                PdfDropdownItem(value: unit, label: unit),
            ],
          ),
          const Text('  =  '),
          SizedBox(
            width: 80,
            child: TextField(
              key: const ValueKey('pdf-scale-value'),
              controller: _value,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.end,
              onSubmitted: (_) => _submit(),
              contextMenuBuilder: pdfTextContextMenu,
            ),
          ),
          const SizedBox(width: 8),
          PdfDropdown<String>(
            key: const ValueKey('pdf-scale-unit'),
            value: _unit,
            onChanged: (value) => setState(() => _unit = value),
            items: [
              for (final unit in pdfScaleUnits)
                PdfDropdownItem(value: unit, label: unit),
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
            child: Text(pdfL10n(context).measCalibrate),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(pdfL10n(context).cancel),
        ),
        PdfDialogSubmit.action(
            onSubmit: _submit,
            child: FilledButton(
              key: const ValueKey('pdf-scale-apply'),
              onPressed: _submit,
              child: Text(pdfL10n(context).measSetScaleButton),
            )),
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
    pdfPresentDialog<(double, String)>(
      context,
      builder: (context) =>
          _PdfCalibrationLengthDialog(initialUnit: initialUnit),
    );

/// Asks for the extrusion depth of a volume measurement, in the scale's
/// distance unit ([unitLabel], shown as a suffix). Returns the depth, or
/// null when dismissed. Used by the volume tool after the footprint polygon
/// is drawn.
Future<double?> showPdfDepthDialog(
  BuildContext context, {
  String? unitLabel,
}) =>
    pdfPresentDialog<double>(
      context,
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
      title: Text(pdfL10n(context).measVolumeDepth),
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(pdfL10n(context).measDepthLabel),
          SizedBox(
            width: 100,
            child: TextField(
              key: const ValueKey('pdf-depth-value'),
              controller: _value,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.end,
              onSubmitted: (_) => _submit(),
              contextMenuBuilder: pdfTextContextMenu,
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
          child: Text(pdfL10n(context).cancel),
        ),
        PdfDialogSubmit.action(
            onSubmit: _submit,
            child: FilledButton(
              key: const ValueKey('pdf-depth-apply'),
              onPressed: _submit,
              child: Text(pdfL10n(context).measMeasure),
            )),
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
            pdfScaleUnits.contains(widget.initialUnit))
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
      title: Text(pdfL10n(context).measCalibrateScale),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(pdfL10n(context).measLineRepresents),
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
                  contextMenuBuilder: pdfTextContextMenu,
                ),
              ),
              const SizedBox(width: 8),
              PdfDropdown<String>(
                key: const ValueKey('pdf-calibrate-unit'),
                value: _unit,
                onChanged: (value) => setState(() => _unit = value),
                items: [
                  for (final unit in pdfScaleUnits)
                    PdfDropdownItem(value: unit, label: unit),
                ],
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(pdfL10n(context).cancel),
        ),
        PdfDialogSubmit.action(
            onSubmit: _submit,
            child: FilledButton(
              key: const ValueKey('pdf-calibrate-apply'),
              onPressed: _submit,
              child: Text(pdfL10n(context).measSetScaleButton),
            )),
      ],
    );
  }
}
