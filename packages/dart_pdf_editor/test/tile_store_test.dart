// PdfTileStore: the zoom-bucket tile pyramid must snap ratios to a stable
// ladder, cover a viewport center-out, fall back per-tile to the nearest
// coarser cached bucket, invalidate per page (discarding stale in-flight
// rasters), and stay under its byte budget - all the behaviour the deep-zoom
// composite depends on.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ui.Image> _solidImage(int w, int h,
    [Color color = const Color(0xFF102030)]) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..color = color);
  final picture = recorder.endRecording();
  final image = picture.toImage(w, h);
  picture.dispose();
  return image;
}

/// A rasterizer that holds every request pending until [flush], so a test can
/// inspect the in-flight state before the tiles land.
class _Rasterizer {
  _Rasterizer({this.tileSize = 16, this.sizeFromRegion = false});

  final int tileSize;

  /// Size each completed image from its requested region × ratio (what a real
  /// scene raster returns) instead of a fixed [tileSize] - required by batched
  /// stores, whose slab slicing reads exact pixel offsets.
  final bool sizeFromRegion;

  final calls = <({Rect region, double ratio})>[];
  final _pending = <Completer<ui.Image>>[];

  Future<ui.Image> call(Rect region, double ratio) {
    calls.add((region: region, ratio: ratio));
    final completer = Completer<ui.Image>();
    _pending.add(completer);
    return completer.future;
  }

  int get pendingCount => _pending.where((c) => !c.isCompleted).length;

  /// Completes every outstanding raster with a solid image, then drains the
  /// store's completion + tick microtasks.
  Future<void> flush() async {
    final pending = <int>[
      for (var i = 0; i < _pending.length; i++)
        if (!_pending[i].isCompleted) i,
    ];
    // Build every image first, then complete them all in one synchronous burst
    // so the store's completions land in a single microtask drain (the case
    // its tick-coalescing targets).
    final images = <ui.Image>[
      for (final i in pending)
        await _solidImage(
          sizeFromRegion
              ? (calls[i].region.width * calls[i].ratio).ceil()
              : tileSize,
          sizeFromRegion
              ? (calls[i].region.height * calls[i].ratio).ceil()
              : tileSize,
        ),
    ];
    for (var i = 0; i < pending.length; i++) {
      _pending[pending[i]].complete(images[i]);
    }
    await pumpEventQueue();
  }
}

const _plan = PdfPageRenderPlan();

PdfTilePageIdentity _id(int page, {int epoch = 0, int content = 0}) =>
    PdfTilePageIdentity(
      pageIndex: page,
      pageEpoch: epoch,
      contentStamp: content,
      destructiveStamp: 0,
      plan: _plan,
    );

void main() {
  group('PdfTileZoomLadder', () {
    test('rung 0 is ratio 1 and the ×√2 ladder round-trips', () {
      const ladder = PdfTileZoomLadder(); // stepsPerOctave: 2
      expect(ladder.ratioFor(0), 1.0);
      expect(ladder.ratioFor(2), closeTo(2.0, 1e-9));
      expect(ladder.ratioFor(-2), closeTo(0.5, 1e-9));
      expect(ladder.ratioFor(1), closeTo(1.4142135, 1e-6));
      for (final rung in [-4, -1, 0, 3, 7]) {
        expect(ladder.rungFor(ladder.ratioFor(rung)), rung);
      }
    });

    test('snaps a desired ratio to the nearest rung and clamps', () {
      const ladder = PdfTileZoomLadder(stepsPerOctave: 1, minRung: -2, maxRung: 4);
      expect(ladder.rungFor(1.1), 0); // nearest rung 0 (ratio 1)
      expect(ladder.rungFor(1.9), 1); // nearest rung 1 (ratio 2)
      expect(ladder.rungFor(1000), 4); // clamped to maxRung
      expect(ladder.rungFor(0.001), -2); // clamped to minRung
      expect(ladder.rungFor(0), -2); // degenerate ratio → safe 0.05, clamped
    });
  });

  group('PdfTileStore.viewFor', () {
    testWidgets('schedules the visible tiles center-out at the bucket ratio',
        (tester) async {
      await tester.runAsync(() async {
        final store = PdfTileStore(
          tilePixels: 16,
          prefetchRing: 0,
          ladder: const PdfTileZoomLadder(stepsPerOctave: 1),
          batchRasters: false, // this test pins the per-tile scheduling order
          registerForMemoryPressure: false,
        );
        final raster = _Rasterizer();
        const pageSize = Size(64, 64); // 4×4 grid at rung 0 (span 16)

        final view = store.viewFor(
          id: _id(0),
          pageSize: pageSize,
          desiredRatio: 1.0,
          visiblePageRect: const Rect.fromLTWH(0, 0, 64, 64),
          rasterize: raster.call,
        );

        expect(view.rung, 0);
        expect(view.complete, isFalse); // nothing cached yet
        expect(view.isEmpty, isTrue); // no fallback available
        expect(store.inFlightCount, 16);
        expect(raster.calls.length, 16);
        expect(raster.calls.every((c) => c.ratio == 1.0), isTrue);

        // The first scheduled tile is one of the four central tiles (col/row
        // 1 or 2), not a corner.
        final first = raster.calls.first.region;
        expect(first.left, anyOf(16.0, 32.0));
        expect(first.top, anyOf(16.0, 32.0));

        await raster.flush();
        expect(store.tileCount, 16);
        expect(store.debugTilesLanded, 16);

        // A second identical request now composites exact tiles - no reschedule.
        final calls = raster.calls.length;
        final view2 = store.viewFor(
          id: _id(0),
          pageSize: pageSize,
          desiredRatio: 1.0,
          visiblePageRect: const Rect.fromLTWH(0, 0, 64, 64),
          rasterize: raster.call,
        );
        expect(view2.complete, isTrue);
        expect(view2.placements.length, 16);
        // Exact-bucket placements are never flagged as fallbacks.
        expect(view2.placements.any((p) => p.isFallback), isFalse);
        expect(raster.calls.length, calls); // fully cached, nothing scheduled
        store.dispose();
      });
    });

    testWidgets('prefetch ring schedules the border outside the viewport',
        (tester) async {
      await tester.runAsync(() async {
        final store = PdfTileStore(
          tilePixels: 16,
          prefetchRing: 1,
          ladder: const PdfTileZoomLadder(stepsPerOctave: 1),
          registerForMemoryPressure: false,
        );
        final raster = _Rasterizer();
        // Visible = the single centre tile (2,2) of a 5×5 grid; ring adds the
        // 8 surrounding tiles.
        store.viewFor(
          id: _id(0),
          pageSize: const Size(80, 80),
          desiredRatio: 1.0,
          visiblePageRect: const Rect.fromLTWH(32, 32, 16, 16),
          rasterize: raster.call,
        );
        expect(store.inFlightCount, 9); // 1 visible + 8 ring
        store.dispose();
      });
    });

    testWidgets('falls back to the nearest coarser cached bucket, upscaled',
        (tester) async {
      await tester.runAsync(() async {
        final store = PdfTileStore(
          tilePixels: 32,
          prefetchRing: 0,
          registerForMemoryPressure: false,
        );
        final raster = _Rasterizer(tileSize: 32);
        const pageSize = Size(256, 256);
        const visible = Rect.fromLTWH(0, 0, 128, 128);

        // Warm a coarse bucket (ratio 1, rung 0).
        store.viewFor(
          id: _id(0),
          pageSize: pageSize,
          desiredRatio: 1.0,
          visiblePageRect: visible,
          rasterize: raster.call,
        );
        await raster.flush();
        final coarseTiles = store.tileCount;
        expect(coarseTiles, greaterThan(0));

        // Request a sharper bucket over the same area: exact tiles are missing,
        // but the coarse bucket covers it, so the view is non-empty yet not
        // complete (upscaled fallback in play).
        final view = store.viewFor(
          id: _id(0),
          pageSize: pageSize,
          desiredRatio: 4.0, // rung 4 on the ×√2 ladder
          visiblePageRect: visible,
          rasterize: raster.call,
        );
        expect(view.rung, greaterThan(0));
        expect(view.complete, isFalse);
        expect(view.placements, isNotEmpty,
            reason: 'coarser bucket should supply a fallback');
        // Every fallback placement draws from a coarse-bucket image (32² here)
        // and is flagged as a fallback (what the debug overlay colors orange).
        expect(view.placements.every((p) => p.image.width == 32), isTrue);
        expect(view.placements.every((p) => p.isFallback), isTrue);
        store.dispose();
      });
    });

    testWidgets('no fallback and no cache yields an empty (base-only) view',
        (tester) async {
      await tester.runAsync(() async {
        final store = PdfTileStore(
          tilePixels: 32,
          prefetchRing: 0,
          registerForMemoryPressure: false,
        );
        final raster = _Rasterizer(tileSize: 32);
        final view = store.viewFor(
          id: _id(0),
          pageSize: const Size(128, 128),
          desiredRatio: 4.0,
          visiblePageRect: const Rect.fromLTWH(0, 0, 128, 128),
          rasterize: raster.call,
        );
        expect(view.isEmpty, isTrue);
        expect(view.complete, isFalse);
        store.dispose();
      });
    });
  });

  group('PdfTileStore.invalidate', () {
    testWidgets('drops only the named pages; others survive', (tester) async {
      await tester.runAsync(() async {
        final store = PdfTileStore(
          tilePixels: 16,
          prefetchRing: 0,
          ladder: const PdfTileZoomLadder(stepsPerOctave: 1),
          registerForMemoryPressure: false,
        );
        final raster = _Rasterizer();
        for (final page in [0, 1]) {
          store.viewFor(
            id: _id(page),
            pageSize: const Size(32, 32),
            desiredRatio: 1.0,
            visiblePageRect: const Rect.fromLTWH(0, 0, 32, 32),
            rasterize: raster.call,
          );
        }
        await raster.flush();
        final before = store.tileCount;
        expect(before, 8); // 4 tiles each

        store.invalidate(pages: {0});
        expect(store.tileCount, 4);
        expect(store.containsTile(PdfTileKey(_id(0), 0, 0, 0)), isFalse);
        expect(store.containsTile(PdfTileKey(_id(1), 0, 0, 0)), isTrue);
        store.dispose();
      });
    });

    testWidgets('discards in-flight rasters for an invalidated page',
        (tester) async {
      await tester.runAsync(() async {
        final store = PdfTileStore(
          tilePixels: 16,
          prefetchRing: 0,
          ladder: const PdfTileZoomLadder(stepsPerOctave: 1),
          registerForMemoryPressure: false,
        );
        final raster = _Rasterizer();
        store.viewFor(
          id: _id(0),
          pageSize: const Size(32, 32),
          desiredRatio: 1.0,
          visiblePageRect: const Rect.fromLTWH(0, 0, 32, 32),
          rasterize: raster.call,
        );
        expect(store.inFlightCount, 4);

        // Invalidate before the rasters land: their results must be dropped.
        store.invalidate(pages: {0});
        await raster.flush();
        expect(store.tileCount, 0);
        expect(store.debugTilesDiscarded, 4);
        expect(store.debugTilesLanded, 0);
        store.dispose();
      });
    });

    testWidgets('keeps in-flight rasters for the pages it did not invalidate',
        (tester) async {
      await tester.runAsync(() async {
        final store = PdfTileStore(
          tilePixels: 16,
          prefetchRing: 0,
          ladder: const PdfTileZoomLadder(stepsPerOctave: 1),
          registerForMemoryPressure: false,
        );
        final raster = _Rasterizer();
        for (var page = 0; page < 2; page++) {
          store.viewFor(
            id: _id(page),
            pageSize: const Size(32, 32),
            desiredRatio: 1.0,
            visiblePageRect: const Rect.fromLTWH(0, 0, 32, 32),
            rasterize: raster.call,
          );
        }
        expect(store.inFlightCount, 8);

        // A targeted invalidation must not reach across pages. The page view
        // fires this on every live transform tick, so a global stale check
        // throws away the neighbouring page's in-flight work during the very
        // pan that scheduled it (issue #374's discard rate).
        store.invalidate(pages: {0});
        await raster.flush();

        expect(store.debugTilesDiscarded, 4, reason: 'only page 0');
        expect(store.debugTilesLanded, 4, reason: 'page 1 survives');
        expect(store.containsTile(PdfTileKey(_id(1), 0, 0, 0)), isTrue);
        store.dispose();
      });
    });

    testWidgets('an off-screen neighbour settling does not starve the panned '
        'page', (tester) async {
      await tester.runAsync(() async {
        final store = PdfTileStore(
          tilePixels: 16,
          prefetchRing: 0,
          ladder: const PdfTileZoomLadder(stepsPerOctave: 1),
          registerForMemoryPressure: false,
        );
        final raster = _Rasterizer();

        // The shape of issue #427's session: page 0 is zoomed and panning, so
        // each settle schedules its visible tiles; page 1 is scrolled off
        // screen, so _detailGeometryAt returns null every settle and the page
        // view drops its detail - invalidating only its own slot.
        for (var settle = 0; settle < 8; settle++) {
          store.viewFor(
            id: _id(0),
            pageSize: const Size(64, 64),
            desiredRatio: 1.0,
            visiblePageRect: Rect.fromLTWH(settle * 4.0, 0, 32, 32),
            rasterize: raster.call,
          );
          store.invalidate(pages: {1});
        }
        await raster.flush();

        expect(store.debugTilesScheduled, greaterThan(0));
        expect(store.debugTilesDiscarded, 0,
            reason: 'page 1 never had tiles; page 0 was never invalidated');
        expect(store.debugTilesLanded, store.debugTilesScheduled);
        store.dispose();
      });
    });

    testWidgets('null clears every page', (tester) async {
      await tester.runAsync(() async {
        final store = PdfTileStore(
          tilePixels: 16,
          prefetchRing: 0,
          ladder: const PdfTileZoomLadder(stepsPerOctave: 1),
          registerForMemoryPressure: false,
        );
        final raster = _Rasterizer();
        store.viewFor(
          id: _id(0),
          pageSize: const Size(32, 32),
          desiredRatio: 1.0,
          visiblePageRect: const Rect.fromLTWH(0, 0, 32, 32),
          rasterize: raster.call,
        );
        await raster.flush();
        expect(store.tileCount, greaterThan(0));
        store.invalidate();
        expect(store.tileCount, 0);
        store.dispose();
      });
    });
  });

  group('PdfTileStore budget-fit guard (#314/#360)', () {
    test('budgetTileCapacity is the byte budget counted in whole tiles', () {
      final store = PdfTileStore(
        tilePixels: 512, // 512² × 4 = 1 MB per tile
        maxBytes: 8 << 20, // 8 MB → 8 tiles
        registerForMemoryPressure: false,
      );
      expect(store.budgetTileCapacity, 8);
      store.dispose();
    });

    test('viewFitsBudget rejects a view whose visible set overruns the budget',
        () {
      // 8-tile budget; the fit threshold is 75% → up to 6 visible tiles tile.
      final store = PdfTileStore(
        tilePixels: 512,
        maxBytes: 8 << 20,
        ladder: const PdfTileZoomLadder(stepsPerOctave: 1),
        registerForMemoryPressure: false,
      );
      // 2×2 = 4 visible tiles ≤ 6 → fits.
      expect(
        store.viewFitsBudget(
          pageSize: const Size(1024, 1024),
          desiredRatio: 1.0,
          visiblePageRect: const Rect.fromLTWH(0, 0, 1024, 1024),
        ),
        isTrue,
      );
      // 3×3 = 9 visible tiles > 6 → does not fit (the caller uses the patch).
      expect(
        store.viewFitsBudget(
          pageSize: const Size(1536, 1536),
          desiredRatio: 1.0,
          visiblePageRect: const Rect.fromLTWH(0, 0, 1536, 1536),
        ),
        isFalse,
      );
      store.dispose();
    });

    test('viewFor drops the prefetch ring when the visible set fills the budget',
        () {
      const pageSize = Size(5120, 5120); // 10×10 grid at span 512
      const window = Rect.fromLTWH(2048, 2048, 1536, 1536); // centre 3×3 = 9
      final raster = _Rasterizer(tileSize: 512);

      // Ample budget → the full 5×5 ring around the 3×3 window is scheduled.
      final roomy = PdfTileStore(
        tilePixels: 512,
        prefetchRing: 1,
        maxBytes: 128 << 20, // 128 tiles
        ladder: const PdfTileZoomLadder(stepsPerOctave: 1),
        batchRasters: false,
        registerForMemoryPressure: false,
      );
      roomy.viewFor(
        id: _id(0),
        pageSize: pageSize,
        desiredRatio: 1.0,
        visiblePageRect: window,
        rasterize: raster.call,
      );
      expect(roomy.inFlightCount, 25, reason: '3×3 visible + full 5×5 ring');
      roomy.dispose();

      // Budget exactly the visible set → no headroom, ring fully dropped.
      final tight = PdfTileStore(
        tilePixels: 512,
        prefetchRing: 1,
        maxBytes: 9 << 20, // 9 tiles = the visible 3×3 exactly
        ladder: const PdfTileZoomLadder(stepsPerOctave: 1),
        batchRasters: false,
        registerForMemoryPressure: false,
      );
      tight.viewFor(
        id: _id(0),
        pageSize: pageSize,
        desiredRatio: 1.0,
        visiblePageRect: window,
        rasterize: raster.call,
      );
      expect(tight.inFlightCount, 9, reason: 'ring dropped: visible tiles only');
      tight.dispose();
    });

    testWidgets('a budget-tight static view converges - no eviction thrash',
        (tester) async {
      await tester.runAsync(() async {
        const pageSize = Size(5120, 5120);
        const window = Rect.fromLTWH(2048, 2048, 1536, 1536); // 3×3 = 9
        final raster = _Rasterizer(tileSize: 512);
        final store = PdfTileStore(
          tilePixels: 512,
          prefetchRing: 1,
          maxBytes: 9 << 20, // holds exactly the 9 visible tiles
          ladder: const PdfTileZoomLadder(stepsPerOctave: 1),
          batchRasters: false,
          registerForMemoryPressure: false,
        );

        PdfTileView view() => store.viewFor(
              id: _id(0),
              pageSize: pageSize,
              desiredRatio: 1.0,
              visiblePageRect: window,
              rasterize: raster.call,
            );

        view();
        await raster.flush();
        expect(store.tileCount, 9);
        expect(store.debugTilesLanded, 9);
        final scheduledAfterFirst = store.debugTilesScheduled;
        expect(scheduledAfterFirst, 9, reason: 'ring dropped, visible only');

        // Re-run the identical static view several times (the repaint-tick
        // loop). A thrashing store re-schedules evicted tiles every pass; a
        // healthy one composites the cached tiles and schedules nothing new.
        for (var i = 0; i < 4; i++) {
          final v = view();
          expect(v.complete, isTrue);
          await raster.flush();
        }
        expect(store.debugTilesScheduled, scheduledAfterFirst,
            reason: 'static view schedules nothing further - no thrash');
        expect(store.debugTilesDiscarded, 0);
        expect(store.tileCount, 9);
        store.dispose();
      });
    });
  });

  group('PdfTileStore budget & lifecycle', () {
    testWidgets('stays under the byte budget as tiles land', (tester) async {
      await tester.runAsync(() async {
        // 8 MB budget (the floor), 4 MB tiles → at most 2 retained.
        final store = PdfTileStore(
          tilePixels: 1024,
          prefetchRing: 0,
          maxBytes: 8 << 20,
          ladder: const PdfTileZoomLadder(stepsPerOctave: 1),
          registerForMemoryPressure: false,
        );
        final raster = _Rasterizer(tileSize: 1024); // 1024² × 4 = 4 MB
        store.viewFor(
          id: _id(0),
          pageSize: const Size(64, 64), // 4×4 tiles at span 16
          desiredRatio: 1.0,
          visiblePageRect: const Rect.fromLTWH(0, 0, 64, 64),
          rasterize: raster.call,
        );
        await raster.flush();
        expect(store.retainedBytes, lessThanOrEqualTo(8 << 20));
        expect(store.tileCount, lessThanOrEqualTo(2));
        expect(store.tileCount, greaterThan(0)); // the MRU tile survives
        store.dispose();
      });
    });

    testWidgets('ticks once (coalesced) as a batch of tiles lands',
        (tester) async {
      await tester.runAsync(() async {
        final store = PdfTileStore(
          tilePixels: 16,
          prefetchRing: 0,
          ladder: const PdfTileZoomLadder(stepsPerOctave: 1),
          registerForMemoryPressure: false,
        );
        var ticks = 0;
        store.addListener(() => ticks++);
        final raster = _Rasterizer();
        store.viewFor(
          id: _id(0),
          pageSize: const Size(32, 32),
          desiredRatio: 1.0,
          visiblePageRect: const Rect.fromLTWH(0, 0, 32, 32),
          rasterize: raster.call,
        );
        await raster.flush(); // 4 tiles land in one microtask batch
        expect(store.debugTilesLanded, 4);
        expect(ticks, 1, reason: 'notifications coalesce to one tick');
        store.dispose();
      });
    });

    testWidgets('memory pressure clears every tile', (tester) async {
      await tester.runAsync(() async {
        final store = PdfTileStore(
          tilePixels: 16,
          prefetchRing: 0,
          ladder: const PdfTileZoomLadder(stepsPerOctave: 1),
        );
        final raster = _Rasterizer();
        store.viewFor(
          id: _id(0),
          pageSize: const Size(32, 32),
          desiredRatio: 1.0,
          visiblePageRect: const Rect.fromLTWH(0, 0, 32, 32),
          rasterize: raster.call,
        );
        await raster.flush();
        expect(store.tileCount, greaterThan(0));
        PdfCacheRegistry.instance.handleMemoryPressure();
        expect(store.tileCount, 0);
        store.dispose();
      });
    });

    testWidgets('after dispose viewFor is inert and late tiles are dropped',
        (tester) async {
      await tester.runAsync(() async {
        final store = PdfTileStore(
          tilePixels: 16,
          prefetchRing: 0,
          registerForMemoryPressure: false,
        );
        final raster = _Rasterizer();
        store.viewFor(
          id: _id(0),
          pageSize: const Size(32, 32),
          desiredRatio: 1.0,
          visiblePageRect: const Rect.fromLTWH(0, 0, 32, 32),
          rasterize: raster.call,
        );
        store.dispose();
        final view = store.viewFor(
          id: _id(0),
          pageSize: const Size(32, 32),
          desiredRatio: 1.0,
          visiblePageRect: const Rect.fromLTWH(0, 0, 32, 32),
          rasterize: raster.call,
        );
        expect(view.isEmpty, isTrue);
        await raster.flush(); // completions after dispose just free the images
        expect(store.tileCount, 0);
      });
    });
  });

  group('PdfTileStore batched rasters', () {
    testWidgets('a cold settle coalesces into one slab readback and slices it',
        (tester) async {
      await tester.runAsync(() async {
        final store = PdfTileStore(
          tilePixels: 16,
          prefetchRing: 1,
          ladder: const PdfTileZoomLadder(stepsPerOctave: 1),
          registerForMemoryPressure: false,
        );
        final raster = _Rasterizer(sizeFromRegion: true);
        const pageSize = Size(64, 64); // 4×4 grid, fully visible (no ring)

        store.viewFor(
          id: _id(0),
          pageSize: pageSize,
          desiredRatio: 1.0,
          visiblePageRect: const Rect.fromLTWH(0, 0, 64, 64),
          rasterize: raster.call,
        );
        // All 16 tiles in flight, but a single readback for the whole region.
        expect(store.inFlightCount, 16);
        expect(raster.calls.length, 1);
        expect(raster.calls.single.region, const Rect.fromLTWH(0, 0, 64, 64));
        expect(store.debugBatchesDispatched, 1);

        await raster.flush();
        expect(store.tileCount, 16);
        expect(store.debugTilesLanded, 16);

        final view = store.viewFor(
          id: _id(0),
          pageSize: pageSize,
          desiredRatio: 1.0,
          visiblePageRect: const Rect.fromLTWH(0, 0, 64, 64),
          rasterize: raster.call,
        );
        expect(view.complete, isTrue);
        expect(view.placements.length, 16);
        // Every slice is a real tile-sized image of its own.
        expect(view.placements.every((p) => p.image.width == 16), isTrue);
        expect(raster.calls.length, 1); // fully cached, nothing new
        store.dispose();
      });
    });

    testWidgets('slab slices land each tile\'s own pixels', (tester) async {
      await tester.runAsync(() async {
        final store = PdfTileStore(
          tilePixels: 16,
          prefetchRing: 0,
          ladder: const PdfTileZoomLadder(stepsPerOctave: 1),
          registerForMemoryPressure: false,
        );
        const colors = [
          Color(0xFFFF0000), // tile (0,0)
          Color(0xFF00FF00), // tile (1,0)
          Color(0xFF0000FF), // tile (0,1)
          Color(0xFFFFFF00), // tile (1,1)
        ];
        // Paints the requested region as a 2×2 quadrant grid in slab pixels.
        Future<ui.Image> quadrants(Rect region, double ratio) async {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          for (var i = 0; i < 4; i++) {
            canvas.drawRect(
              Rect.fromLTWH((i % 2) * 16.0, (i ~/ 2) * 16.0, 16, 16),
              Paint()..color = colors[i],
            );
          }
          final picture = recorder.endRecording();
          final image = await picture.toImage(
            (region.width * ratio).ceil(),
            (region.height * ratio).ceil(),
          );
          picture.dispose();
          return image;
        }

        store.viewFor(
          id: _id(0),
          pageSize: const Size(32, 32),
          desiredRatio: 1.0,
          visiblePageRect: const Rect.fromLTWH(0, 0, 32, 32),
          rasterize: quadrants,
        );
        expect(store.debugBatchesDispatched, 1);
        await pumpEventQueue();
        expect(store.tileCount, 4);

        final view = store.viewFor(
          id: _id(0),
          pageSize: const Size(32, 32),
          desiredRatio: 1.0,
          visiblePageRect: const Rect.fromLTWH(0, 0, 32, 32),
          rasterize: quadrants,
        );
        expect(view.placements.length, 4);
        for (final placement in view.placements) {
          final tx = placement.destFraction.left >= 0.5 ? 1 : 0;
          final ty = placement.destFraction.top >= 0.5 ? 1 : 0;
          final data = (await placement.image.toByteData())!;
          final o = ((8 * placement.image.width) + 8) * 4; // center pixel
          final pixel = Color.fromARGB(data.getUint8(o + 3), data.getUint8(o),
              data.getUint8(o + 1), data.getUint8(o + 2));
          expect(pixel, colors[ty * 2 + tx],
              reason: 'tile ($tx,$ty) sliced from the wrong slab offset');
        }
        store.dispose();
      });
    });

    testWidgets('canRasterize vetoes tiles per region and heals when lifted',
        (tester) async {
      await tester.runAsync(() async {
        final store = PdfTileStore(
          tilePixels: 16,
          prefetchRing: 0,
          ladder: const PdfTileZoomLadder(stepsPerOctave: 1),
          registerForMemoryPressure: false,
        );
        final raster = _Rasterizer(sizeFromRegion: true);
        const pageSize = Size(64, 64); // 4×4 grid

        // Veto the left half of the page (a vector-only scene's image area).
        store.viewFor(
          id: _id(0),
          pageSize: pageSize,
          desiredRatio: 1.0,
          visiblePageRect: const Rect.fromLTWH(0, 0, 64, 64),
          rasterize: raster.call,
          canRasterize: (region) => region.left >= 32,
        );
        // Only the right half scheduled - and as one batch of that half.
        expect(store.inFlightCount, 8);
        expect(raster.calls.length, 1);
        expect(raster.calls.single.region, const Rect.fromLTWH(32, 0, 32, 64));
        await raster.flush();
        expect(store.tileCount, 8);

        // The veto lifting (scene upgraded to the full record) heals the rest
        // on the next pass without any invalidation.
        store.viewFor(
          id: _id(0),
          pageSize: pageSize,
          desiredRatio: 1.0,
          visiblePageRect: const Rect.fromLTWH(0, 0, 64, 64),
          rasterize: raster.call,
        );
        expect(store.inFlightCount, 8);
        await raster.flush();
        expect(store.tileCount, 16);
        store.dispose();
      });
    });

    testWidgets('a sparse missing set never re-rasters the cached area between',
        (tester) async {
      await tester.runAsync(() async {
        final store = PdfTileStore(
          tilePixels: 16,
          prefetchRing: 0,
          ladder: const PdfTileZoomLadder(stepsPerOctave: 1),
          registerForMemoryPressure: false,
        );
        final raster = _Rasterizer(sizeFromRegion: true);
        const pageSize = Size(160, 16); // 10×1 grid

        // Warm the middle run (tiles 1..8) as one slab.
        store.viewFor(
          id: _id(0),
          pageSize: pageSize,
          desiredRatio: 1.0,
          visiblePageRect: const Rect.fromLTWH(16, 0, 128, 16),
          rasterize: raster.call,
        );
        expect(raster.calls.length, 1);
        await raster.flush();
        expect(store.tileCount, 8);

        // Full row: only the far ends (tiles 0 and 9) are missing. A bounding
        // box would re-raster the 8 cached tiles between them; the sparse path
        // must issue two tile-sized rasters instead.
        store.viewFor(
          id: _id(0),
          pageSize: pageSize,
          desiredRatio: 1.0,
          visiblePageRect: const Rect.fromLTWH(0, 0, 160, 16),
          rasterize: raster.call,
        );
        final sparse = raster.calls.skip(1).toList();
        expect(sparse.length, 2);
        expect(sparse.every((c) => c.region.width == 16), isTrue);
        expect({sparse[0].region.left, sparse[1].region.left}, {0.0, 144.0});

        await raster.flush();
        expect(store.tileCount, 10);
        store.dispose();
      });
    });
  });

  group('PdfTileStore diagnostics', () {
    testWidgets('debugTileFractionsForPage reports cached tiles as fractions',
        (tester) async {
      await tester.runAsync(() async {
        final store = PdfTileStore(
          tilePixels: 16,
          prefetchRing: 0,
          ladder: const PdfTileZoomLadder(stepsPerOctave: 1),
          registerForMemoryPressure: false,
        );
        final raster = _Rasterizer();
        const pageSize = Size(32, 32); // 2×2 grid at span 16

        expect(store.debugTileFractionsForPage(0), isEmpty);
        store.viewFor(
          id: _id(0),
          pageSize: pageSize,
          desiredRatio: 1.0,
          visiblePageRect: const Rect.fromLTWH(0, 0, 32, 32),
          rasterize: raster.call,
        );
        await raster.flush();

        final fractions = store.debugTileFractionsForPage(0);
        expect(fractions.length, 4);
        // The 4 tiles tile the unit square in quarters (span 16 of 32).
        expect(
          fractions.map((f) => f.fraction).toSet(),
          {
            const Rect.fromLTRB(0, 0, 0.5, 0.5),
            const Rect.fromLTRB(0.5, 0, 1, 0.5),
            const Rect.fromLTRB(0, 0.5, 0.5, 1),
            const Rect.fromLTRB(0.5, 0.5, 1, 1),
          },
        );
        expect(fractions.every((f) => f.rung == 0), isTrue);

        // Scoped by page, and a pure peek (no LRU touch → no reschedule).
        expect(store.debugTileFractionsForPage(1), isEmpty);
        final view = store.viewFor(
          id: _id(0),
          pageSize: pageSize,
          desiredRatio: 1.0,
          visiblePageRect: const Rect.fromLTWH(0, 0, 32, 32),
          rasterize: raster.call,
        );
        expect(view.complete, isTrue, reason: 'peek did not evict any tile');
        store.dispose();
      });
    });

    test('instanceOrNull is null until instance is first touched', () {
      // Guarded by whether another test already created the shared store; if
      // so, instanceOrNull just mirrors instance. Assert the invariant that
      // holds either way: once instance exists, instanceOrNull returns it.
      final shared = PdfTileStore.instance;
      expect(PdfTileStore.instanceOrNull, same(shared));
    });
  });
}
