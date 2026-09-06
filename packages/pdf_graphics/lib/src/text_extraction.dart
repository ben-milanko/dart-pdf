import 'dart:math' as math;

import 'package:bidi/bidi.dart' as bidi;
import 'package:pdf_cos/perf.dart';
import 'package:pdf_document/pdf_document.dart';

import 'color.dart';
import 'device.dart';
import 'interpreter.dart';
import 'matrix.dart';
import 'mesh.dart';
import 'path.dart';
import 'shading.dart';

final _bidiFormattingControls =
    RegExp(r'[\u061C\u200E\u200F\u202A-\u202E\u2066-\u2069]');

/// One positioned run of text on a page, in page space.
class PdfExtractedRun {
  const PdfExtractedRun({
    required this.text,
    required this.startIndex,
    required this.transform,
    required this.width,
    required this.bounds,
    this.charOffsets,
    this.isRightToLeft = false,
    this.mcid,
  });

  final String text;

  /// Offset of [text] inside the owning [PdfPageText.text].
  final int startIndex;

  /// The marked-content id of the structure-tagged sequence this run belongs
  /// to (§14.7), or null when the run is not tagged. Joins runs to the
  /// logical structure tree - see [PdfTaggedText].
  final int? mcid;

  /// Em space → page space (see [PdfTextRun.transform]).
  final PdfMatrix transform;

  /// Advance width in em units.
  final double width;

  /// Page-space bounding box.
  final PdfRect bounds;

  /// Em-space offset of every character boundary in [text], measured from this
  /// run's own origin: entry `i` is the advance to the start of `text[i]`, and
  /// the last entry (index `text.length`) is [width]. Ascending, length
  /// `text.length + 1`.
  ///
  /// This is what puts a selection or search highlight on the actual glyphs of
  /// a proportional font (issue #647) - `world` in `Hello, world!` starts 51.5%
  /// of the way along the run, not 7/13 = 53.8% of it. Null when the source
  /// run carried no metrics (vertical writing mode, or text reordered by the
  /// BiDi pass); callers then interpolate across [width] as before.
  final List<double>? charOffsets;

  /// Whether logical character order runs opposite this run's em-space
  /// advance. Search and selection use this to map logical Arabic/Hebrew
  /// offsets back onto the visual glyph positions in the PDF.
  final bool isRightToLeft;
}

/// Four page-space corners of a text span's highlight box, in perimeter
/// order: lower-left, lower-right, upper-right, upper-left of the run's
/// own baseline frame.
///
/// For horizontal text the quad is axis-aligned and matches [bounds];
/// for rotated text the corners follow the glyph baseline, so a highlight
/// painted as a quad rotates with the text instead of ballooning out to
/// an axis-aligned bounding box.
class PdfTextQuad {
  const PdfTextQuad(this.corners, {this.isRightToLeft = false});

  /// The four `(x, y)` page-space points in perimeter order (ll, lr, ur,
  /// ul). Always length 4.
  final List<(double x, double y)> corners;

  /// Whether logical text advances from the quad's right edge toward its
  /// left edge. Selection chrome uses this to anchor its logical endpoints.
  final bool isRightToLeft;

  /// The axis-aligned page-space bounding box of the four corners.
  PdfRect get bounds {
    var minX = corners.first.$1, maxX = corners.first.$1;
    var minY = corners.first.$2, maxY = corners.first.$2;
    for (final (x, y) in corners) {
      minX = math.min(minX, x);
      maxX = math.max(maxX, x);
      minY = math.min(minY, y);
      maxY = math.max(maxY, y);
    }
    return PdfRect(minX, minY, maxX, maxY);
  }
}

/// One search hit, with page-space geometry for highlighting.
class PdfTextMatch {
  const PdfTextMatch({
    required this.pageIndex,
    required this.start,
    required this.end,
    required this.rects,
    required this.quads,
  });

  final int pageIndex;
  final int start;
  final int end;

  /// Axis-aligned bounding boxes (one per run touched), for scroll-to and
  /// callers that only need a rough box.
  final List<PdfRect> rects;

  /// Baseline-aligned quads (one per run touched), so highlights rotate
  /// with rotated text.
  final List<PdfTextQuad> quads;
}

/// The text content of one page, with geometry for search highlighting.
class PdfPageText {
  const PdfPageText({
    required this.pageIndex,
    required this.text,
    required this.runs,
  });

  final int pageIndex;
  final String text;
  final List<PdfExtractedRun> runs;

  /// Finds non-overlapping occurrences of [query].
  ///
  /// With [wholeWord] only matches whose surrounding characters are not
  /// letters/digits/underscore count. With [regex] the query is a Dart
  /// regular expression (an invalid pattern yields no matches rather than
  /// throwing); matching is synchronous with no timeout, so a pathological
  /// (catastrophically backtracking) pattern over a large page can block
  /// the caller. [caseSensitive] applies to both literal and regex search.
  /// Literal queries ignore Unicode BiDi formatting controls so text copied
  /// with direction metadata can be pasted back into search.
  List<PdfTextMatch> findAll(
    String query, {
    bool caseSensitive = false,
    bool wholeWord = false,
    bool regex = false,
  }) {
    if (query.isEmpty) return const [];
    final matches = <PdfTextMatch>[];
    if (regex) {
      final RegExp pattern;
      try {
        pattern = RegExp(query, caseSensitive: caseSensitive, multiLine: true);
      } on FormatException {
        return const []; // invalid pattern - surface no matches, don't throw
      }
      for (final match in pattern.allMatches(text)) {
        if (match.start == match.end) continue; // skip zero-width hits
        if (wholeWord && !_isWholeWord(match.start, match.end)) continue;
        matches.add(_matchAt(match.start, match.end));
      }
      return matches;
    }
    query = query.replaceAll(_bidiFormattingControls, '');
    if (query.isEmpty) return const [];
    final haystack = caseSensitive ? text : text.toLowerCase();
    final needle = caseSensitive ? query : query.toLowerCase();
    var from = 0;
    while (true) {
      final index = haystack.indexOf(needle, from);
      if (index < 0) break;
      final end = index + needle.length;
      if (!wholeWord || _isWholeWord(index, end)) {
        matches.add(_matchAt(index, end));
      }
      from = end;
    }
    return matches;
  }

  PdfTextMatch _matchAt(int start, int end) {
    final quads = quadsFor(start, end);
    return PdfTextMatch(
      pageIndex: pageIndex,
      start: start,
      end: end,
      rects: [for (final quad in quads) quad.bounds],
      quads: quads,
    );
  }

  /// Whether [text]`[start..end)` is bounded by non-word characters on both
  /// sides (or the string edge) - the "match whole word" test.
  bool _isWholeWord(int start, int end) =>
      !_isWordChar(start - 1) && !_isWordChar(end);

  bool _isWordChar(int index) {
    if (index < 0 || index >= text.length) return false;
    final c = text.codeUnitAt(index);
    return (c >= 0x30 && c <= 0x39) || // 0-9
        (c >= 0x41 && c <= 0x5A) || // A-Z
        (c >= 0x61 && c <= 0x7A) || // a-z
        c == 0x5F; // _
  }

  /// Axis-aligned page-space rectangles covering the characters
  /// [start]..[end] of [text]. Convenience over [quadsFor] for callers
  /// that don't need rotation (e.g. text-markup QuadPoints, scroll-to).
  List<PdfRect> rectsFor(int start, int end) =>
      [for (final quad in quadsFor(start, end)) quad.bounds];

  /// Baseline-aligned page-space quads covering the characters
  /// [start]..[end] of [text] - for selection and search highlights that
  /// rotate with rotated text.
  List<PdfTextQuad> quadsFor(int start, int end) {
    final quads = <PdfTextQuad>[];
    for (final run in runs) {
      if (run.text.isEmpty) continue;
      final runEnd = run.startIndex + run.text.length;
      final overlapStart = math.max(start, run.startIndex);
      final overlapEnd = math.min(end, runEnd);
      if (overlapStart >= overlapEnd) continue;
      // The offsets ascend with the em advance, so they only index logical
      // character order on an LTR run - extraction leaves them null for RTL.
      final offsets = run.isRightToLeft ? null : run.charOffsets;
      double x0, x1;
      if (offsets != null) {
        // Real per-character metrics: the highlight lands on the glyphs even
        // when they have wildly different widths (issue #647).
        x0 = offsets[overlapStart - run.startIndex];
        x1 = offsets[overlapEnd - run.startIndex];
      } else {
        // No metrics for this run - approximate by character fraction.
        final logicalStart = (overlapStart - run.startIndex) / run.text.length;
        final logicalEnd = (overlapEnd - run.startIndex) / run.text.length;
        final f0 = run.isRightToLeft ? 1 - logicalEnd : logicalStart;
        final f1 = run.isRightToLeft ? 1 - logicalStart : logicalEnd;
        x0 = run.width * f0;
        x1 = run.width * f1;
      }
      quads.add(_quadOf(
        run.transform,
        x0,
        x1,
        isRightToLeft: run.isRightToLeft,
      ));
    }
    return quads;
  }

  /// The page text inside [rect] (page space): runs whose bounds center
  /// falls within the rect, in document order, preserving whitespace between
  /// adjacent runs. The text a /Link annotation's rectangle covers, for one.
  String textIn(PdfRect rect) {
    final selected = <PdfExtractedRun>[];
    for (final run in runs) {
      if (run.text.trim().isEmpty) continue;
      final b = run.bounds;
      if (rect.contains((b.left + b.right) / 2, (b.bottom + b.top) / 2)) {
        selected.add(run);
      }
    }
    selected.sort((a, b) => a.startIndex.compareTo(b.startIndex));
    final buffer = StringBuffer();
    PdfExtractedRun? previous;
    for (final run in selected) {
      if (previous != null) {
        final from = previous.startIndex + previous.text.length;
        if (run.startIndex > from) {
          final between = text.substring(from, run.startIndex);
          buffer.write(between.trim().isEmpty ? between : ' ');
        }
      }
      buffer.write(run.text);
      previous = run;
    }
    return buffer.toString();
  }

  /// Index into [text] nearest the page-space point ([x], [y]), for
  /// mapping pointer positions to text positions (selection).
  ///
  /// Returns -1 when the document has no text or the nearest run is more
  /// than [tolerance] page units away.
  int positionNear(double x, double y, {double tolerance = double.infinity}) {
    PdfExtractedRun? best;
    var bestDistance = double.infinity;
    for (final run in runs) {
      if (run.text.isEmpty) continue;
      final b = run.bounds;
      final dx = math.max(0.0, math.max(b.left - x, x - b.right));
      final dy = math.max(0.0, math.max(b.bottom - y, y - b.top));
      final distance = dx * dx + dy * dy;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = run;
      }
    }
    if (best == null || bestDistance > tolerance * tolerance) return -1;
    // offset along the run's baseline, in em space
    final inverse = best.transform.inverted();
    final ex = inverse == null ? 0.0 : inverse.transformX(x, y);
    final offsets = best.isRightToLeft ? null : best.charOffsets;
    if (offsets != null) {
      return best.startIndex + _nearestBoundary(offsets, ex);
    }
    final fraction = best.width > 0 ? (ex / best.width).clamp(0.0, 1.0) : 0.0;
    final logicalFraction = best.isRightToLeft ? 1 - fraction : fraction;
    return best.startIndex + (logicalFraction * best.text.length).round();
  }

  /// The index into the ascending [offsets] whose value is closest to [ex] -
  /// the caret position a click at [ex] snaps to.
  static int _nearestBoundary(List<double> offsets, double ex) {
    // Binary search for the first boundary at or past `ex`.
    var lo = 0, hi = offsets.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (offsets[mid] < ex) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    if (lo == 0) return 0;
    // `lo - 1` sits before `ex` and `lo` at or past it - snap to the nearer.
    return ex - offsets[lo - 1] <= offsets[lo] - ex ? lo - 1 : lo;
  }
}

/// Adds Unicode direction metadata suitable for putting extracted [text] on
/// a plain-text clipboard.
///
/// Searchable PDF text remains in clean logical order. Each paragraph that
/// contains strong RTL text is instead wrapped at copy time in the isolate
/// matching its first strong character (`RLI` or `LRI`), followed by `PDI`.
/// Isolates are paragraph-scoped, so line endings are preserved outside the
/// controls. A paragraph already wrapped in `LRI`/`RLI`/`FSI` and `PDI` is
/// left alone.
///
/// This follows the W3C guidance for carrying bidirectional metadata in
/// plain text when markup is unavailable:
/// https://www.w3.org/International/questions/qa-bidi-unicode-controls.en.html
String pdfBidiIsolateForCopy(String text) {
  if (text.isEmpty) return text;
  return text.splitMapJoin(
    RegExp(r'\r\n|[\r\n]'),
    onMatch: (match) => match.group(0)!,
    onNonMatch: _isolateBidiParagraph,
  );
}

String _isolateBidiParagraph(String text) {
  if (text.isEmpty || _hasOuterBidiIsolate(text)) return text;
  _BidiKind? firstStrong;
  var hasRightToLeft = false;
  for (final rune in text.runes) {
    final direction = _strongBidiKind(rune);
    if (direction == null) continue;
    firstStrong ??= direction;
    if (direction == _BidiKind.rtl) hasRightToLeft = true;
  }
  if (!hasRightToLeft) return text;
  final opener = firstStrong == _BidiKind.rtl ? '\u2067' : '\u2066';
  return '$opener$text\u2069';
}

bool _hasOuterBidiIsolate(String text) {
  final first = text.codeUnitAt(0);
  return (first == 0x2066 || first == 0x2067 || first == 0x2068) &&
      text.codeUnitAt(text.length - 1) == 0x2069;
}

/// A line of text inferred from positioned page text.
class PdfReflowLine {
  const PdfReflowLine({
    required this.text,
    required this.bounds,
    required this.fontSize,
  });

  final String text;
  final PdfRect bounds;
  final double fontSize;
}

/// One item in a reflowed page, placed in inferred reading order: either a
/// text [PdfReflowBlock] or a [PdfReflowImage].
sealed class PdfReflowItem {
  const PdfReflowItem();

  /// Page-space bounds of the item.
  PdfRect get bounds;
}

/// One paragraph-like block in reading order.
class PdfReflowBlock extends PdfReflowItem {
  const PdfReflowBlock({
    required this.text,
    required this.bounds,
    required this.lines,
    required this.fontSize,
    this.isListItem = false,
  });

  /// Text with line breaks removed and soft hyphens repaired.
  final String text;

  /// Page-space bounds of the source lines.
  @override
  final PdfRect bounds;

  final List<PdfReflowLine> lines;

  /// Median source font size for display heuristics.
  final double fontSize;

  /// True when the block begins with a bullet or numbered list marker, so a
  /// reading view can indent it instead of folding it into the prose.
  final bool isListItem;
}

/// An image or diagram placed on the page, surfaced in the reflow view in
/// reading order. The pixels are not decoded here ([pdf_graphics] is
/// VM-only); decode [request] with the renderer's `decodeImages` to display
/// it.
class PdfReflowImage extends PdfReflowItem {
  const PdfReflowImage({
    required this.request,
    required this.bounds,
  });

  /// The interpreter's draw request - carries the image stream and the
  /// unit-square → page-space transform.
  final PdfImageRequest request;

  /// Page-space bounds the image was painted into.
  @override
  final PdfRect bounds;

  /// Width over height of the placed image (1 when degenerate), for laying
  /// the image out at its on-page aspect ratio.
  double get aspectRatio =>
      bounds.height <= 0 ? 1 : bounds.width / bounds.height;
}

/// A page's content reduced to text paragraph blocks and images in inferred
/// reading order.
class PdfReflowPage {
  const PdfReflowPage({
    required this.pageIndex,
    required this.items,
  });

  final int pageIndex;

  /// Text blocks and images interleaved in reading order.
  final List<PdfReflowItem> items;

  /// The text blocks only, in reading order.
  List<PdfReflowBlock> get blocks => [
        for (final item in items)
          if (item is PdfReflowBlock) item
      ];

  /// The images only, in reading order.
  List<PdfReflowImage> get images => [
        for (final item in items)
          if (item is PdfReflowImage) item
      ];

  /// The reading-order text - blocks joined with blank lines (images skipped).
  String get text => blocks.map((block) => block.text).join('\n\n');
}

/// Document-level convenience wrapper for reflowed text.
class PdfReflowDocument {
  const PdfReflowDocument({required this.pages});

  final List<PdfReflowPage> pages;

  String get text => pages.map((page) => page.text).join('\n\n');
}

/// Extracts positioned text by running the interpreter with a collecting
/// device - the same code path rendering uses, so what you search is what
/// you see.
class PdfTextExtractor {
  PdfTextExtractor._();

  static PdfPageText extract(PdfDocument document, int pageIndex) {
    final t0 = PdfPerf.begin();
    try {
      return _pageTextFrom(pageIndex, _interpret(document, pageIndex).runs);
    } finally {
      PdfPerf.end(PdfPerfPhase.textExtract, t0);
    }
  }

  static _ExtractionDevice _interpret(PdfDocument document, int pageIndex) {
    final device = _ExtractionDevice();
    // Extraction reads geometry and Unicode, never colour, so the overprint
    // colorant buffer (§8.6.7) would be pure cost on a page that uses it.
    PdfInterpreter(
      cos: document.cos,
      device: device,
      resolveOverprint: false,
      // Selection and search highlights need the real per-character advances,
      // not a linear guess across the run (issue #647).
      collectCharOffsets: true,
    ).drawPage(document.page(pageIndex));
    return device;
  }

  static PdfPageText _pageTextFrom(int pageIndex, List<PdfTextRun> deviceRuns) {
    final buffer = StringBuffer();
    final runs = <PdfExtractedRun>[];
    final line = <_SourceRun>[];
    PdfTextRun? previous;

    void flushLine() {
      if (line.isEmpty) return;
      final bidiLine = _bidiLine(line);
      if (bidiLine == null) {
        for (final item in line) {
          buffer.write(item.separator);
          _appendExtractedRun(
              buffer, runs, item.run, item.run.text, 0, item.run.text.length);
        }
      } else {
        final groups =
            bidiLine.rightToLeft ? bidiLine.groups.reversed : bidiLine.groups;
        for (final group in groups) {
          final pieces = group.kind == _BidiKind.rtl
              ? group.pieces.reversed
              : group.pieces;
          for (final piece in pieces) {
            final text = group.kind == _BidiKind.rtl && !piece.preserveText
                ? _reverseRunes(piece.text)
                : piece.text;
            final source = piece.source;
            if (source == null) {
              buffer.write(text);
            } else {
              _appendExtractedRun(
                buffer,
                runs,
                source,
                text,
                piece.sourceStart,
                piece.sourceEnd,
                rightToLeft: group.kind == _BidiKind.rtl,
                sourceX0: piece.sourceX0,
                sourceX1: piece.sourceX1,
              );
            }
          }
        }
      }
      line.clear();
    }

    for (final run in deviceRuns) {
      final separator = previous == null ? '' : _separator(previous, run);
      if (separator == '\n') {
        flushLine();
        buffer.write('\n');
        line.add(_SourceRun('', run));
      } else {
        line.add(_SourceRun(separator, run));
      }
      previous = run;
    }
    flushLine();
    return PdfPageText(
        pageIndex: pageIndex, text: buffer.toString(), runs: runs);
  }

  /// PDF text-showing operators advance in glyph order, so embedded RTL fonts
  /// normally expose visual-order Unicode through /ToUnicode. Convert one
  /// visual line back to logical order. Runs without outlines are excluded:
  /// those are rendered by a BiDi-aware substitute and may already contain
  /// logical Unicode (including appearances authored by this package).
  static _BidiLine? _bidiLine(List<_SourceRun> line) {
    final pieces = <_BidiPiece>[];
    _BidiKind? previousKind;
    var hasRtl = false;
    var hasUnpositionedRtl = false;
    var runeCount = 0;
    var rtlCount = 0;

    void add(
      String text,
      PdfTextRun? source, {
      int sourceOffset = 0,
      bool preserveText = false,
      double? sourceX0,
      double? sourceX1,
    }) {
      var segmentStart = 0;
      var offset = 0;
      _BidiKind? segmentKind;

      void flush() {
        if (segmentKind == null || segmentStart == offset) return;
        pieces.add(_BidiPiece(
          text.substring(segmentStart, offset),
          segmentKind,
          source,
          sourceOffset + segmentStart,
          sourceOffset + offset,
          preserveText,
          sourceX0,
          sourceX1,
        ));
      }

      for (final rune in text.runes) {
        runeCount++;
        final kind = _bidiKind(rune, previousKind);
        if (kind != segmentKind) {
          flush();
          segmentStart = offset;
          segmentKind = kind;
        }
        // UTF-16 length of the code point, without allocating a String for it.
        offset += rune > 0xFFFF ? 2 : 1;
        previousKind = kind;
        if (kind == _BidiKind.rtl) {
          hasRtl = true;
          rtlCount++;
          if (source != null && source.glyphs == null) {
            hasUnpositionedRtl = true;
          }
        }
      }
      flush();
    }

    final visualLine = _visualSourceClusters(line);
    PdfTextRun? visualPrevious;
    for (final cluster in visualLine) {
      add(
        visualPrevious == null
            ? ''
            : _separatorWithinVisualLine(visualPrevious, cluster.anchor),
        null,
      );
      if (_isZeroAdvanceMark(cluster.sources.first.run)) {
        previousKind = _firstStrongKind(cluster.anchor.text) ?? previousKind;
      }
      for (final item in cluster.sources) {
        final glyphs = item.run.glyphs;
        final hasGlyphText = glyphs != null &&
            glyphs.every((glyph) => glyph.text != null) &&
            glyphs.map((glyph) => glyph.text!).join() == item.run.text;
        if (!hasGlyphText) {
          add(item.run.text, item.run);
          continue;
        }
        var sourceOffset = 0;
        for (var i = 0; i < glyphs.length; i++) {
          final glyph = glyphs[i];
          final text = glyph.text!;
          final end = i + 1 < glyphs.length
              ? math.max(glyph.offset, glyphs[i + 1].offset)
              : item.run.width;
          add(
            text,
            item.run,
            sourceOffset: sourceOffset,
            preserveText: true,
            sourceX0: glyph.offset,
            sourceX1: end,
          );
          sourceOffset += text.length;
        }
      }
      visualPrevious = cluster.anchor;
    }
    if (!hasRtl || hasUnpositionedRtl) return null;

    final groups = <_BidiGroup>[];
    for (final piece in pieces) {
      if (groups.isEmpty || groups.last.kind != piece.kind) {
        groups.add(_BidiGroup(piece.kind, [piece]));
      } else {
        groups.last.pieces.add(piece);
      }
    }
    // Match the base-direction inference used by PDF.js: a line whose strong
    // RTL content exceeds roughly 30% is an RTL paragraph. Otherwise only the
    // embedded RTL spans reverse, so `English + العربية + English` keeps its
    // surrounding LTR reading order.
    return _BidiLine(groups, rightToLeft: rtlCount > runeCount * 0.3);
  }

  static void _appendExtractedRun(
    StringBuffer buffer,
    List<PdfExtractedRun> runs,
    PdfTextRun source,
    String text,
    int sourceStart,
    int sourceEnd, {
    bool rightToLeft = false,
    double? sourceX0,
    double? sourceX1,
  }) {
    final offsets =
        _sliceCharOffsets(source, text, sourceStart, sourceEnd, rightToLeft);
    final double x0, width;
    if (offsets != null) {
      // Exact metrics beat both the caller's glyph bracket and the character
      // fraction below, and keep bounds consistent with `offsets`.
      x0 = source.charOffsets![sourceStart];
      width = offsets.last;
    } else {
      final sourceLength = source.text.length;
      final f0 = sourceLength == 0 ? 0.0 : sourceStart / sourceLength;
      final f1 = sourceLength == 0 ? 1.0 : sourceEnd / sourceLength;
      x0 = sourceX0 ?? source.width * f0;
      width = (sourceX1 ?? source.width * f1) - x0;
    }
    final transform = x0 == 0
        ? source.transform
        : PdfMatrix.translation(x0, 0).concat(source.transform);
    final start = buffer.length;
    buffer.write(text);
    runs.add(PdfExtractedRun(
      text: text,
      startIndex: start,
      transform: transform,
      width: width,
      bounds: _boundsOf(transform, 0, width),
      charOffsets: offsets,
      isRightToLeft: rightToLeft,
      mcid: source.mcid,
    ));
  }

  /// [source]'s character offsets for `[sourceStart, sourceEnd)`, rebased so
  /// entry 0 is 0 - or null when they can't be trusted for [text].
  ///
  /// The BiDi pass reverses and re-splits runs, so the offsets only line up
  /// when [text] is still the source's own characters in their own order.
  /// Everything else falls back to interpolating across the run width.
  static List<double>? _sliceCharOffsets(
    PdfTextRun source,
    String text,
    int sourceStart,
    int sourceEnd,
    bool rightToLeft,
  ) {
    final all = source.charOffsets;
    if (all == null || rightToLeft) return null;
    if (sourceEnd - sourceStart != text.length) return null;
    if (sourceStart < 0 || sourceEnd >= all.length) return null;
    final base = all[sourceStart];
    // The overwhelmingly common case is one extracted run per source run, so
    // the slice is the whole table already rebased at 0 - share it rather
    // than copying every run's advances. Nothing mutates it.
    if (base == 0 && sourceEnd == all.length - 1) return all;
    return [for (var i = sourceStart; i <= sourceEnd; i++) all[i] - base];
  }

  /// Groups zero-advance marks with their following base run, then orders the
  /// clusters by their location along the line's visual baseline.
  ///
  /// Skia emits Arabic marks as separate text-showing operators immediately
  /// before their base glyph. Sorting those marks independently moves them
  /// across the base and makes the gap heuristic insert spaces inside words.
  /// Keeping the source-order cluster intact lets the RTL reversal restore
  /// base-then-mark logical order while separately positioned words can still
  /// move into visual order before the reversal.
  static List<_SourceCluster> _visualSourceClusters(List<_SourceRun> line) {
    final clusters = <_SourceCluster>[];
    final pendingMarks = <_SourceRun>[];
    for (final source in line) {
      if (_isZeroAdvanceMark(source.run)) {
        pendingMarks.add(source);
        continue;
      }
      clusters.add(_SourceCluster(
        [...pendingMarks, source],
        source.run,
      ));
      pendingMarks.clear();
    }
    if (pendingMarks.isNotEmpty) {
      if (clusters.isEmpty) {
        clusters.add(_SourceCluster([...pendingMarks], pendingMarks.last.run));
      } else {
        final last = clusters.removeLast();
        clusters.add(_SourceCluster(
          [...last.sources, ...pendingMarks],
          last.anchor,
        ));
      }
    }
    if (clusters.length < 2) return clusters;

    final baseline = line.first.run.transform;
    final length = math.sqrt(baseline.a * baseline.a + baseline.b * baseline.b);
    if (length <= 1e-9) return clusters;
    final ux = baseline.a / length;
    final uy = baseline.b / length;
    final positioned = <({int index, double offset, _SourceCluster cluster})>[
      for (var i = 0; i < clusters.length; i++)
        (
          index: i,
          offset: clusters[i].anchor.transform.e * ux +
              clusters[i].anchor.transform.f * uy,
          cluster: clusters[i],
        ),
    ];
    positioned.sort((a, b) {
      final order = a.offset.compareTo(b.offset);
      return order != 0 ? order : a.index.compareTo(b.index);
    });
    return [for (final item in positioned) item.cluster];
  }

  static bool _isZeroAdvanceMark(PdfTextRun run) =>
      run.width.abs() <= 1e-9 && run.text.trim().isNotEmpty;

  static _BidiKind? _firstStrongKind(String text) {
    for (final rune in text.runes) {
      final kind = _strongBidiKind(rune);
      if (kind != null) return kind;
    }
    return null;
  }

  /// Reconstructs an inferred separator after source runs have been reordered
  /// visually. The gap is measured along the preceding run's baseline so the
  /// same logic works for rotated text.
  static String _separatorWithinVisualLine(
      PdfTextRun previous, PdfTextRun next) {
    if (previous.text.trim().isEmpty || next.text.trim().isEmpty) return '';
    final em = previous.transform.scaleFactor;
    final axisLength = math.sqrt(previous.transform.a * previous.transform.a +
        previous.transform.b * previous.transform.b);
    if (em <= 0 || axisLength <= 1e-9) return ' ';
    final endX = previous.transform.transformX(previous.width, 0);
    final endY = previous.transform.transformY(previous.width, 0);
    final dx = next.transform.e - endX;
    final dy = next.transform.f - endY;
    final ux = previous.transform.a / axisLength;
    final uy = previous.transform.b / axisLength;
    final along = dx * ux + dy * uy;
    final across = (dx * -uy + dy * ux).abs();
    if (across > 0.5 * em || along > 0.15 * em) return ' ';
    return '';
  }

  /// Extracts every page and infers paragraph blocks in reading order.
  ///
  /// This is intentionally heuristic: PDFs do not carry a general-purpose
  /// reading order. The implementation groups visible text into visual lines,
  /// splits large horizontal gaps into separate columns, reads columns
  /// left-to-right, and folds nearby lines into paragraphs.
  static PdfReflowDocument reflow(PdfDocument document) => PdfReflowDocument(
        pages: [
          for (var i = 0; i < document.pageCount; i++) reflowPage(document, i),
        ],
      );

  /// Extracts one page and infers paragraph blocks and images in reading
  /// order.
  static PdfReflowPage reflowPage(PdfDocument document, int pageIndex) {
    final device = _interpret(document, pageIndex);
    return PdfTextReflower.reflow(
      _pageTextFrom(pageIndex, device.runs),
      images: device.images,
    );
  }

  /// Joins consecutive runs: nothing when they abut (kerning splits inside a
  /// word), a space within a line, a newline on baseline changes.
  static String _separator(PdfTextRun previous, PdfTextRun next) {
    final em = previous.transform.scaleFactor;
    if (em <= 0) return ' ';
    final endX = previous.transform.transformX(previous.width, 0);
    final endY = previous.transform.transformY(previous.width, 0);
    final dx = next.transform.e - endX;
    final dy = next.transform.f - endY;
    if (dy.abs() > 0.5 * em) return '\n';
    if (dx.abs() > 0.15 * em) return ' ';
    return '';
  }
}

/// Paragraph and reading-order inference over [PdfPageText].
class PdfTextReflower {
  PdfTextReflower._();

  static PdfReflowPage reflow(PdfPageText page,
      {List<PdfImageRequest> images = const []}) {
    final reflowImages = _imagesFrom(images);
    final lines = _visualLines(page.runs);
    if (lines.isEmpty) {
      // An image-only page (a scan, a full-page figure) still reads top-down.
      return PdfReflowPage(
        pageIndex: page.pageIndex,
        items: _topDownItems(reflowImages),
      );
    }
    final ordered = _orderLines(lines);
    return PdfReflowPage(
      pageIndex: page.pageIndex,
      items: _interleave(_paragraphs(ordered), reflowImages),
    );
  }

  /// Drops decorative images (rules, spacers, tiny icons) and near-duplicate
  /// re-draws (tiled backgrounds, repeated watermarks), keeping the figures
  /// and diagrams a reader cares about.
  static List<PdfReflowImage> _imagesFrom(List<PdfImageRequest> requests) {
    const minSide = 24.0;
    final out = <PdfReflowImage>[];
    for (final request in requests) {
      final bounds = _imageBounds(request.transform);
      if (bounds.width < minSide || bounds.height < minSide) continue;
      final duplicate = out.any((existing) =>
          identical(existing.request.stream, request.stream) &&
          _overlapFraction(existing.bounds, bounds) > 0.9);
      if (duplicate) continue;
      out.add(PdfReflowImage(request: request, bounds: bounds));
    }
    return out;
  }

  /// Page-space bounds of the unit image square under [transform].
  static PdfRect _imageBounds(PdfMatrix transform) {
    final xs = [
      transform.transformX(0, 0),
      transform.transformX(1, 0),
      transform.transformX(1, 1),
      transform.transformX(0, 1),
    ];
    final ys = [
      transform.transformY(0, 0),
      transform.transformY(1, 0),
      transform.transformY(1, 1),
      transform.transformY(0, 1),
    ];
    return PdfRect(xs.reduce(math.min), ys.reduce(math.min),
        xs.reduce(math.max), ys.reduce(math.max));
  }

  /// Sorts reflow items top-to-bottom, then left-to-right.
  static List<PdfReflowItem> _topDownItems(Iterable<PdfReflowItem> items) =>
      [...items]..sort((a, b) {
          final y = b.bounds.top.compareTo(a.bounds.top);
          return y != 0 ? y : a.bounds.left.compareTo(b.bounds.left);
        });

  /// Folds images into the ordered text blocks. Each image inherits the
  /// reading position of the nearest text block above it (in the same
  /// column), so a figure lands where it sits on the page even in a
  /// multi-column read; an image with no text above falls back to its
  /// vertical position.
  static List<PdfReflowItem> _interleave(
      List<PdfReflowBlock> blocks, List<PdfReflowImage> images) {
    if (images.isEmpty) return List<PdfReflowItem>.from(blocks);
    final keyed = <(double, PdfReflowItem)>[
      for (var i = 0; i < blocks.length; i++) (i.toDouble(), blocks[i]),
      for (final image in images) (_imageOrderKey(image, blocks), image),
    ];
    keyed.sort((a, b) {
      final k = a.$1.compareTo(b.$1);
      return k != 0 ? k : b.$2.bounds.top.compareTo(a.$2.bounds.top);
    });
    return [for (final entry in keyed) entry.$2];
  }

  static double _imageOrderKey(
      PdfReflowImage image, List<PdfReflowBlock> blocks) {
    var follow = -1;
    var bestGap = double.infinity;
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i].bounds;
      final overlap = _horizontalOverlap(b, image.bounds);
      if (overlap <= math.min(b.width, image.bounds.width) * 0.1) continue;
      final gap = b.bottom - image.bounds.top; // >= 0 when the block is above
      if (gap >= 0 && gap < bestGap) {
        bestGap = gap;
        follow = i;
      }
    }
    if (follow >= 0) return follow + 0.5;
    // No overlapping block above: drop the image after the last block whose
    // top sits above the image's vertical centre.
    final centerY = (image.bounds.bottom + image.bounds.top) / 2;
    var fallback = -1;
    for (var i = 0; i < blocks.length; i++) {
      if (blocks[i].bounds.top >= centerY) fallback = i;
    }
    return fallback + 0.5;
  }

  static List<PdfReflowLine> _visualLines(List<PdfExtractedRun> runs) {
    final pieces = [
      for (final run in runs)
        if (run.text.trim().isNotEmpty) _LinePiece.fromRun(run),
    ];
    if (pieces.isEmpty) return const [];
    pieces.sort((a, b) {
      final y = b.centerY.compareTo(a.centerY);
      return y != 0 ? y : a.bounds.left.compareTo(b.bounds.left);
    });

    // Each band keeps a running centre sum and its font sizes in ascending
    // order, so the two per-candidate questions below - "what is the median
    // font size including this piece?" and "where is this band centred?" -
    // are answered without building or sorting a list. Previously both were
    // recomputed from scratch for every (piece, candidate) pair, which made
    // this O(pieces x bands x bandSize) with an allocation and a sort inside
    // the innermost loop.
    //
    // The scan itself still walks bands in creation order and takes the FIRST
    // match, which is load-bearing: band centres are running means, so an
    // earlier band can drift back within tolerance of a later piece. Taking
    // the most recent band instead - tempting, since pieces arrive sorted by
    // descending centreY - is not equivalent.
    final bands = <_LineBand>[];
    for (final piece in pieces) {
      _LineBand? band;
      for (final candidate in bands) {
        final tolerance = math.max(
            2.0, 0.55 * _medianWith(candidate.fontSizes, piece.fontSize));
        if ((piece.centerY - candidate.center).abs() <= tolerance) {
          band = candidate;
          break;
        }
      }
      (band ?? (bands..add(_LineBand())).last).add(piece);
    }

    final out = <PdfReflowLine>[];
    for (final band in bands) {
      final pieces = band.pieces
        ..sort((a, b) => a.bounds.left.compareTo(b.bounds.left));
      var current = <_LinePiece>[];
      var currentFonts = <double>[];
      for (final piece in pieces) {
        if (current.isNotEmpty) {
          final previous = current.last;
          final gap = piece.bounds.left - previous.bounds.right;
          final font = _medianWith(currentFonts, piece.fontSize);
          if (gap > math.max(36.0, font * 4.0)) {
            out.add(_lineFrom(current));
            current = <_LinePiece>[];
            currentFonts = <double>[];
          }
        }
        current.add(piece);
        _insertSorted(currentFonts, piece.fontSize);
      }
      if (current.isNotEmpty) out.add(_lineFrom(current));
    }
    return out;
  }

  static PdfReflowLine _lineFrom(List<_LinePiece> pieces) {
    final logicalOrder = pieces.any((piece) => piece.isRightToLeft);
    final ordered = logicalOrder
        ? ([...pieces]..sort((a, b) => a.startIndex.compareTo(b.startIndex)))
        : pieces;
    final buffer = StringBuffer();
    _LinePiece? previous;
    for (final piece in ordered) {
      if (previous != null) {
        if (logicalOrder) {
          final gap =
              piece.startIndex - (previous.startIndex + previous.text.length);
          if (gap > 0) buffer.write(' ');
        } else {
          final gap = piece.bounds.left - previous.bounds.right;
          final font = (piece.fontSize + previous.fontSize) / 2;
          if (gap > math.max(1.0, font * 0.18)) buffer.write(' ');
        }
      }
      buffer.write(piece.text.trim());
      previous = piece;
    }
    return PdfReflowLine(
      text: _normalizeSpaces(buffer.toString()),
      bounds: _union(pieces.map((p) => p.bounds)),
      fontSize: _median(pieces.map((p) => p.fontSize)),
    );
  }

  static List<PdfReflowLine> _orderLines(List<PdfReflowLine> lines) {
    final pageBounds = _union(lines.map((line) => line.bounds));
    final candidates = lines
        .where((line) => line.bounds.width < pageBounds.width * 0.72)
        .toList();
    if (candidates.length < 4) return _topDown(lines);

    final columns = <_Column>[];
    for (final line in _topDown(candidates)) {
      _Column? best;
      var bestOverlap = 0.0;
      for (final column in columns) {
        final overlap = _horizontalOverlap(line.bounds, column.bounds);
        final ratio =
            overlap / math.min(line.bounds.width, column.bounds.width);
        if (ratio > bestOverlap) {
          bestOverlap = ratio;
          best = column;
        }
      }
      if (best != null && bestOverlap >= 0.28) {
        best.add(line);
      } else {
        columns.add(_Column(line));
      }
    }
    columns.removeWhere((column) => column.lines.length < 2);
    if (columns.length < 2) return _topDown(lines);
    columns.sort((a, b) => a.bounds.left.compareTo(b.bounds.left));

    final ordered = <PdfReflowLine>[];
    final assigned = <PdfReflowLine>{};
    final spanning = <PdfReflowLine>[];
    for (final line in _topDown(lines)) {
      final hits = columns
          .where((column) =>
              _horizontalOverlap(line.bounds, column.bounds) >
              math.min(line.bounds.width, column.bounds.width) * 0.2)
          .length;
      if (hits > 1 || line.bounds.width >= pageBounds.width * 0.72) {
        spanning.add(line);
        assigned.add(line);
      }
    }

    var spanIndex = 0;
    for (final column in columns) {
      while (spanIndex < spanning.length &&
          spanning[spanIndex].bounds.bottom >= column.bounds.top) {
        ordered.add(spanning[spanIndex++]);
      }
      for (final line in _topDown(column.lines)) {
        if (assigned.add(line)) ordered.add(line);
      }
    }
    while (spanIndex < spanning.length) {
      ordered.add(spanning[spanIndex++]);
    }

    final leftovers = [
      for (final line in _topDown(lines))
        if (assigned.add(line)) line,
    ];
    ordered.addAll(leftovers);
    return ordered;
  }

  static List<PdfReflowLine> _topDown(Iterable<PdfReflowLine> lines) =>
      [...lines]..sort((a, b) {
          final y = b.bounds.top.compareTo(a.bounds.top);
          return y != 0 ? y : a.bounds.left.compareTo(b.bounds.left);
        });

  static List<PdfReflowBlock> _paragraphs(List<PdfReflowLine> lines) {
    final blocks = <PdfReflowBlock>[];
    var current = <PdfReflowLine>[];
    PdfReflowLine? previous;
    for (final line in lines) {
      // A bullet/numbered marker always begins a fresh block, so a list reads
      // as separate items instead of collapsing into one run-on paragraph.
      final newBlock = previous != null &&
          (_startsListItem(line.text) || _startsParagraph(previous, line));
      if (newBlock) {
        blocks.add(_blockFrom(current));
        current = <PdfReflowLine>[];
      }
      current.add(line);
      previous = line;
    }
    if (current.isNotEmpty) blocks.add(_blockFrom(current));
    return blocks;
  }

  /// A line that opens with a bullet glyph or an enumerator (`1.`, `a)`,
  /// `(iv)`) followed by whitespace - the start of a list item.
  static final RegExp _listMarker = RegExp(r'^\s*([•‣◦⁃∙·▪●❖*\-–-]'
      r'|\(?([0-9]{1,3}|[A-Za-z]|[ivxlcdmIVXLCDM]{1,5})[.)])\s+\S');

  static bool _startsListItem(String text) => _listMarker.hasMatch(text);

  static bool _startsParagraph(PdfReflowLine previous, PdfReflowLine next) {
    final font = (previous.fontSize + next.fontSize) / 2;
    final verticalGap = previous.bounds.bottom - next.bounds.top;
    if (verticalGap > font * 0.85) return true;
    final overlap = _horizontalOverlap(previous.bounds, next.bounds);
    if (overlap <= 0) return true;
    final leftShift = next.bounds.left - previous.bounds.left;
    return leftShift.abs() > font * 4.0;
  }

  static PdfReflowBlock _blockFrom(List<PdfReflowLine> lines) {
    final buffer = StringBuffer();
    for (final line in lines) {
      if (buffer.isEmpty) {
        buffer.write(line.text);
        continue;
      }
      final soFar = buffer.toString();
      if (soFar.endsWith('-') && line.text.isNotEmpty) {
        buffer
          ..clear()
          ..write(soFar.substring(0, soFar.length - 1))
          ..write(line.text);
      } else {
        buffer
          ..write(' ')
          ..write(line.text);
      }
    }
    return PdfReflowBlock(
      text: _normalizeSpaces(buffer.toString()),
      bounds: _union(lines.map((line) => line.bounds)),
      lines: List.unmodifiable(lines),
      fontSize: _median(lines.map((line) => line.fontSize)),
      isListItem: lines.isNotEmpty && _startsListItem(lines.first.text),
    );
  }
}

class _LinePiece {
  const _LinePiece({
    required this.text,
    required this.bounds,
    required this.fontSize,
    required this.startIndex,
    required this.isRightToLeft,
  });

  factory _LinePiece.fromRun(PdfExtractedRun run) => _LinePiece(
        text: run.text,
        bounds: run.bounds,
        fontSize: math.max(1.0, run.transform.scaleFactor),
        startIndex: run.startIndex,
        isRightToLeft: run.isRightToLeft,
      );

  final String text;
  final PdfRect bounds;
  final double fontSize;
  final int startIndex;
  final bool isRightToLeft;

  double get centerY => (bounds.bottom + bounds.top) / 2;
}

class _SourceRun {
  const _SourceRun(this.separator, this.run);

  final String separator;
  final PdfTextRun run;
}

class _SourceCluster {
  const _SourceCluster(this.sources, this.anchor);

  final List<_SourceRun> sources;
  final PdfTextRun anchor;
}

enum _BidiKind { ltr, rtl, neutral }

class _BidiPiece {
  const _BidiPiece(
    this.text,
    this.kind,
    this.source,
    this.sourceStart,
    this.sourceEnd,
    this.preserveText,
    this.sourceX0,
    this.sourceX1,
  );

  final String text;
  final _BidiKind kind;
  final PdfTextRun? source;
  final int sourceStart;
  final int sourceEnd;
  final bool preserveText;
  final double? sourceX0;
  final double? sourceX1;
}

class _BidiGroup {
  const _BidiGroup(this.kind, this.pieces);

  final _BidiKind kind;
  final List<_BidiPiece> pieces;
}

class _BidiLine {
  const _BidiLine(this.groups, {required this.rightToLeft});

  final List<_BidiGroup> groups;
  final bool rightToLeft;
}

/// Directional class used by the visual-to-logical PDF text pass. Numbers
/// stay left-to-right inside an RTL line; non-spacing marks inherit the
/// preceding visual character per UAX #9 rule W1, so reversing the RTL run
/// restores them after their logical base character.
_BidiKind _bidiKind(int rune, _BidiKind? previous) {
  // The bidi package's compact table covers the BMP. Preserve the strong RTL
  // class for supplementary-plane RTL scripts that otherwise default to LTR.
  if ((rune >= 0x10800 && rune <= 0x10FFF) ||
      (rune >= 0x1E800 && rune <= 0x1EDFF)) {
    return _BidiKind.rtl;
  }
  return switch (bidi.getCharacterType(rune)) {
    bidi.CharacterType.rtl ||
    bidi.CharacterType.al ||
    bidi.CharacterType.rle ||
    bidi.CharacterType.rlo ||
    bidi.CharacterType.rli =>
      _BidiKind.rtl,
    bidi.CharacterType.ltr ||
    bidi.CharacterType.lre ||
    bidi.CharacterType.lro ||
    bidi.CharacterType.lri ||
    bidi.CharacterType.en ||
    bidi.CharacterType.an =>
      _BidiKind.ltr,
    bidi.CharacterType.nonspacingMark => previous ?? _BidiKind.rtl,
    _ => _BidiKind.neutral,
  };
}

/// Strong direction only, for choosing a plain-text paragraph isolate.
/// Numbers and neutral/formatting characters deliberately return null.
_BidiKind? _strongBidiKind(int rune) {
  if ((rune >= 0x10800 && rune <= 0x10FFF) ||
      (rune >= 0x1E800 && rune <= 0x1EDFF)) {
    return _BidiKind.rtl;
  }
  return switch (bidi.getCharacterType(rune)) {
    bidi.CharacterType.rtl || bidi.CharacterType.al => _BidiKind.rtl,
    bidi.CharacterType.ltr => _BidiKind.ltr,
    _ => null,
  };
}

String _reverseRunes(String text) =>
    String.fromCharCodes(text.runes.toList().reversed);

class _Column {
  _Column(PdfReflowLine line)
      : lines = [line],
        bounds = line.bounds;

  final List<PdfReflowLine> lines;
  PdfRect bounds;

  void add(PdfReflowLine line) {
    lines.add(line);
    bounds = _union([bounds, line.bounds]);
  }
}

/// Quad of the em-space span [x0]..[x1] (with conventional 0.25 em descent
/// and 0.75 em ascent) mapped through [transform], in perimeter order
/// (ll, lr, ur, ul). Rotated text yields a rotated parallelogram.
PdfTextQuad _quadOf(
  PdfMatrix transform,
  double x0,
  double x1, {
  bool isRightToLeft = false,
}) {
  const descent = -0.25;
  const ascent = 0.75;
  return PdfTextQuad(
    [
      for (final (x, y) in [
        (x0, descent),
        (x1, descent),
        (x1, ascent),
        (x0, ascent),
      ])
        (transform.transformX(x, y), transform.transformY(x, y)),
    ],
    isRightToLeft: isRightToLeft,
  );
}

/// Axis-aligned bounding box of the em-space span [x0]..[x1] mapped
/// through [transform].
PdfRect _boundsOf(PdfMatrix transform, double x0, double x1) =>
    _quadOf(transform, x0, x1).bounds;

PdfRect _union(Iterable<PdfRect> rects) {
  final iterator = rects.iterator;
  if (!iterator.moveNext()) return const PdfRect(0, 0, 0, 0);
  var left = iterator.current.left;
  var bottom = iterator.current.bottom;
  var right = iterator.current.right;
  var top = iterator.current.top;
  while (iterator.moveNext()) {
    final rect = iterator.current;
    left = math.min(left, rect.left);
    bottom = math.min(bottom, rect.bottom);
    right = math.max(right, rect.right);
    top = math.max(top, rect.top);
  }
  return PdfRect(left, bottom, right, top);
}

double _horizontalOverlap(PdfRect a, PdfRect b) =>
    math.max(0.0, math.min(a.right, b.right) - math.max(a.left, b.left));

/// Area of the intersection of [a] and [b] over the smaller of their areas
/// (0 when they don't overlap, 1 when one contains the other).
double _overlapFraction(PdfRect a, PdfRect b) {
  final w = _horizontalOverlap(a, b);
  final h =
      math.max(0.0, math.min(a.top, b.top) - math.max(a.bottom, b.bottom));
  final overlap = w * h;
  if (overlap <= 0) return 0;
  final smaller = math.min(a.width * a.height, b.width * b.height);
  return smaller <= 0 ? 0 : overlap / smaller;
}

/// Index where [value] would be inserted to keep [sorted] ascending.
int _lowerBound(List<double> sorted, double value) {
  var lo = 0;
  var hi = sorted.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (sorted[mid] < value) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}

void _insertSorted(List<double> sorted, double value) =>
    sorted.insert(_lowerBound(sorted, value), value);

/// Median of [sorted] (ascending) with [extra] merged in, without building
/// the merged list.
///
/// Equivalent to `_median([...sorted, extra])`, but the line-banding loop asks
/// this once per piece per candidate band, where materialising and sorting a
/// fresh list dominated the cost of [_visualLines] on a text-heavy page.
double _medianWith(List<double> sorted, double extra) {
  final length = sorted.length + 1;
  final pos = _lowerBound(sorted, extra);
  // the merged sequence is sorted[0..pos) + [extra] + sorted[pos..)
  double at(int rank) =>
      rank < pos ? sorted[rank] : (rank == pos ? extra : sorted[rank - 1]);
  final middle = length ~/ 2;
  if (length.isOdd) return at(middle);
  return (at(middle - 1) + at(middle)) / 2;
}

/// A run of pieces sharing a visual line, with the aggregates the banding
/// scan needs kept incrementally rather than recomputed per comparison.
class _LineBand {
  final List<_LinePiece> pieces = [];

  /// Ascending, so [_medianWith] can merge one more value in O(log n).
  final List<double> fontSizes = [];

  double _sumCenterY = 0;

  double get center => _sumCenterY / pieces.length;

  void add(_LinePiece piece) {
    pieces.add(piece);
    _insertSorted(fontSizes, piece.fontSize);
    _sumCenterY += piece.centerY;
  }
}

double _median(Iterable<double> values) {
  final sorted = [...values]..sort();
  if (sorted.isEmpty) return 0;
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle];
  return (sorted[middle - 1] + sorted[middle]) / 2;
}

String _normalizeSpaces(String text) =>
    text.replaceAll(RegExp(r'[ \t\f\v]+'), ' ').trim();

class _ExtractionDevice implements PdfDevice {
  final List<PdfTextRun> runs = [];
  final List<PdfImageRequest> images = [];

  @override
  void drawText(PdfTextRun run) => runs.add(run);

  @override
  void save() {}
  @override
  void restore() {}
  @override
  void fillPath(PdfPath path, PdfColor color, PdfFillRule rule, double a) {}
  @override
  void fillPathGradient(
      PdfPath path, PdfFillRule rule, PdfGradient gradient, double a) {}
  @override
  void fillMesh(PdfMesh mesh, double a) {}
  @override
  void strokePath(PdfPath path, PdfColor color, PdfStroke stroke, double a) {}
  @override
  void clipPath(PdfPath path, PdfFillRule rule) {}
  @override
  void drawImage(PdfImageRequest request) => images.add(request);

  @override
  void setBlendMode(PdfBlendMode mode) {}
  @override
  void setOverprint(
      {required bool fill, required bool stroke, required int mode}) {}
  @override
  void beginGroup(double alpha, {bool knockout = false}) {}
  @override
  void endGroup() {}
  @override
  void beginSoftMasked() {}
  @override
  void endSoftMasked(
      {required bool luminosity,
      required PdfRect backdrop,
      required void Function() drawMask,
      double backdropLuminance = 0,
      double transferScale = 1,
      double transferOffset = 0}) {}
}
