/// The metric-compatible faces `dart_pdf_editor_assets` bundles for unembedded
/// PDF text, and the policy that picks one for a PDF font name.
///
/// A page that names one of the standard 14 fonts carries no font program: the
/// viewer supplies the glyphs and the advances come from the built-in AFM
/// tables (`PdfFontInfo`). Substituting a face with different advances is not a
/// small error, because the renderer places every character at the PDF's own
/// pen offset (`CanvasPdfDevice.exactSubstitutedGlyphPlacement`) so that
/// selection, search and hit boxes land on the ink: a substitute that draws a
/// glyph narrower than its slot leaves the difference as white space *inside*
/// the word. DejaVu Sans - what the fallback chain used to reach on any host
/// without a real Helvetica - draws `J` 295/1000 em where Helvetica's table
/// reserves 500, which put ~2.7pt of air after every capital J at 12pt.
///
/// The TeX Gyre families are URW's clones of the Adobe base 14 and are
/// metric-compatible with them by construction (verified against our own AFM
/// tables in `dart_pdf_editor_assets`'s `substitute_metrics_test.dart`): Heros
/// for Helvetica/Arial, Termes for Times, Cursor for Courier, and the
/// pre-existing Adventor for Century Gothic / Avant Garde. Naming them means a
/// standard-14 page is drawn with the advances it was typeset against, on every
/// platform, instead of whatever the host happens to have installed.
library;

/// The package whose asset bundle carries the substitute faces.
const String _assetsPackage = 'dart_pdf_editor_assets';

/// The open metric-compatible face used for unembedded Helvetica / Arial text.
const pdfHerosFontFamily = 'TeX Gyre Heros';

/// The open metric-compatible face used for unembedded Times text.
const pdfTermesFontFamily = 'TeX Gyre Termes';

/// The open metric-compatible face used for unembedded Courier text.
const pdfCursorFontFamily = 'TeX Gyre Cursor';

/// The open metric-compatible face used for unembedded Century Gothic and
/// Avant Garde text.
const pdfAdventorFontFamily = 'TeX Gyre Adventor';

/// Flutter's package-qualified name for the optional bundled Adventor face.
const pdfBundledAdventorFontFamily =
    'packages/$_assetsPackage/$pdfAdventorFontFamily';

/// One bundled font file, with the weight and slant it registers under.
typedef PdfSubstituteFace = ({String file, int weight, bool italic});

/// A bundled face family standing in for a group of unembedded PDF fonts.
enum PdfBundledSubstitute {
  /// URW's Helvetica clone - the substitute for Helvetica, Arial and every
  /// other unembedded font with no more specific match.
  heros(
    family: pdfHerosFontFamily,
    assetPrefix: 'TeXGyreHeros',
    systemFallbacks: ['Helvetica', 'Arial', 'Liberation Sans', 'Nimbus Sans'],
    genericFallback: 'sans-serif',
  ),

  /// URW's Times clone - the substitute for unembedded Times and serif text.
  termes(
    family: pdfTermesFontFamily,
    assetPrefix: 'TeXGyreTermes',
    systemFallbacks: [
      'Times New Roman',
      'Times',
      'Liberation Serif',
      'Nimbus Roman',
    ],
    genericFallback: 'serif',
  ),

  /// URW's Courier clone - the substitute for unembedded Courier and other
  /// monospaced text.
  cursor(
    family: pdfCursorFontFamily,
    assetPrefix: 'TeXGyreCursor',
    systemFallbacks: [
      'Courier New',
      'Courier',
      'Liberation Mono',
      'Nimbus Mono PS',
    ],
    genericFallback: 'monospace',
  ),

  /// The geometric sans clone - Century Gothic was designed to copyfit ITC
  /// Avant Garde, and Adventor extends URW Gothic L, the open metric-compatible
  /// Avant Garde replacement. Ships upright weights only; a slanted request
  /// registers the upright file and the engine obliques it, which is what the
  /// AFM tables say anyway (Avant Garde's oblique advances match its upright).
  adventor(
    family: pdfAdventorFontFamily,
    assetPrefix: 'TeXGyreAdventor',
    hasItalicFaces: false,
    systemFallbacks: [
      'Century Gothic',
      'URW Gothic L',
      'Avenir Next',
      'Futura',
    ],
    genericFallback: 'sans-serif',
  );

  const PdfBundledSubstitute({
    required this.family,
    required this.assetPrefix,
    required this.systemFallbacks,
    required this.genericFallback,
    this.hasItalicFaces = true,
  });

  /// The engine font-family name the face registers under.
  final String family;

  /// The shared prefix of this family's asset file names.
  final String assetPrefix;

  /// Host faces to try, in order, when the bundled asset isn't registered.
  final List<String> systemFallbacks;

  /// The CSS generic that ends this family's canvas2d font list.
  final String genericFallback;

  /// Whether this family ships slanted files of its own.
  final bool hasItalicFaces;

  /// Flutter's package-qualified name for the bundled face - what the renderer
  /// asks for first, so the bundled file wins over a same-named host font.
  String get packageFamily => 'packages/$_assetsPackage/$family';

  /// This family's bundled files, in the order a pubspec declares them.
  List<PdfSubstituteFace> get faces => [
        for (final italic
            in hasItalicFaces ? const [false, true] : const [false])
          for (final weight in const [400, 700])
            (
              file: assetFile(bold: weight == 700, italic: italic),
              weight: weight,
              italic: italic
            ),
      ];

  /// The bundled file closest to the requested weight and slant. A family with
  /// no slanted files answers with its upright one, to be obliqued.
  String assetFile({bool bold = false, bool italic = false}) {
    final slant = hasItalicFaces && italic;
    final suffix =
        bold ? (slant ? 'BoldItalic' : 'Bold') : (slant ? 'Italic' : 'Regular');
    return '$assetPrefix-$suffix.otf';
  }

  /// The canvas2d `font` shorthand's family list: the bundled face first, then
  /// the host faces that carry the same metrics, then the CSS generic.
  String get canvas2dFamilyList => [
        for (final name in [family, ...systemFallbacks])
          name.contains(' ') ? '"$name"' : name,
        genericFallback,
      ].join(', ');
}

/// The bundled face that stands in for [fontName].
///
/// Symbolic families (Symbol, ZapfDingbats) have no bundled clone and are not
/// special-cased here: a caller that renders them from a symbol face must test
/// for them before asking. Everything else resolves - an unembedded font we
/// know nothing about is a sans-serif until proven otherwise, exactly as the
/// substitution switch has always assumed.
PdfBundledSubstitute pdfBundledSubstituteFor(String? fontName) {
  final name = fontName ?? '';
  if (pdfUsesAdventorSubstitute(name)) return PdfBundledSubstitute.adventor;
  if (name.contains('Courier') || name.contains('Mono')) {
    return PdfBundledSubstitute.cursor;
  }
  if (name.contains('Times') || name.contains('Serif')) {
    return PdfBundledSubstitute.termes;
  }
  return PdfBundledSubstitute.heros;
}

/// Whether [fontName] belongs to the Century Gothic / Avant Garde metric
/// family.
///
/// Keeping this gate narrow avoids treating unrelated CJK families such as
/// MS Gothic as geometric Latin sans faces.
bool pdfUsesAdventorSubstitute(String? fontName) {
  final name = (fontName ?? '').toLowerCase();
  return name.contains('centurygothic') ||
      name.contains('century gothic') ||
      name.contains('avantgarde') ||
      name.contains('avant garde') ||
      name.contains('texgyreadventor') ||
      name.contains('tex gyre adventor') ||
      name.contains('urwgothic') ||
      name.contains('urw gothic');
}

/// Whether a run in [fontName] draws in a bold weight.
bool pdfSubstituteIsBold(String? fontName) => (fontName ?? '').contains('Bold');

/// Whether a run in [fontName] draws slanted.
bool pdfSubstituteIsItalic(String? fontName) {
  final name = fontName ?? '';
  return name.contains('Italic') || name.contains('Oblique');
}

/// Canvas2D font-family value for substituted [fontName].
///
/// The worker registers the bundled faces when their optional assets are
/// present (see `_loadWorkerSubstituteFonts`); a self-hosted worker without them
/// falls through to the host faces that share the same metrics, then to the CSS
/// generic.
String pdfCanvas2dSubstituteFamily(String? fontName) =>
    pdfBundledSubstituteFor(fontName).canvas2dFamilyList;
