// Precomputed strip plans through StripPdfDevice / PdfRetainedScene:
//
//  - a plan binned headlessly (StripPlanBinner) over the scene's own
//    commands rasterizes byte-identically to the device's local binning,
//    full page and region, with debugVerifyPrecomputed asserting the
//    batch-sequence parity along the way;
//  - a worker-binned plan (native isolate end to end) is byte-identical
//    too - the whole point of the offload;
//  - a doctored/stale plan transparently falls back to local binning
//    (counted in totalPlanMismatches, output still correct);
//  - debug-delegate flags force local binning even when a plan is offered.
//
// Like strip_zoom_router_test, the tester.runAsync raster comparisons run
// before any widget-pumping tests in this file.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/strips.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

import 'strip_zoom_router_test.dart' show buildVectorPdf;
import 'strip_zoom_router_test.dart' as router;

Future<Uint8List> _rgba(ui.Image image) async =>
    (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
        .buffer
        .asUint8List();

Future<StripPlan> _localPlan(PdfRetainedScene scene,
    {required double pixelRatio, Rect? region}) async {
  final geometry = region == null
      ? scene.stripGeometry(pixelRatio: pixelRatio)
      : scene.stripRegionGeometry(region, pixelRatio: pixelRatio);
  final binner = StripPlanBinner(
    pageToDevice: geometry.pageToDevice,
    deviceWidth: geometry.width,
    deviceHeight: geometry.height,
    pixelRatio: pixelRatio,
  );
  await binner.bin(scene.commands);
  return binner.finish();
}

void main() {
  testWidgets('worker-shaped Slug plan paints like local Slug routing',
      (tester) async {
    await tester.runAsync(() async {
      final doc = PdfDocument.open(buildEmbeddedFontPdf());
      final scene = await PdfRetainedScene.record(doc.page(0));
      addTearDown(scene.dispose);
      final geometry = scene.stripGeometry(pixelRatio: 1);
      final binner = StripPlanBinner(
        pageToDevice: geometry.pageToDevice,
        deviceWidth: geometry.width,
        deviceHeight: geometry.height,
        pixelRatio: 1,
        slugGlyphs: true,
      );
      await binner.bin(scene.commands);
      final plan = binner.finish();
      expect(plan.slugBatches, isNotEmpty);

      final plannedPicture = await scene.replayStrips(
          pixelRatio: 1, stripPlan: plan, slugGlyphs: true);
      final localPicture =
          await scene.replayStrips(pixelRatio: 1, slugGlyphs: true);
      final planned =
          await plannedPicture.toImage(geometry.width, geometry.height);
      final local = await localPicture.toImage(geometry.width, geometry.height);
      plannedPicture.dispose();
      localPicture.dispose();
      expect(await _rgba(planned), await _rgba(local));
      planned.dispose();
      local.dispose();
    });
  });

  testWidgets(
      'a precomputed plan rasterizes byte-identically to local '
      'binning (verified batch-by-batch)', (tester) async {
    await tester.runAsync(() async {
      final doc = PdfDocument.open(buildVectorPdf());
      final scene = await PdfRetainedScene.record(doc.page(0));
      addTearDown(scene.dispose);

      for (final ratio in [1.0, 2.4]) {
        final plan = await _localPlan(scene, pixelRatio: ratio);
        expect(plan.batches, isNotEmpty);

        StripPdfDevice.resetStats();
        StripPdfDevice.debugVerifyPrecomputed = true;
        final ui.Image planned;
        try {
          planned =
              await scene.rasterizeStrips(pixelRatio: ratio, stripPlan: plan);
        } finally {
          StripPdfDevice.debugVerifyPrecomputed = false;
        }
        final local = await scene.rasterizeStrips(pixelRatio: ratio);
        expect(StripPdfDevice.totalPlanMismatches, 0);
        expect(await _rgba(planned), await _rgba(local),
            reason: 'plan-fed raster must match local binning at $ratio');
        planned.dispose();
        local.dispose();
      }

      // Region variant, mirrored geometry.
      const region = Rect.fromLTWH(290, 300, 200, 150);
      final regionPlan = await _localPlan(scene, pixelRatio: 2, region: region);
      StripPdfDevice.resetStats();
      final planned = await scene.rasterizeRegionStrips(region,
          pixelRatio: 2, stripPlan: regionPlan);
      final local = await scene.rasterizeRegionStrips(region, pixelRatio: 2);
      expect(StripPdfDevice.totalPlanMismatches, 0);
      expect(StripPdfDevice.totalPlanPictures, 1);
      expect(await _rgba(planned), await _rgba(local));
      planned.dispose();
      local.dispose();
    });
  });

  testWidgets('a worker-binned plan rasterizes byte-identically end to end',
      (tester) async {
    await tester.runAsync(() async {
      final bytes = buildVectorPdf();
      final doc = PdfDocument.open(bytes);
      final page = doc.page(0);
      final worker = PdfRenderWorker.startUncached(bytes);
      addTearDown(worker.dispose);

      final commands = await worker.record(0);
      expect(commands, isNotNull);
      final scene = await PdfRetainedScene.fromCommands(page, commands!);
      addTearDown(scene.dispose);

      const ratio = 2.0;
      final geometry = scene.stripGeometry(pixelRatio: ratio);
      final m = geometry.pageToDevice;
      final plan = await worker.binStrips(0,
          annotations: true,
          pageToDevice: [m.a, m.b, m.c, m.d, m.e, m.f],
          deviceWidth: geometry.width,
          deviceHeight: geometry.height,
          pixelRatio: ratio);
      expect(plan, isNotNull);

      StripPdfDevice.resetStats();
      final planned =
          await scene.rasterizeStrips(pixelRatio: ratio, stripPlan: plan);
      expect(StripPdfDevice.totalPlanMismatches, 0);
      expect(StripPdfDevice.totalPlanPictures, 1,
          reason: 'the worker plan must actually be consumed');
      final local = await scene.rasterizeStrips(pixelRatio: ratio);
      expect(await _rgba(planned), await _rgba(local),
          reason: 'worker-binned plan must raster like a local bin');
      planned.dispose();
      local.dispose();
    });
  });

  testWidgets('a desynced plan falls back to local binning transparently',
      (tester) async {
    await tester.runAsync(() async {
      final doc = PdfDocument.open(buildVectorPdf());
      final scene = await PdfRetainedScene.record(doc.page(0));
      addTearDown(scene.dispose);

      const ratio = 2.0;
      final good = await _localPlan(scene, pixelRatio: ratio);
      // Doctored: right geometry, wrong flush structure - only detectable
      // at finish, after the whole walk consumed it.
      final doctored = StripPlan(
        totalFlushPoints: good.totalFlushPoints + 1,
        deviceWidth: good.deviceWidth,
        deviceHeight: good.deviceHeight,
        pageToDevice: good.pageToDevice,
        tolerance: good.tolerance,
        batches: good.batches,
      );
      StripPdfDevice.resetStats();
      final fallback =
          await scene.rasterizeStrips(pixelRatio: ratio, stripPlan: doctored);
      expect(StripPdfDevice.totalPlanMismatches, 1,
          reason: 'the desync must be counted');
      expect(StripPdfDevice.totalPlanPictures, 0);
      final local = await scene.rasterizeStrips(pixelRatio: ratio);
      expect(await _rgba(fallback), await _rgba(local),
          reason: 'the fallback re-bin must produce the correct raster');
      fallback.dispose();
      local.dispose();

      // Stale geometry (a plan for another zoom level) is rejected up
      // front - cheaper, same fallback.
      StripPdfDevice.resetStats();
      final stale =
          await scene.rasterizeStrips(pixelRatio: 3.0, stripPlan: good);
      expect(StripPdfDevice.totalPlanMismatches, 1);
      expect(StripPdfDevice.totalPlanPictures, 0);
      final local3 = await scene.rasterizeStrips(pixelRatio: 3.0);
      expect(await _rgba(stale), await _rgba(local3));
      stale.dispose();
      local3.dispose();
    });
  });

  testWidgets('debug-delegate flags force local binning over an offered plan',
      (tester) async {
    await tester.runAsync(() async {
      final doc = PdfDocument.open(buildVectorPdf());
      final scene = await PdfRetainedScene.record(doc.page(0));
      addTearDown(scene.dispose);

      const ratio = 2.0;
      final plan = await _localPlan(scene, pixelRatio: ratio);
      StripPdfDevice.debugDelegateFills = true;
      addTearDown(() => StripPdfDevice.debugDelegateFills = false);
      StripPdfDevice.resetStats();
      final image =
          await scene.rasterizeStrips(pixelRatio: ratio, stripPlan: plan);
      // The plan is ignored (not a mismatch - a debug mode), fills went to
      // the canvas fallback, strokes still binned locally.
      expect(StripPdfDevice.totalPlanPictures, 0);
      expect(StripPdfDevice.totalPlanMismatches, 0);
      expect(StripPdfDevice.totalDelegatedPaints, greaterThan(0));
      image.dispose();
    });
  });

  // Widget-level end to end (runs LAST - see the header note): a zoom
  // settle on a worker-backed, strip-routed page consumes a worker-binned
  // plan instead of binning on the UI thread.
  testWidgets('PdfPageView settles dense worker-backed pages from a plan',
      (tester) async {
    PdfPageView.retainedZoomReplayMaxCommands = 0; // every page is "dense"
    PdfPageView.stripZoomReplay = true;
    PdfPageView.debugStripZoomReplayBackendOverride = true;
    addTearDown(() {
      PdfPageView.retainedZoomReplayMaxCommands = 20000;
      PdfPageView.stripZoomReplay = true; // the default
      PdfPageView.debugStripZoomReplayBackendOverride = null;
    });
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);

    final bytes = buildVectorPdf();
    final doc = PdfDocument.open(bytes);
    final page = doc.page(0);
    late PdfRenderWorker worker;
    await tester.runAsync(() async {
      worker = PdfRenderWorker.start(bytes);
    });
    addTearDown(worker.dispose);

    Widget at(double scale) => Center(
        child: SizedBox(
            width: 612,
            child:
                PdfPageView(page: page, scale: scale, renderWorker: worker)));

    StripPdfDevice.resetStats();
    await tester.pumpWidget(at(1));
    await router.settleRaster(tester, 612);

    await tester.pumpWidget(at(3));
    final expectedWidth = router.vectorRasterWidth(3);
    final zoomed = await router.settleRaster(tester, expectedWidth);
    expect(zoomed.width, expectedWidth);
    expect(StripPdfDevice.totalPlanPictures, greaterThan(0),
        reason: 'the settle must consume a worker-binned plan');
    expect(StripPdfDevice.totalPlanMismatches, 0);
  });

  // Speculative binning: while the gesture quiesces (the live transformScale
  // stops moving for 50 ms), the page pre-requests the worker plan for the
  // geometry the settle will ask for; the settle then consumes it instead of
  // starting a fresh bin.
  testWidgets(
      'a zoom settle consumes the plan speculated while the gesture '
      'quiesced', (tester) async {
    PdfPageView.retainedZoomReplayMaxCommands = 0; // every page is "dense"
    PdfPageView.stripZoomReplay = true;
    PdfPageView.debugStripZoomReplayBackendOverride = true;
    PdfPageView.debugResetSpeculativeStats();
    addTearDown(() {
      PdfPageView.retainedZoomReplayMaxCommands = 20000;
      PdfPageView.stripZoomReplay = true; // the default
      PdfPageView.debugStripZoomReplayBackendOverride = null;
      PdfPageView.debugResetSpeculativeStats();
    });
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);

    final bytes = buildVectorPdf();
    final doc = PdfDocument.open(bytes);
    final page = doc.page(0);
    late PdfRenderWorker worker;
    await tester.runAsync(() async {
      worker = PdfRenderWorker.start(bytes);
    });
    addTearDown(worker.dispose);

    final live = ValueNotifier<double>(1.0);
    addTearDown(live.dispose);
    Widget at(double scale, int settleGeneration) => Center(
        child: SizedBox(
            width: 612,
            child: PdfPageView(
                page: page,
                scale: scale,
                settleGeneration: settleGeneration,
                renderWorker: worker,
                transformScale: live)));

    await tester.pumpWidget(at(1, 0));
    await router.settleRaster(tester, 612);

    // The gesture moves to 3x, then quiesces past the 50 ms debounce: the
    // page speculatively requests the worker bin for the settle's geometry.
    live.value = 3.0;
    await tester.pump(const Duration(milliseconds: 60));
    expect(PdfPageView.debugSpeculativePlanHits, 0);
    expect(PdfPageView.debugSpeculativePlanMisses, 0);

    // The viewer's settle: the same quantized scale, a bumped generation.
    StripPdfDevice.resetStats();
    await tester.pumpWidget(at(3, 1));
    final expectedWidth = router.vectorRasterWidth(3);
    final zoomed = await router.settleRaster(tester, expectedWidth);
    expect(zoomed.width, expectedWidth);
    expect(PdfPageView.debugSpeculativePlanHits, 1,
        reason: 'the settle must consume the speculative plan');
    expect(PdfPageView.debugSpeculativePlanMisses, 0);
    expect(StripPdfDevice.totalPlanPictures, greaterThan(0),
        reason: 'the speculative plan must feed the strip device');
    expect(StripPdfDevice.totalPlanMismatches, 0);
  });

  testWidgets(
      'a settle at a different scale than speculated misses and '
      'still renders from a fresh worker plan', (tester) async {
    PdfPageView.retainedZoomReplayMaxCommands = 0; // every page is "dense"
    PdfPageView.stripZoomReplay = true;
    PdfPageView.debugStripZoomReplayBackendOverride = true;
    PdfPageView.debugResetSpeculativeStats();
    addTearDown(() {
      PdfPageView.retainedZoomReplayMaxCommands = 20000;
      PdfPageView.stripZoomReplay = true; // the default
      PdfPageView.debugStripZoomReplayBackendOverride = null;
      PdfPageView.debugResetSpeculativeStats();
    });
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);

    final bytes = buildVectorPdf();
    final doc = PdfDocument.open(bytes);
    final page = doc.page(0);
    late PdfRenderWorker worker;
    await tester.runAsync(() async {
      worker = PdfRenderWorker.start(bytes);
    });
    addTearDown(worker.dispose);

    final live = ValueNotifier<double>(1.0);
    addTearDown(live.dispose);
    Widget at(double scale, int settleGeneration) => Center(
        child: SizedBox(
            width: 612,
            child: PdfPageView(
                page: page,
                scale: scale,
                settleGeneration: settleGeneration,
                renderWorker: worker,
                transformScale: live)));

    await tester.pumpWidget(at(1, 0));
    await router.settleRaster(tester, 612);

    // Speculate for 2x...
    live.value = 2.0;
    await tester.pump(const Duration(milliseconds: 60));

    // ...but settle at 3x: wrong geometry, so the speculative plan is
    // dropped (a miss) and a fresh request serves the settle - output is
    // still a plan-fed strip raster at the right size.
    StripPdfDevice.resetStats();
    await tester.pumpWidget(at(3, 1));
    final expectedWidth = router.vectorRasterWidth(3);
    final zoomed = await router.settleRaster(tester, expectedWidth);
    expect(zoomed.width, expectedWidth);
    expect(PdfPageView.debugSpeculativePlanHits, 0);
    expect(PdfPageView.debugSpeculativePlanMisses, 1,
        reason: 'the mismatched speculation must be counted');
    expect(StripPdfDevice.totalPlanPictures, greaterThan(0),
        reason: 'a fresh worker plan must still land');
    expect(StripPdfDevice.totalPlanMismatches, 0);
  });

  testWidgets(
      'a deep-zoom pan consumes the combined region detail '
      'speculated from live translation', (tester) async {
    PdfPageView.retainedZoomReplayMaxCommands = 0; // every page is "dense"
    PdfPageView.stripZoomReplay = true;
    PdfPageView.debugStripZoomReplayBackendOverride = true;
    PdfPageView.debugResetSpeculativeStats();
    addTearDown(() {
      PdfPageView.retainedZoomReplayMaxCommands = 20000;
      PdfPageView.stripZoomReplay = true;
      PdfPageView.debugStripZoomReplayBackendOverride = null;
      PdfPageView.debugResetSpeculativeStats();
    });
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);

    final bytes = buildSyntheticRasterUnderlaySheet(
      // Keep the source just above the shared 16 MP decode ceiling. A smaller
      // image now reaches native resolution in the focused 2x-headroom base,
      // correctly making region speculation redundant instead of exercising
      // the combined detail path this test is about.
      underlays: const [PdfUnderlaySpec(width: 4352, height: 4352)],
      layers: 1,
      ops: 100,
      pageW: 612,
      pageH: 792,
    );
    final doc = PdfDocument.open(bytes);
    final page = doc.page(0);
    late PdfRenderWorker worker;
    await tester.runAsync(() async {
      worker = PdfRenderWorker.start(bytes);
    });
    addTearDown(worker.dispose);

    // The viewer's scale notifier stays at the live 16x zoom. The separate
    // pan notifier models the full TransformationController: it rebuilds the
    // translated page and wakes speculation even though scale is unchanged.
    final liveScale = ValueNotifier<double>(16.0);
    final pan = ValueNotifier<Offset>(Offset.zero);
    final scheduler = PdfPageRenderScheduler();
    addTearDown(liveScale.dispose);
    addTearDown(pan.dispose);
    addTearDown(scheduler.dispose);

    Widget at(double scale, int settleGeneration) => Align(
          alignment: Alignment.topLeft,
          child: ValueListenableBuilder<Offset>(
            valueListenable: pan,
            builder: (context, offset, _) => Transform.translate(
              offset: offset,
              child: SizedBox(
                width: 612,
                child: PdfPageView(
                  page: page,
                  scale: scale,
                  settleGeneration: settleGeneration,
                  renderWorker: worker,
                  renderScheduler: scheduler,
                  transformScale: liveScale,
                  transformChanges: pan,
                ),
              ),
            ),
          ),
        );

    // Prime the worker-recorded retained scene at 1x, then enter deep zoom
    // and wait for its first ordinary detail patch to land.
    await tester.pumpWidget(at(1, 0));
    await router.settleRaster(tester, 612);
    await tester.pumpWidget(at(16, 1));
    for (var i = 0; i < 500; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
      if (find.byType(RawImage).evaluate().length >= 2) break;
    }
    expect(find.byType(RawImage).evaluate().length, greaterThanOrEqualTo(2),
        reason: 'deep zoom must have a base raster and detail patch');
    // The first progressive patch can paint while the image-complete base and
    // its replacement detail are still in flight. Let that foreground pass
    // drain before starting the pan, otherwise it can itself observe the new
    // translation and make the speculative result redundant before settle.
    for (var i = 0; i < 500 && scheduler.busy; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(scheduler.busy, isFalse,
        reason: 'the priming render must finish before measuring speculation');
    PdfPageView.debugResetSpeculativeStats();

    // Translate without changing scale. One frame applies the transform;
    // the following 60 ms crosses the 50 ms speculation debounce. The real
    // viewer holds scheduled page renders throughout this window; worker
    // speculation must continue because overlapping that hold is its purpose.
    scheduler.holding = true;
    pan.value = const Offset(-450, 0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    // The viewer's 200 ms settle later bumps only settleGeneration. Its
    // region geometry is bit-identical to the live translation's request.
    scheduler.holding = false;
    await tester.pumpWidget(at(16, 2));
    for (var i = 0;
        i < 500 && PdfPageView.debugSpeculativeDetailHits == 0;
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(PdfPageView.debugSpeculativeDetailHits, 1);
    expect(PdfPageView.debugSpeculativeDetailMisses, 0);
    expect(PdfPageView.debugSpeculativePlanHits, 0,
        reason: 'deep zoom must speculate the combined region job, not a '
            'full-page bin');

    // A second live region can be overtaken before the viewer's settle. The
    // stored geometry must miss rather than painting the stale patch, and the
    // settle must issue a fresh request for the newest translation.
    PdfPageView.debugResetSpeculativeStats();
    scheduler.holding = true;
    pan.value = const Offset(-250, 0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    pan.value = const Offset(-500, 0);
    await tester.pump(); // apply the newer transform, before its 50 ms timer
    scheduler.holding = false;
    await tester.pumpWidget(at(16, 3));
    for (var i = 0;
        i < 500 && PdfPageView.debugSpeculativeDetailMisses == 0;
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(PdfPageView.debugSpeculativeDetailHits, 0);
    expect(PdfPageView.debugSpeculativeDetailMisses, 1,
        reason: 'a translated settle must reject stale region geometry');

    // Dispose before the newer translation's pending speculation timer fires.
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
