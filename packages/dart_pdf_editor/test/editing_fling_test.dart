import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Touch fling momentum on the editing overlay's viewport-pan path: with
// a tool armed the overlay (not the list's scroll physics) moves the
// document, so lift-off velocity must be carried by the viewer's own
// fling, or every finger scroll stops dead the moment it lifts.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<PdfEditingController> pumpViewer(WidgetTester tester) async {
    final editing = PdfEditingController(buildMultiPagePdf(4));
    addTearDown(editing.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: editing,
          builder: (context, _) => PdfViewer(
            initialFit: PdfViewerFit.width,
            document: editing.document,
            editing: editing,
          ),
        ),
      ),
    ));
    await tester.pump();
    editing.tool = PdfEditTool.select;
    await tester.pump();
    return editing;
  }

  ScrollPosition scrollPosition(WidgetTester tester) =>
      tester.state<ScrollableState>(find.byType(Scrollable).first).position;

  /// A fast upward touch drag over empty page area; the overlay's pan
  /// recognizer claims it (select tool armed) and pans the viewport.
  /// Events carry explicit timestamps - TestGesture defaults every event
  /// to t=0, which reads as zero velocity at lift-off.
  Future<(TestGesture, Duration)> swipeUp(WidgetTester tester) async {
    var stamp = Duration.zero;
    final gesture = await tester.startGesture(const Offset(400, 450),
        kind: PointerDeviceKind.touch);
    for (var i = 0; i < 6; i++) {
      stamp += const Duration(milliseconds: 16);
      await gesture.moveBy(const Offset(0, -40), timeStamp: stamp);
      await tester.pump(const Duration(milliseconds: 16));
    }
    return (gesture, stamp);
  }

  testWidgets('a touch viewport pan keeps its momentum after lift-off',
      (tester) async {
    await pumpViewer(tester);

    final (gesture, stamp) = await swipeUp(tester);
    final atLift = scrollPosition(tester).pixels;
    expect(atLift, greaterThan(100)); // the drag itself panned
    await gesture.up(timeStamp: stamp + const Duration(milliseconds: 16));
    await tester.pump();

    // the fling carries on well past the lift-off position
    await tester.pump(const Duration(milliseconds: 100));
    final early = scrollPosition(tester).pixels;
    expect(early, greaterThan(atLift + 30));
    await tester.pump(const Duration(milliseconds: 400));
    final later = scrollPosition(tester).pixels;
    expect(later, greaterThan(early + 50));

    // decelerating, not constant-velocity: the next stretch covers less
    await tester.pump(const Duration(milliseconds: 400));
    final coast = scrollPosition(tester).pixels - later;
    expect(coast, lessThan(later - early));

    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400)); // double-tap timer
  });

  testWidgets('touching down stops the fling immediately', (tester) async {
    await pumpViewer(tester);

    final (gesture, stamp) = await swipeUp(tester);
    await gesture.up(timeStamp: stamp + const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 100));
    final flying = scrollPosition(tester).pixels;
    await tester.pump(const Duration(milliseconds: 50));
    expect(scrollPosition(tester).pixels, greaterThan(flying)); // mid-fling

    final finger = await tester.startGesture(const Offset(400, 300),
        kind: PointerDeviceKind.touch);
    await tester.pump();
    final stopped = scrollPosition(tester).pixels;
    await tester.pump(const Duration(milliseconds: 300));
    expect(scrollPosition(tester).pixels, stopped);

    await finger.up();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('a slow release does not fling', (tester) async {
    await pumpViewer(tester);

    var stamp = Duration.zero;
    final gesture = await tester.startGesture(const Offset(400, 450),
        kind: PointerDeviceKind.touch);
    for (var i = 0; i < 6; i++) {
      stamp += const Duration(milliseconds: 400);
      // long gaps between samples: well under kMinFlingVelocity
      await gesture.moveBy(const Offset(0, -15), timeStamp: stamp);
      await tester.pump(const Duration(milliseconds: 400));
    }
    await gesture.up(timeStamp: stamp + const Duration(milliseconds: 400));
    await tester.pump();
    final atLift = scrollPosition(tester).pixels;
    await tester.pump(const Duration(milliseconds: 400));
    expect(scrollPosition(tester).pixels, atLift);
    await tester.pump(const Duration(milliseconds: 400));
  });
}
