import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'retained_scene.dart';
import 'tile_store.dart';

/// Creates a scene-scoped renderer for deep-zoom tile slabs.
///
/// [PdfTileStore] remains responsible for LoD selection, batching, caching,
/// and composition. A backend only turns a retained-scene region into an
/// image. Keeping the session at scene lifetime lets accelerated backends
/// tessellate commands and upload buffers or textures once, then reuse those
/// resources for every slab the store requests.
///
/// Returning null from [createSession], or throwing while creating or using a
/// session, makes the page view fall back to [PdfCanvasTileRasterBackend] for
/// that scene. Implementations should therefore reject unsupported command
/// mixes conservatively instead of approximating painter order, groups,
/// clipping, or blending.
abstract class PdfTileRasterBackend {
  const PdfTileRasterBackend();

  /// A short diagnostics label, such as `canvas` or `flutter_gpu`.
  String get debugLabel;

  /// Creates a lightweight owner for resources retained across tile renders.
  ///
  /// This is called lazily, when the tile path first needs a slab—not while
  /// the page's initial raster is being prepared. Expensive initialization
  /// should itself be deferred by the returned session until
  /// [PdfTileRasterSession.rasterizeRegion], so enabling an experimental
  /// backend cannot delay first paint.
  PdfTileRasterSession? createSession(PdfRetainedScene scene);
}

/// Scene-lifetime resources used to rasterize many tile slabs.
abstract class PdfTileRasterSession {
  /// The retained scene this session was built for.
  PdfRetainedScene get scene;

  /// Rasterizes [region] in page-point, y-down raster space.
  ///
  /// The tile store may request a slab spanning several adjacent tiles and
  /// slice the returned image, so implementations should preserve the exact
  /// output dimensions used by [PdfRetainedScene.rasterizeRegion]. A
  /// wrong-sized result is disposed and treated as a backend failure. On
  /// success ownership of the returned image transfers to the tile store;
  /// sessions must return a uniquely owned image (or a clone), not a borrowed
  /// cached image.
  Future<ui.Image> rasterizeRegion(
    Rect region, {
    required double pixelRatio,
    int? tracePage,
  });

  /// Releases scene-level GPU/CPU resources.
  ///
  /// A page can be replaced while an already-submitted raster is in flight.
  /// Implementations must allow futures returned before this call to finish
  /// safely (for example by retiring resources after the command buffer has
  /// completed). Implementations should not throw; disposal failures are
  /// ignored so an optional backend cannot break page replacement or teardown.
  void dispose();
}

/// The universal retained-scene renderer used today and as a fallback for
/// accelerated backends.
class PdfCanvasTileRasterBackend extends PdfTileRasterBackend {
  const PdfCanvasTileRasterBackend();

  @override
  String get debugLabel => 'canvas';

  @override
  PdfTileRasterSession createSession(PdfRetainedScene scene) =>
      _PdfCanvasTileRasterSession(scene);
}

class _PdfCanvasTileRasterSession implements PdfTileRasterSession {
  _PdfCanvasTileRasterSession(this.scene);

  @override
  final PdfRetainedScene scene;

  @override
  Future<ui.Image> rasterizeRegion(
    Rect region, {
    required double pixelRatio,
    int? tracePage,
  }) =>
      scene.rasterizeRegion(
        region,
        pixelRatio: pixelRatio,
        tracePage: tracePage,
      );

  @override
  void dispose() {}
}
