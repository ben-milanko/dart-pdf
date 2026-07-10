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
import 'package:pdf_document/pdf_document.dart';

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
  testWidgets('a precomputed plan rasterizes byte-identically to local '
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
      final regionPlan =
          await _localPlan(scene, pixelRatio: 2, region: region);
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
      final fallback = await scene.rasterizeStrips(
          pixelRatio: ratio, stripPlan: doctored);
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
      final stale = await scene.rasterizeStrips(
          pixelRatio: 3.0, stripPlan: good);
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
    final zoomed = await router.settleRaster(tester, 612 * 3);
    expect(zoomed.width, 612 * 3);
    expect(StripPdfDevice.totalPlanPictures, greaterThan(0),
        reason: 'the settle must consume a worker-binned plan');
    expect(StripPdfDevice.totalPlanMismatches, 0);
  });
}
