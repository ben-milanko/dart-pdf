import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart';

import 'editing_color_pick.dart';
import 'editing_controller.dart';
import 'editing_font_controls.dart';
import 'editing_fonts.dart';
import 'editing_value_field.dart';
import 'text_prompt.dart';
import '../l10n/pdf_l10n.dart';
import '../popup_position.dart';

/// A field-type menu for the single selected form widget.
///
/// The three targets mirror [PdfEditor.changeFieldType]. Existing radio,
/// choice, and signature fields can still be converted to one of these
/// creatable types; their current type is shown even though it is not a
/// conversion target.
class PdfSelectedFormFieldTypeMenu extends StatelessWidget {
  const PdfSelectedFormFieldTypeMenu({
    super.key,
    required this.controller,
    required this.buttonKey,
    required this.itemKeyPrefix,
    this.showLabel = false,
  });

  final PdfEditingController controller;

  /// Key on the popup trigger.
  final Key buttonKey;

  /// Prefix for the `-text`, `-checkbox`, and `-button` item keys.
  final String itemKeyPrefix;

  /// Shows the current type beside the icon, for a labelled panel row.
  final bool showLabel;

  static PdfFormFieldKind? _kind(PdfFieldType type) => switch (type) {
        PdfFieldType.text => PdfFormFieldKind.text,
        PdfFieldType.checkBox => PdfFormFieldKind.checkBox,
        PdfFieldType.pushButton => PdfFormFieldKind.pushButton,
        _ => null,
      };

  static String _label(BuildContext context, PdfFieldType type) =>
      switch (type) {
        PdfFieldType.text => pdfL10n(context).propFieldTypeText,
        PdfFieldType.checkBox => pdfL10n(context).propFieldTypeCheckBox,
        PdfFieldType.radioGroup => pdfL10n(context).propFieldTypeRadioGroup,
        PdfFieldType.pushButton => pdfL10n(context).propFieldTypeImageButton,
        PdfFieldType.comboBox => pdfL10n(context).propFieldTypeComboBox,
        PdfFieldType.listBox => pdfL10n(context).propFieldTypeListBox,
        PdfFieldType.signature => pdfL10n(context).propFieldTypeSignature,
        PdfFieldType.unknown => pdfL10n(context).propFieldTypeUnknown,
      };

  static IconData _icon(PdfFieldType type) => switch (type) {
        PdfFieldType.text => Icons.text_fields,
        PdfFieldType.checkBox => Icons.check_box_outlined,
        PdfFieldType.radioGroup => Icons.radio_button_checked,
        PdfFieldType.pushButton => Icons.smart_button,
        PdfFieldType.comboBox || PdfFieldType.listBox => Icons.list_alt,
        PdfFieldType.signature => Icons.draw_outlined,
        PdfFieldType.unknown => Icons.help_outline,
      };

  @override
  Widget build(BuildContext context) {
    final type = controller.selectedWidgetFieldType;
    if (type == null) return const SizedBox.shrink();
    final label = _label(context, type);
    return PopupMenuButton<PdfFormFieldKind>(
      key: buttonKey,
      tooltip: pdfL10n(context).propFieldTypeTooltip(label),
      initialValue: _kind(type),
      onSelected: controller.changeSelectedFormFieldKind,
      itemBuilder: (context) => [
        PopupMenuItem(
          key: ValueKey('$itemKeyPrefix-text'),
          value: PdfFormFieldKind.text,
          height: 34,
          child: Text(pdfL10n(context).propFieldTypeText),
        ),
        PopupMenuItem(
          key: ValueKey('$itemKeyPrefix-checkbox'),
          value: PdfFormFieldKind.checkBox,
          height: 34,
          child: Text(pdfL10n(context).propFieldTypeCheckBox),
        ),
        PopupMenuItem(
          key: ValueKey('$itemKeyPrefix-button'),
          value: PdfFormFieldKind.pushButton,
          height: 34,
          child: Text(pdfL10n(context).propFieldTypeImageButton),
        ),
      ],
      icon: showLabel ? null : Icon(_icon(type)),
      child: showLabel
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_icon(type), size: 18),
                const SizedBox(width: 8),
                Text(label),
                const Icon(Icons.arrow_drop_down),
              ],
            )
          : null,
    );
  }
}

/// A reusable column of controls that style the selected form text field's
/// text - font family, bold/italic, alignment, auto-size, size, multiline,
/// and colour - all routed through [PdfEditingController.setFormFieldStyle].
///
/// Shared by the field context-menu sheet and the toolbar style popup so
/// the surfaces stay in lock-step; the properties panel renders its own
/// panel-styled rows over the same controller calls. Renders nothing when
/// no single text field is selected.
class PdfFormFieldStyleControls extends StatefulWidget {
  const PdfFormFieldStyleControls({
    super.key,
    required this.controller,
    this.fontPicker,
  });

  final PdfEditingController controller;

  /// How "Font → Load font…" obtains a `.ttf`/`.otf` file; the entry
  /// is hidden when null.
  final PdfFontPicker? fontPicker;

  @override
  State<PdfFormFieldStyleControls> createState() =>
      _PdfFormFieldStyleControlsState();
}

class _PdfFormFieldStyleControlsState extends State<PdfFormFieldStyleControls> {
  double? _draggingSize;

  PdfEditingController get _controller => widget.controller;

  Future<void> _pickColor(String name, Color current) async {
    final picked =
        await pickEditingColor(context, _controller, initial: current);
    if (picked != null) {
      _controller.setFormFieldStyle(name, color: picked.toARGB32() & 0xFFFFFF);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final name = _controller.selectedFormFieldName;
        final style = _controller.selectedFormFieldStyle;
        if (name == null || style == null) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(child: Text(pdfL10n(context).propFont)),
              PdfFontMenuButton(
                buttonKey: const ValueKey('pdf-form-style-font-menu'),
                controller: _controller,
                fontPicker: widget.fontPicker,
                currentFont: style.font,
              ),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: Text(pdfL10n(context).propStyle)),
              FontStyleToggles(
                keyPrefix: 'pdf-form-style-font',
                font: style.font,
                onChanged: (font) =>
                    _controller.setFormFieldStyle(name, font: font),
              ),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: Text(pdfL10n(context).propAlign)),
              TextAlignToggles(
                keyPrefix: 'pdf-form-style-align',
                align: style.align,
                onChanged: (align) =>
                    _controller.setFormFieldStyle(name, align: align),
              ),
            ]),
            SwitchListTile(
              key: const ValueKey('pdf-form-style-autosize'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(pdfL10n(context).propAutoSize),
              value: style.autoSize,
              onChanged: (v) => _controller.setFormFieldStyle(name,
                  autoSize: v, fontSize: v ? null : style.size),
            ),
            if (!style.autoSize)
              Row(children: [
                Text(pdfL10n(context).propSize),
                Expanded(
                  child: Slider(
                    key: const ValueKey('pdf-form-style-size'),
                    value: (_draggingSize ?? style.size).clamp(6, 72),
                    min: 6,
                    max: 72,
                    onChanged: (v) => setState(() => _draggingSize = v),
                    onChangeEnd: (v) {
                      _controller.setFormFieldStyle(name,
                          fontSize: v.roundToDouble());
                      setState(() => _draggingSize = null);
                    },
                  ),
                ),
                PdfSliderValueField(
                  key: const ValueKey('pdf-form-style-size-input'),
                  value: _draggingSize ?? style.size,
                  min: 6,
                  max: 72,
                  fieldMin: 1,
                  fieldMax: kPdfTypedSizeMax,
                  width: 40,
                  display: (v) => '${v.round()}',
                  onSubmit: (v) {
                    _controller.setFormFieldStyle(name,
                        fontSize: v.roundToDouble());
                    setState(() => _draggingSize = null);
                  },
                ),
              ]),
            SwitchListTile(
              key: const ValueKey('pdf-form-style-multiline'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(pdfL10n(context).propMultiline),
              value: style.multiline,
              onChanged: (v) =>
                  _controller.setFormFieldStyle(name, multiline: v),
            ),
            Row(children: [
              Expanded(child: Text(pdfL10n(context).propColour)),
              InkWell(
                key: const ValueKey('pdf-form-style-color'),
                onTap: () => _pickColor(name, style.color),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: style.color,
                    border: Border.all(color: scheme.outline),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ]),
          ],
        );
      },
    );
  }
}

/// Opens the form text field's style controls in a popup anchored at
/// [position] (global coordinates) - the field-anchored surface launched
/// from the form context menu's "Text style…" entry.
Future<void> showPdfFormTextStylePopup({
  required BuildContext context,
  required Offset position,
  required PdfEditingController controller,
  PdfFontPicker? fontPicker,
}) async {
  if (!controller.canStyleSelectedFormField) return;
  await showMenu<void>(
    context: context,
    position: pdfPopupPosition(context, position),
    items: [
      PopupMenuItem<void>(
        key: const ValueKey('pdf-form-style-popup'),
        enabled: false,
        padding: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: SizedBox(
            width: 260,
            child: PdfFormFieldStyleControls(
              controller: controller,
              fontPicker: fontPicker,
            ),
          ),
        ),
      ),
    ],
  );
}
