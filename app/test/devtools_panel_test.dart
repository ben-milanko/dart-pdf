// The F12 developer tools panel: opens via F12, shows the metric sections,
// hosts the deep-zoom detail mode switch (#314), and captures logs. The panel
// exists in debug/profile builds only; tests run in debug, so it's available.
import 'package:flutter/gestures.dart';
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
    // Touch logging is a process-global singleton; reset it (and the viewer
    // sink it installs) so it never leaks into another test.
    AppDevTools.instance.logTouchInput = false;
    AppDevTools.instance.localeOverride.value = null;
    AppDevTools.instance.clearLog();
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

  testWidgets('the Locale section sets a testing override', (tester) async {
    await pumpWithDoc(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.f12);
    await tester.pump();

    expect(AppDevTools.instance.localeOverride.value, isNull);

    final dropdown = find.byKey(const ValueKey('devtools-locale-dropdown'));
    await tester.ensureVisible(dropdown);
    await tester.pump();
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    // Pick Arabic (RTL) from the opened menu.
    await tester.tap(find.text('العربية (Arabic) — RTL').last);
    await tester.pumpAndSettle();

    expect(AppDevTools.instance.localeOverride.value, const Locale('ar'));
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

  testWidgets('touch input logging captures a drag as down/up summaries',
      (tester) async {
    await pumpWithDoc(tester);
    // The toggle installs the viewer gesture sink and starts pointer capture.
    AppDevTools.instance.logTouchInput = true;
    expect(pdfDebugGestureLog, isNotNull);

    // A touch drag over the viewer body, routed through the passive Listener.
    final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PdfViewer)),
        kind: PointerDeviceKind.touch);
    for (var i = 0; i < 5; i++) {
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump(const Duration(milliseconds: 8));
    }
    await gesture.up();
    await tester.pump();

    final messages = AppDevTools.instance.log.map((e) => e.message).toList();
    expect(messages.any((m) => m.startsWith('touch: DOWN')), isTrue,
        reason: 'a touch-down summary should be logged');
    expect(
        messages.any((m) =>
            m.startsWith('touch: UP') && m.contains('moves=')),
        isTrue,
        reason: 'a touch-up summary with a move count should be logged');

    // Turning it off tears the viewer sink back down.
    AppDevTools.instance.logTouchInput = false;
    expect(pdfDebugGestureLog, isNull);
  });

  testWidgets('devtools rides up as a bottom sheet on a phone-width screen',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpWithDoc(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.f12);
    await tester.pump();

    final panel = find.byKey(const ValueKey('devtools-panel'));
    expect(panel, findsOneWidget);
    // The sheet supplies its own close button (the docked frame's is absent in
    // bottom-sheet mode) and anchors to the bottom of the screen.
    expect(find.byKey(const ValueKey('devtools-close')), findsOneWidget);
    final box = tester.getRect(panel);
    expect(box.bottom, moreOrLessEquals(844, epsilon: 1),
        reason: 'the sheet hugs the bottom edge');
    expect(box.top, greaterThan(844 * 0.3),
        reason: 'the sheet is a partial-height card, not full screen');
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
