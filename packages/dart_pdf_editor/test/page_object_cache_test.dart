// The viewer's per-page object caches (extracted text, annotation lists,
// form-field rects) are bounded LRU maps so a long scroll cannot pin one entry
// per visited page for the life of the viewer (issue #283 / follow-up to #286).
// These cases pin the count bound, the LRU order under both reads and inserts,
// the compute-once semantics, and the runtime-default / explicit-override
// plumbing.
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PdfPageObjectCache', () {
    test('bounds the entry count so a long scroll cannot grow unbounded', () {
      final cache = PdfPageObjectCache<int>(maxEntries: 3);
      for (var page = 0; page < 100; page++) {
        cache.putIfAbsent(page, () => page);
      }
      expect(cache.length, 3);
      // The most-recently inserted survive; the cold tail is gone.
      expect(cache.pages.toList(), [97, 98, 99]);
    });

    test('never drops below the cap while filling', () {
      final cache = PdfPageObjectCache<int>(maxEntries: 5);
      for (var page = 0; page < 5; page++) {
        cache.putIfAbsent(page, () => page);
      }
      expect(cache.length, 5);
      cache.putIfAbsent(5, () => 5);
      expect(cache.length, 5, reason: 'inserting a sixth evicts, not grows');
      expect(cache[0], isNull, reason: 'the LRU entry (page 0) was evicted');
    });

    test('a lookup marks its page most-recently used', () {
      final cache = PdfPageObjectCache<int>(maxEntries: 3);
      cache.putIfAbsent(0, () => 0);
      cache.putIfAbsent(1, () => 1);
      cache.putIfAbsent(2, () => 2);
      // Touch page 0 so it is no longer the LRU victim.
      expect(cache[0], 0);
      // Inserting page 3 must now evict page 1 (the untouched LRU), not 0.
      cache.putIfAbsent(3, () => 3);
      expect(cache[0], 0, reason: 'the touched page survived eviction');
      expect(cache[1], isNull, reason: 'the untouched LRU page was evicted');
      expect(cache[2], 2);
      expect(cache[3], 3);
    });

    test('an insert of an existing page refreshes its recency without recompute',
        () {
      final cache = PdfPageObjectCache<int>(maxEntries: 3);
      cache.putIfAbsent(0, () => 0);
      cache.putIfAbsent(1, () => 1);
      cache.putIfAbsent(2, () => 2);
      var recomputed = false;
      // A hit returns the stored value and does not run the compute closure.
      expect(cache.putIfAbsent(0, () {
        recomputed = true;
        return -1;
      }), 0);
      expect(recomputed, isFalse);
      // ...and page 0 is now the most-recently used, so page 1 is the victim.
      cache.putIfAbsent(3, () => 3);
      expect(cache[0], 0);
      expect(cache[1], isNull);
    });

    test('clear drops every entry', () {
      final cache = PdfPageObjectCache<int>(maxEntries: 3);
      cache.putIfAbsent(0, () => 0);
      cache.putIfAbsent(1, () => 1);
      cache.clear();
      expect(cache.length, 0);
      expect(cache[0], isNull);
    });

    test('a null maxEntries takes the runtime default', () {
      final previous = pdfViewerPageObjectCacheMaxEntries;
      addTearDown(() => pdfViewerPageObjectCacheMaxEntries = previous);
      pdfViewerPageObjectCacheMaxEntries = 2;
      final cache = PdfPageObjectCache<int>();
      for (var page = 0; page < 10; page++) {
        cache.putIfAbsent(page, () => page);
      }
      expect(cache.length, 2);
    });

    test('an explicit maxEntries overrides the runtime default', () {
      final previous = pdfViewerPageObjectCacheMaxEntries;
      addTearDown(() => pdfViewerPageObjectCacheMaxEntries = previous);
      pdfViewerPageObjectCacheMaxEntries = 2;
      final cache = PdfPageObjectCache<int>(maxEntries: 4);
      for (var page = 0; page < 10; page++) {
        cache.putIfAbsent(page, () => page);
      }
      expect(cache.length, 4);
    });

    test('the cap is floored at 1', () {
      final cache = PdfPageObjectCache<int>(maxEntries: 0);
      cache.putIfAbsent(0, () => 0);
      cache.putIfAbsent(1, () => 1);
      expect(cache.length, 1);
      expect(cache.pages.toList(), [1]);
    });
  });
}
