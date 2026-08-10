import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:pdf_document/pdf_document.dart';

import 'budgeted_cache.dart';
import 'perf_log.dart';
import 'raster_cache.dart';
import 'raster_warm.dart';
import 'render_worker.dart';
import 'retained_scene.dart';
import 'renderer.dart';

/// Memory policy for full-resolution rasters of pages the user has visited.
///
/// A page widget is disposed after it leaves the scroll view's build window.
/// Its completed raster can outlive that widget in [PdfPagePreviewCache], so a
/// revisit at the same physical size paints immediately without interpreting
/// or rasterizing the page again.
///
/// The defaults preserve the package's bounded working set: 32 MiB total and
/// 16 MiB for any one page. Desktop hosts that prefer revisit speed over
/// memory can opt into a much larger budget:
///
/// ```dart
/// PdfViewer(
///   document: document,
///   pageRasterCachePolicy: const PdfPageRasterCachePolicy(
///     maxBytes: 5 * 1024 * 1024 * 1024,
///     maxEntryBytes: 64 * 1024 * 1024,
///   ),
/// )
/// ```
///
/// This controls only exact, already-rendered page rasters. Low-resolution
/// fast-scroll previews, decoded PDF images, retained scenes, deep-zoom tiles,
/// and render-worker records have their own bounds. A large value is therefore
/// an upper limit on this cache, not on the process's total memory use.
@immutable
class PdfPageRasterCachePolicy {
  const PdfPageRasterCachePolicy({
    this.maxBytes = 32 * 1024 * 1024,
    this.maxEntryBytes = 16 * 1024 * 1024,
  })  : assert(maxBytes >= 0),
        assert(maxEntryBytes >= 0);

  /// Disables retention of full-resolution visited-page rasters.
  const PdfPageRasterCachePolicy.disabled()
      : maxBytes = 0,
        maxEntryBytes = 0;

  /// Total approximate RGBA byte budget for retained page rasters.
  final int maxBytes;

  /// Largest individual page raster admitted to the cache.
  ///
  /// This remains a separate guard even with a large [maxBytes], so one
  /// unusually large-format or high-DPI page need not displace the useful
  /// working set unless the host explicitly allows it.
  final int maxEntryBytes;

  @override
  bool operator ==(Object other) =>
      other is PdfPageRasterCachePolicy &&
      maxBytes == other.maxBytes &&
      maxEntryBytes == other.maxEntryBytes;

  @override
  int get hashCode => Object.hash(maxBytes, maxEntryBytes);
}

/// Everything that changes the pixels of a baked full-resolution page raster.
///
/// This is the exact-raster cache's key. It is deliberately *not* just the page
/// index: a page can legitimately hold more than one useful raster at once -
/// most importantly its fit-size one (which the idle warm bakes and a
/// zoom-back-to-fit wants) alongside the one the current zoom is displaying.
/// Keying by index alone meant storing either overwrote the other, so warming
/// a page and then zooming it threw the warm away.
///
/// Document revision is *not* part of the signature. Revisions are compared by
/// [PdfPage] identity on the retained entry instead, because an edit that
/// leaves a page's pixels alone rebinds it to the new revision's page object
/// rather than invalidating a still-correct raster (see
/// [PdfPagePreviewCache.rebind]).
@immutable
class PdfPageRasterSignature {
  const PdfPageRasterSignature({
    required this.pageIndex,
    required this.width,
    required this.height,
    required this.pageColor,
    required this.annotations,
    required this.rotation,
  });

  /// The page this raster shows.
  final int pageIndex;

  /// Physical raster size in device pixels.
  final int width;
  final int height;

  /// The paper color painted behind the page.
  final Color pageColor;

  /// Whether annotations are baked into the raster.
  final bool annotations;

  /// Display rotation override (null = the page's own /Rotate).
  final int? rotation;

  /// Approximate RGBA bytes an image of this size occupies.
  int get bytes => width * height * 4;

  @override
  bool operator ==(Object other) =>
      other is PdfPageRasterSignature &&
      pageIndex == other.pageIndex &&
      width == other.width &&
      height == other.height &&
      pageColor == other.pageColor &&
      annotations == other.annotations &&
      rotation == other.rotation;

  @override
  int get hashCode => Object.hash(
      pageIndex, width, height, pageColor.toARGB32(), annotations, rotation);

  @override
  String toString() => 'page=$pageIndex ${width}x$height '
      'color=${pageColor.toARGB32().toRadixString(16)} '
      'annotations=$annotations rotation=$rotation';
}

/// Low-resolution page previews shown while a page's full render is
/// pending - most visibly during fast scrolling, when [PdfPageView]
/// holds the (UI-thread) first interpretation of pages flying past and
/// would otherwise show blank paper.
///
/// The cache lives above the page widgets (the viewer owns one per
/// document), so previews survive page states being disposed as they
/// scroll out of the build window: a page seen once keeps its preview
/// for the rest of the session. Pages never seen are filled in by the
/// viewer's background prerender, nearest the viewport first.
///
/// Entries are small (longest side [longestSide] px, ~125 KB each at the
/// default 200) and capped at [capacity], oldest-touched evicted first.
/// [imageFor] hands out [ui.Image.clone]s, so eviction can never pull
/// pixels out from under a painting widget.
class PdfPagePreviewCache extends ChangeNotifier {
  PdfPagePreviewCache({
    this.longestSide = 200,
    this.capacity = 300,
    int maxFullRasterPixels = 8 << 20,
    int maxFullRasterEntryPixels = 4 << 20,
    int maxRetainedSceneBytes = 64 << 20,
    int maxRetainedSceneEntries = 4,
  })  : assert(maxFullRasterPixels >= 0),
        assert(maxFullRasterEntryPixels >= 0),
        assert(maxRetainedSceneBytes >= 0),
        assert(maxRetainedSceneEntries > 0),
        _maxFullRasterBytes = maxFullRasterPixels * 4,
        _maxFullRasterEntryBytes = maxFullRasterEntryPixels * 4,
        _maxRetainedSceneBytes = maxRetainedSceneBytes,
        _maxRetainedSceneEntries = maxRetainedSceneEntries;

  /// Pixel size of a preview's longest side. Stretched to page size on
  /// screen the result is soft but recognizable - enough to navigate by.
  final double longestSide;

  /// Maximum number of cached previews (LRU eviction past it).
  final int capacity;

  /// Total pixel budget for exact, recently-viewed page rasters.
  ///
  /// These entries remove the soft-preview delay when a lazy page widget is
  /// rebuilt during back-and-forth scrolling. The default is about 32 MiB of
  /// RGBA pixels. Set to zero to keep only low-resolution previews.
  int get maxFullRasterPixels => _maxFullRasterBytes ~/ 4;

  /// Largest exact raster admitted to the recent-page cache.
  ///
  /// Oversized/high-zoom pages keep the existing preview + scheduled-render
  /// path instead of consuming the whole budget. The default is about 16 MiB
  /// of RGBA pixels, which covers ordinary document pages while excluding the
  /// large CAD rasters this cache is not intended to retain.
  int get maxFullRasterEntryPixels => _maxFullRasterEntryBytes ~/ 4;

  /// Approximate bytes currently allowed for exact visited-page rasters.
  int get maxFullRasterBytes => _maxFullRasterBytes;

  /// Largest individual visited-page raster currently admitted.
  int get maxFullRasterEntryBytes => _maxFullRasterEntryBytes;

  /// Approximate bytes currently retained by the exact raster LRU.
  int get fullRasterBytes => _fullEntries.weight;

  /// Number of exact page rasters currently retained.
  int get fullRasterCount => _fullEntries.length;

  int _maxFullRasterBytes;
  int _maxFullRasterEntryBytes;
  final int _maxRetainedSceneBytes;
  final int _maxRetainedSceneEntries;

  // Two shared budgeted LRUs: soft previews bounded by entry count, exact
  // recent-page rasters bounded by total pixels. Both dispose evicted images;
  // the pixel budget and count cap live in PdfBudgetedCache (and are
  // property-tested there), so this class keeps only the preview-domain logic
  // (disk write-through, rebinding, staleness) on top.
  late final PdfBudgetedCache<int, _PreviewEntry> _entries =
      PdfBudgetedCache<int, _PreviewEntry>(
    maxEntries: capacity,
    disposer: (entry) => entry.image.dispose(),
    debugLabel: 'page-preview',
  );
  late final PdfBudgetedCache<PdfPageRasterSignature, _FullRasterEntry>
      _fullEntries = PdfBudgetedCache<PdfPageRasterSignature, _FullRasterEntry>(
    weigher: (entry) => entry.bytes,
    maxWeight: _maxFullRasterBytes,
    disposer: (entry) => entry.image.dispose(),
    onEvicted: _logFullRasterEviction,
    clearsUnderMemoryPressure: true,
    debugLabel: 'page-full-raster',
  );
  late final PdfBudgetedCache<_RetainedSceneKey, _RetainedSceneEntry>
      _retainedScenes =
      PdfBudgetedCache<_RetainedSceneKey, _RetainedSceneEntry>(
    weigher: (entry) => entry.estimatedBytes,
    maxWeight: _maxRetainedSceneBytes,
    maxEntries: _maxRetainedSceneEntries,
    rejectOversize: true,
    disposer: (entry) => entry.dropCacheReference(),
    clearsUnderMemoryPressure: true,
    debugLabel: 'page-retained-scene',
  );
  bool _disposed = false;

  /// Distinct raster geometries retained for any one page.
  ///
  /// Two is the useful number: the fit-size raster (what the idle warm bakes
  /// and what a zoom-back-to-fit needs) plus whatever the current zoom is
  /// displaying. A third variant is almost always a resolution the viewer has
  /// moved past, and before the cache was keyed by signature at all those
  /// stale entries were the whole problem - a ratio-0.4 raster sitting in the
  /// cache producing `miss reason=dimensions` while the viewer, long since at
  /// ratio 1.4, re-rasterized the page from scratch each time (the 2026-07-29
  /// trace). Keeping two bounds that waste to one entry per page; the byte
  /// budget still governs the total.
  static const _maxVariantsPerPage = 2;

  // Idle-warm and lookup diagnostics (see [warmStats]). Lifetime-cumulative.
  int _warmAttempts = 0;
  int _warmCompletions = 0;
  int _warmSkips = 0;
  int _warmRejections = 0;
  int _warmPreemptions = 0;
  int _warmedBytes = 0;

  /// Pixels currently retained by the exact recent-page cache.
  @visibleForTesting
  int get debugFullRasterPixels => _fullEntries.weight ~/ 4;

  /// Applies a new full-resolution visited-page memory policy.
  ///
  /// Raising the budget lets later page renders occupy the extra room.
  /// Lowering it trims the LRU immediately and also drops entries that exceed
  /// the new per-page limit. Low-resolution previews are unaffected.
  void configureFullRasterCache(PdfPageRasterCachePolicy policy) {
    if (_disposed) return;
    final beforeCount = _fullEntries.length;
    final beforeBytes = _fullEntries.weight;
    _maxFullRasterBytes = policy.maxBytes;
    _maxFullRasterEntryBytes = policy.maxEntryBytes;
    _fullEntries.evictWhere((key) {
      final entry = _fullEntries.peek(key);
      return entry != null && entry.bytes > _maxFullRasterEntryBytes;
    });
    _fullEntries.maxWeight = _maxFullRasterBytes;
    PdfPerfLog.log(
      'page-raster policy total=${policy.maxBytes} '
      'entry=${policy.maxEntryBytes} retained=${_fullEntries.weight} '
      'entries=${_fullEntries.length} '
      'trimmedEntries=${beforeCount - _fullEntries.length} '
      'trimmedBytes=${beforeBytes - _fullEntries.weight} '
      'registry=${PdfCacheRegistry.instance.totalWeight} '
      'ceiling=${PdfCacheRegistry.instance.maxTotalWeight}'
      '${PdfPerfLog.rssSuffix()}',
    );
  }

  /// Optional persistent backing (see [PdfRasterCache]). When set, fresh
  /// previews are written through to disk as they render, and [loadFromDisk]
  /// can prime the in-memory cache from a previous session. The viewer
  /// binds this to the open document; null leaves the cache session-only,
  /// exactly as before.
  PdfRasterCache? disk;

  /// Whether [disk] carries the optional persistent full-resolution raster
  /// tier (#615). False keeps the pre-existing behaviour exactly: full
  /// rasters live and die with the process.
  bool get hasPersistentFullRasters => disk?.storesFullRasters ?? false;

  /// Lets the host preempt background encode/store work: while this returns
  /// true (a scroll in flight, a foreground render holding the raster thread)
  /// queued full-raster writes wait rather than compete. Loads are *not*
  /// gated - a disk read is the foreground first paint it exists to serve.
  bool Function()? deferBackgroundIo;

  // Queued full-raster disk writes. Each holds a clone (cheap - it shares the
  // engine image) so the encode survives the page view replacing its raster,
  // and the queue is capped so a permanently-deferring host cannot pin an
  // unbounded number of page-sized images.
  static const int _maxPendingFullWrites = 2;
  static const int _maxFullWriteDeferrals = 60; // ~3s, then drop the write
  final List<_PendingFullRasterWrite> _pendingFullWrites = [];
  bool _drainingFullWrites = false;

  /// Loads any persisted previews for [pages] into memory, so a cold open
  /// of a previously-seen document paints soft content at once. Pages that
  /// already hold a (fresher, in-session) preview are left alone, and the
  /// loaded entries are bound to the current [pages] objects so the
  /// background prerender treats them as done - the on-screen full render
  /// still replaces them when it lands.
  Future<void> loadFromDisk(List<PdfPage> pages) async {
    final cache = disk;
    if (cache == null || _disposed) return;
    for (var i = 0; i < pages.length; i++) {
      if (_disposed) return;
      if (_entries.containsKey(i)) continue;
      final image = await cache.loadPreview(i);
      if (image == null) continue;
      if (_disposed || _entries.containsKey(i)) {
        image.dispose();
        continue;
      }
      // adopt without writing back - these bytes just came from disk. put
      // trims to capacity, disposing the LRU and never the entry just loaded.
      _entries.put(i, _PreviewEntry(pages[i], image, includesImages: true));
      notifyListeners();
    }
  }

  /// The preview for page [index], as a clone the caller owns (and must
  /// dispose), or null when none is cached. Counts as a use for LRU.
  ui.Image? imageFor(int index) {
    final entry = _entries.take(index); // touch; the master stays cached
    if (entry == null) return null;
    return entry.image.clone();
  }

  /// Returns a lease on a complete retained scene for this page and display
  /// plan, or null when the scene has fallen out of the bounded LRU.
  ///
  /// A page widget may leave Flutter's lazy-list cache window while its exact
  /// raster remains useful. Keeping the matching command scene here means a
  /// later zoom can replay/cull that already-recorded page instead of asking a
  /// worker to transfer and reconstruct the whole command stream again. The
  /// lease pins the scene while the page widget uses it, so an LRU eviction or
  /// memory-pressure clear cannot dispose it underneath an in-flight replay.
  PdfRetainedSceneHandle? retainedSceneFor(
    int index,
    PdfPage page, {
    required PdfPageRenderPlan plan,
  }) {
    final key = _RetainedSceneKey(index, plan);
    final entry = _retainedScenes.take(key);
    if (entry == null) return null;
    if (!identical(entry.page, page)) {
      _retainedScenes.evict(key);
      return null;
    }
    return entry.acquire();
  }

  /// Retains [scene] in the session LRU and returns a lease for the caller.
  ///
  /// [estimatedBytes] includes the command scene's estimated heap plus the
  /// engine picture size observed while building it. Oversize entries remain
  /// usable by the caller through the returned lease but are not cached.
  PdfRetainedSceneHandle retainScene(
    int index,
    PdfPage page,
    PdfRetainedScene scene, {
    required PdfPageRenderPlan plan,
    required bool fromWorker,
    required int estimatedBytes,
    ui.Picture? picture,
  }) {
    final key = _RetainedSceneKey(index, plan);
    final entry = _RetainedSceneEntry(
      page,
      scene,
      picture: picture,
      fromWorker: fromWorker,
      estimatedBytes: estimatedBytes,
    );
    final handle = entry.acquire();
    _retainedScenes.put(key, entry);
    if (!identical(_retainedScenes.peek(key), entry)) {
      // PdfBudgetedCache deliberately leaves an oversize value owned by the
      // caller. Convert that ownership into the same lease contract used for
      // admitted entries.
      entry.dropCacheReference();
    }
    return handle;
  }

  /// Approximate bytes held by the retained-scene LRU.
  @visibleForTesting
  int get debugRetainedSceneBytes => _retainedScenes.weight;

  /// Number of complete page scenes retained across lazy page-widget disposal.
  @visibleForTesting
  int get debugRetainedSceneCount => _retainedScenes.length;

  /// Returns a cached raster matching this page and display geometry.
  ///
  /// The caller owns the returned clone. An exact physical-size hit is
  /// preferred. Otherwise the smallest sharper raster with the same aspect
  /// ratio may satisfy the lookup: scaling already-rendered pixels down is
  /// visually lossless and avoids an unnecessary replay/readback after
  /// zooming out. A smaller raster is never stretched up through this path.
  /// Page content, paper color, annotation visibility, and rotation must all
  /// match.
  ui.Image? fullImageFor(
    int index,
    PdfPage page, {
    required int width,
    required int height,
    required Color pageColor,
    required bool annotations,
    required int? rotation,
  }) =>
      fullImageForSignature(
        PdfPageRasterSignature(
          pageIndex: index,
          width: width,
          height: height,
          pageColor: pageColor,
          annotations: annotations,
          rotation: rotation,
        ),
        page,
      );

  /// [fullImageFor] against an already-built [signature].
  ui.Image? fullImageForSignature(
      PdfPageRasterSignature signature, PdfPage page) {
    final index = signature.pageIndex;
    final entry = _fullEntries.take(signature); // touch; master stays cached
    if (entry != null && identical(entry.page, page)) {
      _logFullRasterLookup('hit', index, bytes: entry.bytes);
      return entry.image.clone();
    }
    // A miss. Geometry variants of this page (a different zoom, say) are left
    // alone - they are a legitimate second raster the LRU bounds, not waste.
    // A *revision* mismatch is not: those pixels are of a page that no longer
    // exists, so no lookup can ever use them and retaining them only spends a
    // scarce budget on something nothing can read. Drop every one of them here,
    // where a fresh page object proves the revision moved.
    _dropStaleVariants(index, page);
    PdfPageRasterSignature? best;
    for (final candidate in _fullEntries.keys) {
      if (!_canDownsample(candidate, signature)) continue;
      if (best == null || candidate.bytes < best.bytes) best = candidate;
    }
    if (best != null) {
      final sharper = _fullEntries.take(best);
      if (sharper != null && identical(sharper.page, page)) {
        _logFullRasterLookup(
          'hit',
          index,
          reason: 'sharper-${best.width}x${best.height}',
          bytes: sharper.bytes,
        );
        return sharper.image.clone();
      }
    }
    _logFullRasterLookup(
      'miss',
      index,
      reason: entry == null ? 'empty' : 'page-identity',
    );
    return null;
  }

  /// Whether [candidate] can be scaled down to answer [requested] without
  /// changing the page pixels or distorting its geometry.
  ///
  /// Both dimensions must be at least as large. The cross-product tolerance
  /// allows the one-pixel differences produced by independently ceiling the
  /// width and height at each ratio, while rejecting arbitrary images with a
  /// different aspect ratio stored through the public cache API.
  static bool _canDownsample(
    PdfPageRasterSignature candidate,
    PdfPageRasterSignature requested,
  ) {
    if (candidate.pageIndex != requested.pageIndex ||
        candidate.pageColor != requested.pageColor ||
        candidate.annotations != requested.annotations ||
        candidate.rotation != requested.rotation ||
        candidate.width < requested.width ||
        candidate.height < requested.height) {
      return false;
    }
    final cross = (candidate.width * requested.height -
            candidate.height * requested.width)
        .abs();
    final roundingTolerance =
        candidate.width + candidate.height + requested.width + requested.height;
    return cross <= roundingTolerance;
  }

  /// Whether a raster of [signature] for exactly this [page] is retained.
  /// A pure peek: it neither touches LRU order nor moves the hit/miss counters,
  /// so the idle warm can ask "is this page already done?" without distorting
  /// the diagnostics or the eviction order.
  bool hasFullRaster(PdfPageRasterSignature signature, PdfPage page) =>
      identical(_fullEntries.peek(signature)?.page, page);

  /// Whether a raster of [bytes] could be admitted under the current policy.
  ///
  /// The idle warm asks *before* interpreting a page: rendering a raster the
  /// cache would reject on arrival is the one kind of background work that
  /// cannot possibly pay for itself.
  bool admitsFullRaster(int bytes) =>
      _maxFullRasterBytes > 0 &&
      bytes <= _maxFullRasterEntryBytes &&
      bytes <= _maxFullRasterBytes;

  /// Retains a clone of a completed on-screen raster for immediate reuse.
  ///
  /// The cache is an LRU bounded by [maxFullRasterPixels], and rejects a
  /// single image over [maxFullRasterEntryPixels]. Cloning shares the engine
  /// image rather than performing another GPU readback.
  void putFullImage(
    int index,
    PdfPage page,
    ui.Image image, {
    required Color pageColor,
    required bool annotations,
    required int? rotation,
    String revision = '',
  }) {
    if (_disposed) return;
    // Write through before the memory admission below, deliberately: the disk
    // tier is also the *overflow* path for a RAM budget smaller than the
    // document's useful working set, so a raster the policy rejects is still
    // worth keeping for the next session.
    _queueFullRasterWrite(
      index,
      image,
      pageColor: pageColor,
      annotations: annotations,
      rotation: rotation,
      revision: revision,
    );
    _admitFullImage(
      index,
      page,
      image,
      pageColor: pageColor,
      annotations: annotations,
      rotation: rotation,
    );
  }

  /// Restores an exact raster for [index] from the persistent tier, admitting
  /// it through the in-memory [PdfPageRasterCachePolicy] on the way past.
  ///
  /// Returns an image the caller owns (and must dispose), or null on a miss.
  /// The returned image is usable for the page on screen **whether or not**
  /// the memory policy admitted it: a disk hit too large for RAM still serves
  /// this paint, it just does not displace the memory working set.
  Future<ui.Image?> loadFullFromDisk(
    int index,
    PdfPage page, {
    required int width,
    required int height,
    required Color pageColor,
    required bool annotations,
    required int? rotation,
    String revision = '',
  }) async {
    final cache = disk;
    if (cache == null || !cache.storesFullRasters || _disposed) return null;
    final image = await cache.loadFullRaster(
      index,
      width: width,
      height: height,
      pageColor: pageColor.toARGB32(),
      annotations: annotations,
      rotation: rotation,
      revision: revision,
    );
    if (image == null) return null;
    if (_disposed) {
      image.dispose();
      return null;
    }
    // _admitFullImage clones, so the caller keeps ownership of `image`.
    _admitFullImage(
      index,
      page,
      image,
      pageColor: pageColor,
      annotations: annotations,
      rotation: rotation,
    );
    return image;
  }

  /// Empties the persistent full-raster tier (previews and thumbnails, which
  /// live in a different [PdfDiskCache], are untouched). See
  /// [PdfRasterCache.clearFullRasters].
  Future<void> clearPersistentFullRasters() async {
    _dropPendingFullWrites();
    await disk?.clearFullRasters();
  }

  void _queueFullRasterWrite(
    int index,
    ui.Image image, {
    required Color pageColor,
    required bool annotations,
    required int? rotation,
    required String revision,
  }) {
    final cache = disk;
    if (cache == null || !cache.storesFullRasters) return;
    // Only the newest raster for a page is worth storing.
    for (var i = 0; i < _pendingFullWrites.length; i++) {
      if (_pendingFullWrites[i].index == index) {
        _pendingFullWrites.removeAt(i).image.dispose();
        break;
      }
    }
    _pendingFullWrites.add(_PendingFullRasterWrite(
      index,
      image.clone(),
      pageColor: pageColor,
      annotations: annotations,
      rotation: rotation,
      revision: revision,
    ));
    while (_pendingFullWrites.length > _maxPendingFullWrites) {
      _pendingFullWrites.removeAt(0).image.dispose();
    }
    if (!_drainingFullWrites) unawaited(_drainFullRasterWrites());
  }

  Future<void> _drainFullRasterWrites() async {
    if (_drainingFullWrites) return;
    _drainingFullWrites = true;
    try {
      while (_pendingFullWrites.isNotEmpty && !_disposed) {
        var deferrals = 0;
        while ((deferBackgroundIo?.call() ?? false) &&
            deferrals < _maxFullWriteDeferrals &&
            !_disposed) {
          deferrals++;
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        if (_disposed) break;
        // The queue can be emptied *while* we wait above - a document swap
        // (clear) or a host wiping the tier (clearPersistentFullRasters).
        // Re-check before indexing, or the drain throws RangeError into the
        // zone as an unhandled async error.
        if (_pendingFullWrites.isEmpty) continue;
        final pending = _pendingFullWrites.removeAt(0);
        if (deferrals >= _maxFullWriteDeferrals) {
          // Still contended after seconds of scrolling. Drop it rather than
          // take the raster thread away from the page the user is looking at;
          // the page re-renders (and re-queues) when the view settles.
          pending.image.dispose();
          continue;
        }
        try {
          await disk?.storeFullRaster(
            pending.index,
            pending.image,
            pageColor: pending.pageColor.toARGB32(),
            annotations: pending.annotations,
            rotation: pending.rotation,
            revision: pending.revision,
          );
        } catch (_) {
          // storeFullRaster already degrades internally; a throw here would
          // only kill the drain loop.
        } finally {
          pending.image.dispose();
        }
      }
    } finally {
      _drainingFullWrites = false;
      if (_disposed) _dropPendingFullWrites();
    }
  }

  void _dropPendingFullWrites() {
    for (final pending in _pendingFullWrites) {
      pending.image.dispose();
    }
    _pendingFullWrites.clear();
  }

  void _admitFullImage(
    int index,
    PdfPage page,
    ui.Image image, {
    required Color pageColor,
    required bool annotations,
    required int? rotation,
  }) {
    if (_disposed) return;
    final signature = PdfPageRasterSignature(
      pageIndex: index,
      width: image.width,
      height: image.height,
      pageColor: pageColor,
      annotations: annotations,
      rotation: rotation,
    );
    final bytes = signature.bytes;
    final rejection = _maxFullRasterBytes == 0
        ? 'disabled'
        : bytes > _maxFullRasterEntryBytes
            ? 'entry-limit'
            : bytes > _maxFullRasterBytes
                ? 'total-limit'
                : null;
    if (rejection != null) {
      _logFullRasterLookup(
        'reject',
        index,
        reason: rejection,
        bytes: bytes,
      );
      return;
    }
    final beforeEvictions = _fullEntries.evictions;
    // A revision swap that changed this page leaves entries no lookup can use;
    // drop them here rather than letting them age out of a budget the fresh
    // raster needs.
    _dropStaleVariants(index, page);
    // put disposes any prior entry for this exact signature and evicts the LRU
    // rasters past the byte budget; the entry just stored (which the guard
    // above kept within budget) is never the one evicted.
    _fullEntries.put(
      signature,
      _FullRasterEntry(
        page,
        image.clone(),
        pageColor: pageColor,
        annotations: annotations,
        rotation: rotation,
      ),
    );
    _trimVariants(index, keep: signature);
    if (!_fullEntries.containsKey(signature)) {
      _logFullRasterLookup(
        'reject',
        index,
        reason: 'coordinated-ceiling',
        bytes: bytes,
      );
      return;
    }
    PdfPerfLog.log(
      'page-raster store page=$index bytes=$bytes ${signature.width}x'
      '${signature.height} '
      'evicted=${_fullEntries.evictions - beforeEvictions} '
      '${_fullRasterState()}${PdfPerfLog.rssSuffix()}',
    );
  }

  /// Drops every retained raster of page [index] whose entry belongs to a
  /// different document revision than [page].
  void _dropStaleVariants(int index, PdfPage page) {
    _fullEntries.evictWhere((key) {
      if (key.pageIndex != index) return false;
      final entry = _fullEntries.peek(key);
      return entry != null && !identical(entry.page, page);
    });
  }

  /// Keeps at most [_maxVariantsPerPage] geometries for page [index],
  /// dropping the least-recently-used first and never [keep].
  void _trimVariants(int index, {required PdfPageRasterSignature keep}) {
    // _fullEntries.keys is least-recently-used first, so the oldest variants
    // of this page come out of this list in eviction order. `keep` is excluded
    // and counted separately - it is the one that must survive.
    final variants = [
      for (final key in _fullEntries.keys)
        if (key.pageIndex == index && key != keep) key,
    ];
    final excess = variants.length + 1 - _maxVariantsPerPage;
    for (var i = 0; i < excess; i++) {
      _fullEntries.evict(variants[i]); // disposes the image
      PdfPerfLog.log(
        'page-raster evict page=$index reason=variant-cap '
        '${_fullRasterState()}',
      );
    }
  }

  void _logFullRasterEviction(
      PdfPageRasterSignature key, _FullRasterEntry entry) {
    PdfPerfLog.log(
      'page-raster evict page=${key.pageIndex} bytes=${entry.bytes} '
      'reason=budget ${_fullRasterState()}${PdfPerfLog.rssSuffix()}',
    );
  }

  void _logFullRasterLookup(
    String event,
    int index, {
    String? reason,
    int? bytes,
  }) {
    PdfPerfLog.log(
      'page-raster $event page=$index'
      '${bytes == null ? '' : ' bytes=$bytes'}'
      '${reason == null ? '' : ' reason=$reason'} '
      '${_fullRasterState()}${PdfPerfLog.rssSuffix()}',
    );
  }

  String _fullRasterState() {
    final registry = PdfCacheRegistry.instance;
    return 'retained=${_fullEntries.weight} entries=${_fullEntries.length} '
        'totalLimit=$_maxFullRasterBytes '
        'entryLimit=$_maxFullRasterEntryBytes '
        'registry=${registry.totalWeight} ceiling=${registry.maxTotalWeight}';
  }

  /// Whether any preview (fresh or stale) exists for page [index].
  bool has(int index) => _entries.containsKey(index);

  /// Whether the cached preview for [index] was rendered from exactly
  /// this [page] object - the staleness test both fill paths use to
  /// skip redundant work.
  bool isFresh(int index, PdfPage page, {bool requireImages = false}) {
    final entry = _entries.peek(index); // a staleness check, not a use
    if (!identical(entry?.page, page)) return false;
    return !requireImages || entry!.includesImages;
  }

  double _ratioFor(Size size) {
    final longest = math.max(size.width, size.height);
    if (longest <= 0) return 1;
    return math.min(1, longestSide / longest);
  }

  /// Interprets [page] and stores its preview - the background-prerender
  /// path for pages that have never rendered on screen. When [worker] is
  /// supplied the interpreter walk is offloaded to a background isolate and
  /// only the (cheap) replay + downscale run here; otherwise the walk is
  /// synchronous UI-thread work, so callers pace and gate these (the viewer
  /// pauses while the user scrolls). A page that fails to render simply gets
  /// no preview.
  Future<void> renderPreview(int index, PdfPage page,
      {Color pageColor = const Color(0xFFFFFFFF),
      bool annotations = true,
      PdfRenderWorker? worker,
      int? rotation,
      bool decodeImages = true,
      int priority = 1,
      int? commandLimit,
      bool Function()? deferUiWork}) async {
    if (_disposed || isFresh(index, page, requireImages: decodeImages)) return;
    if (!decodeImages && (worker == null || !worker.isActive)) {
      // A vector-first preview is only cheap through the worker. The local
      // fallback would run a full UI-thread render and decode the images, which
      // is exactly what fast-scroll prefetch is trying to avoid.
      return;
    }
    try {
      final sw = Stopwatch()..start();
      final size = PdfPageRenderer.pageSize(page, rotation: rotation);
      final ratio = _ratioFor(size);
      // priority 1: prefetch yields to any on-screen page the worker owes.
      // The preview is rasterized at [ratio] (longest side ~200px), so cap the
      // worker's images to that - a heavy raster underlay need not ship at full
      // resolution just to be downscaled into a thumbnail.
      final commands = worker != null && worker.isActive
          ? await worker.record(index,
              annotations: annotations,
              priority: priority,
              imagePixelRatio: decodeImages ? ratio : null,
              decodeImages: decodeImages,
              commandLimit: commandLimit)
          : null;
      if (!decodeImages && commands == null) {
        // Worker-declined vector warms must stay cheap. Falling back to
        // renderImage here would synchronously interpret/decode images on the
        // UI thread during the fast-scroll path.
        return;
      }
      if (deferUiWork?.call() ?? false) return;
      if (_disposed || isFresh(index, page, requireImages: decodeImages)) {
        return;
      }
      final ui.Image image;
      var includesImages = decodeImages;
      if (commands != null) {
        includesImages = commandLimit == null &&
            (decodeImages || !PdfPageRenderer.hasImageDraws(commands));
        final picture = await PdfPageRenderer.pictureFromCommands(
            page, commands,
            pageColor: pageColor,
            rotation: rotation,
            includeImages: decodeImages,
            maxImagePixelRatio: ratio);
        if (deferUiWork?.call() ?? false) {
          picture.dispose();
          return;
        }
        try {
          image = await PdfPageRenderer.rasterize(picture, size, ratio);
        } finally {
          picture.dispose();
        }
      } else {
        if (deferUiWork?.call() ?? false) return;
        image = await PdfPageRenderer.renderImage(page,
            pixelRatio: ratio,
            pageColor: pageColor,
            annotations: annotations,
            recorded: true,
            rotation: rotation);
      }
      if (deferUiWork?.call() ?? false) {
        image.dispose();
        return;
      }
      sw.stop();
      PdfPerfLog.log('prerender page=$index '
          '${commands != null ? 'worker ' : ''}'
          '${includesImages ? 'full' : 'vector'} '
          'warm=${(sw.elapsedMicroseconds / 1000).toStringAsFixed(1)}ms');
      if (_disposed || isFresh(index, page, requireImages: decodeImages)) {
        image.dispose();
        return;
      }
      _store(index, page, image, includesImages: includesImages);
    } catch (_) {
      // no preview is strictly better than a crash mid-scroll
    }
  }

  /// Bakes the exact, display-sized raster of an off-screen page into the
  /// full-raster cache - the idle warm's one unit of work.
  ///
  /// This is the same interpretation and readback the page would run on its
  /// first arrival on screen, moved to a moment the viewer is doing nothing.
  /// [signature] is the geometry the page will *later* ask the cache for
  /// (see [PdfPageRasterGeometry]); rendering at anything else would produce a
  /// raster that can only miss.
  ///
  /// Ordering of the guards is the point:
  ///
  ///  * a raster already retained for this page and geometry is skipped
  ///    without touching LRU order,
  ///  * a raster the policy could not admit is declined *before* any
  ///    interpretation - the expensive part - rather than after,
  ///  * [shouldStop] is polled around every await, so a scroll, zoom, edit, or
  ///    foreground render arriving mid-warm abandons the pass instead of
  ///    finishing it on top of the frame the user is waiting for.
  ///
  /// [worker] moves the interpreter walk off the platform thread when the
  /// backend offloads; [priority] should stay above any foreground request so
  /// a visible page always wins the worker's queue. Returns whether a raster
  /// was stored.
  Future<bool> warmFullRaster(
    int index,
    PdfPage page, {
    required PdfPageRasterSignature signature,
    required double pixelRatio,
    PdfRenderWorker? worker,
    int priority = 4,
    bool Function()? shouldStop,
  }) async {
    if (_disposed) return false;
    if (hasFullRaster(signature, page)) {
      _warmSkips++;
      return false;
    }
    if (!admitsFullRaster(signature.bytes)) {
      _warmRejections++;
      PdfPerfLog.log(
        'raster-warm decline page=$index bytes=${signature.bytes} '
        'reason=inadmissible ${_fullRasterState()}',
      );
      return false;
    }
    if (shouldStop?.call() ?? false) return false;
    _warmAttempts++;
    final sw = Stopwatch()..start();
    var stored = false;
    try {
      final size = PdfPageRenderer.pageSize(page, rotation: signature.rotation);
      final commands = worker != null && worker.isActive
          ? await worker.record(index,
              annotations: signature.annotations,
              priority: priority,
              imagePixelRatio: pixelRatio)
          : null;
      if (shouldStop?.call() ?? false) {
        _warmPreemptions++;
        return false;
      }
      if (_disposed || hasFullRaster(signature, page)) return false;
      ui.Picture? picture;
      final ui.Image image;
      if (commands != null) {
        picture = await PdfPageRenderer.pictureFromCommands(page, commands,
            pageColor: signature.pageColor,
            rotation: signature.rotation,
            maxImagePixelRatio: pixelRatio);
      } else {
        // No worker (or it declined): the walk runs here, exactly as it would
        // when the page arrives on screen. That is the cost being moved into
        // idle time, so it is worth paying - but only while nothing else
        // wants the thread.
        picture = await PdfPageRenderer.renderPictureRecordedWithPlan(
          page,
          PdfPageRenderPlan(
            pageColor: signature.pageColor,
            annotations: signature.annotations,
            rotation: signature.rotation,
          ),
          maxImagePixelRatio: pixelRatio,
        );
      }
      if ((shouldStop?.call() ?? false) || _disposed) {
        picture.dispose();
        if (!_disposed) _warmPreemptions++;
        return false;
      }
      try {
        image = await PdfPageRenderer.rasterize(picture, size, pixelRatio);
      } catch (_) {
        picture.dispose();
        rethrow;
      }
      if (_disposed) {
        image.dispose();
        picture.dispose();
        return false;
      }
      try {
        // The raster the warm exists to produce. A late shouldStop is
        // deliberately NOT honoured here: the pixels are already paid for, and
        // storing them costs a clone, not a frame.
        putFullImage(
          index,
          page,
          image,
          pageColor: signature.pageColor,
          annotations: signature.annotations,
          rotation: signature.rotation,
        );
        stored = hasFullRaster(signature, page);
        if (stored) {
          _warmCompletions++;
          _warmedBytes += signature.bytes;
        }
        // The interpretation is already in hand, so the low-resolution
        // navigation preview comes free - no second walk when the background
        // prerender reaches this page.
        if (!isFresh(index, page, requireImages: true)) {
          await putFromPicture(index, page, picture,
              rotation: signature.rotation);
        }
      } finally {
        image.dispose();
        picture.dispose();
      }
      PdfPerfLog.log(
        'raster-warm page=$index ${signature.width}x${signature.height} '
        '${commands != null ? 'worker ' : 'local '}'
        'stored=$stored '
        'warm=${(sw.elapsedMicroseconds / 1000).toStringAsFixed(1)}ms '
        '${_fullRasterState()}',
      );
    } catch (_) {
      // A page that fails to warm simply isn't cached; it renders on arrival
      // exactly as it would have without the warm.
    }
    return stored;
  }

  /// A snapshot of what the idle warm and the exact-raster cache have done.
  PdfPageRasterWarmStats get warmStats => PdfPageRasterWarmStats(
        attempts: _warmAttempts,
        completions: _warmCompletions,
        skipped: _warmSkips,
        rejected: _warmRejections,
        preempted: _warmPreemptions,
        warmedBytes: _warmedBytes,
        hits: _fullEntries.hits,
        misses: _fullEntries.misses,
        evictions: _fullEntries.evictions,
        retainedBytes: _fullEntries.weight,
        entries: _fullEntries.length,
      );

  /// Downscales an already-interpreted [picture] into the cache - free
  /// population as pages render on screen (raster-thread work only, no
  /// second interpreter walk). The picture stays owned by the caller.
  Future<void> putFromPicture(int index, PdfPage page, ui.Picture picture,
      {int? rotation}) async {
    if (_disposed || isFresh(index, page, requireImages: true)) return;
    try {
      final size = PdfPageRenderer.pageSize(page, rotation: rotation);
      final image =
          await PdfPageRenderer.rasterize(picture, size, _ratioFor(size));
      _store(index, page, image, includesImages: true);
    } catch (_) {
      // the caller can dispose the picture mid-rasterize (page swap)
    }
  }

  void _store(int index, PdfPage page, ui.Image image,
      {required bool includesImages}) {
    if (_disposed) {
      image.dispose();
      return;
    }
    // put disposes any prior preview for this index and evicts the LRU past
    // capacity, never the entry just stored.
    _entries.put(
        index, _PreviewEntry(page, image, includesImages: includesImages));
    // Write through to disk so the next session opens with this preview
    // already on screen. Fire-and-forget: the encode is a raster-thread
    // readback and a slow/failed store must never stall rendering.
    if (includesImages) disk?.storePreview(index, image);
    notifyListeners();
  }

  /// Re-binds entries to the page objects of a same-geometry document
  /// revision (an edit swap) without re-rendering. Previews of pages the
  /// edit visually changed go briefly stale - they refresh from the full
  /// render the moment the page is on screen, which is where edits
  /// happen - but the whole document doesn't re-interpret per pen
  /// stroke.
  ///
  /// [changed] (when given) names pages whose *content* changed in the new
  /// revision - most importantly a redaction burn, where the old preview
  /// still shows the removed glyphs/images. Their previews are dropped
  /// rather than rebound, so a fresh page state scrolled past during a fast
  /// scroll paints blank (then re-renders) instead of flashing now-deleted
  /// content. The rest rebind in place as before.
  void rebind(List<PdfPage> pages, {bool Function(int index)? changed}) {
    // A retained scene keeps the PdfPage it was recorded from as well as its
    // command objects. Even an unchanged page in an incremental revision has
    // a new document graph, so do not rebind these by index the way immutable
    // raster pixels can be rebound.
    _retainedScenes.clear();
    var dropped = false;
    for (final index in _entries.keys.toList()) {
      if (changed != null && changed(index)) {
        _entries.evict(index); // disposes the image
        dropped = true;
      } else if (index < pages.length) {
        _entries.peek(index)!.page = pages[index]; // rebind, no reorder
      }
    }
    for (final key in _fullEntries.keys.toList()) {
      final index = key.pageIndex;
      if (changed != null && changed(index)) {
        _fullEntries.evict(key); // disposes the image, subtracts its pixels
        dropped = true;
      } else if (index < pages.length) {
        _fullEntries.peek(key)!.page = pages[index]; // rebind, no reorder
      } else {
        // the revision has fewer pages than this raster's index
        _fullEntries.evict(key);
        dropped = true;
      }
    }
    if (dropped && !_disposed) notifyListeners();
  }

  /// Drops every preview (different document, page color change...).
  void clear() {
    _entries.clear(); // disposes every retained image
    _fullEntries.clear();
    _retainedScenes.clear();
    // Queued writes belong to the document being left behind.
    _dropPendingFullWrites();
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _entries.dispose(); // disposes every retained image
    _fullEntries.dispose();
    _retainedScenes.dispose();
    // A drain in flight sees _disposed and clears the rest itself; clearing
    // here covers the (usual) case where nothing is draining.
    if (!_drainingFullWrites) _dropPendingFullWrites();
    super.dispose();
  }
}

class _PendingFullRasterWrite {
  _PendingFullRasterWrite(
    this.index,
    this.image, {
    required this.pageColor,
    required this.annotations,
    required this.rotation,
    required this.revision,
  });

  final int index;
  final ui.Image image;
  final Color pageColor;
  final bool annotations;
  final int? rotation;
  final String revision;
}

/// A pinned reference to a complete retained page scene.
///
/// Obtained from [PdfPagePreviewCache.retainedSceneFor] or
/// [PdfPagePreviewCache.retainScene]. Dispose the handle when the page widget
/// no longer needs the scene. The scene itself remains cached until its LRU
/// slot is evicted; if eviction happens first, the final live handle releases
/// it safely.
class PdfRetainedSceneHandle {
  PdfRetainedSceneHandle._(this._entry);

  _RetainedSceneEntry? _entry;

  PdfRetainedScene get scene {
    final entry = _entry;
    if (entry == null) throw StateError('Retained scene handle is disposed');
    return entry.scene;
  }

  bool get fromWorker {
    final entry = _entry;
    if (entry == null) throw StateError('Retained scene handle is disposed');
    return entry.fromWorker;
  }

  /// The complete page picture retained beside [scene], when the producer had
  /// one. It is owned by this handle/cache entry; callers must not dispose it.
  ui.Picture? get picture {
    final entry = _entry;
    if (entry == null) throw StateError('Retained scene handle is disposed');
    return entry.picture;
  }

  void dispose() {
    final entry = _entry;
    if (entry == null) return;
    _entry = null;
    entry.release();
  }
}

@immutable
class _RetainedSceneKey {
  const _RetainedSceneKey(this.pageIndex, this.plan);

  final int pageIndex;
  final PdfPageRenderPlan plan;

  @override
  bool operator ==(Object other) =>
      other is _RetainedSceneKey &&
      pageIndex == other.pageIndex &&
      plan == other.plan;

  @override
  int get hashCode => Object.hash(pageIndex, plan);
}

class _RetainedSceneEntry {
  _RetainedSceneEntry(
    this.page,
    this.scene, {
    this.picture,
    required this.fromWorker,
    required this.estimatedBytes,
  });

  final PdfPage page;
  final PdfRetainedScene scene;
  final ui.Picture? picture;
  final bool fromWorker;
  final int estimatedBytes;

  var _cacheReference = true;
  var _leases = 0;
  var _disposed = false;

  PdfRetainedSceneHandle acquire() {
    if (_disposed) throw StateError('Retained scene is already disposed');
    _leases++;
    return PdfRetainedSceneHandle._(this);
  }

  void dropCacheReference() {
    if (!_cacheReference) return;
    _cacheReference = false;
    _disposeIfUnused();
  }

  void release() {
    if (_leases == 0) return;
    _leases--;
    _disposeIfUnused();
  }

  void _disposeIfUnused() {
    if (_cacheReference || _leases != 0 || _disposed) return;
    _disposed = true;
    scene.dispose();
    picture?.dispose();
  }
}

class _PreviewEntry {
  _PreviewEntry(this.page, this.image, {required this.includesImages});

  PdfPage page;
  final ui.Image image;
  final bool includesImages;
}

class _FullRasterEntry {
  _FullRasterEntry(
    this.page,
    this.image, {
    required this.pageColor,
    required this.annotations,
    required this.rotation,
  });

  PdfPage page;
  final ui.Image image;
  final Color pageColor;
  final bool annotations;
  final int? rotation;

  int get bytes => image.width * image.height * 4;
}
