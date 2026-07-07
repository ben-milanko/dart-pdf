import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/session_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('save then load round-trips the open documents in order', () async {
    final a = SessionStore();
    await a.save(const [
      SessionDocument(
          title: 'a.pdf', path: '/docs/a.pdf', bookmark: 'bookmark-a'),
      SessionDocument(title: 'b.pdf', path: '/docs/b.pdf'),
    ]);

    final b = SessionStore();
    final restored = await b.load();
    expect(restored.map((d) => d.path), ['/docs/a.pdf', '/docs/b.pdf']);
    expect(restored.map((d) => d.title), ['a.pdf', 'b.pdf']);
    expect(restored.map((d) => d.bookmark), ['bookmark-a', null]);
  });

  test('load is empty when nothing was persisted', () async {
    final store = SessionStore();
    expect(await store.load(), isEmpty);
  });

  test('save replaces the previous set', () async {
    final store = SessionStore();
    await store.save(const [SessionDocument(title: 'a.pdf', path: '/a.pdf')]);
    await store.save(const [SessionDocument(title: 'c.pdf', path: '/c.pdf')]);

    final reloaded = SessionStore();
    expect((await reloaded.load()).single.path, '/c.pdf');
  });

  test('documents without a usable path are dropped on load', () async {
    SharedPreferences.setMockInitialValues({
      'dart_pdf_editor_app.session': '[{"t":"keep.pdf","p":"/k.pdf"},'
          '{"t":"nopath.pdf","p":""},{"t":"missing.pdf"}]',
    });
    final store = SessionStore();
    final restored = await store.load();
    expect(restored.map((d) => d.path), ['/k.pdf']);
  });
}
