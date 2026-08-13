// With PdfPageView.tileStoreDetail on, a deep-zoom page must composite tiles
// from the store instead of the single detail patch, while the base raster
// keeps showing through. Kept in its own file so the global flag mutation can't
// leak into other page-view tests.
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/region_replay_index.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  testWidgets('tile backend is lazy, scene-scoped, and disposal-safe',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);

    final store =
        PdfTileStore(tilePixels: 256, registerForMemoryPressure: false);
    final backend = _RecordingTileRasterBackend(
      throwOnDispose: true,
      batchAdjacentTiles: false,
      maxNewTilesPerPaint: 1,
    );
    PdfPageView.tileStoreDetail = true;
    PdfPageView.debugTileStoreOverride = store;
    addTearDown(() {
      PdfPageView.tileStoreDetail = false;
      PdfPageView.debugTileStoreOverride = null;
      store.dispose();
    });

    final doc = PdfDocument.open(buildClassicPdf());
    Widget page(double width) => Center(
          child: OverflowBox(
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: SizedBox(
              width: width,
              child: PdfPageView(
                page: doc.page(0),
                tileRasterBackend: backend,
              ),
            ),
          ),
        );

    // A normal first paint records and rasterizes the page, but never creates
    // the optional tile backend.
    await tester.pumpWidget(page(612));
    for (var i = 0; i < 100 && find.byType(RawImage).evaluate().isEmpty; i++) {
      await tester.pump();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    expect(find.byType(RawImage), findsOneWidget);
    expect(backend.sessionCreates, 0);

    // Deep zoom engages the existing tile scheduler. Every slab goes through
    // one session retained for this scene.
    await tester.pumpWidget(page(6120));
    for (var i = 0; i < 300 && store.tileCount == 0; i++) {
      await tester.pump();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    expect(store.tileCount, greaterThan(0));
    expect(backend.sessionCreates, 1);
    expect(backend.rasterizations, greaterThan(0));
    final tilePaint = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('pdf-page-tile-layer')),
    );
    expect((tilePaint.painter as dynamic).batchRasters, isFalse,
        reason: 'a final-texture backend must bypass slab slicing');
    expect((tilePaint.painter as dynamic).maxNewTilesPerPaint, 1,
        reason: 'the backend session owns its per-frame admission policy');
    expect((tilePaint.painter as dynamic).maxInFlightTiles, 2,
        reason: 'repaints must not grow the backend submission queue');

    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull,
        reason: 'an optional backend must not break page teardown');
    expect(backend.sessionDisposals, 1);
  });

  testWidgets('a failed tile backend falls back to Canvas', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);

    final store =
        PdfTileStore(tilePixels: 256, registerForMemoryPressure: false);
    final backend = _RecordingTileRasterBackend(failRasterization: true);
    PdfPageView.tileStoreDetail = true;
    PdfPageView.debugTileStoreOverride = store;
    addTearDown(() {
      PdfPageView.tileStoreDetail = false;
      PdfPageView.debugTileStoreOverride = null;
      store.dispose();
    });

    final doc = PdfDocument.open(buildClassicPdf());
    await tester.pumpWidget(
      Center(
        child: OverflowBox(
          maxWidth: double.infinity,
          maxHeight: double.infinity,
          child: SizedBox(
            width: 6120,
            child: PdfPageView(
              page: doc.page(0),
              tileRasterBackend: backend,
            ),
          ),
        ),
      ),
    );

    for (var i = 0; i < 300 && store.tileCount == 0; i++) {
      await tester.pump();
      final exception = tester.takeException();
      if (exception != null) fail('Canvas fallback failed: $exception');
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
    }

    expect(backend.sessionCreates, 1);
    expect(backend.rasterizations, greaterThan(0));
    expect(store.tileCount, greaterThan(0),
        reason: 'the failed backend request must be retried through Canvas');
    expect(backend.sessionDisposals, 1,
        reason: 'a permanently-failed primary must release scene resources');
  });

  testWidgets('a wrong-sized backend slab falls back to Canvas',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);

    final store =
        PdfTileStore(tilePixels: 256, registerForMemoryPressure: false);
    final backend = _RecordingTileRasterBackend(wrongDimensions: true);
    PdfPageView.tileStoreDetail = true;
    PdfPageView.debugTileStoreOverride = store;
    addTearDown(() {
      PdfPageView.tileStoreDetail = false;
      PdfPageView.debugTileStoreOverride = null;
      store.dispose();
    });

    final doc = PdfDocument.open(buildClassicPdf());
    await tester.pumpWidget(
      Center(
        child: OverflowBox(
          maxWidth: double.infinity,
          maxHeight: double.infinity,
          child: SizedBox(
            width: 6120,
            child: PdfPageView(
              page: doc.page(0),
              tileRasterBackend: backend,
            ),
          ),
        ),
      ),
    );

    for (var i = 0; i < 300 && store.tileCount == 0; i++) {
      await tester.pump();
      final exception = tester.takeException();
      if (exception != null) fail('Canvas fallback failed: $exception');
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
    }

    expect(backend.sessionCreates, 1);
    expect(backend.rasterizations, greaterThan(0));
    expect(store.tileCount, greaterThan(0),
        reason: 'malformed backend pixels must not enter the tile cache');
  });

  testWidgets('an unavailable tile backend falls back during initialization',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);

    final store =
        PdfTileStore(tilePixels: 256, registerForMemoryPressure: false);
    final backend = _RecordingTileRasterBackend(failCreation: true);
    final logs = <String>[];
    PdfPerfLog.enabled = true;
    PdfPerfLog.sink = logs.add;
    PdfPageView.tileStoreDetail = true;
    PdfPageView.debugTileStoreOverride = store;
    addTearDown(() {
      PdfPageView.tileStoreDetail = false;
      PdfPageView.debugTileStoreOverride = null;
      store.dispose();
      PdfPerfLog.enabled = false;
      PdfPerfLog.sink = null;
    });

    final doc = PdfDocument.open(buildClassicPdf());
    await tester.pumpWidget(
      Center(
        child: OverflowBox(
          maxWidth: double.infinity,
          maxHeight: double.infinity,
          child: SizedBox(
            width: 6120,
            child: PdfPageView(
              page: doc.page(0),
              tileRasterBackend: backend,
            ),
          ),
        ),
      ),
    );

    for (var i = 0; i < 300 && store.tileCount == 0; i++) {
      await tester.pump();
      final exception = tester.takeException();
      if (exception != null) fail('Canvas fallback failed: $exception');
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
    }

    expect(backend.sessionCreates, 1);
    expect(backend.rasterizations, 0);
    expect(store.tileCount, greaterThan(0));
    expect(
      logs,
      contains(contains(
          'requested=recording route=canvas reason=test unsupported clip')),
      reason: 'field traces must explain why the requested backend declined',
    );
  });

  testWidgets('tile path composites deep-zoom tiles instead of the patch',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);

    final store =
        PdfTileStore(tilePixels: 256, registerForMemoryPressure: false);
    final oldRegionLimit = PdfRetainedScene.spatialRegionReplayMaxCommands;
    // Force even this small fixture through the heavy/grid index gate. This
    // reproduces the field-trace failure where _useTilePath stayed
    // `index-warming` forever because the warm-up was hidden behind that gate.
    PdfRetainedScene.spatialRegionReplayMaxCommands = 0;
    PdfPageView.tileStoreDetail = true;
    PdfPageView.debugTileStoreOverride = store;
    addTearDown(() {
      PdfRetainedScene.spatialRegionReplayMaxCommands = oldRegionLimit;
      PdfPageView.tileStoreDetail = false;
      PdfPageView.debugTileStoreOverride = null;
      store.dispose();
    });

    final doc = PdfDocument.open(buildClassicPdf());
    // Laid out 10x wider than its point size: only a slice fits, so the tile
    // layer covers the visible fraction and the base raster shows underneath.
    await tester.pumpWidget(
      Center(
        child: OverflowBox(
          maxWidth: double.infinity,
          maxHeight: double.infinity,
          child: SizedBox(width: 6120, child: PdfPageView(page: doc.page(0))),
        ),
      ),
    );
    // Let the base render, the tile-geometry refresh, and the tile rasters land.
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump();
    }

    // The tile layer replaced the single detail patch.
    expect(find.byKey(const ValueKey('pdf-page-tile-layer')), findsOneWidget);
    expect(find.byKey(const ValueKey('pdf-page-detail-image')), findsNothing);
    final tilePaint = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('pdf-page-tile-layer')),
    );
    expect((tilePaint.painter as dynamic).maxNewTilesPerPaint, 1,
        reason: 'grid-indexed scenes must pace replay one tile per paint');
    expect((tilePaint.painter as dynamic).maxInFlightTiles, 2,
        reason: 'the cross-frame queue remains bounded while tiles land');
    // The base raster is still the only RawImage (tiles paint via CustomPaint).
    expect(find.byType(RawImage), findsOneWidget);
    // Real tiles rastered from the page's retained scene.
    expect(store.tileCount, greaterThan(0));
  });

  testWidgets('late tile pan-ahead changes no exact foreground pixels',
      (tester) async {
    tester.view.physicalSize = const Size(400, 300);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = PdfTileStore(
      tilePixels: 128,
      prefetchRing: 1,
      registerForMemoryPressure: false,
    );
    final backend = _SolidTileRasterBackend();
    final oldTiles = PdfPageView.tileStoreDetail;
    final oldDirect = PdfPageView.directPicturePresentation;
    PdfPageView.tileStoreDetail = false;
    PdfPageView.directPicturePresentation = false;
    PdfPageView.debugTileStoreOverride = store;
    addTearDown(() {
      PdfPageView.tileStoreDetail = oldTiles;
      PdfPageView.directPicturePresentation = oldDirect;
      PdfPageView.debugTileStoreOverride = null;
      store.dispose();
    });

    final bytes = buildSyntheticRasterUnderlaySheet(
      underlays: const [PdfUnderlaySpec(width: 2048, height: 2048)],
      layers: 1,
      ops: 0,
      pageW: 256,
      pageH: 256,
    );
    final doc = PdfDocument.open(bytes);
    const boundaryKey = ValueKey('tile-under-detail-boundary');
    const detailKey = ValueKey('pdf-page-detail-image');
    const tileKey = ValueKey('pdf-page-tile-layer');

    Widget page(double scale, int generation) => RepaintBoundary(
          key: boundaryKey,
          child: Center(
            child: OverflowBox(
              maxWidth: double.infinity,
              maxHeight: double.infinity,
              child: SizedBox(
                width: 2560,
                child: PdfPageView(
                  page: doc.page(0),
                  baseRasterScale: 1,
                  scale: scale,
                  settleGeneration: generation,
                  tileRasterBackend: backend,
                ),
              ),
            ),
          ),
        );

    Future<ui.Image> waitForDetail() async {
      for (var i = 0; i < 300; i++) {
        await tester.pump();
        if (find.byKey(detailKey).evaluate().isNotEmpty) {
          final image = tester.widget<RawImage>(find.byKey(detailKey)).image;
          if (image != null) return image;
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
      }
      fail('exact detail did not land');
    }

    Future<Uint8List> pixels() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundaryKey),
      );
      for (var i = 0; i < 300 && boundary.debugNeedsPaint; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)),
        );
      }
      expect(boundary.debugNeedsPaint, isFalse);
      return (await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        image.dispose();
        return data!.buffer.asUint8List();
      }))!;
    }

    await tester.pumpWidget(page(2, 0));
    final exact = await waitForDetail();
    final before = await pixels();

    // Enable the production-default tile route on a new settle with unchanged
    // geometry. The current exact patch is reused; its post-paint callback then
    // admits the pyramid and its ring underneath.
    PdfPageView.tileStoreDetail = true;
    await tester.pumpWidget(page(2, 1));
    for (var i = 0;
        i < 300 &&
            (find.byKey(tileKey).evaluate().isEmpty || store.tileCount == 0);
        i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    expect(find.byKey(tileKey), findsOneWidget);
    expect(backend.rasterizations, greaterThan(0));
    expect(store.tileCount, greaterThan(0));
    await tester.pump();
    final after = await pixels();
    expect(after, orderedEquals(before),
        reason: 'deliberately different late tile pixels must stay occluded '
            'by the exact visible patch');
    expect(tester.widget<RawImage>(find.byKey(detailKey)).image, same(exact));
  });

  testWidgets('translation cannot abandon exact-first recovery for tiles',
      (tester) async {
    tester.view.physicalSize = const Size(400, 300);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = PdfTileStore(
      tilePixels: 128,
      prefetchRing: 1,
      registerForMemoryPressure: false,
    );
    final oldTiles = PdfPageView.tileStoreDetail;
    PdfPageView.tileStoreDetail = true;
    PdfPageView.debugTileStoreOverride = store;
    addTearDown(() {
      PdfPageView.tileStoreDetail = oldTiles;
      PdfPageView.debugTileStoreOverride = null;
      store.dispose();
    });

    final doc = PdfDocument.open(buildClassicPdf());
    Widget page(double scale, int generation, double dx) => Center(
          child: Transform.translate(
            offset: Offset(dx, 0),
            child: OverflowBox(
              maxWidth: double.infinity,
              maxHeight: double.infinity,
              child: SizedBox(
                width: 1024,
                child: PdfPageView(
                  page: doc.page(0),
                  baseRasterScale: 1,
                  scale: scale,
                  settleGeneration: generation,
                ),
              ),
            ),
          ),
        );

    await tester.pumpWidget(page(1, 0, 0));
    for (var i = 0; i < 200 && find.byType(RawImage).evaluate().isEmpty; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }

    await tester.pumpWidget(page(4, 1, 0));
    expect(find.byKey(const ValueKey('pdf-page-tile-layer')), findsNothing,
        reason: 'a scale settle keeps incremental tiles hidden');

    // Reproduce the trace: a tiny translation advances the settle while the
    // exact region is still in flight. The old generation-based gate forgot
    // the exact-first obligation here and exposed a staggered tile tail.
    await tester.pumpWidget(page(4, 2, -12));
    expect(find.byKey(const ValueKey('pdf-page-tile-layer')), findsNothing,
        reason: 'translation must retain exact-first recovery');

    for (var i = 0;
        i < 300 &&
            find
                .byKey(const ValueKey('pdf-page-detail-image'))
                .evaluate()
                .isEmpty;
        i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    expect(find.byKey(const ValueKey('pdf-page-detail-image')), findsOneWidget);
    for (var i = 0;
        i < 50 &&
            find
                .byKey(const ValueKey('pdf-page-tile-layer'))
                .evaluate()
                .isEmpty;
        i++) {
      await tester.pump();
    }
    expect(find.byKey(const ValueKey('pdf-page-tile-layer')), findsOneWidget,
        reason: 'tiles become pan-ahead only after exact pixels paint');
  });

  testWidgets('a page entered at deep zoom paints exact before tile batches',
      (tester) async {
    tester.view.physicalSize = const Size(400, 300);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = PdfTileStore(
      tilePixels: 512,
      prefetchRing: 1,
      registerForMemoryPressure: false,
    );
    final logs = <String>[];
    final oldTiles = PdfPageView.tileStoreDetail;
    PdfPageView.tileStoreDetail = true;
    PdfPageView.debugTileStoreOverride = store;
    PdfPerfLog.enabled = true;
    PdfPerfLog.sink = logs.add;
    addTearDown(() {
      PdfPageView.tileStoreDetail = oldTiles;
      PdfPageView.debugTileStoreOverride = null;
      PdfPerfLog.enabled = false;
      PdfPerfLog.sink = null;
      store.dispose();
    });

    final doc = PdfDocument.open(buildClassicPdf());
    await tester.pumpWidget(
      Center(
        child: OverflowBox(
          maxWidth: double.infinity,
          maxHeight: double.infinity,
          child: SizedBox(
            width: 1024,
            child: PdfPageView(
              page: doc.page(0),
              baseRasterScale: 1,
              scale: 4,
            ),
          ),
        ),
      ),
    );

    for (var i = 0;
        i < 300 &&
            (find
                    .byKey(const ValueKey('pdf-page-tile-layer'))
                    .evaluate()
                    .isEmpty ||
                store.tileCount == 0);
        i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }

    final exactPaint = logs.indexWhere(
      (line) => line.contains('detail paint page=0 pass=visible'),
    );
    final firstTile = logs.indexWhere(
      (line) =>
          line.contains('tile slice page=0') && line.contains('class=visible'),
    );
    expect(exactPaint, greaterThanOrEqualTo(0));
    expect(firstTile, greaterThan(exactPaint),
        reason: 'a newly visible deep-zoom page must not sharpen in patches');
    expect(find.byKey(const ValueKey('pdf-page-detail-image')), findsOneWidget);
    expect(find.byKey(const ValueKey('pdf-page-tile-layer')), findsOneWidget);
    final painter = tester
        .widget<CustomPaint>(
          find.byKey(const ValueKey('pdf-page-tile-layer')),
        )
        .painter as dynamic;
    expect(painter.maxInFlightTiles, 8,
        reason: 'ordinary scenes get one bounded visible slab at a time');
  });

  testWidgets('an active tile target never steps down in quality',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);

    final store =
        PdfTileStore(tilePixels: 256, registerForMemoryPressure: false);
    final oldRegionLimit = PdfRetainedScene.spatialRegionReplayMaxCommands;
    PdfRetainedScene.spatialRegionReplayMaxCommands = 0;
    PdfPageView.tileStoreDetail = true;
    PdfPageView.debugTileStoreOverride = store;
    addTearDown(() {
      PdfRetainedScene.spatialRegionReplayMaxCommands = oldRegionLimit;
      PdfPageView.tileStoreDetail = false;
      PdfPageView.debugTileStoreOverride = null;
      store.dispose();
    });

    final doc = PdfDocument.open(buildClassicPdf());
    Widget page(double width) => Center(
          child: OverflowBox(
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: SizedBox(
              width: width,
              child: PdfPageView(page: doc.page(0)),
            ),
          ),
        );

    await tester.pumpWidget(page(6120));
    final layer = find.byKey(const ValueKey('pdf-page-tile-layer'));
    for (var i = 0; i < 300 && layer.evaluate().isEmpty; i++) {
      await tester.pump();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    expect(layer, findsOneWidget);
    double desiredRatio() =>
        ((tester.widget<CustomPaint>(layer).painter as dynamic).desiredRatio
            as double);
    final sharpRatio = desiredRatio();

    // Narrowing the layout lowers the newly-computed target while the same
    // enlarged page remains visible. Re-run enough frames for the layout-width
    // refresh; the existing sharp rung must remain the presentation target.
    await tester.pumpWidget(page(4880));
    for (var i = 0; i < 30; i++) {
      await tester.pump();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    expect(layer, findsOneWidget);
    expect(desiredRatio(), sharpRatio,
        reason: 'a completed sharp view must not be replaced by a lower rung');
  });

  testWidgets('shared foreground pages disable ring and coarse fallback',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);

    final store =
        PdfTileStore(tilePixels: 512, registerForMemoryPressure: false);
    final oldRegionLimit = PdfRetainedScene.spatialRegionReplayMaxCommands;
    PdfRetainedScene.spatialRegionReplayMaxCommands = 0;
    PdfPageView.tileStoreDetail = true;
    PdfPageView.debugTileStoreOverride = store;
    addTearDown(() {
      PdfRetainedScene.spatialRegionReplayMaxCommands = oldRegionLimit;
      PdfPageView.tileStoreDetail = false;
      PdfPageView.debugTileStoreOverride = null;
      store.dispose();
    });

    final doc = PdfDocument.open(buildClassicPdf());
    await tester.pumpWidget(
      Center(
        child: OverflowBox(
          maxWidth: double.infinity,
          maxHeight: double.infinity,
          child: SizedBox(
            width: 6120,
            child: PdfPageView(
              page: doc.page(0),
              qualityPageCount: 2,
            ),
          ),
        ),
      ),
    );

    final layer = find.byKey(const ValueKey('pdf-page-tile-layer'));
    for (var i = 0; i < 300 && layer.evaluate().isEmpty; i++) {
      await tester.pump();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    expect(layer, findsOneWidget);
    final painter = tester.widget<CustomPaint>(layer).painter as dynamic;
    expect(painter.prefetchRingOverride, 0,
        reason: 'shared pages cannot spend one another\'s budget on pan rings');
    expect(painter.allowCoarserFallback, isFalse,
        reason: 'combined coarse sets would consume the reserved headroom');
  });

  testWidgets('heavy index warm does not launch an obsolete detail record',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);

    final store =
        PdfTileStore(tilePixels: 256, registerForMemoryPressure: false);
    final oldRegionLimit = PdfRetainedScene.spatialRegionReplayMaxCommands;
    PdfRetainedScene.spatialRegionReplayMaxCommands = 0;
    PdfPageView.tileStoreDetail = true;
    PdfPageView.debugTileStoreOverride = store;

    final bytes = buildClassicPdf();
    final doc = PdfDocument.open(bytes);
    final worker = _DelayedIndexWorker(PdfRenderWorker.startUncached(bytes));
    addTearDown(() {
      if (!worker.releaseIndex.isCompleted) worker.releaseIndex.complete();
      worker.dispose();
      PdfRetainedScene.spatialRegionReplayMaxCommands = oldRegionLimit;
      PdfPageView.tileStoreDetail = false;
      PdfPageView.debugTileStoreOverride = null;
      store.dispose();
    });

    await tester.pumpWidget(
      Center(
        child: OverflowBox(
          maxWidth: double.infinity,
          maxHeight: double.infinity,
          child: SizedBox(
            width: 6120,
            child: PdfPageView(
              page: doc.page(0),
              renderWorker: worker,
            ),
          ),
        ),
      ),
    );

    for (var i = 0; i < 300 && worker.indexRequests == 0; i++) {
      await tester.pump();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    expect(worker.indexRequests, 1, reason: 'the heavy index should start');
    expect(worker.detailRecords, 0,
        reason: 'the capped base stays visible while the index warms');

    worker.releaseIndex.complete();
    for (var i = 0; i < 300 && store.tileCount == 0; i++) {
      await tester.pump();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    expect(store.tileCount, greaterThan(0));
    expect(worker.detailRecords, 0,
        reason: 'tiles make the fallback detail record obsolete');
  });

  testWidgets('a view over the tile budget falls back to the single patch',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);

    // Capacity 2 tiles (8 MB floor / 4 MB per 1024² tile) → the 75% fit
    // threshold is 1 tile, so the multi-tile deep-zoom slice below cannot tile
    // and must fall back to the single detail patch instead of thrashing.
    final store = PdfTileStore(
      tilePixels: 1024,
      maxBytes: 8 << 20,
      registerForMemoryPressure: false,
    );
    PdfPageView.tileStoreDetail = true;
    PdfPageView.debugTileStoreOverride = store;
    addTearDown(() {
      PdfPageView.tileStoreDetail = false;
      PdfPageView.debugTileStoreOverride = null;
      store.dispose();
    });

    final doc = PdfDocument.open(buildClassicPdf());
    await tester.pumpWidget(
      Center(
        child: OverflowBox(
          maxWidth: double.infinity,
          maxHeight: double.infinity,
          child: SizedBox(width: 6120, child: PdfPageView(page: doc.page(0))),
        ),
      ),
    );

    // Poll until the fallback patch lands (the tile path never engages).
    final detail = find.byKey(const ValueKey('pdf-page-detail-image'));
    var landed = false;
    for (var i = 0; i < 500 && !landed; i++) {
      await tester.pump();
      final exception = tester.takeException();
      if (exception != null) fail('detail patch failed: $exception');
      landed = detail.evaluate().isNotEmpty;
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
    }

    expect(landed, isTrue, reason: 'over budget → the single detail patch');
    expect(find.byKey(const ValueKey('pdf-page-tile-layer')), findsNothing);
    expect(store.tileCount, 0, reason: 'nothing rastered into the pyramid');
  });

  testWidgets('foreground pages divide the shared tile budget', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);

    // Eight 4096px tiles fit in this synthetic store. This viewport touches
    // four of them: it fits the ordinary six-tile admission limit, but not
    // either page's three-tile share when two meaningful pages are visible at
    // once. No tile is actually allocated because admission rejects the view.
    final store = PdfTileStore(
      tilePixels: 4096,
      maxBytes: 512 << 20,
      maxBatchTilesPerAxis: 4,
      registerForMemoryPressure: false,
    );
    final logs = <String>[];
    PdfPerfLog.enabled = true;
    PdfPerfLog.sink = logs.add;
    PdfPageView.tileStoreDetail = true;
    PdfPageView.debugTileStoreOverride = store;
    addTearDown(() {
      PdfPageView.tileStoreDetail = false;
      PdfPageView.debugTileStoreOverride = null;
      PdfPerfLog.enabled = false;
      PdfPerfLog.sink = null;
      store.dispose();
    });

    final doc = PdfDocument.open(buildClassicPdf());
    await tester.pumpWidget(
      Center(
        child: OverflowBox(
          maxWidth: double.infinity,
          maxHeight: double.infinity,
          child: SizedBox(
            width: 6120,
            child: PdfPageView(
              page: doc.page(0),
              qualityPageCount: 2,
            ),
          ),
        ),
      ),
    );

    final detail = find.byKey(const ValueKey('pdf-page-detail-image'));
    for (var i = 0; i < 500 && detail.evaluate().isEmpty; i++) {
      await tester.pump();
      final exception = tester.takeException();
      if (exception != null) fail('shared-budget fallback failed: $exception');
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
    }

    expect(detail, findsOneWidget,
        reason: 'the page must use the stable single patch for its share');
    expect(find.byKey(const ValueKey('pdf-page-tile-layer')), findsNothing);
    expect(store.tileCount, 0);
    expect(
      logs,
      contains(contains('foregroundPages=2')),
      reason: 'the collective budget, not the old per-page limit, rejected it',
    );
  });

  testWidgets('a soft-mask-free scene reports region-cullable', (tester) async {
    // Guards the fallback-adapter gate: classic pages are cullable, so they
    // take the tile path; a soft-mask page would keep the legacy patch.
    await tester.runAsync(() async {
      final doc = PdfDocument.open(buildClassicPdf());
      final scene = await PdfRetainedScene.record(doc.page(0));
      expect(scene.supportsRegionRaster, isTrue);
      scene.dispose();
    });
  });
}

class _SolidTileRasterBackend extends PdfCanvasTileRasterBackend {
  int rasterizations = 0;

  @override
  String get debugLabel => 'solid';

  @override
  PdfTileRasterSession createSession(PdfRetainedScene scene) =>
      _SolidTileRasterSession(this, scene);
}

class _SolidTileRasterSession
    implements PdfTileRasterSession, PdfTileRasterScheduling {
  _SolidTileRasterSession(this.backend, this.scene);

  final _SolidTileRasterBackend backend;

  @override
  final PdfRetainedScene scene;

  @override
  bool get batchAdjacentTiles => false;

  @override
  int get maxNewTilesPerPaint => 1;

  @override
  Future<ui.Image> rasterizeRegion(
    Rect region, {
    required double pixelRatio,
    int? tracePage,
  }) async {
    backend.rasterizations++;
    final width = (region.width * pixelRatio).ceil().clamp(1, 1 << 14);
    final height = (region.height * pixelRatio).ceil().clamp(1, 1 << 14);
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..color = const Color(0xFFFF00FF),
    );
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(width, height);
    } finally {
      picture.dispose();
    }
  }

  @override
  void dispose() {}
}

// Deliberately subclasses the stock backend: custom subclasses still override
// createSession and must not bypass the failure adapter.
class _RecordingTileRasterBackend extends PdfCanvasTileRasterBackend {
  _RecordingTileRasterBackend({
    this.failCreation = false,
    this.failRasterization = false,
    this.wrongDimensions = false,
    this.throwOnDispose = false,
    this.batchAdjacentTiles = true,
    this.maxNewTilesPerPaint,
  });

  final bool failCreation;
  final bool failRasterization;
  final bool wrongDimensions;
  final bool throwOnDispose;
  final bool batchAdjacentTiles;
  final int? maxNewTilesPerPaint;
  int sessionCreates = 0;
  int sessionDisposals = 0;
  int rasterizations = 0;

  @override
  String get debugLabel => 'recording';

  @override
  String? get lastSessionRejection =>
      failCreation ? 'test unsupported clip' : null;

  @override
  PdfTileRasterSession createSession(PdfRetainedScene scene) {
    sessionCreates++;
    if (failCreation) throw StateError('experimental backend unavailable');
    return _RecordingTileRasterSession(this, scene);
  }
}

class _RecordingTileRasterSession
    implements PdfTileRasterSession, PdfTileRasterScheduling {
  _RecordingTileRasterSession(this.backend, this.scene);

  final _RecordingTileRasterBackend backend;

  @override
  final PdfRetainedScene scene;

  @override
  bool get batchAdjacentTiles => backend.batchAdjacentTiles;

  @override
  int? get maxNewTilesPerPaint => backend.maxNewTilesPerPaint;

  @override
  Future<ui.Image> rasterizeRegion(
    Rect region, {
    required double pixelRatio,
    int? tracePage,
  }) async {
    backend.rasterizations++;
    if (backend.failRasterization) {
      throw StateError('experimental backend failed');
    }
    if (backend.wrongDimensions) {
      final recorder = ui.PictureRecorder();
      final picture = recorder.endRecording();
      try {
        return await picture.toImage(1, 1);
      } finally {
        picture.dispose();
      }
    }
    return scene.rasterizeRegion(
      region,
      pixelRatio: pixelRatio,
      tracePage: tracePage,
    );
  }

  @override
  void dispose() {
    backend.sessionDisposals++;
    if (backend.throwOnDispose) {
      throw StateError('experimental backend dispose failed');
    }
  }
}

class _DelayedIndexWorker extends PdfRenderWorker {
  _DelayedIndexWorker(this.inner);

  final PdfRenderWorker inner;
  final releaseIndex = Completer<void>();
  int indexRequests = 0;
  int detailRecords = 0;

  @override
  bool get isActive => inner.isActive;

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
  }) {
    if (imageDecodeRegion != null) detailRecords++;
    return inner.record(
      pageIndex,
      annotations: annotations,
      priority: priority,
      imagePixelRatio: imagePixelRatio,
      decodeImages: decodeImages,
      commandLimit: commandLimit,
      imageDecodeRegion: imageDecodeRegion,
      onPartial: onPartial,
    );
  }

  @override
  Future<PdfRegionReplayIndex?> buildRegionIndex(
    int pageIndex, {
    required bool annotations,
    required int maxCommands,
    required bool buildGrid,
    int priority = 0,
  }) async {
    indexRequests++;
    await releaseIndex.future;
    return inner.buildRegionIndex(
      pageIndex,
      annotations: annotations,
      maxCommands: maxCommands,
      buildGrid: buildGrid,
      priority: priority,
    );
  }

  @override
  void cancel(int pageIndex, {int priority = 0}) =>
      inner.cancel(pageIndex, priority: priority);

  @override
  void dispose() => inner.dispose();
}
