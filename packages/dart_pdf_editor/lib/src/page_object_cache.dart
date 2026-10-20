import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;

/// Default maximum number of per-page objects the viewer keeps in each of its
/// page-keyed object caches (extracted text, annotation lists, form-field
/// rects).
const int defaultPdfViewerPageObjectCacheMaxEntries = 128;

/// Maximum number of per-page objects the viewer retains in each page-keyed
/// object cache, regardless of size. See [PdfPageObjectCache].
///
/// Left unbounded these caches grow one small entry for every page ever
/// visited and are dropped only on a document/revision swap - retention keyed
/// by the page index that only ever grows, the same shape issue #283 measured
/// (the render worker's record cache had the identical problem, capped in
/// #286). The entries hold text/annotation data, not decoded pixels, so the
/// footprint is minor, but on a long scroll it is still unbounded in the page
/// count. Capturing this cap when a viewer builds its caches bounds it. Lower
/// it once at startup on a memory-constrained device.
int pdfViewerPageObjectCacheMaxEntries =
    defaultPdfViewerPageObjectCacheMaxEntries;

/// A bounded, least-recently-used cache keyed by page index.
///
/// The viewer derives a few objects per page - extracted text, the interactive
/// and visible annotation lists, the form-field rects - and keeps them so a
/// re-visit (a scroll back, a hit-test, a search) does not recompute. The cap
/// sits well above the on-screen plus preview-warm working set (a page's
/// objects are derived only when it is near the viewport - hit-tested, selected
/// or searched), so ordinary back-and-forth revisits still hit; it only stops
/// the cold tail from growing without limit on a long document.
///
/// Insertion order is LRU order: a plain Dart map is insertion-ordered, so its
/// first key is the least-recently used, and a remove-then-reinsert on access
/// moves an entry to the most-recently-used end (the technique the render
/// worker's record cache uses). A lookup or insert therefore marks its page
/// most-recently used, so a page in view is never the eviction victim.
///
/// [V] is expected to be non-nullable - a stored null reads back as a miss.
class PdfPageObjectCache<V> {
  PdfPageObjectCache({int? maxEntries})
      : _maxEntries =
            math.max(1, maxEntries ?? pdfViewerPageObjectCacheMaxEntries);

  /// The most entries this cache retains before evicting the least-recently
  /// used. At least 1.
  final int _maxEntries;

  final Map<int, V> _entries = {};

  /// The cached value for [page], or null on a miss. A hit is marked
  /// most-recently used so a lookup protects the entry from eviction.
  V? operator [](int page) {
    final hit = _entries.remove(page);
    if (hit == null) return null;
    _entries[page] = hit;
    return hit;
  }

  /// The cached value for [page], computing and storing it with [ifAbsent] on
  /// a miss. The entry is marked most-recently used, then the least-recently
  /// used entries past the cap are evicted (never the entry just inserted - it
  /// is the most-recently used).
  V putIfAbsent(int page, V Function() ifAbsent) {
    final existing = this[page];
    if (existing != null) return existing;
    final value = ifAbsent();
    _entries[page] = value;
    while (_entries.length > _maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    return value;
  }

  /// Drops every entry - a document or revision swap invalidates them all.
  void clear() => _entries.clear();

  /// Drops the cached values for [pages], preserving every clean page's LRU
  /// value and relative recency.
  void removeAll(Iterable<int> pages) {
    for (final page in pages) {
      _entries.remove(page);
    }
  }

  /// The number of retained entries. Bounded by the configured cap.
  @visibleForTesting
  int get length => _entries.length;

  /// The retained pages, least-recently used first.
  @visibleForTesting
  Iterable<int> get pages => _entries.keys;
}
