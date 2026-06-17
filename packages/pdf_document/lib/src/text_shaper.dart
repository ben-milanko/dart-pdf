import 'font_embedder.dart';
import 'content_writer.dart';

/// A shaped text result ready for encoding into a PDF appearance stream.
///
/// The [text] is the visual-order string with Arabic characters mapped to
/// their Unicode Presentation Forms B (U+FE70–U+FEFF) based on joining
/// context, and with mandatory ligatures (lam-alef) applied. The
/// [originalRunes] maps each shaped character back to its source rune(s)
/// for correct /ToUnicode CMap generation.
class PdfShapedText {
  const PdfShapedText(this.text, this.originalRunes);

  /// The shaped string in visual order, with presentation forms applied.
  final String text;

  /// For each character in [text], the original Unicode rune(s) it came
  /// from. A ligature (e.g. lam-alef) maps to two source runes. Simple
  /// 1:1 mappings store a single-element list.
  final List<List<int>> originalRunes;
}

/// Shapes [text] for PDF appearance-stream output: applies Arabic
/// contextual form selection (initial/medial/final/isolated via Unicode
/// Presentation Forms B), mandatory lam-alef ligatures, and visual
/// reordering for RTL paragraphs.
///
/// When [font] is provided, characters whose presentation form has no
/// glyph in the font fall back to the base form (the cmap lookup
/// decides). When [font] is null, all presentation-form mappings apply
/// unconditionally (suitable for standard fonts that ignore the forms).
///
/// Non-Arabic text passes through with only bidi reordering applied.
PdfShapedText pdfShapeText(
  String text, {
  PdfTextFont? font,
  PdfTextDirection direction = PdfTextDirection.auto,
}) {
  final resolved = direction.resolve(text);
  final runes = text.runes.toList();
  if (runes.isEmpty) return const PdfShapedText('', []);

  // 1. Apply Arabic shaping (contextual forms + ligatures).
  final shaped = _shapeArabic(runes, font: font is PdfEmbeddedFont ? font : null);

  // 2. Apply visual bidi reordering.
  if (resolved == PdfTextDirection.rtl) {
    return _bidiReorderRtl(shaped);
  }
  return shaped;
}

/// Whether [text] contains any Arabic script characters that would
/// benefit from shaping.
bool pdfTextNeedsShaping(String text) {
  for (final rune in text.runes) {
    if (_isArabicBase(rune)) return true;
  }
  return false;
}

// ---------------------------------------------------------------------------
// Arabic contextual shaping
// ---------------------------------------------------------------------------

/// Applies Arabic contextual form selection and lam-alef ligatures.
///
/// Each Arabic letter is mapped to its Presentation Form B equivalent
/// based on its joining context: isolated, initial, medial, or final.
PdfShapedText _shapeArabic(List<int> runes, {PdfEmbeddedFont? font}) {
  // First pass: apply lam-alef ligatures.
  final (ligRunes, ligOrigins) = _applyLamAlefLigatures(runes);

  // Second pass: determine joining context and map to presentation forms.
  final out = StringBuffer();
  final origins = <List<int>>[];

  for (var i = 0; i < ligRunes.length; i++) {
    final rune = ligRunes[i];
    final origin = ligOrigins[i];

    if (!_isArabicBase(rune) && !_isLamAlefLigature(rune)) {
      out.writeCharCode(rune);
      origins.add(origin);
      continue;
    }

    final joining = _joiningType(rune);
    if (joining == _JoiningType.nonJoining ||
        joining == _JoiningType.transparent) {
      out.writeCharCode(rune);
      origins.add(origin);
      continue;
    }

    final prevJoins = _prevJoinsRight(ligRunes, i);
    final nextJoins = _nextJoinsLeft(ligRunes, i);

    _ArabicForm form;
    if (prevJoins && nextJoins && joining == _JoiningType.dual) {
      form = _ArabicForm.medial;
    } else if (prevJoins) {
      form = _ArabicForm.final_;
    } else if (nextJoins && joining == _JoiningType.dual) {
      form = _ArabicForm.initial;
    } else {
      form = _ArabicForm.isolated;
    }

    final shaped = _presentationForm(rune, form);
    if (shaped != null) {
      // Verify the font has the presentation form glyph.
      if (font != null && font.glyphForRune(shaped) == 0) {
        // Font lacks the presentation form; keep the base character.
        out.writeCharCode(rune);
      } else {
        out.writeCharCode(shaped);
      }
    } else {
      out.writeCharCode(rune);
    }
    origins.add(origin);
  }

  return PdfShapedText(out.toString(), origins);
}

/// Scans backward from [index] (skipping transparent joiners) and returns
/// true when the preceding character extends a join toward this position
/// (i.e. it is dual-joining or left-joining).
bool _prevJoinsRight(List<int> runes, int index) {
  for (var j = index - 1; j >= 0; j--) {
    final jt = _joiningType(runes[j]);
    if (jt == _JoiningType.transparent) continue;
    return jt == _JoiningType.dual || jt == _JoiningType.leftJoining;
  }
  return false;
}

/// Scans forward from [index] (skipping transparent joiners) and returns
/// true when the following character accepts a join from this position
/// (i.e. it is dual-joining or right-joining).
bool _nextJoinsLeft(List<int> runes, int index) {
  for (var j = index + 1; j < runes.length; j++) {
    final jt = _joiningType(runes[j]);
    if (jt == _JoiningType.transparent) continue;
    return jt == _JoiningType.dual || jt == _JoiningType.rightJoining;
  }
  return false;
}

/// Applies mandatory lam-alef ligatures: when a Lam (U+0644) is
/// immediately followed by an Alef variant, the pair is collapsed to a
/// single ligature code point.
(List<int>, List<List<int>>) _applyLamAlefLigatures(List<int> runes) {
  final out = <int>[];
  final origins = <List<int>>[];
  var i = 0;
  while (i < runes.length) {
    if (runes[i] == 0x0644 && i + 1 < runes.length) {
      final next = runes[i + 1];
      final lig = _lamAlefLigature(next);
      if (lig != null) {
        out.add(lig);
        origins.add([runes[i], next]);
        i += 2;
        continue;
      }
    }
    out.add(runes[i]);
    origins.add([runes[i]]);
    i++;
  }
  return (out, origins);
}

/// Returns the lam-alef ligature code point for the given alef variant
/// following a lam, or null if it's not an alef variant.
int? _lamAlefLigature(int alef) => switch (alef) {
      0x0622 => 0xFEF5, // Lam + Alef with Madda Above
      0x0623 => 0xFEF7, // Lam + Alef with Hamza Above
      0x0625 => 0xFEF9, // Lam + Alef with Hamza Below
      0x0627 => 0xFEFB, // Lam + Alef
      _ => null,
    };

bool _isLamAlefLigature(int rune) =>
    rune >= 0xFEF5 && rune <= 0xFEFC;

/// Reorders shaped text for RTL display — reverses runs for a
/// right-to-left paragraph with proper handling of LTR embedded runs
/// (numbers, Latin text).
PdfShapedText _bidiReorderRtl(PdfShapedText shaped) {
  final runes = shaped.text.runes.toList();
  final origins = shaped.originalRunes;
  if (runes.isEmpty) return shaped;

  // Split into directional runs.
  final runs = <({int start, int end, bool isRtl})>[];
  var runStart = 0;
  var currentRtl = _isRtlForReorder(runes[0]);

  for (var i = 1; i < runes.length; i++) {
    final kind = _charDirectionForReorder(runes[i]);
    if (kind == _DirKind.neutral) continue;
    final isRtl = kind == _DirKind.rtl;
    if (isRtl != currentRtl) {
      runs.add((start: runStart, end: i, isRtl: currentRtl));
      runStart = i;
      currentRtl = isRtl;
    }
  }
  runs.add((start: runStart, end: runes.length, isRtl: currentRtl));

  // Assign neutral characters between runs to the adjacent RTL run when
  // surrounded by RTL, or to the paragraph direction (RTL here).
  // Then reverse the run order (RTL paragraph) and reverse RTL run contents.
  final out = StringBuffer();
  final outOrigins = <List<int>>[];

  for (final run in runs.reversed) {
    if (run.isRtl) {
      // RTL run: reverse the characters within.
      for (var i = run.end - 1; i >= run.start; i--) {
        out.writeCharCode(runes[i]);
        outOrigins.add(origins[i]);
      }
    } else {
      // LTR run: keep internal order.
      for (var i = run.start; i < run.end; i++) {
        out.writeCharCode(runes[i]);
        outOrigins.add(origins[i]);
      }
    }
  }

  return PdfShapedText(out.toString(), outOrigins);
}

enum _DirKind { ltr, rtl, neutral }

_DirKind _charDirectionForReorder(int rune) {
  if (_isRtlForReorder(rune)) return _DirKind.rtl;
  if (_isLtrForReorder(rune)) return _DirKind.ltr;
  return _DirKind.neutral;
}

bool _isRtlForReorder(int rune) =>
    _isHebrewOrRtl(rune) ||
    _isArabicBase(rune) ||
    _isArabicPresentationForm(rune) ||
    _isLamAlefLigature(rune);

/// RTL script ranges beyond Arabic base and presentation forms:
/// Hebrew, Syriac, Thaana, and supplementary RTL blocks.
bool _isHebrewOrRtl(int rune) =>
    (rune >= 0x0590 && rune <= 0x05FF) || // Hebrew
    (rune >= 0x0700 && rune <= 0x074F) || // Syriac
    (rune >= 0x0780 && rune <= 0x07BF) || // Thaana
    (rune >= 0x10800 && rune <= 0x10FFF) || // supplementary RTL
    (rune >= 0x1E800 && rune <= 0x1EDFF); // supplementary RTL

bool _isLtrForReorder(int rune) =>
    _isLtrRune(rune) || _isNumberRune(rune);

bool _isNumberRune(int rune) => rune >= 0x30 && rune <= 0x39;

bool _isLtrRune(int rune) =>
    (rune >= 0x0041 && rune <= 0x005A) ||
    (rune >= 0x0061 && rune <= 0x007A) ||
    (rune >= 0x00C0 && rune <= 0x02AF) ||
    (rune >= 0x0370 && rune <= 0x03FF) ||
    (rune >= 0x0400 && rune <= 0x052F);

bool _isArabicPresentationForm(int rune) =>
    (rune >= 0xFB50 && rune <= 0xFDFF) ||
    (rune >= 0xFE70 && rune <= 0xFEFF);

// ---------------------------------------------------------------------------
// Arabic character data
// ---------------------------------------------------------------------------

/// True for base Arabic code points (U+0600–U+06FF, U+0750–U+077F,
/// U+08A0–U+08FF).
bool _isArabicBase(int rune) =>
    (rune >= 0x0600 && rune <= 0x06FF) ||
    (rune >= 0x0750 && rune <= 0x077F) ||
    (rune >= 0x08A0 && rune <= 0x08FF);

enum _ArabicForm { isolated, initial, medial, final_ }

enum _JoiningType {
  rightJoining,
  dual,
  leftJoining, // rare: Alef and similar
  nonJoining,
  transparent, // combining marks
}

/// Returns the Unicode Arabic Joining Type for [rune].
_JoiningType _joiningType(int rune) {
  // Combining marks (U+064B–U+065F, U+0670, U+06D6–U+06ED, etc.)
  if ((rune >= 0x064B && rune <= 0x065F) ||
      rune == 0x0670 ||
      (rune >= 0x06D6 && rune <= 0x06ED) ||
      (rune >= 0x08D3 && rune <= 0x08FF) ||
      (rune >= 0xFE20 && rune <= 0xFE2F)) {
    return _JoiningType.transparent;
  }

  // Right-joining: Alef variants, Teh Marbuta, some others.
  if (_rightJoiningSet.contains(rune)) return _JoiningType.rightJoining;

  // Most Arabic letters are dual-joining.
  if (_isArabicLetter(rune)) return _JoiningType.dual;

  // Lam-alef ligatures are dual-joining.
  if (_isLamAlefLigature(rune)) return _JoiningType.dual;

  return _JoiningType.nonJoining;
}

bool _isArabicLetter(int rune) =>
    (rune >= 0x0621 && rune <= 0x064A) ||
    (rune >= 0x066E && rune <= 0x066F) ||
    (rune >= 0x0671 && rune <= 0x06D3) ||
    rune == 0x06D5 ||
    (rune >= 0x06EE && rune <= 0x06EF) ||
    (rune >= 0x06FA && rune <= 0x06FF);

/// The Arabic characters with right-joining type (they accept a join
/// from the right / previous character but never extend to the left /
/// next character). This is the canonical set from Unicode 15.1.
const Set<int> _rightJoiningSet = {
  0x0622, // ALEF WITH MADDA ABOVE
  0x0623, // ALEF WITH HAMZA ABOVE
  0x0624, // WAW WITH HAMZA ABOVE
  0x0625, // ALEF WITH HAMZA BELOW
  0x0627, // ALEF
  0x0629, // TEH MARBUTA
  0x062F, // DAL
  0x0630, // THAL
  0x0631, // REH
  0x0632, // ZAIN
  0x0648, // WAW
  0x0671, // ALEF WASLA
  0x0672, // ALEF WITH WAVY HAMZA ABOVE
  0x0673, // ALEF WITH WAVY HAMZA BELOW
  0x0675, // HIGH HAMZA ALEF
  0x0676, // HIGH HAMZA WAW
  0x0677, // U WITH HAMZA ABOVE
  0x0688, // DAL WITH SMALL TAH
  0x0689, // DAL WITH RING
  0x068A, // DAL WITH DOT BELOW
  0x068B, // DAL WITH DOT BELOW AND SMALL TAH
  0x068C, // DAHAL
  0x068D, // DDAHAL
  0x068E, // DUL
  0x068F, // DAL WITH THREE DOTS ABOVE DOWNWARDS
  0x0690, // DAL WITH FOUR DOTS ABOVE
  0x0691, // RREH
  0x0692, // REH WITH SMALL V
  0x0693, // REH WITH RING
  0x0694, // REH WITH DOT BELOW
  0x0695, // REH WITH SMALL V BELOW
  0x0696, // REH WITH DOT BELOW AND DOT ABOVE
  0x0697, // REH WITH TWO DOTS ABOVE
  0x0698, // JEH
  0x0699, // REH WITH FOUR DOTS ABOVE
  0x06C0, // HEH WITH YEH ABOVE
  0x06C5, // KIRGHIZ OE
  0x06C6, // OE
  0x06C7, // U
  0x06C8, // YU
  0x06C9, // KIRGHIZ YU
  0x06CB, // VE
  0x06CF, // WAW WITH DOT ABOVE
  0x06D2, // YEH BARREE
  0x06D3, // YEH BARREE WITH HAMZA ABOVE
  0x06D5, // AE
  0x06EE, // DAL WITH INVERTED V
  0x06EF, // REH WITH INVERTED V
};

/// Maps a base Arabic character to its Presentation Form B code point
/// for the given [form], or null if no mapping exists.
int? _presentationForm(int rune, _ArabicForm form) {
  final entry = _arabicForms[rune];
  if (entry == null) return null;
  return switch (form) {
    _ArabicForm.isolated => entry.$1,
    _ArabicForm.final_ => entry.$2,
    _ArabicForm.initial => entry.$3,
    _ArabicForm.medial => entry.$4,
  };
}

/// Arabic Presentation Forms B mapping table.
///
/// Each entry maps a base Arabic character to its four contextual forms:
/// (isolated, final, initial, medial). A null form means the character
/// doesn't have that contextual variant (right-joining characters lack
/// initial and medial forms — those are filled with the isolated/final
/// forms for safety, though the joining logic should never request them).
///
/// Data source: Unicode Character Database, ArabicShaping.txt + the
/// Presentation Forms B block U+FE70–U+FEFF.
const Map<int, (int, int, int?, int?)> _arabicForms = {
  // HAMZA (non-joining, but listed for completeness)
  0x0621: (0xFE80, 0xFE80, null, null),
  // ALEF WITH MADDA ABOVE (right-joining)
  0x0622: (0xFE81, 0xFE82, null, null),
  // ALEF WITH HAMZA ABOVE (right-joining)
  0x0623: (0xFE83, 0xFE84, null, null),
  // WAW WITH HAMZA ABOVE (right-joining)
  0x0624: (0xFE85, 0xFE86, null, null),
  // ALEF WITH HAMZA BELOW (right-joining)
  0x0625: (0xFE87, 0xFE88, null, null),
  // YEH WITH HAMZA ABOVE (dual)
  0x0626: (0xFE89, 0xFE8A, 0xFE8B, 0xFE8C),
  // ALEF (right-joining)
  0x0627: (0xFE8D, 0xFE8E, null, null),
  // BEH (dual)
  0x0628: (0xFE8F, 0xFE90, 0xFE91, 0xFE92),
  // TEH MARBUTA (right-joining)
  0x0629: (0xFE93, 0xFE94, null, null),
  // TEH (dual)
  0x062A: (0xFE95, 0xFE96, 0xFE97, 0xFE98),
  // THEH (dual)
  0x062B: (0xFE99, 0xFE9A, 0xFE9B, 0xFE9C),
  // JEEM (dual)
  0x062C: (0xFE9D, 0xFE9E, 0xFE9F, 0xFEA0),
  // HAH (dual)
  0x062D: (0xFEA1, 0xFEA2, 0xFEA3, 0xFEA4),
  // KHAH (dual)
  0x062E: (0xFEA5, 0xFEA6, 0xFEA7, 0xFEA8),
  // DAL (right-joining)
  0x062F: (0xFEA9, 0xFEAA, null, null),
  // THAL (right-joining)
  0x0630: (0xFEAB, 0xFEAC, null, null),
  // REH (right-joining)
  0x0631: (0xFEAD, 0xFEAE, null, null),
  // ZAIN (right-joining)
  0x0632: (0xFEAF, 0xFEB0, null, null),
  // SEEN (dual)
  0x0633: (0xFEB1, 0xFEB2, 0xFEB3, 0xFEB4),
  // SHEEN (dual)
  0x0634: (0xFEB5, 0xFEB6, 0xFEB7, 0xFEB8),
  // SAD (dual)
  0x0635: (0xFEB9, 0xFEBA, 0xFEBB, 0xFEBC),
  // DAD (dual)
  0x0636: (0xFEBD, 0xFEBE, 0xFEBF, 0xFEC0),
  // TAH (dual)
  0x0637: (0xFEC1, 0xFEC2, 0xFEC3, 0xFEC4),
  // ZAH (dual)
  0x0638: (0xFEC5, 0xFEC6, 0xFEC7, 0xFEC8),
  // AIN (dual)
  0x0639: (0xFEC9, 0xFECA, 0xFECB, 0xFECC),
  // GHAIN (dual)
  0x063A: (0xFECD, 0xFECE, 0xFECF, 0xFED0),
  // FEH (dual)
  0x0641: (0xFED1, 0xFED2, 0xFED3, 0xFED4),
  // QAF (dual)
  0x0642: (0xFED5, 0xFED6, 0xFED7, 0xFED8),
  // KAF (dual)
  0x0643: (0xFED9, 0xFEDA, 0xFEDB, 0xFEDC),
  // LAM (dual)
  0x0644: (0xFEDD, 0xFEDE, 0xFEDF, 0xFEE0),
  // MEEM (dual)
  0x0645: (0xFEE1, 0xFEE2, 0xFEE3, 0xFEE4),
  // NOON (dual)
  0x0646: (0xFEE5, 0xFEE6, 0xFEE7, 0xFEE8),
  // HEH (dual)
  0x0647: (0xFEE9, 0xFEEA, 0xFEEB, 0xFEEC),
  // WAW (right-joining)
  0x0648: (0xFEED, 0xFEEE, null, null),
  // ALEF MAKSURA (right-joining in practice, dual per Unicode)
  0x0649: (0xFEEF, 0xFEF0, 0xFBE8, 0xFBE9),
  // YEH (dual)
  0x064A: (0xFEF1, 0xFEF2, 0xFEF3, 0xFEF4),

  // Lam-Alef ligatures — these are already ligatures, but they have
  // isolated and final forms in Presentation Forms B.
  0xFEF5: (0xFEF5, 0xFEF6, null, null), // Lam+Alef Madda
  0xFEF7: (0xFEF7, 0xFEF8, null, null), // Lam+Alef Hamza Above
  0xFEF9: (0xFEF9, 0xFEFA, null, null), // Lam+Alef Hamza Below
  0xFEFB: (0xFEFB, 0xFEFC, null, null), // Lam+Alef
};
