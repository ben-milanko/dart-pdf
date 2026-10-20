part of 'editor.dart';

/// Which pages of a source a [PdfPageInsertSource.select] keeps, counted by
/// the source's one-based page numbers.
enum PdfPageSubset {
  /// Every selected page.
  all,

  /// Pages 1, 3, 5, ... only.
  odd,

  /// Pages 2, 4, 6, ... only.
  even,
}

/// How [PdfPageInsertion.insertPages] weaves inserted pages into the
/// existing ones instead of inserting them as one block.
///
/// Starting at the insertion point, [inserted] new pages are placed, then
/// [existing] of the document's own pages, alternating until one side runs
/// out; whatever is left of the other side follows in order. The default
/// one-for-one weave rejoins odd and even pages that were scanned or output
/// separately: insert the even pages *after the first page* of the odd ones.
class PdfPageInterleave {
  const PdfPageInterleave({this.existing = 1, this.inserted = 1})
      : assert(existing > 0),
        assert(inserted > 0);

  /// How many of the document's own pages sit between two inserted runs.
  final int existing;

  /// How many inserted pages land in each run.
  final int inserted;

  /// The page order that weaves [insertedCount] pages (appended after the
  /// document's [existingCount] pages, so they currently sit at
  /// `existingCount..`) into the document starting at [at] - entry i is the
  /// current index of the page that ends up at position i, the shape
  /// [PdfPageOperations.reorderPages] takes. A null [interleave] inserts
  /// one contiguous block.
  static List<int> order({
    required int existingCount,
    required int insertedCount,
    required int at,
    PdfPageInterleave? interleave,
  }) {
    RangeError.checkNotNegative(existingCount, 'existingCount');
    RangeError.checkNotNegative(insertedCount, 'insertedCount');
    RangeError.checkValueInInterval(at, 0, existingCount, 'at');
    final order = <int>[for (var i = 0; i < at; i++) i];
    var nextExisting = at;
    var nextInserted = 0;
    final insertedStep = interleave?.inserted ?? insertedCount;
    final existingStep = interleave?.existing ?? existingCount;
    while (nextInserted < insertedCount || nextExisting < existingCount) {
      for (var n = 0; n < insertedStep && nextInserted < insertedCount; n++) {
        order.add(existingCount + nextInserted++);
      }
      // once the inserted pages are spent the rest of the document follows
      final take = nextInserted < insertedCount ? existingStep : existingCount;
      for (var n = 0; n < take && nextExisting < existingCount; n++) {
        order.add(nextExisting++);
      }
    }
    return order;
  }
}

/// One document's contribution to [PdfPageInsertion.insertPages].
class PdfPageInsertSource {
  const PdfPageInsertSource(this.document, {this.indices, this.bookmarkTitle});

  /// The open source document (opened with its password if encrypted).
  final PdfDocument document;

  /// The zero-based source pages to insert, in order; null inserts all of
  /// them. A page may appear only once.
  final List<int>? indices;

  /// When set, a top-level bookmark with this title is added pointing at
  /// the first page inserted from this source (Bluebeam's "use the file
  /// name" convention for a merged packet).
  final String? bookmarkTitle;

  /// Resolves a page choice against a source of [pageCount] pages: the
  /// one-based [ranges] expression (`1-3, 7, 10-12`; blank or null means
  /// every page), filtered to the [subset], optionally [reverse]d. Repeated
  /// pages keep their first position. Throws [FormatException] for a
  /// malformed or out-of-range expression, like [PdfSplitter.parseRanges].
  static List<int> select(
    int pageCount, {
    String? ranges,
    PdfPageSubset subset = PdfPageSubset.all,
    bool reverse = false,
  }) {
    final picked = <int>{};
    if (ranges == null || ranges.trim().isEmpty) {
      picked.addAll([for (var i = 0; i < pageCount; i++) i]);
    } else {
      for (final r in PdfSplitter.parseRanges(ranges, pageCount: pageCount)) {
        for (var i = r.start; i <= r.end; i++) {
          picked.add(i);
        }
      }
    }
    final kept = [
      for (final i in picked)
        if (switch (subset) {
          PdfPageSubset.all => true,
          // index 0 is page 1, an odd page
          PdfPageSubset.odd => i.isEven,
          PdfPageSubset.even => i.isOdd,
        })
          i,
    ];
    return reverse ? kept.reversed.toList() : kept;
  }
}

/// Inserting pages from several documents in one edit.
extension PdfPageInsertion on PdfEditor {
  /// Inserts pages from each of [sources], in order, at [at] (default:
  /// appended at the end) - as one block, or woven into the existing pages
  /// when [interleave] is given. [bookmarks] controls whether each source's
  /// own outline comes along; [PdfPageInsertSource.bookmarkTitle] adds one
  /// bookmark per source on top. Everything is one staged edit, so a
  /// session commits it as a single undo step.
  ///
  /// Returns the final indices of the inserted pages, in insertion order
  /// (empty, with nothing staged, when no source contributes a page).
  List<int> insertPages(
    List<PdfPageInsertSource> sources, {
    int? at,
    PdfPageInterleave? interleave,
    bool bookmarks = true,
  }) {
    final existing = document.pageCount;
    final insertAt = at ?? existing;
    RangeError.checkValueInInterval(insertAt, 0, existing, 'at');
    var inserted = 0;
    for (final source in sources) {
      final picks = source.indices ??
          [for (var i = 0; i < source.document.pageCount; i++) i];
      if (picks.toSet().length != picks.length) {
        throw ArgumentError.value(
            picks, 'indices', 'a source page may be inserted only once');
      }
      if (picks.isEmpty) continue;
      final title = source.bookmarkTitle;
      final rootRef = title == null ? null : _ensureOutlineRoot();
      final before = rootRef == null ? null : {..._outlineChildren(rootRef)};
      // A block lands in place, as appendPagesFrom always has; a weave is
      // staged at the end and permuted into position once, below.
      final landing =
          interleave == null ? insertAt + inserted : existing + inserted;
      appendPagesFrom(source.document,
          indices: picks, at: landing, outlines: bookmarks);
      if (title != null) {
        // Page references survive the reorder below, so the bookmark can
        // target the page where it sits now. The source's own outline nests
        // under it, as a merged packet reads in Bluebeam/Acrobat.
        final item = addOutlineItem(title, pageIndex: landing);
        for (final child in _outlineChildren(rootRef!)) {
          if (child != item && !before!.contains(child)) {
            moveOutlineItem(child, parent: item);
          }
        }
      }
      inserted += picks.length;
    }
    if (inserted == 0) return const [];
    if (interleave == null) {
      return [for (var i = 0; i < inserted; i++) insertAt + i];
    }
    final order = PdfPageInterleave.order(
      existingCount: existing,
      insertedCount: inserted,
      at: insertAt,
      interleave: interleave,
    );
    reorderPages(order);
    final position = List<int>.filled(inserted, 0);
    for (var i = 0; i < order.length; i++) {
      if (order[i] >= existing) position[order[i] - existing] = i;
    }
    return position;
  }
}
