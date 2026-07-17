import 'dart:convert';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/editor_screen.dart';
import 'package:dart_pdf_editor_app/incoming_file.dart';

// Multi-window is built on Flutter's experimental windowing feature, which is
// off in the test harness (and can't create real OS windows there). What we can
// pin down is the app-side wiring: the "New window" affordance appears exactly
// when the host provides EditorScreen.onNewWindow, and both the menu item and
// the ⇧⌘/Ctrl+Shift+N shortcut route to it with a live BuildContext. The app
// (app.dart) only passes onNewWindow when `multiWindowSupported`, so hiding the
// item without a callback is what keeps released builds single-window.
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
      home: EditorScreen(prefs: prefs, onNewWindow: contexts.add),
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

  // The shortcut lives in the CallbackShortcuts above the editor, so a document
  // must be open and focused (tap the viewer) for the key event to bubble up -
  // the same recipe the Save shortcut tests use.
  Future<void> pumpWithDocument(
    WidgetTester tester, {
    required void Function(BuildContext) onNewWindow,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(
        prefs: prefs,
        onNewWindow: onNewWindow,
        initialDocument: (bytes: buildClassicPdf(), title: 'doc.pdf'),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byType(PdfViewer), kind: PointerDeviceKind.mouse);
    await tester.pump();
  }

  testWidgets('Shift+Cmd+N opens a new window', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      var opened = 0;
      await pumpWithDocument(tester, onNewWindow: (_) => opened++);

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
      await pumpWithDocument(tester, onNewWindow: (_) => opened++);

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

  // Secondary multi-window instances pass persistSession: false so only the
  // primary window owns the single persisted session. Proven by seeding a
  // stored session, then opening a document in a persistSession: false screen
  // (which would normally rewrite the store) and asserting the seed survives.
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

    // Open a document the way the OS would; a persisting screen would now
    // overwrite the stored session with this tab.
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
