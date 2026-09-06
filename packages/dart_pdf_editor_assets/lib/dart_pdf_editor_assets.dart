/// Optional bundled assets for `dart_pdf_editor`: the six editor fonts offered
/// by the font menu (and used as composite-text fallbacks), TeX Gyre Adventor
/// for unembedded Century Gothic / Avant Garde, and the prebuilt web worker.
///
/// These assets are declared in *this* package rather than in `dart_pdf_editor`
/// so a viewer-only application never bundles them - Flutter includes a
/// package's declared assets on every build target, so the only way to make the
/// ~1.7 MB of fonts + worker opt-in is to keep them out of the package every
/// consumer depends on.
///
/// Depend on this package and call [registerBundledEditorAssets] once at startup
/// (before opening a viewer) to get the historical full-featured behaviour:
///
/// ```dart
/// import 'package:dart_pdf_editor_assets/dart_pdf_editor_assets.dart';
///
/// void main() {
///   registerBundledEditorAssets();
///   runApp(const MyApp());
/// }
/// ```
library;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';

/// The asset-bundle package name Flutter serves this package's assets under.
const String _package = 'dart_pdf_editor_assets';

/// The editor fonts bundled with this package - the DejaVu trio (sans, serif
/// and monospace covering Latin, Cyrillic, Greek and more) plus Fira Sans
/// (humanist sans), Spectral (a refined serif) and Lobster (a display script).
///
/// Assigned to [pdfBundledFonts] by [registerBundledEditorAssets] so they show
/// up in every [showPdfFontMenu]; the DejaVu trio also backs [loadFallbackFonts]
/// for composite (/Type0) text editing.
const List<PdfBundledFont> bundledEditorFonts = <PdfBundledFont>[
  PdfBundledFont('DejaVu Sans',
      'packages/$_package/assets/fonts/DejaVuSans.ttf',
      package: _package),
  PdfBundledFont('DejaVu Serif',
      'packages/$_package/assets/fonts/DejaVuSerif.ttf',
      package: _package),
  PdfBundledFont('DejaVu Sans Mono',
      'packages/$_package/assets/fonts/DejaVuSansMono.ttf',
      package: _package),
  PdfBundledFont('Fira Sans',
      'packages/$_package/assets/fonts/FiraSans-Regular.ttf',
      package: _package),
  PdfBundledFont('Spectral',
      'packages/$_package/assets/fonts/Spectral-Regular.ttf',
      package: _package),
  PdfBundledFont('Lobster',
      'packages/$_package/assets/fonts/Lobster-Regular.ttf',
      package: _package),
];

/// The package-asset URL of the prebuilt web render worker shipped here.
///
/// Assigned to [pdfRenderWorkerScriptUrl] by [registerBundledEditorAssets] so a
/// Flutter web app gets off-main-thread page rendering without build steps.
/// Ignored on native platforms, where the worker is an isolate that needs no
/// script.
const String bundledEditorWorkerScriptUrl =
    'assets/packages/$_package/assets/web/pdf_render_worker.dart.js';

/// Registers this package's bundled assets with `dart_pdf_editor`, restoring the
/// historical full-featured defaults an app got before the assets were split
/// out.
///
/// Call once at startup, before opening a viewer:
///
/// - [fonts] (default true) sets [pdfBundledFonts] to [bundledEditorFonts], so
///   the font menu offers them and composite-text editing has fallback faces.
/// - [webWorker] (default true) points [pdfRenderWorkerScriptUrl] at this
///   package's [bundledEditorWorkerScriptUrl]. Harmless on native.
///
/// Pass `fonts: false` or `webWorker: false` to register only one group - e.g.
/// a web app that wants the worker but supplies its own font catalogue, or a
/// native app that wants the fonts but no worker asset.
void registerBundledEditorAssets({bool fonts = true, bool webWorker = true}) {
  if (fonts) {
    pdfBundledFonts = bundledEditorFonts;
  }
  if (webWorker) {
    pdfRenderWorkerScriptUrl = bundledEditorWorkerScriptUrl;
  }
}
