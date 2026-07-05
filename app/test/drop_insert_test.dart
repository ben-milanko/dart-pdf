import 'dart:async';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/editor_screen.dart';
import 'package:dart_pdf_editor_app/incoming_file.dart';

// These tests exercise the *branching* a drop takes — show the open/insert
// dialog when a document is open, and route to the right action — by driving
// the desktop_drop channel directly. They deliberately do not read real files:
// the bytes a dropped item carries are read lazily through dart:io, whose
// futures never complete under the widget tester's fake clock (and the read is
// triggered from a UI tap, so it can't be wrapped in runAsync either). The
// actual page copy is covered by the editor package's insertPagesFrom* tests;
// here we assert the synchronous effects each branch produces.
void main() {
  late PdfEditingPreferences prefs;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    prefs = PdfEditingPreferences();
  });

  tearDown(() => prefs.dispose());

  // Delivers a PDF to the running app the way the OS would (a warm-start
  // "open with"), opening it in a new tab.
  Future<void> openTab(WidgetTester tester, String name, Uint8List bytes) async {
    const codec = StandardMethodCodec();
    final message = codec.encodeMethodCall(
      MethodCall('openFile', {'name': name, 'bytes': bytes}),
    );
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      IncomingFileService.channelName,
      message,
      (_) {},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  // Drives the desktop_drop channel the way the Linux platform side does when
  // a file is dropped on the window. Only a path is delivered — the bytes are
  // read lazily later — so no real file is needed to exercise the drop's
  // branching (show the action dialog / add a loading tab). The drop point is
  // the centre of the surface so it lands inside the editor body (DropTarget
  // only reports a done event for in-bounds drops). Send an update first so
  // the target is entered even when the test runs on a non-Linux host.
  Future<void> dropPdf(WidgetTester tester, String name) async {
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    const codec = StandardMethodCodec();
    final point = <double>[size.width / 2, size.height / 2];
    final update = codec.encodeMethodCall(MethodCall('updated', point));
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'desktop_drop',
      update,
      (_) {},
    );
    await tester.pump();
    final message = codec.encodeMethodCall(
      MethodCall('performOperation_linux', <dynamic>[
        Uri.file('/dartpdf-test/$name').toString(),
        point,
      ]),
    );
    unawaited(
      tester.binding.defaultBinaryMessenger
          .handlePlatformMessage('desktop_drop', message, (_) {}),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Finder tabTitle(String name) => find.descendant(
        of: find.byKey(const ValueKey('tab-strip')),
        matching: find.text(name),
      );

  testWidgets('dropping onto an open document offers open or insert',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
    await tester.pump();
    await openTab(tester, 'base.pdf', buildMultiPagePdf(2));

    await dropPdf(tester, 'extra.pdf');

    expect(find.byKey(const ValueKey('drop-action-dialog')), findsOneWidget);
    expect(find.byKey(const ValueKey('drop-action-insert')), findsOneWidget);
    expect(find.byKey(const ValueKey('drop-action-open')), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('choosing insert keeps a single document (no new tab)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
    await tester.pump();
    await openTab(tester, 'base.pdf', buildMultiPagePdf(2));

    await dropPdf(tester, 'extra.pdf');
    await tester.tap(find.byKey(const ValueKey('drop-action-insert')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350)); // dialog dismiss

    // Insert merges into the open document rather than opening a tab.
    expect(find.byKey(const ValueKey('drop-action-dialog')), findsNothing);
    expect(tabTitle('extra.pdf'), findsNothing);
    expect(tabTitle('base.pdf'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('choosing open adds the dropped PDF as a new tab',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
    await tester.pump();
    await openTab(tester, 'base.pdf', buildMultiPagePdf(2));

    await dropPdf(tester, 'extra.pdf');
    await tester.tap(find.byKey(const ValueKey('drop-action-open')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350)); // dialog dismiss

    expect(find.byKey(const ValueKey('drop-action-dialog')), findsNothing);
    expect(tabTitle('extra.pdf'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('dropping with nothing open skips the prompt and opens a tab',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
    await tester.pump();

    await dropPdf(tester, 'lonely.pdf');

    expect(find.byKey(const ValueKey('drop-action-dialog')), findsNothing);
    expect(tabTitle('lonely.pdf'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
