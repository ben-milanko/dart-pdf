/// The presentation half of [PdfTileStore]: a [CustomPaint] that composites the
/// store's best-available tiles for a page's visible region via
/// `canvas.drawImageRect`, repainting as sharper tiles land.
///
/// Kept separate from `tile_store.dart` so the store stays a pure model (no
/// widget dependency); this file is the only tile code that imports Flutter's
/// widget layer.
library;

import 'package:flutter/widgets.dart';

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
    this.filterQuality = FilterQuality.medium,
  });

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
    required this.filterQuality,
  }) : super(repaint: store); // tick as sharper tiles land

  final PdfTileStore store;
  final PdfTilePageIdentity identity;
  final Size pageSize;
  final double desiredRatio;
  final Rect visibleFraction;
  final PdfTileRasterizer rasterize;
  final FilterQuality filterQuality;

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
    );
    if (view.isEmpty) return;
    final paint = Paint()..filterQuality = filterQuality;
    for (final placement in view.placements) {
      final dest = Rect.fromLTRB(
        placement.destFraction.left * size.width,
        placement.destFraction.top * size.height,
        placement.destFraction.right * size.width,
        placement.destFraction.bottom * size.height,
      );
      canvas.drawImageRect(placement.image, placement.src, dest, paint);
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
      old.filterQuality != filterQuality;
}
