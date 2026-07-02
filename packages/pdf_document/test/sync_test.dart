// The transport-agnostic sync layer: a loopback transport, presence, and
// two in-process sessions converging — including deterministic
// last-writer-wins resolution of conflicting edits keyed on /NM.

import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

/// A base document seeded with one named square, so both peers start from
/// identical bytes with a durable /NM (independently minted names would
/// never reconcile).
Uint8List seeded() {
  final editor = PdfEditor(PdfDocument.open(buildClassicPdf()))
    ..addSquare(0, const PdfRect(100, 600, 200, 680),
        strokeColor: 0x000000, name: 'shared-1');
  return editor.save();
}

/// Lets every pending microtask (loopback delivery) drain.
Future<void> settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('loopback transport', () {
    test('presence tracks joins and leaves', () async {
      final hub = PdfLoopbackSyncHub();
      final a = hub.connect('a');
      expect(a.peers, {'a'});

      final seenByA = <Set<String>>[];
      a.presence.listen(seenByA.add);

      final b = hub.connect('b');
      await settle();
      expect(a.peers, {'a', 'b'});
      expect(b.peers, {'a', 'b'});
      expect(seenByA.last, {'a', 'b'});

      b.close();
      await settle();
      expect(a.peers, {'a'});
      a.close();
    });

    test('connecting a live id twice throws', () {
      final hub = PdfLoopbackSyncHub();
      final a = hub.connect('a');
      expect(() => hub.connect('a'), throwsArgumentError);
      a.close();
    });

    test('a send never echoes to the sender', () async {
      final hub = PdfLoopbackSyncHub();
      final a = hub.connect('a');
      final b = hub.connect('b');
      final atA = <PdfSyncMessage>[];
      final atB = <PdfSyncMessage>[];
      a.incoming.listen(atA.add);
      b.incoming.listen(atB.add);

      final snapshot = PdfAnnotationSnapshot.capture(
          PdfDocument.open(seeded()),
          PdfDocument.open(seeded()).page(0).annotations.single,
          keepName: true)!;
      a.send(PdfSyncMessage(
        origin: 'a',
        clock: 1,
        change: PdfAnnotationChange(
          kind: PdfAnnotationChangeKind.created,
          pageIndex: 0,
          name: 'shared-1',
          snapshot: snapshot,
        ),
      ));
      await settle();
      expect(atA, isEmpty);
      expect(atB, hasLength(1));
      a.close();
      b.close();
    });
  });

  group('message serialization', () {
    test('toJson/fromJson round-trips a created change', () {
      final doc = PdfDocument.open(seeded());
      final snapshot = PdfAnnotationSnapshot.capture(
          doc, doc.page(0).annotations.single,
          keepName: true)!;
      final message = PdfSyncMessage(
        origin: 'a',
        clock: 7,
        change: PdfAnnotationChange(
          kind: PdfAnnotationChangeKind.created,
          pageIndex: 0,
          name: 'shared-1',
          snapshot: snapshot,
        ),
      );
      final back = PdfSyncMessage.fromJson(message.toJson());
      expect(back.origin, 'a');
      expect(back.clock, 7);
      expect(back.name, 'shared-1');
      expect(back.change.kind, PdfAnnotationChangeKind.created);
      expect(back.change.snapshot!.name, 'shared-1');
    });
  });

  group('session surface', () {
    test('bytes/peers/presence/changes are exposed', () async {
      final hub = PdfLoopbackSyncHub();
      final base = seeded();
      final a = PdfSyncSession(bytes: base, transport: hub.connect('a'));
      final b = PdfSyncSession(bytes: base, transport: hub.connect('b'));
      addTearDown(() async {
        await a.dispose();
        await b.dispose();
      });

      expect(a.id, 'a');
      expect(PdfDocument.open(a.bytes).pageCount, greaterThan(0));
      await settle();
      expect(a.peers, {'a', 'b'});

      final presenceSeen = <Set<String>>[];
      final presenceSub = a.presence.listen(presenceSeen.add);
      addTearDown(presenceSub.cancel);

      // a local edit notifies the session's own change stream
      final localChanges = <List<PdfAnnotationChange>>[];
      final changeSub = a.changes.listen(localChanges.add);
      addTearDown(changeSub.cancel);
      a.apply((e) => e.addNote(0, 50, 50, 'hi', name: 'n1'), pages: [0]);
      await settle();
      expect(localChanges, isNotEmpty);

      // and an accepted remote change also surfaces on b.changes
      final remoteChanges = <List<PdfAnnotationChange>>[];
      final bSub = b.changes.listen(remoteChanges.add);
      addTearDown(bSub.cancel);
      a.apply((e) => e.addNote(0, 80, 80, 'yo', name: 'n2'), pages: [0]);
      await settle();
      expect(remoteChanges, isNotEmpty);
    });

    test('a remote removal is applied on the peer', () async {
      final hub = PdfLoopbackSyncHub();
      final base = seeded();
      final a = PdfSyncSession(bytes: base, transport: hub.connect('a'));
      final b = PdfSyncSession(bytes: base, transport: hub.connect('b'));
      addTearDown(() async {
        await a.dispose();
        await b.dispose();
      });

      a.apply((e) => e.addNote(0, 50, 50, 'temp', name: 'temp-1'),
          pages: [0]);
      await settle();
      expect(b.annotationDigest().keys, contains('temp-1'));

      a.apply((e) => e.removeAnnotationByName('temp-1'), pages: [0]);
      await settle();
      expect(b.annotationDigest().keys, isNot(contains('temp-1')),
          reason: 'the remove replayed through _applyRemote');
      expect(a.annotationDigest(), b.annotationDigest());
    });
  });

  group('two sessions converge', () {
    test('independent creates merge both ways', () async {
      final hub = PdfLoopbackSyncHub();
      final base = seeded();
      final a = PdfSyncSession(bytes: base, transport: hub.connect('a'));
      final b = PdfSyncSession(bytes: base, transport: hub.connect('b'));

      a.apply((e) => e.addNote(0, 100, 500, 'from A', name: 'note-a'),
          pages: [0]);
      b.apply((e) => e.addCircle(0, const PdfRect(300, 300, 360, 360),
          name: 'circle-b'),
          pages: [0]);
      await settle();

      expect(a.annotationDigest().keys,
          containsAll(['shared-1', 'note-a', 'circle-b']));
      expect(a.annotationDigest(), b.annotationDigest(),
          reason: 'both sessions hold the same annotation set');
      await a.dispose();
      await b.dispose();
    });

    test('conflicting edits to the same /NM resolve deterministically',
        () async {
      final hub = PdfLoopbackSyncHub();
      final base = seeded();
      final a = PdfSyncSession(bytes: base, transport: hub.connect('a'));
      final b = PdfSyncSession(bytes: base, transport: hub.connect('b'));

      // both restyle 'shared-1' concurrently to different colors before
      // either hears the other (no settle in between)
      a.apply((e) {
        e.restyleAnnotation(
            0, e.document.page(0).annotations.single,
            color: 0xFF0000);
      }, pages: [0]);
      b.apply((e) {
        e.restyleAnnotation(
            0, e.document.page(0).annotations.single,
            color: 0x0000FF);
      }, pages: [0]);
      await settle();

      // converged, and to the SAME winner on both
      expect(a.annotationDigest(), b.annotationDigest());
      final colorA =
          a.document.page(0).annotations.single.color;
      final colorB =
          b.document.page(0).annotations.single.color;
      expect(colorA, colorB);
      // tie on the Lamport clock breaks on the greater origin id ("b")
      expect(colorA, 0x0000FF, reason: 'origin "b" wins the tie');
      await a.dispose();
      await b.dispose();
    });

    test('create-vs-remove on the same /NM converges', () async {
      final hub = PdfLoopbackSyncHub();
      final base = seeded();
      final a = PdfSyncSession(bytes: base, transport: hub.connect('a'));
      final b = PdfSyncSession(bytes: base, transport: hub.connect('b'));

      a.apply((e) => e.removeAnnotationByName('shared-1'), pages: [0]);
      b.apply((e) {
        e.moveAnnotation(0, e.document.page(0).annotations.single, 20, 0);
      }, pages: [0]);
      await settle();

      expect(a.annotationDigest(), b.annotationDigest());
      await a.dispose();
      await b.dispose();
    });

    test('a stale edit (lower clock) is dropped after a newer one', () async {
      final hub = PdfLoopbackSyncHub();
      final base = seeded();
      final a = PdfSyncSession(bytes: base, transport: hub.connect('a'));
      final b = PdfSyncSession(bytes: base, transport: hub.connect('b'));

      // A edits first and B hears it (B's clock advances past A's)
      a.apply((e) {
        e.restyleAnnotation(0, e.document.page(0).annotations.single,
            color: 0xFF0000);
      }, pages: [0]);
      await settle();
      // now B edits — causally later, higher clock — B must win on both
      b.apply((e) {
        e.restyleAnnotation(0, e.document.page(0).annotations.single,
            color: 0x00FF00);
      }, pages: [0]);
      await settle();

      expect(a.annotationDigest(), b.annotationDigest());
      expect(a.document.page(0).annotations.single.color, 0x00FF00);
      await a.dispose();
      await b.dispose();
    });

    test('a reply thread syncs and reassembles on the peer', () async {
      final hub = PdfLoopbackSyncHub();
      final base = seeded();
      final a = PdfSyncSession(bytes: base, transport: hub.connect('a'));
      final b = PdfSyncSession(bytes: base, transport: hub.connect('b'));

      a.apply((e) {
        final root = e.document.page(0).annotations.single;
        e.replyToAnnotation(0, root, 'a remark',
            author: 'A', name: 'reply-1');
      }, pages: [0]);
      await settle();

      expect(b.annotationDigest().keys, contains('reply-1'));
      final thread = PdfCommentThread.forPage(b.document, 0).single;
      expect(thread.name, 'shared-1');
      expect(thread.replyCount, 1);
      expect(thread.root.replies.single.text, 'a remark');
      await a.dispose();
      await b.dispose();
    });
  });
}
