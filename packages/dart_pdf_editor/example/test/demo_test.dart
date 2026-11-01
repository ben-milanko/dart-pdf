import 'package:material_ui/material_ui.dart';
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
    // use-deferred-loading makes the localizations delegate load
    // asynchronously, so the app subtree - and the post-frame demo open -
    // only appear after the deferred unit resolves over several frames.
    // pumpAndSettle can't be used (the open demo runs a periodic clock timer
    // that never settles), so pump a bounded number of frames until the demo
    // viewer is up.
    for (var i = 0; i < 20 && find.byType(PdfViewer).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Demo pages are 612×792pt and the viewer opens fit-page (the whole
  /// page visible, centered horizontally), so the on-screen page rect is
  /// derived from the viewer's own fit math - not assumed fit-width.
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

  // plain Text widgets only - find.text would also match the page-number
  // field's EditableText, whose value is '1' on page 1
  Finder plainText(String value) =>
      find.byWidgetPredicate((w) => w is Text && w.data == value);

  testWidgets('mobile editor survives a negative native keyboard inset',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(402, 874);
    tester.view.viewPadding = const FakeViewPadding(top: 62, bottom: 34);
    tester.view.padding = const FakeViewPadding(top: 62, bottom: 34);
    addTearDown(tester.view.reset);
    await openDemo(tester);
    await tester.pump(const Duration(milliseconds: 350));

    final pageField = find.byKey(const ValueKey('pdf-page-number-field'));
    await tester.enterText(pageField, '6');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pump(const Duration(milliseconds: 350));
    final viewer = tester.widget<PdfViewer>(find.byType(PdfViewer)).controller!;
    expect(viewer.currentPage, 5);

    // The engine derives padding as max(0, viewPadding - viewInsets).
    // An invalid negative keyboard inset must not turn the dock's safe area
    // into millions of pixels and squeeze the actual PDF out of the screen.
    tester.view.viewInsets = const FakeViewPadding(bottom: -10000000);
    tester.view.padding = const FakeViewPadding(top: 62, bottom: 10000034);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(PdfViewer)).height, greaterThan(300));
    expect(
        tester.getSize(find.byType(PdfEditingToolbar)).height, lessThan(200));

    // A real keyboard still resizes the app. Recovery restores navigation
    // through the same page-number text field, not a controller shortcut.
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    tester.view.padding = const FakeViewPadding(top: 62);
    await tester.pump();
    expect(tester.takeException(), isNull);
    final keyboardHeight = tester.getSize(find.byType(PdfViewer)).height;
    tester.view.viewInsets = const FakeViewPadding();
    tester.view.padding = const FakeViewPadding(top: 62, bottom: 34);
    await tester.pump();
    expect(tester.getSize(find.byType(PdfViewer)).height,
        greaterThan(keyboardHeight));
    await tester.enterText(pageField, '4');
    expect(tester.widget<TextField>(pageField).controller!.text, '4');
    expect(tester.widget<TextField>(pageField).focusNode!.hasFocus, isTrue);
    await tester.testTextInput.receiveAction(TextInputAction.go);
    for (var i = 0; i < 60 && viewer.currentPage != 3; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(viewer.currentPage, 3);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

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
    // finish the scroll animation with plain pumps - the clock overlay's
    // periodic timer would keep pumpAndSettle from ever settling
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    final toggle = find.byKey(const ValueKey('demo-overlay-switch'));
    expect(toggle, findsOneWidget);
    expect(tester.getSemantics(toggle), isSemantics(isToggled: false));
    await tester.tap(toggle);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getSemantics(toggle), isSemantics(isToggled: true));

    // the counter control edits the same state the page-1 link increments
    // (.first: the page overlay's button - the AppBar tab strip's new-tab
    // '+' is also an Icons.add, and Scaffold mounts the body before the bar)
    await tester.tap(find.descendant(
      of: find.byType(PdfViewer),
      matching: find.byIcon(Icons.add),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    expect(plainText('1'), findsWidgets);

    // the note field accepts input above the page (by key - the app bar
    // hosts TextFields of its own now)
    await tester.enterText(
        find.byKey(const ValueKey('demo-note')), 'typed over the PDF');
    expect(find.text('typed over the PDF'), findsOneWidget);

    // unmount so the clock's periodic timer is disposed before teardown
    await tester.pumpWidget(const SizedBox());
  });
}
