import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/editor_screen.dart';
import 'package:dart_pdf_editor_app/incoming_file.dart';

void main() {
  late PdfEditingPreferences prefs;

  setUp(() {
    // The mock store is process-global; reset it so a prior test's persisted
    // preferences never leak into this one.
    SharedPreferences.setMockInitialValues({});
    prefs = PdfEditingPreferences();
  });

  tearDown(() => prefs.dispose());

  // Delivers a PDF to the running app the way the OS would (a warm-start
  // "open with"), opening it in a new tab.
  Future<void> openTab(WidgetTester tester, String name) async {
    const codec = StandardMethodCodec();
    final message = codec.encodeMethodCall(
      MethodCall('openFile', {'name': name, 'bytes': buildClassicPdf()}),
    );
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      IncomingFileService.channelName,
      message,
      (_) {},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  // The tab title within the strip (scoped to the tab-strip ReorderableListView
  // so it never matches the AppBar's active-document title nor the thumbnail
  // sidebar's own reorderable list in the body).
  Finder tabTitle(String name) => find.descendant(
        of: find.byKey(const ValueKey('tab-strip')),
        matching: find.text(name),
      );

  testWidgets('tabs render in a reorderable strip', (tester) async {
    await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
    await tester.pump();

    await openTab(tester, 'alpha.pdf');
    await openTab(tester, 'beta.pdf');

    expect(find.byKey(const ValueKey('tab-strip')), findsOneWidget);
    expect(tabTitle('alpha.pdf'), findsOneWidget);
    expect(tabTitle('beta.pdf'), findsOneWidget);
  });

  testWidgets('dragging a tab reorders it and keeps the active document',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
    await tester.pump();

    await openTab(tester, 'alpha.pdf');
    await openTab(tester, 'beta.pdf');

    // Opened in order, so alpha sits left of beta. The last-opened (beta) is
    // active — the AppBar title reflects it.
    expect(tester.getCenter(tabTitle('alpha.pdf')).dx,
        lessThan(tester.getCenter(tabTitle('beta.pdf')).dx));

    // Drag alpha to the right, past beta. A mouse drag reorders immediately
    // (touch would need a long press, per _TabDragStartListener).
    final gesture = await tester.startGesture(
      tester.getCenter(tabTitle('alpha.pdf')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(); // register the drag recognizer on pointer-down
    await gesture.moveBy(const Offset(30, 0)); // exceed slop → drag starts
    await tester.pump(const Duration(milliseconds: 50));
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(25, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump();
    // Let the drop animation finish (the proxy overlay clears).
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));

    // alpha is now to the right of beta.
    expect(tester.getCenter(tabTitle('alpha.pdf')).dx,
        greaterThan(tester.getCenter(tabTitle('beta.pdf')).dx));

    // Both tabs survive and beta is still the active document (its tab keeps
    // the selected weight while alpha reverts to normal).
    expect(find.byTooltip('Close tab'), findsNWidgets(2));
    expect(tester.widget<Text>(tabTitle('beta.pdf')).style?.fontWeight,
        FontWeight.w600);
    expect(tester.widget<Text>(tabTitle('alpha.pdf')).style?.fontWeight,
        FontWeight.normal);
  });
}
