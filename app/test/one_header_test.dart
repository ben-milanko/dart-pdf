// One header bar: over an editable document the editor draws the app bar
// (PdfEditorView.headerBuilder), and in read-only mode the reader does
// (PdfReader.headerBuilder) - never an app bar stacked over the shell's own.
// On a compact window the save/share button rides in that app bar and stays
// live without edits, but ⌘S / Ctrl+S saves only when there is something to
// save, as on desktop.

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/editor_screen.dart';
import 'package:dart_pdf_editor_app/file_io.dart';
import 'package:dart_pdf_editor_app/incoming_file.dart';

void main() {
  late PdfEditingPreferences prefs;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    prefs = PdfEditingPreferences();
  });
  tearDown(() => prefs.dispose());

  final appBar = find.byKey(const ValueKey('dartpdf-app-menu'));
  final save = find.byKey(const ValueKey('pdf-shell-save'));

  void setSize(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  // Opens a PDF the way the OS hands one over: a file the user already has,
  // so it starts clean (not new, not dirty).
  Future<void> openFile(WidgetTester tester) async {
    const codec = StandardMethodCodec();
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      IncomingFileService.channelName,
      codec.encodeMethodCall(MethodCall('openFile', {
        'name': 'report.pdf',
        'bytes': buildClassicPdf(),
      })),
      (_) {},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<List<Uint8List>> pumpWithFile(WidgetTester tester) async {
    final saved = <Uint8List>[];
    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(
        prefs: prefs,
        saveDocumentAs: (context, bytes, name) async {
          saved.add(bytes);
          return SaveResult.cancelled;
        },
        saveDocumentToPath: (bytes, path, {bookmark}) async {
          saved.add(bytes);
          return SaveResult.cancelled;
        },
      ),
    ));
    await tester.pump();
    await openFile(tester);
    return saved;
  }

  Future<void> pressSave(WidgetTester tester) async {
    // focus inside the editor, where its shortcuts listen
    await tester.tap(find.byType(PdfViewer), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
    for (final modifier in [
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.controlLeft,
    ]) {
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(modifier);
      await tester.pumpAndSettle();
    }
  }

  testWidgets('compact: ⌘S/Ctrl+S on an unedited file saves nothing',
      (tester) async {
    setSize(tester, const Size(390, 844));
    final saved = await pumpWithFile(tester);
    expect(save, findsOneWidget);
    // the app bar's save/share button stays live without edits...
    expect(tester.getSemantics(save), isSemantics(isEnabled: true));
    await pressSave(tester);
    // ...but the shortcut has nothing to save
    expect(saved, isEmpty);

    // pressing the button itself still saves (shares) the untouched file
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(saved, hasLength(1));
  });

  testWidgets('compact: ⌘S/Ctrl+S saves once there is an edit', (tester) async {
    setSize(tester, const Size(390, 844));
    final saved = await pumpWithFile(tester);
    tester
        .widget<PdfEditorView>(find.byType(PdfEditorView))
        .controller!
        .addBookmark('An edit');
    await tester.pump();
    await pressSave(tester);
    expect(saved, isNotEmpty);
  });

  testWidgets('wide: the save button waits for an edit', (tester) async {
    setSize(tester, const Size(1280, 800));
    final saved = await pumpWithFile(tester);
    expect(tester.getSemantics(save), isSemantics(isEnabled: false));
    await pressSave(tester);
    expect(saved, isEmpty);
  });

  for (final (name, size) in [
    ('wide', const Size(1280, 800)),
    ('compact', const Size(390, 844)),
  ]) {
    testWidgets('$name: read-only tabs draw one header, like editable ones',
        (tester) async {
      setSize(tester, size);
      await pumpWithFile(tester);
      expect(find.byType(PdfEditorView), findsOneWidget);
      expect(appBar, findsOneWidget);
      // the shell draws the app bar, not the Scaffold
      expect(find.descendant(of: find.byType(PdfEditorView), matching: appBar),
          findsOneWidget);

      await tester.tap(appBar);
      await tester.pumpAndSettle();
      final readOnly = find.byKey(const ValueKey('menu-read-only'));
      await tester.ensureVisible(readOnly);
      await tester.pumpAndSettle();
      await tester.tap(readOnly);
      await tester.pumpAndSettle();

      expect(find.byType(PdfReader), findsOneWidget);
      expect(appBar, findsOneWidget);
      expect(find.descendant(of: find.byType(PdfReader), matching: appBar),
          findsOneWidget);
      // the reader's own controls ride in the same bar; no save there
      expect(find.byType(PdfPageNumberField), findsOneWidget);
      expect(save, findsNothing);
    });
  }
}
