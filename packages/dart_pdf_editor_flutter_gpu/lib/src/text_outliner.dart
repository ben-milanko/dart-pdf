import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart'
    show pdfFitSubstitutedPiece;
import 'package:pdf_graphics/pdf_graphics.dart';

/// Supplies vector outlines for a substituted [PdfTextRun].
///
/// Flutter does not expose glyph paths from `TextPainter`, so the accelerated
/// backend cannot retain unembedded PDF text unless the host supplies the same
/// font program its Canvas renderer uses for substitution. Returning null is
/// always safe: the whole scene remains on the exact Canvas fallback.
abstract interface class FlutterGpuTextOutliner {
  PdfTextRun? outline(PdfTextRun run);
}

/// A parsed outline font face used by [FlutterGpuTrueTypeTextOutliner].
abstract interface class FlutterGpuFontFace {
  int gidForUnicode(int codePoint);

  PdfPath? outlineForGlyph(int glyphId);

  double? advanceForGlyph(int glyphId);
}

/// A parsed TrueType `glyf` face used by [FlutterGpuTrueTypeTextOutliner].
class FlutterGpuTrueTypeFontFace implements FlutterGpuFontFace {
  FlutterGpuTrueTypeFontFace._(this.font);

  /// Parses [bytes], throwing when the selected face cannot provide TrueType
  /// `glyf` outlines. [collectionIndex] selects a face from a TTC.
  factory FlutterGpuTrueTypeFontFace(
    Uint8List bytes, {
    int collectionIndex = 0,
  }) {
    final font = TrueTypeFont.parse(
      bytes,
      collectionIndex: collectionIndex,
    );
    if (font == null) {
      throw FormatException(
        'font face $collectionIndex has no usable TrueType outlines',
      );
    }
    return FlutterGpuTrueTypeFontFace._(font);
  }

  final TrueTypeFont font;

  @override
  int gidForUnicode(int codePoint) => font.gidForUnicode(codePoint);

  @override
  PdfPath? outlineForGlyph(int glyphId) => font.outlineForGlyph(glyphId);

  @override
  double? advanceForGlyph(int glyphId) => font.advanceForGlyph(glyphId);
}

/// A parsed CFF-flavoured OpenType face, including one TTC collection entry.
class FlutterGpuOpenTypeCffFontFace implements FlutterGpuFontFace {
  FlutterGpuOpenTypeCffFontFace._(this.font);

  factory FlutterGpuOpenTypeCffFontFace(
    Uint8List bytes, {
    int collectionIndex = 0,
  }) {
    final font = OpenTypeCffFont.parse(
      bytes,
      collectionIndex: collectionIndex,
    );
    if (font == null) {
      throw FormatException(
        'font face $collectionIndex has no usable OpenType CFF outlines',
      );
    }
    return FlutterGpuOpenTypeCffFontFace._(font);
  }

  final OpenTypeCffFont font;

  @override
  int gidForUnicode(int codePoint) => font.gidForUnicode(codePoint);

  @override
  PdfPath? outlineForGlyph(int glyphId) => font.outlineForGlyph(glyphId);

  @override
  double? advanceForGlyph(int glyphId) => font.advanceForGlyph(glyphId);
}

/// Resolves the exact substitute face for one recorded text run.
///
/// The resolver should return null when it cannot prove that its bytes match
/// the face Flutter Canvas selects. In particular, bold/italic synthesis and
/// complex-script fallback should not be guessed.
typedef FlutterGpuFontFaceResolver = FlutterGpuFontFace? Function(
  PdfTextRun run,
);

/// Converts simple horizontal substituted text to retained font outlines.
///
/// PDF character offsets remain authoritative. Glyph shapes receive one
/// uniform horizontal scale—the same copy-fitting rule used by
/// `CanvasPdfDevice`—and each glyph is then fitted to the slot the PDF gives
/// it ([pdfFitSubstitutedPiece]): centred when the substitute draws it
/// narrower, squeezed when wider, untouched within the 0.02 em tolerance.
/// Complex shaping, vertical text, missing glyphs, and malformed metrics
/// return null.
class FlutterGpuTrueTypeTextOutliner implements FlutterGpuTextOutliner {
  const FlutterGpuTrueTypeTextOutliner(this.resolveFace);

  final FlutterGpuFontFaceResolver resolveFace;

  @override
  PdfTextRun? outline(PdfTextRun run) {
    if (run.glyphs != null || run.invisible) return run;
    final offsets = run.charOffsets;
    final text = run.text;
    if (text.isEmpty ||
        offsets == null ||
        offsets.length != text.length + 1 ||
        !_isPlaceableText(text)) {
      return null;
    }
    final face = resolveFace(run);
    if (face == null) return null;

    final resolved = <_ResolvedGlyph>[];
    var naturalAdvance = 0.0;
    var pdfAdvance = 0.0;
    for (var index = 0; index < text.length;) {
      final length = _runeLengthAt(text, index);
      final rune = _runeAt(text, index, length);
      // HarfBuzz treats C1 controls as default-ignorable characters: they
      // advance through the PDF's own offset table but paint no fallback box.
      // Keep them as empty placements instead of requiring a cmap glyph that
      // Canvas never draws.
      final blank = _isWhitespace(rune) || _isControl(rune);
      final glyphId = face.gidForUnicode(rune);
      PdfPath? outline;
      var glyphAdvance = 0.0;
      var glyphSlot = 0.0;
      if (!blank) {
        if (glyphId == 0) return null;
        outline = face.outlineForGlyph(glyphId);
        final advance = face.advanceForGlyph(glyphId);
        if (outline == null || advance == null || advance <= 0) return null;
        // The width the PDF gives this glyph, not the pen's step across it:
        // the step carries the run's Tc, and copy-fitting shapes to it
        // stretches a widely spaced digit to fill its gap.
        final pdfWidth = run.glyphWidthAt(index, length);
        if (pdfWidth == null) return null;
        naturalAdvance += advance;
        pdfAdvance += pdfWidth;
        glyphAdvance = advance;
        glyphSlot = pdfWidth;
      }
      resolved
          .add(_ResolvedGlyph(index, length, outline, glyphAdvance, glyphSlot));
      index += length;
    }
    final hasInk = resolved.any((glyph) => glyph.outline != null);
    if (hasInk && (naturalAdvance <= 0 || pdfAdvance <= 0)) return null;
    final xScale = hasInk ? pdfAdvance / naturalAdvance : 1.0;
    if (!xScale.isFinite || xScale <= 0) return null;

    final glyphs = <PdfGlyphPlacement>[
      for (final glyph in resolved) _place(glyph, offsets, text, xScale),
    ];
    final scaledOffsets = <double>[
      for (final offset in offsets) offset / xScale,
    ];
    return PdfTextRun(
      text: text,
      transform: PdfMatrix.scaled(xScale, 1).concat(run.transform),
      color: run.color,
      width: run.width / xScale,
      gradient: run.gradient,
      fontName: run.fontName,
      serif: run.serif,
      fontSize: run.fontSize,
      glyphs: List.unmodifiable(glyphs),
      charOffsets: List.unmodifiable(scaledOffsets),
      invisible: run.invisible,
      fill: run.fill,
      strokeColor: run.strokeColor,
      strokeWidth: run.strokeWidth,
      fillAlpha: run.fillAlpha,
      strokeAlpha: run.strokeAlpha,
      letterSpacing: run.letterSpacing / xScale,
      wordSpacing: run.wordSpacing / xScale,
      visibleWidth:
          run.visibleWidth == null ? null : run.visibleWidth! / xScale,
      leadingSpace: run.leadingSpace / xScale,
      mcid: run.mcid,
    );
  }
}

/// [glyph] placed at its PDF offset under a run scaled by [xScale], fitted
/// to the slot the PDF gives it the way `CanvasPdfDevice` fits a piece.
PdfGlyphPlacement _place(
    _ResolvedGlyph glyph, List<double> offsets, String text, double xScale) {
  var outline = glyph.outline;
  var origin = offsets[glyph.index];
  if (outline != null) {
    // In PDF em: the substitute draws the glyph `advance x xScale` wide.
    final fit =
        pdfFitSubstitutedPiece(slot: glyph.slot, drawn: glyph.advance * xScale);
    origin += fit.shift;
    if (fit.scaleX != 1) outline = _scaleX(outline, fit.scaleX);
  }
  return PdfGlyphPlacement(
    // The run transform receives xScale. Divide origins by it so
    // `S(xScale) * (offset/xScale)` lands at the original PDF offset.
    offset: origin / xScale,
    outline: outline,
    text: text.substring(glyph.index, glyph.index + glyph.length),
  );
}

/// [path] squeezed horizontally by [factor] about its own origin - the pen
/// position a glyph outline is drawn from.
PdfPath _scaleX(PdfPath path, double factor) {
  final segments = <PdfPathSegment>[];
  final reader = path.cursor();
  while (reader.moveNext()) {
    segments.add(switch (reader.verb) {
      PdfPathVerb.moveTo => PdfMoveTo(reader.x1 * factor, reader.y1),
      PdfPathVerb.lineTo => PdfLineTo(reader.x1 * factor, reader.y1),
      PdfPathVerb.cubicTo => PdfCubicTo(reader.x1 * factor, reader.y1,
          reader.x2 * factor, reader.y2, reader.x3 * factor, reader.y3),
      PdfPathVerb.close => const PdfClosePath(),
    });
  }
  return PdfPath(segments);
}

class _ResolvedGlyph {
  const _ResolvedGlyph(
      this.index, this.length, this.outline, this.advance, this.slot);

  final int index;
  final int length;
  final PdfPath? outline;

  /// The substitute's own advance for the glyph, in em; 0 when blank.
  final double advance;

  /// The width the PDF gives the glyph ([PdfTextRun.glyphWidthAt]); 0 when
  /// blank.
  final double slot;
}

int _runeLengthAt(String text, int index) {
  final first = text.codeUnitAt(index);
  if (first < 0xD800 || first > 0xDBFF || index + 1 >= text.length) return 1;
  final second = text.codeUnitAt(index + 1);
  return second >= 0xDC00 && second <= 0xDFFF ? 2 : 1;
}

int _runeAt(String text, int index, int length) {
  final first = text.codeUnitAt(index);
  if (length == 1) return first;
  return 0x10000 +
      ((first - 0xD800) << 10) +
      (text.codeUnitAt(index + 1) - 0xDC00);
}

bool _isWhitespace(int rune) =>
    (rune >= 0x09 && rune <= 0x0D) ||
    rune == 0x20 ||
    rune == 0x85 ||
    rune == 0xA0 ||
    rune == 0x1680 ||
    (rune >= 0x2000 && rune <= 0x200A) ||
    rune == 0x2028 ||
    rune == 0x2029 ||
    rune == 0x202F ||
    rune == 0x205F ||
    rune == 0x3000 ||
    rune == 0xFEFF;

bool _isControl(int rune) => rune >= 0x7F && rune <= 0x9F;

bool _isPlaceableText(String text) {
  for (var i = 0; i < text.length; i++) {
    final code = text.codeUnitAt(i);
    if (!_isPlaceableCodeUnit(code)) return false;
  }
  return true;
}

bool _isPlaceableCodeUnit(int code) =>
    (code >= 0x20 && code <= 0x2FF) ||
    (code >= 0x370 && code <= 0x482) ||
    (code >= 0x48A && code <= 0x52F) ||
    (code >= 0x2000 && code <= 0x206F) ||
    (code >= 0x20A0 && code <= 0x20CF) ||
    (code >= 0x2100 && code <= 0x214F) ||
    (code >= 0x2190 && code <= 0x2BFF) ||
    (code >= 0x3000 && code <= 0xD7AF) ||
    (code >= 0xF900 && code <= 0xFAFF) ||
    (code >= 0xFF00 && code <= 0xFFEF);
