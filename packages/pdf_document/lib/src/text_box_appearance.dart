import 'dart:math' as math;

import 'content_writer.dart';
import 'rect.dart';

/// Shared machinery for drawing a clipped, word-wrapped, quadding-aligned
/// block of text into a form XObject.
///
/// Three appearance generators author this same shape - variable-text form
/// fields (§12.7.3.3), free-text annotations (§12.5.6.6), and the visible
/// signature box (§12.7.4.5). Each opens a text object, sets the font, places
/// the first baseline one ascent below the top, aligns each line left/centre/
/// right, and emits `Td` deltas. This module holds that common core so the
/// baseline ascent, alignment, wrap, and clip logic live - and are tested - in
/// one place; the call sites contribute their specifics (auto-size policy, /DA
/// colour operators, background/border decoration, orientation, and how a line
/// is encoded for embedded or composite fonts) as inputs.

/// Vertical placement of the wrapped block inside the layout box.
enum PdfTextBoxVAlign {
  /// First baseline one ascent below the top padding; lines march down. Used
  /// by multiline form fields, free-text annotations, and top-anchored
  /// signature panels.
  top,

  /// The whole N-line block is centred in the box - the signature name
  /// panel's `centerVertical` layout.
  centerBlock,

  /// A single line centred by its ascent within the box, clamped to the top
  /// padding - single-line form fields.
  centerLine,
}

/// One underline segment recorded while a line is laid out. Path artwork must
/// sit outside the enclosing `BT`/`ET`, so a run is collected during the text
/// loop and flushed with [pdfDrawUnderlines] afterwards.
class PdfTextUnderline {
  const PdfTextUnderline(
      this.x, this.baseline, this.width, this.fontSize, this.color);

  final double x;
  final double baseline;
  final double width;
  final double fontSize;
  final int color;
}

/// Draws the collected underline [runs] as filled rectangles just below each
/// baseline. Must be called after the text object closes.
void pdfDrawUnderlines(ContentWriter w, List<PdfTextUnderline> runs) {
  for (final run in runs) {
    final thickness = math.max(0.5, run.fontSize * 0.06);
    final y = run.baseline - run.fontSize * 0.12;
    w
      ..fillColor(run.color)
      ..rect(run.x, y, run.width, thickness)
      ..fill();
  }
}

/// The x where a line of advance [width] starts so it sits at [align] inside
/// [box], padded by [padding].
///
/// Centring cancels the padding, so a centred line is centred within the full
/// width. When [clamp] is set (form fields), a centred or right-aligned line
/// that would start left of the left padding is pinned there instead, so an
/// overlong line still begins inside the box.
double pdfTextBoxLineX(
  PdfTextAlign align,
  PdfRect box,
  double width,
  double padding, {
  bool clamp = false,
}) {
  final min = box.left + padding;
  switch (align) {
    case PdfTextAlign.left:
      return min;
    case PdfTextAlign.center:
      final x = box.left + (box.width - width) / 2;
      return clamp && x < min ? min : x;
    case PdfTextAlign.right:
      final x = box.right - padding - width;
      return clamp && x < min ? min : x;
  }
}

/// Greedy word-wrap of [text] to [maxWidth] using [measure] to size a
/// candidate line. Paragraphs (split on `\n`) always contribute at least one
/// line; a single word wider than [maxWidth] overflows onto its own line (and
/// is clipped by the appearance).
///
/// [tolerance] is the slack allowed before a line breaks. A box auto-sized to
/// its content sets its width to `lineWidth + 2*pad` and wraps at
/// `width - 2*pad`; in IEEE-754 those cancel a hair *under* the line width, so
/// a tiny tolerance keeps the last word from wrapping. Pass 0 when the box
/// width is independent of the text.
List<String> pdfWrapText(
  String text,
  double maxWidth,
  double Function(String candidate) measure, {
  double tolerance = 0,
}) {
  final lines = <String>[];
  for (final paragraph in text.split('\n')) {
    var line = '';
    for (final word in paragraph.split(' ')) {
      final candidate = line.isEmpty ? word : '$line $word';
      if (line.isNotEmpty && measure(candidate) > maxWidth + tolerance) {
        lines.add(line);
        line = word;
      } else {
        line = candidate;
      }
    }
    lines.add(line);
  }
  return lines;
}

/// Lays [lines] (already wrapped) out as a clipped, aligned block of text
/// inside [box], with the first baseline placed from [font]'s ascent, and
/// appends the operators to [writer].
///
/// This is the shared core of the form-field, free-text, and signature
/// appearance generators. The caller owns everything around it - the enclosing
/// `q`/`Q`, any page/widget orientation transform, background and border
/// decoration, and marked-content wrappers - and supplies the parts that vary:
///
/// - [measureLine] measures a line's advance for alignment (defaults to
///   `font.measure`); pass a closure that folds in character spacing or
///   horizontal scaling when the appearance uses them.
/// - [writeColor] emits the fill-colour operators (a raw /DA fragment, an
///   `rg`, plus any `Tc`/`Tz`) just after the font is selected.
/// - [emitLine] shows one line's text (defaults to [ContentWriter.showText]);
///   pass a closure that applies bidi reordering and encodes glyphs for
///   embedded or composite fonts.
/// - [underlineColor], when non-null, records an underline under every
///   non-empty line and draws them after the text object closes.
void writePdfTextBox(
  ContentWriter writer,
  PdfRect box,
  List<String> lines, {
  required PdfTextFont font,
  required double fontSize,
  required PdfTextAlign align,
  required double padding,
  required double lineHeight,
  PdfTextBoxVAlign vAlign = PdfTextBoxVAlign.top,
  bool clip = true,
  bool clampAlign = false,
  bool leading = false,
  double Function(String line)? measureLine,
  void Function(ContentWriter writer)? writeColor,
  void Function(ContentWriter writer, String line)? emitLine,
  int? underlineColor,
}) {
  final measure = measureLine ?? (String s) => font.measure(s, fontSize);
  final emit =
      emitLine ?? (ContentWriter w, String s) => w.showText(s);
  final ascentPts = fontSize * font.ascent / 1000;

  if (clip) {
    writer
      ..rect(box.left, box.bottom, box.width, box.height)
      ..clip();
  }
  writer
    ..beginText()
    ..font(font.resourceName, fontSize);
  if (leading) writer.leading(lineHeight);
  writeColor?.call(writer);

  final double firstY;
  switch (vAlign) {
    case PdfTextBoxVAlign.top:
      firstY = box.top - padding - ascentPts;
    case PdfTextBoxVAlign.centerBlock:
      final blockTop =
          box.bottom + (box.height + lines.length * lineHeight) / 2;
      firstY = blockTop - ascentPts;
    case PdfTextBoxVAlign.centerLine:
      final centered = (box.height - ascentPts) / 2;
      firstY = box.bottom + (centered < padding ? padding : centered);
  }

  final underlines = <PdfTextUnderline>[];
  var prevX = 0.0;
  var prevY = 0.0;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final width = measure(line);
    final x = pdfTextBoxLineX(align, box, width, padding, clamp: clampAlign);
    final y = firstY - i * lineHeight;
    writer.textAt(x - prevX, y - prevY);
    emit(writer, line);
    if (underlineColor != null && line.isNotEmpty) {
      underlines.add(PdfTextUnderline(x, y, width, fontSize, underlineColor));
    }
    prevX = x;
    prevY = y;
  }
  writer.endText();
  if (underlines.isNotEmpty) pdfDrawUnderlines(writer, underlines);
}

/// Emits a `cm` operator that counter-rotates content by [rotation] degrees
/// (90/180/270) about ([cx], [cy]).
///
/// A widget or annotation appearance draws its artwork the right way up in the
/// unrotated coordinate space and this transform cancels the page's display
/// rotation, so the contents stay upright. The form editor (widget space,
/// centre `w/2, h/2`) and the annotation editor (page space, the rect's
/// centre) share the matrix and pick their own centre.
void writePdfCounterRotation(
  ContentWriter w,
  double cx,
  double cy,
  int rotation,
) {
  switch (rotation) {
    case 90:
      w.concatMatrix(0, 1, -1, 0, cx + cy, cy - cx);
    case 180:
      w.concatMatrix(-1, 0, 0, -1, 2 * cx, 2 * cy);
    case 270:
      w.concatMatrix(0, -1, 1, 0, cx - cy, cx + cy);
  }
}
