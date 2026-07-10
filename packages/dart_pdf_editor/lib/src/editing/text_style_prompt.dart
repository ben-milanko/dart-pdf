import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart'
    show PdfStandardFont, PdfStandardFontFamily, PdfTextStyle;

import 'editing_font_controls.dart';

/// The quick-pick colours the styled-text dialog offers by default - the
/// same set the toolbar uses. Overridden by the host's own palette when the
/// toolbar opens the dialog.
const List<Color> defaultStyledTextPalette = [
  Color(0xFFE53935), // red
  Color(0xFFFFD100), // marker yellow
  Color(0xFF43A047), // green
  Color(0xFF1E88E5), // blue
  Color(0xFF000000), // black
];

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
  List<Color> palette,
});

/// The default [PdfStyledTextPrompt]: a Material dialog that reuses the
/// toolbar's text-box style controls - the Bold/Italic [FontStyleToggles], a
/// font-size slider, and a [PdfColorSwatchRow] for the fill - above a text
/// field.
///
/// Every override is opt-in: the size, style, and colour rows leave the
/// run's existing value alone until the user touches them, so an untouched
/// dialog is a plain text replacement (all [PdfTextStyle] fields null).
Future<PdfStyledTextEdit?> showPdfStyledTextPrompt(
  BuildContext context, {
  required String initial,
  List<Color> palette = defaultStyledTextPalette,
}) {
  return showDialog<PdfStyledTextEdit>(
    context: context,
    builder: (context) => _StyledTextDialog(initial: initial, palette: palette),
  );
}

class _StyledTextDialog extends StatefulWidget {
  const _StyledTextDialog({required this.initial, required this.palette});

  final String initial;
  final List<Color> palette;

  @override
  State<_StyledTextDialog> createState() => _StyledTextDialogState();
}

class _StyledTextDialogState extends State<_StyledTextDialog> {
  late final TextEditingController _text =
      TextEditingController(text: widget.initial);

  // Overrides are opt-in: each stays null (keep the run's value) until its
  // control is touched. FontStyleToggles works on an absolute font, so a
  // separate flag records whether the style was changed at all.
  PdfStandardFont _font = PdfStandardFont.helvetica;
  bool _styleTouched = false;
  double _size = 14;
  bool _sizeTouched = false;
  Color? _fill;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final style = PdfTextStyle(
      color: _fill == null ? null : (_fill!.toARGB32() & 0xFFFFFF),
      fontSize: _sizeTouched ? _size : null,
      family: _styleTouched ? _font.family : null,
      bold: _styleTouched ? _font.isBold : null,
      italic: _styleTouched ? _font.isItalic : null,
    );
    Navigator.of(context).pop(PdfStyledTextEdit(_text.text, style));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit text & style'),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
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
              const SizedBox(height: 12),
              Row(children: [
                const SizedBox(width: 86, child: Text('Font size')),
                Expanded(
                  child: Slider(
                    key: const ValueKey('pdf-styled-size'),
                    value: _size,
                    min: 6,
                    max: 96,
                    onChanged: (v) => setState(() {
                      _size = v.roundToDouble();
                      _sizeTouched = true;
                    }),
                  ),
                ),
                SizedBox(
                  width: 52,
                  child: Text(
                    _sizeTouched ? '${_size.round()} pt' : 'keep',
                    textAlign: TextAlign.right,
                  ),
                ),
              ]),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(children: [
                  const SizedBox(width: 86, child: Text('Font')),
                  DropdownButton<PdfStandardFontFamily>(
                    key: const ValueKey('pdf-styled-family'),
                    value: _font.family,
                    isDense: true,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final family in PdfStandardFontFamily.values)
                        DropdownMenuItem(
                          value: family,
                          key: ValueKey('pdf-styled-family-${family.name}'),
                          child: Text(family.label),
                        ),
                    ],
                    onChanged: (family) {
                      if (family == null) return;
                      setState(() {
                        _font = PdfStandardFont.styled(family,
                            bold: _font.isBold, italic: _font.isItalic);
                        _styleTouched = true;
                      });
                    },
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(children: [
                  const SizedBox(width: 86, child: Text('Style')),
                  FontStyleToggles(
                    keyPrefix: 'pdf-styled',
                    font: _font,
                    onChanged: (font) => setState(() {
                      _font = font;
                      _styleTouched = true;
                    }),
                  ),
                ]),
              ),
              PdfColorSwatchRow(
                label: 'Text fill',
                keyPrefix: 'pdf-styled-fill',
                value: _fill,
                palette: widget.palette,
                onChanged: (color) => setState(() => _fill = color),
              ),
            ],
          ),
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
