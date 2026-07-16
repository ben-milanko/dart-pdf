// Wheel-event scrolling, including web trackpad pans: on web there are
// no PointerPanZoomEvents - the engine delivers trackpad scrolls as
// PointerScrollEvents with kind: trackpad - so these tests simulate that
// stream. Regression: with an editing tool armed the list's
// NeverScrollableScrollPhysics made the Scrollable refuse wheel events,
// which on web killed vertical two-finger scrolling entirely (horizontal
// still panned the zoom window, so the bug read "only left and right
// work"); _onPointerSignal now scrolls the list itself via jumpTo.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<PdfViewerController> pumpViewer(WidgetTester tester) async {
    final controller = PdfViewerController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          initialFit: PdfViewerFit.width,
          document: PdfDocument.open(buildMultiPagePdf(5)),
          controller: controller,
        ),
      ),
    ));
    await tester.pump();
    return controller;
  }

  testWidgets('web-style trackpad scroll: vertical, not zoomed',
      (tester) async {
    await pumpViewer(tester);
    final pointer = TestPointer(101, PointerDeviceKind.trackpad);
    pointer.hover(const Offset(400, 300));
    await tester.sendEventToBinding(
        pointer.scroll(const Offset(0, 120)));
    await tester.pumpAndSettle();
    final state = tester
        .state<ScrollableState>(find.byType(Scrollable).first);
    expect(state.position.pixels, greaterThan(0),
        reason: 'vertical trackpad scroll should scroll the list');
  });

  testWidgets('web-style trackpad scroll: vertical while zoomed',
      (tester) async {
    final controller = await pumpViewer(tester);
    // zoom in with a touch double-tap
    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(const Offset(400, 300));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(controller.zoom, greaterThan(1.01));

    final state = tester
        .state<ScrollableState>(find.byType(Scrollable).first);
    final before = state.position.pixels;
    final pointer = TestPointer(102, PointerDeviceKind.trackpad);
    pointer.hover(const Offset(400, 300));
    for (var i = 0; i < 5; i++) {
      await tester.sendEventToBinding(
          pointer.scroll(const Offset(0, 60)));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();
    expect(state.position.pixels, greaterThan(before),
        reason: 'vertical trackpad scroll should move the document');
  });

  testWidgets('web-style trackpad scroll: horizontal while zoomed',
      (tester) async {
    final controller = await pumpViewer(tester);
    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(const Offset(400, 300));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(controller.zoom, greaterThan(1.01));

    final pointer = TestPointer(103, PointerDeviceKind.trackpad);
    pointer.hover(const Offset(400, 300));
    // capture tx via the controller's pan state: use visiblePageRegion
    final beforeRegion = controller.visiblePageRegion(0);
    for (var i = 0; i < 5; i++) {
      await tester.sendEventToBinding(
          pointer.scroll(const Offset(60, 0)));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();
    final afterRegion = controller.visiblePageRegion(0);
    expect(afterRegion!.left, isNot(closeTo(beforeRegion!.left, 0.001)),
        reason: 'horizontal trackpad scroll should pan the zoom window');
  });

  testWidgets('web-style trackpad scroll: horizontal at fit zoom reaches the '
      'pasteboard', (tester) async {
    // On web a two-finger sideways trackpad swipe arrives as a horizontal
    // wheel event. At the default fit zoom it must still pan the page a
    // bounded distance onto the off-page pasteboard (not do nothing), so
    // off-page material is reachable without zooming in first.
    final controller = await pumpViewer(tester);
    expect(controller.captureViewport()!.left,
        moreOrLessEquals(0, epsilon: 0.01));
    final state = tester.state<ScrollableState>(find.byType(Scrollable).first);

    final pointer = TestPointer(107, PointerDeviceKind.trackpad);
    pointer.hover(const Offset(400, 300));
    for (var i = 0; i < 5; i++) {
      await tester.sendEventToBinding(pointer.scroll(const Offset(60, 0)));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();

    final vp = controller.captureViewport()!;
    expect(vp.left.abs(), greaterThan(0.05),
        reason: 'a fit-zoom horizontal wheel reaches the pasteboard');
    expect(vp.left.abs(), lessThan(0.25),
        reason: 'the pasteboard pan is bounded to the margin');
    expect(vp.top, moreOrLessEquals(0, epsilon: 0.02),
        reason: 'no vertical drift: the list owns vertical scrolling');
    expect(state.position.pixels, moreOrLessEquals(0, epsilon: 0.5),
        reason: 'a pure horizontal pan does not scroll the list');
  });

  testWidgets('shift+mouse wheel at fit zoom reaches the pasteboard',
      (tester) async {
    final controller = await pumpViewer(tester);
    final state = tester.state<ScrollableState>(find.byType(Scrollable).first);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    final pointer = TestPointer(108, PointerDeviceKind.mouse);
    pointer.hover(const Offset(400, 300));
    for (var i = 0; i < 5; i++) {
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 60)));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();

    final vp = controller.captureViewport()!;
    expect(vp.left.abs(), greaterThan(0.05),
        reason: 'shift+wheel reaches the pasteboard at fit zoom');
    expect(vp.left.abs(), lessThan(0.25));
    expect(state.position.pixels, moreOrLessEquals(0, epsilon: 0.5),
        reason: 'shift+wheel pans horizontally, it does not scroll the list');
  });

  // Two ways a shift+mouse-wheel reaches Flutter: with the vertical delta
  // still in dy (the engine passes the wheel through raw and Flutter's
  // own pointerAxisModifiers do the flip) and pre-flipped into dx (the
  // browser / macOS swap the axis at the source). Both must pan the zoom
  // window sideways without scrolling the list - and crucially the dx form
  // is the one the vertical Scrollable would otherwise eat as a vertical
  // scroll, so it's the regression that broke real-app shift-scrolling.
  for (final delta in const [Offset(0, 60), Offset(60, 0)]) {
    testWidgets('shift+mouse wheel ($delta) pans horizontally while zoomed',
        (tester) async {
      final controller = await pumpViewer(tester);
      await tester.tapAt(const Offset(400, 300));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(const Offset(400, 300));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expect(controller.zoom, greaterThan(1.01));

      final state =
          tester.state<ScrollableState>(find.byType(Scrollable).first);
      final scrollBefore = state.position.pixels;
      final beforeRegion = controller.visiblePageRegion(0);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      final pointer = TestPointer(106, PointerDeviceKind.mouse);
      pointer.hover(const Offset(400, 300));
      for (var i = 0; i < 5; i++) {
        await tester.sendEventToBinding(pointer.scroll(delta));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();

      final afterRegion = controller.visiblePageRegion(0);
      expect(afterRegion!.left, isNot(closeTo(beforeRegion!.left, 0.001)),
          reason: 'shift+wheel should pan the zoom window horizontally');
      expect(state.position.pixels, closeTo(scrollBefore, 0.001),
          reason: 'shift+wheel should not scroll the document vertically');
    });
  }

  testWidgets('web-style trackpad scroll: vertical with a tool armed',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final editing = PdfEditingController(buildMultiPagePdf(5));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: editing,
          builder: (_, __) => PdfViewer(
            initialFit: PdfViewerFit.width,
            document: editing.document,
            editing: editing,
          ),
        ),
      ),
    ));
    await tester.pump();
    editing.tool = PdfEditTool.ink;
    await tester.pumpAndSettle();

    final pointer = TestPointer(105, PointerDeviceKind.trackpad);
    pointer.hover(const Offset(400, 300));
    for (var i = 0; i < 5; i++) {
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 60)));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();
    final state = tester.state<ScrollableState>(find
        .descendant(
            of: find.byType(PdfViewer), matching: find.byType(Scrollable))
        .first);
    expect(state.position.pixels, greaterThan(0),
        reason: 'vertical trackpad scroll should still scroll the list '
            'with a tool armed (web delivers trackpad pans as wheel '
            'events)');
    editing.dispose();
  });

  testWidgets('web-style trackpad scroll: vertical in PdfEditorView shell',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfEditorView(bytes: buildMultiPagePdf(5)),
      ),
    ));
    await tester.pump();
    await tester.pumpAndSettle();

    final pointer = TestPointer(104, PointerDeviceKind.trackpad);
    pointer.hover(tester.getCenter(find.byType(PdfViewer)));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
    await tester.pumpAndSettle();
    final state = tester.state<ScrollableState>(find
        .descendant(
            of: find.byType(PdfViewer), matching: find.byType(Scrollable))
        .first);
    expect(state.position.pixels, greaterThan(0),
        reason: 'vertical trackpad scroll should scroll the list');
  });
}
