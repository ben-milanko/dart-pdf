import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

import 'page_comparison.dart';

/// How two documents' pages line up.
enum PdfPagePairKind {
  /// Both documents have the page (compared in place).
  matched,

  /// Only the after document has it (added).
  inserted,

  /// Only the before document had it (removed).
  removed,
}

/// One aligned page pair.
class PdfPagePair {
  const PdfPagePair({this.beforeIndex, this.afterIndex});

  /// Page index in the before document, or null when inserted.
  final int? beforeIndex;

  /// Page index in the after document, or null when removed.
  final int? afterIndex;

  PdfPagePairKind get kind => beforeIndex == null
      ? PdfPagePairKind.inserted
      : afterIndex == null
          ? PdfPagePairKind.removed
          : PdfPagePairKind.matched;
}

/// What a [PdfDiffChange] is.
enum PdfDiffChangeKind { inserted, deleted, replaced, pageInserted, pageRemoved }

/// A single navigation stop in the diff — a text hunk on a page, or a whole
/// inserted/removed page. Carries the page-space bounds on each side so a
/// side-by-side view can frame both panes and an overlay can frame one.
class PdfDiffChange {
  const PdfDiffChange({
    required this.kind,
    required this.label,
    this.beforePage,
    this.afterPage,
    this.beforeBounds,
    this.afterBounds,
  });

  final PdfDiffChangeKind kind;

  /// A short description for the navigator list.
  final String label;

  final int? beforePage;
  final int? afterPage;
  final PdfRect? beforeBounds;
  final PdfRect? afterBounds;

  /// The page index to surface this change on in the after document (or the
  /// before document for a pure removal).
  int get displayPage => afterPage ?? beforePage ?? 0;
}

/// Drives a document comparison view: it pairs the two documents' pages,
/// computes a word-level text diff per matched page (a [PdfTextDiff]), and
/// exposes the resulting changes as an ordered, navigable list — the
/// model behind the diff navigator panel.
///
/// v1 pairs pages by index: matched in the common range, trailing extra
/// pages on either side become inserted/removed. Mid-document insertions
/// therefore mis-align following pages — a documented limitation; a
/// content-similarity pairing is the planned upgrade.
///
/// Pixel diffs (for the overlay mode and CAD-style drawings without text)
/// are produced lazily through [pixelDiff]; they are not part of the
/// navigator list, which is text- and structure-driven.
class PdfComparisonController extends ChangeNotifier {
  PdfComparisonController({
    required this.before,
    required this.after,
    this.pixelRatio = 1.5,
  });

  final PdfDocument before;
  final PdfDocument after;

  /// Resolution the overlay pixel diffs render at.
  final double pixelRatio;

  late final List<PdfPagePair> pairs = _pairPages();

  List<PdfDiffChange> _changes = const [];
  bool _built = false;
  int _current = -1;

  /// The ordered change list. Empty until [build] runs.
  List<PdfDiffChange> get changes => _changes;

  /// Index into [changes] of the active stop, or -1.
  int get currentChange => _current;

  bool get hasChanges => _changes.isNotEmpty;

  /// Computes the text- and structure-level change list. Synchronous (no
  /// rasterization); interprets each matched page once per side. Idempotent.
  void build() {
    if (_built) return;
    _built = true;
    _changes = _buildChanges();
    _current = _changes.isEmpty ? -1 : 0;
    notifyListeners();
  }

  void goToChange(int index) {
    if (index < 0 || index >= _changes.length) return;
    _current = index;
    notifyListeners();
  }

  void nextChange() {
    if (_changes.isEmpty) return;
    _current = (_current + 1) % _changes.length;
    notifyListeners();
  }

  void previousChange() {
    if (_changes.isEmpty) return;
    _current = (_current - 1 + _changes.length) % _changes.length;
    notifyListeners();
  }

  final Map<int, PdfPageDiff> _pixelCache = {};

  /// The pixel diff for pair [pairIndex], rendered once and cached.
  Future<PdfPageDiff> pixelDiff(int pairIndex) async {
    final cached = _pixelCache[pairIndex];
    if (cached != null) return cached;
    final pair = pairs[pairIndex];
    final diff = await PdfPageComparison.comparePages(
      pair.beforeIndex == null ? null : before.page(pair.beforeIndex!),
      pair.afterIndex == null ? null : after.page(pair.afterIndex!),
      pixelRatio: pixelRatio,
    );
    _pixelCache[pairIndex] = diff;
    return diff;
  }

  /// The pair index that displays after-document page [afterIndex], or -1.
  int pairForAfterPage(int afterIndex) {
    for (var i = 0; i < pairs.length; i++) {
      if (pairs[i].afterIndex == afterIndex) return i;
    }
    return -1;
  }

  List<PdfPagePair> _pairPages() {
    final n = before.pageCount;
    final m = after.pageCount;
    return [
      for (var i = 0; i < math.max(n, m); i++)
        PdfPagePair(
          beforeIndex: i < n ? i : null,
          afterIndex: i < m ? i : null,
        ),
    ];
  }

  List<PdfDiffChange> _buildChanges() {
    final changes = <PdfDiffChange>[];
    for (final pair in pairs) {
      switch (pair.kind) {
        case PdfPagePairKind.inserted:
          changes.add(PdfDiffChange(
            kind: PdfDiffChangeKind.pageInserted,
            afterPage: pair.afterIndex,
            label: 'Page ${pair.afterIndex! + 1} added',
          ));
        case PdfPagePairKind.removed:
          changes.add(PdfDiffChange(
            kind: PdfDiffChangeKind.pageRemoved,
            beforePage: pair.beforeIndex,
            label: 'Page ${pair.beforeIndex! + 1} removed',
          ));
        case PdfPagePairKind.matched:
          final beforeText =
              PdfTextExtractor.extract(before, pair.beforeIndex!);
          final afterText = PdfTextExtractor.extract(after, pair.afterIndex!);
          final diff = PdfTextDiff.between(beforeText, afterText);
          for (final hunk in diff.hunks) {
            changes.add(PdfDiffChange(
              kind: hunk.isInsertion
                  ? PdfDiffChangeKind.inserted
                  : hunk.isDeletion
                      ? PdfDiffChangeKind.deleted
                      : PdfDiffChangeKind.replaced,
              beforePage: pair.beforeIndex,
              afterPage: pair.afterIndex,
              beforeBounds: _unionTokens(hunk.before),
              afterBounds: _unionTokens(hunk.after),
              label: _hunkLabel(hunk),
            ));
          }
      }
    }
    return changes;
  }
}

PdfRect? _unionTokens(List<PdfTextToken> tokens) {
  PdfRect? box;
  for (final t in tokens) {
    final b = t.bounds;
    if (b == null) continue;
    box = box == null
        ? b
        : PdfRect(
            math.min(box.left, b.left),
            math.min(box.bottom, b.bottom),
            math.max(box.right, b.right),
            math.max(box.top, b.top),
          );
  }
  return box;
}

String _hunkLabel(PdfTextDiffHunk hunk) {
  String text(List<PdfTextToken> tokens) =>
      tokens.map((t) => t.text).join(' ');
  if (hunk.isInsertion) return _cap(text(hunk.after));
  if (hunk.isDeletion) return _cap(text(hunk.before));
  return '${_cap(text(hunk.before))} → ${_cap(text(hunk.after))}';
}

String _cap(String s, {int max = 60}) {
  final collapsed = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (collapsed.length <= max) return collapsed;
  return '${collapsed.substring(0, max - 1)}…';
}
