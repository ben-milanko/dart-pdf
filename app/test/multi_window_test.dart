import 'dart:convert';

// This regression must inspect the same experimental internal feature gate
// that MaterialApp/showDialog read.
// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/src/foundation/_features.dart' show isWindowingEnabled;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/document_tab.dart';
import 'package:dart_pdf_editor_app/editor_screen.dart';
import 'package:dart_pdf_editor_app/incoming_file.dart';
import 'package:dart_pdf_editor_app/window_support.dart';

// flutter_test cannot create real desktop windows. These tests pin the public
// app-side seam instead: feature visibility, shortcuts, lossless handoff,
// failure safety, process-service isolation, and the native close handshake.
void main() {
  late PdfEditingPreferences prefs;

  test('desktop startup enables windowing by default before binding', () {
    final original = isWindowingEnabled;
    final originalPlatform = debugDefaultTargetPlatformOverride;
    try {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      isWindowingEnabled = false;
      expect(multiWindowSupported, isFalse);

      enableDartPdfWindowing();
      expect(multiWindowSupported, isTrue);

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      isWindowingEnabled = false;
      enableDartPdfWindowing();
      expect(isWindowingEnabled, isFalse);
    } finally {
      isWindowingEnabled = original;
      debugDefaultTargetPlatformOverride = originalPlatform;
    }
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    prefs = PdfEditingPreferences();
  });

  tearDown(() => prefs.dispose());

  Future<void> openAppMenu(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('dartpdf-app-menu')));
    await tester.pumpAndSettle();
  }

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
    bool Function(BuildContext, {DocumentHandoff? document})? onNewWindow,
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

  testWidgets('window commands stay hidden without a native opener',
      (tester) async {
    await pumpWithDocument(tester);

    await openAppMenu(tester);
    expect(find.byKey(const ValueKey('menu-new-window')), findsNothing);
    await tester.tapAt(const Offset(700, 500));
    await tester.pumpAndSettle();

    await rightClickTab(tester, 'doc.pdf');
    expect(find.byKey(const ValueKey('tab-menu-move-window')), findsNothing);
    expect(find.byKey(const ValueKey('tab-menu-close')), findsOneWidget);
  });

  testWidgets('New window menu and shortcut invoke the native opener',
      (tester) async {
    var opened = 0;
    await pumpWithDocument(
      tester,
      onNewWindow: (_, {document}) {
        expect(document, isNull);
        opened++;
        return true;
      },
    );

    await openAppMenu(tester);
    await tester.tap(find.byKey(const ValueKey('menu-new-window')));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PdfViewer), kind: PointerDeviceKind.mouse);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(opened, 2);
  });

  testWidgets('failed window creation keeps the source tab', (tester) async {
    await pumpWithDocument(
      tester,
      onNewWindow: (_, {document}) => false,
    );

    await rightClickTab(tester, 'doc.pdf');
    await tester.tap(find.byKey(const ValueKey('tab-menu-move-window')));
    await tester.pumpAndSettle();

    expect(tabTitle('doc.pdf'), findsOneWidget);
    expect(find.text('Couldn’t open a new window'), findsOneWidget);
  });

  testWidgets('move hands off exact bytes, baseline and file origin',
      (tester) async {
    DocumentHandoff? moved;
    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(
        prefs: prefs,
        onNewWindow: (_, {document}) {
          moved = document;
          return true;
        },
      ),
    ));
    await tester.pump();

    const codec = StandardMethodCodec();
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      IncomingFileService.channelName,
      codec.encodeMethodCall(MethodCall('openFile', {
        'name': 'origin.pdf',
        'bytes': buildClassicPdf(),
        'path': '/docs/origin.pdf',
        'bookmark': 'bookmark-data',
      })),
      (_) {},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final controller =
        tester.widget<PdfEditorView>(find.byType(PdfEditorView)).controller!;
    final savedLength = controller.bytes.length;
    controller.addFreeText(0, const PdfRect(72, 650, 240, 700), 'edit');
    await tester.pump();

    await rightClickTab(tester, 'origin.pdf');
    await tester.tap(find.byKey(const ValueKey('tab-menu-move-window')));
    await tester.pumpAndSettle();

    expect(moved, isNotNull);
    expect(moved!.title, 'origin.pdf');
    expect(moved!.savedLength, savedLength);
    expect(moved!.bytes.length, greaterThan(savedLength));
    expect(moved!.isDirty, isTrue);
    expect(moved!.originPath, '/docs/origin.pdf');
    expect(moved!.originBookmark, 'bookmark-data');
    expect(tabTitle('origin.pdf'), findsNothing);
  });

  testWidgets('initial handoff preserves dirty state in its new window',
      (tester) async {
    final original = buildClassicPdf();
    final edited = PdfEditingController(original);
    edited.addFreeText(0, const PdfRect(72, 650, 240, 700), 'edit');
    final bytes = Uint8List.fromList(edited.bytes);
    edited.dispose();

    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(
        prefs: prefs,
        initialHandoff: DocumentHandoff(
          bytes: bytes,
          title: 'moved.pdf',
          savedLength: original.length,
          originPath: '/docs/moved.pdf',
        ),
        ownsApplicationSession: false,
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tabTitle('moved.pdf'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('tab-strip')),
        matching: find.byIcon(Icons.circle),
      ),
      findsOneWidget,
    );
  });

  testWidgets('secondary window does not replace the persisted app session',
      (tester) async {
    const sessionKey = 'dart_pdf_editor_app.session';
    final seed = jsonEncode([
      {'t': 'seed.pdf', 'p': '/seeded/seed.pdf'}
    ]);
    SharedPreferences.setMockInitialValues({sessionKey: seed});
    final store = await SharedPreferences.getInstance();
    final bytes = buildClassicPdf();

    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(
        prefs: prefs,
        initialHandoff: DocumentHandoff(
          bytes: bytes,
          title: 'secondary.pdf',
          savedLength: bytes.length,
        ),
        ownsApplicationSession: false,
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tabTitle('secondary.pdf'), findsOneWidget);
    expect(store.getString(sessionKey), seed);
  });

  testWidgets('native close waits for unsaved-changes confirmation',
      (tester) async {
    final coordinator = DartPdfWindowCloseCoordinator();
    final bytes = buildClassicPdf();
    await tester.pumpWidget(DartPdfWindowCloseScope(
      coordinator: coordinator,
      child: MaterialApp(
        home: EditorScreen(
          prefs: prefs,
          initialHandoff: DocumentHandoff(
            bytes: bytes,
            title: 'dirty.pdf',
            savedLength: bytes.length - 1,
          ),
          ownsApplicationSession: false,
        ),
      ),
    ));
    await tester.pump();

    final cancelled = coordinator.requestClose();
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await cancelled, isFalse);

    final approved = coordinator.requestClose();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(await approved, isTrue);
  });
}
