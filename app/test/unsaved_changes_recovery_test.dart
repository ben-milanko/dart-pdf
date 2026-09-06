import 'dart:convert';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/document_tab.dart';
import 'package:dart_pdf_editor_app/editor_screen.dart';
import 'package:dart_pdf_editor_app/file_io.dart';
import 'package:dart_pdf_editor_app/unsaved_changes.dart';

import 'test_finders.dart';

/// The editor half of crash recovery: what the user sees on the launch after
/// the app went away with unsaved work.
void main() {
  late PdfEditingPreferences prefs;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    prefs = PdfEditingPreferences();
  });

  tearDown(() => prefs.dispose());

  Finder tabTitle(String name) => find.descendant(
        of: find.byKey(const ValueKey('tab-strip')),
        matching: findMiddleEllipsisText(name),
      );

  /// The dirty dot the tab strip paints beside an edited document.
  Finder dirtyDot() => find.descendant(
        of: find.byKey(const ValueKey('tab-strip')),
        matching: find.byWidgetPredicate(
            (w) => w is Icon && w.icon == Icons.circle && w.size == 8),
      );

  /// Builds a real edited revision and mirrors it, exactly as a run that
  /// crashed mid-edit would have left the store.
  Future<InMemoryUnsavedChangesStore> storeWithLostWork({
    String title = 'crashed.pdf',
    String originPath = '/docs/crashed.pdf',
  }) async {
    final tab = DocumentTab.document(
      title: title,
      bytes: Uint8List.fromList(buildClassicPdf()),
      preferences: prefs,
      originPath: originPath,
    );
    expect(tab.session!.addBookmark('work in progress'), isTrue);
    final store = InMemoryUnsavedChangesStore();
    await store.write(
      UnsavedRecord(
        id: 'lost-1',
        title: title,
        length: tab.session!.bytes.length,
        originPath: originPath,
        savedLength: tab.savedLength,
      ),
      tab.session!.bytes,
    );
    tab.dispose();
    return store;
  }

  testWidgets('unsaved work from a lost run comes back, still unsaved',
      (tester) async {
    final store = await storeWithLostWork();

    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(prefs: prefs, unsavedChangesStore: store),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tabTitle('crashed.pdf'), findsOneWidget);
    expect(dirtyDot(), findsOneWidget,
        reason: 'the edits are recovered but still not written to the file');
    // And it says so, rather than silently resurrecting a document.
    expect(find.textContaining('Recovered unsaved changes'), findsOneWidget);
  });

  testWidgets('a recovered document still knows where it saves',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    // Wide enough for the shell to show its header Save button.
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    final store = await storeWithLostWork();
    var savedTo = '';
    Uint8List? savedBytes;

    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(
        prefs: prefs,
        unsavedChangesStore: store,
        saveDocumentToPath: (bytes, path, {String? bookmark}) async {
          savedTo = path;
          savedBytes = bytes;
          return SaveResult.saved(path);
        },
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // The shell's Save is live because the recovered document is dirty.
    await tester.tap(find.byKey(const ValueKey('pdf-shell-save')));
    await tester.pumpAndSettle();

    // Straight back to the file it was opened from - the interrupted save
    // finishes without a second thought from the user.
    expect(savedTo, '/docs/crashed.pdf');
    expect(savedBytes, isNotNull);
    expect(dirtyDot(), findsNothing);
    // And once it is on the user's own disk, the recovery copy is gone.
    expect(await store.list(), isEmpty);

    await tester.binding.setSurfaceSize(null);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('the recovered document wins over the same file in the session',
      (tester) async {
    final store = await storeWithLostWork();
    // The last session also listed the file; without the dedup the user would
    // get the same document twice, once with their edits and once without.
    SharedPreferences.setMockInitialValues({
      'dart_pdf_editor_app.session': jsonEncode([
        {'t': 'crashed.pdf', 'p': '/docs/crashed.pdf'}
      ]),
    });

    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(prefs: prefs, unsavedChangesStore: store),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tabTitle('crashed.pdf'), findsOneWidget);
    expect(dirtyDot(), findsOneWidget);
  });

  testWidgets('a clean launch shows nothing and says nothing', (tester) async {
    final store = InMemoryUnsavedChangesStore();

    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(prefs: prefs, unsavedChangesStore: store),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Recovered unsaved changes'), findsNothing);
    expect(tabTitle('crashed.pdf'), findsNothing);
  });

  /// The live edit session behind the one open tab.
  PdfEditingController sessionOf(WidgetTester tester) =>
      tester.widget<PdfViewer>(find.byType(PdfViewer).first).editing
          as PdfEditingController;

  testWidgets('backgrounding the app mirrors edits it has not written yet',
      (tester) async {
    final store = InMemoryUnsavedChangesStore();

    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(
        prefs: prefs,
        unsavedChangesStore: store,
        initialDocument: (bytes: buildClassicPdf(), title: 'live.pdf'),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final session = sessionOf(tester);
    expect(session.addBookmark('typed something'), isTrue);
    expect(await store.list(), isEmpty, reason: 'still inside the debounce');

    // On mobile and the web this callback can be the last one we get before
    // the process is reclaimed, so it must not wait the debounce out.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await tester.pump();

    final records = await store.list();
    expect(records, hasLength(1));
    expect(records.single.length, session.bytes.length);
  });

  testWidgets('discarding on quit does not offer the work back',
      (tester) async {
    final store = InMemoryUnsavedChangesStore();

    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(
        prefs: prefs,
        unsavedChangesStore: store,
        initialDocument: (bytes: buildClassicPdf(), title: 'live.pdf'),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(sessionOf(tester).addBookmark('typed something'), isTrue);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(await store.list(), hasLength(1));

    final exit = tester.binding.handleRequestAppExit();
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(await exit, ui.AppExitResponse.exit);
    // The user was asked and said throw it away - resurrecting it next launch
    // would be the app overruling them.
    expect(await store.list(), isEmpty);
  });

  testWidgets('editing a freshly opened document mirrors it', (tester) async {
    final store = InMemoryUnsavedChangesStore();

    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(
        prefs: prefs,
        unsavedChangesStore: store,
        initialDocument: (bytes: buildClassicPdf(), title: 'live.pdf'),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final state = tester.state(find.byType(EditorScreen));
    // Reach through the screen the way the editing UI does - any committed
    // revision has to reach the mirror.
    final session = tester
        .widget<PdfViewer>(find.byType(PdfViewer).first)
        .editing as PdfEditingController;
    expect(session.addBookmark('typed something'), isTrue);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(state.mounted, isTrue);

    final records = await store.list();
    expect(records, hasLength(1));
    expect(records.single.title, 'live.pdf');
    expect(records.single.length, session.bytes.length);
  });
}
