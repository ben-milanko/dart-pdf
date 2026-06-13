import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_viewer_example/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> openDemo(WidgetTester tester) async {
    // the mock store is process-global: start every test from defaults
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ViewerApp());
    await tester.pump();
  }

  // each open document carries one 'Close tab' button in the strip
  Finder closeButtons() => find.byTooltip('Close tab');

  testWidgets('app launches with a single document tab', (tester) async {
    await openDemo(tester);
    expect(closeButtons(), findsOneWidget);
    expect(find.byType(PdfViewer), findsOneWidget);
  });

  testWidgets('the AppBar demo action opens a second tab', (tester) async {
    await openDemo(tester);
    await tester.tap(find.byTooltip('Open the interactive demo in a new tab'));
    await tester.pump();

    // two tabs now, but still exactly one mounted viewer (only the active
    // tab is rendered)
    expect(closeButtons(), findsNWidgets(2));
    expect(find.byType(PdfViewer), findsOneWidget);
  });

  testWidgets('closing a tab drops it and keeps another active',
      (tester) async {
    await openDemo(tester);
    await tester.tap(find.byTooltip('Open the interactive demo in a new tab'));
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

    // no tabs, no strip, no viewer — just the empty-state buttons
    expect(closeButtons(), findsNothing);
    expect(find.byType(PdfViewer), findsNothing);
    expect(find.text('Open a PDF'), findsOneWidget);
    expect(find.text('Try the interactive demo'), findsOneWidget);
  });

  testWidgets('the More menu offers comparing against another PDF',
      (tester) async {
    await openDemo(tester);
    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    expect(find.text('Compare with another PDF…'), findsOneWidget);
  });
}
