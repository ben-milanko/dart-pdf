import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  const thumb = ValueKey('pdf-scrollbar-thumb');

  Future<PdfViewerController> pumpViewer(WidgetTester tester,
      {int pages = 5, PdfViewerFit fit = PdfViewerFit.width}) async {
    final controller = PdfViewerController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          initialFit: fit,
          document: PdfDocument.open(buildMultiPagePdf(pages)),
          controller: controller,
        ),
      ),
    ));
    await tester.pump();
    return controller;
  }

  ScrollPosition scrollPosition(WidgetTester tester) =>
      tester.state<ScrollableState>(find.byType(Scrollable).first).position;

  testWidgets('shows a thumb when the document overflows', (tester) async {
    await pumpViewer(tester);
    expect(find.byKey(thumb), findsOneWidget);

    // thumb height reflects the visible fraction: 600px viewport over
    // 5 fit-width pages (5·800·792/612 + spacing) ≈ 11% - but never
    // under the 36px minimum
    final height = tester.getSize(find.byKey(thumb)).height;
    final position = scrollPosition(tester);
    final total = position.maxScrollExtent + position.viewportDimension;
    expect(height,
        closeTo((600 * position.viewportDimension / total).clamp(36, 600), 1));
  });

  testWidgets('hides when the whole document fits', (tester) async {
    // fit-page on a single page: everything visible, nothing to scroll
    await pumpViewer(tester, pages: 1, fit: PdfViewerFit.page);
    expect(find.byKey(thumb), findsNothing);
  });

  testWidgets('tracks the scroll position', (tester) async {
    await pumpViewer(tester);
    final before = tester.getTopLeft(find.byKey(thumb)).dy;
    expect(before, 0);

    scrollPosition(tester).jumpTo(1000);
    await tester.pump();
    expect(tester.getTopLeft(find.byKey(thumb)).dy, greaterThan(before));
  });

  testWidgets('dragging the thumb scrolls the document', (tester) async {
    await pumpViewer(tester);
    final position = scrollPosition(tester);
    expect(position.pixels, 0);

    // a raw gesture: tester.drag spends part of the offset on touch slop
    final gesture =
        await tester.startGesture(tester.getCenter(find.byKey(thumb)));
    await gesture.moveBy(const Offset(0, 100));
    await gesture.up();
    await tester.pump();

    // 100 track px over a (600 − thumb) track maps to the scrollable
    // range. The lazy list revises maxScrollExtent as items build during
    // the scroll, so allow for the estimate drift.
    final thumbHeight = tester.getSize(find.byKey(thumb)).height;
    final total = position.maxScrollExtent + position.viewportDimension;
    final expected =
        100 * (total - position.viewportDimension) / (600 - thumbHeight);
    expect(position.pixels, closeTo(expected, 25));
    // let the viewer's scroll-settle timer fire before teardown
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('tapping the track jumps toward that position', (tester) async {
    await pumpViewer(tester);
    final position = scrollPosition(tester);

    final bar = tester.getTopRight(find.byType(PdfViewer));
    await tester.tapAt(Offset(bar.dx - 7, bar.dy + 590));
    // touch taps resolve only after the viewer's double-tap timeout; the
    // lazy list revises maxScrollExtent as the jumped-over items build
    await tester.pump(const Duration(milliseconds: 400));
    expect(position.pixels, closeTo(position.maxScrollExtent, 100));

    await tester.tapAt(Offset(bar.dx - 7, bar.dy + 5));
    await tester.pump(const Duration(milliseconds: 400));
    expect(position.pixels, 0);
  });

  testWidgets('a horizontal bar appears while zoomed in and pans the window',
      (tester) async {
    const hThumb = ValueKey('pdf-hscrollbar-thumb');
    final controller = await pumpViewer(tester);
    expect(find.byKey(hThumb), findsNothing,
        reason: 'no sideways overflow at fit-width');

    // double-tap (touch) zooms in around the tap point
    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(const Offset(400, 300));
    await tester.pumpAndSettle();
    expect(controller.zoom, greaterThan(1.5));
    expect(find.byKey(hThumb), findsOneWidget);

    // thumb width is the visible fraction of the inset (800 − 14) track.
    // The horizontal bar reflects the transform scale, not the px/pt zoom:
    // public zoom is px/pt (= transform scale × fit-width), so divide it
    // back out (fit-width = 800/612 for this 612pt page in the 800px view).
    const fitWidth = 800 / 612;
    final transformScale = controller.zoom / fitWidth;
    expect(tester.getSize(find.byKey(hThumb)).width,
        closeTo((800 - 14) / transformScale, 1));

    final before = controller.visiblePageRegion(0)!.left;
    final gesture =
        await tester.startGesture(tester.getCenter(find.byKey(hThumb)));
    await gesture.moveBy(const Offset(60, 0));
    await gesture.up();
    await tester.pump();
    expect(controller.visiblePageRegion(0)!.left, greaterThan(before));

    // zooming back out removes it
    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(const Offset(400, 300));
    await tester.pumpAndSettle();
    expect(find.byKey(hThumb), findsNothing);
  });
}
