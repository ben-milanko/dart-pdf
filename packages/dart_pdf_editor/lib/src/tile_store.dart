/// A quantized zoom-bucket pyramid of fixed-size, GPU-resident page tiles.
///
/// The classic deep-zoom path ([PdfRetainedScene.rasterizeRegion], driven by
/// `_PdfPageViewState._updateDetail`) keeps exactly one detail patch per page:
/// it is unbudgeted and dies on every settle, scene change, and edit, so a pan
/// past its bounds shows the capped base raster until a fresh whole-region
/// `toImage` lands. [PdfTileStore] instead retains many small tiles across a
/// pyramid of zoom buckets under one shared budget, so panning at deep zoom
/// composites cached tiles with zero re-raster and a settle only rasterizes the
/// handful of visible tiles that are missing.
///
/// A tile is a region raster (see [PdfRetainedScene.rasterizeRegion]) of fixed
/// physical size ([PdfTileStore.tilePixels]² ≈ 1 MB RGBA), keyed by
/// `(page identity, plan, zoom bucket, column, row)` - every identity already
/// carried by [PdfPageRenderIntent] and [PdfPageRenderPlan]. Storage is one
/// [PdfBudgetedCache] weighed by tile bytes, evicting by least-recently used
/// and registered with the coordinated memory-pressure path.
///
/// The presentation contract is small and synchronous: [viewFor] returns the
/// best-available tiles *now* - exact-bucket tiles where cached, else the
/// nearest coarser bucket upscaled - and schedules the missing ones; the store
/// is a [Listenable] that ticks as sharper tiles land so the page view repaints
/// them via `canvas.drawImageRect`.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'budgeted_cache.dart';
import 'perf_log.dart';
import 'performance_policy.dart';
import 'renderer.dart';

/// Rasterizes one tile: [region] is the tile's bounds in page points (the
/// y-down raster space [PdfRetainedScene.rasterizeRegion] takes), [pixelRatio]
/// the bucket ratio. The returned image is owned by the store.
typedef PdfTileRasterizer = Future<ui.Image> Function(
    Rect region, double pixelRatio);

/// Optional persistent backing for the LoD pyramid.
///
/// Loads race the ordinary raster path: a slow or missing store never delays
/// rendering, while a fast hit may populate the memory cache first. Stores are
/// started only after a newly-rendered tile has landed, so image readback and
/// compression are never on the path between raster completion and display.
abstract interface class PdfTilePersistence {
  Future<ui.Image?> loadTile(
    PdfTileKey key, {
    required Rect region,
    required double pixelRatio,
    required int width,
    required int height,
  });

  /// Best-effort write-through. Implementations must retain or clone [image]
  /// synchronously before their first await because the memory LRU owns it.
  Future<void> storeTile(
    PdfTileKey key,
    ui.Image image, {
    required Rect region,
    required double pixelRatio,
  });
}

/// The discrete ×√2 (or ×2) pixel-ratio ladder tiles are rastered on.
///
/// A continuous zoom would raster every tile at a slightly different ratio and
/// never reuse one; snapping the desired ratio to a rung means a small pan or
/// pinch keeps hitting the same rung's tiles. Rung 0 is ratio 1.0; each rung is
/// [stepsPerOctave]-th of a doubling, so the default of 2 gives a ×√2 ladder.
@immutable
class PdfTileZoomLadder {
  const PdfTileZoomLadder({
    this.stepsPerOctave = 2,
    this.minRung = -8,
    this.maxRung = 16,
  })  : assert(stepsPerOctave >= 1),
        assert(minRung <= 0 && maxRung >= 0);

  /// Rungs per factor-of-two of pixel ratio. 1 is a ×2 ladder, 2 is ×√2.
  final int stepsPerOctave;

  /// Clamp bounds so a degenerate desired ratio can't select an absurd bucket
  /// (ratio floor 0.05 / a huge accidental zoom). minRung ratio ≈ 2^(min/steps).
  final int minRung;
  final int maxRung;

  /// The rung whose ratio is nearest [ratio] (in log space), clamped.
  int rungFor(double ratio) {
    final safe = ratio <= 0 ? 0.05 : ratio;
    final raw = (math.log(safe) / math.ln2) * stepsPerOctave;
    return raw.round().clamp(minRung, maxRung);
  }

  /// The first rung whose pixel ratio is at or above [ratio], clamped.
  ///
  /// Exact settled tiles use this rung so they are never permanently
  /// upscaled. A cached lower rung may still be presented as a temporary
  /// fallback while this sharper rung is rasterizing.
  int rungAtOrAbove(double ratio) {
    final safe = ratio <= 0 ? 0.05 : ratio;
    final raw = (math.log(safe) / math.ln2) * stepsPerOctave;
    // Subtract a tiny tolerance so ratioFor(rung) round-trips to that rung
    // despite floating-point log/pow noise instead of spuriously jumping one
    // level higher.
    return (raw - 1e-10).ceil().clamp(minRung, maxRung);
  }

  /// The exact pixel ratio a [rung]'s tiles are rastered at.
  double ratioFor(int rung) => math.pow(2, rung / stepsPerOctave).toDouble();
}

/// Everything about a page's visual state that changes what a tile should
/// contain: the page slot and its epoch/content/destructive stamps (from
/// [PdfPageRenderIntent]) plus the display [plan] (paper color, annotations,
/// rotation, from [PdfPageRenderPlan]). Two identities that compare equal may
/// share tiles; any difference is a distinct key so stale pixels never surface.
@immutable
class PdfTilePageIdentity {
  const PdfTilePageIdentity({
    this.cacheNamespace,
    required this.pageIndex,
    required this.pageEpoch,
    required this.contentStamp,
    required this.destructiveStamp,
    required this.plan,
  });

  /// Stable identity of the viewer/document lineage that owns this tile.
  ///
  /// [PdfTileStore.instance] is process-wide, including across tabs and native
  /// windows. Page index and revision stamps are only unique inside one
  /// document, so omitting this boundary lets page 58 in one tab consume page
  /// 58's pixels from another. Keep the same value across incremental
  /// revisions to preserve unchanged-page reuse, and replace it when a viewer
  /// opens an unrelated document. Null remains useful for isolated stores and
  /// backwards-compatible tests.
  final Object? cacheNamespace;

  final int pageIndex;
  final int pageEpoch;
  final int contentStamp;
  final int destructiveStamp;
  final PdfPageRenderPlan plan;

  @override
  bool operator ==(Object other) =>
      other is PdfTilePageIdentity &&
      identical(cacheNamespace, other.cacheNamespace) &&
      pageIndex == other.pageIndex &&
      pageEpoch == other.pageEpoch &&
      contentStamp == other.contentStamp &&
      destructiveStamp == other.destructiveStamp &&
      plan == other.plan;

  @override
  int get hashCode => Object.hash(identityHashCode(cacheNamespace), pageIndex,
      pageEpoch, contentStamp, destructiveStamp, plan);
}

class _PdfTilePageSlot {
  const _PdfTilePageSlot(this.cacheNamespace, this.pageIndex);

  final Object? cacheNamespace;
  final int pageIndex;

  @override
  bool operator ==(Object other) =>
      other is _PdfTilePageSlot &&
      identical(cacheNamespace, other.cacheNamespace) &&
      pageIndex == other.pageIndex;

  @override
  int get hashCode => Object.hash(identityHashCode(cacheNamespace), pageIndex);
}

/// The full cache key of a single tile.
@immutable
class PdfTileKey {
  const PdfTileKey(this.id, this.rung, this.tx, this.ty);

  final PdfTilePageIdentity id;
  final int rung;
  final int tx;
  final int ty;

  @override
  bool operator ==(Object other) =>
      other is PdfTileKey &&
      rung == other.rung &&
      tx == other.tx &&
      ty == other.ty &&
      id == other.id;

  @override
  int get hashCode => Object.hash(id, rung, tx, ty);
}

/// A retained tile image plus the page-point region it covers and the bucket it
/// belongs to. Owned by the store's cache; disposed on eviction.
class PdfTile {
  PdfTile(this.image, this.region, this.rung, this.pageFraction);

  final ui.Image image;

  /// The tile's bounds in page points (clamped to the page at the edges).
  final Rect region;
  final int rung;

  /// [region] as fractions (0..1) of the page - recorded at raster time so
  /// diagnostics (the thumbnail debug overlay) can place the tile without
  /// knowing the page size.
  final Rect pageFraction;

  int get bytes => image.width * image.height * 4;
}

/// One `drawImageRect` a [PdfTileView] asks the painter to issue: [src] pixels
/// of [image] scaled into [destFraction] (0..1 of the page rect).
@immutable
class PdfTilePlacement {
  const PdfTilePlacement({
    required this.image,
    required this.src,
    required this.destFraction,
    this.isFallback = false,
  });

  final ui.Image image;
  final Rect src;
  final Rect destFraction;

  /// True when this placement upscales a coarser-bucket tile standing in for
  /// a missing exact tile (diagnostic - drawn differently by the debug
  /// border overlay).
  final bool isFallback;
}

/// The synchronous result of [PdfTileStore.viewFor]: the tiles to composite for
/// the requested viewport right now, plus whether every visible tile was
/// available at the exact bucket ([complete] = no upscaled fallback in play).
@immutable
class PdfTileView {
  const PdfTileView({
    required this.rung,
    required this.placements,
    required this.complete,
  });

  static const empty =
      PdfTileView(rung: 0, placements: <PdfTilePlacement>[], complete: true);

  /// The zoom bucket this view targeted.
  final int rung;

  /// Composited bottom-to-top (fallbacks and exact tiles never overlap, so the
  /// order only matters for determinism).
  final List<PdfTilePlacement> placements;

  /// True when no coarser-bucket fallback was needed - the view is fully sharp.
  final bool complete;

  bool get isEmpty => placements.isEmpty;
}

/// Byte-budget admission decision for one exact-bucket visible tile set.
@immutable
class PdfTileBudgetStatus {
  const PdfTileBudgetStatus({
    required this.rung,
    required this.visibleTiles,
    required this.capacity,
    required this.limit,
  });

  final int rung;
  final int visibleTiles;
  final int capacity;
  final int limit;

  bool get fits => visibleTiles <= limit;
}

/// The tile pyramid. Instantiable (tests, an isolated page) with a shared
/// process-wide default ([instance]) so one budget spans every page, replacing
/// the unbudgeted per-page detail patch and image retention.
class PdfTileStore extends ChangeNotifier {
  PdfTileStore({
    this.tilePixels = 512,
    this.ladder = const PdfTileZoomLadder(),
    int? maxBytes,
    this.prefetchRing = 1,
    this.maxPrefetchInFlightTiles = 4,
    this.maxFallbackDepth = 4,
    this.batchRasters = true,
    this.maxBatchTilesPerAxis = 8,
    bool registerForMemoryPressure = true,
  })  : assert(maxPrefetchInFlightTiles > 0),
        assert(tilePixels * maxBatchTilesPerAxis <= 1 << 14,
            'a batch slab must fit the engine texture limit'),
        _cache = PdfBudgetedCache<PdfTileKey, PdfTile>(
          weigher: (tile) => tile.bytes,
          maxWeight: math.max(
            maxBytes ?? pdfDefaultTileBudgetBytes(),
            _minBytes,
          ),
          disposer: (tile) => tile.image.dispose(),
          clearsUnderMemoryPressure: registerForMemoryPressure,
          debugLabel: 'tiles',
        );

  /// A floor so a viewport's worth of tiles is never evicted out from under the
  /// view that just asked for them (see [viewFor]'s MRU-protection contract).
  static const _minBytes = 8 << 20;

  static PdfTileStore? _instance;

  /// The shared store the viewer uses. Lazily created so nothing is allocated
  /// (or registered for memory pressure) unless the tile path is exercised.
  static PdfTileStore get instance => _instance ??= PdfTileStore();

  /// The shared store if one was ever created, without creating it -
  /// diagnostics must not allocate a pyramid just by looking.
  static PdfTileStore? get instanceOrNull => _instance;

  /// Physical pixels per tile side. A tile at bucket ratio r covers
  /// `tilePixels / r` page points per side.
  final int tilePixels;
  final PdfTileZoomLadder ladder;

  /// How many tiles beyond the visible range to pre-raster on each side, so a
  /// pan reveals ready tiles instead of blanks.
  final int prefetchRing;

  /// Maximum exact-rung prefetch tiles submitted concurrently for one page
  /// view. Ring work is background work: bounding it prevents unrelated
  /// repaints from filling the Canvas/GPU queue with every off-screen batch.
  /// A newly visible tile then waits behind at most this small window.
  final int maxPrefetchInFlightTiles;

  /// How many buckets coarser [viewFor] will search for an upscaled fallback
  /// before leaving the base raster to show through.
  final int maxFallbackDepth;

  /// Coalesce the missing tiles of one [viewFor] pass into as few region
  /// rasters as possible, then slice each returned slab into tiles GPU-side
  /// (`drawImageRect` + `toImageSync` - a blit, no scene replay and no extra
  /// readback). The per-`toImage` fixed overhead is what makes one raster per
  /// 512² tile lose to the legacy single-patch path on a cold sweep (see
  /// benchmark_tile_store_test.dart), so batching restores the patch's
  /// one-readback-per-settle cost while keeping the pyramid's reuse.
  ///
  /// A dense missing set (at least half of its bounding box, the cold-settle
  /// shape) rasters as one slab; a sparse one (revisit holes) falls back to
  /// per-row runs so cached tiles are never re-rastered. False restores one
  /// raster call per tile.
  final bool batchRasters;

  /// Cap on a batch's tile extent per axis, bounding the slab under the
  /// engine's 2^14 px texture limit (8 × 512 = 4096) and bounding the latency
  /// of any single readback.
  final int maxBatchTilesPerAxis;

  /// A missing set sparser than this fraction of its bounding box splits into
  /// per-row runs instead of one slab, bounding wasted raster area to <2×.
  static const _batchFillThreshold = 0.5;

  final PdfBudgetedCache<PdfTileKey, PdfTile> _cache;
  final Set<PdfTileKey> _inFlight = {};
  final Set<PdfTileKey> _persistentInFlight = {};

  /// Invalidation epochs: a tile whose page was invalidated after its raster
  /// was dispatched is discarded on completion (mirrors the render worker's
  /// stale-inflight guard).
  ///
  /// [_epochCounter] only stamps dispatches and invalidations in order - it is
  /// deliberately NOT the staleness test. Only [_allPagesEpoch] (raised by a
  /// full [invalidate]) and [_pageEpoch] (per page slot) make a tile stale, so
  /// a targeted invalidation cannot reach across pages.
  ///
  /// That distinction is load-bearing. `_PdfPageViewState._updateDetail` drops
  /// its detail - and so invalidates its own slot - whenever
  /// `_detailGeometryAt` returns null, which includes every page scrolled off
  /// screen. With a shared counter, each settle of an off-screen page threw
  /// away the in-flight tiles of the page actually being panned (issue #374;
  /// measured at a 55% discard rate in issue #427).
  int _epochCounter = 0;
  int _allPagesEpoch = -1;
  final Map<Object?, int> _namespaceEpoch = Map<Object?, int>.identity();
  final Map<_PdfTilePageSlot, int> _pageEpoch = {};

  bool _tickScheduled = false;
  bool _disposed = false;

  // Diagnostics (asserted in tests).
  int debugTilesScheduled = 0;
  int debugTilesLanded = 0;
  int debugTilesDiscarded = 0;
  int debugTicks = 0;
  int debugBatchesDispatched = 0;
  int debugPersistentLoads = 0;
  int debugPersistentHits = 0;
  int debugPersistentStores = 0;

  /// Total bytes of retained tiles.
  int get retainedBytes => _cache.weight;

  /// Number of retained tiles.
  int get tileCount => _cache.length;

  /// Tiles whose raster is currently in flight.
  int get inFlightCount => _inFlight.length;

  /// Distinct viewer/document namespaces currently represented by retained
  /// or in-flight tiles. Exported support snapshots use this to make
  /// cross-tab cache isolation directly auditable.
  int get debugNamespaceCount {
    final namespaces = Set<Object?>.identity();
    for (final key in _cache.keys) {
      namespaces.add(key.id.cacheNamespace);
    }
    for (final key in _inFlight) {
      namespaces.add(key.id.cacheNamespace);
    }
    for (final key in _persistentInFlight) {
      namespaces.add(key.id.cacheNamespace);
    }
    return namespaces.length;
  }

  /// The weight budget, live-adjustable (a device-memory tier could lower it).
  int get maxBytes => _cache.maxWeight;
  set maxBytes(int value) => _cache.maxWeight = math.max(value, _minBytes);

  /// Whether a tile for [key] is retained (test/diagnostic; no LRU touch).
  bool containsTile(PdfTileKey key) => _cache.containsKey(key);

  /// Diagnostic snapshot of the retained tiles for [pageIndex] (any identity
  /// generation), as page fractions + rung. Pure peek - no LRU touches. The
  /// thumbnail debug overlay draws these.
  List<({Rect fraction, int rung})> debugTileFractionsForPage(int pageIndex) =>
      [
        for (final key in _cache.keys.toList())
          if (key.id.pageIndex == pageIndex)
            if (_cache.peek(key) case final tile?)
              (fraction: tile.pageFraction, rung: tile.rung),
      ];

  /// Bytes a full tile occupies (edge tiles are clamped smaller, so this
  /// over-counts): the unit the weight budget is measured in.
  int get _fullTileBytes => tilePixels * tilePixels * 4;

  /// How many full tiles the current weight budget holds. [viewFor] keeps one
  /// pass's resident set under this so the LRU never evicts a tile the live
  /// view still needs - the eviction thrash issues #314/#360 hit on dense,
  /// many-tile views (a HiDPI viewport whose visible+ring set overran the
  /// budget re-rastered on every repaint tick, flickering even when static).
  int get budgetTileCapacity => math.max(1, maxBytes ~/ _fullTileBytes);

  /// A single view may claim at most this fraction of [budgetTileCapacity] and
  /// still be tiled; the remainder is headroom for coarser fallback tiles, edge
  /// under-fill, and a margin against eviction. Beyond it the caller falls back
  /// to the single detail patch (see [viewFitsBudget]).
  static const _budgetFitFraction = 0.75;

  /// The exact-bucket tile grid one [viewFor] pass touches for this view: the
  /// rung [desiredRatio] snaps to, its ratio and page-point tile [span], the
  /// full page grid dims, and the visible tile range. Null when the view is
  /// degenerate. Shared by [viewFor] and [viewFitsBudget] so the fit test and
  /// the scheduler count exactly the same tiles.
  ({
    int rung,
    double ratio,
    double span,
    int nx,
    int ny,
    int tx0,
    int ty0,
    int tx1,
    int ty1,
  })? _tileGrid(Size pageSize, double desiredRatio, Rect visiblePageRect) {
    if (pageSize.width <= 0 ||
        pageSize.height <= 0 ||
        visiblePageRect.isEmpty) {
      return null;
    }
    // A settled exact tile must carry at least one source pixel per physical
    // display pixel. Nearest-rung snapping can choose the lower level (for
    // example 0.50x at a 0.57x display ratio), leaving a permanently upscaled
    // page that is technically "complete" but still visibly soft.
    final rung = ladder.rungAtOrAbove(desiredRatio);
    final ratio = ladder.ratioFor(rung);
    final span = tilePixels / ratio; // page points per tile side
    if (!span.isFinite || span <= 0) return null;
    final nx = math.max(1, (pageSize.width / span).ceil());
    final ny = math.max(1, (pageSize.height / span).ceil());
    final visible = visiblePageRect.intersect(Offset.zero & pageSize);
    if (visible.isEmpty) return null;
    final tx0 = (visible.left / span).floor().clamp(0, nx - 1);
    final ty0 = (visible.top / span).floor().clamp(0, ny - 1);
    final tx1 = ((visible.right / span).ceil() - 1).clamp(0, nx - 1);
    final ty1 = ((visible.bottom / span).ceil() - 1).clamp(0, ny - 1);
    return (
      rung: rung,
      ratio: ratio,
      span: span,
      nx: nx,
      ny: ny,
      tx0: tx0,
      ty0: ty0,
      tx1: tx1,
      ty1: ty1,
    );
  }

  /// The page-point region containing every tile [viewFor] can schedule for
  /// this view, including its configured prefetch ring.
  ///
  /// Region-scoped image decoders use this before admitting tile work. A
  /// merely visible-pixel-aligned decode is insufficient: [viewFor] rasters
  /// whole grid cells, so a tile that extends outside that decode would have
  /// to replay from a lower-resolution base scene and then remain cached under
  /// the same zoom key.
  Rect? rasterCoverageForView({
    required Size pageSize,
    required double desiredRatio,
    required Rect visiblePageRect,
    int? prefetchRingOverride,
  }) {
    assert(prefetchRingOverride == null || prefetchRingOverride >= 0);
    final grid = _tileGrid(pageSize, desiredRatio, visiblePageRect);
    if (grid == null) return null;
    final ring = prefetchRingOverride ?? prefetchRing;
    final tx0 = math.max(0, grid.tx0 - ring);
    final ty0 = math.max(0, grid.ty0 - ring);
    final tx1 = math.min(grid.nx - 1, grid.tx1 + ring);
    final ty1 = math.min(grid.ny - 1, grid.ty1 + ring);
    return _clampToPage(
      Rect.fromLTRB(
        tx0 * grid.span,
        ty0 * grid.span,
        (tx1 + 1) * grid.span,
        (ty1 + 1) * grid.span,
      ),
      pageSize,
    );
  }

  /// Whether tiling this view fits the weight budget with margin - so a
  /// [viewFor] pass will not thrash the shared LRU. Counts the visible
  /// exact-bucket tiles only (the prefetch ring is dropped under pressure
  /// inside [viewFor]); false means the caller should use the single detail
  /// patch instead, which covers an arbitrarily large view in one raster
  /// without evicting the pyramid. The page view consults this before it
  /// engages the tile layer.
  bool viewFitsBudget({
    required Size pageSize,
    required double desiredRatio,
    required Rect visiblePageRect,
  }) =>
      viewBudgetStatus(
        pageSize: pageSize,
        desiredRatio: desiredRatio,
        visiblePageRect: visiblePageRect,
      )?.fits ??
      false;

  /// Explains [viewFitsBudget] for field diagnostics and tuning.
  PdfTileBudgetStatus? viewBudgetStatus({
    required Size pageSize,
    required double desiredRatio,
    required Rect visiblePageRect,
  }) {
    final grid = _tileGrid(pageSize, desiredRatio, visiblePageRect);
    if (grid == null) return null;
    final visible = (grid.tx1 - grid.tx0 + 1) * (grid.ty1 - grid.ty0 + 1);
    final capacity = budgetTileCapacity;
    return PdfTileBudgetStatus(
      rung: grid.rung,
      visibleTiles: visible,
      capacity: capacity,
      limit: (capacity * _budgetFitFraction).floor(),
    );
  }

  /// The best-available composite for [id] over [visiblePageRect] (page points)
  /// at [desiredRatio], scheduling the missing exact-bucket tiles (center-out)
  /// plus a one-tile prefetch ring. Missing tiles fall back per-tile to the
  /// nearest coarser cached bucket, upscaled; anything still uncovered leaves
  /// the base raster showing through.
  ///
  /// [canRasterize], when given, vetoes scheduling per tile region: a vetoed
  /// tile is never rastered or cached (its area keeps the fallback/base),
  /// and is re-consulted on every pass so it heals once the veto lifts. The
  /// page view uses this to tile a vector-only progressive scene everywhere
  /// except the regions its absent image pixels would corrupt.
  ///
  /// [maxNewTiles] optionally caps how many missing tiles this call admits.
  /// Tiles already cached or in flight are unaffected. A landed tile ticks the
  /// store, so a painting caller can use a small cap to spread synchronous
  /// retained-scene replay across frames while the view fills center-out.
  /// [maxInFlightTiles] additionally caps the number of admitted visible tiles
  /// that may remain unresolved across repeated paints. Unlike [maxNewTiles],
  /// this closes the loophole where unrelated frames each admitted one more
  /// raster before the first completion freed the queue.
  /// [batchRasters] overrides this store's batching policy for this view. This
  /// lets a GPU session request final tile textures directly while Canvas
  /// sessions using the same shared store continue to amortize slab replay.
  ///
  /// [prefetchRingOverride] replaces [prefetchRing] for this request. Passing
  /// zero is useful for a scale-changing frame: raster the pixels visible now
  /// before spending work on pan headroom, then restore the configured ring on
  /// subsequent pan settles.
  ///
  /// [scheduleMissing] can make a view presentation-only: retained exact or
  /// fallback tiles still paint, but neither visible misses nor the prefetch
  /// ring start new work. The viewer uses this for a narrow page sliver at a
  /// page boundary. Letting that non-foreground page refill its old pyramid
  /// makes it compete with the focused page in the shared LRU; both pages then
  /// evict and immediately re-raster one another's tiles.
  ///
  /// [allowCoarserFallback] controls presentation only: exact misses are still
  /// scheduled, but a false value leaves their area transparent instead of
  /// upscaling a lower-rung tile. This is useful above a retained vector base,
  /// which is already sharper than a coarse raster fallback.
  ///
  /// Synchronous and side-effecting: every tile it *places* is touched to
  /// most-recently-used, so a concurrent completion's eviction can only drop
  /// tiles outside the current view (the budget floor keeps a viewport's worth
  /// safely above the eviction line). The returned images are the cache masters
  /// - valid until the next completion for that key - which is exactly the
  /// window `drawImageRect` needs within one frame.
  PdfTileView viewFor({
    required PdfTilePageIdentity id,
    required Size pageSize,
    required double desiredRatio,
    required Rect visiblePageRect,
    required PdfTileRasterizer rasterize,
    PdfTilePersistence? persistence,
    bool Function(Rect region)? canRasterize,
    bool? batchRasters,
    int? maxNewTiles,
    int? maxInFlightTiles,
    int? prefetchRingOverride,
    bool scheduleMissing = true,
    bool allowCoarserFallback = true,
  }) {
    assert(maxNewTiles == null || maxNewTiles > 0);
    assert(maxInFlightTiles == null || maxInFlightTiles > 0);
    assert(prefetchRingOverride == null || prefetchRingOverride >= 0);
    if (_disposed) return PdfTileView.empty;
    final grid = _tileGrid(pageSize, desiredRatio, visiblePageRect);
    if (grid == null) return PdfTileView.empty;
    final rung = grid.rung;
    final ratio = grid.ratio;
    final span = grid.span;
    final nx = grid.nx;
    final ny = grid.ny;
    final tx0 = grid.tx0;
    final ty0 = grid.ty0;
    final tx1 = grid.tx1;
    final ty1 = grid.ty1;

    Rect tileRegion(int tx, int ty) => _clampToPage(
          Rect.fromLTWH(tx * span, ty * span, span, span),
          pageSize,
        );

    int tileBytes(int tx, int ty) {
      final size = _rasterSize(tileRegion(tx, ty), ratio);
      return size.width * size.height * 4;
    }

    // Center-out ordering: the tile under the viewport center sharpens first.
    // (_tileGrid guaranteed a non-empty intersection, so recomputing the
    // clipped visible rect for its center is safe.)
    final visible = visiblePageRect.intersect(Offset.zero & pageSize);
    final cx = (visible.center.dx / span);
    final cy = (visible.center.dy / span);
    final coords = <(int, int)>[];
    for (var ty = ty0; ty <= ty1; ty++) {
      for (var tx = tx0; tx <= tx1; tx++) {
        coords.add((tx, ty));
      }
    }
    coords.sort((a, b) {
      final da = (a.$1 + 0.5 - cx) * (a.$1 + 0.5 - cx) +
          (a.$2 + 0.5 - cy) * (a.$2 + 0.5 - cy);
      final db = (b.$1 + 0.5 - cx) * (b.$1 + 0.5 - cx) +
          (b.$2 + 0.5 - cy) * (b.$2 + 0.5 - cy);
      return da.compareTo(db);
    });

    final placements = <PdfTilePlacement>[];
    final pending = (batchRasters ?? this.batchRasters) ? <PdfTileKey>[] : null;
    var newTiles = 0;
    var inFlightForView =
        _inFlight.where((key) => key.id == id && key.rung == rung).length;
    bool schedule(
      PdfTileKey key, {
      required bool notifyOnLand,
      int? inFlightLimit,
    }) {
      if (maxNewTiles != null && newTiles >= maxNewTiles) return false;
      // Already-admitted work consumes no new slot. Its original visible/ring
      // completion will tick the layer, so the current view will see it land.
      if (_inFlight.contains(key)) return false;
      if (inFlightLimit != null && inFlightForView >= inFlightLimit) {
        return false;
      }
      final scheduled = _schedule(
        key,
        id,
        pageSize,
        span,
        ratio,
        rasterize,
        persistence,
        pending,
        canRasterize,
        notifyOnLand: notifyOnLand,
      );
      if (scheduled) {
        newTiles++;
        inFlightForView++;
      }
      return scheduled;
    }

    var complete = true;
    for (final (tx, ty) in coords) {
      final key = PdfTileKey(id, rung, tx, ty);
      final tile = _cache.take(key); // hit → promote to MRU
      if (tile != null) {
        placements.add(PdfTilePlacement(
          image: tile.image,
          src: Rect.fromLTWH(
              0, 0, tile.image.width.toDouble(), tile.image.height.toDouble()),
          destFraction: _fractionOf(tile.region, pageSize),
        ));
      } else {
        complete = false;
        if (scheduleMissing) {
          schedule(
            key,
            notifyOnLand: true,
            inFlightLimit: maxInFlightTiles,
          );
        }
        final fallback = allowCoarserFallback
            ? _coarserFallback(id, rung, tx, ty, span, pageSize)
            : null;
        if (fallback != null) placements.add(fallback);
      }
    }

    // Prefetch ring: pre-raster the border just outside the visible range so a
    // pan reveals ready tiles. Admit it only after every visible tile is exact:
    // with batched rasters, merely appending the ring after the visible keys
    // coalesced both into one large slab and made first sharp paint wait for
    // off-screen work. A visible completion notifies the layer; its next paint
    // schedules this ring as a separate background batch. Capped to the
    // byte-budget headroom left after the visible set, so a large view never
    // schedules more tiles than the LRU can hold - which would evict this
    // view's own tiles and re-raster them on every repaint (issues #314/#360).
    // Use the actual rounded raster dimensions rather than nominal tile count:
    // a sqrt(2)-ladder cell can become 513px after `ceil(region * ratio)`, so
    // 96 nominal 512px tiles do not quite fit in the 96 MiB default cache.
    // Reserve cached and in-flight ring members too. Otherwise every repaint
    // would see their reservation as free and extend the working set again.
    // A view whose visible set already fills the budget gets no ring; the page
    // view falls back to the single patch before a view gets that dense.
    final requestPrefetchRing = prefetchRingOverride ?? prefetchRing;
    if (scheduleMissing && requestPrefetchRing > 0 && complete) {
      var ringHeadroomBytes = maxBytes;
      for (final (tx, ty) in coords) {
        ringHeadroomBytes -= tileBytes(tx, ty);
      }
      if (ringHeadroomBytes > 0) {
        final rx0 = math.max(0, tx0 - requestPrefetchRing);
        final ry0 = math.max(0, ty0 - requestPrefetchRing);
        final rx1 = math.min(nx - 1, tx1 + requestPrefetchRing);
        final ry1 = math.min(ny - 1, ty1 + requestPrefetchRing);
        for (var ty = ry0; ty <= ry1; ty++) {
          for (var tx = rx0; tx <= rx1; tx++) {
            if (tx >= tx0 && tx <= tx1 && ty >= ty0 && ty <= ty1) continue;
            final bytes = tileBytes(tx, ty);
            if (bytes > ringHeadroomBytes) continue;
            ringHeadroomBytes -= bytes;
            schedule(
              PdfTileKey(id, rung, tx, ty),
              // The bounded ring is advanced by completion ticks. This also
              // promotes a ring tile cleanly when a pan makes it visible while
              // its raster is already in flight.
              notifyOnLand: true,
              inFlightLimit: maxPrefetchInFlightTiles,
            );
          }
        }
      }
    }

    if (pending != null && pending.isNotEmpty) {
      for (final group in _groupBatches(pending)) {
        _dispatchBatch(
          group,
          id,
          pageSize,
          span,
          ratio,
          rasterize,
          persistence,
          // Ring batches are bounded and advance on their own completion tick;
          // visible batches already need that tick to present their pixels.
          notifyOnLand: true,
          prefetch: complete,
        );
      }
    }

    return PdfTileView(rung: rung, placements: placements, complete: complete);
  }

  /// The coarsest-searched cached tile covering the missing fine tile's center,
  /// as an upscaled placement clipped to the overlap. Nearest coarser bucket
  /// first (sharpest available); null when nothing coarser is cached.
  PdfTilePlacement? _coarserFallback(
    PdfTilePageIdentity id,
    int rung,
    int tx,
    int ty,
    double span,
    Size pageSize,
  ) {
    final fine =
        _clampToPage(Rect.fromLTWH(tx * span, ty * span, span, span), pageSize);
    if (fine.isEmpty) return null;
    final center = fine.center;
    for (var d = 1; d <= maxFallbackDepth; d++) {
      final cr = rung - d;
      if (cr < ladder.minRung) break;
      final cratio = ladder.ratioFor(cr);
      final cspan = tilePixels / cratio;
      final ctx = (center.dx / cspan).floor();
      final cty = (center.dy / cspan).floor();
      final key = PdfTileKey(id, cr, ctx, cty);
      final tile = _cache.take(key); // promote the fallback too
      if (tile == null) continue;
      final overlap = fine.intersect(tile.region);
      if (overlap.isEmpty) continue;
      final src = Rect.fromLTRB(
        (overlap.left - tile.region.left) * cratio,
        (overlap.top - tile.region.top) * cratio,
        (overlap.right - tile.region.left) * cratio,
        (overlap.bottom - tile.region.top) * cratio,
      );
      return PdfTilePlacement(
        image: tile.image,
        src: Rect.fromLTRB(
          src.left.clamp(0, tile.image.width.toDouble()),
          src.top.clamp(0, tile.image.height.toDouble()),
          src.right.clamp(0, tile.image.width.toDouble()),
          src.bottom.clamp(0, tile.image.height.toDouble()),
        ),
        destFraction: _fractionOf(overlap, pageSize),
        isFallback: true,
      );
    }
    return null;
  }

  /// Marks [key] in-flight and either dispatches its raster now or, when
  /// [pending] is non-null (one [viewFor] pass in [batchRasters] mode), defers
  /// it into the pass's batch.
  bool _schedule(
    PdfTileKey key,
    PdfTilePageIdentity id,
    Size pageSize,
    double span,
    double ratio,
    PdfTileRasterizer rasterize,
    PdfTilePersistence? persistence,
    List<PdfTileKey>? pending,
    bool Function(Rect region)? canRasterize, {
    required bool notifyOnLand,
  }) {
    if (_disposed || _cache.containsKey(key) || _inFlight.contains(key)) {
      return false;
    }
    final region = _clampToPage(
        Rect.fromLTWH(key.tx * span, key.ty * span, span, span), pageSize);
    if (region.width <= 0 || region.height <= 0) return false;
    // Vetoed tiles are neither in-flight nor cached, so every pass re-asks -
    // the veto lifting (a scene upgrade) heals them without invalidation.
    if (canRasterize != null && !canRasterize(region)) return false;

    _inFlight.add(key);
    debugTilesScheduled++;
    _loadPersistentTile(key, id, pageSize, region, ratio, persistence,
        _epochCounter, notifyOnLand);
    if (pending != null) {
      pending.add(key);
      return true;
    }
    final dispatchEpoch = _epochCounter;
    rasterize(region, ratio).then((image) {
      _inFlight.remove(key);
      if (_disposed || _isStale(id, dispatchEpoch)) {
        image.dispose();
        debugTilesDiscarded++;
        // Invalidation can race a visible raster. Its completion releases the
        // in-flight key, so repaint now and let the current scene reschedule
        // the tile; otherwise the stale result disappears with no event to
        // replace it.
        if (notifyOnLand) _scheduleTick();
        _dropNamespaceFenceIfIdle(id.cacheNamespace);
        return;
      }
      if (_cache.containsKey(key)) {
        // A persistent hit won the race. Keep its already-visible pixels and
        // release the duplicate raster without replacing/promoting the entry.
        image.dispose();
        _dropNamespaceFenceIfIdle(id.cacheNamespace);
        return;
      }
      _cache.put(
          key, PdfTile(image, region, key.rung, _fractionOf(region, pageSize)));
      debugTilesLanded++;
      _storePersistentTile(key, image, region, ratio, persistence);
      if (notifyOnLand) _scheduleTick();
      _dropNamespaceFenceIfIdle(id.cacheNamespace);
    }, onError: (Object _, StackTrace __) {
      _inFlight.remove(key);
      debugTilesDiscarded++;
      _dropNamespaceFenceIfIdle(id.cacheNamespace);
    });
    return true;
  }

  /// Splits one pass's missing tiles into raster batches: the whole set as a
  /// single slab when it fills at least [_batchFillThreshold] of its bounding
  /// box (and fits [maxBatchTilesPerAxis]), else contiguous per-row runs so a
  /// sparse set never re-rasters the cached tiles between its holes.
  List<List<PdfTileKey>> _groupBatches(List<PdfTileKey> keys) {
    var txMin = keys.first.tx, txMax = keys.first.tx;
    var tyMin = keys.first.ty, tyMax = keys.first.ty;
    for (final k in keys) {
      txMin = math.min(txMin, k.tx);
      txMax = math.max(txMax, k.tx);
      tyMin = math.min(tyMin, k.ty);
      tyMax = math.max(tyMax, k.ty);
    }
    final w = txMax - txMin + 1;
    final h = tyMax - tyMin + 1;
    if (w <= maxBatchTilesPerAxis &&
        h <= maxBatchTilesPerAxis &&
        keys.length >= _batchFillThreshold * w * h) {
      return [keys];
    }
    final byRow = <int, List<PdfTileKey>>{};
    for (final k in keys) {
      (byRow[k.ty] ??= []).add(k);
    }
    final groups = <List<PdfTileKey>>[];
    for (final row in byRow.values) {
      row.sort((a, b) => a.tx.compareTo(b.tx));
      var run = <PdfTileKey>[row.first];
      for (final k in row.skip(1)) {
        if (k.tx == run.last.tx + 1 && run.length < maxBatchTilesPerAxis) {
          run.add(k);
        } else {
          groups.add(run);
          run = [k];
        }
      }
      groups.add(run);
    }
    return groups;
  }

  /// Rasters one batch as a single slab readback and slices it into tiles.
  /// Every key in [batch] is already in [_inFlight].
  void _dispatchBatch(
    List<PdfTileKey> batch,
    PdfTilePageIdentity id,
    Size pageSize,
    double span,
    double ratio,
    PdfTileRasterizer rasterize,
    PdfTilePersistence? persistence, {
    required bool notifyOnLand,
    required bool prefetch,
  }) {
    Rect tileRegion(PdfTileKey key) => _clampToPage(
        Rect.fromLTWH(key.tx * span, key.ty * span, span, span), pageSize);

    var txMin = batch.first.tx, txMax = batch.first.tx;
    var tyMin = batch.first.ty, tyMax = batch.first.ty;
    for (final k in batch) {
      txMin = math.min(txMin, k.tx);
      txMax = math.max(txMax, k.tx);
      tyMin = math.min(tyMin, k.ty);
      tyMax = math.max(tyMax, k.ty);
    }
    final batchRegion = _clampToPage(
        Rect.fromLTWH(txMin * span, tyMin * span, (txMax - txMin + 1) * span,
            (tyMax - tyMin + 1) * span),
        pageSize);

    final dispatchEpoch = _epochCounter;
    debugBatchesDispatched++;
    rasterize(batchRegion, ratio).then((slab) {
      for (final key in batch) {
        _inFlight.remove(key);
      }
      if (_disposed || _isStale(id, dispatchEpoch)) {
        slab.dispose();
        debugTilesDiscarded += batch.length;
        if (notifyOnLand) _scheduleTick();
        _dropNamespaceFenceIfIdle(id.cacheNamespace);
        return;
      }
      final sliceClock = PdfPerfLog.enabled ? (Stopwatch()..start()) : null;
      try {
        for (final key in batch) {
          final region = tileRegion(key);
          if (_cache.containsKey(key)) continue;
          final image = _sliceTile(slab, batchRegion, region, ratio);
          _cache.put(key,
              PdfTile(image, region, key.rung, _fractionOf(region, pageSize)));
          debugTilesLanded++;
          _storePersistentTile(key, image, region, ratio, persistence);
        }
      } finally {
        slab.dispose();
      }
      final sliceElapsedMs = (sliceClock?.elapsedMicroseconds ?? 0) / 1000;
      PdfPerfLog.log(
        'tile slice page=${id.pageIndex} rung=${batch.first.rung} '
        'class=${prefetch ? 'prefetch' : 'visible'} '
        'tiles=${batch.length} '
        'elapsed=${sliceElapsedMs.toStringAsFixed(1)}ms '
        'retained=${_cache.weight} entries=${_cache.length}'
        '${PdfPerfLog.rssSuffix()}',
      );
      if (notifyOnLand) _scheduleTick();
      _dropNamespaceFenceIfIdle(id.cacheNamespace);
    }, onError: (Object _, StackTrace __) {
      for (final key in batch) {
        _inFlight.remove(key);
      }
      debugTilesDiscarded += batch.length;
      _dropNamespaceFenceIfIdle(id.cacheNamespace);
    });
  }

  /// Cuts one tile out of a batch slab: a 1:1 `drawImageRect` blit converted
  /// with `toImageSync`, so the tile becomes its own GPU-resident texture
  /// without a scene replay or a pixel readback.
  ui.Image _sliceTile(
      ui.Image slab, Rect batchRegion, Rect tileRegion, double ratio) {
    final size = _rasterSize(tileRegion, ratio);
    final w = size.width;
    final h = size.height;
    final src = Rect.fromLTWH(
      (tileRegion.left - batchRegion.left) * ratio,
      (tileRegion.top - batchRegion.top) * ratio,
      w.toDouble(),
      h.toDouble(),
    ).intersect(
        Rect.fromLTWH(0, 0, slab.width.toDouble(), slab.height.toDouble()));
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    if (!src.isEmpty) {
      canvas.drawImageRect(
        slab,
        src,
        Rect.fromLTWH(0, 0, src.width, src.height),
        Paint()..filterQuality = FilterQuality.none,
      );
    }
    final picture = recorder.endRecording();
    try {
      return picture.toImageSync(w, h);
    } finally {
      picture.dispose();
    }
  }

  void _loadPersistentTile(
    PdfTileKey key,
    PdfTilePageIdentity id,
    Size pageSize,
    Rect region,
    double ratio,
    PdfTilePersistence? persistence,
    int dispatchEpoch,
    bool notifyOnLand,
  ) {
    if (persistence == null || !_persistentInFlight.add(key)) return;
    final size = _rasterSize(region, ratio);
    final width = size.width;
    final height = size.height;
    debugPersistentLoads++;
    persistence
        .loadTile(key,
            region: region, pixelRatio: ratio, width: width, height: height)
        .then((image) {
      _persistentInFlight.remove(key);
      if (image == null) {
        _dropNamespaceFenceIfIdle(id.cacheNamespace);
        return;
      }
      if (_disposed || _isStale(id, dispatchEpoch) || _cache.containsKey(key)) {
        image.dispose();
        _dropNamespaceFenceIfIdle(id.cacheNamespace);
        return;
      }
      _cache.put(
          key, PdfTile(image, region, key.rung, _fractionOf(region, pageSize)));
      debugPersistentHits++;
      debugTilesLanded++;
      if (notifyOnLand) _scheduleTick();
      _dropNamespaceFenceIfIdle(id.cacheNamespace);
    }, onError: (Object _, StackTrace __) {
      _persistentInFlight.remove(key);
      _dropNamespaceFenceIfIdle(id.cacheNamespace);
    });
  }

  void _storePersistentTile(PdfTileKey key, ui.Image image, Rect region,
      double pixelRatio, PdfTilePersistence? persistence) {
    if (persistence == null) return;
    debugPersistentStores++;
    // The implementation clones synchronously before its first await. This is
    // deliberately unawaited: the tile is displayable before any readback.
    unawaited(persistence.storeTile(key, image,
        region: region, pixelRatio: pixelRatio));
  }

  bool _isStale(PdfTilePageIdentity id, int dispatchEpoch) =>
      _allPagesEpoch > dispatchEpoch ||
      (_namespaceEpoch[id.cacheNamespace] ?? -1) > dispatchEpoch ||
      (_pageEpoch[_PdfTilePageSlot(id.cacheNamespace, id.pageIndex)] ?? -1) >
          dispatchEpoch;

  /// Drops every retained and in-flight tile belonging to one viewer/document
  /// lineage, without disturbing the other tabs sharing this process store.
  ///
  /// Structural page edits call this before replacing their namespace. The
  /// epoch check makes any raster or persistent load already in flight for the
  /// old page slots dispose its result instead of repopulating dead cache
  /// entries after the edit.
  void invalidateNamespace(Object? cacheNamespace) {
    if (_disposed) return;
    _namespaceEpoch[cacheNamespace] = ++_epochCounter;
    _cache.evictWhere(
      (key) => identical(key.id.cacheNamespace, cacheNamespace),
    );
    _pageEpoch.removeWhere(
      (slot, _) => identical(slot.cacheNamespace, cacheNamespace),
    );
    _dropNamespaceFenceIfIdle(cacheNamespace);
  }

  /// An invalidated namespace needs a strong epoch fence only while one of its
  /// old asynchronous requests can still complete. Drop it afterward so a
  /// long editing session with many page operations does not retain every
  /// superseded namespace object forever.
  void _dropNamespaceFenceIfIdle(Object? cacheNamespace) {
    if (!_namespaceEpoch.containsKey(cacheNamespace)) return;
    final active = _inFlight.any(
          (key) => identical(key.id.cacheNamespace, cacheNamespace),
        ) ||
        _persistentInFlight.any(
          (key) => identical(key.id.cacheNamespace, cacheNamespace),
        );
    if (!active) _namespaceEpoch.remove(cacheNamespace);
  }

  /// Drops retained (and in-flight) tiles. With [pages] null every tile is
  /// dropped; otherwise only tiles for those page slots inside
  /// [cacheNamespace] - the model
  /// [PdfCachingRenderWorker.updateRevision]'s `changedPages` feeds. In-flight
  /// rasters for the affected pages are discarded on completion.
  void invalidate({Set<int>? pages, Object? cacheNamespace}) {
    if (_disposed) return;
    final epoch = ++_epochCounter;
    if (pages == null) {
      _allPagesEpoch = epoch;
      _cache.clear();
    } else {
      for (final page in pages) {
        _pageEpoch[_PdfTilePageSlot(cacheNamespace, page)] = epoch;
      }
      _cache.evictWhere((key) =>
          identical(key.id.cacheNamespace, cacheNamespace) &&
          pages.contains(key.id.pageIndex));
    }
  }

  /// Drops retained tiles on [pageIndex] that satisfy [test], while marking
  /// every in-flight tile for that page stale.
  ///
  /// The selective retained eviction lets a newly expanded image-detail scene
  /// replace tiles that could only have come from the capped base decode while
  /// preserving already-sharp tiles in the scene's previous coverage.
  void invalidatePageTilesWhere(int pageIndex, bool Function(PdfTile tile) test,
      {Object? cacheNamespace}) {
    if (_disposed) return;
    _pageEpoch[_PdfTilePageSlot(cacheNamespace, pageIndex)] = ++_epochCounter;
    _cache.evictWhere((key) {
      if (!identical(key.id.cacheNamespace, cacheNamespace) ||
          key.id.pageIndex != pageIndex) {
        return false;
      }
      final tile = _cache.peek(key);
      return tile != null && test(tile);
    });
  }

  void _scheduleTick() {
    if (_tickScheduled || _disposed) return;
    _tickScheduled = true;
    scheduleMicrotask(() {
      _tickScheduled = false;
      if (_disposed) return;
      debugTicks++;
      notifyListeners();
    });
  }

  ({int width, int height}) _rasterSize(Rect region, double ratio) => (
        width: (region.width * ratio).ceil().clamp(1, 1 << 14),
        height: (region.height * ratio).ceil().clamp(1, 1 << 14),
      );

  Rect _clampToPage(Rect r, Size pageSize) =>
      r.intersect(Offset.zero & pageSize);

  Rect _fractionOf(Rect region, Size pageSize) => Rect.fromLTRB(
        region.left / pageSize.width,
        region.top / pageSize.height,
        region.right / pageSize.width,
        region.bottom / pageSize.height,
      );

  @override
  void dispose() {
    _disposed = true;
    _cache.dispose();
    _inFlight.clear();
    _persistentInFlight.clear();
    super.dispose();
  }
}
