import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart'
    as fs;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/editor_screen.dart';
import 'package:dart_pdf_editor_app/incoming_file.dart';
import 'package:dart_pdf_editor_app/session_store.dart';
import 'package:dart_pdf_editor_app/unsaved_changes.dart';
import 'package:dart_pdf_editor_app/welcome_screen.dart';

class _FakeFileSelector extends fs.FileSelectorPlatform {
  _FakeFileSelector(this.files);

  final List<fs.XFile> files;
  bool openedMultiple = false;

  @override
  Future<List<fs.XFile>> openFiles({
    List<fs.XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    openedMultiple = true;
    return files;
  }
}

class _DelayedRecoveryStore extends InMemoryUnsavedChangesStore {
  final gate = Completer<List<UnsavedRecord>>();

  @override
  Future<List<UnsavedRecord>> list() => gate.future;
}

void main() {
  late PdfEditingPreferences prefs;
  late Directory tempDir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    prefs = PdfEditingPreferences();
    tempDir = Directory.systemTemp.createTempSync('dartpdf_session_test');
  });

  tearDown(() {
    prefs.dispose();
    tempDir.deleteSync(recursive: true);
  });

  // Writes a real PDF on disk so restore can read it back through the same
  // path-based opener the desktop file pickers use.
  String seedFile(String name) {
    final path = '${tempDir.path}/$name';
    File(path).writeAsBytesSync(Uint8List.fromList(buildClassicPdf()));
    return path;
  }

  void seedSession(List<({String title, String path})> docs) {
    SharedPreferences.setMockInitialValues({
      'dart_pdf_editor_app.session': jsonEncode([
        for (final d in docs) {'t': d.title, 'p': d.path}
      ]),
    });
  }

  // A mobile pick has no durable path; the session tracks its private byte
  // snapshot ('c') instead. Reuse a real on-disk file as that snapshot so
  // restore can read it back through the same path-based opener.
  void seedCacheSession(List<({String title, String cachePath})> docs) {
    SharedPreferences.setMockInitialValues({
      'dart_pdf_editor_app.session': jsonEncode([
        for (final d in docs) {'t': d.title, 'p': '', 'c': d.cachePath}
      ]),
    });
  }

  Finder tabTitle(String name) => find.descendant(
        of: find.byKey(const ValueKey('tab-strip')),
        matching: find.text(name),
      );

  // The editor never settles (it keeps rasterizing), and restore performs real
  // file I/O - which only progresses under runAsync. Pump a handful of real
  // frames so each read can complete and swap its loading placeholder.
  Future<void> pumpEditor(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();
  }

  // Real frames: restore and the progressive opener both do file I/O, which
  // only progresses under runAsync.
  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  // Hands the app a file the way a native runner does - the macOS
  // `application(_:open:)` payload is a path (plus a security bookmark), no
  // bytes. Call inside runAsync.
  Future<void> deliverOpenFile(WidgetTester tester,
      {required String name, required String path}) async {
    const codec = StandardMethodCodec();
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      IncomingFileService.channelName,
      codec.encodeMethodCall(MethodCall('openFile', {
        'name': name,
        'path': path,
      })),
      (_) {},
    );
  }

  testWidgets('re-opens the documents from the last session on startup',
      (tester) async {
    final a = seedFile('a.pdf');
    final b = seedFile('b.pdf');
    seedSession([(title: 'a.pdf', path: a), (title: 'b.pdf', path: b)]);

    await pumpEditor(tester);

    expect(tabTitle('a.pdf'), findsOneWidget);
    expect(tabTitle('b.pdf'), findsOneWidget);
  });

  testWidgets('does not start recent thumbnails during transient restore frame',
      (tester) async {
    final restored = seedFile('restored.pdf');
    final recent = seedFile('recent.pdf');
    SharedPreferences.setMockInitialValues({
      'dart_pdf_editor_app.session': jsonEncode([
        {'t': 'restored.pdf', 'p': restored}
      ]),
      'dart_pdf_editor_app.recents': jsonEncode([
        {
          't': 'recent.pdf',
          'p': recent,
          'o': DateTime.now().millisecondsSinceEpoch,
        }
      ]),
    });
    final recovery = _DelayedRecoveryStore();

    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(prefs: prefs, unsavedChangesStore: recovery),
    ));
    await tester.pump();

    // Recents may already be visible, but their expensive renderer stays
    // detached until session restore has decided there is no document to show.
    final welcome = tester.widget<WelcomeScreen>(find.byType(WelcomeScreen));
    expect(welcome.thumbnails, isNull);

    recovery.gate.complete(const []);
    await tester.runAsync(() async {
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();

    expect(find.byType(WelcomeScreen), findsNothing);
    expect(tabTitle('restored.pdf'), findsOneWidget);
  });

  testWidgets('restores a mobile document from its private snapshot',
      (tester) async {
    // No reusable path (mobile), only a cached copy of the bytes.
    final snapshot = seedFile('snapshot.pdf');
    seedCacheSession([(title: 'shared.pdf', cachePath: snapshot)]);

    await pumpEditor(tester);

    expect(tabTitle('shared.pdf'), findsOneWidget);
  });

  testWidgets('drops a session document whose file is gone, no error tab',
      (tester) async {
    seedSession([(title: 'missing.pdf', path: '${tempDir.path}/missing.pdf')]);

    await pumpEditor(tester);

    // Nothing opened - we land back on the welcome screen, no error placeholder.
    expect(tabTitle('missing.pdf'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Open a PDF'), findsOneWidget);
  });

  testWidgets('skips restore when launched to open a specific document',
      (tester) async {
    final a = seedFile('a.pdf');
    seedSession([(title: 'a.pdf', path: a)]);

    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        home: EditorScreen(
          prefs: prefs,
          initialDocument: (
            bytes: Uint8List.fromList(buildClassicPdf()),
            title: 'launched.pdf',
          ),
        ),
      ));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();

    expect(tabTitle('launched.pdf'), findsOneWidget);
    expect(tabTitle('a.pdf'), findsNothing);
  });

  testWidgets('records the open documents so the next launch can restore them',
      (tester) async {
    // Start with no prior session, then open a file-backed document the way the
    // OS hands one over. The open set should be persisted for next time.
    final path = '${tempDir.path}/opened.pdf';
    await pumpEditor(tester); // empty session: enables persistence

    const codec = StandardMethodCodec();
    final message = codec.encodeMethodCall(MethodCall('openFile', {
      'name': 'opened.pdf',
      'bytes': buildClassicPdf(),
      'path': path,
      'bookmark': 'bookmark-data',
    }));
    await tester.runAsync(() async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        IncomingFileService.channelName,
        message,
        (_) {},
      );
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();

    expect(tabTitle('opened.pdf'), findsOneWidget);
    final persisted = await SessionStore().load();
    expect(persisted.map((d) => d.path), [path]);
    expect(persisted.map((d) => d.bookmark), ['bookmark-data']);
  });

  testWidgets('Open button opens every PDF selected in the picker',
      (tester) async {
    final a = seedFile('picker-a.pdf');
    final b = seedFile('picker-b.pdf');
    await pumpEditor(tester);

    final original = fs.FileSelectorPlatform.instance;
    final fake = _FakeFileSelector([fs.XFile(a), fs.XFile(b)]);
    fs.FileSelectorPlatform.instance = fake;
    addTearDown(() => fs.FileSelectorPlatform.instance = original);

    await tester.tap(find.widgetWithText(FilledButton, 'Open a PDF'));
    await tester.runAsync(() async {
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();

    expect(fake.openedMultiple, isTrue);
    expect(tabTitle('picker-a.pdf'), findsOneWidget);
    expect(tabTitle('picker-b.pdf'), findsOneWidget);
  });

  testWidgets('a restored tab left unparsed opens when it is activated',
      (tester) async {
    // Two-document session: the last restored tab is active and parsed; the
    // first is deferred (its bytes held, not yet opened). Activating it must
    // materialize a working editor - proving deferral doesn't strand a tab.
    final a = seedFile('a.pdf');
    final b = seedFile('b.pdf');
    seedSession([(title: 'a.pdf', path: a), (title: 'b.pdf', path: b)]);

    await pumpEditor(tester);
    expect(tabTitle('a.pdf'), findsOneWidget);
    expect(tabTitle('b.pdf'), findsOneWidget);

    // Switch to the deferred tab; it should parse on demand, not error out.
    await tester.runAsync(() async {
      await tester.tap(tabTitle('a.pdf'));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();

    expect(find.textContaining('Could not open'), findsNothing);
    expect(tabTitle('a.pdf'), findsOneWidget);
    expect(find.byType(PdfEditorView), findsOneWidget);
  });

  testWidgets('an OS file-open beats session restore to the end of the strip',
      (tester) async {
    final a = seedFile('a.pdf');
    final b = seedFile('b.pdf');
    seedSession([(title: 'a.pdf', path: a), (title: 'b.pdf', path: b)]);
    final clicked = seedFile('clicked.pdf');
    // Hold restore at its first await so the OS file-open lands first. That is
    // the macOS "open with" shape: the runner builds its payload off the
    // AppKit thread and pushes it whenever it is ready, which can be before
    // the stored session has even been read back.
    final recovery = _DelayedRecoveryStore();

    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        home: EditorScreen(prefs: prefs, unsavedChangesStore: recovery),
      ));
      await tester.pump();
      await deliverOpenFile(tester, name: 'clicked.pdf', path: clicked);
      await pumpFrames(tester);
      recovery.gate.complete(const []);
      await pumpFrames(tester);
    });
    await tester.pump();

    expect(tabTitle('a.pdf'), findsOneWidget);
    expect(tabTitle('b.pdf'), findsOneWidget);
    // The restored session slots in ahead of the clicked document, which keeps
    // the end of the strip...
    expect(tester.getCenter(tabTitle('a.pdf')).dx,
        lessThan(tester.getCenter(tabTitle('b.pdf')).dx));
    expect(tester.getCenter(tabTitle('b.pdf')).dx,
        lessThan(tester.getCenter(tabTitle('clicked.pdf')).dx));
    // ...and stays the document on screen.
    expect(tester.widget<Text>(tabTitle('clicked.pdf')).style?.fontWeight,
        FontWeight.w600);
    expect(tester.widget<Text>(tabTitle('b.pdf')).style?.fontWeight,
        FontWeight.normal);
  });

  testWidgets('an OS file-open of an already-restored document moves it last',
      (tester) async {
    final a = seedFile('a.pdf');
    final b = seedFile('b.pdf');
    seedSession([(title: 'a.pdf', path: a), (title: 'b.pdf', path: b)]);

    // Restore runs to completion first, then the OS hands over one of the very
    // files it just restored. Focusing it in place would leave it buried
    // mid-strip - the same double-click has to land the same way whichever
    // side wins the race.
    await pumpEditor(tester);
    await tester.runAsync(() async {
      await deliverOpenFile(tester, name: 'a.pdf', path: a);
      await pumpFrames(tester);
    });
    await tester.pump();

    expect(find.byTooltip('Close tab'), findsNWidgets(2)); // no duplicate tab
    expect(tester.getCenter(tabTitle('b.pdf')).dx,
        lessThan(tester.getCenter(tabTitle('a.pdf')).dx));
    expect(tester.widget<Text>(tabTitle('a.pdf')).style?.fontWeight,
        FontWeight.w600);
  });
}
