// PdfEditingSync: two editing controllers (two devices, or two people)
// converging through a sync transport - the loopback hub, and the shared
// folder transport over an in-memory store standing in for OneDrive.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shared starting bytes: one square that already has a durable /NM, as
/// every participant must (see [PdfEditingSync]).
Uint8List seeded() => (PdfEditor(PdfDocument.open(buildClassicPdf()))
      ..addSquare(0, const PdfRect(100, 600, 200, 680),
          strokeColor: 0x000000, name: 'shared-1'))
    .save();

/// [pages] blank pages, the first carrying the named square of [seeded].
Uint8List seededPages(int pages) {
  final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(pages)))
    ..addSquare(0, const PdfRect(100, 600, 200, 680),
        strokeColor: 0x000000, name: 'shared-1');
  return editor.save();
}

/// /NM -> snapshot JSON for every named annotation: equal digests mean the
/// two documents hold the same annotations.
Map<String, String> digest(PdfEditingController editing) => {
      for (final change in editing.annotationBaseline())
        change.name!: jsonEncode(change.snapshot!.toJson()),
    };

/// A transport that records what it sends, to prove nothing echoes.
class _SpyTransport implements PdfSyncTransport {
  _SpyTransport(this.inner);

  final PdfSyncTransport inner;
  final List<PdfSyncMessage> sent = [];

  @override
  String get sessionId => inner.sessionId;
  @override
  Stream<PdfSyncMessage> get incoming => inner.incoming;
  @override
  Stream<Set<String>> get presence => inner.presence;
  @override
  Set<String> get peers => inner.peers;
  @override
  void send(PdfSyncMessage message) {
    sent.add(message);
    inner.send(message);
  }

  @override
  void close() => inner.close();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  PdfEditingController controller(Uint8List bytes) {
    final editing = PdfEditingController(bytes);
    addTearDown(editing.dispose);
    return editing;
  }

  PdfEditingSync sync(PdfEditingController editing, PdfSyncTransport t) {
    final s = PdfEditingSync(controller: editing, transport: t);
    addTearDown(s.dispose);
    return s;
  }

  group('loopback', () {
    test('independent edits merge both ways, without echo', () async {
      final hub = PdfLoopbackSyncHub();
      final base = seeded();
      final a = controller(base);
      final b = controller(base);
      final tb = _SpyTransport(hub.connect('b'));
      sync(a, hub.connect('a'));
      final syncB = sync(b, tb);
      final remoteAtB = <List<PdfAnnotationChange>>[];
      syncB.remoteChanges.listen(remoteAtB.add);

      a.addRectangle(0, const PdfRect(300, 300, 360, 360));
      b.addNote(0, 50, 50, 'from B');
      await pumpEventQueue();

      expect(digest(a), hasLength(3));
      expect(digest(a), digest(b));
      expect(remoteAtB, hasLength(1),
          reason: 'B applied A rectangle and announced it once');
      expect(tb.sent, hasLength(1),
          reason: "B sent only its own note, never A's rectangle back");
      expect(syncB.peers, {'a', 'b'});
    });

    test('concurrent moves of one annotation resolve to the same winner',
        () async {
      final hub = PdfLoopbackSyncHub();
      final base = seeded();
      final a = controller(base);
      final b = controller(base);
      sync(a, hub.connect('a'));
      sync(b, hub.connect('b'));

      // both move the shared square before hearing from the other
      a
        ..selectAnnotation(0, 0)
        ..moveSelected(40, 0);
      b
        ..selectAnnotation(0, 0)
        ..moveSelected(0, -40);
      await pumpEventQueue();

      expect(digest(a), digest(b));
      final (_, square) = b.findAnnotationByName('shared-1')!;
      // equal Lamport clocks tie-break on the greater origin: "b"
      expect(square.rect.left, closeTo(100, 1e-6));
      expect(square.rect.bottom, closeTo(560, 1e-6));
    });

    test('undo travels as an edit', () async {
      final hub = PdfLoopbackSyncHub();
      final base = seeded();
      final a = controller(base);
      final b = controller(base);
      sync(a, hub.connect('a'));
      sync(b, hub.connect('b'));

      a.addRectangle(0, const PdfRect(300, 300, 360, 360));
      await pumpEventQueue();
      expect(digest(b), hasLength(2));

      a.undo();
      await pumpEventQueue();
      expect(digest(b).keys, ['shared-1']);
      expect(digest(a), digest(b));
    });

    test('an editor and a headless PdfSyncSession converge together', () async {
      final hub = PdfLoopbackSyncHub();
      final base = seeded();
      final a = controller(base);
      sync(a, hub.connect('a'));
      final server = PdfSyncSession(bytes: base, transport: hub.connect('z'));
      addTearDown(server.dispose);

      a.addRectangle(0, const PdfRect(300, 300, 360, 360));
      server
          .apply((e) => e.addNote(0, 20, 20, 'bot', name: 'bot-1'), pages: [0]);
      await pumpEventQueue();

      expect(digest(a).keys, containsAll(['shared-1', 'bot-1']));
      expect(server.annotationDigest().keys, unorderedEquals(digest(a).keys));
    });

    test('dispose stops both directions', () async {
      final hub = PdfLoopbackSyncHub();
      final base = seeded();
      final a = controller(base);
      final b = controller(base);
      final syncA = PdfEditingSync(controller: a, transport: hub.connect('a'));
      sync(b, hub.connect('b'));

      await syncA.dispose();
      a.addRectangle(0, const PdfRect(300, 300, 360, 360));
      b.addNote(0, 50, 50, 'from B');
      await pumpEventQueue();

      expect(digest(a), hasLength(2));
      expect(digest(b), hasLength(2));
      expect(digest(a), isNot(digest(b)));
    });
  });

  group('page-structure lock', () {
    test('a sync locks page edits for its lifetime and says so', () async {
      final hub = PdfLoopbackSyncHub();
      final a = controller(seededPages(3));
      var refusals = 0;
      a.onPageStructureLocked = () => refusals++;

      final s = PdfEditingSync(controller: a, transport: hub.connect('a'));
      expect(a.pageStructureLocked, isTrue);
      final before = a.bytes.length;
      a.removePage(1);
      a.addBlankPage();
      a.movePage(0, 2);
      expect(a.document.pageCount, 3);
      expect(a.bytes.length, before, reason: 'nothing was committed');
      expect(refusals, 3);

      // annotations still work, and the document reads back unharmed
      a.addRectangle(2, const PdfRect(300, 300, 360, 360));
      expect(a.document.page(2).annotations, hasLength(1));

      await s.dispose();
      expect(a.pageStructureLocked, isFalse);
      a.removePage(1);
      expect(a.document.pageCount, 2);
    });

    test('undo and redo do not cross a page edit while locked', () {
      final a = controller(seededPages(3));
      var refusals = 0;
      a.onPageStructureLocked = () => refusals++;
      a.removePage(2);
      expect(a.document.pageCount, 2);

      a.pageStructureLocked = true;
      a.undo();
      expect(a.document.pageCount, 2);
      expect(refusals, 1);

      a.pageStructureLocked = false;
      a.undo();
      expect(a.document.pageCount, 3);
      a.pageStructureLocked = true;
      a.redo();
      expect(a.document.pageCount, 3);
      expect(refusals, 2);
    });
  });

  test('replaying a change the document already holds adds no revision',
      () async {
    final hub = PdfLoopbackSyncHub();
    final base = seeded();
    final a = controller(base);
    sync(a, hub.connect('a'));
    final b = hub.connect('b');
    final held = a.annotationBaseline().single;

    final before = a.bytes.length;
    b.send(PdfSyncMessage(change: held, origin: 'b', clock: 5));
    await pumpEventQueue();
    expect(a.bytes.length, before);
  });

  group('shared folder', () {
    test(
        'two devices converge through one folder, and a late joiner '
        'catches up', () async {
      final store = PdfMemorySyncStore();
      final base = seeded();
      PdfSharedFolderSyncTransport folder(String id) {
        final t = PdfSharedFolderSyncTransport(
            store: store, sessionId: id, flushDelay: Duration.zero);
        addTearDown(t.close);
        return t;
      }

      final ta = folder('laptop_1');
      final tb = folder('phone_1');
      final a = controller(base);
      final b = controller(base);
      sync(a, ta);
      sync(b, tb);

      a.addRectangle(0, const PdfRect(300, 300, 360, 360));
      b.addNote(0, 50, 50, 'from the phone');
      await pumpEventQueue();
      await ta.flush();
      await tb.flush();
      await ta.poll();
      await tb.poll();
      await pumpEventQueue();
      expect(digest(a), hasLength(3));
      expect(digest(a), digest(b));

      // a third session opens the same (uncompacted) PDF and replays the log
      final tc = folder('desktop_1');
      final c = controller(base);
      sync(c, tc);
      await tc.poll();
      await pumpEventQueue();
      expect(digest(c), digest(a));
    });
  });
}
