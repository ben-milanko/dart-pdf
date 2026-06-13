import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart';

/// A Bold / Italic toggle pair that picks the matching base-14 variant of
/// [font]'s current family (Sans/Serif/Mono). Reports the new font — same
/// family, the toggled style — through [onChanged].
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
        label: 'B',
        tooltip: 'Bold',
        selected: font.isBold,
        weight: FontWeight.bold,
        style: FontStyle.normal,
        onTap: () => onChanged(font.withBold(!font.isBold)),
      ),
      const SizedBox(width: 8),
      toggle(
        key: ValueKey('$keyPrefix-italic'),
        label: 'I',
        tooltip: 'Italic',
        selected: font.isItalic,
        weight: FontWeight.normal,
        style: FontStyle.italic,
        onTap: () => onChanged(font.withItalic(!font.isItalic)),
      ),
    ]);
  }
}
