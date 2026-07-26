import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/autosave.dart';
import 'package:dart_pdf_editor_app/document_tab.dart';
import 'package:dart_pdf_editor_app/unsaved_changes.dart';

/// Short enough to pump through, long enough to still coalesce a burst.
const _debounce = Duration(milliseconds: 20);

void main() {
  late PdfEditingPreferences prefs;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    prefs = PdfEditingPreferences();
  });

  tearDown(() => prefs.dispose());

  DocumentTab openTab({String title = 'a.pdf', String? path = '/docs/a.pdf'}) =>
      DocumentTab.document(
        title: title,
        bytes: Uint8List.fromList(buildClassicPdf()),
        preferences: prefs,
        originPath: path,
      );

  AutosaveController controllerOver(UnsavedChangesStore store) =>
      AutosaveController(store: store, debounce: _debounce);

  // Lets the debounce fire and the (async) store write settle.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(_debounce);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('an untouched document is never mirrored', (tester) async {
    final store = InMemoryUnsavedChangesStore();
    final autosave = controllerOver(store);
    final tab = openTab();
    addTearDown(tab.dispose);

    autosave.track(tab);
    await settle(tester);

    expect(tab.isDirty, isFalse);
    expect(await store.list(), isEmpty,
        reason: 'nothing is unsaved, so there is nothing to recover');
    expect(store.bytesWritten, 0);
  });

  testWidgets('an edit is mirrored, and the next one costs only its tail',
      (tester) async {
    final store = InMemoryUnsavedChangesStore();
    final autosave = controllerOver(store);
    final tab = openTab();
    addTearDown(tab.dispose);
    autosave.track(tab);

    expect(tab.session!.addBookmark('first'), isTrue);
    await settle(tester);

    var records = await store.list();
    expect(records, hasLength(1));
    expect(records.single.title, 'a.pdf');
    expect(records.single.originPath, '/docs/a.pdf');
    expect(records.single.length, tab.session!.bytes.length);
    // The baseline travels with the record, so recovery knows the document is
    // dirty rather than merely open.
    expect(records.single.savedLength, lessThan(records.single.length));
    final firstPass = store.bytesWritten;
    expect(firstPass, tab.session!.bytes.length);

    final lengthAfterFirst = tab.session!.bytes.length;
    expect(tab.session!.addBookmark('second'), isTrue);
    await settle(tester);

    records = await store.list();
    expect(records.single.length, tab.session!.bytes.length);
    // Revisions are prefixes of one buffer, so mirroring the second edit must
    // append its tail - not re-copy the document. This is the whole reason
    // autosaving a large PDF on every edit is affordable.
    expect(store.bytesWritten - firstPass,
        tab.session!.bytes.length - lengthAfterFirst);
  });

  testWidgets('a burst of edits coalesces into one mirror pass',
      (tester) async {
    final store = InMemoryUnsavedChangesStore();
    final autosave = controllerOver(store);
    final tab = openTab();
    addTearDown(tab.dispose);
    autosave.track(tab);

    for (var i = 0; i < 5; i++) {
      expect(tab.session!.addBookmark('b$i'), isTrue);
      await tester.pump(const Duration(milliseconds: 2));
    }
    await settle(tester);

    final records = await store.list();
    expect(records, hasLength(1));
    expect(records.single.length, tab.session!.bytes.length);
    // One pass over the final revision, not five.
    expect(store.bytesWritten, tab.session!.bytes.length);
  });

  testWidgets('saving drops the record', (tester) async {
    final store = InMemoryUnsavedChangesStore();
    final autosave = controllerOver(store);
    final tab = openTab();
    addTearDown(tab.dispose);
    autosave.track(tab);

    tab.session!.addBookmark('one');
    await settle(tester);
    expect(await store.list(), hasLength(1));

    tab.markSaved();
    await autosave.noteSaved(tab);

    expect(await store.list(), isEmpty,
        reason: 'the bytes are on the user\'s own disk now');
  });

  testWidgets('undoing back to the saved state drops the record',
      (tester) async {
    final store = InMemoryUnsavedChangesStore();
    final autosave = controllerOver(store);
    final tab = openTab();
    addTearDown(tab.dispose);
    autosave.track(tab);

    tab.session!.addBookmark('one');
    await settle(tester);
    expect(await store.list(), hasLength(1));

    tab.session!.undo();
    await settle(tester);

    expect(tab.isDirty, isFalse);
    expect(await store.list(), isEmpty);
  });

  testWidgets('closing a tab drops its record', (tester) async {
    final store = InMemoryUnsavedChangesStore();
    final autosave = controllerOver(store);
    final tab = openTab();
    autosave.track(tab);

    tab.session!.addBookmark('one');
    await settle(tester);
    expect(await store.list(), hasLength(1));

    // What the editor does when the tab set changes: a closed tab is no longer
    // in the list, so its mirror goes away with it.
    autosave.syncTracking(const []);
    await tester.pump();
    tab.dispose();

    expect(await store.list(), isEmpty);
  });

  testWidgets('discarding on exit drops every record', (tester) async {
    final store = InMemoryUnsavedChangesStore();
    final autosave = controllerOver(store);
    final a = openTab(title: 'a.pdf');
    final b = openTab(title: 'b.pdf', path: '/docs/b.pdf');
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    autosave..track(a)..track(b);

    a.session!.addBookmark('one');
    b.session!.addBookmark('one');
    await settle(tester);
    expect(await store.list(), hasLength(2));

    await autosave.discardAll();

    expect(await store.list(), isEmpty,
        reason: 'the user was asked and chose to throw the edits away');
  });

  testWidgets('backgrounding mirrors without waiting out the debounce',
      (tester) async {
    final store = InMemoryUnsavedChangesStore();
    final autosave = controllerOver(store);
    final tab = openTab();
    addTearDown(tab.dispose);
    autosave.track(tab);

    tab.session!.addBookmark('one');
    // No pump past the debounce: on mobile and the web, the moment the app
    // leaves the foreground can be the last one we get.
    await autosave.flushPending();

    expect((await store.list()).single.length, tab.session!.bytes.length);
  });

  testWidgets('a lost session comes back at the revision it was on',
      (tester) async {
    final store = InMemoryUnsavedChangesStore();
    final crashed = controllerOver(store);
    final tab = openTab(title: 'work.pdf');
    crashed.track(tab);
    tab.session!.addBookmark('unsaved work');
    await settle(tester);
    final lostBytes = Uint8List.fromList(tab.session!.bytes);
    final lostBaseline = tab.savedLength;
    // The app goes away without ever untracking: exactly what a crash looks
    // like from the store's point of view.
    crashed.dispose();
    tab.dispose();

    final relaunched = controllerOver(store);
    final recovered = await relaunched.recover();

    expect(recovered, hasLength(1));
    expect(recovered.single.record.title, 'work.pdf');
    expect(recovered.single.record.originPath, '/docs/a.pdf');
    expect(recovered.single.record.savedLength, lostBaseline);
    expect(recovered.single.bytes, lostBytes);
  });

  testWidgets('a recovered document keeps appending to its own record',
      (tester) async {
    final store = InMemoryUnsavedChangesStore();
    final crashed = controllerOver(store);
    final lost = openTab(title: 'work.pdf');
    crashed.track(lost);
    lost.session!.addBookmark('unsaved work');
    await settle(tester);
    crashed.dispose();
    lost.dispose();

    final relaunched = controllerOver(store);
    final doc = (await relaunched.recover()).single;
    final reopened = DocumentTab.document(
      title: doc.record.title,
      bytes: doc.bytes,
      preferences: prefs,
      originPath: doc.record.originPath,
      savedLength: doc.record.savedLength,
    );
    addTearDown(reopened.dispose);
    relaunched.track(reopened, recovered: doc.record);
    await relaunched.pruneAfterRecovery();

    // Still dirty, still pointed at the same file, and still under one record.
    expect(reopened.isDirty, isTrue);
    expect(await store.list(), hasLength(1));
    final beforeAdoption = store.bytesWritten;

    reopened.session!.addBookmark('more work');
    await settle(tester);

    final records = await store.list();
    expect(records, hasLength(1),
        reason: 'adopting the record must not fork a second copy');
    expect(records.single.id, doc.record.id);
    expect(records.single.length, reopened.session!.bytes.length);
    // Adoption appends the new edit only - it does not re-mirror the document
    // it just read back.
    expect(store.bytesWritten - beforeAdoption,
        lessThan(reopened.session!.bytes.length));
  });

  testWidgets('recovery drops records nothing adopted', (tester) async {
    final store = InMemoryUnsavedChangesStore();
    await store.write(
      const UnsavedRecord(id: 'orphan', title: 'gone.pdf', length: 4),
      Uint8List.fromList(const [1, 2, 3, 4]),
    );

    final autosave = controllerOver(store);
    await autosave.recover();
    await autosave.pruneAfterRecovery();

    expect(await store.list(), isEmpty,
        reason: 'an unadopted record would otherwise be offered forever');
  });

  testWidgets('a store that fails every write never breaks editing',
      (tester) async {
    final autosave = controllerOver(_FailingStore());
    final tab = openTab();
    addTearDown(tab.dispose);
    autosave.track(tab);

    expect(tab.session!.addBookmark('one'), isTrue);
    await settle(tester);
    await autosave.flushPending();

    expect(tab.isDirty, isTrue);
    expect(tab.session!.bytes, isNotEmpty);
  });

  test('a platform with no store leaves recovery disabled', () async {
    final autosave = AutosaveController(store: null);
    expect(autosave.enabled, isFalse);
    expect(await autosave.recover(), isEmpty);
  });

  test('a record round-trips through its encoding', () {
    const record = UnsavedRecord(
      id: 'abc-1',
      title: 'a.pdf',
      length: 4096,
      originPath: '/docs/a.pdf',
      originBookmark: 'bm',
      cachePath: '/cache/a.pdf',
      savedLength: 2048,
      updatedAt: 1234,
    );
    final decoded = UnsavedRecord.decode(record.encode())!;
    expect(decoded.sameAs(record), isTrue);
    expect(decoded.updatedAt, 1234);
  });

  group('chunking (the web store\'s append arithmetic)', () {
    const chunking = UnsavedChunking(1024);

    test('a document occupies exactly the chunks it needs', () {
      expect(chunking.chunkCount(0), 0);
      expect(chunking.chunkCount(1), 1);
      expect(chunking.chunkCount(1024), 1);
      expect(chunking.chunkCount(1025), 2);
      expect(chunking.chunkCount(4096), 4);
    });

    test('an append rewrites the partial chunk and nothing before it', () {
      // Nothing stored: everything is new.
      expect(chunking.firstDirtyChunk(0), 0);
      // Mid-chunk: that chunk is partial and has to be rewritten...
      expect(chunking.firstDirtyChunk(1), 0);
      expect(chunking.firstDirtyChunk(1023), 0);
      expect(chunking.firstDirtyChunk(1500), 1);
      // ...but on an exact boundary the previous chunk is full and final, so
      // the append starts a fresh one instead of rewriting a whole megabyte.
      expect(chunking.firstDirtyChunk(1024), 1);
      expect(chunking.firstDirtyChunk(4096), 4);
    });

    test('the last chunk is short, not padded', () {
      expect(chunking.chunkStart(2), 2048);
      expect(chunking.chunkEnd(2, 4096), 3072);
      expect(chunking.chunkEnd(2, 2500), 2500);
      // Every chunk of a document tiles it exactly once, with no gap or
      // overlap - what a read relies on when it splices them back together.
      const length = 5000;
      var offset = 0;
      for (var i = 0; i < chunking.chunkCount(length); i++) {
        expect(chunking.chunkStart(i), offset);
        offset = chunking.chunkEnd(i, length);
      }
      expect(offset, length);
    });
  });

  test('a truncated or foreign record decodes to nothing', () {
    // What a crash mid-commit leaves behind. Better no recovery than a
    // half-read one.
    expect(UnsavedRecord.decode('{"i":"abc","t":"a.pdf",'), isNull);
    expect(UnsavedRecord.decode('[]'), isNull);
    expect(UnsavedRecord.decode('{"t":"a.pdf","n":10}'), isNull);
    expect(UnsavedRecord.decode('{"i":"abc","n":0}'), isNull);
  });
}

/// A store where nothing works - a full disk, a denied sandbox, a browser with
/// storage switched off.
class _FailingStore implements UnsavedChangesStore {
  @override
  Future<void> delete(String id) async => throw StateError('no store');

  @override
  Future<List<UnsavedRecord>> list() async => throw StateError('no store');

  @override
  Future<void> pruneExcept(Set<String> keep) async =>
      throw StateError('no store');

  @override
  Future<Uint8List?> read(UnsavedRecord record) async =>
      throw StateError('no store');

  @override
  Future<void> write(UnsavedRecord record, Uint8List bytes) async =>
      throw StateError('no store');
}
