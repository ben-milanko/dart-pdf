// Live sync in the app: the menu turns it on for a document opened from a
// folder, the header chip shows whether it is working and who else is in
// the document, another person's annotation lands in the open editor, Save
// syncs instead of overwriting, page edits are refused with a reason, and
// the chip's dialog stops it.

import 'dart:async';
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor_app/document_tab.dart';
import 'package:dart_pdf_editor_app/editor_screen.dart';
import 'package:dart_pdf_editor_app/file_io.dart';
import 'package:dart_pdf_editor_app/live_sync.dart';
import 'package:dart_pdf_editor_app/unsaved_changes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryBackend extends LiveSyncBackend {
  _MemoryBackend(this.store);

  final PdfSyncStore store;
  final requested = <String>[];

  @override
  PdfSyncStore? storeFor(String path) {
    requested.add(path);
    return store;
  }

  @override
  String get deviceName => 'Test Mac';
}

Uint8List seeded() => (PdfEditor(PdfDocument.open(buildMultiPagePdf(2)))
      ..addSquare(0, const PdfRect(100, 600, 200, 680),
          strokeColor: 0x000000, name: 'shared-1'))
    .save();

void main() {
  late PdfEditingPreferences prefs;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    prefs = PdfEditingPreferences();
  });
  tearDown(() => prefs.dispose());

  testWidgets('start, see a colleague and their annotation, save, stop',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bytes = seeded();
    final store = PdfMemorySyncStore();
    final backend = _MemoryBackend(store);
    final written = <Uint8List>[];
    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(
        prefs: prefs,
        unsavedChangesStore: InMemoryUnsavedChangesStore(),
        liveSyncBackend: backend,
        initialHandoff: DocumentHandoff(
          bytes: bytes,
          title: 'Plan.pdf',
          savedLength: bytes.length,
          originPath: '/Users/ben/OneDrive - Acme/Plan.pdf',
        ),
        saveDocumentToPath: (bytes, path, {bookmark}) async {
          written.add(bytes);
          return SaveResult.saved(path);
        },
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    PdfEditingController editing() =>
        tester.widget<PdfEditorView>(find.byType(PdfEditorView)).controller!;

    // Turn it on from the app menu.
    await tester.tap(find.byTooltip('DartPDF menu'));
    await tester.pumpAndSettle();
    final start = find.byKey(const ValueKey('menu-live-sync'));
    await tester.ensureVisible(start);
    await tester.pumpAndSettle();
    expect(find.text('Start live sync (experimental)'), findsOneWidget);
    await tester.tap(start);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(backend.requested, ['/Users/ben/OneDrive - Acme/Plan.pdf']);
    final chip = find.byKey(const ValueKey('live-sync-chip'));
    expect(chip, findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(
        find.descendant(of: chip, matching: find.text('Live')), findsOneWidget);

    // A colleague opens the same PDF from the same folder.
    final alice = PdfSyncSession(
      bytes: bytes,
      transport: PdfSharedFolderSyncTransport(
        store: store,
        sessionId: 'walice',
        flushDelay: Duration.zero,
        presenceInfo: const {'name': 'Alice Chen', 'device': 'ALICE-PC'},
      ),
    );
    final aliceFolder = alice.transport as PdfSharedFolderSyncTransport;
    await aliceFolder.poll();
    for (var i = 0;
        i < 10 &&
            find
                .descendant(of: chip, matching: find.text('AC'))
                .evaluate()
                .isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    await tester.pump(const Duration(milliseconds: 300)); // toast slides in
    expect(find.descendant(of: chip, matching: find.text('AC')), findsOneWidget,
        reason: 'her initials appear on the chip');
    expect(find.text('Alice Chen joined'), findsOneWidget);

    // She adds a note; it shows up in the open document.
    alice.apply((e) => e.addNote(0, 60, 60, 'Check this', name: 'alice-note'),
        pages: [0]);
    await aliceFolder.flush();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    expect(editing().findAnnotationByName('alice-note'), isNotNull);

    // Our rectangle reaches her.
    editing().addRectangle(1, const PdfRect(300, 300, 360, 360));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    await aliceFolder.poll();
    expect(alice.annotationDigest(), hasLength(3));

    // Page edits are refused, with a reason.
    editing().removePage(1);
    await tester.pump();
    expect(editing().document.pageCount, 2);
    expect(
        find.text('Adding, removing and reordering pages is off while '
            'live sync is on.'),
        findsOneWidget);

    // Save syncs rather than overwriting the shared PDF.
    await tester.tap(find.byKey(const ValueKey('pdf-shell-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Changes synced. The shared PDF updates automatically.'),
        findsOneWidget);

    // The dialog behind the chip lists everyone and stops sync.
    await tester.tap(chip);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('live-sync-details')), findsOneWidget);
    expect(find.text('Test Mac (you)'), findsOneWidget);
    expect(find.text('Alice Chen'), findsOneWidget);
    expect(find.text('ALICE-PC'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('live-sync-stop')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(chip, findsNothing);
    expect(editing().pageStructureLocked, isFalse);

    aliceFolder.close();
    unawaited(alice.dispose());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a document with no folder says why it cannot sync',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(
        prefs: prefs,
        unsavedChangesStore: InMemoryUnsavedChangesStore(),
        liveSyncBackend: _MemoryBackend(PdfMemorySyncStore()),
        initialDocument: (bytes: seeded(), title: 'Untitled.pdf'),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byTooltip('DartPDF menu'));
    await tester.pumpAndSettle();
    final start = find.byKey(const ValueKey('menu-live-sync'));
    await tester.ensureVisible(start);
    await tester.pumpAndSettle();
    await tester.tap(start);
    await tester.pump();
    expect(find.textContaining('Live sync needs a PDF saved in a folder'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('live-sync-chip')), findsNothing);
    await tester.pump(const Duration(seconds: 6));
  });
}
