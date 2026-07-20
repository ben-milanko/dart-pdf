import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

// The public scroll-indicator API (issue #326): PdfScrollMetrics, the
// controller's scrollMetrics/jumpToNormalized/animateToPage commands, and
// PdfViewer.scrollIndicatorBuilder.
void main() {
  const stockThumb = ValueKey('pdf-scrollbar-thumb');

  Future<PdfViewerController> pumpViewer(
    WidgetTester tester, {
    int pages = 5,
    PdfViewerFit fit = PdfViewerFit.width,
    PdfScrollIndicatorBuilder? indicator,
    PdfViewerController? controller,
    PdfPageLayout layout = const PdfPageLayout.verticalContinuous(),
  }) async {
    final c = controller ?? PdfViewerController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          initialFit: fit,
          pageLayout: layout,
          document: PdfDocument.open(buildMultiPagePdf(pages)),
          controller: c,
          scrollIndicatorBuilder: indicator,
        ),
      ),
    ));
    await tester.pump();
    return c;
  }

  ScrollPosition scrollPosition(WidgetTester tester) =>
      tester.state<ScrollableState>(find.byType(Scrollable).first).position;

  group('PdfScrollMetrics', () {
    test('value equality', () {
      const a = PdfScrollMetrics(
        pageCount: 5,
        currentPage: 1,
        position: 0.5,
        extent: 0.2,
        pixels: 100,
        maxPixels: 200,
        viewportPixels: 60,
        zoom: 1,
        hasOverflow: true,
      );
      const b = PdfScrollMetrics(
        pageCount: 5,
        currentPage: 1,
        position: 0.5,
        extent: 0.2,
        pixels: 100,
        maxPixels: 200,
        viewportPixels: 60,
        zoom: 1,
        hasOverflow: true,
      );
      const c = PdfScrollMetrics(
        pageCount: 5,
        currentPage: 2, // differs
        position: 0.5,
        extent: 0.2,
        pixels: 100,
        maxPixels: 200,
        viewportPixels: 60,
        zoom: 1,
        hasOverflow: true,
      );
      // scrollAxis defaults to vertical and participates in equality
      const d = PdfScrollMetrics(
        pageCount: 5,
        currentPage: 1,
        position: 0.5,
        extent: 0.2,
        pixels: 100,
        maxPixels: 200,
        viewportPixels: 60,
        zoom: 1,
        hasOverflow: true,
        scrollAxis: Axis.horizontal, // differs
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
      expect(a, isNot(d));
      expect(a.scrollAxis, Axis.vertical);
      expect(a.hasOverflow, isTrue);
      // toString surfaces the page, position/extent/zoom, and the axis
      expect(
          a.toString(),
          allOf(contains('page 2/5'), contains('position: 0.500'),
              contains('axis: vertical')));
      expect(d.toString(), contains('axis: horizontal'));
    });
  });

  group('controller.scrollMetrics', () {
    testWidgets('is null before layout, populated after', (tester) async {
      final controller = PdfViewerController();
      expect(controller.scrollMetrics, isNull);
      await pumpViewer(tester, controller: controller);

      final metrics = controller.scrollMetrics;
      expect(metrics, isNotNull);
      expect(metrics!.pageCount, 5);
      expect(metrics.currentPage, 0);
      expect(metrics.scrollAxis, Axis.vertical);
      expect(metrics.position, moreOrLessEquals(0, epsilon: 0.001));
      expect(metrics.hasOverflow, isTrue);
      // extent is the visible fraction, matching the stock thumb sizing
      final position = scrollPosition(tester);
      final total = position.maxScrollExtent + position.viewportDimension;
      expect(metrics.extent,
          moreOrLessEquals(position.viewportDimension / total, epsilon: 0.001));
      expect(metrics.zoom, moreOrLessEquals(controller.zoom, epsilon: 0.001));
    });

    testWidgets('position tracks scrolling', (tester) async {
      final controller = await pumpViewer(tester);
      expect(controller.scrollMetrics!.position, moreOrLessEquals(0, epsilon: 0.001));

      scrollPosition(tester).jumpTo(scrollPosition(tester).maxScrollExtent);
      await tester.pump();
      expect(controller.scrollMetrics!.position,
          moreOrLessEquals(1, epsilon: 0.001));
      expect(controller.scrollMetrics!.currentPage, 4);
    });

    testWidgets('reports no overflow when the whole document fits',
        (tester) async {
      final controller =
          await pumpViewer(tester, pages: 1, fit: PdfViewerFit.page);
      final metrics = controller.scrollMetrics;
      expect(metrics, isNotNull);
      expect(metrics!.hasOverflow, isFalse);
      expect(metrics.position, 0);
      // nearly the whole content is visible (only the trailing page margin
      // sits below the fold)
      expect(metrics.extent, greaterThan(0.95));
    });
  });

  group('controller.jumpToNormalized', () {
    testWidgets('scrolls to the top and bottom', (tester) async {
      final controller = await pumpViewer(tester);
      final position = scrollPosition(tester);

      controller.jumpToNormalized(1);
      await tester.pump();
      expect(position.pixels, moreOrLessEquals(position.maxScrollExtent, epsilon: 0.5));
      expect(controller.scrollMetrics!.position,
          moreOrLessEquals(1, epsilon: 0.001));

      controller.jumpToNormalized(0);
      await tester.pump();
      expect(position.pixels, moreOrLessEquals(0, epsilon: 0.5));
    });

    testWidgets('maps a mid-range fraction proportionally', (tester) async {
      final controller = await pumpViewer(tester);
      final position = scrollPosition(tester);

      controller.jumpToNormalized(0.5);
      await tester.pump();
      expect(controller.scrollMetrics!.position,
          moreOrLessEquals(0.5, epsilon: 0.01));
      expect(position.pixels,
          moreOrLessEquals(position.maxScrollExtent / 2, epsilon: 1));
    });

    testWidgets('clamps out-of-range fractions', (tester) async {
      final controller = await pumpViewer(tester);
      final position = scrollPosition(tester);

      controller.jumpToNormalized(5);
      await tester.pump();
      expect(position.pixels, moreOrLessEquals(position.maxScrollExtent, epsilon: 0.5));

      controller.jumpToNormalized(-5);
      await tester.pump();
      expect(position.pixels, moreOrLessEquals(0, epsilon: 0.5));
    });
  });

  group('controller.animateToPage', () {
    testWidgets('animates to a page', (tester) async {
      final controller = await pumpViewer(tester, pages: 8);
      unawaited(controller.animateToPage(3));
      await tester.pumpAndSettle();
      expect(controller.currentPage, 3);
    });
  });

  group('PdfViewer.scrollIndicatorBuilder', () {
    testWidgets('replaces the stock scrollbar and receives live metrics',
        (tester) async {
      PdfScrollMetrics? seen;
      final controller = await pumpViewer(
        tester,
        indicator: (context, controller, metrics) {
          seen = metrics;
          return const SizedBox.shrink(key: ValueKey('custom-indicator'));
        },
      );

      // the built-in scrollbar thumb is gone, the custom indicator is up
      expect(find.byKey(stockThumb), findsNothing);
      expect(find.byKey(const ValueKey('custom-indicator')), findsOneWidget);
      expect(seen, isNotNull);
      expect(seen!.pageCount, 5);
      expect(seen!.position, moreOrLessEquals(0, epsilon: 0.001));

      // scrolling rebuilds the indicator with fresh metrics
      scrollPosition(tester).jumpTo(scrollPosition(tester).maxScrollExtent);
      await tester.pump();
      expect(seen!.position, moreOrLessEquals(1, epsilon: 0.001));
      expect(controller.scrollMetrics!.position,
          moreOrLessEquals(1, epsilon: 0.001));
    });

    testWidgets('is not built while the document fits (no overflow)',
        (tester) async {
      var built = 0;
      await pumpViewer(
        tester,
        pages: 1,
        fit: PdfViewerFit.page,
        indicator: (context, controller, metrics) {
          built++;
          return const SizedBox.shrink(key: ValueKey('custom-indicator'));
        },
      );
      expect(find.byKey(const ValueKey('custom-indicator')), findsNothing);
      expect(built, 0);
    });

    testWidgets('a scrubber drag through the controller scrolls', (tester) async {
      final controller = await pumpViewer(
        tester,
        pages: 8,
        indicator: (context, controller, metrics) => GestureDetector(
          key: const ValueKey('scrubber'),
          // opaque so the scrubber wins the gesture arena over the scroll
          // view underneath, the way the stock scrollbar's strip does
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (d) {
            final box = context.findRenderObject() as RenderBox;
            controller.jumpToNormalized(d.localPosition.dy / box.size.height);
          },
          child: const SizedBox.expand(),
        ),
      );
      expect(controller.scrollMetrics!.position,
          moreOrLessEquals(0, epsilon: 0.001));

      // drag to roughly the middle of the track
      await tester.drag(
          find.byKey(const ValueKey('scrubber')), const Offset(0, 300));
      await tester.pump();
      expect(controller.scrollMetrics!.position, greaterThan(0.2));
      // drain the viewer's settle/motion-hold timers before teardown
      await tester.pumpAndSettle();
    });
  });

  // The scroll-indicator API describes the viewer's main layout axis (issue
  // #428): in a horizontal continuous layout the metrics, jumpToNormalized,
  // and the indicator builder all follow the horizontal axis.
  group('horizontal layout', () {
    const horizontal = PdfPageLayout.horizontalContinuous();

    testWidgets('scrollAxis reports the horizontal main axis', (tester) async {
      final controller = await pumpViewer(tester, layout: horizontal);
      final metrics = controller.scrollMetrics;
      expect(metrics, isNotNull);
      expect(metrics!.scrollAxis, Axis.horizontal);
      expect(metrics.pageCount, 5);
      expect(metrics.hasOverflow, isTrue);
      expect(metrics.position, moreOrLessEquals(0, epsilon: 0.001));
    });

    testWidgets('position and extent track horizontal scrolling',
        (tester) async {
      final controller = await pumpViewer(tester, layout: horizontal);
      final position = scrollPosition(tester);
      // the list scrolls along X, so extent mirrors the visible fraction
      final total = position.maxScrollExtent + position.viewportDimension;
      expect(controller.scrollMetrics!.extent,
          moreOrLessEquals(position.viewportDimension / total, epsilon: 0.001));

      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
      expect(controller.scrollMetrics!.position,
          moreOrLessEquals(1, epsilon: 0.001));
      expect(controller.scrollMetrics!.currentPage, 4);
    });

    testWidgets('jumpToNormalized moves along the horizontal axis',
        (tester) async {
      final controller = await pumpViewer(tester, layout: horizontal);
      final position = scrollPosition(tester);

      controller.jumpToNormalized(1);
      await tester.pump();
      expect(position.pixels,
          moreOrLessEquals(position.maxScrollExtent, epsilon: 0.5));

      controller.jumpToNormalized(0.5);
      await tester.pump();
      expect(position.pixels,
          moreOrLessEquals(position.maxScrollExtent / 2, epsilon: 1));
      expect(controller.scrollMetrics!.position,
          moreOrLessEquals(0.5, epsilon: 0.01));

      controller.jumpToNormalized(0);
      await tester.pump();
      expect(position.pixels, moreOrLessEquals(0, epsilon: 0.5));
    });

    testWidgets('the indicator replaces the stock bar in horizontal layout',
        (tester) async {
      PdfScrollMetrics? seen;
      final controller = await pumpViewer(
        tester,
        layout: horizontal,
        indicator: (context, controller, metrics) {
          seen = metrics;
          return const SizedBox.shrink(key: ValueKey('custom-indicator'));
        },
      );

      // the stock main-axis thumb is gone, the custom indicator is up, and
      // the metrics it receives describe the horizontal axis
      expect(find.byKey(stockThumb), findsNothing);
      expect(find.byKey(const ValueKey('custom-indicator')), findsOneWidget);
      expect(seen, isNotNull);
      expect(seen!.scrollAxis, Axis.horizontal);

      // scrolling horizontally rebuilds the indicator with fresh metrics
      scrollPosition(tester).jumpTo(scrollPosition(tester).maxScrollExtent);
      await tester.pump();
      expect(seen!.position, moreOrLessEquals(1, epsilon: 0.001));
      expect(controller.scrollMetrics!.position,
          moreOrLessEquals(1, epsilon: 0.001));
    });
  });
}
