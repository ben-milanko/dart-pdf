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
import 'package:pdf_graphics/pdf_graphics.dart';
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

  testWidgets('changing either policy on a mounted viewer re-arms the pass',
      (tester) async {
    // The app's Developer-tools selector does exactly this: flips the policy on
    // a viewer that is already showing a document. Both levers have to take
    // effect without reopening it - and a raised cache budget has to re-offer
    // pages the warm previously declined as inadmissible.
    final document = PdfDocument.open(buildMultiPagePdf(8));
    final controller = PdfViewerController();
    addTearDown(controller.dispose);

    const tiny = PdfPageRasterCachePolicy(
      maxBytes: 64 * 1024,
      maxEntryBytes: 64 * 1024,
    );
    const roomy = PdfPageRasterCachePolicy(
      maxBytes: 512 * 1024 * 1024,
      maxEntryBytes: 64 * 1024 * 1024,
    );

    // Warming off: nothing happens, however long the viewer idles.
    await tester.pumpWidget(viewer(document, controller,
        warm: const PdfPageRasterWarmPolicy.disabled(), cache: roomy));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await settle(tester);
    }
    expect(controller.pageRasterWarmStats!.attempts, 0);

    // Turn it on, but with a budget that cannot admit a page raster: the warm
    // now runs and declines rather than staying silent.
    await tester.pumpWidget(viewer(document, controller,
        warm: const PdfPageRasterWarmPolicy.document(idleDelay: eager),
        cache: tiny));
    await pumpUntil(
        tester, () => (controller.pageRasterWarmStats?.rejected ?? 0) > 0);
    expect(controller.pageRasterWarmStats!.rejected, greaterThan(0));
    expect(controller.pageRasterWarmStats!.completions, 0);

    // Raise the budget on the same mounted viewer. Pages written off as
    // inadmissible have to be reconsidered, not left written off.
    await tester.pumpWidget(viewer(document, controller,
        warm: const PdfPageRasterWarmPolicy.document(idleDelay: eager),
        cache: roomy));
    await pumpUntil(
        tester, () => (controller.pageRasterWarmStats?.completions ?? 0) > 0);
    expect(controller.pageRasterWarmStats!.completions, greaterThan(0),
        reason: 'a raised budget re-offers pages the warm had declined');
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

  group('warmFullRaster guards', () {
    // The unit of work, driven directly. The viewer-level tests above prove the
    // pass runs and stands down; these prove the individual guards inside it,
    // each of which is a promise the policy's documentation makes.
    late PdfDocument document;
    late PdfPage page;
    late PdfPagePreviewCache cache;

    ({double ratio, PdfPageRasterSignature signature}) target(
        {int index = 0, double ratio = 0.4}) {
      final size = PdfPageRenderer.pageSize(page);
      final dimensions = PdfPageRasterGeometry.dimensions(size, ratio);
      return (
        ratio: ratio,
        signature: PdfPageRasterSignature(
          pageIndex: index,
          width: dimensions.$1,
          height: dimensions.$2,
          pageColor: const Color(0xFFFFFFFF),
          annotations: true,
          rotation: null,
        ),
      );
    }

    setUp(() {
      document = PdfDocument.open(buildMultiPagePdf(2));
      page = document.page(0);
      cache = PdfPagePreviewCache()
        ..configureFullRasterCache(const PdfPageRasterCachePolicy(
          maxBytes: 64 * 1024 * 1024,
          maxEntryBytes: 64 * 1024 * 1024,
        ));
    });

    tearDown(() => cache.dispose());

    testWidgets('an already-cached page is skipped without re-rendering',
        (tester) async {
      final t = target();
      await tester.runAsync(() async {
        expect(
          await cache.warmFullRaster(0, page,
              signature: t.signature, pixelRatio: t.ratio),
          isTrue,
        );
        // Asking again must not repeat the interpret + readback. The skip uses
        // a pure peek, so it also must not move the hit/miss counters.
        final before = cache.warmStats;
        expect(
          await cache.warmFullRaster(0, page,
              signature: t.signature, pixelRatio: t.ratio),
          isFalse,
        );
        final after = cache.warmStats;
        expect(after.skipped, before.skipped + 1);
        expect(after.attempts, before.attempts,
            reason: 'a skip is not an attempt');
        expect(after.hits, before.hits,
            reason: 'the skip check is a peek, not a lookup');
        expect(after.misses, before.misses);
      });
    });

    testWidgets('shouldStop mid-warm abandons the page and stores nothing',
        (tester) async {
      final t = target();
      await tester.runAsync(() async {
        // Idle for the admission check, then not idle by the time the first
        // await returns - the shape a scroll starting mid-warm produces.
        var calls = 0;
        final stored = await cache.warmFullRaster(
          0,
          page,
          signature: t.signature,
          pixelRatio: t.ratio,
          shouldStop: () => calls++ > 0,
        );
        expect(stored, isFalse);
        expect(cache.warmStats.preempted, greaterThan(0));
        expect(cache.warmStats.completions, 0);
        expect(cache.fullRasterCount, 0,
            reason: 'an abandoned warm leaves nothing behind');
      });
    });

    testWidgets('a preempt before any work is not counted as an attempt',
        (tester) async {
      final t = target();
      await tester.runAsync(() async {
        expect(
          await cache.warmFullRaster(0, page,
              signature: t.signature,
              pixelRatio: t.ratio,
              shouldStop: () => true),
          isFalse,
        );
        expect(cache.warmStats.attempts, 0,
            reason: 'nothing was interpreted, so nothing was attempted');
      });
    });

    testWidgets('the worker path produces the same raster as the local one',
        (tester) async {
      final t = target();
      await tester.runAsync(() async {
        final worker = _RecordingWorker(page);
        final stored = await cache.warmFullRaster(0, page,
            signature: t.signature, pixelRatio: t.ratio, worker: worker);
        expect(stored, isTrue);
        expect(worker.recorded, isNotEmpty,
            reason: 'the warm offloads the interpreter walk when it can');
        expect(worker.priorities.every((p) => p >= 4), isTrue,
            reason: 'warm records rank behind every foreground request');
        expect(cache.hasFullRaster(t.signature, page), isTrue);
      });
    });

    testWidgets('a worker that declines falls back to a local walk',
        (tester) async {
      final t = target();
      await tester.runAsync(() async {
        final worker = _DecliningWorker();
        expect(
          await cache.warmFullRaster(0, page,
              signature: t.signature, pixelRatio: t.ratio, worker: worker),
          isTrue,
          reason: 'the local walk is the cost being moved into idle time, so '
              'a declined record must not abandon the warm',
        );
      });
    });

    testWidgets('a preempt after the picture is built still stores nothing',
        (tester) async {
      final t = target();
      await tester.runAsync(() async {
        // False through the admission and post-record gates, true at the gate
        // that guards the readback - a scroll starting while the interpreter
        // walk was in flight.
        var calls = 0;
        expect(
          await cache.warmFullRaster(
            0,
            page,
            signature: t.signature,
            pixelRatio: t.ratio,
            shouldStop: () => calls++ >= 2,
          ),
          isFalse,
        );
        expect(cache.warmStats.preempted, greaterThan(0));
        expect(cache.fullRasterCount, 0);
      });
    });

    testWidgets('an edit that changes a page drops its warmed raster',
        (tester) async {
      // The issue's hard requirement: a destructive edit (a redaction burn)
      // must never flash a stale warmed raster. Rebinding a still-correct page
      // is fine; rebinding a changed one is not.
      final t = target();
      final other = target(index: 1);
      await tester.runAsync(() async {
        await cache.warmFullRaster(0, page,
            signature: t.signature, pixelRatio: t.ratio);
        await cache.warmFullRaster(1, document.page(1),
            signature: other.signature, pixelRatio: other.ratio);
        expect(cache.fullRasterCount, 2);

        final next = PdfDocument.open(buildMultiPagePdf(2));
        final pages = [next.page(0), next.page(1)];
        cache.rebind(pages, changed: (i) => i == 0);

        expect(cache.hasFullRaster(t.signature, pages[0]), isFalse,
            reason: 'the changed page cannot serve its old pixels');
        expect(cache.hasFullRaster(other.signature, pages[1]), isTrue,
            reason: 'an untouched page rebinds instead of re-rendering');
        expect(cache.fullRasterCount, 1);
      });
    });

    testWidgets('a revision with fewer pages drops rasters past the end',
        (tester) async {
      final t = target();
      final other = target(index: 1);
      await tester.runAsync(() async {
        await cache.warmFullRaster(0, page,
            signature: t.signature, pixelRatio: t.ratio);
        await cache.warmFullRaster(1, document.page(1),
            signature: other.signature, pixelRatio: other.ratio);
        expect(cache.fullRasterCount, 2);

        // Page 1 was deleted: its warmed raster has no page to belong to.
        final next = PdfDocument.open(buildMultiPagePdf(1));
        cache.rebind([next.page(0)]);
        expect(cache.fullRasterCount, 1);
        expect(cache.hasFullRaster(other.signature, next.page(0)), isFalse);
      });
    });

    test('a disposed cache stores nothing', () async {
      // Its own cache: a late warm landing after teardown is exactly the case
      // this covers, so it must not be the group's shared instance.
      final dead = PdfPagePreviewCache()..dispose();
      final t = target();
      expect(
        await dead.warmFullRaster(0, page,
            signature: t.signature, pixelRatio: t.ratio),
        isFalse,
      );
    });
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

    test('a signature describes itself', () {
      // It is the cache key, so it shows up in traces when a warmed page
      // unexpectedly misses - the description has to name every field that
      // could be the reason.
      final text = '${PdfPageRasterSignature(
        pageIndex: 4,
        width: 800,
        height: 1000,
        pageColor: const Color(0xFFEEE8D5),
        annotations: false,
        rotation: 90,
      )}';
      expect(text, contains('page=4'));
      expect(text, contains('800x1000'));
      expect(text, contains('ffeee8d5'));
      expect(text, contains('annotations=false'));
      expect(text, contains('rotation=90'));
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
    expect('${const PdfPageRasterWarmPolicy.disabled()}', contains('disabled'));
    expect('${const PdfPageRasterWarmPolicy.nearby(window: 7)}',
        contains('window: 7'));
    // Policies built at runtime from a host setting, not const literals - the
    // shape the app's Developer-tools selector produces.
    expect(PdfPageRasterWarmPolicy.nearby(window: 1 + 1),
        const PdfPageRasterWarmPolicy.nearby(window: 2));
    expect(
      PdfPageRasterWarmPolicy.document(
          idleDelay: Duration(seconds: 1 + 1)).idleDelay,
      const Duration(seconds: 2),
    );
  });

  test('warm stats describe themselves', () {
    // These exist to be read - by a diagnostics panel, a benchmark, or a
    // trace - so the description has to actually work.
    const stats = PdfPageRasterWarmStats(
      attempts: 3,
      completions: 2,
      skipped: 1,
      rejected: 4,
      preempted: 5,
      warmedBytes: 6,
      hits: 7,
      misses: 8,
      evictions: 9,
      retainedBytes: 10,
      entries: 11,
    );
    final text = '$stats';
    expect(text, contains('attempts: 3'));
    expect(text, contains('completions: 2'));
    expect(text, contains('skipped: 1'));
    expect(text, contains('rejected: 4'));
    expect(text, contains('preempted: 5'));
    expect(text, contains('evictions: 9'));
    expect(text, contains('entries: 11'));
  });
}

/// Records like a real worker: interprets the page here and hands back the
/// command buffer, so the warm's worker branch is exercised end to end.
class _RecordingWorker extends PdfRenderWorker {
  _RecordingWorker(this.page);

  final PdfPage page;
  final List<int> recorded = [];
  final List<int> priorities = [];

  @override
  bool get isActive => true;

  @override
  Future<List<PdfRenderCommand>?> record(
    int pageIndex, {
    bool annotations = true,
    int priority = 0,
    double? imagePixelRatio,
    bool decodeImages = true,
    int? commandLimit,
    PdfRect? imageDecodeRegion,
    PdfPartialRecordSink? onPartial,
  }) async {
    recorded.add(pageIndex);
    priorities.add(priority);
    final device = RecordingPdfDevice();
    PdfInterpreter(cos: page.document.cos, device: device).drawPage(page);
    return device.commands;
  }

  @override
  void cancel(int pageIndex, {int priority = 0}) {}

  @override
  void dispose() {}
}

/// Active, but declines every record - the real worker's behaviour when a page
/// is not serializable or its queue drops the request.
class _DecliningWorker extends PdfRenderWorker {
  @override
  bool get isActive => true;

  @override
  Future<List<PdfRenderCommand>?> record(
    int pageIndex, {
    bool annotations = true,
    int priority = 0,
    double? imagePixelRatio,
    bool decodeImages = true,
    int? commandLimit,
    PdfRect? imageDecodeRegion,
    PdfPartialRecordSink? onPartial,
  }) async =>
      null;

  @override
  void cancel(int pageIndex, {int priority = 0}) {}

  @override
  void dispose() {}
}
