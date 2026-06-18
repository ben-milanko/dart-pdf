import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_viewer_example/recent_files.dart';

/// A PDF-ish byte payload distinct enough that [pdfContentKey] separates it
/// from the others (the seed byte varies the content).
Uint8List _doc(int seed, {int length = 64}) =>
    Uint8List.fromList(List.generate(length, (i) => (seed * 31 + i) & 0xff));

void main() {
  test('records newest first and reads bytes back', () async {
    final store = RecentFilesStore(PdfMemoryCacheStore());
    await store.ready;

    final a = _doc(1);
    final b = _doc(2);
    await store.record('a.pdf', a);
    await store.record('b.pdf', b);

    expect(store.entries.map((e) => e.title), ['b.pdf', 'a.pdf']);
    final id = store.entries.last.id;
    expect(await store.bytesFor(id), a);
  });

  test('re-opening the same content folds into one entry, moved to front',
      () async {
    final store = RecentFilesStore(PdfMemoryCacheStore());
    final a = _doc(1);
    await store.record('a.pdf', a);
    await store.record('b.pdf', _doc(2));
    // same bytes as a, but picked from a different folder (new name)
    await store.record('copy-of-a.pdf', a);

    expect(store.entries.map((e) => e.title), ['copy-of-a.pdf', 'b.pdf']);
  });

  test('evicts the oldest past the entry cap and deletes its bytes',
      () async {
    final backend = PdfMemoryCacheStore();
    final store = RecentFilesStore(backend, maxEntries: 2);
    await store.record('a.pdf', _doc(1));
    final oldestId = store.entries.first.id;
    await store.record('b.pdf', _doc(2));
    await store.record('c.pdf', _doc(3));

    expect(store.entries.map((e) => e.title), ['c.pdf', 'b.pdf']);
    expect(await store.bytesFor(oldestId), isNull);
  });

  test('evicts the oldest to stay under the byte budget', () async {
    // budget holds two 64-byte docs but not three
    final store = RecentFilesStore(PdfMemoryCacheStore(), maxBytes: 150);
    await store.record('a.pdf', _doc(1));
    await store.record('b.pdf', _doc(2));
    await store.record('c.pdf', _doc(3));

    expect(store.entries.map((e) => e.title), ['c.pdf', 'b.pdf']);
  });

  test('keeps the newest entry even when it alone busts the budget',
      () async {
    final store = RecentFilesStore(PdfMemoryCacheStore(), maxBytes: 16);
    final big = _doc(1, length: 64);
    await store.record('big.pdf', big);

    expect(store.entries.single.title, 'big.pdf');
    expect(await store.bytesFor(store.entries.single.id), big);
  });

  test('touch moves an entry to the front', () async {
    final store = RecentFilesStore(PdfMemoryCacheStore());
    await store.record('a.pdf', _doc(1));
    await store.record('b.pdf', _doc(2));
    final aId = store.entries.last.id;

    await store.touch(aId);
    expect(store.entries.map((e) => e.title), ['a.pdf', 'b.pdf']);
  });

  test('remove forgets one entry and drops its bytes', () async {
    final store = RecentFilesStore(PdfMemoryCacheStore());
    await store.record('a.pdf', _doc(1));
    await store.record('b.pdf', _doc(2));
    final aId = store.entries.last.id;

    await store.remove(aId);
    expect(store.entries.map((e) => e.title), ['b.pdf']);
    expect(await store.bytesFor(aId), isNull);
  });

  test('clear empties the list and the stored bytes', () async {
    final store = RecentFilesStore(PdfMemoryCacheStore());
    await store.record('a.pdf', _doc(1));
    await store.record('b.pdf', _doc(2));
    final ids = store.entries.map((e) => e.id).toList();

    await store.clear();
    expect(store.entries, isEmpty);
    for (final id in ids) {
      expect(await store.bytesFor(id), isNull);
    }
  });

  test('the list and bytes survive a fresh store over the same backend',
      () async {
    final backend = PdfMemoryCacheStore();
    final first = RecentFilesStore(backend);
    final a = _doc(1);
    await first.record('a.pdf', a);
    await first.record('b.pdf', _doc(2));

    final reloaded = RecentFilesStore(backend);
    await reloaded.ready;
    expect(reloaded.entries.map((e) => e.title), ['b.pdf', 'a.pdf']);
    expect(await reloaded.bytesFor(reloaded.entries.last.id), a);
  });

  test('notifies listeners on record and clear', () async {
    final store = RecentFilesStore(PdfMemoryCacheStore());
    await store.ready;
    var notifications = 0;
    store.addListener(() => notifications++);

    await store.record('a.pdf', _doc(1));
    expect(notifications, 1);
    await store.clear();
    expect(notifications, 2);
  });
}
