import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

import 'retained_scene.dart';
import 'tile_store.dart';

/// Creates a scene-scoped renderer for deep-zoom tiles or tile slabs.
///
/// [PdfTileStore] remains responsible for LoD selection, batching, caching,
/// and composition. A backend only turns a retained-scene region into an
/// image. Keeping the session at scene lifetime lets accelerated backends
/// tessellate commands and upload buffers or textures once, then reuse those
/// resources for every region the store requests.
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

  /// Why the most recent [createSession] call returned null, when known.
  ///
  /// This deliberately describes the latest call rather than lifetime state:
  /// page-level perf logs can name the exact reason a requested backend routed
  /// a scene to Canvas without depending on that backend's diagnostics type.
  /// Implementations that do not expose a reason may leave this null.
  String? get lastSessionRejection => null;

  /// Whether worker-decoded RGBA should stay attached to a retained scene
  /// until this backend has created its scene resources.
  ///
  /// The Canvas backend only needs the engine [ui.Image], so dropping the
  /// duplicate worker payload immediately saves memory. A backend that can
  /// upload those bytes directly may opt in and release them after its one-time
  /// scene compilation through
  /// [PdfRetainedScene.releaseDecodedImagePixels].
  bool get prefersDirectDecodedImageUploads => false;

  /// Whether this command mix needs locally decoded RGBA retained for upload.
  ///
  /// Returning false lets compatible engine images stay on a zero-copy import
  /// route. Backends should return true only when scene resources require a CPU
  /// representation, such as a hand-built mip chain.
  bool shouldRetainLocallyDecodedImagePixels(List<PdfRenderCommand> commands) =>
      false;

  /// Whether [warmUp] performs useful process- or view-scoped preparation.
  ///
  /// False lets the viewer skip its idle timer entirely for Canvas and other
  /// no-op backends. Implementations that opt in must coalesce repeated calls.
  bool get supportsWarmUp => false;

  /// Whether sessions returned by [createSession] implement
  /// [PdfTileRasterWarmUp]. False avoids creating an otherwise-unused session
  /// for backends that have no scene-specific preparation.
  bool get supportsSessionWarmUp => false;

  /// Whether idle full-page raster warming may render through this backend.
  ///
  /// The resulting [ui.Image] is retained by the viewer's exact-raster LRU,
  /// not by the short-lived session. This lets a host make a budgeted set (or
  /// an entire modest document) immediately sharp on navigation without
  /// keeping every page widget and tile session alive. Returning false keeps
  /// the universal Canvas warm path.
  ///
  /// Implementations should opt in only when a full-page request has the same
  /// exactness and ownership guarantees as an ordinary tile request. Returning
  /// null from [createSession], or throwing during the raster, still falls back
  /// to Canvas for that page.
  bool get supportsFullPageRasterWarmUp => false;

  /// Prepares process- or view-scoped resources before the first tile.
  ///
  /// [PdfViewer] calls this after useful pixels and a quiet window, never while
  /// constructing the initial page. Backends can use the idle lead time to
  /// load shaders or issue a bounded compilation pass. Calls may repeat after
  /// a backend or native view changes, so implementations must coalesce their
  /// own work. The default Canvas implementation has nothing to prepare.
  Future<void> warmUp() => Future<void>.value();

  /// Creates a lightweight owner for resources retained across tile renders.
  ///
  /// This is called lazily when the tile path first needs pixels, or by an
  /// opted-in [PdfTileRasterWarmUp] pass after useful page pixels and a quiet
  /// window—not while the page's initial raster is being prepared.
  /// Scene-specific work otherwise stays deferred until
  /// [PdfTileRasterSession.rasterizeRegion]; only view-scoped work belongs in
  /// [warmUp].
  PdfTileRasterSession? createSession(PdfRetainedScene scene);
}

/// Optional asynchronous second chance after [PdfTileRasterBackend.createSession]
/// conservatively declines a retained scene.
///
/// The viewer calls [retrySession] immediately after the synchronous result is
/// null. Returning null keeps the normal Canvas fallback. Returning a future
/// starts the extra work asynchronously; if that future later completes with
/// null or throws, the same exact Canvas fallback takes over.
/// This is intended for bounded re-recording strategies, not approximations.
abstract interface class PdfTileRasterRetryBackend {
  Future<PdfTileRasterSession?>? retrySession(PdfRetainedScene scene);
}

/// Scene-lifetime resources used to rasterize many tile regions.
abstract class PdfTileRasterSession {
  /// The retained scene this session was built for.
  PdfRetainedScene get scene;

  /// Rasterizes [region] in page-point, y-down raster space.
  ///
  /// The tile store may request one tile or a slab spanning several adjacent
  /// tiles and slice the returned image, so implementations should preserve
  /// the exact output dimensions used by [PdfRetainedScene.rasterizeRegion]. A
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

/// Optional scheduling hints implemented by tile sessions with non-Canvas
/// submission costs.
///
/// This is deliberately separate from [PdfTileRasterSession]: existing custom
/// session implementations retain the Canvas-compatible defaults without a
/// source-breaking interface change.
abstract interface class PdfTileRasterScheduling {
  /// Whether adjacent missing tiles should be rendered as one slab and split.
  ///
  /// Canvas replay benefits from amortizing its fixed `toImage` overhead over
  /// a slab. A backend that already produces a final GPU texture per request
  /// should return false: splitting its slab queues one extra GPU texture copy
  /// per tile and can move otherwise invisible work into a later raster frame.
  bool get batchAdjacentTiles;

  /// Optional admission cap for new tiles issued by one paint.
  ///
  /// A landed tile causes another paint, so accelerated backends can use this
  /// to keep command submission and texture allocation within a frame budget
  /// while the base/coarser image remains visible underneath.
  int? get maxNewTilesPerPaint;
}

/// Optional idle preparation for a scene-scoped tile session.
///
/// A page invokes this only after its first useful pixels have landed. The
/// session stays owned by that page and is disposed through the ordinary
/// scene lifecycle, so a backend can prepare geometry and uploads without
/// creating a separate document-wide cache or extending resource lifetimes.
abstract interface class PdfTileRasterWarmUp {
  Future<void> warmUp();
}

/// Bounded, always-on page/tile routing diagnostics for support exports.
///
/// Aggregate backend counters can say that a GPU submission completed, but
/// they cannot identify which document/page produced a corrupt texture—or
/// whether that page had already fallen back to Canvas. This registry records
/// the latest route and raster for up to [maxEntries] page namespaces without
/// retaining documents, scenes, or viewer objects.
class PdfTileRasterDiagnostics extends ChangeNotifier {
  PdfTileRasterDiagnostics._();

  static final PdfTileRasterDiagnostics instance = PdfTileRasterDiagnostics._();

  static const int maxEntries = 128;

  final LinkedHashMap<(int, int), _PdfTileRasterDiagnosticEntry> _entries =
      LinkedHashMap<(int, int), _PdfTileRasterDiagnosticEntry>();

  void reportSession({
    required Object cacheNamespace,
    required Object document,
    required Object scene,
    required int pageIndex,
    required String requestedBackend,
    required String effectiveBackend,
    required int commandCount,
    required int pageColor,
    required bool annotations,
    required int? rotation,
    String? fallbackReason,
  }) {
    final key = (identityHashCode(cacheNamespace), pageIndex);
    _entries.remove(key);
    _entries[key] = _PdfTileRasterDiagnosticEntry(
      namespaceIdentity: key.$1,
      documentIdentity: identityHashCode(document),
      sceneIdentity: identityHashCode(scene),
      pageIndex: pageIndex,
      requestedBackend: requestedBackend,
      effectiveBackend: effectiveBackend,
      fallbackReason: fallbackReason,
      commandCount: commandCount,
      pageColor: pageColor,
      annotations: annotations,
      rotation: rotation,
      updatedAt: DateTime.now(),
    );
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    _scheduleNotify();
  }

  void reportFallback({
    required Object cacheNamespace,
    required int pageIndex,
    required Object error,
  }) {
    final entry =
        _entries.remove((identityHashCode(cacheNamespace), pageIndex));
    if (entry == null) return;
    entry
      ..effectiveBackend = 'canvas'
      ..fallbackReason = error.toString()
      ..updatedAt = DateTime.now();
    _entries[(entry.namespaceIdentity, pageIndex)] = entry;
    _scheduleNotify();
  }

  void reportTile({
    required Object cacheNamespace,
    required int pageIndex,
    required Rect region,
    required double pixelRatio,
    required int width,
    required int height,
    Object? error,
  }) {
    final entry =
        _entries.remove((identityHashCode(cacheNamespace), pageIndex));
    if (entry == null) return;
    if (error == null) {
      entry.tileRasters++;
    } else {
      entry.tileFailures++;
    }
    entry
      ..lastTileError = error?.toString()
      ..lastTile = <String, Object?>{
        'left': region.left,
        'top': region.top,
        'width': region.width,
        'height': region.height,
        'pixelRatio': pixelRatio,
        'imageWidth': width,
        'imageHeight': height,
      }
      ..updatedAt = DateTime.now();
    _entries[(entry.namespaceIdentity, pageIndex)] = entry;
    _scheduleNotify();
  }

  /// The latest typed diagnostics for [pageIndex] in [cacheNamespace].
  ///
  /// The returned value is an immutable snapshot. It remains safe to retain
  /// while later tile submissions update this process-wide registry.
  PdfTileRasterDiagnostic? page(
    Object cacheNamespace,
    int pageIndex,
  ) =>
      _entries[(identityHashCode(cacheNamespace), pageIndex)]?.snapshot();

  /// Typed diagnostics for one viewer namespace, oldest update first.
  ///
  /// [namespaceIdentity] is exposed by
  /// [PdfViewerController.tileCacheNamespaceIdentity].
  List<PdfTileRasterDiagnostic> forNamespace(int namespaceIdentity) =>
      <PdfTileRasterDiagnostic>[
        for (final entry in _entries.values)
          if (entry.namespaceIdentity == namespaceIdentity) entry.snapshot(),
      ];

  /// A JSON-safe, least-recently-updated-first snapshot.
  List<Map<String, Object?>> snapshot() => <Map<String, Object?>>[
        for (final entry in _entries.values) entry.toJson(),
      ];

  /// Clears support history without changing any renderer or cache state.
  void clear() {
    if (_entries.isEmpty) return;
    _entries.clear();
    _scheduleNotify();
  }

  bool _notifyScheduled = false;

  // Sessions can be created from a lazy page's build/layout path. Coalesce a
  // burst and notify after the current stack so a listening devtool never
  // triggers a build-during-build exception.
  void _scheduleNotify() {
    // The support registry remains always-on, but the extra UI work is truly
    // opt-in: without a visible devtool there is no listener and no queued
    // microtask on each tile completion.
    if (!hasListeners || _notifyScheduled) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      notifyListeners();
    });
  }
}

/// How a page's deep-zoom detail tiles are currently rasterized.
enum PdfTileRasterRoute {
  /// No tile session has been requested yet; the fitted base raster is Canvas.
  unrouted,

  /// Canvas was explicitly requested as the tile backend.
  canvas,

  /// An accelerated backend declined or failed and Canvas took over.
  canvasFallback,

  /// The requested non-Canvas backend owns the tile session.
  accelerated,
}

/// Immutable, typed view of one page's latest tile-routing diagnostics.
@immutable
class PdfTileRasterDiagnostic {
  const PdfTileRasterDiagnostic({
    required this.namespaceIdentity,
    required this.documentIdentity,
    required this.sceneIdentity,
    required this.pageIndex,
    required this.requestedBackend,
    required this.effectiveBackend,
    required this.fallbackReason,
    required this.commandCount,
    required this.pageColor,
    required this.annotations,
    required this.rotation,
    required this.updatedAt,
    required this.tileRasters,
    required this.tileFailures,
    required this.lastTileError,
    required this.lastTile,
  });

  final int namespaceIdentity;
  final int documentIdentity;
  final int sceneIdentity;
  final int pageIndex;
  int get pageNumber => pageIndex + 1;
  final String requestedBackend;
  final String effectiveBackend;
  final String? fallbackReason;
  final int commandCount;
  final int pageColor;
  final bool annotations;
  final int? rotation;
  final DateTime updatedAt;
  final int tileRasters;
  final int tileFailures;
  final String? lastTileError;
  final Map<String, Object?>? lastTile;

  PdfTileRasterRoute get route {
    if (effectiveBackend != 'canvas') return PdfTileRasterRoute.accelerated;
    if (requestedBackend == 'canvas' && fallbackReason == null) {
      return PdfTileRasterRoute.canvas;
    }
    return PdfTileRasterRoute.canvasFallback;
  }
}

class _PdfTileRasterDiagnosticEntry {
  _PdfTileRasterDiagnosticEntry({
    required this.namespaceIdentity,
    required this.documentIdentity,
    required this.sceneIdentity,
    required this.pageIndex,
    required this.requestedBackend,
    required this.effectiveBackend,
    required this.fallbackReason,
    required this.commandCount,
    required this.pageColor,
    required this.annotations,
    required this.rotation,
    required this.updatedAt,
  });

  final int namespaceIdentity;
  final int documentIdentity;
  final int sceneIdentity;
  final int pageIndex;
  final String requestedBackend;
  String effectiveBackend;
  String? fallbackReason;
  final int commandCount;
  final int pageColor;
  final bool annotations;
  final int? rotation;
  DateTime updatedAt;
  int tileRasters = 0;
  int tileFailures = 0;
  String? lastTileError;
  Map<String, Object?>? lastTile;

  Map<String, Object?> toJson() => <String, Object?>{
        'updatedAt': updatedAt.toIso8601String(),
        'namespaceIdentity': namespaceIdentity,
        'documentIdentity': documentIdentity,
        'sceneIdentity': sceneIdentity,
        'pageIndex': pageIndex,
        'pageNumber': pageIndex + 1,
        'requestedBackend': requestedBackend,
        'effectiveBackend': effectiveBackend,
        'fallbackReason': fallbackReason,
        'commands': commandCount,
        'pageColor':
            '#${pageColor.toRadixString(16).padLeft(8, '0').toUpperCase()}',
        'annotations': annotations,
        'rotation': rotation,
        'tileRasters': tileRasters,
        'tileFailures': tileFailures,
        'lastTileError': lastTileError,
        'lastTile': lastTile,
      };

  PdfTileRasterDiagnostic snapshot() => PdfTileRasterDiagnostic(
        namespaceIdentity: namespaceIdentity,
        documentIdentity: documentIdentity,
        sceneIdentity: sceneIdentity,
        pageIndex: pageIndex,
        requestedBackend: requestedBackend,
        effectiveBackend: effectiveBackend,
        fallbackReason: fallbackReason,
        commandCount: commandCount,
        pageColor: pageColor,
        annotations: annotations,
        rotation: rotation,
        updatedAt: updatedAt,
        tileRasters: tileRasters,
        tileFailures: tileFailures,
        lastTileError: lastTileError,
        lastTile: lastTile == null
            ? null
            : Map<String, Object?>.unmodifiable(lastTile!),
      );
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
