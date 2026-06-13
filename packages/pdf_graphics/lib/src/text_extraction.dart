import 'dart:math' as math;

import 'package:pdf_document/pdf_document.dart';

import 'color.dart';
import 'device.dart';
import 'interpreter.dart';
import 'matrix.dart';
import 'mesh.dart';
import 'path.dart';
import 'shading.dart';

/// One positioned run of text on a page, in page space.
class PdfExtractedRun {
  const PdfExtractedRun({
    required this.text,
    required this.startIndex,
    required this.transform,
    required this.width,
    required this.bounds,
  });

  final String text;

  /// Offset of [text] inside the owning [PdfPageText.text].
  final int startIndex;

  /// Em space → page space (see [PdfTextRun.transform]).
  final PdfMatrix transform;

  /// Advance width in em units.
  final double width;

  /// Page-space bounding box.
  final PdfRect bounds;
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
  const PdfTextQuad(this.corners);

  /// The four `(x, y)` page-space points in perimeter order (ll, lr, ur,
  /// ul). Always length 4.
  final List<(double x, double y)> corners;

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
  List<PdfTextMatch> findAll(String query, {bool caseSensitive = false}) {
    if (query.isEmpty) return const [];
    final haystack = caseSensitive ? text : text.toLowerCase();
    final needle = caseSensitive ? query : query.toLowerCase();
    final matches = <PdfTextMatch>[];
    var from = 0;
    while (true) {
      final index = haystack.indexOf(needle, from);
      if (index < 0) break;
      final end = index + needle.length;
      final quads = quadsFor(index, end);
      matches.add(PdfTextMatch(
        pageIndex: pageIndex,
        start: index,
        end: end,
        rects: [for (final quad in quads) quad.bounds],
        quads: quads,
      ));
      from = end;
    }
    return matches;
  }

  /// Axis-aligned page-space rectangles covering the characters
  /// [start]..[end] of [text]. Convenience over [quadsFor] for callers
  /// that don't need rotation (e.g. text-markup QuadPoints, scroll-to).
  List<PdfRect> rectsFor(int start, int end) =>
      [for (final quad in quadsFor(start, end)) quad.bounds];

  /// Baseline-aligned page-space quads covering the characters
  /// [start]..[end] of [text] — for selection and search highlights that
  /// rotate with rotated text.
  List<PdfTextQuad> quadsFor(int start, int end) {
    final quads = <PdfTextQuad>[];
    for (final run in runs) {
      if (run.text.isEmpty) continue;
      final runEnd = run.startIndex + run.text.length;
      final overlapStart = math.max(start, run.startIndex);
      final overlapEnd = math.min(end, runEnd);
      if (overlapStart >= overlapEnd) continue;
      // approximate within-run positions by character fraction; per-glyph
      // geometry arrives with the font engine
      final f0 = (overlapStart - run.startIndex) / run.text.length;
      final f1 = (overlapEnd - run.startIndex) / run.text.length;
      quads.add(_quadOf(run.transform, run.width * f0, run.width * f1));
    }
    return quads;
  }

  /// The page text inside [rect] (page space): runs whose bounds center
  /// falls within the rect, in document order, joined with single
  /// spaces. The text a /Link annotation's rectangle covers, for one.
  String textIn(PdfRect rect) {
    final parts = <(int, String)>[];
    for (final run in runs) {
      final piece = run.text.trim();
      if (piece.isEmpty) continue;
      final b = run.bounds;
      if (rect.contains((b.left + b.right) / 2, (b.bottom + b.top) / 2)) {
        parts.add((run.startIndex, piece));
      }
    }
    parts.sort((a, b) => a.$1.compareTo(b.$1));
    return parts.map((part) => part.$2).join(' ');
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
    // fraction along the run's baseline, in em space
    final inverse = best.transform.inverted();
    final ex = inverse == null ? 0.0 : inverse.transformX(x, y);
    final fraction = best.width > 0 ? (ex / best.width).clamp(0.0, 1.0) : 0.0;
    return best.startIndex + (fraction * best.text.length).round();
  }
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

/// One paragraph-like block in reading order.
class PdfReflowBlock {
  const PdfReflowBlock({
    required this.text,
    required this.bounds,
    required this.lines,
    required this.fontSize,
  });

  /// Text with line breaks removed and soft hyphens repaired.
  final String text;

  /// Page-space bounds of the source lines.
  final PdfRect bounds;

  final List<PdfReflowLine> lines;

  /// Median source font size for display heuristics.
  final double fontSize;
}

/// A page's text reduced to paragraph blocks in inferred reading order.
class PdfReflowPage {
  const PdfReflowPage({
    required this.pageIndex,
    required this.blocks,
  });

  final int pageIndex;
  final List<PdfReflowBlock> blocks;

  String get text => blocks.map((block) => block.text).join('\n\n');
}

/// Document-level convenience wrapper for reflowed text.
class PdfReflowDocument {
  const PdfReflowDocument({required this.pages});

  final List<PdfReflowPage> pages;

  String get text => pages.map((page) => page.text).join('\n\n');
}

/// Extracts positioned text by running the interpreter with a collecting
/// device — the same code path rendering uses, so what you search is what
/// you see.
class PdfTextExtractor {
  PdfTextExtractor._();

  static PdfPageText extract(PdfDocument document, int pageIndex) {
    final device = _ExtractionDevice();
    PdfInterpreter(cos: document.cos, device: device)
        .drawPage(document.page(pageIndex));

    final buffer = StringBuffer();
    final runs = <PdfExtractedRun>[];
    PdfTextRun? previous;
    for (final run in device.runs) {
      if (previous != null) {
        buffer.write(_separator(previous, run));
      }
      final start = buffer.length;
      buffer.write(run.text);
      runs.add(PdfExtractedRun(
        text: run.text,
        startIndex: start,
        transform: run.transform,
        width: run.width,
        bounds: _boundsOf(run.transform, 0, run.width),
      ));
      previous = run;
    }
    return PdfPageText(
        pageIndex: pageIndex, text: buffer.toString(), runs: runs);
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

  /// Extracts one page and infers paragraph blocks in reading order.
  static PdfReflowPage reflowPage(PdfDocument document, int pageIndex) =>
      PdfTextReflower.reflow(extract(document, pageIndex));

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

  static PdfReflowPage reflow(PdfPageText page) {
    final lines = _visualLines(page.runs);
    if (lines.isEmpty) {
      return PdfReflowPage(pageIndex: page.pageIndex, blocks: const []);
    }
    final ordered = _orderLines(lines);
    return PdfReflowPage(
      pageIndex: page.pageIndex,
      blocks: _paragraphs(ordered),
    );
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

    final bands = <List<_LinePiece>>[];
    for (final piece in pieces) {
      List<_LinePiece>? band;
      for (final candidate in bands) {
        final tolerance = math.max(
            2.0,
            0.55 *
                _median([
                  piece.fontSize,
                  ...candidate.map((p) => p.fontSize),
                ]));
        final center = candidate.map((p) => p.centerY).reduce((a, b) => a + b) /
            candidate.length;
        if ((piece.centerY - center).abs() <= tolerance) {
          band = candidate;
          break;
        }
      }
      (band ?? (bands..add(<_LinePiece>[])).last).add(piece);
    }

    final out = <PdfReflowLine>[];
    for (final band in bands) {
      band.sort((a, b) => a.bounds.left.compareTo(b.bounds.left));
      var current = <_LinePiece>[];
      for (final piece in band) {
        if (current.isNotEmpty) {
          final previous = current.last;
          final gap = piece.bounds.left - previous.bounds.right;
          final font =
              _median([...current.map((p) => p.fontSize), piece.fontSize]);
          if (gap > math.max(36.0, font * 4.0)) {
            out.add(_lineFrom(current));
            current = <_LinePiece>[];
          }
        }
        current.add(piece);
      }
      if (current.isNotEmpty) out.add(_lineFrom(current));
    }
    return out;
  }

  static PdfReflowLine _lineFrom(List<_LinePiece> pieces) {
    final buffer = StringBuffer();
    _LinePiece? previous;
    for (final piece in pieces) {
      if (previous != null) {
        final gap = piece.bounds.left - previous.bounds.right;
        final font = (piece.fontSize + previous.fontSize) / 2;
        if (gap > math.max(1.0, font * 0.18)) buffer.write(' ');
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
      if (previous != null && _startsParagraph(previous, line)) {
        blocks.add(_blockFrom(current));
        current = <PdfReflowLine>[];
      }
      current.add(line);
      previous = line;
    }
    if (current.isNotEmpty) blocks.add(_blockFrom(current));
    return blocks;
  }

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
    );
  }
}

class _LinePiece {
  const _LinePiece({
    required this.text,
    required this.bounds,
    required this.fontSize,
  });

  factory _LinePiece.fromRun(PdfExtractedRun run) => _LinePiece(
        text: run.text,
        bounds: run.bounds,
        fontSize: math.max(1.0, run.transform.scaleFactor),
      );

  final String text;
  final PdfRect bounds;
  final double fontSize;

  double get centerY => (bounds.bottom + bounds.top) / 2;
}

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
PdfTextQuad _quadOf(PdfMatrix transform, double x0, double x1) {
  const descent = -0.25;
  const ascent = 0.75;
  return PdfTextQuad([
    for (final (x, y) in [
      (x0, descent),
      (x1, descent),
      (x1, ascent),
      (x0, ascent),
    ])
      (transform.transformX(x, y), transform.transformY(x, y)),
  ]);
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
  void drawImage(PdfImageRequest request) {}

  @override
  void setBlendMode(PdfBlendMode mode) {}
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
