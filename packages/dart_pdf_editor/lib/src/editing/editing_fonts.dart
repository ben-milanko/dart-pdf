import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf_document/pdf_document.dart';

import 'editing_controller.dart';
import 'text_prompt.dart';

/// A font shipped with the package, embeddable without a file picker. The
/// bytes load lazily from the asset bundle ([loadBundledFont]).
class PdfBundledFont {
  const PdfBundledFont(this.label, this.assetKey);

  /// The name shown in the font menu.
  final String label;

  /// The asset bundle key (e.g.
  /// `packages/dart_pdf_editor/assets/fonts/DejaVuSans.ttf`).
  final String assetKey;
}

/// The full-Unicode fonts bundled with the editor — a sans, serif, and
/// monospace face that cover Latin, Cyrillic, Greek and more, so users get
/// a richer choice than the base-14 set out of the box (custom `.ttf`/
/// `.otf` files extend it further via a [PdfFontPicker]).
const List<PdfBundledFont> pdfBundledFonts = [
  PdfBundledFont(
      'DejaVu Sans', 'packages/dart_pdf_editor/assets/fonts/DejaVuSans.ttf'),
  PdfBundledFont(
      'DejaVu Serif', 'packages/dart_pdf_editor/assets/fonts/DejaVuSerif.ttf'),
  PdfBundledFont('DejaVu Sans Mono',
      'packages/dart_pdf_editor/assets/fonts/DejaVuSansMono.ttf'),
];

final Map<String, Uint8List> _bundledCache = {};

/// Loads (and caches) a bundled font's bytes from the asset bundle.
Future<Uint8List> loadBundledFont(PdfBundledFont font) async {
  final cached = _bundledCache[font.assetKey];
  if (cached != null) return cached;
  final data = await rootBundle.load(font.assetKey);
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  return _bundledCache[font.assetKey] = bytes;
}

/// Applies [font] to [controller]: it becomes the font new free text is
/// written in (an embedded font sets [PdfEditingController.activeFont]; a
/// standard family sets [PdfEditingController.fontFamily]) and, when a
/// single free-text box is selected, restyles it in place too.
void pdfApplyFont(PdfEditingController controller, PdfTextFont font) {
  if (font is PdfStandardFont) {
    controller.fontFamily = font;
  } else if (font is PdfEmbeddedFont) {
    controller.activeFont = font;
  }
  if (controller.restyleEditingTextSelection(font: font)) return;
  if (controller.canRestyleSelectedText) {
    controller.restyleSelectedFont(font);
  }
}

/// A compact button showing the current font that opens [showPdfFontMenu].
///
/// Lives in the toolbar style popup and the properties panel; the standard
/// families also have their own SegmentedButton there, so this is the
/// gateway to the bundled and custom (embedded) fonts.
class PdfFontMenuButton extends StatelessWidget {
  const PdfFontMenuButton({
    super.key,
    required this.controller,
    this.fontPicker,
    this.bundled = pdfBundledFonts,
  });

  final PdfEditingController controller;

  /// How "Load font…" obtains a `.ttf`/`.otf` file; the entry is hidden
  /// when null.
  final PdfFontPicker? fontPicker;

  /// The bundled fonts offered. Defaults to [pdfBundledFonts].
  final List<PdfBundledFont> bundled;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      key: const ValueKey('pdf-font-menu'),
      icon: const Icon(Icons.font_download_outlined, size: 18),
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 120),
        child: Text(controller.activeFontLabel,
            overflow: TextOverflow.ellipsis, maxLines: 1),
      ),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      onPressed: () => showPdfFontMenu(
        context: context,
        controller: controller,
        fontPicker: fontPicker,
        bundled: bundled,
      ),
    );
  }
}

/// A menu selection: a standard family, a bundled font, or the load-custom
/// action.
sealed class _FontChoice {
  const _FontChoice();
}

class _StandardChoice extends _FontChoice {
  const _StandardChoice(this.family);
  final PdfStandardFontFamily family;
}

class _BundledChoice extends _FontChoice {
  const _BundledChoice(this.font);
  final PdfBundledFont font;
}

class _LoadChoice extends _FontChoice {
  const _LoadChoice();
}

Text _fontChoiceText(String label,
        {String? fontFamily, String? package, FontWeight? weight}) =>
    Text(label,
        style: TextStyle(
          fontFamily: fontFamily,
          package: package,
          fontWeight: weight,
        ));

/// Pops a font menu anchored at [context]'s widget and applies the pick:
/// the standard families, the [bundled] fonts, then "Load font…" (when a
/// [fontPicker] is given). Bundled and custom fonts embed into the
/// document so the text renders everywhere.
Future<void> showPdfFontMenu({
  required BuildContext context,
  required PdfEditingController controller,
  PdfFontPicker? fontPicker,
  List<PdfBundledFont> bundled = pdfBundledFonts,
}) async {
  final box = context.findRenderObject() as RenderBox?;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (box == null || overlay == null) return;
  final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
  final bottomRight =
      box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay);
  final position = RelativeRect.fromRect(
      Rect.fromPoints(topLeft, bottomRight), Offset.zero & overlay.size);

  final choice = await showMenu<_FontChoice>(
    context: context,
    position: position,
    items: [
      const PopupMenuItem(
        key: ValueKey('pdf-font-std-sans'),
        value: _StandardChoice(PdfStandardFontFamily.sans),
        child:
            Text('Sans (Helvetica)', style: TextStyle(fontFamily: 'Helvetica')),
      ),
      const PopupMenuItem(
        key: ValueKey('pdf-font-std-serif'),
        value: _StandardChoice(PdfStandardFontFamily.serif),
        child: Text('Serif (Times)',
            style: TextStyle(fontFamily: 'Times New Roman')),
      ),
      const PopupMenuItem(
        key: ValueKey('pdf-font-std-mono'),
        value: _StandardChoice(PdfStandardFontFamily.mono),
        child: Text('Mono (Courier)', style: TextStyle(fontFamily: 'Courier')),
      ),
      if (bundled.isNotEmpty) const PopupMenuDivider(),
      for (var i = 0; i < bundled.length; i++)
        PopupMenuItem(
          key: ValueKey('pdf-font-bundled-$i'),
          value: _BundledChoice(bundled[i]),
          child: _fontChoiceText(bundled[i].label,
              fontFamily: bundled[i].label, package: 'dart_pdf_editor'),
        ),
      if (fontPicker != null) ...[
        const PopupMenuDivider(),
        const PopupMenuItem(
          key: ValueKey('pdf-font-load'),
          value: _LoadChoice(),
          child: Row(children: [
            Icon(Icons.upload_file_outlined, size: 18),
            SizedBox(width: 8),
            Text('Load font…'),
          ]),
        ),
      ],
    ],
  );
  if (choice == null) return;

  switch (choice) {
    case _StandardChoice(:final family):
      final current =
          controller.selectedTextStyle?.font ?? controller.fontFamily;
      pdfApplyFont(
          controller,
          PdfStandardFont.styled(family,
              bold: current.isBold, italic: current.isItalic));
    case _BundledChoice(:final font):
      try {
        final bytes = await loadBundledFont(font);
        pdfApplyFont(controller, PdfEmbeddedFont.parse(bytes));
      } catch (_) {
        // A missing/corrupt bundled asset just leaves the font unchanged.
      }
    case _LoadChoice():
      if (fontPicker == null) return;
      if (!context.mounted) return;
      final bytes = await fontPicker(context);
      if (bytes != null) controller.setCustomFont(bytes);
  }
}
