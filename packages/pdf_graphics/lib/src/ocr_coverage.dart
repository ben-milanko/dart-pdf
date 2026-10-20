import 'package:pdf_document/pdf_document.dart';

import 'text_extraction.dart';

/// The share of a span's box that must already be covered by the page's own
/// text for [ocrSpansNotIn] to treat the span as a duplicate.
const double defaultOcrDuplicateCoverage = 0.5;

/// Returns the [spans] that do **not** repeat text [existing] already
/// carries - the filter that keeps OCR from writing a second copy of words
/// the page can already select, search, and extract.
///
/// OCR reads the page raster, so it recognizes born-digital text just as
/// happily as scanned text; injecting those spans would duplicate every
/// such word in extraction, search hits, and copy/paste. The same goes for a
/// page that already carries an (invisible, render mode 3) OCR layer from an
/// earlier pass or another tool: the extractor sees that layer too, so
/// re-running OCR only fills in what is still missing.
///
/// A span is dropped when at least [minCoverage] of its area lies under the
/// bounds of the page's existing (non-blank) text runs. The covered area is
/// the true union of those boxes, so text drawn twice (fake bold, a stale
/// layer under a visible one) does not count double.
List<PdfOcrSpan> ocrSpansNotIn(
  PdfPageText existing,
  Iterable<PdfOcrSpan> spans, {
  double minCoverage = defaultOcrDuplicateCoverage,
}) {
  final textBoxes = [
    for (final run in existing.runs)
      if (run.text.trim().isNotEmpty &&
          run.bounds.width > 0 &&
          run.bounds.height > 0)
        run.bounds,
  ];
  if (textBoxes.isEmpty) return spans.toList();
  return [
    for (final span in spans)
      if (_coverage(span.bounds, textBoxes) < minCoverage) span,
  ];
}

/// Fraction of [box]'s area covered by the union of [others].
double _coverage(PdfRect box, List<PdfRect> others) {
  final area = box.width * box.height;
  if (area <= 0) return 0;
  final clipped = [
    for (final other in others)
      if (box.intersect(other) case final r when r.width > 0 && r.height > 0) r,
  ];
  if (clipped.isEmpty) return 0;
  return _unionArea(clipped) / area;
}

/// Exact area of the union of [rects], by coordinate compression - the
/// rects here are only the few text runs touching one OCR span.
double _unionArea(List<PdfRect> rects) {
  if (rects.length == 1) return rects.single.width * rects.single.height;
  final xs = {
    for (final r in rects) ...[r.left, r.right]
  }.toList()
    ..sort();
  var total = 0.0;
  for (var i = 0; i + 1 < xs.length; i++) {
    // xs is de-duplicated and sorted, so every slab has positive width.
    final x0 = xs[i], x1 = xs[i + 1];
    // Merge the y-intervals of the rects spanning this x slab.
    final spansY = [
      for (final r in rects)
        if (r.left <= x0 && r.right >= x1) (r.bottom, r.top),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    var covered = 0.0;
    double? start, end;
    for (final (bottom, top) in spansY) {
      if (end == null || bottom > end) {
        if (end != null) covered += end - start!;
        start = bottom;
        end = top;
      } else if (top > end) {
        end = top;
      }
    }
    if (end != null) covered += end - start!;
    total += covered * (x1 - x0);
  }
  return total;
}
