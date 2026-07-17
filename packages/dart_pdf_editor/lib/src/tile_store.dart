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
import 'renderer.dart';

/// Rasterizes one tile: [region] is the tile's bounds in page points (the
/// y-down raster space [PdfRetainedScene.rasterizeRegion] takes), [pixelRatio]
/// the bucket ratio. The returned image is owned by the store.
typedef PdfTileRasterizer = Future<ui.Image> Function(
    Rect region, double pixelRatio);

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
    required this.pageIndex,
    required this.pageEpoch,
    required this.contentStamp,
    required this.destructiveStamp,
    required this.plan,
  });

  final int pageIndex;
  final int pageEpoch;
  final int contentStamp;
  final int destructiveStamp;
  final PdfPageRenderPlan plan;

  @override
  bool operator ==(Object other) =>
      other is PdfTilePageIdentity &&
      pageIndex == other.pageIndex &&
      pageEpoch == other.pageEpoch &&
      contentStamp == other.contentStamp &&
      destructiveStamp == other.destructiveStamp &&
      plan == other.plan;

  @override
  int get hashCode => Object.hash(
      pageIndex, pageEpoch, contentStamp, destructiveStamp, plan);
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
  PdfTile(this.image, this.region, this.rung);

  final ui.Image image;

  /// The tile's bounds in page points (clamped to the page at the edges).
  final Rect region;
  final int rung;

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
  });

  final ui.Image image;
  final Rect src;
  final Rect destFraction;
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

/// The tile pyramid. Instantiable (tests, an isolated page) with a shared
/// process-wide default ([instance]) so one budget spans every page, replacing
/// the unbudgeted per-page detail patch and image retention.
class PdfTileStore extends ChangeNotifier {
  PdfTileStore({
    this.tilePixels = 512,
    this.ladder = const PdfTileZoomLadder(),
    int maxBytes = _defaultMaxBytes,
    this.prefetchRing = 1,
    this.maxFallbackDepth = 4,
    bool registerForMemoryPressure = true,
  }) : _cache = PdfBudgetedCache<PdfTileKey, PdfTile>(
          weigher: (tile) => tile.bytes,
          maxWeight: math.max(maxBytes, _minBytes),
          disposer: (tile) => tile.image.dispose(),
          clearsUnderMemoryPressure: registerForMemoryPressure,
          debugLabel: 'tiles',
        );

  /// ~96 MB: enough for a deep-zoom viewport plus a prefetch ring across a
  /// couple of buckets, well under the decoded-image budget it sits beside.
  static const _defaultMaxBytes = 96 << 20;

  /// A floor so a viewport's worth of tiles is never evicted out from under the
  /// view that just asked for them (see [viewFor]'s MRU-protection contract).
  static const _minBytes = 8 << 20;

  static PdfTileStore? _instance;

  /// The shared store the viewer uses. Lazily created so nothing is allocated
  /// (or registered for memory pressure) unless the tile path is exercised.
  static PdfTileStore get instance => _instance ??= PdfTileStore();

  /// Physical pixels per tile side. A tile at bucket ratio r covers
  /// `tilePixels / r` page points per side.
  final int tilePixels;
  final PdfTileZoomLadder ladder;

  /// How many tiles beyond the visible range to pre-raster on each side, so a
  /// pan reveals ready tiles instead of blanks.
  final int prefetchRing;

  /// How many buckets coarser [viewFor] will search for an upscaled fallback
  /// before leaving the base raster to show through.
  final int maxFallbackDepth;

  final PdfBudgetedCache<PdfTileKey, PdfTile> _cache;
  final Set<PdfTileKey> _inFlight = {};

  /// Invalidation epochs: a tile whose page was invalidated after its raster
  /// was dispatched is discarded on completion (mirrors the render worker's
  /// stale-inflight guard). [_globalEpoch] rises on every invalidation;
  /// [_pageEpoch] records the epoch at which each page was last invalidated.
  int _globalEpoch = 0;
  final Map<int, int> _pageEpoch = {};

  bool _tickScheduled = false;
  bool _disposed = false;

  // Diagnostics (asserted in tests).
  int debugTilesScheduled = 0;
  int debugTilesLanded = 0;
  int debugTilesDiscarded = 0;
  int debugTicks = 0;

  /// Total bytes of retained tiles.
  int get retainedBytes => _cache.weight;

  /// Number of retained tiles.
  int get tileCount => _cache.length;

  /// Tiles whose raster is currently in flight.
  int get inFlightCount => _inFlight.length;

  /// The weight budget, live-adjustable (a device-memory tier could lower it).
  int get maxBytes => _cache.maxWeight;
  set maxBytes(int value) => _cache.maxWeight = math.max(value, _minBytes);

  /// Whether a tile for [key] is retained (test/diagnostic; no LRU touch).
  bool containsTile(PdfTileKey key) => _cache.containsKey(key);

  /// The best-available composite for [id] over [visiblePageRect] (page points)
  /// at [desiredRatio], scheduling the missing exact-bucket tiles (center-out)
  /// plus a one-tile prefetch ring. Missing tiles fall back per-tile to the
  /// nearest coarser cached bucket, upscaled; anything still uncovered leaves
  /// the base raster showing through.
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
  }) {
    if (_disposed ||
        pageSize.width <= 0 ||
        pageSize.height <= 0 ||
        visiblePageRect.isEmpty) {
      return PdfTileView.empty;
    }

    final rung = ladder.rungFor(desiredRatio);
    final ratio = ladder.ratioFor(rung);
    final span = tilePixels / ratio; // page points per tile side
    if (!span.isFinite || span <= 0) return PdfTileView.empty;

    final nx = math.max(1, (pageSize.width / span).ceil());
    final ny = math.max(1, (pageSize.height / span).ceil());

    final visible = visiblePageRect.intersect(Offset.zero & pageSize);
    if (visible.isEmpty) return PdfTileView.empty;

    final tx0 = (visible.left / span).floor().clamp(0, nx - 1);
    final ty0 = (visible.top / span).floor().clamp(0, ny - 1);
    final tx1 = ((visible.right / span).ceil() - 1).clamp(0, nx - 1);
    final ty1 = ((visible.bottom / span).ceil() - 1).clamp(0, ny - 1);

    // Center-out ordering: the tile under the viewport center sharpens first.
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
        _schedule(key, id, pageSize, span, ratio, rasterize);
        final fallback = _coarserFallback(id, rung, tx, ty, span, pageSize);
        if (fallback != null) placements.add(fallback);
      }
    }

    // Prefetch ring: pre-raster the border just outside the visible range so a
    // pan reveals ready tiles. Scheduled after the visible tiles (which matter
    // now); dedup keeps a hovering viewport from re-queueing.
    if (prefetchRing > 0) {
      final rx0 = math.max(0, tx0 - prefetchRing);
      final ry0 = math.max(0, ty0 - prefetchRing);
      final rx1 = math.min(nx - 1, tx1 + prefetchRing);
      final ry1 = math.min(ny - 1, ty1 + prefetchRing);
      for (var ty = ry0; ty <= ry1; ty++) {
        for (var tx = rx0; tx <= rx1; tx++) {
          if (tx >= tx0 && tx <= tx1 && ty >= ty0 && ty <= ty1) continue;
          _schedule(PdfTileKey(id, rung, tx, ty), id, pageSize, span, ratio,
              rasterize);
        }
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
    final fine = _clampToPage(Rect.fromLTWH(tx * span, ty * span, span, span),
        pageSize);
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
      );
    }
    return null;
  }

  void _schedule(
    PdfTileKey key,
    PdfTilePageIdentity id,
    Size pageSize,
    double span,
    double ratio,
    PdfTileRasterizer rasterize,
  ) {
    if (_disposed || _cache.containsKey(key) || _inFlight.contains(key)) return;
    final region = _clampToPage(
        Rect.fromLTWH(key.tx * span, key.ty * span, span, span), pageSize);
    if (region.width <= 0 || region.height <= 0) return;

    _inFlight.add(key);
    debugTilesScheduled++;
    final dispatchEpoch = _globalEpoch;
    rasterize(region, ratio).then((image) {
      _inFlight.remove(key);
      if (_disposed || _isStale(id.pageIndex, dispatchEpoch)) {
        image.dispose();
        debugTilesDiscarded++;
        return;
      }
      _cache.put(key, PdfTile(image, region, key.rung));
      debugTilesLanded++;
      _scheduleTick();
    }, onError: (Object _, StackTrace __) {
      _inFlight.remove(key);
      debugTilesDiscarded++;
    });
  }

  bool _isStale(int pageIndex, int dispatchEpoch) =>
      _globalEpoch > dispatchEpoch ||
      (_pageEpoch[pageIndex] ?? -1) > dispatchEpoch;

  /// Drops retained (and in-flight) tiles. With [pages] null every tile is
  /// dropped; otherwise only tiles for those page slots - the model
  /// [PdfCachingRenderWorker.updateRevision]'s `changedPages` feeds. In-flight
  /// rasters for the affected pages are discarded on completion.
  void invalidate({Set<int>? pages}) {
    if (_disposed) return;
    _globalEpoch++;
    if (pages == null) {
      _cache.clear();
    } else {
      for (final page in pages) {
        _pageEpoch[page] = _globalEpoch;
      }
      _cache.evictWhere((key) => pages.contains(key.id.pageIndex));
    }
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
    super.dispose();
  }
}
