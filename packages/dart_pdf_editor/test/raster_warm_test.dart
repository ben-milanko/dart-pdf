// Idle full-resolution page-raster warming (#614): the viewer spends genuine
// idle time baking the exact, display-sized raster a page will ask for when it
// arrives, so navigation paints immediately instead of interpreting and
// reading back first.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  /// Lets the real async renderer make progress, then pumps a frame with the
  /// clock advanced - the warm's idle countdown is a [Timer], so a zero-length
  /// pump would never let it fire.
  Future<void> settle(WidgetTester tester) async {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 10));
  }

  // previews are <=200px on their longest side; full rasters are far bigger
  final previewRaster = find.byWidgetPredicate((w) =>
      w is RawImage &&
      w.image != null &&
      w.image!.width <= 200 &&
      w.image!.height <= 200);
  final fullRaster = find.byWidgetPredicate((w) =>
      w is RawImage &&
      w.image != null &&
      (w.image!.width > 200 || w.image!.height > 200));

  /// A warm policy that fires almost immediately, so a test does not spend the
  /// production idle delay in real time.
  const eager = Duration(milliseconds: 1);

  Widget viewer(
    PdfDocument document,
    PdfViewerController controller, {
    required PdfPageRasterWarmPolicy warm,
    PdfPageRasterCachePolicy cache = const PdfPageRasterCachePolicy(
      maxBytes: 512 * 1024 * 1024,
      maxEntryBytes: 64 * 1024 * 1024,
    ),
  }) =>
      MaterialApp(
        home: Scaffold(
          body: PdfViewer(
            document: document,
            controller: controller,
            initialFit: PdfViewerFit.width,
            pageRasterCachePolicy: cache,
            pageRasterWarmPolicy: warm,
          ),
        ),
      );

  /// Pumps until [test] passes or the budget runs out.
  Future<void> pumpUntil(WidgetTester tester, bool Function() test,
      {int rounds = 120}) async {
    for (var i = 0; i < rounds && !test(); i++) {
      await settle(tester);
    }
  }

  testWidgets('an idle-warmed page paints its exact raster on arrival',
      (tester) async {
    final document = PdfDocument.open(buildMultiPagePdf(6));
    final controller = PdfViewerController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(viewer(
      document,
      controller,
      warm: const PdfPageRasterWarmPolicy.document(idleDelay: eager),
    ));
    await tester.pump();

    // Idle time alone fills the exact-raster cache for pages the user has
    // never visited - no scroll, no navigation, no page widget ever built for
    // them.
    await pumpUntil(
        tester, () => (controller.pageRasterWarmStats?.completions ?? 0) >= 5);
    final warmed = controller.pageRasterWarmStats!;
    expect(warmed.completions, greaterThanOrEqualTo(5),
        reason: 'the warm reaches off-screen pages while the viewer idles');
    expect(warmed.warmedBytes, greaterThan(0));
    expect(warmed.retainedBytes, greaterThan(0));

    // Arrive on a warmed page. A cache hit is served synchronously by
    // _restoreFullRaster, ahead of the render scheduler; a fresh render is a
    // worker/interpret round trip plus a GPU readback and could not possibly
    // land in one frame. So a full raster present after a single pump is proof
    // the warmed entry was reused rather than re-produced.
    final hitsBefore = warmed.hits;
    unawaited(controller.jumpToPage(4));
    await tester.pump();
    await tester.pump();

    expect(fullRaster, findsWidgets,
        reason: 'the warmed raster paints without a new interpretation');
    expect(previewRaster, findsNothing,
        reason: 'a warmed page never shows the soft low-resolution preview');
    expect(controller.pageRasterWarmStats!.hits, greaterThan(hitsBefore));
  });

  testWidgets('disabled mode performs no background full-raster work',
      (tester) async {
    final document = PdfDocument.open(buildMultiPagePdf(6));
    final controller = PdfViewerController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(viewer(
      document,
      controller,
      warm: const PdfPageRasterWarmPolicy.disabled(),
    ));
    await tester.pump();

    for (var i = 0; i < 20; i++) {
      await settle(tester);
    }
    // Belt and braces: even asked directly, a disabled policy warms nothing.
    await tester.runAsync(controller.debugWarmFullRasters);

    final stats = controller.pageRasterWarmStats!;
    expect(stats.attempts, 0);
    expect(stats.completions, 0);
    expect(stats.warmedBytes, 0);
    expect(controller.debugRasterWarming, isFalse);
  });

  testWidgets('nearby mode stays inside its window', (tester) async {
    final document = PdfDocument.open(buildMultiPagePdf(12));
    final controller = PdfViewerController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(viewer(
      document,
      controller,
      warm: const PdfPageRasterWarmPolicy.nearby(window: 2, idleDelay: eager),
    ));
    await tester.pump();

    for (var i = 0; i < 40; i++) {
      await settle(tester);
    }
    final stats = controller.pageRasterWarmStats!;
    // From page 0 the window reaches at most pages 1 and 2, and pages inside
    // the live build window are excluded (they render on their own).
    expect(stats.completions, lessThanOrEqualTo(2));
    expect(stats.entries, lessThanOrEqualTo(3),
        reason: 'far pages are never warmed under a nearby policy');
  });

  testWidgets('an inadmissible page is declined before it is rendered',
      (tester) async {
    final document = PdfDocument.open(buildMultiPagePdf(6));
    final controller = PdfViewerController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(viewer(
      document,
      controller,
      warm: const PdfPageRasterWarmPolicy.document(idleDelay: eager),
      // room for a thumbnail, nowhere near a display-sized page raster
      cache: const PdfPageRasterCachePolicy(
        maxBytes: 64 * 1024,
        maxEntryBytes: 64 * 1024,
      ),
    ));
    await tester.pump();

    await pumpUntil(
        tester, () => (controller.pageRasterWarmStats?.rejected ?? 0) > 0);
    final stats = controller.pageRasterWarmStats!;
    expect(stats.rejected, greaterThan(0),
        reason: 'the policy cannot admit a page raster this size');
    expect(stats.attempts, 0,
        reason: 'the decision is taken before any interpretation');
    expect(stats.completions, 0);
    expect(stats.retainedBytes, lessThanOrEqualTo(64 * 1024));
  });

  testWidgets('scrolling preempts warming', (tester) async {
    final document = PdfDocument.open(buildMultiPagePdf(12));
    final controller = PdfViewerController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(viewer(
      document,
      controller,
      warm: const PdfPageRasterWarmPolicy.document(idleDelay: eager),
    ));
    await tester.pump();
    await pumpUntil(
        tester, () => (controller.pageRasterWarmStats?.completions ?? 0) >= 1);
    expect(
        controller.pageRasterWarmStats!.completions, greaterThanOrEqualTo(1));

    // A scroll raises the viewer's motion hold and its 500ms quiet window; the
    // warm must stand down for the whole of it rather than landing a replay
    // and a GPU readback on top of a scrolling frame.
    await tester.drag(find.byType(PdfViewer), const Offset(0, -400));
    await tester.pump();
    final during = controller.pageRasterWarmStats!.completions;
    await tester.runAsync(controller.debugWarmFullRasters);
    expect(controller.pageRasterWarmStats!.completions, during,
        reason: 'no page is warmed while the viewer is in motion');
    expect(controller.debugRasterWarming, isFalse);

    // ...and picks itself back up once things settle.
    await pumpUntil(
        tester, () => controller.pageRasterWarmStats!.completions > during);
    expect(controller.pageRasterWarmStats!.completions, greaterThan(during),
        reason: 'the settle restarts the pass');
  });

  testWidgets('a warm respects the byte budget and evicts under it',
      (tester) async {
    final document = PdfDocument.open(buildMultiPagePdf(12));
    final controller = PdfViewerController();
    addTearDown(controller.dispose);
    // Big enough to admit a page, small enough that a 12-page document cannot
    // all fit: the warm must settle into a moving window, not grow past it.
    const budget = 4 * 1024 * 1024;
    await tester.pumpWidget(viewer(
      document,
      controller,
      warm: const PdfPageRasterWarmPolicy.document(idleDelay: eager),
      cache: const PdfPageRasterCachePolicy(
        maxBytes: budget,
        maxEntryBytes: budget,
      ),
    ));
    await tester.pump();

    for (var i = 0; i < 60; i++) {
      await settle(tester);
      expect(controller.pageRasterWarmStats!.retainedBytes,
          lessThanOrEqualTo(budget),
          reason: 'the warm never exceeds the configured budget');
    }
  });

  group('raster signatures', () {
    /// Everything the signature covers must make a warmed raster unreachable
    /// when it changes - otherwise a page could paint another page's pixels,
    /// the wrong paper, or a stale rotation.
    late PdfDocument document;
    late PdfPage page;
    late ui.Image image;
    late PdfPagePreviewCache cache;

    setUp(() async {
      document = PdfDocument.open(buildMultiPagePdf(2));
      page = document.page(0);
      image = await PdfPageRenderer.renderImage(page, pixelRatio: 0.5);
      cache = PdfPagePreviewCache()
        ..configureFullRasterCache(const PdfPageRasterCachePolicy(
          maxBytes: 64 * 1024 * 1024,
          maxEntryBytes: 64 * 1024 * 1024,
        ));
      cache.putFullImage(
        0,
        page,
        image,
        pageColor: const Color(0xFFFFFFFF),
        annotations: true,
        rotation: null,
      );
    });

    tearDown(() {
      cache.dispose();
      image.dispose();
    });

    ui.Image? lookup({
      int index = 0,
      Color pageColor = const Color(0xFFFFFFFF),
      bool annotations = true,
      int? rotation,
      int? width,
      int? height,
      PdfPage? revision,
    }) =>
        cache.fullImageFor(
          index,
          revision ?? page,
          width: width ?? image.width,
          height: height ?? image.height,
          pageColor: pageColor,
          annotations: annotations,
          rotation: rotation,
        );

    test('the matching signature hits', () {
      final hit = lookup();
      expect(hit, isNotNull);
      hit!.dispose();
    });

    test('paper color is part of the identity', () {
      expect(lookup(pageColor: const Color(0xFFEEE8D5)), isNull);
    });

    test('annotation visibility is part of the identity', () {
      expect(lookup(annotations: false), isNull);
    });

    test('rotation is part of the identity', () {
      expect(lookup(rotation: 90), isNull);
    });

    test('physical size is part of the identity', () {
      expect(lookup(width: image.width + 1), isNull);
      expect(lookup(height: image.height + 1), isNull);
    });

    test('the page index is part of the identity', () {
      expect(lookup(index: 1, revision: document.page(1)), isNull);
    });

    test('a new revision of the page cannot reuse it', () {
      final next = PdfDocument.open(buildMultiPagePdf(2)).page(0);
      expect(lookup(revision: next), isNull);
      expect(cache.fullRasterCount, 0,
          reason: 'and the stale pixels are dropped, not left holding budget');
    });
  });

  test('warm geometry matches what a displayed page asks the cache for', () {
    // The warm bakes a raster at PdfPageRasterGeometry's numbers and the page
    // widget looks one up at the same numbers. If the two ever drift, every
    // warmed page silently becomes a miss - so pin the arithmetic.
    const pageSize = Size(612, 792);
    final ratio = PdfPageRasterGeometry.effectiveRatio(
      pageSize: pageSize,
      layoutWidth: 918, // 1.5x
      devicePixelRatio: 2,
    );
    expect(ratio, closeTo(3.0, 1e-9));
    expect(PdfPageRasterGeometry.dimensions(pageSize, ratio), (1836, 2376));

    // A page far larger than the per-side cap is bounded, not grown without
    // limit - deep zoom is the detail patch's job, not the base raster's.
    final huge = PdfPageRasterGeometry.effectiveRatio(
      pageSize: const Size(20000, 20000),
      layoutWidth: 20000,
      devicePixelRatio: 4,
    );
    expect(huge * 20000, lessThanOrEqualTo(PdfPageRasterGeometry.maxDimension));
  });

  test('warm policies compare and describe themselves', () {
    expect(const PdfPageRasterWarmPolicy.disabled().enabled, isFalse);
    expect(const PdfPageRasterWarmPolicy.nearby().enabled, isTrue);
    expect(const PdfPageRasterWarmPolicy.document().enabled, isTrue);
    expect(const PdfPageRasterWarmPolicy.nearby(window: 3),
        const PdfPageRasterWarmPolicy.nearby(window: 3));
    expect(const PdfPageRasterWarmPolicy.nearby(window: 3),
        isNot(const PdfPageRasterWarmPolicy.nearby(window: 4)));
    expect(const PdfPageRasterWarmPolicy.nearby(window: 3).hashCode,
        const PdfPageRasterWarmPolicy.nearby(window: 3).hashCode);
    expect('${const PdfPageRasterWarmPolicy.document()}', contains('document'));
  });
}
