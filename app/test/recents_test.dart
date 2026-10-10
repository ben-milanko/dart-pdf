import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/recents.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('add inserts most-recent-first and dedupes by id', () async {
    final store = RecentsStore();
    await store.add(title: 'a.pdf', path: '/docs/a.pdf');
    await store.add(title: 'b.pdf', path: '/docs/b.pdf');
    await store.add(title: 'a.pdf', path: '/docs/a.pdf'); // re-open a

    expect(store.items.map((e) => e.path),
        ['/docs/a.pdf', '/docs/b.pdf']); // a moved to front, no dupe
  });

  test('entries without a path or cache are not reopenable', () async {
    final store = RecentsStore();
    await store.add(title: 'shared.pdf'); // web: no path, no snapshot
    expect(store.items.single.isReopenable, isFalse);
  });

  test('a cache-backed entry is reopenable and reads from the snapshot',
      () async {
    final store = RecentsStore();
    // Mobile: no durable path, but a private snapshot to read back.
    await store.add(title: 'shared.pdf', cachePath: '/app/recent_pdfs/x.pdf');
    final entry = store.items.single;
    expect(entry.path, isNull);
    expect(entry.isReopenable, isTrue);
    expect(entry.readPath, '/app/recent_pdfs/x.pdf');
    expect(entry.id, '/app/recent_pdfs/x.pdf'); // dedupes by snapshot
  });

  test('cache-backed entries persist and round-trip across loads', () async {
    final a = RecentsStore();
    await a.add(title: 'shared.pdf', cachePath: '/app/recent_pdfs/x.pdf');

    final b = RecentsStore();
    await b.load();
    final entry = b.items.single;
    expect(entry.cachePath, '/app/recent_pdfs/x.pdf');
    expect(entry.isReopenable, isTrue);
  });

  test('persists across loads', () async {
    final a = RecentsStore();
    await a.add(
        title: 'keep.pdf', path: '/x/keep.pdf', bookmark: 'bookmark-data');

    final b = RecentsStore();
    await b.load();
    expect(b.items.single.path, '/x/keep.pdf');
    expect(b.items.single.bookmark, 'bookmark-data');
  });

  test('clear empties the list', () async {
    final store = RecentsStore();
    await store.add(title: 'a.pdf', path: '/a.pdf');
    await store.clear();
    expect(store.isEmpty, isTrue);
  });

  test('rename preserves cached identity, availability and ordering', () async {
    final store = RecentsStore();
    addTearDown(store.dispose);
    await store.add(title: 'old.pdf', cachePath: 'cached', bookmark: 'access');
    await store.add(title: 'newest.pdf', path: '/newest.pdf');
    await store.updateCachedAvailability({'cached'}, {});
    final openedAt = store.items.last.openedAt;
    await store.rename('cached', 'renamed.pdf');

    final restored = RecentsStore();
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.items.map((entry) => entry.title),
        ['newest.pdf', 'renamed.pdf']);
    expect(restored.items.last.id, 'cached');
    expect(restored.items.last.cacheAvailable, isFalse);
    expect(restored.items.last.bookmark, 'access');
    expect(restored.items.last.openedAt, openedAt);
  });

  test('eviction preserves identity, order and a usable original path',
      () async {
    final store = RecentsStore();
    await store.add(title: 'a.pdf', cachePath: 'a');
    await store.add(title: 'b.pdf', cachePath: 'b', path: '/b.pdf');
    await store.add(title: 'new.pdf', cachePath: 'new');
    final ids = store.items.map((entry) => entry.id).toList();
    final times = store.items.map((entry) => entry.openedAt).toList();
    await store.updateCachedAvailability({'a', 'b'}, {});
    expect(store.items.map((entry) => entry.id), ids);
    expect(store.items.map((entry) => entry.openedAt), times);
    expect(store.items.map((entry) => entry.isReopenable), [true, true, false]);
    await store.add(title: 'a.pdf', cachePath: 'a');
    expect(store.items.length, 3);
    expect(store.items.first.isReopenable, isTrue);
  });

  test('load re-anchors snapshots an app update moved', () async {
    final before = RecentsStore();
    await before.add(title: 'moved.pdf', cachePath: '/old/recent_pdfs/m.pdf');
    await before.updateCachedAvailability({'/old/recent_pdfs/m.pdf'}, {});
    await before.add(title: 'gone.pdf', cachePath: '/old/recent_pdfs/g.pdf');

    final after = RecentsStore(
        resolveCacheKey: (key) async =>
            key.endsWith('/m.pdf') ? '/new/recent_pdfs/m.pdf' : null);
    await after.load();

    final moved = after.items.firstWhere((e) => e.title == 'moved.pdf');
    expect(moved.cachePath, '/new/recent_pdfs/m.pdf');
    expect(moved.isReopenable, isTrue); // previously marked missing
    final gone = after.items.firstWhere((e) => e.title == 'gone.pdf');
    expect(gone.cachePath, '/old/recent_pdfs/g.pdf'); // left for a re-pick

    // The re-anchored path is what persists.
    final reloaded = RecentsStore(resolveCacheKey: (_) async => null);
    await reloaded.load();
    expect(reloaded.items.map((e) => e.cachePath),
        contains('/new/recent_pdfs/m.pdf'));
  });
}
