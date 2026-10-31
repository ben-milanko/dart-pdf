// Live sync end to end on a real folder: two people (two editing sessions)
// with the same PDF open from one shared folder - the shape of a OneDrive /
// Google Drive / Dropbox folder on disk - see each other, merge each other's
// annotations, and leave behind one PDF with everyone's work and no
// conflict copies.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor_app/live_sync.dart';
import 'package:dart_pdf_editor_app/live_sync_store_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

Uint8List seeded() => (PdfEditor(PdfDocument.open(buildMultiPagePdf(2)))
      ..addSquare(0, const PdfRect(100, 600, 200, 680),
          strokeColor: 0x000000, name: 'shared-1'))
    .save();

Map<String, String> digest(PdfDocument document) => {
      for (var page = 0; page < document.pageCount; page++)
        for (final annotation in document.page(page).annotations)
          if (annotation.name case final name?)
            name: jsonEncode(PdfAnnotationSnapshot.capture(document, annotation,
                    keepName: true)!
                .toJson()),
    };

/// Polls [condition] (real time) until it holds or [timeout] passes.
Future<void> until(bool Function() condition,
    {Duration timeout = const Duration(seconds: 30)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition not met', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late Directory root;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('live_sync_test');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  group('FolderSyncStore', () {
    test('writes atomically, lists, reads and deletes', () async {
      final store =
          FolderSyncStore(Directory('${root.path}/.a.pdf.dartpdf-sync'));
      expect(await store.list(), isEmpty, reason: 'no folder yet');

      await store.write('ops.a.00000001.json', Uint8List.fromList([1, 2]));
      await store.write('ops.a.00000001.json', Uint8List.fromList([3]));
      await store.write('presence.a.json', Uint8List.fromList([4]));
      // a sync client's half-finished download, and our own temp file
      await File('${store.directory.path}/~\$ops.b.00000001.json.1.tmp')
          .writeAsBytes([9]);

      final names = (await store.list()).map((e) => e.name).toSet();
      expect(names, {'ops.a.00000001.json', 'presence.a.json'});
      expect(await store.read('ops.a.00000001.json'), [3]);
      expect(await store.read('missing.json'), isNull);
      await store.delete('presence.a.json');
      await store.delete('presence.a.json'); // already gone: fine
      expect((await store.list()).map((e) => e.name), ['ops.a.00000001.json']);
    });

    test('the sidecar sits next to the PDF', () {
      final dir = FolderLiveSyncBackend.sidecarFor(
          '${root.path}${Platform.pathSeparator}Plan.pdf');
      expect(dir.path,
          '${root.path}${Platform.pathSeparator}.Plan.pdf.dartpdf-sync');
      expect(
          const FolderLiveSyncBackend().storeFor('content://x/y.pdf'), isNull);
    });
  });

  test('two people sync annotations through a folder and leave one PDF',
      () async {
    final pdf = File('${root.path}/Plan.pdf');
    await pdf.writeAsBytes(seeded());
    final backend = const FolderLiveSyncBackend();

    final sessions = <LiveSyncSession>[];
    final controllers = <PdfEditingController>[];
    Future<(PdfEditingController, LiveSyncSession)> open(String name) async {
      final editing = PdfEditingController(await pdf.readAsBytes());
      final session = LiveSyncSession(
        controller: editing,
        store: backend.storeFor(pdf.path)!,
        name: name,
        device: '$name-laptop',
        writtenLength: editing.bytes.length,
        pollInterval: const Duration(milliseconds: 25),
        compactAfter: const Duration(milliseconds: 100),
        writePdf: (bytes) async {
          // temp + rename, so the checks below never read a half-written file
          final temp = File('${pdf.path}.$name.tmp');
          await temp.writeAsBytes(bytes, flush: true);
          await temp.rename(pdf.path);
          return true;
        },
      );
      controllers.add(editing);
      sessions.add(session);
      await session.start();
      return (editing, session);
    }

    addTearDown(() async {
      for (final s in sessions) {
        await s.close();
      }
      for (final c in controllers) {
        c.dispose();
      }
    });

    final (alice, aliceSync) = await open('Alice');
    // listen before Bob exists, or Alice may see him join first
    final joinedAtAlice = <String>[];
    aliceSync.peerChanges
        .listen((c) => joinedAtAlice.add('${c.joined}:${c.peer.name}'));
    final (bob, bobSync) = await open('Bob');

    // they see each other, by name
    await until(() =>
        aliceSync.peers.map((p) => p.name).join() == 'Bob' &&
        bobSync.peers.map((p) => p.name).join() == 'Alice');
    expect(aliceSync.status, LiveSyncStatus.live);
    expect(bobSync.peers.single.device, 'Alice-laptop');
    expect([aliceSync.isWriter, bobSync.isWriter].where((w) => w), hasLength(1),
        reason: 'exactly one of them writes the PDF');

    // each annotates; both end up with both
    alice.addRectangle(1, const PdfRect(300, 300, 360, 360));
    bob.addNote(0, 50, 50, 'from Bob');
    await until(() =>
        digest(alice.document).length == 3 && digest(bob.document).length == 3);
    expect(digest(alice.document), digest(bob.document));

    // page edits are off while syncing
    bob.removePage(1);
    expect(bob.document.pageCount, 2);

    // the writer folds everything into the PDF once it is quiet
    await until(() {
      final onDisk = PdfDocument.open(pdf.readAsBytesSync());
      return digest(onDisk).length == 3;
    });
    expect(digest(PdfDocument.open(pdf.readAsBytesSync())),
        digest(alice.document));

    // one PDF and its sidecar - no "Plan (1).pdf" or conflict copies
    expect(
        root
            .listSync()
            .map((e) => e.uri.pathSegments.lastWhere((s) => s.isNotEmpty))
            .toSet(),
        {'Plan.pdf', '.Plan.pdf.dartpdf-sync'});

    // Bob leaves: Alice is told, and becomes (or stays) the writer
    await bobSync.close();
    await until(() => aliceSync.peers.isEmpty);
    expect(joinedAtAlice, ['true:Bob', 'false:Bob']);
    expect(aliceSync.isWriter, isTrue);

    // someone opening the PDF later starts from the file plus the log and
    // lands on the same annotations, without a revision per replayed change
    final (carol, carolSync) = await open('Carol');
    expect(digest(carol.document), digest(alice.document));
    expect(carol.canUndo, isFalse);
    await until(() => carolSync.peers.map((p) => p.name).join() == 'Alice');
  });

  test('the first session names unnamed annotations and writes them', () async {
    // a legacy PDF whose annotation has no /NM
    final pdf = File('${root.path}/Legacy.pdf');
    final editor = PdfEditor(PdfDocument.open(seeded()));
    editor.setAnnotationName(
        0, editor.document.page(0).annotations.single, null);
    await pdf.writeAsBytes(editor.save());
    expect(
        PdfDocument.open(pdf.readAsBytesSync()).page(0).annotations.single.name,
        isNull);

    final editing = PdfEditingController(await pdf.readAsBytes());
    addTearDown(editing.dispose);
    final session = LiveSyncSession(
      controller: editing,
      store: const FolderLiveSyncBackend().storeFor(pdf.path)!,
      name: 'Alice',
      pollInterval: const Duration(milliseconds: 25),
      writePdf: (bytes) async {
        await pdf.writeAsBytes(bytes, flush: true);
        return true;
      },
    );
    addTearDown(session.close);
    await session.start();

    final named =
        PdfDocument.open(pdf.readAsBytesSync()).page(0).annotations.single;
    expect(named.name, isNotNull,
        reason: 'joiners must start from the same names');
  });

  test('an unreachable folder reads as offline', () async {
    final editing = PdfEditingController(seeded());
    addTearDown(editing.dispose);
    final session = LiveSyncSession(
      controller: editing,
      store: _BrokenStore(),
      name: 'Alice',
      writePdf: (_) async => true,
    );
    addTearDown(session.close);
    await session.start();
    expect(session.status, LiveSyncStatus.offline);
    expect(session.error, isA<FileSystemException>());
  });
}

class _BrokenStore implements PdfSyncStore {
  @override
  Future<List<PdfSyncStoreEntry>> list() async =>
      throw const FileSystemException('offline');
  @override
  Future<Uint8List?> read(String name) async =>
      throw const FileSystemException('offline');
  @override
  Future<void> write(String name, Uint8List bytes) async =>
      throw const FileSystemException('offline');
  @override
  Future<void> delete(String name) async {}
}
