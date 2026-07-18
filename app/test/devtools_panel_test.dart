// The F12 developer tools panel: opens via F12, shows the metric sections,
// hosts the deep-zoom detail mode switch (#314), and captures logs. The panel
// exists in debug/profile builds only; tests run in debug, so it's available.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor_app/devtools.dart';
import 'package:dart_pdf_editor_app/editor_screen.dart';

void main() {
  late PdfEditingPreferences prefs;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    prefs = PdfEditingPreferences();
  });
  tearDown(() {
    prefs.dispose();
    // Reset the statics the mode switch flips so tests stay independent.
    PdfPageView.tileStoreDetail = false;
    PdfPageView.debugTileStoreOverride = null;
  });

  Future<void> pumpWithDoc(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(
        prefs: prefs,
        initialDocument: (bytes: buildClassicPdf(), title: 'Report.pdf'),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('F12 toggles the panel; sections and session info render',
      (tester) async {
    await pumpWithDoc(tester);
    expect(find.byKey(const ValueKey('devtools-panel')), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.f12);
    await tester.pump();
    expect(find.byKey(const ValueKey('devtools-panel')), findsOneWidget);
    expect(find.text('Frames'), findsOneWidget);
    expect(find.text('Memory'), findsOneWidget);
    expect(find.text('Deep-zoom detail (#314)'), findsOneWidget);
    expect(find.text('Session'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.f12);
    await tester.pump();
    expect(find.byKey(const ValueKey('devtools-panel')), findsNothing);
  });

  testWidgets('the deep-zoom mode switch flips the tile path statics',
      (tester) async {
    await pumpWithDoc(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.f12);
    await tester.pump();

    expect(PdfPageView.tileStoreDetail, isFalse);

    Future<void> tapMode(String mode) async {
      final finder = find.byKey(ValueKey('devtools-mode-$mode'));
      await tester.ensureVisible(finder);
      await tester.pump();
      await tester.tap(finder);
      await tester.pump();
    }

    await tapMode('tiles (batched)');
    expect(PdfPageView.tileStoreDetail, isTrue);
    expect(PdfPageView.debugTileStoreOverride, isNotNull);
    expect(PdfPageView.debugTileStoreOverride!.batchRasters, isTrue);

    await tapMode('tiles (per-tile)');
    expect(PdfPageView.debugTileStoreOverride!.batchRasters, isFalse);

    await tapMode('patch');
    expect(PdfPageView.tileStoreDetail, isFalse);
    expect(PdfPageView.debugTileStoreOverride, isNull);
  });

  testWidgets('captured logs appear and the filter narrows them',
      (tester) async {
    AppDevTools.instance.addLog('devtools-test: alpha entry');
    AppDevTools.instance.addLog('devtools-test: beta entry');
    await pumpWithDoc(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.f12);
    await tester.pump();

    await tester.ensureVisible(
        find.byKey(const ValueKey('devtools-log-filter')));
    await tester.pump();
    expect(find.textContaining('alpha entry'), findsOneWidget);
    expect(find.textContaining('beta entry'), findsOneWidget);

    await tester.enterText(
        find.byKey(const ValueKey('devtools-log-filter')), 'alpha');
    await tester.pump();
    expect(find.textContaining('alpha entry'), findsOneWidget);
    expect(find.textContaining('beta entry'), findsNothing);
  });

  testWidgets('Settings offers Developer tools and it opens the panel',
      (tester) async {
    await pumpWithDoc(tester);
    await tester.tap(find.byTooltip('DartPDF menu'));
    await tester.pumpAndSettle();
    // With a document open the menu is taller than the test surface.
    await tester.ensureVisible(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    final tile = find.byKey(const ValueKey('settings-devtools'));
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('devtools-panel')), findsOneWidget);
  });
}
