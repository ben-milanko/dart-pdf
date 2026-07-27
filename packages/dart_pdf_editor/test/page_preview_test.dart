// Low-res fast-scroll previews: pages whose full render is pending (the
// render hold, or simply not interpreted yet) paint a small cached
// raster instead of blank paper - Bluebeam-style. The cache is fed for
// free from on-screen renders and by the viewer's background prerender.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
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

  testWidgets('exact raster cache enforces entry and total pixel budgets',
      (tester) async {
    final document = PdfDocument.open(buildMultiPagePdf(2));
    final first = document.page(0);
    final second = document.page(1);
    final image = await PdfPageRenderer.renderImage(first, pixelRatio: 0.5);
    addTearDown(image.dispose);
    final pixels = image.width * image.height;
    final cache = PdfPagePreviewCache(
      maxFullRasterPixels: pixels + 1,
      maxFullRasterEntryPixels: pixels,
    );
    addTearDown(cache.dispose);

    void put(int index, PdfPage page) => cache.putFullImage(
          index,
          page,
          image,
          pageColor: const Color(0xFFFFFFFF),
          annotations: true,
          rotation: null,
        );

    put(0, first);
    expect(cache.debugFullRasterPixels, pixels);
    put(1, second);
    expect(cache.debugFullRasterPixels, pixels,
        reason: 'the second exact raster evicts the first under the budget');
    expect(
      cache.fullImageFor(
        0,
        first,
        width: image.width,
        height: image.height,
        pageColor: const Color(0xFFFFFFFF),
        annotations: true,
        rotation: null,
      ),
      isNull,
    );
    final retained = cache.fullImageFor(
      1,
      second,
      width: image.width,
      height: image.height,
      pageColor: const Color(0xFFFFFFFF),
      annotations: true,
      rotation: null,
    );
    expect(retained, isNotNull);
    retained!.dispose();

    final rejecting = PdfPagePreviewCache(
      maxFullRasterPixels: pixels,
      maxFullRasterEntryPixels: pixels - 1,
    );
    addTearDown(rejecting.dispose);
    rejecting.putFullImage(
      0,
      first,
      image,
      pageColor: const Color(0xFFFFFFFF),
      annotations: true,
      rotation: null,
    );
    expect(rejecting.debugFullRasterPixels, 0,
        reason: 'oversized pages remain on the scheduled render path');
  });

  testWidgets('byte policy raises and trims the visited-page raster cache',
      (tester) async {
    final document = PdfDocument.open(buildMultiPagePdf(2));
    final first = document.page(0);
    final second = document.page(1);
    final image = await PdfPageRenderer.renderImage(first, pixelRatio: 0.5);
    addTearDown(image.dispose);
    final imageBytes = image.width * image.height * 4;
    final cache = PdfPagePreviewCache();
    addTearDown(cache.dispose);

    cache.configureFullRasterCache(PdfPageRasterCachePolicy(
      maxBytes: imageBytes * 2,
      maxEntryBytes: imageBytes,
    ));
    expect(cache.maxFullRasterBytes, imageBytes * 2);
    cache.putFullImage(
      0,
      first,
      image,
      pageColor: const Color(0xFFFFFFFF),
      annotations: true,
      rotation: null,
    );
    cache.putFullImage(
      1,
      second,
      image,
      pageColor: const Color(0xFFFFFFFF),
      annotations: true,
      rotation: null,
    );
    expect(cache.fullRasterCount, 2);
    expect(cache.fullRasterBytes, imageBytes * 2);

    cache.configureFullRasterCache(PdfPageRasterCachePolicy(
      maxBytes: imageBytes,
      maxEntryBytes: imageBytes,
    ));
    expect(cache.fullRasterCount, 1,
        reason: 'lowering the total budget trims the LRU immediately');
    expect(cache.fullRasterBytes, imageBytes);

    cache.configureFullRasterCache(PdfPageRasterCachePolicy(
      maxBytes: imageBytes,
      maxEntryBytes: imageBytes - 1,
    ));
    expect(cache.fullRasterCount, 0,
        reason: 'lowering the entry limit drops oversized retained pages');
  });

  test('visited-page rasters join and leave process-wide accounting', () {
    final registry = PdfCacheRegistry.instance;
    final before = registry.registrationCount;
    final cache = PdfPagePreviewCache();

    cache.configureFullRasterCache(const PdfPageRasterCachePolicy());
    expect(registry.registrationCount, before + 1);
    expect(
      registry.snapshot().where((row) => row.label == 'page-full-raster'),
      isNotEmpty,
    );

    cache.dispose();
    expect(registry.registrationCount, before);
  });

  testWidgets('viewer applies page raster policy updates', (tester) async {
    final document = PdfDocument.open(buildClassicPdf());
    final controller = PdfViewerController();
    addTearDown(controller.dispose);
    const generous = PdfPageRasterCachePolicy(
      maxBytes: 5 * 1024 * 1024 * 1024,
      maxEntryBytes: 64 * 1024 * 1024,
    );

    Widget viewer(PdfPageRasterCachePolicy policy) => MaterialApp(
          home: PdfViewer(
            document: document,
            controller: controller,
            pageRasterCachePolicy: policy,
          ),
        );

    await tester.pumpWidget(viewer(generous));
    expect(controller.pagePreviewCache!.maxFullRasterBytes,
        generous.maxBytes);

    await tester
        .pumpWidget(viewer(const PdfPageRasterCachePolicy.disabled()));
    expect(controller.pagePreviewCache!.maxFullRasterBytes, 0);
    expect(controller.pagePreviewCache!.fullRasterCount, 0);
  });

  testWidgets('rebind drops previews of pages whose content changed',
      (tester) async {
    // A same-geometry edit revision rebinds previews to the new page objects
    // without re-rendering - except pages whose content actually changed (a
    // redaction burn), whose stale previews must be dropped so a fast scroll
    // can't flash the removed content.
    final document = PdfDocument.open(buildMultiPagePdf(3));
    final cache = PdfPagePreviewCache();
    addTearDown(cache.dispose);
    await tester.runAsync(() async {
      for (var i = 0; i < 3; i++) {
        await cache.renderPreview(i, document.page(i));
      }
    });
    expect(cache.has(0) && cache.has(1) && cache.has(2), isTrue);

    final next = PdfDocument.open(buildMultiPagePdf(3));
    final pages = [for (var i = 0; i < 3; i++) next.page(i)];
    cache.rebind(pages, changed: (i) => i == 1);

    // the changed page's stale preview is gone; the rest rebind to the new
    // page objects (so an on-screen render still treats them as fresh)
    expect(cache.has(1), isFalse, reason: 'changed page dropped, not rebound');
    expect(cache.has(0), isTrue);
    expect(cache.has(2), isTrue);
    expect(cache.isFresh(0, pages[0]), isTrue);
    expect(cache.isFresh(2, pages[2]), isTrue);
    // a dropped page is no longer fresh, so its next on-screen render refills
    // it (in the buggy rebind path it stayed "fresh" and could never refresh)
    expect(cache.isFresh(1, pages[1]), isFalse);
  });

  testWidgets('vector-first prerender upgrades to a full preview',
      (tester) async {
    final document = PdfDocument.open(buildClassicPdf());
    final page = document.page(0);
    final cache = PdfPagePreviewCache();
    final worker = _PreviewWorker();
    addTearDown(cache.dispose);

    await tester.runAsync(() =>
        cache.renderPreview(0, page, worker: worker, decodeImages: false));
    expect(worker.calls.single, (0, false, null));
    expect(cache.isFresh(0, page), isTrue,
        reason: 'a vector preview is good enough to paint while held');
    expect(cache.isFresh(0, page, requireImages: true), isFalse,
        reason: 'it must not suppress the later full-image warm');

    await tester.runAsync(
        () => cache.renderPreview(0, page, worker: worker, decodeImages: true));
    expect(worker.calls.last.$2, isTrue);
    expect(worker.calls.last.$3, isNotNull,
        reason: 'full preview decodes at the low preview ratio');
    expect(cache.isFresh(0, page, requireImages: true), isTrue);
  });

  testWidgets('command-limited previews stay partial without image draws',
      (tester) async {
    final document = PdfDocument.open(buildClassicPdf());
    final page = document.page(0);
    final cache = PdfPagePreviewCache();
    final worker = _VectorOnlyWorker();
    addTearDown(cache.dispose);

    await tester.runAsync(() => cache.renderPreview(0, page,
        worker: worker, decodeImages: false, commandLimit: 2000));

    expect(worker.commandLimits, [2000]);
    expect(cache.isFresh(0, page), isTrue);
    expect(cache.isFresh(0, page, requireImages: true), isFalse,
        reason: 'a capped command prefix must not masquerade as complete');
  });

  testWidgets('vector preview defers UI replay while motion is active',
      (tester) async {
    final document = PdfDocument.open(buildClassicPdf());
    final page = document.page(0);
    final cache = PdfPagePreviewCache();
    final worker = _VectorOnlyWorker();
    addTearDown(cache.dispose);

    var moving = true;
    await tester.runAsync(() => cache.renderPreview(0, page,
        worker: worker,
        decodeImages: false,
        commandLimit: 2000,
        deferUiWork: () => moving));

    expect(worker.commandLimits, [2000]);
    expect(cache.has(0), isFalse,
        reason: 'worker results must not replay/rasterize on the UI side '
            'during a live pan');

    moving = false;
    await tester.runAsync(() => cache.renderPreview(0, page,
        worker: worker,
        decodeImages: false,
        commandLimit: 2000,
        deferUiWork: () => moving));
    expect(worker.commandLimits, [2000, 2000]);
    expect(cache.isFresh(0, page), isTrue);
  });

  testWidgets('full page renders upgrade vector-only previews', (tester) async {
    final document = PdfDocument.open(buildClassicPdf());
    final page = document.page(0);
    final cache = PdfPagePreviewCache();
    final worker = _PreviewWorker();
    addTearDown(cache.dispose);

    await tester.runAsync(() =>
        cache.renderPreview(0, page, worker: worker, decodeImages: false));
    expect(cache.isFresh(0, page), isTrue);
    expect(cache.isFresh(0, page, requireImages: true), isFalse);

    await tester.runAsync(() async {
      final picture = await PdfPageRenderer.renderPicture(page);
      try {
        await cache.putFromPicture(0, page, picture);
      } finally {
        picture.dispose();
      }
    });

    expect(cache.isFresh(0, page, requireImages: true), isTrue,
        reason: 'the completed on-screen render must replace vector previews');
  });

  testWidgets('worker-declined vector prefetch does not render locally',
      (tester) async {
    final document = PdfDocument.open(buildClassicPdf());
    final page = document.page(0);
    final cache = PdfPagePreviewCache();
    final worker = _DecliningWorker();
    addTearDown(cache.dispose);

    await tester.runAsync(() =>
        cache.renderPreview(0, page, worker: worker, decodeImages: false));

    expect(worker.calls, [(0, false, null)]);
    expect(cache.has(0), isFalse,
        reason: 'vector prefetch must skip pages the worker declines');
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

  testWidgets('a recycled page restores its exact raster through render hold',
      (tester) async {
    final document = PdfDocument.open(buildClassicPdf());
    final page = document.page(0);
    final cache = PdfPagePreviewCache();
    addTearDown(cache.dispose);

    Widget pageView({PdfPageRenderScheduler? scheduler}) => MaterialApp(
          home: Center(
            child: SizedBox(
              width: 400,
              child: PdfPageView(
                page: page,
                previewCache: cache,
                renderScheduler: scheduler,
              ),
            ),
          ),
        );

    // First visit pays the normal interpret + GPU readback and leaves an
    // exact, bounded cache entry above the lazy page widget.
    await tester.pumpWidget(pageView());
    for (var i = 0;
        i < 50 &&
            (fullRaster.evaluate().isEmpty || cache.debugFullRasterPixels == 0);
        i++) {
      await settle(tester);
    }
    expect(fullRaster, findsOneWidget);
    expect(cache.debugFullRasterPixels, greaterThan(0));

    // Simulate the lazy list disposing the off-screen page, then revisit it
    // while fast-scroll hold is still raised. Reuse is safe ahead of the
    // scheduler because this exact physical-size raster already exists.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    final scheduler = PdfPageRenderScheduler()..holding = true;
    addTearDown(scheduler.dispose);
    await tester.pumpWidget(pageView(scheduler: scheduler));
    await tester.pump();
    await tester.pump();

    expect(fullRaster, findsOneWidget,
        reason: 'the recent exact raster should replace blur immediately');
    expect(previewRaster, findsNothing);
    expect(scheduler.hasPending, isFalse,
        reason: 'a cache hit must not wait for scroll-settle release');
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

  testWidgets('prerender warms previews of pages never seen on screen',
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
          // Warm the whole 8-page doc so the far pages (6, 7) pre-render from
          // idle; the default window is deliberately small (it bounds the
          // worker-decode flood) and would not reach distance 7.
          previewWindow: 8,
        ),
      ),
    ));
    await tester.pump();

    // the background prerender reaches the far pages while the viewer
    // idles - pages 6 and 7 have never been built
    final cache = controller.debugPreviewCache!;
    for (var i = 0; i < 100 && !(cache.has(6) && cache.has(7)); i++) {
      await settle(tester);
    }
    expect(cache.has(6), isTrue);
    expect(cache.has(7), isTrue);

    // A long jump now lands directly on the destination and may render it
    // fully right away. The contract this test pins is the background warm:
    // far pages received previews before they were ever built on screen.
    unawaited(controller.jumpToPage(6));
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
    // interleaving would stall the clock) - the settle restarts the loop,
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

  testWidgets('large documents shrink the full-image preview window',
      (tester) async {
    final document = PdfDocument.open(buildMultiPagePdf(80));
    final controller = PdfViewerController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          document: document,
          controller: controller,
          initialFit: PdfViewerFit.width,
          previewWindow: 8,
        ),
      ),
    ));
    await tester.pump();

    // Large documents cap full-image background warming to ±3 pages even when
    // the configured window is wider. Vector-only passes still use the wider
    // window during fast scrolling, but they do not count as image-fresh.
    final cache = controller.debugPreviewCache!;
    for (var i = 0; i < 100 && !cache.has(3); i++) {
      await settle(tester);
    }
    expect(cache.has(3), isTrue, reason: 'inside the adaptive ±3 window');
    for (var i = 0; i < 30; i++) {
      await settle(tester);
    }
    expect(cache.isFresh(8, document.page(8), requireImages: true), isFalse,
        reason: 'outside the adaptive full-image window');
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

    // scroll the far page onto screen - its full render feeds the cache for
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

  testWidgets('pagePreviews: false disables preview warming', (tester) async {
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
    // The fast-scroll hold now waits for a full 500 ms of quiet before the
    // sharp render starts. No preview should appear while that timer runs.
    await tester.pump(const Duration(milliseconds: 550));
    expect(controller.debugPreviewCache!.has(6), isFalse);
    expect(previewRaster, findsNothing);
    for (var i = 0; i < 50 && fullRaster.evaluate().isEmpty; i++) {
      await settle(tester);
    }
    expect(fullRaster, findsWidgets);
  });
}

class _PreviewWorker extends PdfRenderWorker {
  final calls = <(int, bool, double?)>[];

  @override
  bool get isActive => true;

  @override
  Future<List<PdfRenderCommand>?> record(int pageIndex,
      {bool annotations = true,
      int priority = 0,
      double? imagePixelRatio,
      bool decodeImages = true,
      int? commandLimit,
      PdfRect? imageDecodeRegion, PdfPartialRecordSink? onPartial}) async {
    calls.add((pageIndex, decodeImages, imagePixelRatio));
    final request = PdfImageRequest(
      stream: CosStream(CosDictionary(), Uint8List(0)),
      transform: PdfMatrix.identity,
      decoded: decodeImages
          ? PdfDecodedPixels(Uint8List.fromList([0, 0, 0, 255]), 1, 1)
          : null,
    );
    return [PdfDrawImageCommand(request)];
  }

  @override
  void cancel(int pageIndex, {int priority = 0}) {}

  @override
  void dispose() {}
}

class _DecliningWorker extends PdfRenderWorker {
  final calls = <(int, bool, double?)>[];

  @override
  bool get isActive => true;

  @override
  Future<List<PdfRenderCommand>?> record(int pageIndex,
      {bool annotations = true,
      int priority = 0,
      double? imagePixelRatio,
      bool decodeImages = true,
      int? commandLimit,
      PdfRect? imageDecodeRegion, PdfPartialRecordSink? onPartial}) async {
    calls.add((pageIndex, decodeImages, imagePixelRatio));
    return null;
  }

  @override
  void cancel(int pageIndex, {int priority = 0}) {}

  @override
  void dispose() {}
}

class _VectorOnlyWorker extends PdfRenderWorker {
  final commandLimits = <int?>[];

  @override
  bool get isActive => true;

  @override
  Future<List<PdfRenderCommand>?> record(int pageIndex,
      {bool annotations = true,
      int priority = 0,
      double? imagePixelRatio,
      bool decodeImages = true,
      int? commandLimit,
      PdfRect? imageDecodeRegion, PdfPartialRecordSink? onPartial}) async {
    commandLimits.add(commandLimit);
    return const [PdfSaveCommand(), PdfRestoreCommand()];
  }

  @override
  void cancel(int pageIndex, {int priority = 0}) {}

  @override
  void dispose() {}
}
