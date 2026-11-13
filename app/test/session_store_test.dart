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

  test('a cache-backed document (mobile) round-trips and restores', () async {
    final a = SessionStore();
    await a.save(const [
      SessionDocument(
          title: 'shared.pdf', path: '', cachePath: '/app/recent_pdfs/x.pdf'),
    ]);

    final b = SessionStore();
    final restored = await b.load();
    expect(restored.single.cachePath, '/app/recent_pdfs/x.pdf');
    expect(restored.single.readPath, '/app/recent_pdfs/x.pdf');
  });

  test('a document with neither path nor cache is dropped on load', () async {
    SharedPreferences.setMockInitialValues({
      'dart_pdf_editor_app.session': '[{"t":"orphan.pdf","p":""}]',
    });
    final store = SessionStore();
    expect(await store.load(), isEmpty);
  });

  test('load re-anchors snapshots an app update moved', () async {
    await SessionStore().save(const [
      SessionDocument(
          title: 'm.pdf', path: '', cachePath: '/old/recent_pdfs/m.pdf'),
    ]);
    final store =
        SessionStore(resolveCacheKey: (key) async => '/new/recent_pdfs/m.pdf');
    final docs = await store.load();
    expect(docs.single.cachePath, '/new/recent_pdfs/m.pdf');
  });

  group('windows', () {
    const a = SessionDocument(title: 'a.pdf', path: '/a.pdf');
    const b = SessionDocument(title: 'b.pdf', path: '/b.pdf');
    const c = SessionDocument(title: 'c.pdf', path: '/c.pdf');

    test('round-trip each window\'s documents, in window order', () async {
      await SessionStore().saveWindows(const [
        [a, b],
        [],
        [c],
      ]);
      final windows = await SessionStore().loadWindows();
      expect([
        for (final w in windows) [for (final d in w) d.path]
      ], [
        ['/a.pdf', '/b.pdf'],
        ['/c.pdf'],
      ], reason: 'an empty window has nothing to restore');
    });

    test('a single-window load gets every window\'s documents once', () async {
      await SessionStore().saveWindows(const [
        [a, b],
        [b, c],
      ]);
      expect((await SessionStore().load()).map((d) => d.path),
          ['/a.pdf', '/b.pdf', '/c.pdf']);
    });

    test('a session saved before windows were tracked is one window', () async {
      SharedPreferences.setMockInitialValues({
        'dart_pdf_editor_app.session':
            '[{"t":"a.pdf","p":"/a.pdf"},{"t":"b.pdf","p":"/b.pdf"}]',
      });
      final windows = await SessionStore().loadWindows();
      expect(windows, hasLength(1));
      expect(windows.single.map((d) => d.path), ['/a.pdf', '/b.pdf']);
    });

    test('an older build\'s later rewrite of the flat list wins', () async {
      await SessionStore().saveWindows(const [
        [a],
        [b],
      ]);
      // What a build without window tracking writes: only the flat key.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'dart_pdf_editor_app.session', '[{"t":"c.pdf","p":"/c.pdf"}]');
      final windows = await SessionStore().loadWindows();
      expect(windows, hasLength(1));
      expect(windows.single.single.path, '/c.pdf');
    });
  });
}
