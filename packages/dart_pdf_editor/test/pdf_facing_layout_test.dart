import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  // The default test surface is 800×600 and pages are 612×792. A vertical
  // facing layout fits two of the widest page across the viewport, so each
  // page is 400 wide at a scale of 400/612, and the spine sits at x = 400.
  const viewWidth = 800.0;
  const spine = viewWidth / 2;
  const scale = spine / 612;
  const pageHeight = 792 * scale;
  const spacing = 12.0; // PdfViewer.pageSpacing's default

  // Every page carries a full-size overlay, so a page's on-screen rect is the
  // overlay's rect.
  Rect pageRect(WidgetTester tester, int index) =>
      tester.getRect(find.byKey(ValueKey('page-$index')));

  Future<PdfViewerController> pumpFacing(
    WidgetTester tester, {
    int pages = 6,
    Uint8List? bytes,
    PdfPageLayout layout = const PdfPageLayout.facing(),
    PdfViewerFit fit = PdfViewerFit.width,
    List<Widget> Function(int pageIndex, PdfPageGeometry geometry)? extra,
  }) async {
    final controller = PdfViewerController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          document: PdfDocument.open(bytes ?? buildMultiPagePdf(pages)),
          controller: controller,
          pageLayout: layout,
          initialFit: fit,
          pageOverlayBuilder: (context, pageIndex, geometry) => [
            Positioned.fill(
              child: IgnorePointer(
                child: SizedBox(key: ValueKey('page-$pageIndex')),
              ),
            ),
            ...?extra?.call(pageIndex, geometry),
          ],
        ),
      ),
    ));
    await tester.pump();
    return controller;
  }

  group('PdfPageLayout.facing', () {
    test('defaults to vertical spreads without a cover', () {
      const layout = PdfPageLayout.facing();
      expect(layout.facing, isTrue);
      expect(layout.coverPage, isFalse);
      expect(layout.scrollAxis, Axis.vertical);
      expect(const PdfPageLayout.verticalContinuous().facing, isFalse);
      expect(const PdfPageLayout.horizontalContinuous().coverPage, isFalse);
    });

    test('withFacing pairs or unpairs a layout along its axis', () {
      expect(const PdfPageLayout.verticalContinuous().withFacing(true),
          const PdfPageLayout.facing());
      expect(
          const PdfPageLayout.horizontalContinuous()
              .withFacing(true, coverPage: true),
          const PdfPageLayout.facing(
              scrollAxis: Axis.horizontal, coverPage: true));
      expect(
          const PdfPageLayout.facing(scrollAxis: Axis.horizontal)
              .withFacing(false),
          const PdfPageLayout.horizontalContinuous());
      expect(const PdfPageLayout.facing().withFacing(false),
          const PdfPageLayout.verticalContinuous());
    });

    test('has value equality and describes itself', () {
      expect(const PdfPageLayout.facing(), const PdfPageLayout.facing());
      expect(const PdfPageLayout.facing().hashCode,
          const PdfPageLayout.facing().hashCode);
      expect(const PdfPageLayout.facing(),
          isNot(const PdfPageLayout.facing(coverPage: true)));
      expect(const PdfPageLayout.facing(),
          isNot(const PdfPageLayout.verticalContinuous()));
      expect(const PdfPageLayout.facing(scrollAxis: Axis.horizontal),
          isNot(const PdfPageLayout.horizontalContinuous()));
      // runtime construction
      final layout =
          PdfPageLayout.facing(scrollAxis: Axis.horizontal, coverPage: true);
      expect(layout.toString(),
          'PdfPageLayout.facing(scrollAxis: horizontal, coverPage: true)');
    });
  });

  testWidgets('pairs consecutive pages side by side at the spine',
      (tester) async {
    await pumpFacing(tester);
    final left = pageRect(tester, 0);
    final right = pageRect(tester, 1);
    expect(left.left, moreOrLessEquals(0, epsilon: 0.5));
    expect(left.right, moreOrLessEquals(spine, epsilon: 0.5));
    expect(right.left, moreOrLessEquals(spine, epsilon: 0.5));
    expect(right.right, moreOrLessEquals(viewWidth, epsilon: 0.5));
    expect(left.top, moreOrLessEquals(right.top, epsilon: 0.5));
    expect(left.height, moreOrLessEquals(pageHeight, epsilon: 0.5));
  });

  testWidgets('the next spread follows below after the page spacing',
      (tester) async {
    final controller = await pumpFacing(tester);
    controller.jumpToPage(2);
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    final left = pageRect(tester, 2);
    final right = pageRect(tester, 3);
    expect(left.top, moreOrLessEquals(0, epsilon: 0.5));
    expect(right.top, moreOrLessEquals(0, epsilon: 0.5));
    expect(left.left, moreOrLessEquals(0, epsilon: 0.5));
    expect(right.left, moreOrLessEquals(spine, epsilon: 0.5));
    // the next spread starts one page spacing after this one ends
    final below = pageRect(tester, 4);
    expect(below.top, moreOrLessEquals(pageHeight + spacing, epsilon: 0.5));
  });

  testWidgets('a cover page stands alone on the right', (tester) async {
    final controller = await pumpFacing(tester,
        pages: 5, layout: const PdfPageLayout.facing(coverPage: true));
    final cover = pageRect(tester, 0);
    expect(cover.left, moreOrLessEquals(spine, epsilon: 0.5));
    expect(cover.top, moreOrLessEquals(0, epsilon: 0.5));
    // pages 2-3 (indices 1, 2) form the first spread, below the cover
    final left = pageRect(tester, 1);
    final right = pageRect(tester, 2);
    expect(left.top, moreOrLessEquals(pageHeight + spacing, epsilon: 0.5));
    expect(right.top, moreOrLessEquals(left.top, epsilon: 0.5));
    expect(left.right, moreOrLessEquals(spine, epsilon: 0.5));
    expect(right.left, moreOrLessEquals(spine, epsilon: 0.5));
    // the last spread (indices 3, 4) is full
    controller.jumpToPage(4);
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(pageRect(tester, 3).right, moreOrLessEquals(spine, epsilon: 0.5));
    expect(pageRect(tester, 4).left, moreOrLessEquals(spine, epsilon: 0.5));
  });

  testWidgets('an unpaired last page keeps the left side', (tester) async {
    final controller = await pumpFacing(tester, pages: 5);
    controller.jumpToPage(4);
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    final last = pageRect(tester, 4);
    expect(last.left, moreOrLessEquals(0, epsilon: 0.5));
    expect(last.right, moreOrLessEquals(spine, epsilon: 0.5));
    expect(controller.currentPage, 4);
  });

  testWidgets('jumping to a right page shows its spread', (tester) async {
    final controller = await pumpFacing(tester, pages: 8);
    controller.jumpToPage(5);
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(controller.visiblePageRegion(4), isNotNull);
    expect(controller.visiblePageRegion(5), isNotNull);
    expect(pageRect(tester, 5).top, moreOrLessEquals(0, epsilon: 0.5));
    // the spread's left page is the one reported
    expect(controller.currentPage, 4);
  });

  testWidgets('overlays on a right page sit at PDF coordinates and tap',
      (tester) async {
    var taps = 0;
    await pumpFacing(
      tester,
      pages: 2,
      extra: (pageIndex, geometry) => [
        if (pageIndex == 1)
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
    final rect = tester.getRect(find.byKey(const Key('overlay')));
    expect(rect.left, moreOrLessEquals(spine + 72 * scale, epsilon: 0.5));
    expect(rect.top, moreOrLessEquals((792 - 742) * scale, epsilon: 0.5));
    await tester.tap(find.byKey(const Key('overlay')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(taps, 1);
  });

  testWidgets('captures and restores a viewport on a spread', (tester) async {
    final controller = await pumpFacing(tester, pages: 10);
    controller.jumpToPage(6);
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await tester.drag(find.byType(PdfViewer), const Offset(0, -80));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    final snapshot = controller.captureViewport()!;
    expect(snapshot.page, 6);
    expect(snapshot.top, greaterThan(0));

    controller.jumpToPage(0);
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    controller.restoreViewport(snapshot);
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    final restored = controller.captureViewport()!;
    expect(restored.page, 6);
    expect(restored.top, moreOrLessEquals(snapshot.top, epsilon: 0.02));
  });

  testWidgets('search lands on a match on a right page', (tester) async {
    final controller = await pumpFacing(tester, pages: 8);
    await tester.runAsync(() => controller.search('Page 6'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(controller.matchCount, greaterThan(0));
    expect(controller.visiblePageRegion(5), isNotNull,
        reason: 'page index for "Page 6"');
  });

  testWidgets('Fit.page fits the whole first spread', (tester) async {
    final controller =
        await pumpFacing(tester, pages: 4, fit: PdfViewerFit.page);
    for (final page in [0, 1]) {
      final region = controller.visiblePageRegion(page)!;
      expect(region.top, moreOrLessEquals(0, epsilon: 0.001));
      expect(region.bottom, moreOrLessEquals(1, epsilon: 0.02));
      expect(region.left, moreOrLessEquals(0, epsilon: 0.001));
      expect(region.right, moreOrLessEquals(1, epsilon: 0.02));
    }
    // the spread is centred on the spine
    expect(pageRect(tester, 0).right, moreOrLessEquals(spine, epsilon: 0.5));
    expect(pageRect(tester, 1).left, moreOrLessEquals(spine, epsilon: 0.5));
  });

  testWidgets('horizontal spreads touch, with spacing between spreads',
      (tester) async {
    // scrolling horizontally the tallest page fits the 600px height
    const hScale = 600 / 792;
    const hWidth = 612 * hScale;
    await pumpFacing(tester,
        pages: 6,
        layout: const PdfPageLayout.facing(scrollAxis: Axis.horizontal));
    final scrollable = tester.widget<Scrollable>(find
        .descendant(
            of: find.byType(PdfViewer), matching: find.byType(Scrollable))
        .first);
    expect(scrollable.axisDirection, AxisDirection.right);
    expect(pageRect(tester, 0).left, moreOrLessEquals(0, epsilon: 0.5));
    expect(pageRect(tester, 1).left, moreOrLessEquals(hWidth, epsilon: 0.5));
    expect(pageRect(tester, 1).top, moreOrLessEquals(0, epsilon: 0.5));
    await tester.drag(find.byType(PdfViewer), const Offset(-400, 0));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    final shift = pageRect(tester, 0).left;
    expect(pageRect(tester, 2).left - shift,
        moreOrLessEquals(2 * hWidth + spacing, epsilon: 0.5));
  });

  testWidgets('switching to facing at runtime keeps the current page',
      (tester) async {
    final controller = PdfViewerController();
    final document = PdfDocument.open(buildMultiPagePdf(8));
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
    controller.jumpToPage(4);
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(controller.currentPage, 4);

    await tester.pumpWidget(build(const PdfPageLayout.facing()));
    await tester.pump();
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(controller.currentPage, 4);
    expect(controller.visiblePageRegion(5), isNotNull);

    await tester.pumpWidget(build(const PdfPageLayout.verticalContinuous()));
    await tester.pump();
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(controller.currentPage, 4);
  });

  testWidgets('zooming out below fit relays the spreads out', (tester) async {
    final controller = await pumpFacing(tester, pages: 8);
    controller.setZoom(scale / 2);
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    expect(controller.zoom, moreOrLessEquals(scale / 2, epsilon: 0.01));
    // half-size pages: the spine stays centred and two spreads fit
    expect(pageRect(tester, 0).right, moreOrLessEquals(spine, epsilon: 0.5));
    expect(pageRect(tester, 0).width, moreOrLessEquals(200, epsilon: 0.5));
    expect(controller.visiblePageRegion(2), isNotNull);
    expect(controller.visiblePageRegion(3), isNotNull);
  });

  testWidgets('annotation tools draw on the right page of a spread',
      (tester) async {
    final editing = PdfEditingController(buildMultiPagePdf(4));
    final viewer = PdfViewerController();
    addTearDown(editing.dispose);
    addTearDown(viewer.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          initialFit: PdfViewerFit.width,
          controller: viewer,
          editing: editing,
          pageLayout: const PdfPageLayout.facing(),
        ),
      ),
    ));
    await tester.pump();
    editing.tool = PdfEditTool.rectangle;
    await tester.pump();

    // PDF point (x, y) on the right page (index 1), in view coordinates
    Offset right(double x, double y) =>
        Offset(spine + x * scale, (792 - y) * scale);
    final from = right(100, 700), to = right(250, 600);
    final gesture = await tester.startGesture(from);
    await gesture.moveTo(Offset.lerp(from, to, 0.5)!);
    await gesture.moveTo(to);
    await gesture.up();
    await tester.pump();

    expect(editing.document.page(0).annotations, isEmpty);
    final annotation = editing.document.page(1).annotations.single;
    expect(annotation.subtype, 'Square');
    expect(annotation.rect.left, closeTo(100, 3));
    expect(annotation.rect.right, closeTo(250, 3));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
  });
}
