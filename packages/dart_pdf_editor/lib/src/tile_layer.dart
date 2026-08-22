/// The presentation half of [PdfTileStore]: a [CustomPaint] that composites the
/// store's best-available tiles for a page's visible region via
/// `canvas.drawImageRect`, repainting as sharper tiles land.
///
/// Kept separate from `tile_store.dart` so the store stays a pure model (no
/// widget dependency); this file is the only tile code that imports Flutter's
/// widget layer.
library;

import 'dart:ui' as ui show ClipOp;

import 'package:flutter/widgets.dart';

import 'debug_overlays.dart';
import 'tile_store.dart';

/// Draws a page's tile pyramid over its visible region.
///
/// Place it in a [Stack] above the base page raster (e.g. via [Positioned.fill]):
/// the tiles sharpen the visible slice while the base image shows through any
/// gap not yet covered by a tile or an upscaled coarser fallback. The layer
/// asks [store] for the best-available composite every paint and repaints
/// whenever the store ticks (a sharper tile landed).
class PdfTileLayer extends StatelessWidget {
  const PdfTileLayer({
    super.key,
    required this.store,
    required this.identity,
    required this.pageSize,
    required this.desiredRatio,
    required this.visibleFraction,
    required this.rasterize,
    this.persistence,
    this.canRasterize,
    this.batchRasters,
    this.maxNewTilesPerPaint,
    this.maxInFlightTiles,
    this.prefetchRingOverride,
    this.scheduleMissing = true,
    this.allowCoarserFallback = true,
    this.fallbackOcclusionFraction,
    this.onExactViewReady,
    this.filterQuality = FilterQuality.medium,
  })  : assert(maxNewTilesPerPaint == null || maxNewTilesPerPaint > 0),
        assert(maxInFlightTiles == null || maxInFlightTiles > 0),
        assert(prefetchRingOverride == null || prefetchRingOverride >= 0);

  /// The pyramid to composite from.
  final PdfTileStore store;

  /// The page's current visual identity (slot, stamps, plan).
  final PdfTilePageIdentity identity;

  /// The page size in points (after the plan's rotation) - the tile grid space.
  final Size pageSize;

  /// The uncapped resolution the current zoom wants; snapped to a bucket.
  final double desiredRatio;

  /// The on-screen visible slice as fractions (0..1) of the page.
  final Rect visibleFraction;

  /// Rasterizes one tile from the page's retained scene.
  final PdfTileRasterizer rasterize;

  /// Optional cold-session tile backing. Reads race [rasterize] and writes
  /// begin only after a rendered tile is ready for display.
  final PdfTilePersistence? persistence;

  /// Optional per-tile veto (see [PdfTileStore.viewFor]): a region this
  /// returns false for is left to the fallback/base raster.
  final bool Function(Rect region)? canRasterize;

  /// Per-view override for the store's adjacent-tile slab batching policy.
  final bool? batchRasters;

  /// Optional admission cap for missing tiles scheduled by one paint.
  ///
  /// Dense retained scenes use this to keep their synchronous command replay
  /// inside one frame budget. Landed tiles tick the store and cause another
  /// paint, so the viewport still fills center-out without a timer or queue.
  final int? maxNewTilesPerPaint;

  /// Optional cross-paint cap for unresolved visible tile rasters. This pairs
  /// with [maxNewTilesPerPaint]: the per-paint cap protects one frame, while
  /// this cap prevents unrelated frames from growing an unbounded GPU queue.
  final int? maxInFlightTiles;

  /// Overrides [PdfTileStore.prefetchRing] for this paint. Zero prioritizes
  /// only the visible tiles; null uses the store's normal pan-ahead ring.
  final int? prefetchRingOverride;

  /// Whether this layer may schedule missing visible tiles and pan-ahead.
  /// False keeps retained tiles present without letting an edge-sliver page
  /// compete with the focused page for the shared tile budget.
  final bool scheduleMissing;

  /// Whether a missing exact tile may be covered by an upscaled lower rung.
  /// Disable this when the layer sits over a retained vector picture: the
  /// picture is sharper than that fallback and should remain visible until
  /// the exact tile lands.
  final bool allowCoarserFallback;

  /// Page fraction whose existing pixels are sharper than a coarse tile.
  ///
  /// Exact-rung tiles still paint across this region. Upscaled fallback tiles
  /// are clipped out of it, so a fast visible-region refinement cannot regress
  /// to a blurry rectangle while the exact rung is still being produced.
  final Rect? fallbackOcclusionFraction;

  /// Called after a frame in which every visible tile was present at the
  /// exact requested rung.
  ///
  /// The callback is deliberately post-paint: callers may use it to promote
  /// this layer above an older foreground raster without changing the widget
  /// tree during paint. Missing tiles, vetoed regions, and coarser fallbacks
  /// never report ready.
  final ValueChanged<PdfTileView>? onExactViewReady;

  final FilterQuality filterQuality;

  @override
  Widget build(BuildContext context) => CustomPaint(
        key: const ValueKey('pdf-page-tile-layer'),
        painter: _TilePagePainter(
          store: store,
          identity: identity,
          pageSize: pageSize,
          desiredRatio: desiredRatio,
          visibleFraction: visibleFraction,
          rasterize: rasterize,
          persistence: persistence,
          canRasterize: canRasterize,
          batchRasters: batchRasters,
          maxNewTilesPerPaint: maxNewTilesPerPaint,
          maxInFlightTiles: maxInFlightTiles,
          prefetchRingOverride: prefetchRingOverride,
          scheduleMissing: scheduleMissing,
          allowCoarserFallback: allowCoarserFallback,
          fallbackOcclusionFraction: fallbackOcclusionFraction,
          onExactViewReady: onExactViewReady,
          filterQuality: filterQuality,
        ),
      );
}

class _TilePagePainter extends CustomPainter {
  _TilePagePainter({
    required this.store,
    required this.identity,
    required this.pageSize,
    required this.desiredRatio,
    required this.visibleFraction,
    required this.rasterize,
    required this.persistence,
    required this.canRasterize,
    required this.batchRasters,
    required this.maxNewTilesPerPaint,
    required this.maxInFlightTiles,
    required this.prefetchRingOverride,
    required this.scheduleMissing,
    required this.allowCoarserFallback,
    required this.fallbackOcclusionFraction,
    required this.onExactViewReady,
    required this.filterQuality,
  }) : super(
            // tick as sharper tiles land, and repaint on debug-border toggles
            repaint: Listenable.merge([store, pdfDebugPaintDetailBounds]));

  final PdfTileStore store;
  final PdfTilePageIdentity identity;
  final Size pageSize;
  final double desiredRatio;
  final Rect visibleFraction;
  final PdfTileRasterizer rasterize;
  final PdfTilePersistence? persistence;
  final bool Function(Rect region)? canRasterize;
  final bool? batchRasters;
  final int? maxNewTilesPerPaint;
  final int? maxInFlightTiles;
  final int? prefetchRingOverride;
  final bool scheduleMissing;
  final bool allowCoarserFallback;
  final Rect? fallbackOcclusionFraction;
  final ValueChanged<PdfTileView>? onExactViewReady;
  final FilterQuality filterQuality;
  bool _reportedExactView = false;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || pageSize.isEmpty) return;
    final visiblePageRect = Rect.fromLTRB(
      visibleFraction.left * pageSize.width,
      visibleFraction.top * pageSize.height,
      visibleFraction.right * pageSize.width,
      visibleFraction.bottom * pageSize.height,
    );
    // Synchronous: returns cached tiles now and schedules the missing ones
    // (their arrival ticks the store, which repaints this painter).
    final view = store.viewFor(
      id: identity,
      pageSize: pageSize,
      desiredRatio: desiredRatio,
      visiblePageRect: visiblePageRect,
      rasterize: rasterize,
      persistence: persistence,
      canRasterize: canRasterize,
      batchRasters: batchRasters,
      maxNewTiles: maxNewTilesPerPaint,
      maxInFlightTiles: maxInFlightTiles,
      prefetchRingOverride: prefetchRingOverride,
      scheduleMissing: scheduleMissing,
      allowCoarserFallback: allowCoarserFallback,
    );
    if (view.complete && !view.isEmpty) {
      if (!_reportedExactView && onExactViewReady != null) {
        _reportedExactView = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          onExactViewReady!(view);
        });
      }
    } else {
      _reportedExactView = false;
    }
    if (view.isEmpty) return;
    final paint = Paint()..filterQuality = filterQuality;
    final fallbackOcclusion = fallbackOcclusionFraction == null
        ? null
        : Rect.fromLTRB(
            fallbackOcclusionFraction!.left * size.width,
            fallbackOcclusionFraction!.top * size.height,
            fallbackOcclusionFraction!.right * size.width,
            fallbackOcclusionFraction!.bottom * size.height,
          );
    final debugBounds = pdfDebugPaintDetailBounds.value;
    final exactBorder = debugBounds
        ? (Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0xAA00C853)) // green: exact-bucket tile
        : null;
    final fallbackBorder = debugBounds
        ? (Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0xAAFF6D00)) // orange: upscaled fallback
        : null;
    for (final placement in view.placements) {
      final dest = Rect.fromLTRB(
        placement.destFraction.left * size.width,
        placement.destFraction.top * size.height,
        placement.destFraction.right * size.width,
        placement.destFraction.bottom * size.height,
      );
      final clipFallback = placement.isFallback &&
          fallbackOcclusion != null &&
          dest.overlaps(fallbackOcclusion);
      if (clipFallback) {
        canvas.save();
        canvas.clipRect(dest, doAntiAlias: false);
        canvas.clipRect(
          fallbackOcclusion,
          clipOp: ui.ClipOp.difference,
          doAntiAlias: false,
        );
      }
      canvas.drawImageRect(placement.image, placement.src, dest, paint);
      if (debugBounds) {
        canvas.drawRect(
            dest, placement.isFallback ? fallbackBorder! : exactBorder!);
      }
      if (clipFallback) canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _TilePagePainter old) =>
      !identical(old.store, store) ||
      old.identity != identity ||
      old.pageSize != pageSize ||
      old.desiredRatio != desiredRatio ||
      old.visibleFraction != visibleFraction ||
      !identical(old.rasterize, rasterize) ||
      !identical(old.persistence, persistence) ||
      !identical(old.canRasterize, canRasterize) ||
      old.batchRasters != batchRasters ||
      old.maxNewTilesPerPaint != maxNewTilesPerPaint ||
      old.maxInFlightTiles != maxInFlightTiles ||
      old.prefetchRingOverride != prefetchRingOverride ||
      old.scheduleMissing != scheduleMissing ||
      old.allowCoarserFallback != allowCoarserFallback ||
      old.fallbackOcclusionFraction != fallbackOcclusionFraction ||
      old.filterQuality != filterQuality;
}
