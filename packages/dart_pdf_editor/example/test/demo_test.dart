import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_viewer_example/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // the app opens the interactive demo on launch
  Future<void> openDemo(WidgetTester tester) async {
    // the mock store is process-global: start every test from defaults
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ViewerApp());
    await tester.pump();
  }

  /// Demo pages are 612×792pt and the viewer opens fit-page (the whole
  /// page visible, centered horizontally), so the on-screen page rect is
  /// derived from the viewer's own fit math — not assumed fit-width.
  Rect pageRect(WidgetTester tester) {
    final viewer = tester.getRect(find.byType(PdfViewer));
    const aspect = 792 / 612;
    final zoom = (viewer.height / (viewer.width * aspect)).clamp(0.0, 1.0);
    final width = viewer.width * zoom;
    return Rect.fromLTWH(viewer.left + (viewer.width - width) / 2, viewer.top,
        width, width * aspect);
  }

  /// Taps a point given in page 1's PDF coordinates.
  Future<void> tapOnPage(WidgetTester tester, double x, double y) async {
    final page = pageRect(tester);
    final s = page.width / 612;
    await tester.tapAt(page.topLeft + Offset(x * s, (792 - y) * s));
    // single taps wait out the competing double-tap recognizer
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 50));
  }

  // plain Text widgets only — find.text would also match the page-number
  // field's EditableText, whose value is '1' on page 1
  Finder plainText(String value) =>
      find.byWidgetPredicate((w) => w is Text && w.data == value);

  testWidgets('PDF link increments the Flutter counter badge', (tester) async {
    await openDemo(tester);
    expect(plainText('0'), findsOneWidget); // the badge overlay

    await tapOnPage(tester, 176, 618); // "Increment the counter" link
    expect(plainText('1'), findsOneWidget);

    await tapOnPage(tester, 176, 618);
    expect(plainText('2'), findsOneWidget);
  });

  testWidgets('PDF link shows an app message with its URI payload',
      (tester) async {
    await openDemo(tester);
    await tapOnPage(tester, 176, 558); // "Show a message" link
    await tester.pump(const Duration(milliseconds: 250)); // snackbar slides in
    expect(find.text('Hello from the PDF'), findsOneWidget);
  });

  testWidgets('GoTo link reaches the widgets page; overlays are live',
      (tester) async {
    await openDemo(tester);
    await tapOnPage(tester, 176, 498); // "Go to the widgets page" link
    // finish the scroll animation with plain pumps — the clock overlay's
    // periodic timer would keep pumpAndSettle from ever settling
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.byType(Switch), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    await tester.tap(find.byType(Switch));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

    // the counter control edits the same state the page-1 link increments
    // (.first: the page overlay's button — the AppBar tab strip's new-tab
    // '+' is also an Icons.add, and Scaffold mounts the body before the bar)
    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pump(const Duration(milliseconds: 400));
    expect(plainText('1'), findsWidgets);

    // the note field accepts input above the page (by key — the app bar
    // hosts TextFields of its own now)
    await tester.enterText(
        find.byKey(const ValueKey('demo-note')), 'typed over the PDF');
    expect(find.text('typed over the PDF'), findsOneWidget);

    // unmount so the clock's periodic timer is disposed before teardown
    await tester.pumpWidget(const SizedBox());
  });
}
