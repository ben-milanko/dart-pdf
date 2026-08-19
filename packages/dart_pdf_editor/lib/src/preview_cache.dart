import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';
import 'package:pdf_document/pdf_document.dart';

import 'budgeted_cache.dart';
import 'perf_log.dart';
import 'performance_policy.dart';
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

/// Memory and background-work policy for the middle steps in the page-preview
/// ladder.
///
/// Fast scrolling always keeps the existing tiny preview (200 px on its
/// longest side by default) as the cheapest immediate fallback. When the
/// viewer is idle, pages close to the viewport are additionally promoted to
/// [intermediateLongestSides]. A completed on-screen raster can also populate
/// these tiers with scaled image blits, without another PDF interpretation.
/// The final display-sized raster remains separate.
///
/// The defaults make the visible steps roughly 200 px -> 400 px -> 800 px ->
/// the display raster. Each promotion doubles linear resolution (and therefore
/// quadruples pixels), so every level is visibly worthwhile. A shared 32 MiB
/// RGBA budget keeps the ladder around the working set rather than one for
/// every page in a long document. All values are configurable because a
/// desktop document workstation and a memory-constrained phone should not be
/// forced into the same trade-off.
@immutable
class PdfPagePreviewLodPolicy {
  const PdfPagePreviewLodPolicy({
    this.intermediateLongestSides = const [400, 800],
    this.intermediateWindow = 2,
    this.maxBytes = 32 * 1024 * 1024,
    this.maxEntryBytes = 4 * 1024 * 1024,
  })  : assert(intermediateWindow >= 0),
        assert(maxBytes >= 0),
        assert(maxEntryBytes >= 0);

  /// Keeps only the tiny preview and the final raster.
  const PdfPagePreviewLodPolicy.disabled()
      : intermediateLongestSides = const [],
        intermediateWindow = 0,
        maxBytes = 0,
        maxEntryBytes = 0;

  /// Pixel sizes of the intermediate previews' longest sides.
  ///
  /// Values at or below the base preview size, duplicates, and non-positive
  /// values are ignored; the remaining values are used in ascending order.
  /// Keep this list short: each entry is another idle rasterization level.
  final List<double> intermediateLongestSides;

  /// Pages on either side of the current page proactively promoted while
  /// idle. Pages actually viewed can still enter the tier outside this
  /// window by being downscaled from their completed display raster.
  final int intermediateWindow;

  /// Total approximate RGBA byte budget for intermediate previews.
  final int maxBytes;

  /// Largest individual intermediate preview admitted to the cache.
  final int maxEntryBytes;

  bool get enabled =>
      intermediateLongestSides.isNotEmpty && maxBytes > 0 && maxEntryBytes > 0;

  @override
  bool operator ==(Object other) =>
      other is PdfPagePreviewLodPolicy &&
      listEquals(intermediateLongestSides, other.intermediateLongestSides) &&
      intermediateWindow == other.intermediateWindow &&
      maxBytes == other.maxBytes &&
      maxEntryBytes == other.maxEntryBytes;

  @override
  int get hashCode => Object.hash(Object.hashAll(intermediateLongestSides),
      intermediateWindow, maxBytes, maxEntryBytes);
}

/// The progressive page-preview levels below the final display raster.
enum PdfPagePreviewLod { base, intermediate }

/// Snapshot of the preview pyramid's retained working set.
///
/// Exposed through [PdfViewerController.pagePreviewLodStats] and emitted in
/// `preview-store` performance lines so DevTools/support traces can distinguish
/// a genuinely missing middle level from one that was warmed and evicted.
@immutable
class PdfPagePreviewLodStats {
  const PdfPagePreviewLodStats({
    required this.baseEntries,
    required this.baseBytes,
    required this.intermediateEntries,
    required this.intermediateBytes,
    required this.intermediateEvictions,
  });

  final int baseEntries;
  final int baseBytes;
  final int intermediateEntries;
  final int intermediateBytes;
  final int intermediateEvictions;

  @override
  String toString() => 'preview-lod base=$baseEntries/${baseBytes}B '
      'intermediate=$intermediateEntries/${intermediateBytes}B '
      'evictions=$intermediateEvictions';
}

/// One owned preview clone plus the quality metadata needed to promote a live
/// page without accidentally downgrading it when an LRU eviction occurs.
class PdfPagePreviewFrame {
  const PdfPagePreviewFrame({
    required this.image,
    required this.lod,
    required this.targetLongestSide,
    required this.includesImages,
    required this.generation,
  });

  /// The caller-owned image clone.
  final ui.Image image;
  final PdfPagePreviewLod lod;
  final double targetLongestSide;
  final bool includesImages;
  final int generation;
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
    PdfPagePreviewLodPolicy lodPolicy = const PdfPagePreviewLodPolicy(),
    int maxFullRasterPixels = 8 << 20,
    int maxFullRasterEntryPixels = 4 << 20,
    int? maxRetainedSceneBytes,
    int maxRetainedSceneEntries = 32,
  })  : assert(maxFullRasterPixels >= 0),
        assert(maxFullRasterEntryPixels >= 0),
        assert(maxRetainedSceneBytes == null || maxRetainedSceneBytes >= 0),
        assert(maxRetainedSceneEntries > 0),
        _intermediateLongestSides = _normalizedIntermediateSides(
          longestSide,
          lodPolicy.intermediateLongestSides,
        ),
        _maxIntermediateBytes = lodPolicy.maxBytes,
        _maxIntermediateEntryBytes = lodPolicy.maxEntryBytes,
        _maxFullRasterBytes = maxFullRasterPixels * 4,
        _maxFullRasterEntryBytes = maxFullRasterEntryPixels * 4,
        _maxRetainedSceneBytes =
            maxRetainedSceneBytes ?? pdfDefaultRetainedSceneBytes(),
        _maxRetainedSceneEntries = maxRetainedSceneEntries;

  /// Pixel size of a preview's longest side. Stretched to page size on
  /// screen the result is soft but recognizable - enough to navigate by.
  final double longestSide;

  /// Maximum number of cached previews (LRU eviction past it).
  final int capacity;

  List<double> _intermediateLongestSides;
  int _maxIntermediateBytes;
  int _maxIntermediateEntryBytes;

  /// Pixel sizes of the configured intermediate previews' longest sides.
  List<double> get intermediateLongestSides =>
      List<double>.unmodifiable(_intermediateLongestSides);

  /// Approximate bytes retained by intermediate previews.
  int get intermediateBytes => _intermediateEntries.weight;

  /// Number of retained intermediate previews.
  int get intermediateCount => _intermediateEntries.length;

  /// Intermediate previews evicted by the byte budget.
  int get intermediateEvictions => _intermediateEntries.evictions;

  /// Current low/intermediate cache occupancy for diagnostics.
  PdfPagePreviewLodStats get lodStats => PdfPagePreviewLodStats(
        baseEntries: _entries.length,
        baseBytes: _entries.values.fold(0, (sum, entry) => sum + entry.bytes),
        intermediateEntries: _intermediateEntries.length,
        intermediateBytes: _intermediateEntries.weight,
        intermediateEvictions: _intermediateEntries.evictions,
      );

  /// Total pixel budget for exact, recently-viewed page rasters.
  ///
  /// These entries remove the soft-preview delay when a lazy page widget is
  /// rebuilt during back-and-forth scrolling. The default is about 32 MiB of
  /// RGBA pixels. Set to zero to keep only the progressive preview ladder.
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

  /// Entry ceiling for the retained-scene LRU, alongside its byte budget.
  ///
  /// [_maxRetainedSceneBytes] is the governor; this is only a backstop against
  /// a pathological number of tiny entries, so it is far above what any real
  /// document reaches. It used to be 4 - the whole document's allowance - and
  /// that, not the budget, was what made a reader on a long text document
  /// re-render pages shown seconds earlier: a scene restored from here paints
  /// with no record, no replay and no worker round trip.
  final int _maxRetainedSceneEntries;

  // Three shared budgeted LRUs: base previews bounded by entry count,
  // intermediate previews and exact recent-page rasters bounded by bytes. All
  // dispose evicted images; the budgets live in PdfBudgetedCache (and are
  // property-tested there), so this class keeps only the preview-domain logic
  // (disk write-through, rebinding, staleness) on top.
  late final PdfBudgetedCache<int, _PreviewEntry> _entries =
      PdfBudgetedCache<int, _PreviewEntry>(
    maxEntries: capacity,
    disposer: (entry) => entry.image.dispose(),
    debugLabel: 'page-preview',
  );
  late final PdfBudgetedCache<_IntermediatePreviewKey, _PreviewEntry>
      _intermediateEntries =
      PdfBudgetedCache<_IntermediatePreviewKey, _PreviewEntry>(
    weigher: (entry) => entry.bytes,
    maxWeight: _maxIntermediateBytes,
    disposer: (entry) => entry.image.dispose(),
    onEvicted: (key, entry) => PdfPerfLog.log(
      'preview-evict page=${key.pageIndex} lod=${key.longestSide}px '
      'bytes=${entry.bytes} '
      'retained=${_intermediateEntries.weight} '
      'limit=$_maxIntermediateBytes${PdfPerfLog.rssSuffix()}',
    ),
    clearsUnderMemoryPressure: true,
    debugLabel: 'page-preview-intermediate',
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
  int _previewGeneration = 0;
  List<PdfPage>? _boundPages;

  /// Binds future asynchronous cache admissions to the viewer's current page
  /// objects.
  ///
  /// A render or image-scale operation can complete after an edit has swapped
  /// the document revision. Without this guard that old result can re-enter a
  /// changed page's cache after [rebind] deliberately invalidated it (most
  /// visibly flashing removed content after a redaction). Standalone cache
  /// users do not have to bind; the viewer always does.
  void bindPages(List<PdfPage> pages) {
    _boundPages = List<PdfPage>.of(pages, growable: false);
  }

  bool _acceptsPage(int index, PdfPage page) {
    final pages = _boundPages;
    return pages == null ||
        (index >= 0 && index < pages.length && identical(pages[index], page));
  }

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

  /// Applies a new intermediate-LoD policy and trims the working set now.
  ///
  /// Changing only the byte limits preserves compatible images. Changing the
  /// requested sizes drops the middle ladder because its cache keys no longer
  /// describe levels the viewer will request; the tiny persistent preview and
  /// exact display rasters are unaffected.
  void configurePreviewLods(PdfPagePreviewLodPolicy policy) {
    if (_disposed) return;
    final sides = _normalizedIntermediateSides(
      longestSide,
      policy.intermediateLongestSides,
    );
    var changed = false;
    if (!listEquals(sides, _intermediateLongestSides)) {
      _intermediateEntries.clear();
      _intermediateLongestSides = sides;
      changed = true;
    }
    final beforeCount = _intermediateEntries.length;
    final beforeBytes = _intermediateEntries.weight;
    _maxIntermediateBytes = policy.maxBytes;
    _maxIntermediateEntryBytes = policy.maxEntryBytes;
    _intermediateEntries.evictWhere((key) {
      final entry = _intermediateEntries.peek(key);
      return entry != null && entry.bytes > _maxIntermediateEntryBytes;
    });
    _intermediateEntries.maxWeight = _maxIntermediateBytes;
    changed |= beforeCount != _intermediateEntries.length;
    PdfPerfLog.log(
      'preview-lod policy levels=${_intermediateLongestSides.join(',')} '
      'window=${policy.intermediateWindow} total=${policy.maxBytes} '
      'entry=${policy.maxEntryBytes} retained=${_intermediateEntries.weight} '
      'entries=${_intermediateEntries.length} '
      'trimmedEntries=${beforeCount - _intermediateEntries.length} '
      'trimmedBytes=${beforeBytes - _intermediateEntries.weight} '
      'registry=${PdfCacheRegistry.instance.totalWeight} '
      'ceiling=${PdfCacheRegistry.instance.maxTotalWeight}'
      '${PdfPerfLog.rssSuffix()}',
    );
    if (changed && !_disposed) notifyListeners();
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
      _entries.put(
        i,
        _PreviewEntry(
          pages[i],
          image,
          includesImages: true,
          generation: ++_previewGeneration,
        ),
      );
      notifyListeners();
    }
  }

  /// The preview for page [index], as a clone the caller owns (and must
  /// dispose), or null when none is cached. Counts as a use for LRU.
  ui.Image? imageFor(int index) => previewFor(index)?.image;

  /// The sharpest cached preview for [index], with an owned image clone and
  /// enough metadata for a live page to accept genuine promotions while
  /// ignoring unrelated cache notifications or an LRU-driven downgrade.
  PdfPagePreviewFrame? previewFor(int index) {
    _IntermediatePreviewKey? bestKey;
    _PreviewEntry? best;
    for (final key in _intermediateEntries.keys) {
      if (key.pageIndex != index) continue;
      final entry = _intermediateEntries.peek(key)!;
      if (best == null || entry.pixels > best.pixels) {
        bestKey = key;
        best = entry;
      }
    }
    if (bestKey != null) {
      final entry = _intermediateEntries.take(bestKey)!;
      return PdfPagePreviewFrame(
        image: entry.image.clone(),
        lod: PdfPagePreviewLod.intermediate,
        targetLongestSide: bestKey.longestSide,
        includesImages: entry.includesImages,
        generation: entry.generation,
      );
    }
    final entry = _entries.take(index); // touch; the master stays cached
    if (entry == null) return null;
    return PdfPagePreviewFrame(
      image: entry.image.clone(),
      lod: PdfPagePreviewLod.base,
      targetLongestSide: longestSide,
      includesImages: entry.includesImages,
      generation: entry.generation,
    );
  }

  /// Returns a complete preview that already meets [width] × [height].
  ///
  /// Unlike [imageFor], this rejects command-limited/vector-only previews and
  /// stale page revisions. A caller may therefore use the returned clone as
  /// its final display raster instead of interpreting the same page again.
  /// This matters for mixed-format CAD documents: a panoramic sheet can make
  /// ordinary pages display at thumbnail size, where the normal 200 px preview
  /// is already at or above the requested physical resolution.
  ui.Image? completeImageFor(
    int index,
    PdfPage page, {
    required int width,
    required int height,
  }) {
    final entry = _entries.take(index); // a successful lookup is an LRU use
    if (entry == null ||
        !identical(entry.page, page) ||
        !entry.includesImages ||
        entry.image.width < width ||
        entry.image.height < height) {
      return null;
    }
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

  /// Prices a retained scene against the LRU's byte budget.
  ///
  /// The obvious inputs - the command transcript, the engine's own
  /// `Picture.approximateBytesUsed`, and the decoded images - add up to a
  /// number that is badly wrong for exactly the pages this cache is most
  /// useful for. A 38-command text page prices at ~0.5 MB that way and
  /// measures at ~9 MB of browser heap: what a retained picture actually
  /// holds is the engine's shaped text and path objects, which
  /// `approximateBytesUsed` does not count. Under-pricing did not just make
  /// the budget generous, it made it meaningless - and it lied to the
  /// process-wide [PdfCacheRegistry] the host's memory governor drives.
  ///
  /// So a scene is priced at no less than the raster it stands in for
  /// ([rasterBytes], the page's own WxHx4 at display resolution). That is the
  /// memory the alternative - keeping the page's pixels - would cost, it
  /// tracks page size and zoom on its own, and measured against the browser's
  /// agent memory it lands within ~20% of the truth on ordinary pages.
  static int priceRetainedScene({
    required int commandCount,
    required int pictureBytes,
    required int decodedImageBytes,
    required int rasterBytes,
  }) =>
      math.max(commandCount * 260 + pictureBytes, rasterBytes) +
      decodedImageBytes;

  /// Retains [scene] in the session LRU and returns a lease for the caller.
  ///
  /// [estimatedBytes] is what the entry costs against the byte budget - see
  /// [priceRetainedScene], which every caller should use to compute it.
  /// Oversize entries remain usable by the caller through the returned lease
  /// but are not cached.
  PdfRetainedSceneHandle retainScene(
    int index,
    PdfPage page,
    PdfRetainedScene scene, {
    required PdfPageRenderPlan plan,
    required bool fromWorker,
    double? imagePixelRatio,
    required int estimatedBytes,
    ui.Picture? picture,
  }) {
    final key = _RetainedSceneKey(index, plan);
    final entry = _RetainedSceneEntry(
      page,
      scene,
      picture: picture,
      fromWorker: fromWorker,
      imagePixelRatio: imagePixelRatio,
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
    if (_disposed || !_acceptsPage(index, page)) return;
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
    // The sharp raster is already paid for and on screen. Populate every
    // configured middle level by scaling that image, which is a cheap GPU
    // blit/readback and never another PDF interpretation or image decode.
    // This starts only after the full raster has landed, so first paint wins.
    if (_intermediateLongestSides.isNotEmpty) {
      unawaited(_putIntermediateLadderFromImage(
        index,
        page,
        image.clone(),
      ));
    }
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
  bool has(int index) =>
      _entries.containsKey(index) ||
      _intermediateEntries.keys.any((key) => key.pageIndex == index);

  /// Whether at least one middle-LoD preview exists for [index]. When
  /// [targetLongestSide] is supplied, checks that exact configured level.
  bool hasIntermediate(int index, {double? targetLongestSide}) =>
      targetLongestSide == null
          ? _intermediateEntries.keys.any((key) => key.pageIndex == index)
          : _intermediateEntries.containsKey(
              _IntermediatePreviewKey(index, targetLongestSide),
            );

  /// Whether the cached preview for [index] was rendered from exactly
  /// this [page] object - the staleness test both fill paths use to
  /// skip redundant work.
  bool isFresh(
    int index,
    PdfPage page, {
    bool requireImages = false,
    double? targetLongestSide,
  }) {
    final entry = targetLongestSide == null
        ? _entries.peek(index)
        : _intermediateEntries.peek(
            _IntermediatePreviewKey(index, targetLongestSide),
          ); // a staleness check, not a use
    if (!identical(entry?.page, page)) return false;
    return !requireImages || entry!.includesImages;
  }

  double _ratioFor(Size size, {double? targetLongestSide}) {
    final longest = math.max(size.width, size.height);
    if (longest <= 0) return 1;
    return math.min(1, (targetLongestSide ?? longestSide) / longest);
  }

  /// Interprets [page] and stores its preview - the background-prerender
  /// path for pages that have never rendered on screen. When [worker] is
  /// supplied the interpreter walk is offloaded to a background isolate and
  /// only the (cheap) replay + downscale run here; otherwise the walk is
  /// synchronous UI-thread work, so callers pace and gate these (the viewer
  /// pauses while the user scrolls). A page that fails to render simply gets
  /// no preview.
  ///
  /// [alsoFillLongestSides] names further ladder rungs to fill from the *same*
  /// interpretation. The ladder's rungs differ only in raster size, so walking
  /// the content stream once per rung was pure waste: the field trace behind
  /// #699 shows one page warmed to base/400px/800px costing three interprets
  /// and 227 ms of platform thread. The page is recorded once, at the sharpest
  /// requested rung's image resolution, and every rung is rasterized from that
  /// one picture.
  Future<void> renderPreview(int index, PdfPage page,
      {Color pageColor = const Color(0xFFFFFFFF),
      bool annotations = true,
      PdfRenderWorker? worker,
      int? rotation,
      bool decodeImages = true,
      double? targetLongestSide,
      List<double> alsoFillLongestSides = const [],
      int priority = 1,
      int? commandLimit,
      bool Function()? deferUiWork}) async {
    final intermediate = targetLongestSide != null;
    if (_disposed ||
        !_acceptsPage(index, page) ||
        (intermediate &&
            !_intermediateLongestSides.contains(targetLongestSide))) {
      return;
    }
    // Command-limited/vector-first pixels are the instant fallback. Promoting
    // that incomplete display would spend middle-tier memory on a preview
    // known to omit content, so intermediates are image-complete only.
    if (intermediate && !decodeImages) return;
    if (!decodeImages && (worker == null || !worker.isActive)) {
      // A vector-first preview is only cheap through the worker. The local
      // fallback would run a full UI-thread render and decode the images, which
      // is exactly what fast-scroll prefetch is trying to avoid.
      return;
    }
    // The rungs this build owes, the caller's own target first. A rung that is
    // already fresh, not configured, or (for intermediates) not image-complete
    // never joins.
    final targets = <double?>[];
    void consider(double? side) {
      if (targets.contains(side)) return;
      if (side != null &&
          (!decodeImages || !_intermediateLongestSides.contains(side))) {
        return;
      }
      if (isFresh(index, page,
          requireImages: decodeImages, targetLongestSide: side)) {
        return;
      }
      targets.add(side);
    }

    consider(targetLongestSide);
    for (final side in alsoFillLongestSides) {
      consider(side);
    }
    if (targets.isEmpty) return;
    try {
      final sw = Stopwatch()..start();
      final size = PdfPageRenderer.pageSize(page, rotation: rotation);
      // One build serves every rung, so it has to be recorded at the sharpest
      // one's resolution: images decoded for a 200px preview cannot be
      // sharpened into an 800px one afterwards.
      var buildRatio = 0.0;
      for (final side in targets) {
        buildRatio =
            math.max(buildRatio, _ratioFor(size, targetLongestSide: side));
      }
      // priority 1: prefetch yields to any on-screen page the worker owes.
      // Every rung is rasterized at or below [buildRatio], so cap the worker's
      // images to that - a heavy raster underlay need not ship at full
      // resolution just to be downscaled into a thumbnail.
      final commands = worker != null && worker.isActive
          ? await worker.record(index,
              annotations: annotations,
              priority: priority,
              imagePixelRatio: decodeImages ? buildRatio : null,
              decodeImages: decodeImages,
              commandLimit: commandLimit)
          : null;
      if (!decodeImages && commands == null) {
        // Worker-declined vector warms must stay cheap. Recording locally here
        // would synchronously interpret/decode images on the UI thread during
        // the fast-scroll path.
        return;
      }
      if (deferUiWork?.call() ?? false) return;
      if (_disposed || !_acceptsPage(index, page)) return;
      var includesImages = decodeImages;
      final plan = PdfPageRenderPlan(
          pageColor: pageColor, annotations: annotations, rotation: rotation);
      final ui.Picture picture;
      if (commands != null) {
        includesImages = commandLimit == null &&
            (decodeImages || !PdfPageRenderer.hasImageDraws(commands));
        picture = await PdfPageRenderer.pictureFromCommandsWithPlan(
            page, commands, plan,
            includeImages: decodeImages, maxImagePixelRatio: buildRatio);
      } else {
        picture = await PdfPageRenderer.renderPictureRecordedWithPlan(page, plan,
            maxImagePixelRatio: buildRatio);
      }
      try {
        var shared = false;
        for (final side in targets) {
          if (deferUiWork?.call() ?? false) return;
          if (_disposed ||
              !_acceptsPage(index, page) ||
              isFresh(index, page,
                  requireImages: decodeImages, targetLongestSide: side)) {
            continue;
          }
          final image = await PdfPageRenderer.rasterize(
              picture, size, _ratioFor(size, targetLongestSide: side));
          if (deferUiWork?.call() ?? false) {
            image.dispose();
            return;
          }
          if (_disposed ||
              !_acceptsPage(index, page) ||
              isFresh(index, page,
                  requireImages: decodeImages, targetLongestSide: side)) {
            image.dispose();
            continue;
          }
          // `shared` marks a rung that cost only its own raster because the
          // rung before it already paid for the interpret - the line a #699
          // trace comparison reads.
          PdfPerfLog.log('prerender page=$index '
              'lod=${side == null ? 'base' : '${side.toStringAsFixed(0)}px'} '
              '${commands != null ? 'worker ' : ''}'
              '${shared ? 'shared ' : ''}'
              '${includesImages ? 'full' : 'vector'} '
              'warm=${(sw.elapsedMicroseconds / 1000).toStringAsFixed(1)}ms');
          sw.reset();
          shared = true;
          _store(
            index,
            page,
            image,
            includesImages: includesImages,
            targetLongestSide: side,
          );
        }
      } finally {
        picture.dispose();
      }
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
    if (_disposed ||
        !_acceptsPage(index, page) ||
        isFresh(index, page, requireImages: true)) {
      return;
    }
    try {
      final size = PdfPageRenderer.pageSize(page, rotation: rotation);
      final image =
          await PdfPageRenderer.rasterize(picture, size, _ratioFor(size));
      _store(index, page, image, includesImages: true);
    } catch (_) {
      // the caller can dispose the picture mid-rasterize (page swap)
    }
  }

  Future<void> _putIntermediateFromImage(
    int index,
    PdfPage page,
    ui.Image source, {
    required double targetLongestSide,
  }) async {
    try {
      if (_disposed ||
          !_acceptsPage(index, page) ||
          !_intermediateLongestSides.contains(targetLongestSide) ||
          isFresh(
            index,
            page,
            requireImages: true,
            targetLongestSide: targetLongestSide,
          )) {
        return;
      }
      final sourceLongest = math.max(source.width, source.height).toDouble();
      final scale = math.min(1.0, targetLongestSide / sourceLongest);
      final width = math.max(1, (source.width * scale).round());
      final height = math.max(1, (source.height * scale).round());
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawImageRect(
        source,
        ui.Rect.fromLTWH(
          0,
          0,
          source.width.toDouble(),
          source.height.toDouble(),
        ),
        ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        ui.Paint()..filterQuality = ui.FilterQuality.medium,
      );
      final picture = recorder.endRecording();
      late final ui.Image image;
      try {
        image = await picture.toImage(width, height);
      } finally {
        picture.dispose();
      }
      if (_disposed ||
          !_acceptsPage(index, page) ||
          isFresh(
            index,
            page,
            requireImages: true,
            targetLongestSide: targetLongestSide,
          )) {
        image.dispose();
        return;
      }
      _store(
        index,
        page,
        image,
        includesImages: true,
        targetLongestSide: targetLongestSide,
      );
    } catch (_) {
      // The source may be disposed by a page/document swap while the engine is
      // rasterizing. The idle worker path can fill this level later.
    } finally {
      source.dispose();
    }
  }

  Future<void> _putIntermediateLadderFromImage(
      int index, PdfPage page, ui.Image source) async {
    try {
      // The requested full raster has only just been admitted. Let its ready
      // callback and compositor frame win before starting any cache-only GPU
      // downscale/readback work; otherwise a useful LoD side effect can sit in
      // front of the page the user is waiting to see.
      await SchedulerBinding.instance.endOfFrame;
      // Serialize promotions for this completed raster. Two simultaneous
      // toImage readbacks can turn a harmless post-paint cache fill into the
      // same completion burst the page scheduler deliberately avoids.
      final sourceLongest = math.max(source.width, source.height).toDouble();
      for (final target in _intermediateLongestSides.toList()) {
        if (_disposed || !_acceptsPage(index, page)) return;
        if (isFresh(
          index,
          page,
          requireImages: true,
          targetLongestSide: target,
        )) {
          continue;
        }
        await _putIntermediateFromImage(
          index,
          page,
          source.clone(),
          targetLongestSide: target,
        );
        // This source cannot contribute a sharper next level. Keeping the same
        // pixels under another nominal key only burns the shared byte budget.
        if (target >= sourceLongest) break;
      }
    } finally {
      source.dispose();
    }
  }

  void _store(int index, PdfPage page, ui.Image image,
      {required bool includesImages, double? targetLongestSide}) {
    if (_disposed || !_acceptsPage(index, page)) {
      image.dispose();
      if (!_disposed) {
        PdfPerfLog.log(
          'preview-reject page=$index '
          'lod=${targetLongestSide == null ? 'base' : '${targetLongestSide}px'} '
          'reason=page-revision${PdfPerfLog.rssSuffix()}',
        );
      }
      return;
    }
    final entry = _PreviewEntry(
      page,
      image,
      includesImages: includesImages,
      generation: ++_previewGeneration,
    );
    if (targetLongestSide == null) {
      // put disposes any prior preview for this index and evicts the LRU past
      // capacity, never the entry just stored.
      _entries.put(index, entry);
    } else {
      final bytes = entry.bytes;
      final rejection = _maxIntermediateBytes == 0
          ? 'disabled'
          : bytes > _maxIntermediateEntryBytes
              ? 'entry-limit'
              : bytes > _maxIntermediateBytes
                  ? 'total-limit'
                  : null;
      if (rejection != null) {
        image.dispose();
        PdfPerfLog.log(
          'preview-reject page=$index lod=${targetLongestSide}px '
          'bytes=$bytes reason=$rejection retained=${_intermediateEntries.weight} '
          'limit=$_maxIntermediateBytes entryLimit=$_maxIntermediateEntryBytes'
          '${PdfPerfLog.rssSuffix()}',
        );
        return;
      }
      _intermediateEntries.put(
        _IntermediatePreviewKey(index, targetLongestSide),
        entry,
      );
    }
    PdfPerfLog.log(
      'preview-store page=$index '
      'lod=${targetLongestSide == null ? 'base' : '${targetLongestSide}px'} '
      '${image.width}x${image.height} bytes=${entry.bytes} '
      'baseEntries=${_entries.length} '
      'intermediateEntries=${_intermediateEntries.length} '
      'intermediateBytes=${_intermediateEntries.weight}'
      '${PdfPerfLog.rssSuffix()}',
    );
    // Write through to disk so the next session opens with this preview
    // already on screen. Fire-and-forget: the encode is a raster-thread
    // readback and a slow/failed store must never stall rendering.
    if (targetLongestSide == null && includesImages) {
      disk?.storePreview(index, image);
    }
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
    bindPages(pages);
    var dropped = false;
    for (final index in _entries.keys.toList()) {
      if (changed != null && changed(index)) {
        _entries.evict(index); // disposes the image
        dropped = true;
      } else if (index < pages.length) {
        _entries.peek(index)!.page = pages[index]; // rebind, no reorder
      }
    }
    for (final key in _intermediateEntries.keys.toList()) {
      final index = key.pageIndex;
      if (changed != null && changed(index)) {
        _intermediateEntries.evict(key); // disposes the image
        dropped = true;
      } else if (index < pages.length) {
        _intermediateEntries.peek(key)!.page = pages[index];
      } else {
        _intermediateEntries.evict(key);
        dropped = true;
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
    _intermediateEntries.clear();
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
    _intermediateEntries.dispose();
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

  /// The screen-pixel ratio used when the scene's embedded images were
  /// decoded. Null means the scene has no reduced image LoD to track.
  double? get imagePixelRatio {
    final entry = _entry;
    if (entry == null) throw StateError('Retained scene handle is disposed');
    return entry.imagePixelRatio;
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
    required this.imagePixelRatio,
    required this.estimatedBytes,
  });

  final PdfPage page;
  final PdfRetainedScene scene;
  final ui.Picture? picture;
  final bool fromWorker;
  final double? imagePixelRatio;
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
  _PreviewEntry(
    this.page,
    this.image, {
    required this.includesImages,
    required this.generation,
  });

  PdfPage page;
  final ui.Image image;
  final bool includesImages;
  final int generation;

  int get pixels => image.width * image.height;
  int get bytes => pixels * 4;
}

@immutable
class _IntermediatePreviewKey {
  const _IntermediatePreviewKey(this.pageIndex, this.longestSide);

  final int pageIndex;
  final double longestSide;

  @override
  bool operator ==(Object other) =>
      other is _IntermediatePreviewKey &&
      pageIndex == other.pageIndex &&
      longestSide == other.longestSide;

  @override
  int get hashCode => Object.hash(pageIndex, longestSide);
}

List<double> _normalizedIntermediateSides(
    double baseLongestSide, Iterable<double> values) {
  final sides = values
      .where((value) => value.isFinite && value > baseLongestSide)
      .toSet()
      .toList()
    ..sort();
  return sides;
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
