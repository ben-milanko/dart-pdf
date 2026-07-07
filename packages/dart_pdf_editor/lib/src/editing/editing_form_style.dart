import 'package:flutter/material.dart';

import 'editing_color_picker.dart';
import 'editing_controller.dart';
import 'editing_font_controls.dart';
import 'editing_fonts.dart';
import 'editing_value_field.dart';
import 'text_prompt.dart';

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
    final prefs = _controller.preferences;
    final picked = await showPdfColorPicker(context,
        initial: current,
        initialFormat: prefs.colorPickerFormat,
        onFormatChanged: (format) => prefs.colorPickerFormat = format);
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
              const Expanded(child: Text('Font')),
              PdfFontMenuButton(
                buttonKey: const ValueKey('pdf-form-style-font-menu'),
                controller: _controller,
                fontPicker: widget.fontPicker,
                currentFont: style.font,
              ),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              const Expanded(child: Text('Style')),
              FontStyleToggles(
                keyPrefix: 'pdf-form-style-font',
                font: style.font,
                onChanged: (font) =>
                    _controller.setFormFieldStyle(name, font: font),
              ),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              const Expanded(child: Text('Align')),
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
              title: const Text('Auto-size'),
              value: style.autoSize,
              onChanged: (v) => _controller.setFormFieldStyle(name,
                  autoSize: v, fontSize: v ? null : style.size),
            ),
            if (!style.autoSize)
              Row(children: [
                const Text('Size'),
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
              title: const Text('Multiline'),
              value: style.multiline,
              onChanged: (v) =>
                  _controller.setFormFieldStyle(name, multiline: v),
            ),
            Row(children: [
              const Expanded(child: Text('Colour')),
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
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  await showMenu<void>(
    context: context,
    position:
        RelativeRect.fromRect(position & Size.zero, Offset.zero & overlay.size),
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
