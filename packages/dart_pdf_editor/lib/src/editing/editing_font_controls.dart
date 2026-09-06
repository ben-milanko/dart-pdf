import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart';

import 'editing_color_picker.dart';
import '../l10n/pdf_l10n.dart';

/// A Bold / Italic toggle pair that picks the matching base-14 variant of
/// [font]'s current family (Sans/Serif/Mono). Reports the new font - same
/// family, the toggled style - through [onChanged].
///
/// Package-internal chrome shared by the toolbar style popup and the
/// annotation properties panel; not part of the public API.
class FontStyleToggles extends StatelessWidget {
  const FontStyleToggles({
    super.key,
    required this.font,
    required this.onChanged,
    this.keyPrefix = 'pdf-font',
  });

  /// The font whose bold/italic state the toggles reflect.
  final PdfStandardFont font;

  /// Called with the variant of [font]'s family carrying the new style.
  final ValueChanged<PdfStandardFont> onChanged;

  /// Prefix for the toggle keys (`<prefix>-bold` / `<prefix>-italic`), so
  /// the toolbar and the panel get distinct ones.
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget toggle({
      required Key key,
      required String label,
      required String tooltip,
      required bool selected,
      required FontWeight weight,
      required FontStyle style,
      required VoidCallback onTap,
    }) =>
        Tooltip(
          message: tooltip,
          child: InkWell(
            key: key,
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? scheme.primary : Colors.transparent,
                border: Border.all(
                    color: selected ? scheme.primary : scheme.outline),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: weight,
                  fontStyle: style,
                  color: selected ? scheme.onPrimary : scheme.onSurface,
                ),
              ),
            ),
          ),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      toggle(
        key: ValueKey('$keyPrefix-bold'),
        label: pdfL10n(context).propBoldLetter,
        tooltip: pdfL10n(context).propBold,
        selected: font.isBold,
        weight: FontWeight.bold,
        style: FontStyle.normal,
        onTap: () => onChanged(font.withBold(!font.isBold)),
      ),
      const SizedBox(width: 8),
      toggle(
        key: ValueKey('$keyPrefix-italic'),
        label: pdfL10n(context).propItalicLetter,
        tooltip: pdfL10n(context).propItalic,
        selected: font.isItalic,
        weight: FontWeight.normal,
        style: FontStyle.italic,
        onTap: () => onChanged(font.withItalic(!font.isItalic)),
      ),
    ]);
  }
}

/// A left / center / right alignment toggle group for a free-text box,
/// reporting the chosen [PdfTextAlign] through [onChanged].
///
/// Package-internal chrome shared by the toolbar style popup and the
/// annotation properties panel; not part of the public API.
class TextAlignToggles extends StatelessWidget {
  const TextAlignToggles({
    super.key,
    required this.align,
    required this.onChanged,
    this.keyPrefix = 'pdf-text-align',
  });

  /// The alignment the group highlights.
  final PdfTextAlign align;

  /// Called with the alignment the user picked.
  final ValueChanged<PdfTextAlign> onChanged;

  /// Prefix for the toggle keys (`<prefix>-left` / `-center` / `-right`),
  /// so the toolbar and the panel get distinct ones.
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget toggle({
      required PdfTextAlign value,
      required IconData icon,
      required String tooltip,
    }) {
      final selected = value == align;
      return Tooltip(
        message: tooltip,
        child: InkWell(
          key: ValueKey('$keyPrefix-${value.name}'),
          onTap: () => onChanged(value),
          customBorder: const CircleBorder(),
          child: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? scheme.primary : Colors.transparent,
              border: Border.all(
                  color: selected ? scheme.primary : scheme.outline),
            ),
            child: Icon(
              icon,
              size: 17,
              color: selected ? scheme.onPrimary : scheme.onSurface,
            ),
          ),
        ),
      );
    }

    return Row(mainAxisSize: MainAxisSize.min, children: [
      toggle(
        value: PdfTextAlign.left,
        icon: Icons.format_align_left,
        tooltip: pdfL10n(context).propAlignLeft,
      ),
      const SizedBox(width: 8),
      toggle(
        value: PdfTextAlign.center,
        icon: Icons.format_align_center,
        tooltip: pdfL10n(context).propAlignCenter,
      ),
      const SizedBox(width: 8),
      toggle(
        value: PdfTextAlign.right,
        icon: Icons.format_align_right,
        tooltip: pdfL10n(context).propAlignRight,
      ),
    ]);
  }
}

/// One labelled colour row: a "none" swatch, a [palette] of quick picks, and
/// a custom-picker button. Reports the chosen colour (null for none) through
/// [onChanged].
///
/// Package-internal chrome shared by the toolbar style popup (Text fill /
/// Text border) and the content text-style dialog, so both look and behave
/// the same; not part of the public API.
class PdfColorSwatchRow extends StatelessWidget {
  const PdfColorSwatchRow({
    super.key,
    required this.label,
    required this.keyPrefix,
    required this.value,
    required this.palette,
    required this.onChanged,
    this.labelWidth = 86,
    this.allowNone = true,
    this.pickColor,
  });

  /// The row label (e.g. "Text fill").
  final String label;

  /// Prefix for the swatch keys (`<prefix>-none`, `<prefix>-0`, …).
  final String keyPrefix;

  /// The currently selected colour, or null when "none" is selected.
  final Color? value;

  /// The quick-pick swatches shown between "none" and the custom picker.
  final List<Color> palette;

  /// Called with the chosen colour, or null for the "none" swatch.
  final ValueChanged<Color?> onChanged;

  /// Width of the leading label column, matched to the popup's rows.
  final double labelWidth;

  /// Whether to include the leading "none" swatch. Background and border
  /// rows allow no colour; foreground text always needs one.
  final bool allowNone;

  /// Opens the full colour picker for the "More colours…" button, given
  /// the current colour, and returns the chosen colour (or null when
  /// dismissed). Defaults to a plain [showPdfColorPicker]; pass
  /// `pickEditingColor` to add the recents and document-colour grids.
  final Future<Color?> Function(BuildContext context, Color initial)? pickColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget swatch({
      required Key key,
      required Color? color,
      required bool selected,
      required VoidCallback onTap,
    }) =>
        Padding(
          // 1px keeps six swatches + the picker inside the menu's width
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: InkWell(
            key: key,
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: color ?? const Color(0xFFFFFFFF),
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? scheme.primary : scheme.outline,
                  width: selected ? 3 : 1,
                ),
              ),
              child: color == null
                  ? const CustomPaint(painter: _NoneSlashPainter())
                  : null,
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(children: [
        SizedBox(width: labelWidth, child: Text(label)),
        if (allowNone)
          swatch(
            key: ValueKey('$keyPrefix-none'),
            color: null,
            selected: value == null,
            onTap: () => onChanged(null),
          ),
        for (var i = 0; i < palette.length; i++)
          swatch(
            key: ValueKey('$keyPrefix-$i'),
            color: palette[i],
            selected: value != null &&
                (value!.toARGB32() & 0xFFFFFF) ==
                    (palette[i].toARGB32() & 0xFFFFFF),
            onTap: () => onChanged(palette[i]),
          ),
        IconButton(
          key: ValueKey('$keyPrefix-more'),
          icon: const Icon(Icons.palette_outlined, size: 18),
          tooltip: pdfL10n(context).propMoreColors,
          visualDensity: VisualDensity.compact,
          onPressed: () async {
            final initial = value ?? const Color(0xFFFFFFFF);
            final picked = pickColor != null
                ? await pickColor!(context, initial)
                : await showPdfColorPicker(context, initial: initial);
            if (picked != null) onChanged(picked);
          },
        ),
      ]),
    );
  }
}

/// Paints the diagonal slash of a "none" colour swatch.
class _NoneSlashPainter extends CustomPainter {
  const _NoneSlashPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
        Offset(3, size.height - 3),
        Offset(size.width - 3, 3),
        Paint()
          ..color = const Color(0xFFE53935)
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_NoneSlashPainter oldDelegate) => false;
}
