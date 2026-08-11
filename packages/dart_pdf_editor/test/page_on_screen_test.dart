import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

/// [PdfPageView.onScreen] - the visibility flag the prefetch economies key on
/// (#657).
///
/// Focus ([PdfPageView.focusDistance]) is the single page under the viewport
/// *centre*, so on any document whose pages are taller than the viewport there
/// is a second page filling half the screen at distance 1. Treating that page
/// as an off-screen prefetch neighbour is what softened it (reduced-resolution
/// image decodes) and blanked it (live-raster reclaim) as it crossed the screen
/// edge on large-format scans.
void main() {
  // 800x600 test surface, 612x792pt pages at fit-width: each page is
  // 792 * 800/612 = 1035.3px tall, and pages start 12px (pageSpacing) apart.
  const pageExtent = 792 * 800 / 612;
  const pageSpacing = 12.0;

  Future<PdfViewerController> pumpViewer(WidgetTester tester,
      {int pages = 5}) async {
    final controller = PdfViewerController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          initialFit: PdfViewerFit.width,
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

  /// The mounted page views by page index. The lazy list only builds pages
  /// inside its cache window, so far pages are simply absent - and the ones
  /// inside it but past the viewport edge are offstage, which is exactly the
  /// prefetch band under test.
  Map<int, PdfPageView> mountedPages(WidgetTester tester) => {
        for (final view in tester.widgetList<PdfPageView>(
            find.byType(PdfPageView, skipOffstage: false)))
          view.previewIndex: view,
      };

  Future<void> scrollTo(WidgetTester tester, double offset) async {
    scrollPosition(tester).jumpTo(offset);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('a page sharing the screen with the current one stays on screen',
      (tester) async {
    final controller = await pumpViewer(tester);
    // Straddle the boundary: the viewport spans [800, 1400], page 0 occupies
    // [0, 1035.3] and page 1 [1047.3, 2082.6]. Both are on screen, but the
    // centre (1100) is on page 1, so page 0 sits at focus distance 1 - the
    // exact shape that used to soften and blank it.
    await scrollTo(tester, 800);
    expect(controller.currentPage, 1,
        reason: 'the viewport centre has moved onto page 1');

    final pages = mountedPages(tester);
    expect(pages[0], isNotNull);
    expect(pages[0]!.onScreen, isTrue,
        reason: 'page 0 still fills the top of the viewport');
    expect(pages[1]!.onScreen, isTrue);
    expect(pages[0]!.qualityPageCount, 2);
    expect(pages[1]!.qualityPageCount, 2,
        reason: 'both pages must divide shared foreground render caches');
    // Deliberately not asserting page 0's focusDistance here. Focus reaches
    // the page views on the viewer's own rebuild (the scroll/transform
    // settle), so mid-scroll it is stale by design - which is exactly why the
    // prefetch economies must not be the thing keyed on it.
  });

  testWidgets('a prefetched page just past the edge is not on screen',
      (tester) async {
    await pumpViewer(tester);
    // Viewport [440, 1040]. Page 1 starts at 1047.3 - just outside the
    // viewport but inside the list's cache window, so it is built offstage as
    // a prefetch neighbour.
    await scrollTo(tester, 440);

    final pages = mountedPages(tester);
    expect(pages[0]!.onScreen, isTrue);
    expect(pages[0]!.qualityPageCount, 1);
    expect(pages[1], isNotNull,
        reason: 'the page below is prefetched into the cache window');
    expect(pages[1]!.onScreen, isFalse);
  });

  testWidgets('onScreen tracks the viewer\'s own visibility measurement',
      (tester) async {
    final controller = await pumpViewer(tester, pages: 6);
    // Sweep across a couple of page boundaries and hold the flag to the same
    // truth the thumbnail strip's viewport indicator reads
    // (PdfViewerController.visiblePageRegion), so the two can never disagree
    // about what "visible" means.
    for (final offset in [
      0.0,
      350.0,
      440.0,
      800.0,
      pageExtent + pageSpacing,
      2 * (pageExtent + pageSpacing) - 200,
      3 * (pageExtent + pageSpacing),
    ]) {
      await scrollTo(tester, offset);
      final pages = mountedPages(tester);
      expect(pages, isNotEmpty);
      for (final entry in pages.entries) {
        expect(entry.value.onScreen,
            controller.visiblePageRegion(entry.key) != null,
            reason: 'page ${entry.key} at scroll offset $offset');
      }
    }
  });

  testWidgets('the span is measured on a document that never scrolls',
      (tester) async {
    // Opening a document calls neither the scroll nor the transform listener,
    // so the span has to be taken once the first layout's extents exist -
    // otherwise the pages behind the fold read as on screen forever and never
    // get the prefetch reduction.
    //
    // A 300px-wide viewer makes each page 388px tall, so two fit on screen at
    // rest and a third sits in the cache window below them - the arrangement
    // the full-width fixture can't produce (there, page 1 is not even built
    // until it approaches).
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            height: 600,
            child: PdfViewer(
              initialFit: PdfViewerFit.width,
              document: PdfDocument.open(buildMultiPagePdf(5)),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();

    final pages = mountedPages(tester);
    expect(pages[0]!.onScreen, isTrue);
    expect(pages[1]!.onScreen, isTrue);
    expect(pages[2], isNotNull,
        reason: 'page 2 is prefetched into the cache window');
    expect(pages[2]!.onScreen, isFalse,
        reason: 'page 2 starts below the fold and was never scrolled to');
  });

  testWidgets('the flag reaches the page before the scroll settles',
      (tester) async {
    // The viewer used to rebuild its page views only on the 500ms scroll
    // settle, so a page crossing the edge kept its stale prefetch treatment
    // for the whole gesture and then re-rendered. A single frame after the
    // scroll is enough now.
    await pumpViewer(tester);
    scrollPosition(tester).jumpTo(800);
    await tester.pump();

    final pages = mountedPages(tester);
    expect(pages[1], isNotNull);
    expect(pages[1]!.onScreen, isTrue);
  });
}
