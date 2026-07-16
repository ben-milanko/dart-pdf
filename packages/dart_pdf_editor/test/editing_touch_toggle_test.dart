import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The toolbar's finger-draws toggle only governs what TOUCH pointers do,
// so it hides until touch input is in play: always shown on touch-first
// platforms, revealed elsewhere by the first touch pointer the viewer or
// toolbar sees (Ben: "the control is still shown on non-touch displays").
void main() {
  Future<PdfEditingController> pumpEditor(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final editing = PdfEditingController(buildMultiPagePdf(1));
    final viewer = PdfViewerController();
    addTearDown(editing.dispose);
    addTearDown(viewer.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: editing,
          builder: (context, _) => PdfViewer(
            initialFit: PdfViewerFit.width,
            document: editing.document,
            controller: viewer,
            editing: editing,
          ),
        ),
        bottomNavigationBar:
            PdfEditingToolbar(controller: editing, viewerController: viewer),
      ),
    ));
    await tester.pump();
    return editing;
  }

  /// Pumps out the viewer's double-tap timer a touch gesture leaves.
  Future<void> settle(WidgetTester tester) =>
      tester.pump(const Duration(milliseconds: 400));

  test('hasTouchInput: platform default, and noteTouchInput notifies', () {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final editing = PdfEditingController(buildMultiPagePdf(1));
    addTearDown(editing.dispose);
    expect(editing.hasTouchInput, isFalse);

    var notified = 0;
    editing.addListener(() => notified++);
    editing.noteTouchInput();
    expect(editing.hasTouchInput, isTrue);
    expect(notified, 1);
    editing.noteTouchInput(); // idempotent - no second notify
    expect(notified, 1);

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final mobile = PdfEditingController(buildMultiPagePdf(1));
    addTearDown(mobile.dispose);
    expect(mobile.hasTouchInput, isTrue,
        reason: 'touch-first platforms never hide touch chrome');
  });

  testWidgets('the toggle shows with ink armed on a touch-first platform',
      (tester) async {
    // flutter_test's default platform is android, i.e. touch-first
    final editing = await pumpEditor(tester);
    expect(find.byIcon(Icons.touch_app), findsNothing);
    editing.tool = PdfEditTool.ink;
    await tester.pump();
    expect(find.byIcon(Icons.touch_app), findsOneWidget);
  });

  testWidgets('hidden on desktop until the viewer is touched',
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
      (tester) async {
    final editing = await pumpEditor(tester);
    editing.tool = PdfEditTool.ink;
    await tester.pump();
    expect(find.byIcon(Icons.touch_app), findsNothing);

    // a mouse click reveals nothing
    editing.tool = null; // ink would treat the press as a stroke
    await tester.pump();
    await tester.tapAt(const Offset(400, 300), kind: PointerDeviceKind.mouse);
    editing.tool = PdfEditTool.ink;
    await tester.pump();
    expect(find.byIcon(Icons.touch_app), findsNothing);

    // the first touch on the page does - in reader mode, so the tap
    // isn't an ink dot (whose auto-commit timer would outlive the test)
    editing.tool = null;
    await tester.pump();
    final gesture = await tester.startGesture(const Offset(400, 300));
    await gesture.up();
    await settle(tester);
    editing.tool = PdfEditTool.ink;
    await tester.pump();
    expect(find.byIcon(Icons.touch_app), findsOneWidget);
  });

  testWidgets('a touch on the toolbar itself reveals it',
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
      (tester) async {
    final editing = await pumpEditor(tester);
    expect(editing.hasTouchInput, isFalse);

    // arming the tool by finger is usually the first touch of a session
    await tester.tap(find.byIcon(Icons.draw)); // default kind: touch
    await tester.pump();
    expect(editing.tool, PdfEditTool.ink);
    expect(find.byIcon(Icons.touch_app), findsOneWidget);
  });
}
