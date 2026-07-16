import 'dart:typed_data';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  // The default test surface is 800×600. Pages are 612×792, so a horizontal
  // continuous layout fits each page's height to the 600px viewport: the
  // on-screen scale is 600/792 and each page is 612×(600/792) wide.
  const fitScale = 600 / 792;

  Future<PdfViewerController> pumpHorizontal(
    WidgetTester tester, {
    int pages = 5,
    Uint8List? bytes,
    PdfViewerFit fit = PdfViewerFit.width,
    PdfPageOverlayBuilder? overlayBuilder,
  }) async {
    final controller = PdfViewerController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          document: PdfDocument.open(bytes ?? buildMultiPagePdf(pages)),
          controller: controller,
          pageLayout: const PdfPageLayout.horizontalContinuous(),
          initialFit: fit,
          pageOverlayBuilder: overlayBuilder,
        ),
      ),
    ));
    await tester.pump();
    return controller;
  }

  group('PdfPageLayout', () {
    test('exposes the scroll axis', () {
      expect(const PdfPageLayout.verticalContinuous().scrollAxis,
          Axis.vertical);
      expect(const PdfPageLayout.horizontalContinuous().scrollAxis,
          Axis.horizontal);
    });

    test('has value equality', () {
      expect(const PdfPageLayout.horizontalContinuous(),
          const PdfPageLayout.horizontalContinuous());
      expect(const PdfPageLayout.verticalContinuous(),
          isNot(const PdfPageLayout.horizontalContinuous()));
      expect(const PdfPageLayout.horizontalContinuous().hashCode,
          const PdfPageLayout.horizontalContinuous().hashCode);
    });

    test('constructs at runtime and describes itself', () {
      // non-const invocations exercise the constructors at runtime
      final horizontal = PdfPageLayout.horizontalContinuous();
      final vertical = PdfPageLayout.verticalContinuous();
      expect(horizontal.scrollAxis, Axis.horizontal);
      expect(vertical.scrollAxis, Axis.vertical);
      expect(horizontal.toString(), 'PdfPageLayout.horizontalContinuous');
      expect(vertical.toString(), 'PdfPageLayout.verticalContinuous');
    });
  });

  testWidgets('lays pages out along a horizontal scrollable', (tester) async {
    final controller = await pumpHorizontal(tester);
    expect(controller.pageCount, 5);
    expect(controller.currentPage, 0);
    expect(find.byType(PdfPageView), findsWidgets);

    // the list scrolls horizontally
    final scrollable = tester.widget<Scrollable>(find
        .descendant(
            of: find.byType(PdfViewer), matching: find.byType(Scrollable))
        .first);
    expect(scrollable.axisDirection, AxisDirection.right);
  });

  testWidgets('horizontal drag advances the current page', (tester) async {
    final controller = await pumpHorizontal(tester);
    // a leftward drag pulls later pages into view
    await tester.drag(find.byType(PdfViewer), const Offset(-2500, 0));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(controller.currentPage, greaterThan(0));
  });

  testWidgets('jumpToPage scrolls horizontally to the page', (tester) async {
    final controller = await pumpHorizontal(tester);
    controller.jumpToPage(4);
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(controller.currentPage, 4);
    // page 4 sits at the viewport's left edge
    final region = controller.visiblePageRegion(4);
    expect(region, isNotNull);
    expect(region!.left, moreOrLessEquals(0, epsilon: 0.02));
  });

  testWidgets('visiblePageRegion tracks a horizontal scroll', (tester) async {
    final controller = await pumpHorizontal(tester);
    // page 0 fully spans the height, at the left edge
    final page0 = controller.visiblePageRegion(0)!;
    expect(page0.left, moreOrLessEquals(0, epsilon: 0.001));
    expect(page0.top, moreOrLessEquals(0, epsilon: 0.001));
    expect(page0.bottom, moreOrLessEquals(1, epsilon: 0.001));

    controller.jumpToPage(2);
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(controller.visiblePageRegion(0), isNull,
        reason: 'page 0 has scrolled off the left');
    expect(controller.visiblePageRegion(2), isNotNull);
  });

  testWidgets('captures and restores a horizontal viewport', (tester) async {
    final controller = await pumpHorizontal(tester);
    controller.jumpToPage(3);
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    // nudge a little into the page along the scroll axis
    await tester.drag(find.byType(PdfViewer), const Offset(-80, 0));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    final snapshot = controller.captureViewport();
    expect(snapshot, isNotNull);
    expect(snapshot!.page, 3);
    expect(snapshot.top, greaterThan(0));

    // scroll away, then restore
    controller.jumpToPage(0);
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    controller.restoreViewport(snapshot);
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    final restored = controller.captureViewport()!;
    expect(restored.page, 3);
    expect(restored.top, moreOrLessEquals(snapshot.top, epsilon: 0.02));
  });

  testWidgets('page overlays sit at PDF coordinates in a horizontal layout',
      (tester) async {
    var taps = 0;
    final controller = await pumpHorizontal(
      tester,
      pages: 2,
      overlayBuilder: (context, pageIndex, geometry) => [
        if (pageIndex == 0)
          Positioned.fromRect(
            rect: geometry.toViewRect(const PdfRect(72, 692, 172, 742)),
            child: TextButton(
              key: const Key('overlay'),
              onPressed: () => taps++,
              child: const Text('go'),
            ),
          ),
      ],
    );
    expect(controller.currentPage, 0);

    // page 0 starts at scroll 0 and fills the viewport height, so view space
    // == page view space at the fit-height scale
    final rect = tester.getRect(find.byKey(const Key('overlay')));
    expect(rect.left, moreOrLessEquals(72 * fitScale, epsilon: 0.2));
    expect(rect.top, moreOrLessEquals((792 - 742) * fitScale, epsilon: 0.2));
    expect(rect.width, moreOrLessEquals(100 * fitScale, epsilon: 0.2));
    expect(rect.height, moreOrLessEquals(50 * fitScale, epsilon: 0.2));

    // the overlay stays interactive
    await tester.tap(find.byKey(const Key('overlay')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(taps, 1);
    expect(find.byType(TextButton), findsOneWidget);
  });

  testWidgets('search navigates to a match in a horizontal layout',
      (tester) async {
    final controller = await pumpHorizontal(tester, pages: 6);
    await tester.runAsync(() => controller.search('Page 5'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(controller.matchCount, greaterThan(0));
    expect(controller.currentPage, 4, reason: 'page index for "Page 5"');
    expect(controller.visiblePageRegion(4), isNotNull);
  });

  testWidgets('opens fitted to the whole first page (Fit.page)',
      (tester) async {
    // Fit.page shrinks until the first page fits along the main (horizontal)
    // axis too: at fit-height the page is 612*(600/792) ≈ 464 wide, which is
    // already narrower than the 800px viewport, so no extra shrink is needed
    // and the whole page is visible.
    final controller =
        await pumpHorizontal(tester, pages: 3, fit: PdfViewerFit.page);
    final region = controller.visiblePageRegion(0)!;
    expect(region.left, moreOrLessEquals(0, epsilon: 0.001));
    expect(region.right, moreOrLessEquals(1, epsilon: 0.02),
        reason: 'the whole first page is visible along the scroll axis');
  });

  testWidgets('switching layout at runtime keeps the current page',
      (tester) async {
    final controller = PdfViewerController();
    final document = PdfDocument.open(buildMultiPagePdf(6));
    Widget build(PdfPageLayout layout) => MaterialApp(
          home: Scaffold(
            body: PdfViewer(
              key: const ValueKey('viewer'),
              document: document,
              controller: controller,
              pageLayout: layout,
              initialFit: PdfViewerFit.width,
            ),
          ),
        );

    await tester.pumpWidget(build(const PdfPageLayout.verticalContinuous()));
    await tester.pump();
    controller.jumpToPage(3);
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(controller.currentPage, 3);

    // flip to horizontal - the reader stays on page 3
    await tester
        .pumpWidget(build(const PdfPageLayout.horizontalContinuous()));
    await tester.pump(); // adopt the new layout
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(controller.currentPage, 3);

    final scrollable = tester.widget<Scrollable>(find
        .descendant(
            of: find.byType(PdfViewer), matching: find.byType(Scrollable))
        .first);
    expect(scrollable.axisDirection, AxisDirection.right);
  });

  testWidgets('showDestination scrolls to a page position horizontally',
      (tester) async {
    // 8 pages so page 3 sits well clear of the max scroll extent (no clamp)
    final controller = await pumpHorizontal(tester, pages: 8);
    // an /XYZ destination carries a left (horizontal) coordinate; a
    // horizontal layout scrolls the main axis to it (page 612pt wide)
    controller.showDestination(const PdfDestination(
      pageIndex: 3,
      fit: 'XYZ',
      params: [306, 700, null],
    ));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    // the destination scrolled page 3 so that 306/612 = 0.5 of the way
    // across it sits at the viewport's left edge (currentPage tracks the
    // viewport centre, which by then is the following page)
    final region = controller.visiblePageRegion(3);
    expect(region, isNotNull);
    expect(region!.left, moreOrLessEquals(0.5, epsilon: 0.05));
  });

  testWidgets('zooming out below fit relays the pages out horizontally',
      (tester) async {
    final controller = await pumpHorizontal(tester, pages: 5);
    // fit-height rests at 600/792 px/pt; zoom out below it to relayout the
    // pages smaller (exercises the layout-zoom path on the main axis)
    controller.setZoom(0.5);
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    expect(controller.zoom, moreOrLessEquals(0.5, epsilon: 0.01));
    // more pages fit across the viewport once shrunk
    expect(controller.visiblePageRegion(0), isNotNull);
    expect(controller.visiblePageRegion(2), isNotNull);
  });

  testWidgets('touch cross-axis pan rubber-bands and springs back',
      (tester) async {
    // In a horizontal layout the cross (rubber-band) axis is vertical, so a
    // vertical touch drag past the page edge over-scrolls and springs back.
    final editing = PdfEditingController(buildMultiPagePdf(3));
    addTearDown(editing.dispose);
    final controller = PdfViewerController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: editing,
          builder: (context, _) => PdfViewer(
            document: editing.document,
            editing: editing,
            controller: controller,
            pageLayout: const PdfPageLayout.horizontalContinuous(),
            initialFit: PdfViewerFit.width,
          ),
        ),
      ),
    ));
    await tester.pump();
    editing.tool = PdfEditTool.select;
    await tester.pump();

    // zoom in with a touch double-tap (2.5×)
    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(const Offset(400, 300));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(controller.zoom, greaterThan(1));

    final regionBefore = controller.visiblePageRegion(0)!;

    // vertical touch drag downward → content slides down, visible region
    // pushes past the top edge (top < 0 in rubber-band)
    final gesture = await tester.startGesture(const Offset(400, 300),
        kind: PointerDeviceKind.touch);
    var stamp = Duration.zero;
    for (var i = 0; i < 12; i++) {
      stamp += const Duration(milliseconds: 16);
      await gesture.moveBy(const Offset(0, 60), timeStamp: stamp);
      await tester.pump(const Duration(milliseconds: 16));
    }
    final regionMidDrag = controller.visiblePageRegion(0)!;
    expect(regionMidDrag.top, lessThan(regionBefore.top),
        reason: 'the content should have shifted down');

    await gesture.up(timeStamp: stamp + const Duration(milliseconds: 16));
    await tester.pump();
    // the spring-back animation brings the page back to the edge
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    final regionAfter = controller.visiblePageRegion(0)!;
    expect(regionAfter.top, moreOrLessEquals(0, epsilon: 0.02));

    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('mixed page sizes keep their aspect ratios centred',
      (tester) async {
    // buildVariedHeightPdf cycles page heights (792/396/1008, all 612 wide),
    // so in a horizontal layout the cross (height) fit differs per page and
    // shorter pages are centred vertically.
    final controller =
        await pumpHorizontal(tester, bytes: buildVariedHeightPdf(4));
    // the tallest page (1008pt) is the fit reference and fills the height
    final tall = controller.visiblePageRegion(2)!; // index 2 -> 1008pt
    expect(tall.top, moreOrLessEquals(0, epsilon: 0.02));
    expect(tall.bottom, moreOrLessEquals(1, epsilon: 0.02));
  });
}
