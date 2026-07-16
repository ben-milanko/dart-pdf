import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Edge auto-scroll: a region/selection drag (snapshot, marquee, move…) held
// against the viewport edge keeps panning the document in that direction, so
// you can drag past what's currently on screen. The held pointer re-tracks
// onto the content scrolled under it, so the drag keeps growing.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<PdfEditingController> pumpViewer(WidgetTester tester) async {
    final editing = PdfEditingController(buildMultiPagePdf(6));
    addTearDown(editing.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: editing,
          builder: (context, _) => PdfViewer(
            initialFit: PdfViewerFit.width,
            document: editing.document,
            editing: editing,
            onSnapshot: (_, __) async {},
          ),
        ),
      ),
    ));
    await tester.pump();
    return editing;
  }

  ScrollPosition scrollPosition(WidgetTester tester) =>
      tester.state<ScrollableState>(find.byType(Scrollable).first).position;

  testWidgets('a snapshot drag held at the bottom edge keeps scrolling',
      (tester) async {
    final editing = await pumpViewer(tester);
    editing.tool = PdfEditTool.snapshot;
    await tester.pump();

    // press mid-page and drag the rect down into the bottom edge band
    final gesture = await tester.startGesture(const Offset(400, 300),
        kind: PointerDeviceKind.mouse);
    await tester.pump();
    await gesture.moveBy(const Offset(0, 290)); // ≈ y 590, inside the band
    await tester.pump();
    final atEdge = scrollPosition(tester).pixels;

    // holding still - no more pointer moves - keeps panning frame by frame
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final scrolled = scrollPosition(tester).pixels;
    expect(scrolled, greaterThan(atEdge + 10));

    // lifting stops it: the position holds across further frames
    await gesture.up();
    await tester.pump();
    final rest = scrollPosition(tester).pixels;
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(scrollPosition(tester).pixels, rest);

    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400)); // double-tap timer
  });

  testWidgets('a drag away from the edges does not auto-scroll',
      (tester) async {
    final editing = await pumpViewer(tester);
    editing.tool = PdfEditTool.snapshot;
    await tester.pump();

    final gesture = await tester.startGesture(const Offset(300, 250),
        kind: PointerDeviceKind.mouse);
    await tester.pump();
    await gesture.moveBy(const Offset(120, 60)); // stays well inside
    await tester.pump();
    final held = scrollPosition(tester).pixels;
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(scrollPosition(tester).pixels, held);

    await gesture.up();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('dragging to the top edge scrolls back up', (tester) async {
    final editing = await pumpViewer(tester);
    // start partway down so there is room to scroll up
    await tester.fling(find.byType(PdfViewer), const Offset(0, -400), 1000);
    await tester.pumpAndSettle();
    final start = scrollPosition(tester).pixels;
    expect(start, greaterThan(60));

    editing.tool = PdfEditTool.snapshot;
    await tester.pump();

    final gesture = await tester.startGesture(const Offset(400, 300),
        kind: PointerDeviceKind.mouse);
    await tester.pump();
    await gesture.moveBy(const Offset(0, -280)); // ≈ y 20, inside the top band
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(scrollPosition(tester).pixels, lessThan(start - 10));

    await gesture.up();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
  });
}
