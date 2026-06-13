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

  test('entries without a path are not reopenable', () async {
    final store = RecentsStore();
    await store.add(title: 'shared.pdf'); // mobile/web: no path
    expect(store.items.single.isReopenable, isFalse);
  });

  test('persists across loads', () async {
    final a = RecentsStore();
    await a.add(title: 'keep.pdf', path: '/x/keep.pdf');

    final b = RecentsStore();
    await b.load();
    expect(b.items.single.path, '/x/keep.pdf');
  });

  test('clear empties the list', () async {
    final store = RecentsStore();
    await store.add(title: 'a.pdf', path: '/a.pdf');
    await store.clear();
    expect(store.isEmpty, isTrue);
  });
}
