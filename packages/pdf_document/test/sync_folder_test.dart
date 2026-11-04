// The shared-folder transport: sessions syncing through a store of small
// files (the shape of a OneDrive / Drive / iCloud / WebDAV folder), where
// every file has exactly one writer.

import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

/// A base document seeded with one named square, as in sync_test.dart.
Uint8List seeded() {
  final editor = PdfEditor(PdfDocument.open(buildClassicPdf()))
    ..addSquare(0, const PdfRect(100, 600, 200, 680),
        strokeColor: 0x000000, name: 'shared-1');
  return editor.save();
}

PdfSharedFolderSyncTransport folder(PdfSyncStore store, String id,
        {DateTime Function()? now}) =>
    PdfSharedFolderSyncTransport(
        store: store, sessionId: id, flushDelay: Duration.zero, now: now);

/// Flushes every writer, then lets every reader poll.
Future<void> exchange(List<PdfSharedFolderSyncTransport> transports) async {
  for (final t in transports) {
    await t.flush();
  }
  for (final t in transports) {
    await t.poll();
  }
  await Future<void>.delayed(Duration.zero);
}

void main() {
  test('writer ids are validated', () {
    final store = PdfMemorySyncStore();
    expect(() => folder(store, 'a.b'), throwsArgumentError);
    expect(() => folder(store, ''), throwsArgumentError);
    expect(PdfSharedFolderSyncTransport.isValidWriterId('laptop_7f3a'), isTrue);
  });

  test('two sessions converge through one folder', () async {
    final store = PdfMemorySyncStore();
    final ta = folder(store, 'alice_1');
    final tb = folder(store, 'bob_1');
    final base = seeded();
    final a = PdfSyncSession(bytes: base, transport: ta);
    final b = PdfSyncSession(bytes: base, transport: tb);
    addTearDown(() async {
      await a.dispose();
      await b.dispose();
    });

    a.apply((e) => e.addNote(0, 100, 500, 'from A', name: 'note-a'),
        pages: [0]);
    b.apply(
        (e) =>
            e.addCircle(0, const PdfRect(300, 300, 360, 360), name: 'circle-b'),
        pages: [0]);
    await exchange([ta, tb]);

    expect(a.annotationDigest().keys,
        containsAll(['shared-1', 'note-a', 'circle-b']));
    expect(a.annotationDigest(), b.annotationDigest());

    // every file in the folder carries exactly one writer's id
    for (final name in store.names) {
      expect(name, anyOf(contains('alice_1'), contains('bob_1')));
    }
  });

  test('sends batch into one immutable op file per flush', () async {
    final store = PdfMemorySyncStore();
    final ta = folder(store, 'a');
    final a = PdfSyncSession(bytes: seeded(), transport: ta);
    addTearDown(a.dispose);

    a.apply((e) {
      e.addNote(0, 10, 10, 'one', name: 'n1');
      e.addNote(0, 20, 20, 'two', name: 'n2');
    }, pages: [0]);
    expect(ta.pendingCount, 2);
    await ta.flush();
    expect(ta.pendingCount, 0);
    a.apply((e) => e.addNote(0, 30, 30, 'three', name: 'n3'), pages: [0]);
    await ta.flush();

    final ops = store.names.where((n) => n.startsWith('ops.')).toList()..sort();
    expect(ops, ['ops.a.00000001.json', 'ops.a.00000002.json']);
  });

  test('a late joiner catches up, including its own earlier session', () async {
    final store = PdfMemorySyncStore();
    final base = seeded();

    // the same device edited yesterday and closed without compacting
    final yesterday = folder(store, 'laptop_day1');
    final s1 = PdfSyncSession(bytes: base, transport: yesterday);
    s1.apply((e) => e.addNote(0, 50, 50, 'old', name: 'old-note'), pages: [0]);
    await yesterday.flush();
    await s1.dispose();
    yesterday.close();

    // reopening the same (uncompacted) PDF replays the log
    final today = folder(store, 'laptop_day2');
    final s2 = PdfSyncSession(bytes: base, transport: today);
    addTearDown(s2.dispose);
    await today.poll();
    await Future<void>.delayed(Duration.zero);
    expect(s2.annotationDigest().keys, contains('old-note'));

    // and its clock moved past the history, so a new edit wins
    s2.apply((e) {
      e.restyleAnnotation(
          0,
          e.document
              .page(0)
              .annotations
              .firstWhere((x) => x.name == 'shared-1'),
          color: 0x00FF00);
    }, pages: [0]);
    await today.flush();
    final reader = folder(store, 'phone_1');
    final s3 = PdfSyncSession(bytes: base, transport: reader);
    addTearDown(s3.dispose);
    await reader.poll();
    await Future<void>.delayed(Duration.zero);
    expect(s3.annotationDigest(), s2.annotationDigest());
  });

  test('a file still syncing down is retried, not dropped', () async {
    final store = PdfMemorySyncStore();
    final tb = folder(store, 'b');
    final received = <PdfSyncMessage>[];
    tb.incoming.listen(received.add);
    addTearDown(tb.close);

    final doc = PdfDocument.open(seeded());
    final message = PdfSyncMessage(
      origin: 'a',
      clock: 1,
      change: PdfAnnotationChange(
        kind: PdfAnnotationChangeKind.created,
        pageIndex: 0,
        name: 'shared-1',
        snapshot: PdfAnnotationSnapshot.capture(
            doc, doc.page(0).annotations.single,
            keepName: true),
      ),
    );
    final full = utf8.encode(jsonEncode([message.toJson()]));
    await store.write('ops.a.00000001.json',
        Uint8List.fromList(full.sublist(0, full.length ~/ 2)));
    expect(await tb.poll(), 0);

    await store.write('ops.a.00000001.json', Uint8List.fromList(full));
    expect(await tb.poll(), 1);
    expect(await tb.poll(), 0, reason: 'delivered once');
    await Future<void>.delayed(Duration.zero);
    expect(received.single.name, 'shared-1');
  });

  test('presence follows fresh presence files and expires', () async {
    var now = DateTime.utc(2026, 10, 28, 9);
    DateTime clock() => now;
    final store = PdfMemorySyncStore(now: clock);
    final ta = folder(store, 'a', now: clock);
    final tb = folder(store, 'b', now: clock);
    final seen = <Set<String>>[];
    ta.presence.listen(seen.add);

    await tb.poll();
    await ta.poll();
    expect(ta.peers, {'a', 'b'});

    // b goes quiet (crashed, offline) - it drops out after the timeout
    now = now.add(const Duration(seconds: 90));
    await ta.poll();
    expect(ta.peers, {'a'});

    // a clean close removes the presence file at once
    await tb.poll();
    await ta.poll();
    expect(ta.peers, {'a', 'b'});
    tb.close();
    await Future<void>.delayed(Duration.zero);
    await ta.poll();
    expect(ta.peers, {'a'});
    await Future<void>.delayed(Duration.zero);
    expect(seen.last, {'a'});
    ta.close();
  });

  test('a failed write keeps the batch pending for the next flush', () async {
    final store = _FlakyStore();
    final ta = folder(store, 'a');
    final a = PdfSyncSession(bytes: seeded(), transport: ta);
    addTearDown(a.dispose);
    a.apply((e) => e.addNote(0, 10, 10, 'x', name: 'n1'), pages: [0]);

    store.failNext = true;
    await expectLater(ta.flush(), throwsA(isA<StateError>()));
    expect(ta.pendingCount, 1);
    await ta.flush();
    expect(ta.pendingCount, 0);
    expect(store.names, contains('ops.a.00000001.json'));
  });
}

class _FlakyStore extends PdfMemorySyncStore {
  bool failNext = false;

  @override
  Future<void> write(String name, Uint8List bytes) {
    if (failNext) {
      failNext = false;
      throw StateError('offline');
    }
    return super.write(name, bytes);
  }
}
