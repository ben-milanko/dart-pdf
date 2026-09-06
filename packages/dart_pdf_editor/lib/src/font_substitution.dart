/// The open metric-compatible face used for unembedded Century Gothic and
/// Avant Garde text.
const pdfAdventorFontFamily = 'TeX Gyre Adventor';

/// Flutter's package-qualified name for the optional bundled Adventor face.
const pdfBundledAdventorFontFamily =
    'packages/dart_pdf_editor_assets/TeX Gyre Adventor';

/// Whether [fontName] belongs to the Century Gothic / Avant Garde metric
/// family.
///
/// Century Gothic was designed to copyfit ITC Avant Garde. TeX Gyre Adventor
/// extends URW Gothic L, the open metric-compatible Avant Garde replacement.
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

/// Canvas2D font-family value for substituted [fontName].
///
/// The worker registers TeX Gyre Adventor when its optional asset is present.
/// System Century Gothic remains a valid first-party match for self-hosted
/// workers, followed by geometric sans faces before the generic fallback.
String pdfCanvas2dSubstituteFamily(String? fontName) {
  final name = fontName ?? '';
  if (pdfUsesAdventorSubstitute(name)) {
    return '"$pdfAdventorFontFamily", "Century Gothic", "URW Gothic L", '
        '"Avenir Next", Futura, Helvetica';
  }
  return switch (name) {
    _ when name.contains('Courier') || name.contains('Mono') => 'Courier',
    _ when name.contains('Times') || name.contains('Serif') =>
      '"Times New Roman"',
    _ => 'Helvetica',
  };
}
