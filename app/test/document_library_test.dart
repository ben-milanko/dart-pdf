// The open documents' persistence without pumping EditorScreen: the restore
// list, the Recent-recording rule, snapshots, and the tab transitions the
// stores observe.

import 'dart:async';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor_app/document_library.dart';
import 'package:dart_pdf_editor_app/document_tab.dart';
import 'package:dart_pdf_editor_app/document_tabs.dart';
import 'package:dart_pdf_editor_app/recents.dart';
import 'package:dart_pdf_editor_app/session_store.dart';
import 'package:dart_pdf_editor_app/unsaved_changes.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

class _Session implements SessionPersistence {
  final saves = <List<SessionDocument>>[];

  @override
  Future<List<SessionDocument>> load() async => const [];

  @override
  Future<void> save(List<SessionDocument> documents) async =>
      saves.add(documents);

  List<String> get lastKeys => [
        for (final doc in saves.last)
          doc.path.isNotEmpty ? doc.path : doc.cachePath!,
      ];
}

class _Recents implements RecentsLog {
  @override
  final items = <RecentFile>[];
  final availability = <(Set<String>, Set<String>)>[];

  @override
  Future<void> add(
      {required String title,
      String? path,
      String? cachePath,
      String? bookmark}) async {
    items.insert(
        0,
        RecentFile(
            title: title,
            path: path,
            cachePath: cachePath,
            bookmark: bookmark,
            openedAt: items.length));
  }

  @override
  Future<void> updateCachedAvailability(
      Set<String> checked, Set<String> available) async {
    availability.add((checked, available));
  }
}

class _Snapshots implements PdfSnapshotStore {
  _Snapshots({this.available = true});

  @override
  final bool available;

  /// Completes a pending write with its key (null = the write failed).
  final writes = <Completer<String?>>[];
  final prunes = <Set<String>>[];

  @override
  Future<String?> store(Uint8List bytes) {
    final write = Completer<String?>();
    writes.add(write);
    return write.future;
  }

  @override
  Future<Set<String>?> prune(Set<String> keep) async {
    prunes.add(keep);
    return keep;
  }
}

class _Placeholder extends DocumentTab {
  _Placeholder(String title, {super.originPath}) : super.loading(title: title);

  bool disposed = false;

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

void main() {
  final pdf = buildClassicPdf();
  late PdfEditingPreferences prefs;
  late List<VoidCallback> frame;
  late DocumentTabs tabs;
  late _Session session;
  late _Recents recents;
  late _Snapshots snapshots;
  late DocumentLibrary library;
  late List<List<DocumentTab>> tracked;

  DocumentLibrary build({bool canSnapshot = true, bool persists = true}) {
    snapshots = _Snapshots(available: canSnapshot);
    return DocumentLibrary(
      tabs: tabs,
      session: session,
      recents: recents,
      snapshots: snapshots,
      persistsSession: persists,
      onTabsChanged: tracked.add,
    )..sessionLoaded = true;
  }

  setUp(() {
    prefs = PdfEditingPreferences();
    frame = [];
    tabs = DocumentTabs(afterFrame: frame.add);
    session = _Session();
    recents = _Recents();
    tracked = [];
    library = build();
  });

  tearDown(() {
    library.dispose();
    tabs.dispose();
  });

  void endFrame() {
    for (final callback in List.of(frame)) {
      callback();
    }
    frame.clear();
  }

  DocumentTab document(String title,
          {String? originPath, String? cachePath, String? bookmark}) =>
      DocumentTab.document(
          title: title,
          bytes: pdf,
          preferences: prefs,
          originPath: originPath,
          originBookmark: bookmark,
          cachePath: cachePath);

  group('recentRecordingFor', () {
    test('a file origin or an existing snapshot records now', () {
      expect(
          recentRecordingFor(
              originPath: '/a.pdf', cachePath: null, canSnapshot: true),
          RecentRecording.now);
      expect(
          recentRecordingFor(
              originPath: null, cachePath: 'snap', canSnapshot: true),
          RecentRecording.now);
    });

    test('a path-less pick snapshots first where snapshots exist', () {
      expect(
          recentRecordingFor(
              originPath: null, cachePath: null, canSnapshot: true),
          RecentRecording.afterSnapshot);
      expect(
          recentRecordingFor(
              originPath: null, cachePath: null, canSnapshot: false),
          RecentRecording.now);
    });
  });

  group('sessionDocumentsOf', () {
    test('keys by origin, then snapshot, once each, in strip order', () {
      final open = [
        document('b', originPath: '/b.pdf', bookmark: 'bm'),
        document('a', cachePath: 'snap-a'),
        document('b again', originPath: '/b.pdf'),
        DocumentTab.error(title: 'broken', error: 'x'),
        document('scan'),
      ];
      addTearDown(() {
        for (final tab in open) {
          tab.dispose();
        }
      });
      final docs = sessionDocumentsOf(open);
      expect([for (final d in docs) d.title], ['b', 'a']);
      expect(docs.first.bookmark, 'bm');
      expect(docs.last.path, '');
      expect(docs.last.cachePath, 'snap-a');
    });
  });

  group('persistence', () {
    test('every tab change persists, after the autosave mirror sees it', () {
      final tab = document('a', originPath: '/a.pdf');
      tabs.add(tab);
      expect(tracked.single, [tab]);
      expect(session.lastKeys, ['/a.pdf']);
      tabs.remove([tab]);
      expect(session.lastKeys, isEmpty);
    });

    test('nothing is saved until the last session has been read back', () {
      library.dispose();
      library = build()..sessionLoaded = false;
      tabs.add(document('a', originPath: '/a.pdf'));
      expect(tracked, hasLength(1), reason: 'the mirror still tracks it');
      expect(session.saves, isEmpty);
    });

    test('a secondary window never writes the restore list', () {
      library.dispose();
      library = build(persists: false);
      tabs.add(document('a', originPath: '/a.pdf'));
      expect(session.saves, isEmpty);
    });
  });

  group('recording an open', () {
    test('a desktop file records its path straight away', () async {
      final tab = document('a', originPath: '/a.pdf', bookmark: 'bm');
      tabs.add(tab);
      await library.recordOpened(tab, pdf);
      expect(snapshots.writes, isEmpty);
      expect(recents.items.single.path, '/a.pdf');
      expect(recents.items.single.bookmark, 'bm');
    });

    test('a mobile pick snapshots, records the snapshot, and re-persists',
        () async {
      final tab = document('pick');
      tabs.add(tab);
      expect(session.lastKeys, isEmpty, reason: 'no reusable source yet');
      final recorded = library.recordOpened(tab, pdf);
      await pumpEventQueue();
      expect(recents.items, isEmpty, reason: 'held until the write lands');
      snapshots.writes.single.complete('snap-1');
      await recorded;
      await pumpEventQueue();
      expect(tab.cachePath, 'snap-1');
      expect(recents.items.single.cachePath, 'snap-1');
      expect(session.lastKeys, ['snap-1']);
      expect(snapshots.prunes.last, {'snap-1'},
          reason: 'the prune after the write keeps it');
    });

    test('a failed snapshot still records a non-reopenable recent', () async {
      final tab = document('pick');
      tabs.add(tab);
      final recorded = library.recordOpened(tab, pdf);
      await pumpEventQueue();
      snapshots.writes.single.complete(null);
      await recorded;
      expect(tab.cachePath, isNull);
      expect(recents.items.single.isReopenable, isFalse);
    });

    test('a tab closed before its snapshot lands records nothing', () async {
      final tab = document('pick');
      tabs.add(tab);
      final recorded = library.recordOpened(tab, pdf);
      await pumpEventQueue();
      tabs.remove([tab]);
      snapshots.writes.single.complete('snap-1');
      await recorded;
      expect(recents.items, isEmpty);
      expect(tab.cachePath, isNull);
    });

    test('without a snapshot store a pick records non-reopenably', () async {
      library.dispose();
      library = build(canSnapshot: false);
      final tab = document('pick');
      tabs.add(tab);
      await library.recordOpened(tab, pdf);
      expect(snapshots.writes, isEmpty);
      expect(recents.items.single.isReopenable, isFalse);
    });

    test('only an unbacked tab is snapshotted on demand', () async {
      final backed = document('a', originPath: '/a.pdf');
      tabs.add(backed);
      expect(await library.snapshotIfUnbacked(backed, pdf), isFalse);
      expect(snapshots.writes, isEmpty);
    });
  });

  group('transitions', () {
    test(
        'a progressive open whose full read fails becomes an error tab, '
        'disposes the preview after the frame, and leaves no session entry',
        () {
      final preview = _Placeholder('cloud.pdf', originPath: '/cloud.pdf');
      tabs.add(preview);
      expect(session.lastKeys, ['/cloud.pdf']);
      tabs.replace(
          preview, DocumentTab.error(title: 'cloud.pdf', error: 'read failed'));
      expect(preview.disposed, isFalse, reason: 'still mounted this frame');
      endFrame();
      expect(preview.disposed, isTrue);
      expect(session.lastKeys, isEmpty);
    });

    test('a deferred tab materialises keeping its origin and snapshot', () {
      final deferred = DocumentTab.deferred(
          title: 'a',
          bytes: pdf,
          originPath: '/a.pdf',
          originBookmark: 'bm',
          cachePath: 'snap-a');
      final promoted =
          DocumentTab.promoted(deferred, bytes: pdf, preferences: prefs);
      addTearDown(promoted.dispose);
      expect(promoted.session, isNotNull);
      expect(promoted.originPath, '/a.pdf');
      expect(promoted.originBookmark, 'bm');
      expect(promoted.cachePath, 'snap-a');
      expect(promoted.isDirty, isFalse);
    });

    test('a recovered document comes back dirty at its save destination', () {
      final recovered = RecoveredDocument(
        record: UnsavedRecord(
          id: 'r1',
          title: 'draft',
          length: pdf.length,
          originPath: '/draft.pdf',
          originBookmark: 'bm',
          cachePath: 'snap-old',
          savedLength: pdf.length - 10,
        ),
        bytes: pdf,
      );
      final tab = DocumentTab.recovered(recovered,
          preferences: prefs, cachePath: 'snap-live');
      addTearDown(tab.dispose);
      expect(tab.isDirty, isTrue);
      expect(tab.savedLength, pdf.length - 10);
      expect(tab.originPath, '/draft.pdf');
      expect(tab.originBookmark, 'bm');
      expect(tab.cachePath, 'snap-live', reason: 'the resolved key wins');
      final pathless = DocumentTab.recovered(
          RecoveredDocument(
              record: UnsavedRecord(id: 'r2', title: 'scan', length: 1),
              bytes: pdf),
          preferences: prefs);
      addTearDown(pathless.dispose);
      expect(pathless.originPath, isNull);
      expect(pathless.isUnsaved, isTrue);
    });

    test('a window handoff keeps its saved baseline and origin', () {
      final handoff = DocumentHandoff(
        bytes: pdf,
        title: 'moved',
        savedLength: pdf.length - 10,
        originPath: '/moved.pdf',
        originBookmark: 'bm',
        originToken: 'token',
        cachePath: 'snap-m',
      );
      final tab = DocumentTab.fromHandoff(handoff, preferences: prefs);
      addTearDown(tab.dispose);
      expect(tab.savedLength, handoff.savedLength);
      expect(tab.isDirty, isTrue);
      expect(tab.originPath, '/moved.pdf');
      expect(tab.originBookmark, 'bm');
      expect(tab.originToken, 'token');
      expect(tab.cachePath, 'snap-m');
    });
  });
}
