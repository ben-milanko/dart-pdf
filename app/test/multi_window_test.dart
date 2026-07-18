import 'dart:convert';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/document_tab.dart';
import 'package:dart_pdf_editor_app/editor_screen.dart';
import 'package:dart_pdf_editor_app/incoming_file.dart';

// Multi-window is built on Flutter's experimental windowing feature, which is
// off in the test harness (and can't create real OS windows there). What we can
// pin down is the app-side wiring: the "New window" / "Move to new window"
// affordances appear exactly when the host provides EditorScreen.onNewWindow,
// the menu item and the ⇧⌘/Ctrl+Shift+N shortcut route to it with a live
// BuildContext, a moved tab hands off its document and is removed here, and an
// incoming handoff opens as a tab. The app (app.dart) only passes onNewWindow
// when `multiWindowSupported`, so hiding those affordances without a callback
// is what keeps released builds single-window.
void main() {
  late PdfEditingPreferences prefs;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    prefs = PdfEditingPreferences();
  });

  tearDown(() => prefs.dispose());

  Future<void> openAppMenu(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('dartpdf-app-menu')));
    await tester.pumpAndSettle();
  }

  // The tab title within the strip (scoped so it never matches the AppBar's
  // active-document title nor a body list).
  Finder tabTitle(String name) => find.descendant(
        of: find.byKey(const ValueKey('tab-strip')),
        matching: find.text(name),
      );

  Future<void> rightClickTab(WidgetTester tester, String name) async {
    final gesture = await tester.startGesture(
      tester.getCenter(tabTitle(name)),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  Future<void> pumpWithDocument(
    WidgetTester tester, {
    void Function(BuildContext, {DocumentHandoff? document})? onNewWindow,
    String title = 'doc.pdf',
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(
        prefs: prefs,
        onNewWindow: onNewWindow,
        initialDocument: (bytes: buildClassicPdf(), title: title),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  // --- "New window" (empty) -------------------------------------------------

  testWidgets('New window is hidden when no opener is wired', (tester) async {
    await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
    await tester.pump();

    await openAppMenu(tester);

    expect(find.byKey(const ValueKey('menu-new-document')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-new-window')), findsNothing);
  });

  testWidgets('New window menu item invokes the opener with a context',
      (tester) async {
    final contexts = <BuildContext>[];
    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(
        prefs: prefs,
        onNewWindow: (context, {document}) => contexts.add(context),
      ),
    ));
    await tester.pump();

    await openAppMenu(tester);

    final item = find.byKey(const ValueKey('menu-new-window'));
    expect(item, findsOneWidget);
    await tester.tap(item);
    await tester.pumpAndSettle();

    expect(contexts, hasLength(1));
    expect(contexts.single.mounted, isTrue);
  });

  testWidgets('Shift+Cmd+N opens a new window', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      var opened = 0;
      await pumpWithDocument(tester,
          onNewWindow: (_, {document}) => opened++);
      await tester.tap(find.byType(PdfViewer), kind: PointerDeviceKind.mouse);
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();

      expect(opened, 1);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Shift+Ctrl+N opens a new window', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      var opened = 0;
      await pumpWithDocument(tester,
          onNewWindow: (_, {document}) => opened++);
      await tester.tap(find.byType(PdfViewer), kind: PointerDeviceKind.mouse);
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(opened, 1);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  // --- "Move to new window" (tab tear-off) ----------------------------------

  testWidgets('Move to new window is hidden without an opener', (tester) async {
    await pumpWithDocument(tester);

    await rightClickTab(tester, 'doc.pdf');

    expect(find.byKey(const ValueKey('tab-menu-move-window')), findsNothing);
    expect(find.byKey(const ValueKey('tab-menu-close')), findsOneWidget);
  });

  testWidgets('Move to new window hands off the document and removes the tab',
      (tester) async {
    DocumentHandoff? moved;
    var calls = 0;
    await pumpWithDocument(
      tester,
      onNewWindow: (context, {document}) {
        calls++;
        moved = document;
      },
    );

    await rightClickTab(tester, 'doc.pdf');
    expect(find.byKey(const ValueKey('tab-menu-move-window')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tab-menu-move-window')));
    await tester.pumpAndSettle();

    // The document was handed off, carrying its title and bytes...
    expect(calls, 1);
    expect(moved, isNotNull);
    expect(moved!.title, 'doc.pdf');
    expect(moved!.bytes, isNotEmpty);
    // ...and the source tab is gone (back to the empty welcome state).
    expect(tabTitle('doc.pdf'), findsNothing);
  });

  testWidgets('a moved tab carries its file origin and dirty state',
      (tester) async {
    DocumentHandoff? moved;
    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(
        prefs: prefs,
        onNewWindow: (context, {document}) => moved = document,
      ),
    ));
    await tester.pump();

    // Open a file-backed document the way the OS would, then edit it so it's
    // dirty.
    const codec = StandardMethodCodec();
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      IncomingFileService.channelName,
      codec.encodeMethodCall(MethodCall('openFile', {
        'name': 'origin.pdf',
        'bytes': buildClassicPdf(),
        'path': '/docs/origin.pdf',
      })),
      (_) {},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final controller =
        tester.widget<PdfEditorView>(find.byType(PdfEditorView)).controller!;
    controller.addFreeText(0, const PdfRect(72, 650, 240, 700), 'edit');
    await tester.pump();

    await rightClickTab(tester, 'origin.pdf');
    await tester.tap(find.byKey(const ValueKey('tab-menu-move-window')));
    await tester.pumpAndSettle();

    expect(moved, isNotNull);
    expect(moved!.originPath, '/docs/origin.pdf');
    expect(moved!.dirty, isTrue);
  });

  testWidgets('initialHandoff opens the moved document as a tab',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(
        prefs: prefs,
        initialHandoff: DocumentHandoff(
          bytes: buildClassicPdf(),
          title: 'moved.pdf',
          originPath: '/docs/moved.pdf',
          dirty: true,
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tabTitle('moved.pdf'), findsOneWidget);
    // A dirty handoff opens dirty (Save targets the carried origin).
    final tab = tester.widget<PdfEditorView>(find.byType(PdfEditorView));
    expect(tab.controller, isNotNull);
  });

  // --- session isolation ----------------------------------------------------

  // Secondary multi-window instances pass persistSession: false so only the
  // primary window owns the single persisted session.
  testWidgets('persistSession: false leaves the stored session untouched',
      (tester) async {
    const sessionKey = 'dart_pdf_editor_app.session';
    final seed = jsonEncode([
      {'t': 'seed.pdf', 'p': '/seeded/seed.pdf'}
    ]);
    SharedPreferences.setMockInitialValues({sessionKey: seed});
    final store = await SharedPreferences.getInstance();

    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(prefs: prefs, persistSession: false),
    ));
    await tester.pump();

    const codec = StandardMethodCodec();
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      IncomingFileService.channelName,
      codec.encodeMethodCall(MethodCall('openFile', {
        'name': 'fresh.pdf',
        'bytes': buildClassicPdf(),
        'path': '/opened/fresh.pdf',
      })),
      (_) {},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(store.getString(sessionKey), seed);
  });
}
