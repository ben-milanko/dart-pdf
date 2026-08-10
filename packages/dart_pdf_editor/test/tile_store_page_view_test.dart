// With PdfPageView.tileStoreDetail on, a deep-zoom page must composite tiles
// from the store instead of the single detail patch, while the base raster
// keeps showing through. Kept in its own file so the global flag mutation can't
// leak into other page-view tests.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/region_replay_index.dart';
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
    final backend = _RecordingTileRasterBackend(throwOnDispose: true);
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
    expect(backend.rasterizations, 0);
    expect(store.tileCount, greaterThan(0));
  });

  testWidgets('tile path composites deep-zoom tiles instead of the patch',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = PdfTileStore(tilePixels: 256, registerForMemoryPressure: false);
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
      await tester
          .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
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
    // The base raster is still the only RawImage (tiles paint via CustomPaint).
    expect(find.byType(RawImage), findsOneWidget);
    // Real tiles rastered from the page's retained scene.
    expect(store.tileCount, greaterThan(0));
  });

  testWidgets('heavy index warm does not launch an obsolete detail record',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = PdfTileStore(tilePixels: 256, registerForMemoryPressure: false);
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

// Deliberately subclasses the stock backend: custom subclasses still override
// createSession and must not bypass the failure adapter.
class _RecordingTileRasterBackend extends PdfCanvasTileRasterBackend {
  _RecordingTileRasterBackend({
    this.failCreation = false,
    this.failRasterization = false,
    this.wrongDimensions = false,
    this.throwOnDispose = false,
  });

  final bool failCreation;
  final bool failRasterization;
  final bool wrongDimensions;
  final bool throwOnDispose;
  int sessionCreates = 0;
  int sessionDisposals = 0;
  int rasterizations = 0;

  @override
  String get debugLabel => 'recording';

  @override
  PdfTileRasterSession createSession(PdfRetainedScene scene) {
    sessionCreates++;
    if (failCreation) throw StateError('experimental backend unavailable');
    return _RecordingTileRasterSession(this, scene);
  }
}

class _RecordingTileRasterSession implements PdfTileRasterSession {
  _RecordingTileRasterSession(this.backend, this.scene);

  final _RecordingTileRasterBackend backend;

  @override
  final PdfRetainedScene scene;

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
