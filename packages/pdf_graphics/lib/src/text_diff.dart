import 'dart:math' as math;

import 'package:pdf_document/pdf_document.dart';

import 'text_extraction.dart';

/// A whitespace-delimited token of page text, with the page-space box it
/// covers — the unit a [PdfTextDiff] aligns and the bounds a viewer
/// highlights when it flags the token as changed.
class PdfTextToken {
  const PdfTextToken({
    required this.text,
    required this.start,
    required this.end,
    required this.bounds,
  });

  /// The token's characters (no surrounding whitespace).
  final String text;

  /// Half-open `[start, end)` range into the owning [PdfPageText.text].
  final int start;
  final int end;

  /// The axis-aligned page-space box covering the token, or null when the
  /// page exposed no geometry for it (rare — empty/degenerate runs).
  final PdfRect? bounds;
}

/// Splits a page's extracted text into word tokens (maximal runs of
/// non-whitespace) with their page-space bounds.
///
/// Bounds come from [PdfPageText.rectsFor], unioned across the runs a
/// token spans, so a token broken across positioned runs still gets one
/// covering box.
List<PdfTextToken> tokenizePageText(PdfPageText page) {
  final tokens = <PdfTextToken>[];
  final text = page.text;
  final pattern = RegExp(r'\S+');
  for (final match in pattern.allMatches(text)) {
    final start = match.start;
    final end = match.end;
    tokens.add(PdfTextToken(
      text: text.substring(start, end),
      start: start,
      end: end,
      bounds: _union(page.rectsFor(start, end)),
    ));
  }
  return tokens;
}

PdfRect? _union(List<PdfRect> rects) {
  if (rects.isEmpty) return null;
  var left = rects.first.left;
  var bottom = rects.first.bottom;
  var right = rects.first.right;
  var top = rects.first.top;
  for (final r in rects.skip(1)) {
    left = math.min(left, r.left);
    bottom = math.min(bottom, r.bottom);
    right = math.max(right, r.right);
    top = math.max(top, r.top);
  }
  return PdfRect(left, bottom, right, top);
}

/// What a [PdfTextDiffSegment] represents.
enum PdfTextDiffKind {
  /// Tokens present, unchanged, in both pages.
  equal,

  /// Tokens only in the "after" page (added).
  inserted,

  /// Tokens only in the "before" page (removed).
  deleted,
}

/// One run of the alignment between two pages' token streams.
class PdfTextDiffSegment {
  const PdfTextDiffSegment({
    required this.kind,
    required this.before,
    required this.after,
  });

  final PdfTextDiffKind kind;

  /// Tokens from the "before" page ([PdfTextDiffKind.equal] and
  /// [PdfTextDiffKind.deleted]); empty for inserts.
  final List<PdfTextToken> before;

  /// Tokens from the "after" page ([PdfTextDiffKind.equal] and
  /// [PdfTextDiffKind.inserted]); empty for deletes.
  final List<PdfTextToken> after;
}

/// A contiguous change — one or more adjacent non-[PdfTextDiffKind.equal]
/// segments, the unit a diff navigator steps through. A pure replace is a
/// delete next to an insert, so a hunk carries both [before] and [after]
/// tokens.
class PdfTextDiffHunk {
  const PdfTextDiffHunk({required this.before, required this.after});

  /// Removed/replaced tokens, on the before page.
  final List<PdfTextToken> before;

  /// Added/replacing tokens, on the after page.
  final List<PdfTextToken> after;

  bool get isInsertion => before.isEmpty;
  bool get isDeletion => after.isEmpty;
}

/// A word-level diff of two pages' extracted text, computed as a longest
/// common subsequence over their token streams (a standard sequence diff),
/// with each changed token mapped back to its page-space bounds for
/// highlight overlays.
class PdfTextDiff {
  const PdfTextDiff(this.segments);

  /// The alignment, in document order, alternating equal/changed runs.
  final List<PdfTextDiffSegment> segments;

  /// Diffs the extracted text of two pages.
  factory PdfTextDiff.between(PdfPageText before, PdfPageText after) =>
      PdfTextDiff(_diffTokens(
          tokenizePageText(before), tokenizePageText(after)));

  /// Diffs page [index] of two documents directly.
  static PdfTextDiff betweenPages(
          PdfDocument before, PdfDocument after, int index) =>
      PdfTextDiff.between(
        PdfTextExtractor.extract(before, index),
        PdfTextExtractor.extract(after, index),
      );

  bool get hasChanges =>
      segments.any((s) => s.kind != PdfTextDiffKind.equal);

  /// Tokens removed from the before page.
  List<PdfTextToken> get deletedTokens => [
        for (final s in segments)
          if (s.kind == PdfTextDiffKind.deleted) ...s.before
      ];

  /// Tokens added to the after page.
  List<PdfTextToken> get insertedTokens => [
        for (final s in segments)
          if (s.kind == PdfTextDiffKind.inserted) ...s.after
      ];

  /// The changes grouped into contiguous hunks — adjacent delete/insert
  /// segments merge so a replacement is one navigation stop, not two.
  List<PdfTextDiffHunk> get hunks {
    final hunks = <PdfTextDiffHunk>[];
    final before = <PdfTextToken>[];
    final after = <PdfTextToken>[];
    void flush() {
      if (before.isEmpty && after.isEmpty) return;
      hunks.add(PdfTextDiffHunk(
          before: List.of(before), after: List.of(after)));
      before.clear();
      after.clear();
    }

    for (final s in segments) {
      if (s.kind == PdfTextDiffKind.equal) {
        flush();
      } else {
        before.addAll(s.before);
        after.addAll(s.after);
      }
    }
    flush();
    return hunks;
  }
}

List<PdfTextDiffSegment> _diffTokens(
    List<PdfTextToken> a, List<PdfTextToken> b) {
  final n = a.length;
  final m = b.length;
  if (n == 0 && m == 0) return const [];

  // LCS length table over token text equality.
  final lcs = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      if (a[i].text == b[j].text) {
        lcs[i][j] = lcs[i + 1][j + 1] + 1;
      } else {
        lcs[i][j] = math.max(lcs[i + 1][j], lcs[i][j + 1]);
      }
    }
  }

  final segments = <PdfTextDiffSegment>[];
  // Coalesce consecutive ops of the same kind into one segment.
  final equalBefore = <PdfTextToken>[];
  final equalAfter = <PdfTextToken>[];
  final deleted = <PdfTextToken>[];
  final inserted = <PdfTextToken>[];

  void flushEqual() {
    if (equalBefore.isEmpty) return;
    segments.add(PdfTextDiffSegment(
      kind: PdfTextDiffKind.equal,
      before: List.of(equalBefore),
      after: List.of(equalAfter),
    ));
    equalBefore.clear();
    equalAfter.clear();
  }

  void flushChanges() {
    if (deleted.isNotEmpty) {
      segments.add(PdfTextDiffSegment(
        kind: PdfTextDiffKind.deleted,
        before: List.of(deleted),
        after: const [],
      ));
      deleted.clear();
    }
    if (inserted.isNotEmpty) {
      segments.add(PdfTextDiffSegment(
        kind: PdfTextDiffKind.inserted,
        before: const [],
        after: List.of(inserted),
      ));
      inserted.clear();
    }
  }

  var i = 0, j = 0;
  while (i < n && j < m) {
    if (a[i].text == b[j].text) {
      flushChanges();
      equalBefore.add(a[i]);
      equalAfter.add(b[j]);
      i++;
      j++;
    } else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
      flushEqual();
      deleted.add(a[i]);
      i++;
    } else {
      flushEqual();
      inserted.add(b[j]);
      j++;
    }
  }
  while (i < n) {
    flushEqual();
    deleted.add(a[i]);
    i++;
  }
  while (j < m) {
    flushEqual();
    inserted.add(b[j]);
    j++;
  }
  flushEqual();
  flushChanges();
  return segments;
}
