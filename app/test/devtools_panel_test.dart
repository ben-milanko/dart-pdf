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
import 'package:dart_pdf_editor_app/devtools_panel.dart';
import 'package:dart_pdf_editor_app/editor_screen.dart';

void main() {
  late PdfEditingPreferences prefs;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    prefs = PdfEditingPreferences();
    AppDevTools.instance.setPageRasterCachePolicy(
      const PdfPageRasterCachePolicy(),
    );
    AppDevTools.instance.updateAutoPageRasterCache(
      const PdfPageRasterCachePolicy(),
      reason: 'test machine headroom',
      safeProcessLimitBytes: 2 * 1024 * 1024 * 1024,
    );
    AppDevTools.instance.useAutoPageRasterCache();
    AppDevTools.instance.setGpuTileBudgets(
      maxTextureBytes: 256 << 20,
      maxGeometryBytes: 256 << 20,
    );
    AppDevTools.instance.setGpuOverprintApproximation(false);
    AppDevTools.instance
        .setTileRasterBackendMode(TileRasterBackendMode.flutterGpu);
    AppDevTools.instance.flutterGpuTileRasterBackend.stats.reset();
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
    AppDevTools.instance.setPageRasterCachePolicy(
      const PdfPageRasterCachePolicy(),
    );
    AppDevTools.instance.updateAutoPageRasterCache(
      const PdfPageRasterCachePolicy(),
      reason: 'test reset',
    );
    AppDevTools.instance.useAutoPageRasterCache();
    AppDevTools.instance.setGpuTileBudgets(
      maxTextureBytes: 256 << 20,
      maxGeometryBytes: 256 << 20,
    );
    AppDevTools.instance.setGpuOverprintApproximation(false);
    AppDevTools.instance
        .setTileRasterBackendMode(TileRasterBackendMode.flutterGpu);
    AppDevTools.instance.flutterGpuTileRasterBackend.stats.reset();
    AppDevTools.instance.clearLog();
  });

  test('diagnostics identify the exact compiled revision', () {
    final identity = devToolsBuildIdentity();

    expect(identity, containsPair('appVersion', isNotEmpty));
    expect(identity, contains('appBuild'));
    expect(identity, containsPair('buildCommit', isNotEmpty));
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
    expect(find.text('Tile raster backend'), findsOneWidget);
    expect(find.text('Session'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.f12);
    await tester.pump();
    expect(find.byKey(const ValueKey('devtools-panel')), findsNothing);
  });

  testWidgets('the render route overlay toggles from the panel',
      (tester) async {
    addTearDown(() => pdfDebugShowGpuRasterRoutes.value = false);
    await pumpWithDoc(tester);
    expect(find.byKey(const ValueKey('pdf-gpu-route-overlay')), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.f12);
    await tester.pump();
    final toggle = find.byKey(const ValueKey('devtools-gpu-route-overlay'));
    await tester.ensureVisible(toggle);
    await tester.pump();
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(pdfDebugShowGpuRasterRoutes.value, isTrue);
    expect(find.byKey(const ValueKey('pdf-gpu-route-overlay')),
        findsAtLeastNWidgets(1));
  });

  testWidgets('tile backend switch updates the mounted viewer in place',
      (tester) async {
    await pumpWithDoc(tester);
    final tools = AppDevTools.instance;
    expect(
      tester.widget<PdfViewer>(find.byType(PdfViewer)).tileRasterBackend,
      same(tools.flutterGpuTileRasterBackend),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.f12);
    await tester.pump();
    final selector = find.byKey(const ValueKey('devtools-tile-backend'));
    await tester.ensureVisible(selector);
    await tester.pump();
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Canvas').last);
    await tester.pumpAndSettle();

    expect(tools.tileRasterBackendMode.value, TileRasterBackendMode.canvas);
    expect(
      tester.widget<PdfViewer>(find.byType(PdfViewer)).tileRasterBackend,
      isA<PdfCanvasTileRasterBackend>(),
    );

    await tester.ensureVisible(selector);
    await tester.pump();
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('flutter_gpu').last);
    await tester.pumpAndSettle();
    expect(
      tester.widget<PdfViewer>(find.byType(PdfViewer)).tileRasterBackend,
      same(tools.flutterGpuTileRasterBackend),
    );

    final oldBackend = tools.flutterGpuTileRasterBackend;
    final textureBudget =
        find.byKey(const ValueKey('devtools-gpu-texture-budget'));
    await tester.ensureVisible(textureBudget);
    await tester.pump();
    await tester.tap(textureBudget);
    await tester.pumpAndSettle();
    await tester.tap(find.text('512 MB').last);
    await tester.pumpAndSettle();
    expect(tools.flutterGpuTileRasterBackend, isNot(same(oldBackend)));
    expect(tools.flutterGpuTileRasterBackend.maxTextureBytes, 512 << 20);
    expect(
      tester.widget<PdfViewer>(find.byType(PdfViewer)).tileRasterBackend,
      same(tools.flutterGpuTileRasterBackend),
      reason: 'budget changes replace the selected backend live',
    );

    final budgetedBackend = tools.flutterGpuTileRasterBackend;
    final overprint =
        find.byKey(const ValueKey('devtools-gpu-overprint-approximation'));
    await tester.ensureVisible(overprint);
    await tester.pump();
    await tester.tap(overprint);
    await tester.pumpAndSettle();
    expect(tools.gpuOverprintApproximation, isTrue);
    expect(tools.flutterGpuTileRasterBackend, isNot(same(budgetedBackend)));
    expect(
        tools.flutterGpuTileRasterBackend.allowOverprintApproximation, isTrue);
    expect(
      tester.widget<PdfViewer>(find.byType(PdfViewer)).tileRasterBackend,
      same(tools.flutterGpuTileRasterBackend),
      reason: 'correctness experiment changes retire live GPU sessions',
    );
  });

  testWidgets('GPU diagnostics distinguish acceptance and fallback',
      (tester) async {
    AppDevTools.instance.setDeepZoomMode(AppDevTools.modeBatched);
    final stats = AppDevTools.instance.flutterGpuTileRasterBackend.stats
      ..sessionsCreated = 2
      ..sessionsRejected = 1
      ..rasterFallbacks = 1
      ..scenesCompiled = 2
      ..compileMicros = 8000
      ..tilesRendered = 4
      ..selectedCommands = 40
      ..issueMicros = 4000
      ..submitMicros = 2000
      ..completedSubmissions = 3
      ..completionMicros = 18000
      ..maxCompletionMicros = 9000
      ..inFlightSubmissions = 1
      ..lastTileRoute = 'canvas-fallback'
      ..lastRejection = 'unsupported blend mode';
    addTearDown(stats.reset);

    await pumpWithDoc(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.f12);
    await tester.pump();
    final selector = find.byKey(const ValueKey('devtools-tile-backend'));
    await tester.ensureVisible(selector);
    await tester.pump();

    expect(find.text('2 accepted / 1 rejected / 1 runtime fallback'),
        findsOneWidget);
    expect(find.text('unsupported blend mode'), findsOneWidget);
    expect(find.text('Canvas fallback'), findsOneWidget);
    expect(find.textContaining('10.0 commands/tile'), findsOneWidget);
    expect(find.textContaining('9.0 ms worst'), findsOneWidget);
    expect(find.textContaining('1 in flight'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('devtools-reset-gpu-stats')), findsOneWidget);
  });

  testWidgets('web preview advertises every native GPU download',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DevToolsPanel(
          onClose: () {},
          gpuPreviewDownloads: const {
            'macOS': '/downloads/dartpdf-macos-gpu-preview.dmg',
            'Windows': '/downloads/dartpdf-windows-gpu-preview.zip',
            'Linux': '/downloads/dartpdf-linux-gpu-preview.tar.gz',
          },
        ),
      ),
    ));
    await tester.pump();

    expect(find.byKey(const ValueKey('devtools-download-gpu-macos')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('devtools-download-gpu-windows')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('devtools-download-gpu-linux')),
        findsOneWidget);
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

  testWidgets('the idle raster warm selector applies live', (tester) async {
    await pumpWithDoc(tester);
    addTearDown(() => AppDevTools.instance
        .setPageRasterWarmPolicy(const PdfPageRasterWarmPolicy.disabled()));
    await tester.sendKeyEvent(LogicalKeyboardKey.f12);
    await tester.pump();

    final warm = find.byKey(const ValueKey('devtools-page-raster-warm'));
    await tester.ensureVisible(warm);
    await tester.pump();
    expect(find.text('Off'), findsWidgets,
        reason: 'no background full-raster work until asked for');

    await tester.tap(warm);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Whole document').last);
    await tester.pumpAndSettle();
    expect(AppDevTools.instance.pageRasterWarmPolicy.value.mode,
        PdfPageRasterWarmMode.document);
    expect(
      tester.widget<PdfViewer>(find.byType(PdfViewer)).pageRasterWarmPolicy,
      const PdfPageRasterWarmPolicy.document(),
      reason: 'the open viewer receives the policy without being reopened',
    );

    await tester.ensureVisible(warm);
    await tester.pump();
    await tester.tap(warm);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nearby +/-2').last);
    await tester.pumpAndSettle();
    expect(AppDevTools.instance.pageRasterWarmPolicy.value,
        const PdfPageRasterWarmPolicy.nearby(window: 2));
  });

  testWidgets('visited-page raster limits apply live from the memory section',
      (tester) async {
    await pumpWithDoc(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.f12);
    await tester.pump();

    final total = find.byKey(const ValueKey('devtools-page-raster-budget'));
    await tester.ensureVisible(total);
    await tester.pump();
    await tester.tap(total);
    await tester.pumpAndSettle();
    await tester.tap(find.text('5 GB').last);
    await tester.pumpAndSettle();
    expect(
      AppDevTools.instance.pageRasterCachePolicy.value,
      const PdfPageRasterCachePolicy(
        maxBytes: 5 * 1024 * 1024 * 1024,
        maxEntryBytes: 256 * 1024 * 1024,
      ),
      reason: 'entering fixed mode must not retain the dormant 16 MB default',
    );

    final perPage =
        find.byKey(const ValueKey('devtools-page-raster-entry-budget'));
    await tester.ensureVisible(perPage);
    await tester.pump();
    await tester.tap(perPage);
    await tester.pumpAndSettle();
    await tester.tap(find.text('128 MB').last);
    await tester.pumpAndSettle();

    const expected = PdfPageRasterCachePolicy(
      maxBytes: 5 * 1024 * 1024 * 1024,
      maxEntryBytes: 128 * 1024 * 1024,
    );
    expect(AppDevTools.instance.pageRasterCachePolicy.value, expected);
    expect(
      tester.widget<PdfViewer>(find.byType(PdfViewer)).pageRasterCachePolicy,
      expected,
      reason: 'the open viewer receives the policy without being reopened',
    );

    await tester.ensureVisible(total);
    await tester.pump();
    await tester.tap(total);
    await tester.pumpAndSettle();
    await tester.tap(find.text('2 GB').last);
    await tester.pumpAndSettle();
    expect(
      AppDevTools.instance.pageRasterCachePolicy.value.maxEntryBytes,
      128 * 1024 * 1024,
      reason: 'fixed-to-fixed total changes preserve an explicit page limit',
    );

    await tester.ensureVisible(total);
    await tester.pump();
    await tester.tap(total);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Auto (recommended)').last);
    await tester.pumpAndSettle();
    expect(AppDevTools.instance.pageRasterCacheMode, PageRasterCacheMode.auto);
    expect(
      find.byKey(const ValueKey('devtools-page-raster-entry-budget')),
      findsNothing,
      reason: 'Auto owns the derived per-page admission limit',
    );

    await tester.ensureVisible(total);
    await tester.tap(total);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Off').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(total);
    await tester.tap(total);
    await tester.pumpAndSettle();
    await tester.tap(find.text('5 GB').last);
    await tester.pumpAndSettle();
    expect(
      AppDevTools.instance.pageRasterCachePolicy.value.maxEntryBytes,
      256 * 1024 * 1024,
      reason: 'moving from Off to a fixed budget reseeds page admission',
    );
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

    await tester
        .ensureVisible(find.byKey(const ValueKey('devtools-log-filter')));
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
        messages.any((m) => m.startsWith('touch: UP') && m.contains('moves=')),
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
