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

/// The fonts bundled with the editor — the DejaVu trio (sans, serif and
/// monospace covering Latin, Cyrillic, Greek and more) plus a few extra
/// faces for stylistic range: Fira Sans (humanist sans), Spectral (a
/// refined serif) and Lobster (a display script). Users get a richer
/// choice than the base-14 set out of the box, and custom `.ttf`/`.otf`
/// files extend it further via a [PdfFontPicker].
const List<PdfBundledFont> pdfBundledFonts = [
  PdfBundledFont(
      'DejaVu Sans', 'packages/dart_pdf_editor/assets/fonts/DejaVuSans.ttf'),
  PdfBundledFont(
      'DejaVu Serif', 'packages/dart_pdf_editor/assets/fonts/DejaVuSerif.ttf'),
  PdfBundledFont('DejaVu Sans Mono',
      'packages/dart_pdf_editor/assets/fonts/DejaVuSansMono.ttf'),
  PdfBundledFont('Fira Sans',
      'packages/dart_pdf_editor/assets/fonts/FiraSans-Regular.ttf'),
  PdfBundledFont(
      'Spectral', 'packages/dart_pdf_editor/assets/fonts/Spectral-Regular.ttf'),
  PdfBundledFont(
      'Lobster', 'packages/dart_pdf_editor/assets/fonts/Lobster-Regular.ttf'),
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

/// A font discovered on the host platform (e.g. an OS-installed family),
/// offered as a font-menu choice. The editor can't read font files itself
/// (`dart:io` is banned in `lib/` so the package keeps running on the web),
/// so the host app discovers these and registers them in [pdfPlatformFonts]:
/// a label, the engine font family to preview the menu entry with (optional)
/// and a lazy byte loader called only when the font is chosen — its outlines
/// then embed into the document so the text renders everywhere.
class PdfPlatformFont {
  const PdfPlatformFont({
    required this.label,
    required this.loadBytes,
    this.family,
  });

  /// The name shown in the font menu.
  final String label;

  /// The engine font-family name to preview the menu entry with — a real
  /// platform family the host knows the system can draw. When null the entry
  /// previews in the menu's default face (the bytes still embed on pick).
  final String? family;

  /// Lazily loads the font's program bytes for embedding. Returns null when
  /// the font can no longer be read (e.g. it was uninstalled).
  final Future<Uint8List?> Function() loadBytes;
}

/// Platform (OS-installed) fonts offered in every font menu, on top of the
/// base-14 families and the [pdfBundledFonts]. The editor library can't
/// enumerate the host's fonts, so a host app fills this once at startup
/// (see the example/app's `loadPlatformFonts`) and every [showPdfFontMenu]
/// picks it up by default. Empty until a host populates it.
List<PdfPlatformFont> pdfPlatformFonts = const [];

List<PdfEmbeddedFont>? _fallbackFontsCache;

/// The bundled DejaVu trio (sans, serif, monospace) parsed for use as
/// content-edit fallbacks: when rewriting composite (/Type0) page text, a
/// document's own font may be subsetted and lack the glyph for a character
/// the user types, so these wide-Unicode faces draw it instead (the closest
/// serif/mono match is chosen). Loaded and cached once; a missing/corrupt
/// asset is skipped.
Future<List<PdfEmbeddedFont>> loadFallbackFonts() async {
  if (_fallbackFontsCache != null) return _fallbackFontsCache!;
  final fonts = <PdfEmbeddedFont>[];
  for (final label in const [
    'DejaVu Sans',
    'DejaVu Serif',
    'DejaVu Sans Mono'
  ]) {
    final bundled = pdfBundledFonts.where((f) => f.label == label).firstOrNull;
    if (bundled == null) continue;
    try {
      fonts.add(PdfEmbeddedFont.parse(await loadBundledFont(bundled)));
    } catch (_) {
      // skip a font that fails to load/parse
    }
  }
  return _fallbackFontsCache = fonts;
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
  } else if (controller.selectedFormFieldName case final name?) {
    controller.setFormFieldStyle(name, font: font);
  } else if (font is PdfStandardFont &&
      controller.canRestyleMeasurementCaption) {
    // a measurement caption is drawn in a base-14 face (/DA resource name),
    // so only a standard family applies — embedded fonts don't
    controller.setSelectedMeasurementCaption(font: font);
  }
}

/// A compact button showing the current font that opens [showPdfFontMenu].
///
/// Lives in the toolbar style popup and the properties panel. It is the
/// single font selector: the menu includes the base-14 families, bundled
/// fonts, platform fonts, and the optional custom-font loader.
class PdfFontMenuButton extends StatelessWidget {
  const PdfFontMenuButton({
    super.key,
    required this.controller,
    this.buttonKey,
    this.fontPicker,
    this.bundled = pdfBundledFonts,
    this.platformFonts,
    this.currentFont,
  });

  final PdfEditingController controller;

  /// Key placed on the actual tappable button. Defaults to
  /// `ValueKey('pdf-font-menu')`.
  final Key? buttonKey;

  /// How "Load font…" obtains a `.ttf`/`.otf` file; the entry is hidden
  /// when null.
  final PdfFontPicker? fontPicker;

  /// The bundled fonts offered. Defaults to [pdfBundledFonts].
  final List<PdfBundledFont> bundled;

  /// The platform fonts offered. Defaults to the host-populated
  /// [pdfPlatformFonts] registry when null.
  final List<PdfPlatformFont>? platformFonts;

  /// The font whose name should be shown on the button and whose
  /// bold/italic state should be preserved when switching base-14 family.
  /// Null means the controller's active/default font.
  final PdfTextFont? currentFont;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      key: buttonKey ?? const ValueKey('pdf-font-menu'),
      icon: const Icon(Icons.font_download_outlined, size: 18),
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 120),
        child: Text(_fontLabel(currentFont) ?? controller.activeFontLabel,
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
        platformFonts: platformFonts,
        currentFont: currentFont,
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

class _PlatformChoice extends _FontChoice {
  const _PlatformChoice(this.font);
  final PdfPlatformFont font;
}

class _LoadChoice extends _FontChoice {
  const _LoadChoice();
}

String? _fontLabel(PdfTextFont? font) {
  if (font == null) return null;
  if (font is PdfStandardFont) return font.family.label;
  if (font is PdfEmbeddedFont) return font.familyName;
  return font.resourceName;
}

class _FontEntry {
  const _FontEntry({
    required this.key,
    required this.label,
    required this.searchText,
    required this.choice,
    this.subtitle,
    this.fontFamily,
    this.package,
  });

  final Key key;
  final String label;
  final String? subtitle;
  final String searchText;
  final _FontChoice choice;
  final String? fontFamily;
  final String? package;
}

class _PdfFontPickerDialog extends StatefulWidget {
  const _PdfFontPickerDialog({required this.entries});

  final List<_FontEntry> entries;

  @override
  State<_PdfFontPickerDialog> createState() => _PdfFontPickerDialogState();
}

class _PdfFontPickerDialogState extends State<_PdfFontPickerDialog> {
  late final TextEditingController _search = TextEditingController()
    ..addListener(() => setState(() {}));

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final entries = query.isEmpty
        ? widget.entries
        : widget.entries
            .where((entry) => entry.searchText.contains(query))
            .toList();
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380, maxHeight: 500),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Font', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('pdf-font-search'),
                controller: _search,
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search fonts',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: entries.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('No fonts found',
                              key: ValueKey('pdf-font-empty')),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: entries.length,
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          return ListTile(
                            key: entry.key,
                            dense: true,
                            title: Text(
                              entry.label,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: entry.fontFamily,
                                package: entry.package,
                              ),
                            ),
                            subtitle: entry.subtitle == null
                                ? null
                                : Text(entry.subtitle!,
                                    overflow: TextOverflow.ellipsis),
                            onTap: () =>
                                Navigator.of(context).pop(entry.choice),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pops a font menu anchored at [context]'s widget and applies the pick:
/// the standard families, the [bundled] fonts, the platform fonts
/// ([platformFonts], defaulting to the host-populated [pdfPlatformFonts]
/// registry), then "Load font…" (when a [fontPicker] is given). The menu
/// is searchable. Bundled, platform and custom fonts embed into the
/// document so the text renders everywhere.
Future<void> showPdfFontMenu({
  required BuildContext context,
  required PdfEditingController controller,
  PdfFontPicker? fontPicker,
  List<PdfBundledFont> bundled = pdfBundledFonts,
  List<PdfPlatformFont>? platformFonts,
  PdfTextFont? currentFont,
  void Function(PdfTextFont font)? onSelected,
}) async {
  final platform = platformFonts ?? pdfPlatformFonts;
  final entries = <_FontEntry>[
    const _FontEntry(
      key: ValueKey('pdf-font-std-sans'),
      label: 'Sans (Helvetica)',
      subtitle: 'Standard PDF font',
      searchText: 'sans helvetica standard pdf font',
      choice: _StandardChoice(PdfStandardFontFamily.sans),
      fontFamily: 'Helvetica',
    ),
    const _FontEntry(
      key: ValueKey('pdf-font-std-serif'),
      label: 'Serif (Times)',
      subtitle: 'Standard PDF font',
      searchText: 'serif times times-roman standard pdf font',
      choice: _StandardChoice(PdfStandardFontFamily.serif),
      fontFamily: 'Times New Roman',
    ),
    const _FontEntry(
      key: ValueKey('pdf-font-std-mono'),
      label: 'Mono (Courier)',
      subtitle: 'Standard PDF font',
      searchText: 'mono monospace courier standard pdf font',
      choice: _StandardChoice(PdfStandardFontFamily.mono),
      fontFamily: 'Courier',
    ),
    for (var i = 0; i < bundled.length; i++)
      _FontEntry(
        key: ValueKey('pdf-font-bundled-$i'),
        label: bundled[i].label,
        subtitle: 'Bundled font',
        searchText: '${bundled[i].label} bundled font'.toLowerCase(),
        choice: _BundledChoice(bundled[i]),
        fontFamily: bundled[i].label,
        package: 'dart_pdf_editor',
      ),
    for (var i = 0; i < platform.length; i++)
      _FontEntry(
        key: ValueKey('pdf-font-platform-$i'),
        label: platform[i].label,
        subtitle: 'System font',
        searchText: '${platform[i].label} ${platform[i].family ?? ''} '
                'system platform font'
            .toLowerCase(),
        choice: _PlatformChoice(platform[i]),
        fontFamily: platform[i].family,
      ),
    if (fontPicker != null)
      const _FontEntry(
        key: ValueKey('pdf-font-load'),
        label: 'Load font…',
        subtitle: 'TTF or OTF file',
        searchText: 'load custom font ttf otf file upload',
        choice: _LoadChoice(),
      ),
  ];

  final choice = await showDialog<_FontChoice>(
    context: context,
    builder: (_) => _PdfFontPickerDialog(entries: entries),
  );
  if (choice == null) return;

  void apply(PdfTextFont font) {
    if (onSelected != null) {
      onSelected(font);
    } else {
      pdfApplyFont(controller, font);
    }
  }

  switch (choice) {
    case _StandardChoice(:final family):
      final current = currentFont ??
          controller.selectedTextStyle?.font ??
          controller.selectedMeasurementCaptionStyle?.font ??
          controller.fontFamily;
      apply(PdfStandardFont.styled(family,
          bold: current is PdfStandardFont && current.isBold,
          italic: current is PdfStandardFont && current.isItalic));
    case _BundledChoice(:final font):
      try {
        final bytes = await loadBundledFont(font);
        apply(PdfEmbeddedFont.parse(bytes));
      } catch (_) {
        // A missing/corrupt bundled asset just leaves the font unchanged.
      }
    case _PlatformChoice(:final font):
      try {
        final bytes = await font.loadBytes();
        if (bytes != null) {
          apply(PdfEmbeddedFont.parse(bytes));
        }
      } catch (_) {
        // An unreadable/unsupported platform font (e.g. .ttc, WOFF, or one
        // uninstalled since discovery) leaves the font unchanged.
      }
    case _LoadChoice():
      if (fontPicker == null) return;
      if (!context.mounted) return;
      final bytes = await fontPicker(context);
      if (bytes == null) return;
      if (onSelected != null) {
        try {
          onSelected(PdfEmbeddedFont.parse(bytes));
        } catch (_) {
          // Invalid custom font bytes leave the current font unchanged.
        }
      } else {
        controller.setCustomFont(bytes);
      }
  }
}
