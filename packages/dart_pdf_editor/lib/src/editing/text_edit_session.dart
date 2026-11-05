import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:pdf_document/pdf_document.dart';

import 'editing_controller.dart' show PdfEditTool;

/// The character style the inline text editor types with: one run's font,
/// size (points), colour and underline.
@immutable
class PdfTextEditStyle {
  const PdfTextEditStyle(
      {required this.font,
      required this.size,
      required this.color,
      this.underline = false});

  final PdfTextFont font;
  final double size;
  final Color color;
  final bool underline;

  /// This style with the given fields replaced. [color] is 0xRRGGBB.
  PdfTextEditStyle merge(
          {PdfTextFont? font, double? size, int? color, bool? underline}) =>
      PdfTextEditStyle(
        font: font ?? this.font,
        size: size ?? this.size,
        color: color == null ? this.color : Color(0xFF000000 | color),
        underline: underline ?? this.underline,
      );

  /// [text] as a free-text run in this style.
  PdfFreeTextRun toRun(String text) => PdfFreeTextRun(text,
      font: font,
      fontSize: size,
      color: color.toARGB32() & 0xFFFFFF,
      underline: underline);

  /// Whether [other] draws the same glyphs: same face (by identity, as the
  /// editor's runs carry the very font objects the menus hand out), size,
  /// colour and underline.
  bool sameAs(PdfTextEditStyle other) =>
      identical(font, other.font) &&
      size == other.size &&
      color == other.color &&
      underline == other.underline;
}

/// One styled range of a [PdfTextEditBuffer], in UTF-16 offsets.
@immutable
class PdfTextEditStyleRange {
  const PdfTextEditStyleRange(this.start, this.end, this.style);

  final int start;
  final int end;
  final PdfTextEditStyle style;
}

/// How the inline editor turns a styled range into a Flutter span style -
/// supplied by the overlay, which knows the preview font families.
typedef PdfTextEditSpanStyler = TextStyle Function(PdfTextEditStyle style,
    {required double scale, double height, double? letterSpacing});

/// The inline editor's text and its rich runs: a [TextEditingController]
/// whose style ranges follow their characters through every edit.
///
/// [defaultStyle] is what unstyled text (and the next character typed) is
/// drawn in; ranges override it per character.
class PdfTextEditBuffer extends TextEditingController {
  PdfTextEditBuffer();

  PdfTextEditStyle defaultStyle = const PdfTextEditStyle(
      font: PdfStandardFont.helvetica, size: 14, color: Color(0xFF000000));

  /// View pixels per point, for the live preview.
  double scale = 1;

  /// The box-level line-height multiplier and character spacing (already in
  /// view pixels) the styled span previews, so the live text matches the
  /// committed appearance's leading and Tc.
  double previewLineHeight = 1.2;
  double previewLetterSpacing = 0;

  /// Maps a range's style to the span the field paints; without one the
  /// ranges paint unstyled.
  PdfTextEditSpanStyler? spanStyler;

  final List<PdfTextEditStyleRange> _ranges = [];

  /// The text the style ranges are indexed against. Every edit (typing,
  /// backspace, paste) shifts the ranges so a run keeps following its own
  /// characters instead of the absolute offsets sliding under it.
  String _rangeText = '';

  /// Suppresses range remapping while [seedRuns] assigns text and ranges
  /// together (the ranges are already correct for the new text).
  bool _remapRanges = true;

  /// The style ranges, merged and sorted.
  List<PdfTextEditStyleRange> get ranges => List.unmodifiable(_ranges);

  @override
  set value(TextEditingValue newValue) {
    if (_remapRanges && _ranges.isNotEmpty && newValue.text != _rangeText) {
      _shiftRanges(_rangeText, newValue.text);
    }
    _rangeText = newValue.text;
    super.value = newValue;
  }

  /// Re-maps every style range across the edit that turned [before] into
  /// [after], so a run stays glued to its characters. The changed span is
  /// the region between the common prefix and common suffix; text before it
  /// is untouched, text after it shifts by the length delta, and text
  /// inserted inside a run extends that run.
  void _shiftRanges(String before, String after) {
    var prefix = 0;
    final minLen = math.min(before.length, after.length);
    while (prefix < minLen && before[prefix] == after[prefix]) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < minLen - prefix &&
        before[before.length - 1 - suffix] ==
            after[after.length - 1 - suffix]) {
      suffix++;
    }
    final changeStart = prefix;
    final oldChangeEnd = before.length - suffix;
    final delta = after.length - before.length;
    int mapOffset(int o) {
      if (o <= changeStart) return o;
      if (o >= oldChangeEnd) return o + delta;
      return changeStart; // inside a replaced span - collapse to its start
    }

    final next = <PdfTextEditStyleRange>[];
    for (final range in _ranges) {
      final start = mapOffset(range.start);
      final end = mapOffset(range.end);
      if (start < end) {
        next.add(PdfTextEditStyleRange(start, end, range.style));
      }
    }
    _ranges
      ..clear()
      ..addAll(_mergeRanges(next));
  }

  /// Drops every range and types in [style].
  void resetStyles(PdfTextEditStyle style) {
    defaultStyle = style;
    _ranges.clear();
  }

  /// Seeds the editor from a box's persisted per-run styling (its /RC):
  /// sets [text] and a style range per run so reopening a mixed-format
  /// box shows its bold/italic/colour, not a flattened single style.
  /// [fallback] is the typing default (the box's flat /DA) for text added
  /// afterwards. Runs with non-base-14 fonts keep their [PdfTextFont].
  void seedRuns(List<PdfFreeTextRun> runs, PdfTextEditStyle fallback) {
    defaultStyle = fallback;
    final buffer = StringBuffer();
    final ranges = <PdfTextEditStyleRange>[];
    var offset = 0;
    for (final run in runs) {
      if (run.text.isEmpty) continue;
      final start = offset;
      buffer.write(run.text);
      offset += run.text.length;
      ranges.add(PdfTextEditStyleRange(
          start,
          offset,
          PdfTextEditStyle(
              font: run.font,
              size: run.fontSize,
              color: Color(0xFF000000 | (run.color & 0xFFFFFF)),
              underline: run.underline)));
    }
    _ranges
      ..clear()
      ..addAll(_mergeRanges(ranges));
    // assigning text notifies listeners and rebuilds the styled span; the
    // ranges are already correct for the new text, so skip the edit remap
    _remapRanges = false;
    text = buffer.toString();
    _remapRanges = true;
  }

  bool get hasRichStyles => _ranges.isNotEmpty;

  /// The largest font size across the default style and every run - the
  /// strut size the inline editor pins line height to, so line spacing
  /// stays font-independent (matching the committed appearance's leading)
  /// instead of jumping when a run's font changes.
  double get maxStyleSize {
    var largest = defaultStyle.size;
    for (final range in _ranges) {
      if (range.style.size > largest) largest = range.style.size;
    }
    return largest;
  }

  /// The tallest ascent (in points) across the default style and every run -
  /// how far below the text area's top the appearance writes the first
  /// baseline.
  double get maxStyleAscent {
    double ascentOf(PdfTextEditStyle style) =>
        style.size * style.font.ascent / 1000;
    var largest = ascentOf(defaultStyle);
    for (final range in _ranges) {
      largest = math.max(largest, ascentOf(range.style));
    }
    return largest;
  }

  /// Restyles the characters [selection] covers, keeping each character's
  /// own fields the call leaves null. A collapsed selection is a no-op.
  void applyStyle(TextSelection selection,
      {PdfTextFont? font, double? size, int? color, bool? underline}) {
    if (!selection.isValid || selection.isCollapsed) return;
    final start = math.max(0, math.min(selection.start, selection.end));
    final end = math.min(text.length, math.max(selection.start, selection.end));
    if (start >= end) return;
    final next = <PdfTextEditStyleRange>[];
    for (final range in _ranges) {
      if (range.end <= start || range.start >= end) {
        next.add(range);
        continue;
      }
      if (range.start < start) {
        next.add(PdfTextEditStyleRange(range.start, start, range.style));
      }
      if (range.end > end) {
        next.add(PdfTextEditStyleRange(end, range.end, range.style));
      }
    }
    // split the selection into runs of already-uniform style so underlining
    // (or any per-char toggle) keeps each character's own font/size/colour
    var cursor = start;
    while (cursor < end) {
      final runStyle = styleAt(cursor);
      var runEnd = cursor + 1;
      while (runEnd < end && styleAt(runEnd).sameAs(runStyle)) {
        runEnd++;
      }
      next.add(PdfTextEditStyleRange(
          cursor,
          runEnd,
          runStyle.merge(
              font: font, size: size, color: color, underline: underline)));
      cursor = runEnd;
    }
    _ranges
      ..clear()
      ..addAll(_mergeRanges(next));
    notifyListeners();
  }

  /// The text as free-text runs, unstyled gaps in [defaultStyle].
  List<PdfFreeTextRun> toPdfRuns() {
    final value = text;
    if (value.isEmpty) return const [];
    final ranges = _mergeRanges([
      for (final range in _ranges)
        if (range.start < value.length && range.end > 0)
          PdfTextEditStyleRange(range.start.clamp(0, value.length),
              range.end.clamp(0, value.length), range.style)
    ]);
    final result = <PdfFreeTextRun>[];
    var offset = 0;
    for (final range in ranges) {
      if (offset < range.start) {
        result.add(defaultStyle.toRun(value.substring(offset, range.start)));
      }
      result.add(range.style.toRun(value.substring(range.start, range.end)));
      offset = range.end;
    }
    if (offset < value.length) {
      result.add(defaultStyle.toRun(value.substring(offset)));
    }
    return result;
  }

  /// The style the character at [offset] is drawn in.
  PdfTextEditStyle styleAt(int offset) {
    for (final range in _ranges.reversed) {
      if (offset >= range.start && offset < range.end) return range.style;
    }
    return defaultStyle;
  }

  static List<PdfTextEditStyleRange> _mergeRanges(
      List<PdfTextEditStyleRange> ranges) {
    ranges.sort((a, b) => a.start.compareTo(b.start));
    final out = <PdfTextEditStyleRange>[];
    for (final range in ranges) {
      if (range.start >= range.end) continue;
      if (out.isNotEmpty &&
          out.last.end == range.start &&
          out.last.style.sameAs(range.style)) {
        final last = out.removeLast();
        out.add(PdfTextEditStyleRange(last.start, range.end, last.style));
      } else {
        out.add(range);
      }
    }
    return out;
  }

  @override
  TextSpan buildTextSpan(
      {required BuildContext context,
      TextStyle? style,
      required bool withComposing}) {
    final value = text;
    final styler = spanStyler;
    if (value.isEmpty || _ranges.isEmpty || styler == null) {
      return TextSpan(text: value, style: style);
    }
    // the root style is sized to [maxStyleSize] (see the editor's
    // `style:`), so unstyled gaps carry the typing default's size themselves
    final gapStyle = TextStyle(fontSize: defaultStyle.size * scale);
    final children = <InlineSpan>[];
    var offset = 0;
    for (final range in _mergeRanges(List.of(_ranges))) {
      if (range.start >= value.length) continue;
      final start = range.start.clamp(0, value.length);
      final end = range.end.clamp(0, value.length);
      if (offset < start) {
        children.add(
            TextSpan(text: value.substring(offset, start), style: gapStyle));
      }
      children.add(TextSpan(
          text: value.substring(start, end),
          style: styler(range.style,
              scale: scale,
              height: previewLineHeight,
              letterSpacing: previewLetterSpacing)));
      offset = end;
    }
    if (offset < value.length) {
      children.add(TextSpan(text: value.substring(offset), style: gapStyle));
    }
    return TextSpan(style: style, children: children);
  }
}

/// What an open inline text editor will become when it commits.
sealed class PdfTextEditTarget {
  const PdfTextEditTarget(this.page);

  /// The page the editor is open on.
  final int page;

  /// Whether the editor rewrites an annotation that already exists.
  bool get isExisting => false;
}

/// A new free-text box ([PdfEditTool.freeText]).
final class PdfNewTextBox extends PdfTextEditTarget {
  const PdfNewTextBox(super.page);
}

/// A new callout: the box plus a leader pointing at [terminus] (page space).
final class PdfNewCallout extends PdfTextEditTarget {
  const PdfNewCallout(super.page, this.terminus);

  final (double, double) terminus;
}

/// A new cloud callout's note: the cloud marks [region] (page space) and the
/// leader joins it to the note.
final class PdfNewCloudCallout extends PdfTextEditTarget {
  const PdfNewCloudCallout(super.page, this.region);

  final PdfRect region;
}

/// The selected free-text annotation, rewritten in place. [slot] is the
/// annotation the editor opened on (null when the selection had none).
final class PdfExistingTextBox extends PdfTextEditTarget {
  const PdfExistingTextBox(super.page, this.slot);

  final (int, int)? slot;

  @override
  bool get isExisting => true;
}

/// The box-level layout the inline editor previews, so the live text sits
/// where it commits: alignment (/Q, null = follow the text direction),
/// vertical alignment, line height, character spacing, background fill,
/// opacity and resting rotation (view space, radians clockwise).
@immutable
class PdfTextEditLayout {
  const PdfTextEditLayout({
    this.align,
    this.verticalAlign = PdfTextVerticalAlign.top,
    this.lineSpacing = kPdfFreeTextDefaultLineSpacing,
    this.charSpacing = 0,
    this.fill,
    this.opacity = 1,
    this.rotation = 0,
  });

  final PdfTextAlign? align;
  final PdfTextVerticalAlign verticalAlign;
  final double lineSpacing;
  final double charSpacing;
  final Color? fill;
  final double opacity;
  final double rotation;

  PdfTextEditLayout copyWith({
    (PdfTextAlign?,)? align,
    PdfTextVerticalAlign? verticalAlign,
    double? lineSpacing,
    double? charSpacing,
    double? opacity,
  }) =>
      PdfTextEditLayout(
        align: align == null ? this.align : align.$1,
        verticalAlign: verticalAlign ?? this.verticalAlign,
        lineSpacing: lineSpacing ?? this.lineSpacing,
        charSpacing: charSpacing ?? this.charSpacing,
        fill: fill,
        opacity: opacity ?? this.opacity,
        rotation: rotation,
      );

  @override
  bool operator ==(Object other) =>
      other is PdfTextEditLayout &&
      other.align == align &&
      other.verticalAlign == verticalAlign &&
      other.lineSpacing == lineSpacing &&
      other.charSpacing == charSpacing &&
      other.fill == fill &&
      other.opacity == opacity &&
      other.rotation == rotation;

  @override
  int get hashCode => Object.hash(
      align, verticalAlign, lineSpacing, charSpacing, fill, opacity, rotation);
}

/// What committing a [PdfTextEditSession] does to the document - decided by
/// [PdfTextEditSession.decide] without touching it, applied by
/// [PdfEditingController.applyTextEditCommit].
sealed class PdfTextEditCommit {
  const PdfTextEditCommit();

  /// Whether this commit writes a revision.
  bool get changes => true;
}

/// Nothing to write: an empty new box, or an existing one left as it was.
final class PdfTextEditNoChange extends PdfTextEditCommit {
  const PdfTextEditNoChange();

  @override
  bool get changes => false;

  @override
  bool operator ==(Object other) => other is PdfTextEditNoChange;

  @override
  int get hashCode => (PdfTextEditNoChange).hashCode;
}

/// A new annotation: the [target] says which kind, at [rect] (page space).
/// [runs] is set when a plain box carries per-run styling.
final class PdfTextEditAdd extends PdfTextEditCommit {
  const PdfTextEditAdd(this.target, this.rect, this.text, {this.runs});

  final PdfTextEditTarget target;
  final PdfRect rect;
  final String text;
  final List<PdfFreeTextRun>? runs;
}

/// The existing box's text replaced by styled [runs] (its /RC).
final class PdfTextEditSetRichText extends PdfTextEditCommit {
  const PdfTextEditSetRichText(this.runs);

  final List<PdfFreeTextRun> runs;
}

/// The existing box rewritten as [text] with the fields restyled with just a
/// caret: each non-null field is one whose typing style changed since the
/// editor opened.
final class PdfTextEditRestyle extends PdfTextEditCommit {
  const PdfTextEditRestyle(this.text,
      {this.font, this.size, this.color, this.underline});

  final String text;
  final PdfTextFont? font;
  final double? size;

  /// 0xRRGGBB.
  final int? color;
  final bool? underline;

  @override
  bool operator ==(Object other) =>
      other is PdfTextEditRestyle &&
      other.text == text &&
      other.font == font &&
      other.size == size &&
      other.color == color &&
      other.underline == underline;

  @override
  int get hashCode => Object.hash(text, font, size, color, underline);

  @override
  String toString() => 'PdfTextEditRestyle($text, font: $font, size: $size, '
      'color: $color, underline: $underline)';
}

/// The existing box's plain text replaced, its style untouched.
final class PdfTextEditSetText extends PdfTextEditCommit {
  const PdfTextEditSetText(this.text);

  final String text;

  @override
  bool operator ==(Object other) =>
      other is PdfTextEditSetText && other.text == text;

  @override
  int get hashCode => text.hashCode;
}

/// A hold on an open editor's focus behaviour, from
/// [PdfTextEditSession.holdCommit] or [PdfTextEditSession.keepFocused].
/// [release] is idempotent.
class PdfTextEditFocusHold {
  PdfTextEditFocusHold._(this._holds, this._commit);

  final _FocusHolds _holds;
  final bool _commit;
  bool _released = false;

  void release() {
    if (_released) return;
    _released = true;
    _holds.release(commit: _commit);
  }
}

class _FocusHolds extends ChangeNotifier {
  int commit = 0;
  int keep = 0;

  /// Set while the most recent change moved the commit count.
  bool commitChanged = false;

  void take({required bool commit}) {
    if (commit) {
      this.commit++;
    } else {
      keep++;
    }
    commitChanged = commit;
    notifyListeners();
  }

  void release({required bool commit}) {
    if (commit) {
      if (this.commit == 0) return;
      this.commit--;
    } else {
      if (keep == 0) return;
      keep--;
    }
    commitChanged = commit;
    notifyListeners();
  }
}

/// One open inline text editor (free text, callout, cloud-callout note): the
/// [target] it commits to, the style it opened with and the one it types in
/// now, the rich runs ([buffer]), the box [layout], and the commit decision.
///
/// The controller creates it ([PdfEditingController.beginTextEdit]); the
/// toolbar and properties panel restyle it directly
/// ([PdfEditingController.textEditSession]); the page overlay only hosts the
/// `TextField` over [buffer], its focus, and the painting.
class PdfTextEditSession extends ChangeNotifier {
  PdfTextEditSession({
    required this.target,
    required this.rect,
    required PdfTextEditStyle style,
    PdfTextEditLayout layout = const PdfTextEditLayout(),
    String text = '',
    List<PdfFreeTextRun>? runs,
    PdfStandardFont? standardFace,
    this.tool,
    PdfTextEditBuffer? buffer,
    PdfTextEditSession? holdsFrom,
  })  : openStyle = style,
        _layout = layout,
        standardFace = standardFace ??
            (style.font is PdfStandardFont
                ? style.font as PdfStandardFont
                : PdfStandardFont.helvetica),
        _ownsBuffer = buffer == null,
        buffer = buffer ?? PdfTextEditBuffer(),
        _holds = holdsFrom?._holds ?? _FocusHolds() {
    // a box saved with mixed styling carries /RC: reseed its per-run fonts
    // so reopening shows the bold/italic/colour, not a flattened style
    if (runs != null && runs.isNotEmpty) {
      this.buffer.seedRuns(runs, style);
    } else {
      this.buffer.resetStyles(style);
      this.buffer.text = text;
    }
    // TextEditingController.text invalidates the selection. Focus normally
    // repairs it, but at the extreme zoom used for large CAD sheets Flutter
    // can briefly paint the caret at the field origin. Seed the intended
    // insertion point explicitly so it is always after the last glyph.
    this.buffer.selection =
        TextSelection.collapsed(offset: this.buffer.text.length);
    _hadSelection = hasSelection;
    this.buffer.addListener(_onBufferChanged);
  }

  final PdfTextEditTarget target;

  /// The box, page space.
  final PdfRect rect;

  /// The tool that was armed when the editor opened: arming another one
  /// commits the editor.
  final PdfEditTool? tool;

  /// The typing style when the editor opened: an existing box whose
  /// [style] differs at commit was restyled mid-edit with no text selected.
  final PdfTextEditStyle openStyle;

  /// The text and its rich runs.
  final PdfTextEditBuffer buffer;
  final bool _ownsBuffer;

  /// The last base-14 face the box typed in - what bold/italic toggle from
  /// when the box has no selection (an embedded face has no variants).
  PdfStandardFont standardFace;

  final _FocusHolds _holds;
  PdfTextEditLayout _layout;
  bool _closed = false;
  bool _hadSelection = false;

  /// Called when an embedded face enters the editor, so the host can
  /// register its bytes for the live preview.
  void Function(PdfEmbeddedFont font)? onEmbeddedFont;

  /// Called when [hasSelection] flips.
  VoidCallback? onSelectionPresenceChanged;

  /// The current typing style.
  PdfTextEditStyle get style => buffer.defaultStyle;

  PdfTextEditLayout get layout => _layout;

  /// Whether the editor has closed (committed or cancelled).
  bool get isClosed => _closed;

  /// Whether a non-empty run of text is selected.
  bool get hasSelection {
    final selection = buffer.selection;
    return selection.isValid && !selection.isCollapsed;
  }

  /// The style at the start of the selection (or the caret).
  PdfTextEditStyle get styleAtSelection {
    final selection = buffer.selection;
    final offset = selection.isValid
        ? math.min(selection.baseOffset, selection.extentOffset)
        : 0;
    return buffer.styleAt(offset.clamp(0, buffer.text.length));
  }

  void _onBufferChanged() {
    final has = hasSelection;
    if (has != _hadSelection) {
      _hadSelection = has;
      onSelectionPresenceChanged?.call();
    }
  }

  /// Restyles the selected run when text is selected, otherwise the whole
  /// box and what is typed next. [color] is 0xRRGGBB.
  void restyle({PdfTextFont? font, double? size, int? color, bool? underline}) {
    if (_closed) return;
    if (font is PdfEmbeddedFont) onEmbeddedFont?.call(font);
    if (hasSelection) {
      buffer.applyStyle(buffer.selection,
          font: font, size: size, color: color, underline: underline);
      notifyListeners();
      return;
    }
    _restyleWhole(font: font, size: size, color: color, underline: underline);
  }

  /// Restyles every run plus the typing default - a restyle picked with no
  /// text selected. A box without per-run styling stays uniform (no /RC on
  /// commit); the commit carries the new default style ([decide]).
  void _restyleWhole(
      {PdfTextFont? font, double? size, int? color, bool? underline}) {
    final next =
        style.merge(font: font, size: size, color: color, underline: underline);
    if (buffer.hasRichStyles) {
      final length = buffer.text.length;
      if (length > 0) {
        buffer.applyStyle(TextSelection(baseOffset: 0, extentOffset: length),
            font: font, size: size, color: color, underline: underline);
      }
      buffer.defaultStyle = next;
    } else {
      buffer.resetStyles(next);
    }
    if (font is PdfStandardFont) standardFace = font;
    notifyListeners();
  }

  /// The face a bold (or [italic]) toggle switches to: from the selection's
  /// face when text is selected, else from [standardFace].
  PdfStandardFont toggledFace({required bool italic}) {
    final font = hasSelection ? styleAtSelection.font : standardFace;
    final base = font is PdfStandardFont
        ? font
        : PdfStandardFont.fromName(
            font is PdfEmbeddedFont ? font.postScriptName : font.resourceName);
    return italic
        ? base.withItalic(!base.isItalic)
        : base.withBold(!base.isBold);
  }

  /// Types an empty box in [font] (or toggles its [underline]) from scratch:
  /// the box has no text to restyle, so this only resets the typing style.
  void retypeEmpty({PdfStandardFont? font, bool underline = false}) {
    if (font != null) standardFace = font;
    buffer.resetStyles(PdfTextEditStyle(
        font: font ?? standardFace,
        size: style.size,
        color: style.color,
        underline: underline));
    notifyListeners();
  }

  /// Follows the creation defaults the tune popup edits while a new box is
  /// open (alignment, spacing, opacity, and underline while the box has no
  /// per-run styling). An existing box ignores them.
  void adoptBoxDefaults({
    required PdfTextAlign? align,
    required PdfTextVerticalAlign verticalAlign,
    required double lineSpacing,
    required double charSpacing,
    required double opacity,
    required bool underline,
  }) {
    if (_closed || target.isExisting) return;
    final next = _layout.copyWith(
        align: (align,),
        verticalAlign: verticalAlign,
        lineSpacing: lineSpacing,
        charSpacing: charSpacing,
        opacity: opacity);
    final retype = underline != style.underline && !buffer.hasRichStyles;
    if (next == _layout && !retype) return;
    _layout = next;
    if (retype) buffer.resetStyles(style.merge(underline: underline));
    notifyListeners();
  }

  /// Follows the existing box's appearance as the panel restyles it in place
  /// while the editor stays open: its opacity (when it is still the
  /// selection) and vertical alignment.
  void followAppearance(
      {double? opacity, PdfTextVerticalAlign? verticalAlign}) {
    if (_closed || !target.isExisting) return;
    final next =
        _layout.copyWith(opacity: opacity, verticalAlign: verticalAlign);
    if (next == _layout) return;
    _layout = next;
    notifyListeners();
  }

  /// What committing now writes. [savedText] is the existing box's current
  /// text, so an untouched box writes nothing.
  PdfTextEditCommit decide({String? savedText}) {
    final text = buffer.text.trimRight();
    if (text.isEmpty) return const PdfTextEditNoChange();
    final runs = buffer.hasRichStyles ? buffer.toPdfRuns() : null;
    final target = this.target;
    if (target is! PdfExistingTextBox) {
      return PdfTextEditAdd(target, rect, text,
          runs: target is PdfNewTextBox ? runs : null);
    }
    if (runs != null) return PdfTextEditSetRichText(runs);
    final open = openStyle;
    final now = style;
    final restyled = now.font != open.font ||
        now.size != open.size ||
        now.color != open.color ||
        now.underline != open.underline;
    if (restyled) {
      // restyled with just a caret: the whole box takes the new style
      return PdfTextEditRestyle(text,
          font: now.font == open.font ? null : now.font,
          size: now.size == open.size ? null : now.size,
          color:
              now.color == open.color ? null : now.color.toARGB32() & 0xFFFFFF,
          underline: now.underline == open.underline ? null : now.underline);
    }
    if (text != savedText) return PdfTextEditSetText(text);
    return const PdfTextEditNoChange();
  }

  /// Holds off the commit a lost focus would trigger - while a picker or
  /// popup takes the keyboard to restyle this editor. Shared with an editor
  /// reopened from this one ([holdsFrom]).
  PdfTextEditFocusHold holdCommit() {
    _holds.take(commit: true);
    return PdfTextEditFocusHold._(_holds, true);
  }

  /// Asks the host to keep (and reclaim) keyboard focus on the field - while
  /// the tune popup is open over it, so the selection highlight a
  /// `TextField` only paints when focused stays on.
  PdfTextEditFocusHold keepFocused() {
    _holds.take(commit: false);
    return PdfTextEditFocusHold._(_holds, false);
  }

  /// Whether a lost focus should leave the editor open.
  bool get isCommitHeld => _holds.commit > 0;

  /// Whether the host should reclaim focus for the field.
  bool get keepsFocus => !_closed && _holds.keep > 0;

  /// Notifies when a hold is taken or released.
  Listenable get focusHolds => _holds;

  /// Whether the latest [focusHolds] change moved a commit hold.
  bool get commitHoldChanged => _holds.commitChanged;

  /// Marks the session closed; the controller calls this.
  void close() {
    if (_closed) return;
    _closed = true;
    buffer.removeListener(_onBufferChanged);
  }

  @override
  void dispose() {
    close();
    if (_ownsBuffer) buffer.dispose();
    super.dispose();
  }
}
