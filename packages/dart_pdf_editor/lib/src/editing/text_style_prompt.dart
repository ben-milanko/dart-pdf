import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart' show PdfTextStyle;

import 'editing_color_picker.dart';

/// The result of the styled-text editor ([showPdfStyledTextPrompt]): the new
/// [text] plus the [style] overrides to apply to it.
class PdfStyledTextEdit {
  const PdfStyledTextEdit(this.text, this.style);

  /// The replacement text.
  final String text;

  /// The rich-text overrides (colour, size, bold, italic). Any field left
  /// null keeps the run's existing value for that attribute.
  final PdfTextStyle style;
}

/// Signature of the prompt the content tool uses to edit a text element's
/// characters *and* its style at once. Returns null when the user cancels.
typedef PdfStyledTextPrompt = Future<PdfStyledTextEdit?> Function(
  BuildContext context, {
  required String initial,
});

/// The default [PdfStyledTextPrompt]: a Material dialog with a text field, a
/// colour swatch, a size field, and bold / italic toggles.
///
/// The toggles and colour are opt-in overrides - untouched, they leave the
/// existing appearance alone (the returned [PdfTextStyle] field stays null);
/// selecting bold or italic forces it on for the whole replacement.
Future<PdfStyledTextEdit?> showPdfStyledTextPrompt(
  BuildContext context, {
  required String initial,
}) {
  return showDialog<PdfStyledTextEdit>(
    context: context,
    builder: (context) => _StyledTextDialog(initial: initial),
  );
}

class _StyledTextDialog extends StatefulWidget {
  const _StyledTextDialog({required this.initial});

  final String initial;

  @override
  State<_StyledTextDialog> createState() => _StyledTextDialogState();
}

class _StyledTextDialogState extends State<_StyledTextDialog> {
  late final TextEditingController _text =
      TextEditingController(text: widget.initial);
  final TextEditingController _size = TextEditingController();
  bool _bold = false;
  bool _italic = false;
  Color? _color;

  @override
  void dispose() {
    _text.dispose();
    _size.dispose();
    super.dispose();
  }

  Future<void> _pickColor() async {
    final picked = await showPdfColorPicker(
      context,
      initial: _color ?? const Color(0xFF000000),
    );
    if (picked != null) setState(() => _color = picked);
  }

  void _submit() {
    final size = double.tryParse(_size.text.trim());
    final style = PdfTextStyle(
      color: _color == null ? null : (_color!.toARGB32() & 0xFFFFFF),
      fontSize: size != null && size > 0 ? size : null,
      bold: _bold ? true : null,
      italic: _italic ? true : null,
    );
    Navigator.of(context).pop(PdfStyledTextEdit(_text.text, style));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit text & style'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('pdf-styled-text-field'),
              controller: _text,
              autofocus: true,
              maxLines: 1,
              decoration: const InputDecoration(labelText: 'Text'),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                FilterChip(
                  key: const ValueKey('pdf-styled-bold'),
                  label: const Text('Bold',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  selected: _bold,
                  onSelected: (v) => setState(() => _bold = v),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  key: const ValueKey('pdf-styled-italic'),
                  label: const Text('Italic',
                      style: TextStyle(fontStyle: FontStyle.italic)),
                  selected: _italic,
                  onSelected: (v) => setState(() => _italic = v),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('pdf-styled-size'),
                    controller: _size,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Size (pt)',
                      hintText: 'keep',
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                InkWell(
                  key: const ValueKey('pdf-styled-color'),
                  onTap: _pickColor,
                  borderRadius: BorderRadius.circular(4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: _color ?? Colors.transparent,
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: _color == null
                            ? const Icon(Icons.format_color_text, size: 18)
                            : null,
                      ),
                      const SizedBox(width: 6),
                      Text(_color == null ? 'Colour' : 'Colour'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('pdf-styled-ok'),
          onPressed: _submit,
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
