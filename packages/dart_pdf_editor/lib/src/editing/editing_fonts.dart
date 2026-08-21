import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:pdf_document/pdf_document.dart';

import '../dialog.dart';
import 'editing_controller.dart';
import 'text_prompt.dart';
import '../l10n/pdf_l10n.dart';

/// A font offered in the font menu without a file picker, its bytes loaded
/// lazily on pick ([loadBundledFont]).
///
/// By default the bytes come from an [assetKey] in the asset bundle, but a host
/// can instead supply raw [loadBytes] (application-provided fonts, or fonts read
/// from a source Flutter's asset bundle can't reach) - either way the outlines
/// embed into the document so the text renders everywhere.
class PdfBundledFont {
  const PdfBundledFont(this.label, this.assetKey, {this.package, this.loadBytes});

  /// The name shown in the font menu.
  final String label;

  /// The asset bundle key (e.g.
  /// `packages/dart_pdf_editor_assets/assets/fonts/DejaVuSans.ttf`). Used to
  /// load the bytes when [loadBytes] is null, and as this entry's cache key.
  final String assetKey;

  /// The package whose `fonts:` declaration registers this face with the engine
  /// for the menu-row preview (e.g. `dart_pdf_editor_assets`). Null when the
  /// face is not a package asset, in which case the row previews in the menu's
  /// default face (the bytes still embed on pick).
  final String? package;

  /// An optional loader for the font's program bytes, overriding [assetKey].
  /// Lets an app provide font bytes directly instead of declaring an asset.
  final Future<Uint8List> Function()? loadBytes;
}

/// The fonts offered in every font menu without a file picker, on top of the
/// base-14 families, the document's own fonts, and the platform fonts.
///
/// Empty by default: the bundled font catalogue ships in the optional
/// `dart_pdf_editor_assets` package, whose `registerBundledEditorAssets()` fills
/// this in at startup (the DejaVu trio, Fira Sans, Spectral and Lobster). A
/// viewer-only app that doesn't depend on that package leaves it empty - the
/// menu simply drops the "bundled" group rather than failing - and an app can
/// assign its own catalogue (see [PdfBundledFont.loadBytes] for
/// application-provided font bytes). Custom `.ttf`/`.otf` files extend any menu
/// further via a [PdfFontPicker].
List<PdfBundledFont> pdfBundledFonts = const <PdfBundledFont>[];

final Map<String, Uint8List> _bundledCache = {};

/// Loads (and caches) a bundled font's bytes, from its [PdfBundledFont.loadBytes]
/// when set, otherwise from the asset bundle key.
Future<Uint8List> loadBundledFont(PdfBundledFont font) async {
  final cached = _bundledCache[font.assetKey];
  if (cached != null) return cached;
  final loader = font.loadBytes;
  final Uint8List bytes;
  if (loader != null) {
    bytes = await loader();
  } else {
    final data = await rootBundle.load(font.assetKey);
    bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }
  return _bundledCache[font.assetKey] = bytes;
}

/// A font discovered on the host platform (e.g. an OS-installed family),
/// offered as a font-menu choice. The editor can't read font files itself
/// (`dart:io` is banned in `lib/` so the package keeps running on the web),
/// so the host app discovers these and registers them in [pdfPlatformFonts]:
/// a label, the engine font family to preview the menu entry with (optional)
/// and a lazy byte loader called only when the font is chosen - its outlines
/// then embed into the document so the text renders everywhere.
class PdfPlatformFont {
  const PdfPlatformFont({
    required this.label,
    required this.loadBytes,
    this.family,
  });

  /// The name shown in the font menu.
  final String label;

  /// The engine font-family name to preview the menu entry with - a real
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
/// asset is skipped. Returns an empty list when [pdfBundledFonts] carries no
/// DejaVu faces (a viewer that didn't register `dart_pdf_editor_assets`), which
/// just disables composite-text fallback rather than failing.
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
/// standard family sets [PdfEditingController.fontFamily]) and restyles every
/// selected free-text box too. Other selected annotation subtypes are ignored.
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
    // so only a standard family applies - embedded fonts don't
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
    this.bundled,
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

  /// The bundled fonts offered. Defaults to the [pdfBundledFonts] registry
  /// when null.
  final List<PdfBundledFont>? bundled;

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

class _DocumentChoice extends _FontChoice {
  const _DocumentChoice(this.font);

  /// A font already embedded in the open document, reparsed into a
  /// re-embeddable [PdfEmbeddedFont] - picking it needs no byte loading.
  final PdfEmbeddedFont font;
}

class _LoadChoice extends _FontChoice {
  const _LoadChoice();
}

String? _fontLabel(PdfTextFont? font) {
  if (font == null) return null;
  if (font is PdfStandardFont) return font.family.label;
  if (font is PdfEmbeddedFont) return font.displayName;
  return font.resourceName;
}

/// Family names of document fonts already registered with the engine for
/// menu previews (see [_ensureDocumentFontPreview]), so each embeds once.
final Set<String> _documentPreviewFamilies = <String>{};

/// The basic Latin alphabet and digits a font must fully cover to be typed
/// freely. A document font is usually a subset carrying only the glyphs the
/// file already draws (see [PdfEmbeddedFont.canRender]); one that can't draw
/// all of these is flagged "limited" in the menu, because new text typed in
/// it would drop the characters the subset lacks.
const String _typeableProbe = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    'abcdefghijklmnopqrstuvwxyz0123456789';

/// Registers [font]'s program bytes with the engine under a private family
/// name so a menu entry can preview it in its own face, and returns that
/// name (null when the engine can't load it, e.g. in a headless test). The
/// name is stable per PostScript name and cached, so repeated menu opens
/// don't re-register the same face.
Future<String?> _ensureDocumentFontPreview(PdfEmbeddedFont font) async {
  final family = 'pdf-doc-font::${font.postScriptName}';
  if (_documentPreviewFamilies.contains(family)) return family;
  try {
    await (FontLoader(family)
          ..addFont(Future.value(ByteData.sublistView(font.fontBytes))))
        .load();
    _documentPreviewFamilies.add(family);
    return family;
  } catch (_) {
    return null; // preview only - the font still embeds fine on pick
  }
}

/// Bundled font labels already registered with the engine for menu previews
/// (see [_ensureBundledFontPreview]), so each registers once per session.
final Set<String> _bundledPreviewFamilies = <String>{};

/// Registers a bundled font's program bytes with the engine under its own
/// label so its menu row previews in that face, returning the family name
/// (null when the bytes can't load or the engine can't register them, e.g. a
/// headless test - the row then previews in the default UI face and the font
/// still embeds fine on pick).
///
/// The bundled faces used to be declared in `dart_pdf_editor_assets`'s pubspec
/// `fonts:` block, which registered every one of them at startup (a real
/// fetch-and-parse before the first frame under CanvasKit web) for previews
/// most sessions never open. Registering here, on first font-menu open, keeps
/// that cost off cold start. DejaVu Sans stays pubspec-declared - the renderer
/// names it as a script fallback and needs it from the first paint - and
/// re-registering it under its bare label here is harmless.
Future<String?> _ensureBundledFontPreview(PdfBundledFont font) async {
  final family = font.label;
  if (_bundledPreviewFamilies.contains(family)) return family;
  try {
    final bytes = await loadBundledFont(font);
    await (FontLoader(family)
          ..addFont(Future.value(ByteData.sublistView(bytes))))
        .load();
    _bundledPreviewFamilies.add(family);
    return family;
  } catch (_) {
    return null; // preview only - the font still embeds fine on pick
  }
}

class _FontEntry {
  const _FontEntry({
    required this.key,
    required this.label,
    required this.searchText,
    required this.choice,
    this.subtitle,
    this.fontFamily,
    this.bundledFont,
    this.recentKey,
    this.section,
    this.limited = false,
  });

  final Key key;
  final String label;
  final String? subtitle;
  final String searchText;
  final _FontChoice choice;

  /// The engine font-family name to preview this row in, if one is registered.
  /// For bundled fonts this fills in lazily once [bundledFont] registers (see
  /// [_PdfFontPickerDialogState]); null previews in the default UI face.
  final String? fontFamily;

  /// The bundled face this row offers, when it is one. The picker dialog
  /// registers it with the engine on open (off the cold-start path) to preview
  /// the row in its own face; null for every non-bundled row.
  final PdfBundledFont? bundledFont;

  /// Whether this is a document subset font that can't cover the basic Latin
  /// alphabet, so typing new text in it would drop unavailable characters -
  /// the menu flags it with a caption and a warning icon.
  final bool limited;

  /// The opaque key this entry is remembered under in the "Recently used"
  /// group (see [PdfEditingPreferences.recentFonts]); null for entries that
  /// aren't tracked as recents (the "Load font…" action).
  final String? recentKey;

  /// The section header this entry is grouped under in the menu ("In this
  /// document", "All fonts"); null groups it with the preceding entry.
  final String? section;
}

class _PdfFontPickerDialog extends StatefulWidget {
  const _PdfFontPickerDialog({required this.entries, this.recent = const []});

  /// The full font catalogue (standard, document, bundled, platform, load).
  final List<_FontEntry> entries;

  /// The "Recently used" group, newest first, shown above the catalogue
  /// while the search box is empty. Distinct keys from their catalogue
  /// twins so both can appear at once.
  final List<_FontEntry> recent;

  @override
  State<_PdfFontPickerDialog> createState() => _PdfFontPickerDialogState();
}

class _PdfFontPickerDialogState extends State<_PdfFontPickerDialog> {
  late final TextEditingController _search = TextEditingController()
    ..addListener(() => setState(() {}));

  /// Bundled preview families resolved for this open, keyed by font label.
  /// Seeded synchronously from the cache and filled in as each lazy
  /// registration completes, so the dialog appears immediately and each
  /// bundled row swaps into its own face without ever blocking the open.
  final Map<String, String> _bundledPreview = {};

  @override
  void initState() {
    super.initState();
    _registerBundledPreviews();
  }

  /// Registers the bundled faces this menu offers with the engine so their
  /// rows can preview in their own face. Already-registered faces resolve
  /// synchronously (an instant re-open); the rest register in the background
  /// and [setState] their row when ready. Never awaited by [showPdfFontMenu],
  /// which is what keeps the ~1.85 MB of bundled parsing off the click that
  /// opens the dialog (and off cold start).
  void _registerBundledPreviews() {
    final fonts = <String, PdfBundledFont>{};
    for (final entry in [...widget.entries, ...widget.recent]) {
      final font = entry.bundledFont;
      if (font != null) fonts[font.label] = font;
    }
    for (final font in fonts.values) {
      if (_bundledPreviewFamilies.contains(font.label)) {
        _bundledPreview[font.label] = font.label; // already registered
        continue;
      }
      _ensureBundledFontPreview(font).then((family) {
        if (family != null && mounted) {
          setState(() => _bundledPreview[font.label] = family);
        }
      });
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    // A flat list of rows: a String is a section header, a _FontEntry a
    // tappable font. While the query is empty the list is grouped under
    // section headers ("Recently used", then each entry's own section);
    // searching flattens it, filtering the whole catalogue with no headers.
    final rows = <Object>[];
    if (query.isEmpty) {
      if (widget.recent.isNotEmpty) {
        rows.add(pdfL10n(context).propRecentlyUsed);
        rows.addAll(widget.recent);
      }
      String? lastSection;
      for (final entry in widget.entries) {
        if (entry.section != null && entry.section != lastSection) {
          rows.add(entry.section!);
          lastSection = entry.section;
        }
        rows.add(entry);
      }
    } else {
      rows.addAll(
          widget.entries.where((entry) => entry.searchText.contains(query)));
    }
    final hasEntries = rows.any((row) => row is _FontEntry);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380, maxHeight: 500),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(pdfL10n(context).propFont,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('pdf-font-search'),
                controller: _search,
                autofocus: true,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search),
                  hintText: pdfL10n(context).propSearchFonts,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: !hasEntries
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(pdfL10n(context).propNoFontsFound,
                              key: const ValueKey('pdf-font-empty')),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: rows.length,
                        itemBuilder: (context, index) {
                          final row = rows[index];
                          if (row is String) return _sectionHeader(context, row);
                          final entry = row as _FontEntry;
                          // Bundled rows preview in the family the dialog
                          // registered on open (once ready); everything else
                          // uses the family resolved when the entry was built.
                          final previewFamily = entry.bundledFont != null
                              ? _bundledPreview[entry.bundledFont!.label]
                              : entry.fontFamily;
                          return ListTile(
                            key: entry.key,
                            dense: true,
                            title: Text(
                              entry.label,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: previewFamily,
                              ),
                            ),
                            subtitle: entry.subtitle == null
                                ? null
                                : Text(entry.subtitle!,
                                    overflow: TextOverflow.ellipsis),
                            trailing: entry.limited
                                ? Tooltip(
                                    message:
                                        pdfL10n(context).propFontSubsetTooltip,
                                    child: Icon(
                                      Icons.warning_amber_rounded,
                                      size: 18,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outline,
                                    ),
                                  )
                                : null,
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

  Widget _sectionHeader(BuildContext context, String label) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Pops a font menu anchored at [context]'s widget and applies the pick:
/// the standard families, the fonts already embedded in the open document
/// ([documentFonts], defaulting to [PdfEditingController.documentFonts]),
/// the [bundled] fonts, the platform fonts ([platformFonts], defaulting to
/// the host-populated [pdfPlatformFonts] registry), then "Load font…" (when
/// a [fontPicker] is given). Recently-picked fonts head the list in a
/// "Recently used" group. The search field is focused on open and the menu
/// is searchable. Bundled, platform, document and custom fonts embed into
/// the document so the text renders everywhere.
Future<void> showPdfFontMenu({
  required BuildContext context,
  required PdfEditingController controller,
  PdfFontPicker? fontPicker,
  List<PdfBundledFont>? bundled,
  List<PdfPlatformFont>? platformFonts,
  List<PdfEmbeddedFont>? documentFonts,
  PdfTextFont? currentFont,
  void Function(PdfTextFont font)? onSelected,
}) async {
  final bundledFonts = bundled ?? pdfBundledFonts;
  final platform = platformFonts ?? pdfPlatformFonts;
  final inDocument = documentFonts ?? controller.documentFonts;

  // Register each document font's outlines with the engine (best-effort) so
  // its menu row can preview in its own face. Only fonts that can actually
  // draw their whole name get a preview: document fonts are usually subsets
  // whose unused glyphs were stripped (the cmap survives but the outline is
  // empty), so previewing their name would drop letters - those render in the
  // legible UI face instead. A font that fails to register also falls back.
  // A document subset that can't cover the basic alphabet can only type the
  // characters the file already used, so flag it "limited".
  final limited = [for (final f in inDocument) !f.canRender(_typeableProbe)];
  final previewFamilies = <int, String>{};
  await Future.wait([
    for (var i = 0; i < inDocument.length; i++)
      if (inDocument[i].canRender(inDocument[i].displayName))
        _ensureDocumentFontPreview(inDocument[i]).then((family) {
          if (family != null) previewFamilies[i] = family;
        }),
  ]);
  if (!context.mounted) return;

  final entries = <_FontEntry>[
    // Document fonts head the catalogue in their own "In this document"
    // section, previewed in their own face and shown by their real family
    // name (subset tag stripped).
    for (var i = 0; i < inDocument.length; i++)
      _FontEntry(
        key: ValueKey('pdf-font-document-$i'),
        label: inDocument[i].displayName,
        subtitle: limited[i] ? pdfL10n(context).propLimitedCharacters : null,
        searchText: '${inDocument[i].displayName} '
                '${inDocument[i].familyName} ${inDocument[i].postScriptName} '
                'document embedded font'
            .toLowerCase(),
        choice: _DocumentChoice(inDocument[i]),
        fontFamily: previewFamilies[i],
        recentKey: 'doc:${inDocument[i].postScriptName}',
        section: pdfL10n(context).propSectionInThisDocument,
        limited: limited[i],
      ),
    _FontEntry(
      key: const ValueKey('pdf-font-std-sans'),
      label: 'Sans (Helvetica)',
      subtitle: pdfL10n(context).propStandardPdfFont,
      searchText: 'sans helvetica standard pdf font',
      choice: const _StandardChoice(PdfStandardFontFamily.sans),
      fontFamily: 'Helvetica',
      recentKey: 'std:sans',
      section: pdfL10n(context).propSectionAllFonts,
    ),
    _FontEntry(
      key: const ValueKey('pdf-font-std-serif'),
      label: 'Serif (Times)',
      subtitle: pdfL10n(context).propStandardPdfFont,
      searchText: 'serif times times-roman standard pdf font',
      choice: const _StandardChoice(PdfStandardFontFamily.serif),
      fontFamily: 'Times New Roman',
      recentKey: 'std:serif',
      section: pdfL10n(context).propSectionAllFonts,
    ),
    _FontEntry(
      key: const ValueKey('pdf-font-std-mono'),
      label: 'Mono (Courier)',
      subtitle: pdfL10n(context).propStandardPdfFont,
      searchText: 'mono monospace courier standard pdf font',
      choice: const _StandardChoice(PdfStandardFontFamily.mono),
      fontFamily: 'Courier',
      recentKey: 'std:mono',
      section: pdfL10n(context).propSectionAllFonts,
    ),
    for (var i = 0; i < bundledFonts.length; i++)
      _FontEntry(
        key: ValueKey('pdf-font-bundled-$i'),
        label: bundledFonts[i].label,
        subtitle: pdfL10n(context).propBundledFont,
        searchText: '${bundledFonts[i].label} bundled font'.toLowerCase(),
        choice: _BundledChoice(bundledFonts[i]),
        // Seed the preview face from the cache so a re-open is instant; a
        // first open shows the default face and the dialog swaps it in as the
        // lazy registration completes (see [_PdfFontPickerDialogState]).
        fontFamily: _bundledPreviewFamilies.contains(bundledFonts[i].label)
            ? bundledFonts[i].label
            : null,
        bundledFont: bundledFonts[i],
        recentKey: 'bundled:${bundledFonts[i].label}',
        section: pdfL10n(context).propSectionAllFonts,
      ),
    for (var i = 0; i < platform.length; i++)
      _FontEntry(
        key: ValueKey('pdf-font-platform-$i'),
        label: platform[i].label,
        subtitle: pdfL10n(context).propSystemFont,
        searchText: '${platform[i].label} ${platform[i].family ?? ''} '
                'system platform font'
            .toLowerCase(),
        choice: _PlatformChoice(platform[i]),
        fontFamily: platform[i].family,
        recentKey: 'platform:${platform[i].label}',
        section: pdfL10n(context).propSectionAllFonts,
      ),
    if (fontPicker != null)
      _FontEntry(
        key: const ValueKey('pdf-font-load'),
        label: pdfL10n(context).propLoadFont,
        subtitle: pdfL10n(context).propLoadFontSubtitle,
        searchText: 'load custom font ttf otf file upload',
        choice: const _LoadChoice(),
        section: pdfL10n(context).propSectionAllFonts,
      ),
  ];

  // Resolve the persisted recent keys back to live catalogue entries, newest
  // first, giving each a distinct key so it can sit above its twin. Keys with
  // no current match (e.g. a document font from a since-closed file) drop out.
  final byRecentKey = <String, _FontEntry>{};
  for (final entry in entries) {
    if (entry.recentKey case final key?) byRecentKey.putIfAbsent(key, () => entry);
  }
  final recent = <_FontEntry>[];
  for (final key in controller.preferences.recentFonts) {
    final match = byRecentKey[key];
    if (match == null) continue;
    recent.add(_FontEntry(
      key: ValueKey('pdf-font-recent-${recent.length}'),
      label: match.label,
      subtitle: match.subtitle,
      searchText: match.searchText,
      choice: match.choice,
      fontFamily: match.fontFamily,
      bundledFont: match.bundledFont,
      recentKey: match.recentKey,
      section: match.section,
      limited: match.limited,
    ));
  }

  final choice = await showPdfDialog<_FontChoice>(
    context: context,
    builder: (_) => _PdfFontPickerDialog(entries: entries, recent: recent),
  );
  if (choice == null) return;

  void apply(PdfTextFont font) {
    if (onSelected != null) {
      onSelected(font);
    } else {
      pdfApplyFont(controller, font);
    }
  }

  // Records the pick as the newest recent, so the next open floats it up.
  void noteRecent(String? key) {
    if (key != null) controller.preferences.noteRecentFont(key);
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
      noteRecent('std:${family.name}');
    case _DocumentChoice(:final font):
      apply(font);
      noteRecent('doc:${font.postScriptName}');
    case _BundledChoice(:final font):
      try {
        final bytes = await loadBundledFont(font);
        apply(PdfEmbeddedFont.parse(bytes));
        noteRecent('bundled:${font.label}');
      } catch (_) {
        // A missing/corrupt bundled asset just leaves the font unchanged.
      }
    case _PlatformChoice(:final font):
      try {
        final bytes = await font.loadBytes();
        if (bytes != null) {
          apply(PdfEmbeddedFont.parse(bytes));
          noteRecent('platform:${font.label}');
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
