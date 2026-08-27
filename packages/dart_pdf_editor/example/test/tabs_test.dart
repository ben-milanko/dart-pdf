import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:pdf_viewer_example/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> openDemo(WidgetTester tester) async {
    // the mock store is process-global: start every test from defaults
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ViewerApp());
    // use-deferred-loading makes the localizations delegate load async; settle
    // so the localized app (and its post-frame demo open) builds.
    await tester.pumpAndSettle();
  }

  // each open document carries one 'Close tab' button in the strip
  Finder closeButtons() => find.byTooltip('Close tab');

  testWidgets('app launches with a single document tab', (tester) async {
    await openDemo(tester);
    expect(closeButtons(), findsOneWidget);
    expect(find.byType(PdfViewer), findsOneWidget);
  });

  testWidgets('tab strip is left aligned and app logo is compact',
      (tester) async {
    await openDemo(tester);

    expect(tester.getTopLeft(find.byKey(const ValueKey('tab-strip'))).dx,
        lessThan(120));

    final logo = find.descendant(
      of: find.byKey(const ValueKey('dartpdf-app-menu')),
      matching: find.byType(Image),
    );
    expect(tester.getSize(logo), const Size(24, 24));
  });

  testWidgets('the AppBar demo action opens a second tab', (tester) async {
    await openDemo(tester);
    await tester.tap(find.byTooltip('DartPDF menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open the interactive demo'));
    await tester.pump();

    // two tabs now, but still exactly one mounted viewer (only the active
    // tab is rendered)
    expect(closeButtons(), findsNWidgets(2));
    expect(find.byType(PdfViewer), findsOneWidget);
  });

  testWidgets('closing a tab drops it and keeps another active',
      (tester) async {
    await openDemo(tester);
    await tester.tap(find.byTooltip('DartPDF menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open the interactive demo'));
    await tester.pump();
    expect(closeButtons(), findsNWidgets(2));

    await tester.tap(closeButtons().last);
    await tester.pump();
    // the post-frame controller teardown runs; pump it through
    await tester.pump(const Duration(milliseconds: 400));

    expect(closeButtons(), findsOneWidget);
    expect(find.byType(PdfViewer), findsOneWidget);
  });

  testWidgets('closing the last tab shows the open prompt', (tester) async {
    await openDemo(tester);
    await tester.tap(closeButtons());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // no tabs, no strip, no viewer - just the empty-state buttons
    expect(closeButtons(), findsNothing);
    expect(find.byType(PdfViewer), findsNothing);
    expect(find.text('Open a PDF'), findsOneWidget);
    expect(find.text('Try the interactive demo'), findsOneWidget);
  });

  testWidgets('the More menu offers comparing against another PDF',
      (tester) async {
    await openDemo(tester);
    await tester.tap(find.byTooltip('DartPDF menu'));
    await tester.pumpAndSettle();
    expect(find.text('Compare with another PDF…'), findsOneWidget);
  });

  testWidgets('the app menu toggles the GPU rendering devtool', (tester) async {
    pdfDebugShowGpuRasterRoutes.value = false;
    addTearDown(() => pdfDebugShowGpuRasterRoutes.value = false);
    await openDemo(tester);

    await tester.tap(find.byTooltip('DartPDF menu'));
    await tester.pumpAndSettle();
    final devtool = find.byKey(
      const ValueKey('dartpdf-gpu-route-devtool'),
    );
    await tester.ensureVisible(devtool);
    await tester.pumpAndSettle();
    await tester.tap(devtool);
    await tester.pump();

    expect(pdfDebugShowGpuRasterRoutes.value, isTrue);
    expect(find.byKey(const ValueKey('pdf-gpu-route-overlay')), findsWidgets);
    expect(find.text('Detail tiles: not active'), findsWidgets);
  });

  testWidgets('performance menu switches between Auto and fixed workers',
      (tester) async {
    await openDemo(tester);
    final menu = find.byKey(const ValueKey('dartpdf-worker-pool-menu'));
    expect(menu, findsOneWidget);
    expect(find.byTooltip('Performance: Auto'), findsOneWidget);

    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dartpdf-worker-pool-off')));
    await tester.pump();
    expect(find.byTooltip('Performance: single worker'), findsOneWidget);

    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dartpdf-worker-pool-4')));
    await tester.pump();
    expect(find.byTooltip('Performance: 4 workers'), findsOneWidget);

    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dartpdf-worker-pool-auto')));
    await tester.pump();
    expect(find.byTooltip('Performance: Auto'), findsOneWidget);
  });
}
