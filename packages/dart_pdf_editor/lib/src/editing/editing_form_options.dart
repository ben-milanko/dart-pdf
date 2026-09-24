import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart';

import '../dialog.dart';
import '../l10n/pdf_l10n.dart';
import 'editing_controller.dart';

/// What the choice-field options editor hands back: the (export value,
/// display text) pairs in order, plus the one flag that applies to the
/// field's kind - [editable] for a combo box, [multiSelect] for a list box
/// (the other is null).
class PdfFormOptionsEdit {
  const PdfFormOptionsEdit({
    required this.options,
    this.editable,
    this.multiSelect,
  });

  final List<(String export, String display)> options;
  final bool? editable;
  final bool? multiSelect;
}

/// Opens the options editor for the combo or list box [fieldName] and
/// applies the result through
/// [PdfEditingController.setFormFieldOptions]. Returns whether the field
/// changed (false when cancelled, unchanged, or not a choice field).
Future<bool> showPdfFormOptionsDialog({
  required BuildContext context,
  required PdfEditingController controller,
  required String fieldName,
}) async {
  final field = controller.acroForm?.fieldNamed(fieldName);
  if (field == null ||
      (field.type != PdfFieldType.comboBox &&
          field.type != PdfFieldType.listBox)) {
    return false;
  }
  final combo = field.type == PdfFieldType.comboBox;
  final edit = await showPdfDialog<PdfFormOptionsEdit>(
    context: context,
    builder: (context) => PdfFormOptionsEditor(
      options: field.options,
      combo: combo,
      flag: combo
          ? field.flags & PdfFormField.editFlag != 0
          : field.flags & PdfFormField.multiSelectFlag != 0,
    ),
  );
  if (edit == null) return false;
  return controller.setFormFieldOptions(
    fieldName,
    edit.options,
    editable: edit.editable,
    multiSelect: edit.multiSelect,
  );
}

/// The dialog body of [showPdfFormOptionsDialog]: one row per option with
/// its export value and display text, an add button, and the combo box's
/// "allow custom text" or the list box's "allow multiple selections"
/// switch. Pops a [PdfFormOptionsEdit] on save.
///
/// An option left with one of its two texts empty takes the other for
/// both (a plain /Opt string); a row with both empty is dropped.
class PdfFormOptionsEditor extends StatefulWidget {
  const PdfFormOptionsEditor({
    super.key,
    required this.options,
    required this.combo,
    required this.flag,
  });

  /// The options the editor starts from.
  final List<(String, String)> options;

  /// Whether the field is a combo box (else a list box) - picks the flag.
  final bool combo;

  /// The starting value of the kind's flag (Edit or MultiSelect).
  final bool flag;

  @override
  State<PdfFormOptionsEditor> createState() => _PdfFormOptionsEditorState();
}

class _OptionRow {
  _OptionRow(String export, String display)
      : export = TextEditingController(text: export),
        display = TextEditingController(text: display);

  final TextEditingController export;
  final TextEditingController display;

  void dispose() {
    export.dispose();
    display.dispose();
  }
}

class _PdfFormOptionsEditorState extends State<PdfFormOptionsEditor> {
  late final List<_OptionRow> _rows = [
    for (final (export, display) in widget.options) _OptionRow(export, display),
  ];
  late bool _flag = widget.flag;

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  List<(String, String)> get _options => [
        for (final row in _rows)
          if (row.export.text.trim().isNotEmpty ||
              row.display.text.trim().isNotEmpty)
            (
              row.export.text.trim().isEmpty
                  ? row.display.text.trim()
                  : row.export.text.trim(),
              row.display.text.trim().isEmpty
                  ? row.export.text.trim()
                  : row.display.text.trim(),
            ),
      ];

  void _add() => setState(() => _rows.add(_OptionRow('', '')));

  void _remove(int index) => setState(() => _rows.removeAt(index).dispose());

  @override
  Widget build(BuildContext context) {
    final l10n = pdfL10n(context);
    return AlertDialog(
      title: Text(l10n.formOptionsTitle),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _rows.length,
                itemBuilder: (context, i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: ValueKey('pdf-form-options-export-$i'),
                          controller: _rows[i].export,
                          decoration: InputDecoration(
                            labelText: l10n.formOptionsExportValue,
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          key: ValueKey('pdf-form-options-display-$i'),
                          controller: _rows[i].display,
                          decoration: InputDecoration(
                            labelText: l10n.formOptionsDisplayText,
                            isDense: true,
                          ),
                        ),
                      ),
                      IconButton(
                        key: ValueKey('pdf-form-options-remove-$i'),
                        tooltip: l10n.remove,
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () => _remove(i),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const ValueKey('pdf-form-options-add'),
                onPressed: _add,
                icon: const Icon(Icons.add),
                label: Text(l10n.add),
              ),
            ),
            SwitchListTile(
              key: const ValueKey('pdf-form-options-flag'),
              contentPadding: EdgeInsets.zero,
              title: Text(widget.combo
                  ? l10n.formOptionsAllowCustomText
                  : l10n.formOptionsMultiSelect),
              value: _flag,
              onChanged: (value) => setState(() => _flag = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        PdfDialogSubmit(
          child: FilledButton(
            key: const ValueKey('pdf-form-options-save'),
            onPressed: () => Navigator.of(context).pop(
              PdfFormOptionsEdit(
                options: _options,
                editable: widget.combo ? _flag : null,
                multiSelect: widget.combo ? null : _flag,
              ),
            ),
            child: Text(l10n.save),
          ),
        ),
      ],
    );
  }
}
