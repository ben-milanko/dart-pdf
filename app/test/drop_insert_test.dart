import 'dart:async';
import 'dart:io';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/editor_screen.dart';
import 'package:dart_pdf_editor_app/incoming_file.dart';

// These tests exercise the *branching* a drop takes - show the open/insert
// dialog when a document is open, and route to the right action - by driving
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
  // a file is dropped on the window. Only a path is delivered - the bytes are
  // read lazily later - so no real file is needed to exercise the drop's
  // branching (show the action dialog / add a loading tab). The drop point is
  // the centre of the surface so it lands inside the editor body (DropTarget
  // only reports a done event for in-bounds drops). Send an update first so
  // the target is entered even when the test runs on a non-Linux host.
  Future<void> dropPdf(WidgetTester tester, String name, {Offset? at}) async {
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    const codec = StandardMethodCodec();
    final point = <double>[
      at?.dx ?? size.width / 2,
      at?.dy ?? size.height / 2,
    ];
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

  // The desktop layout the docked thumbnail strip needs (it collapses on a
  // compact surface).
  void wideScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  // A point in the upper (or lower) part of the strip's tile for [page] -
  // the halves either side of the tile's middle are the slots before and
  // after that page.
  Offset inStripTile(WidgetTester tester, int page, double fraction) {
    final tile = find.descendant(
      of: find.byType(PdfThumbnailSidebar),
      matching: find.byKey(ValueKey(page)),
    );
    final rect = tester.getRect(tile);
    return Offset(rect.center.dx, rect.top + rect.height * fraction);
  }

  testWidgets('a drag over the thumbnail strip marks the insertion slot',
      (tester) async {
    wideScreen(tester);
    await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
    await tester.pump();
    await openTab(tester, 'base.pdf', buildMultiPagePdf(3));

    const codec = StandardMethodCodec();
    Future<void> dragTo(Offset point) async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'desktop_drop',
        codec.encodeMethodCall(
            MethodCall('updated', <double>[point.dx, point.dy])),
        (_) {},
      );
      await tester.pump();
    }

    await dragTo(inStripTile(tester, 1, 0.25));

    // the strip marks the slot before page 2 ...
    expect(find.byKey(const ValueKey('pdf-thumbnail-drop-indicator-1-top')),
        findsOneWidget);
    // ... and the full-window "drop to open or insert" hint stands aside
    expect(find.text('Drop PDF to open or insert'), findsNothing);

    // dragging back over the page area restores the window-wide hint and
    // clears the strip's marker
    await dragTo(const Offset(1000, 450));
    expect(find.text('Drop PDF to open or insert'), findsOneWidget);
    expect(find.byKey(const ValueKey('pdf-thumbnail-drop-indicator-1-top')),
        findsNothing);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('dropping onto the thumbnail strip inserts without asking',
      (tester) async {
    wideScreen(tester);
    await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
    await tester.pump();
    await openTab(tester, 'base.pdf', buildMultiPagePdf(2));

    await dropPdf(tester, 'extra.pdf', at: inStripTile(tester, 0, 0.25));

    // The drop point already said where the pages go, so no open/insert
    // dialog - and no new tab, since this is an insert into the open file.
    expect(find.byKey(const ValueKey('drop-action-dialog')), findsNothing);
    expect(tabTitle('extra.pdf'), findsNothing);
    expect(tabTitle('base.pdf'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 60)));

  // The one drop test that reads a real file: it needs the *result* of the
  // insert, not just the branch. The read is a dart:io future, so both the
  // write and the drop delivery run inside runAsync (a real event loop) -
  // possible here only because this path takes no UI tap, unlike the
  // open/insert dialog above.
  testWidgets('a drop on the strip merges the file into the open document',
      (tester) async {
    wideScreen(tester);
    await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
    await tester.pump();
    await openTab(tester, 'base.pdf', buildMultiPagePdf(2));

    Finder stripTile(int page) => find.descendant(
          of: find.byType(PdfThumbnailSidebar),
          matching: find.byKey(ValueKey(page)),
        );
    expect(stripTile(1), findsOneWidget);
    expect(stripTile(2), findsNothing); // two pages so far

    final point = inStripTile(tester, 0, 0.25); // the slot before page 1
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('dartpdf-drop');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/extra.pdf');
      await file.writeAsBytes(buildMultiPagePdf(2));
      const codec = StandardMethodCodec();
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'desktop_drop',
        codec.encodeMethodCall(MethodCall('performOperation_linux', <dynamic>[
          Uri.file(file.path).toString(),
          <double>[point.dx, point.dy],
        ])),
        (_) {},
      );
      // let the lazy byte read and the insert it feeds actually land
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // the dropped file's two pages joined the document (4 tiles now), with
    // no dialog and no second tab
    expect(stripTile(3), findsOneWidget);
    expect(find.byKey(const ValueKey('drop-action-dialog')), findsNothing);
    expect(tabTitle('extra.pdf'), findsNothing);
    // settle the insert toast so no timer outlives the test
    await tester.pump(const Duration(seconds: 6));
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
