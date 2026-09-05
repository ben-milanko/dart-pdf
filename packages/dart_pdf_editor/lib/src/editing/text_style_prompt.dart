import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart'
    show
        PdfEmbeddedFont,
        PdfStandardFont,
        PdfStandardFontFamily,
        PdfTextFont,
        PdfTextStyle;

import '../dialog.dart';
import '../l10n/pdf_l10n.dart';
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

/// Opens the app's font menu and returns the chosen font (a standard family
/// or an embedded face), or null if cancelled. Supplied by the toolbar so the
/// styled dialog reuses the same font picker as the rest of the editor.
typedef PdfStyledFontPicker = Future<PdfTextFont?> Function(
    BuildContext context);

/// Signature of the prompt the content tool uses to edit a text element's
/// characters *and* its style at once. Returns null when the user cancels.
typedef PdfStyledTextPrompt = Future<PdfStyledTextEdit?> Function(
  BuildContext context, {
  required String initial,
  List<Color> palette,
  PdfStyledFontPicker? pickFont,
});

/// The default [PdfStyledTextPrompt]: a Material dialog that reuses the
/// toolbar's text-box style controls - the Bold/Italic [FontStyleToggles], a
/// font-size slider, and a [PdfColorSwatchRow] for the fill - above a text
/// field.
///
/// Every override is opt-in: the size, style, and colour rows leave the
/// run's existing value alone until the user touches them, so an untouched
/// dialog is a plain text replacement (all [PdfTextStyle] fields null).
///
/// [pickFont] wires the "Font" row to the editor's normal font menu (standard
/// families, bundled/platform/custom faces); when null the row falls back to a
/// Sans/Serif/Mono dropdown so the dialog still works standalone.
Future<PdfStyledTextEdit?> showPdfStyledTextPrompt(
  BuildContext context, {
  required String initial,
  List<Color> palette = defaultStyledTextPalette,
  PdfStyledFontPicker? pickFont,
}) {
  return showPdfDialog<PdfStyledTextEdit>(
    context: context,
    builder: (context) =>
        _StyledTextDialog(initial: initial, palette: palette, pickFont: pickFont),
  );
}

class _StyledTextDialog extends StatefulWidget {
  const _StyledTextDialog(
      {required this.initial, required this.palette, this.pickFont});

  final String initial;
  final List<Color> palette;
  final PdfStyledFontPicker? pickFont;

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
  PdfEmbeddedFont? _embedded;
  bool _styleTouched = false;
  double _size = 14;
  bool _sizeTouched = false;
  Color? _fill;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  // the button/dropdown label for the current font pick
  String get _fontLabel =>
      _embedded?.familyName ?? (_styleTouched ? _font.family.label : 'Keep');

  void _submit() {
    // an embedded pick takes precedence and carries its own weight/slant, so
    // the base-14 family/bold/italic only apply when no embedded font is set
    final useStd = _embedded == null && _styleTouched;
    final style = PdfTextStyle(
      color: _fill == null ? null : (_fill!.toARGB32() & 0xFFFFFF),
      fontSize: _sizeTouched ? _size : null,
      embeddedFont: _embedded,
      family: useStd ? _font.family : null,
      bold: useStd ? _font.isBold : null,
      italic: useStd ? _font.isItalic : null,
    );
    Navigator.of(context).pop(PdfStyledTextEdit(_text.text, style));
  }

  Future<void> _openFontMenu() async {
    final picked = await widget.pickFont!(context);
    if (picked == null || !mounted) return;
    setState(() {
      _styleTouched = true;
      if (picked is PdfEmbeddedFont) {
        _embedded = picked;
      } else if (picked is PdfStandardFont) {
        _embedded = null;
        _font = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(pdfL10n(context).textStyleTitle),
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
                decoration:
                    InputDecoration(labelText: pdfL10n(context).textStyleText),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 12),
              Row(children: [
                SizedBox(
                    width: 86, child: Text(pdfL10n(context).textStyleFontSize)),
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
                    _sizeTouched
                        ? '${_size.round()} pt'
                        : pdfL10n(context).textStyleKeep,
                    textAlign: TextAlign.right,
                  ),
                ),
              ]),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(children: [
                  SizedBox(
                      width: 86, child: Text(pdfL10n(context).textStyleFont)),
                  if (widget.pickFont != null)
                    OutlinedButton.icon(
                      key: const ValueKey('pdf-styled-font'),
                      icon: const Icon(Icons.font_download_outlined, size: 18),
                      label: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 150),
                        child: Text(_fontLabel,
                            overflow: TextOverflow.ellipsis, maxLines: 1),
                      ),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      onPressed: _openFontMenu,
                    )
                  else
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
                  SizedBox(
                      width: 86, child: Text(pdfL10n(context).textStyleStyle)),
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
                label: pdfL10n(context).textStyleTextFill,
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
          child: Text(pdfL10n(context).cancel),
        ),
        FilledButton(
          key: const ValueKey('pdf-styled-ok'),
          onPressed: _submit,
          child: Text(pdfL10n(context).apply),
        ),
      ],
    );
  }
}
