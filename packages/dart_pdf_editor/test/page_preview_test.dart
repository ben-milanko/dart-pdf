// Low-res fast-scroll previews: pages whose full render is pending (the
// render hold, or simply not interpreted yet) paint a small cached
// raster instead of blank paper — Bluebeam-style. The cache is fed for
// free from on-screen renders and by the viewer's background prerender.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  /// Lets the real async renderer make progress, then pumps a frame.
  Future<void> settle(WidgetTester tester) async {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }

  // previews are ≤200px on their longest side; full rasters are far bigger
  final previewRaster = find.byWidgetPredicate((w) =>
      w is RawImage &&
      w.image != null &&
      w.image!.width <= 200 &&
      w.image!.height <= 200);
  final fullRaster = find.byWidgetPredicate((w) =>
      w is RawImage &&
      w.image != null &&
      (w.image!.width > 200 || w.image!.height > 200));

  testWidgets('cache stores, evicts least-recently-used, clones survive',
      (tester) async {
    final document = PdfDocument.open(buildMultiPagePdf(4));
    final cache = PdfPagePreviewCache(capacity: 2);
    addTearDown(cache.dispose);
    await tester.runAsync(() async {
      for (var i = 0; i < 3; i++) {
        await cache.renderPreview(i, document.page(i));
      }
    });
    expect(cache.has(0), isFalse); // oldest, evicted at capacity 2
    expect(cache.has(1), isTrue);
    expect(cache.has(2), isTrue);

    // a lookup counts as a use: 2 becomes the eviction candidate
    final clone = cache.imageFor(1)!;
    await tester.runAsync(() => cache.renderPreview(3, document.page(3)));
    expect(cache.has(2), isFalse);
    expect(cache.has(1), isTrue);

    // handed-out clones keep their pixels through clear()
    cache.clear();
    expect(cache.has(1), isFalse);
    expect(clone.width, greaterThan(0));
    expect(clone.width, lessThanOrEqualTo(200));
    clone.dispose();
  });

  testWidgets('a held page paints the cached preview, then the full render',
      (tester) async {
    final document = PdfDocument.open(buildClassicPdf());
    final cache = PdfPagePreviewCache();
    addTearDown(cache.dispose);
    await tester.runAsync(() => cache.renderPreview(0, document.page(0)));

    final hold = ValueNotifier<bool>(true);
    addTearDown(hold.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          width: 400,
          child: PdfPageView(
              page: document.page(0), renderHold: hold, previewCache: cache),
        ),
      ),
    ));
    await tester.pump();
    // held: the low-res preview shows instead of blank paper
    expect(previewRaster, findsOneWidget);
    expect(fullRaster, findsNothing);

    hold.value = false;
    for (var i = 0; i < 50 && fullRaster.evaluate().isEmpty; i++) {
      await settle(tester);
    }
    // the full render replaces the preview (which is dropped to free it)
    expect(fullRaster, findsOneWidget);
    expect(previewRaster, findsNothing);
  });

  testWidgets('an on-screen render feeds the cache without re-interpreting',
      (tester) async {
    final document = PdfDocument.open(buildClassicPdf());
    final cache = PdfPagePreviewCache();
    addTearDown(cache.dispose);
    final page = document.page(0);
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
            width: 400, child: PdfPageView(page: page, previewCache: cache)),
      ),
    ));
    for (var i = 0; i < 50 && !cache.isFresh(0, page); i++) {
      await settle(tester);
    }
    expect(cache.isFresh(0, page), isTrue);
  });

  testWidgets('fast scroll shows previews of pages never seen on screen',
      (tester) async {
    final document = PdfDocument.open(buildMultiPagePdf(8));
    final controller = PdfViewerController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          document: document,
          controller: controller,
          initialFit: PdfViewerFit.width,
        ),
      ),
    ));
    await tester.pump();

    // the background prerender reaches the far pages while the viewer
    // idles — pages 6 and 7 have never been built
    final cache = controller.debugPreviewCache!;
    for (var i = 0; i < 100 && !(cache.has(6) && cache.has(7)); i++) {
      await settle(tester);
    }
    expect(cache.has(6), isTrue);
    expect(cache.has(7), isTrue);

    // a long fast jump: full renders stay held, but the destination
    // pages paint their previews instead of blank paper
    unawaited(controller.jumpToPage(6));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 60));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    expect(fullRaster, findsNothing);
    expect(previewRaster, findsWidgets);

    // settled: the destination renders fully
    await tester.pump(const Duration(milliseconds: 300));
    for (var i = 0; i < 50 && fullRaster.evaluate().isEmpty; i++) {
      await settle(tester);
    }
    expect(fullRaster, findsWidgets);
  });

  testWidgets('the prerender warms only a window of pages around the viewport',
      (tester) async {
    final document = PdfDocument.open(buildMultiPagePdf(12));
    final controller = PdfViewerController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          document: document,
          controller: controller,
          initialFit: PdfViewerFit.width,
          previewWindow: 3,
        ),
      ),
    ));
    await tester.pump();

    // a page within the window is warmed by the prerender; a far page is
    // never a candidate, so the loop runs out of work and leaves it cold
    final cache = controller.debugPreviewCache!;
    for (var i = 0; i < 100 && !cache.has(3); i++) {
      await settle(tester);
    }
    expect(cache.has(3), isTrue, reason: 'within ±3 of page 0');
    // give the loop ample idle time to prove it has gone quiet, not just
    // not reached the far page yet
    for (var i = 0; i < 30; i++) {
      await settle(tester);
    }
    expect(cache.has(11), isFalse, reason: 'far outside the window');
  });

  testWidgets('the window recenters as the user navigates', (tester) async {
    final document = PdfDocument.open(buildMultiPagePdf(12));
    final controller = PdfViewerController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          document: document,
          controller: controller,
          initialFit: PdfViewerFit.width,
          previewWindow: 3,
        ),
      ),
    ));
    await tester.pump();
    final cache = controller.debugPreviewCache!;
    for (var i = 0; i < 100 && !cache.has(3); i++) {
      await settle(tester);
    }
    expect(cache.has(11), isFalse);

    // jump to the far end (plain pumps complete the animation; runAsync
    // interleaving would stall the clock) — the settle restarts the loop,
    // which now centers on the new current page and warms its neighbors
    unawaited(controller.jumpToPage(11));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(controller.currentPage, 11);
    for (var i = 0; i < 100 && !cache.has(8); i++) {
      await settle(tester);
    }
    expect(cache.has(8), isTrue, reason: 'within ±3 of page 11 now');
  });

  testWidgets('previewWindow <= 0 warms every page (short-doc behavior)',
      (tester) async {
    final document = PdfDocument.open(buildMultiPagePdf(12));
    final controller = PdfViewerController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          document: document,
          controller: controller,
          initialFit: PdfViewerFit.width,
          previewWindow: 0,
        ),
      ),
    ));
    await tester.pump();
    final cache = controller.debugPreviewCache!;
    // unbounded: the far page is still attempted and warmed
    for (var i = 0; i < 150 && !cache.has(11); i++) {
      await settle(tester);
    }
    expect(cache.has(11), isTrue);
  });

  testWidgets('a visited far page keeps its preview from the on-screen render',
      (tester) async {
    final document = PdfDocument.open(buildMultiPagePdf(12));
    final controller = PdfViewerController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          document: document,
          controller: controller,
          initialFit: PdfViewerFit.width,
          previewWindow: 3,
        ),
      ),
    ));
    await tester.pump();
    final cache = controller.debugPreviewCache!;

    // scroll the far page onto screen — its full render feeds the cache for
    // free (putFromPicture), independent of the prerender window (plain
    // pumps complete the jump; runAsync would stall the animation clock)
    unawaited(controller.jumpToPage(11));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(controller.currentPage, 11);
    for (var i = 0; i < 100 && !cache.has(11); i++) {
      await settle(tester);
    }
    expect(cache.has(11), isTrue);

    // back to the top: page 11 is now outside the ±3 window but its preview
    // survives (capacity 300, no eviction pressure)
    unawaited(controller.jumpToPage(0));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    for (var i = 0; i < 30; i++) {
      await settle(tester);
    }
    expect(cache.has(11), isTrue);
  });

  testWidgets('pagePreviews: false keeps the blank-paper behavior',
      (tester) async {
    final document = PdfDocument.open(buildMultiPagePdf(8));
    final controller = PdfViewerController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          document: document,
          controller: controller,
          initialFit: PdfViewerFit.width,
          pagePreviews: false,
        ),
      ),
    ));
    await tester.pump();
    for (var i = 0; i < 50 && fullRaster.evaluate().isEmpty; i++) {
      await settle(tester);
    }

    unawaited(controller.jumpToPage(6));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 60));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    // no previews anywhere: flown-past and destination pages are blank
    expect(find.byType(RawImage), findsNothing);
    await tester.pump(const Duration(milliseconds: 300));
  });
}
