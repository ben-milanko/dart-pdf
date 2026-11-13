// The multi-window session without pumping any window: which windows are
// persisted, and what closing, quitting and failed restores do to them.

import 'package:dart_pdf_editor_app/session_store.dart';
import 'package:dart_pdf_editor_app/window_sessions.dart';
import 'package:flutter_test/flutter_test.dart';

class _Store implements WindowSessionPersistence {
  _Store([this.stored = const []]);

  List<List<SessionDocument>> stored;
  int writes = 0;

  @override
  Future<List<List<SessionDocument>>> loadWindows() async => stored;

  @override
  Future<void> saveWindows(List<List<SessionDocument>> windows) async {
    writes++;
    stored = windows;
  }

  @override
  Future<List<SessionDocument>> load() async => flattenSessionWindows(stored);

  @override
  Future<void> save(List<SessionDocument> documents) =>
      saveWindows([documents]);

  List<List<String>> get paths => [
        for (final w in stored) [for (final d in w) d.path]
      ];
}

SessionDocument doc(String name) =>
    SessionDocument(title: '$name.pdf', path: '/$name.pdf');

void main() {
  late _Store store;
  late WindowSessions sessions;

  setUp(() {
    store = _Store([
      [doc('seed')]
    ]);
    sessions = WindowSessions(store);
  });

  test('nothing is written until the last session has been read back',
      () async {
    final primary = sessions.open();
    await primary.save([doc('a')]);
    expect(store.writes, 0);
    expect(store.paths, [
      ['/seed.pdf']
    ]);

    sessions.markLoaded();
    await pumpEventQueue();
    expect(store.paths, [
      ['/a.pdf']
    ]);
  });

  test('every window is persisted, in the order the windows opened', () async {
    final primary = sessions.open();
    final restored = sessions.open(documents: [doc('b'), doc('c')]);
    sessions.markLoaded();
    await primary.save([doc('a')]);
    expect(
        store.paths,
        [
          ['/a.pdf'],
          ['/b.pdf', '/c.pdf'],
        ],
        reason: 'a restoring window is described by its seed meanwhile');

    final later = sessions.open();
    await later.save([doc('d')]);
    await restored.save([doc('c')]);
    expect(store.paths, [
      ['/a.pdf'],
      ['/c.pdf'],
      ['/d.pdf'],
    ]);
  });

  test('an empty window is not persisted', () async {
    final primary = sessions.open();
    sessions.open();
    sessions.markLoaded();
    await primary.save([doc('a')]);
    expect(store.paths, [
      ['/a.pdf']
    ]);
  });

  test('closing one of several windows forgets it', () async {
    final primary = sessions.open();
    final second = sessions.open();
    sessions.markLoaded();
    await primary.save([doc('a')]);
    await second.save([doc('b')]);

    primary.close();
    await pumpEventQueue();
    expect(store.paths, [
      ['/b.pdf']
    ]);
    // A late write from the closed window (its tabs disposing) is ignored.
    await primary.save(const []);
    expect(store.paths, [
      ['/b.pdf']
    ]);
  });

  test('closing the last window keeps it for the next launch', () async {
    final primary = sessions.open();
    final second = sessions.open();
    sessions.markLoaded();
    await primary.save([doc('a')]);
    await second.save([doc('b')]);

    second.close();
    primary.close();
    await pumpEventQueue();
    expect(store.paths, [
      ['/a.pdf']
    ]);
  });

  test('quitting keeps every window, whatever closes afterwards', () async {
    final primary = sessions.open();
    final second = sessions.open();
    sessions.markLoaded();
    await primary.save([doc('a')]);
    await second.save([doc('b')]);

    // The app exiting tears windows down without the user closing them.
    primary.detach();
    await primary.save(const []);
    second.close();
    second.detach();
    await pumpEventQueue();
    expect(store.paths, [
      ['/a.pdf'],
      ['/b.pdf'],
    ]);
  });

  test('a restore whose window never opened leaves the session', () async {
    final primary = sessions.open();
    final failed = sessions.open(documents: [doc('b')]);
    failed.discard();
    sessions.markLoaded();
    await primary.save([doc('a'), doc('b')]);
    expect(store.paths, [
      ['/a.pdf', '/b.pdf']
    ]);
  });
}
