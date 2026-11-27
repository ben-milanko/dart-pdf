import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:pdf_document/pdf_document.dart';

import 'design/editor_presenter.dart';
import 'design/material_host.dart';
import 'dialog.dart';
import 'l10n/pdf_l10n.dart';

/// What [showPdfPageResizeDialog] resolves to: the new page size in points,
/// as displayed, and how the content fits it.
typedef PdfPageResizeRequest = ({
  double width,
  double height,
  PdfPageResizeMode mode,
});

/// Asks for a new page size - a standard paper size in either orientation,
/// or a custom width × height in mm, inches or points - and whether the
/// content scales to fit it or keeps its size. Resolves to null when
/// cancelled.
///
/// [width] × [height] (points, as displayed) seed the fields: pass the
/// right-clicked page's size. [pageCount] is how many pages the resize
/// spans, for the title. Feed the result to
/// [PdfEditingController.resizePages].
Future<PdfPageResizeRequest?> showPdfPageResizeDialog(
  BuildContext context, {
  required double width,
  required double height,
  int pageCount = 1,
}) =>
    pdfPresentDialog<PdfPageResizeRequest>(
      context,
      builder: (context) => _PdfPageResizeDialog(
        width: width,
        height: height,
        pageCount: pageCount,
      ),
    );

/// The paper sizes offered, portrait; [custom] is the free-form entry.
enum _PaperPreset {
  a3('A3', PdfPageSize.a3, _PageUnit.mm),
  a4('A4', PdfPageSize.a4, _PageUnit.mm),
  a5('A5', PdfPageSize.a5, _PageUnit.mm),
  letter('Letter', PdfPageSize.letter, _PageUnit.inch),
  legal('Legal', PdfPageSize.legal, _PageUnit.inch),
  tabloid('Tabloid', PdfPageSize.tabloid, _PageUnit.inch),
  custom('', null, null);

  const _PaperPreset(this.name, this.size, this.unit);

  /// A paper size's proper name (not translated, like "A4").
  final String name;
  final PdfPageSize? size;

  /// The unit the paper is specified in, used to describe it.
  final _PageUnit? unit;

  /// The preset [width] × [height] (either orientation) is, or [custom].
  static _PaperPreset matching(double width, double height) {
    final short = width < height ? width : height;
    final long = width < height ? height : width;
    for (final preset in values) {
      final size = preset.size;
      if (size == null) continue;
      // within half a point: files round A-sizes either way
      if ((size.width - short).abs() < 0.5 &&
          (size.height - long).abs() < 0.5) {
        return preset;
      }
    }
    return custom;
  }
}

enum _PageUnit {
  mm('mm', 72 / 25.4, 1),
  inch('in', 72, 2),
  pt('pt', 1, 1);

  const _PageUnit(this.symbol, this.points, this.decimals);

  final String symbol;

  /// Points per unit.
  final double points;

  /// Decimals shown when a size is written into a field.
  final int decimals;

  String format(double pts) {
    var s = (pts / points).toStringAsFixed(decimals);
    if (s.contains('.')) {
      s = s.replaceFirst(RegExp(r'0+$'), '');
      if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    }
    return s;
  }
}

class _PdfPageResizeDialog extends StatefulWidget {
  const _PdfPageResizeDialog({
    required this.width,
    required this.height,
    required this.pageCount,
  });

  final double width;
  final double height;
  final int pageCount;

  @override
  State<_PdfPageResizeDialog> createState() => _PdfPageResizeDialogState();
}

class _PdfPageResizeDialogState extends State<_PdfPageResizeDialog> {
  late _PaperPreset _preset =
      _PaperPreset.matching(widget.width, widget.height);
  late bool _landscape = widget.width > widget.height;
  late _PageUnit _unit = _preset.unit ?? _PageUnit.mm;
  var _mode = PdfPageResizeMode.scaleToFit;
  late final _widthField =
      TextEditingController(text: _unit.format(widget.width));
  late final _heightField =
      TextEditingController(text: _unit.format(widget.height));
  bool _invalid = false;

  @override
  void dispose() {
    _widthField.dispose();
    _heightField.dispose();
    super.dispose();
  }

  double? _parse(TextEditingController field) {
    final value = double.tryParse(field.text.trim().replaceAll(',', '.'));
    if (value == null || !value.isFinite || value <= 0) return null;
    return value * _unit.points;
  }

  /// Writes a preset's size into the fields, in the chosen orientation.
  void _applyPreset() {
    final size = _preset.size;
    if (size == null) return;
    final oriented = _landscape ? size.landscape : size.portrait;
    _widthField.text = _unit.format(oriented.width);
    _heightField.text = _unit.format(oriented.height);
  }

  /// A typed size picks the preset (and orientation) it happens to be.
  void _onFieldEdited() {
    final width = _parse(_widthField);
    final height = _parse(_heightField);
    setState(() {
      _invalid = false;
      if (width == null || height == null) {
        _preset = _PaperPreset.custom;
        return;
      }
      _preset = _PaperPreset.matching(width, height);
      if (width != height) _landscape = width > height;
    });
  }

  void _setUnit(_PageUnit unit) {
    final width = _parse(_widthField);
    final height = _parse(_heightField);
    setState(() {
      _unit = unit;
      if (width != null) _widthField.text = unit.format(width);
      if (height != null) _heightField.text = unit.format(height);
    });
  }

  void _submit() {
    final width = _parse(_widthField);
    final height = _parse(_heightField);
    // 14400pt (200in) is the §C.2 page-size ceiling
    if (width == null || height == null || width > 14400 || height > 14400) {
      setState(() => _invalid = true);
      return;
    }
    // a preset is sized exactly, not as rounded into the fields
    final size = _preset.size;
    if (size != null) {
      final oriented = _landscape ? size.landscape : size.portrait;
      Navigator.of(context).pop((
        width: oriented.width,
        height: oriented.height,
        mode: _mode,
      ));
      return;
    }
    Navigator.of(context).pop((width: width, height: height, mode: _mode));
  }

  String _describe(_PaperPreset preset) {
    final size = preset.size;
    final unit = preset.unit;
    if (size == null || unit == null) return pdfL10n(context).pageResizeCustom;
    return '${preset.name} (${unit.format(size.width)} × '
        '${unit.format(size.height)} ${unit.symbol})';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = pdfL10n(context);
    Widget field(String label, TextEditingController controller, Key key) =>
        Expanded(
          child: TextField(
            key: key,
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            textInputAction: TextInputAction.next,
            onChanged: (_) => _onFieldEdited(),
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: label,
              suffixText: _unit.symbol,
              isDense: true,
            ),
            contextMenuBuilder: pdfTextContextMenu,
          ),
        );

    return AlertDialog(
      key: const ValueKey('pdf-page-resize-dialog'),
      title: Text(l10n.pageResizeTitle(widget.pageCount)),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PdfDropdown<_PaperPreset>(
              key: const ValueKey('pdf-page-resize-preset'),
              value: _preset,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.pageResizeSize,
                isDense: true,
              ),
              items: [
                for (final preset in _PaperPreset.values)
                  PdfDropdownItem(
                    key: ValueKey('pdf-page-resize-preset-${preset.name}'),
                    value: preset,
                    label: _describe(preset),
                  ),
              ],
              onChanged: (preset) => setState(() {
                _preset = preset;
                _invalid = false;
                if (preset.unit case final unit?) _unit = unit;
                _applyPreset();
              }),
            ),
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              key: const ValueKey('pdf-page-resize-orientation'),
              segments: [
                ButtonSegment(
                  value: false,
                  icon: const Icon(Icons.stay_current_portrait),
                  label: Text(l10n.pageResizePortrait),
                ),
                ButtonSegment(
                  value: true,
                  icon: const Icon(Icons.stay_current_landscape),
                  label: Text(l10n.pageResizeLandscape),
                ),
              ],
              selected: {_landscape},
              onSelectionChanged: (value) => setState(() {
                final landscape = value.single;
                if (landscape == _landscape) return;
                _landscape = landscape;
                if (_preset.size != null) {
                  _applyPreset();
                } else {
                  // a custom size swaps its sides
                  final width = _widthField.text;
                  _widthField.text = _heightField.text;
                  _heightField.text = width;
                }
              }),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                field(l10n.pageResizeWidth, _widthField,
                    const ValueKey('pdf-page-resize-width')),
                const SizedBox(width: 12),
                field(l10n.pageResizeHeight, _heightField,
                    const ValueKey('pdf-page-resize-height')),
                const SizedBox(width: 12),
                PdfDropdown<_PageUnit>(
                  key: const ValueKey('pdf-page-resize-unit'),
                  value: _unit,
                  isDense: true,
                  items: [
                    for (final unit in _PageUnit.values)
                      PdfDropdownItem(
                        key: ValueKey('pdf-page-resize-unit-${unit.symbol}'),
                        value: unit,
                        label: unit.symbol,
                      ),
                  ],
                  onChanged: _setUnit,
                ),
              ],
            ),
            if (_invalid) ...[
              const SizedBox(height: 8),
              Text(
                l10n.pageResizeInvalid,
                key: const ValueKey('pdf-page-resize-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            RadioGroup<PdfPageResizeMode>(
              groupValue: _mode,
              onChanged: (mode) {
                if (mode != null) setState(() => _mode = mode);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<PdfPageResizeMode>(
                    key: const ValueKey('pdf-page-resize-scale'),
                    value: PdfPageResizeMode.scaleToFit,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.pageResizeScaleToFit),
                  ),
                  RadioListTile<PdfPageResizeMode>(
                    key: const ValueKey('pdf-page-resize-keep'),
                    value: PdfPageResizeMode.keepContentSize,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.pageResizeKeepSize),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('pdf-page-resize-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        PdfDialogSubmit.action(
          onSubmit: _submit,
          child: FilledButton(
            key: const ValueKey('pdf-page-resize-confirm'),
            onPressed: _submit,
            child: Text(l10n.pageResizeConfirm),
          ),
        ),
      ],
    );
  }
}
