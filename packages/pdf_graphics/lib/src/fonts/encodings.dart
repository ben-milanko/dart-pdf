/// Glyph-name tables for simple-font encodings (ISO 32000-1 Annex D).
///
/// The tables themselves live in `pdf_document`, one layer down, because the
/// content editor there needs the same code -> glyph name -> Unicode chain to
/// read and re-encode simple-font text (`SimpleFont`). This re-export keeps
/// the font engine's own imports unchanged.
library;

export 'package:pdf_document/pdf_document.dart'
    show
        cffStandardStrings,
        glyphNameUnicode,
        standardGlyphName,
        symbolUnicode,
        winAnsiGlyphName,
        zapfDingbatsUnicode;
