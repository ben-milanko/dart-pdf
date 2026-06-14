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

  // Right-clicks the tab labelled [name] to open its context menu.
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

  Future<void> openTabs(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
    await tester.pump();
    await openTab(tester, 'alpha.pdf');
    await openTab(tester, 'beta.pdf');
    await openTab(tester, 'gamma.pdf');
  }

  testWidgets('right-click opens the tab context menu', (tester) async {
    await openTabs(tester);

    await rightClickTab(tester, 'beta.pdf');

    expect(find.byKey(const ValueKey('tab-menu-close')), findsOneWidget);
    expect(find.byKey(const ValueKey('tab-menu-close-others')), findsOneWidget);
    expect(find.byKey(const ValueKey('tab-menu-close-right')), findsOneWidget);
    expect(find.byKey(const ValueKey('tab-menu-close-all')), findsOneWidget);
  });

  testWidgets('Close others leaves only the clicked tab', (tester) async {
    await openTabs(tester);

    await rightClickTab(tester, 'beta.pdf');
    await tester.tap(find.byKey(const ValueKey('tab-menu-close-others')));
    await tester.pumpAndSettle();

    expect(tabTitle('alpha.pdf'), findsNothing);
    expect(tabTitle('gamma.pdf'), findsNothing);
    expect(tabTitle('beta.pdf'), findsOneWidget);
    expect(find.byTooltip('Close tab'), findsOneWidget);
  });

  testWidgets('Close tabs to the right keeps the clicked tab and its left',
      (tester) async {
    await openTabs(tester);

    await rightClickTab(tester, 'beta.pdf');
    await tester.tap(find.byKey(const ValueKey('tab-menu-close-right')));
    await tester.pumpAndSettle();

    expect(tabTitle('alpha.pdf'), findsOneWidget);
    expect(tabTitle('beta.pdf'), findsOneWidget);
    expect(tabTitle('gamma.pdf'), findsNothing);
  });

  testWidgets('Close right is disabled on the rightmost tab', (tester) async {
    await openTabs(tester);

    await rightClickTab(tester, 'gamma.pdf');

    final item = tester.widget<PopupMenuItem<dynamic>>(
      find.byKey(const ValueKey('tab-menu-close-right')),
    );
    expect(item.enabled, isFalse);
  });

  testWidgets('Close all removes every tab', (tester) async {
    await openTabs(tester);

    await rightClickTab(tester, 'alpha.pdf');
    await tester.tap(find.byKey(const ValueKey('tab-menu-close-all')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('tab-strip')), findsNothing);
    expect(find.byTooltip('Close tab'), findsNothing);
  });

  testWidgets('Close on the active tab activates a surviving neighbour',
      (tester) async {
    await openTabs(tester);
    // gamma is active (last opened).

    await rightClickTab(tester, 'gamma.pdf');
    await tester.tap(find.byKey(const ValueKey('tab-menu-close')));
    await tester.pumpAndSettle();

    expect(tabTitle('gamma.pdf'), findsNothing);
    // beta is now the rightmost survivor and becomes active.
    expect(tester.widget<Text>(tabTitle('beta.pdf')).style?.fontWeight,
        FontWeight.w600);
  });
}
