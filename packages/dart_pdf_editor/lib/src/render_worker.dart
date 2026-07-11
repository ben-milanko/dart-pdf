import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_graphics/raster.dart' show StripPlan;

import 'render_worker_stub.dart'
    if (dart.library.io) 'render_worker_isolate.dart'
    if (dart.library.js_interop) 'render_worker_web.dart';

/// The package-asset URL of dart_pdf_editor's bundled Web Worker script.
///
/// Flutter serves package assets under `assets/packages/<package>/...`, so a
/// Flutter web app that depends on this package can use the worker without
/// copying a script into its own `web/` directory.
const String defaultPdfRenderWorkerScriptUrl =
    'assets/packages/dart_pdf_editor/assets/web/pdf_render_worker.dart.js';

/// On web, the URL of the compiled Web Worker script that backs the render
/// worker (its `main()` calls `runPdfRenderWorker`; see the web-only library
/// `package:dart_pdf_editor/render_worker_web.dart` and
/// `doc/render_worker_web.md` for the build wiring).
///
/// The default points at dart_pdf_editor's bundled package asset, so apps get
/// off-main-thread rendering on web without startup configuration. Set this to
/// another URL before opening a viewer to self-host/cache-bust a custom worker,
/// or set it to null to force local main-thread rendering. Ignored on native,
/// where the isolate backend needs no script.
String? pdfRenderWorkerScriptUrl = defaultPdfRenderWorkerScriptUrl;

/// Default number of platform workers [PdfRenderWorker.start] fans page
/// records across.
const int defaultPdfRenderWorkerPoolSize = 3;

/// How many platform workers [PdfRenderWorker.start] fans page records across.
///
/// One worker decodes pages strictly serially: a raster-heavy CAD document
/// whose every sheet is a multi-second image decode fills in one page at a
/// time, so the tail of a scrolled-through document takes a long time to finish
/// warming even though each page is already off the UI thread. A pool of N
/// workers decodes up to N pages at once. The pool routes new pages to the
/// least-loaded active worker and remembers the route while the request is
/// outstanding, so [PdfRenderWorker.cancel] still reaches the right queue.
///
/// The cost is memory: each worker opens its own copy of the document, so the
/// pool holds N copies of the bytes plus N decode working sets. Default 3 gives
/// long documents enough parallelism for viewport-ordered thumbnails without
/// flooding the machine. The host can set this once before opening a viewer,
/// sized to the platform - fewer on a memory-constrained device. Values below 1
/// mean 1.
int pdfRenderWorkerPoolSize = defaultPdfRenderWorkerPoolSize;

/// Default decoded-image command-buffer cache budget for one render worker.
const int defaultPdfRenderWorkerCacheBudgetBytes = 96 << 20;

/// Decoded-image command-buffer cache budget for each render worker.
///
/// Completed worker records keep decoded image pixels so recycled page widgets
/// and thumbnails can revisit recently-rendered pages without paying another
/// decode. The bytes are bounded by this LRU budget. Hosts running on memory-
/// constrained devices can lower it once at startup before opening viewers.
int pdfRenderWorkerCacheBudgetBytes = defaultPdfRenderWorkerCacheBudgetBytes;

/// How long the caching worker waits for one backend record before giving up on
/// that worker snapshot.
///
/// The page view falls back to local rendering when a worker returns null. A
/// wedged native isolate used to leave the worker future pending forever, which
/// also pinned the cache's in-flight entry and kept progressive vector-first
/// rasters on screen indefinitely. Web has its own backend watchdog; this common
/// guard covers native and pooled workers.
Duration pdfRenderWorkerRecordTimeout = const Duration(seconds: 90);

/// One combined deep-zoom worker result.
///
/// [commands] carry images decoded for the requested visible region and
/// [plan] was binned from those exact commands and device geometry. The pair
/// must be consumed together; using the plan with another command recording
/// may trip the strip device's stale-plan guard.
class PdfStripDetail {
  const PdfStripDetail(this.commands, this.plan);

  final List<PdfRenderCommand> commands;
  final StripPlan plan;
}

/// Documents with at least this many pages use a [PdfPooledRenderWorker] via
/// [startPdfRenderWorker]; shorter ones use a single worker because extra
/// startup and memory usually cost more than the parallelism saves.
const int pdfRenderWorkerPoolMinPages = 12;

/// Starts the right cached worker for a [pageCount]-page document: a pooled
/// backend when the document is long enough and [pdfRenderWorkerPoolSize] asks
/// for parallelism, otherwise a single platform worker.
PdfRenderWorker startPdfRenderWorker(Uint8List bytes,
    {required int pageCount}) {
  final backend =
      pdfRenderWorkerPoolSize > 1 && pageCount >= pdfRenderWorkerPoolMinPages
          ? PdfPooledRenderWorker(bytes, pdfRenderWorkerPoolSize)
          : startRenderWorker(bytes);
  return PdfCachingRenderWorker(backend);
}

/// Records a PDF page's interpreter callbacks into a portable command buffer
/// OFF the UI thread, so the dominant render cost - the content-stream parse
/// and interpreter walk - stops blocking frames while scrolling.
///
/// A worker owns a private copy of the document, opened from the same bytes on
/// its own isolate (native), and answers [record] with the page's replayable
/// [PdfRenderCommand] list, already deserialized from the wire format. The
/// caller turns that into a `ui.Picture` with
/// `PdfPageRenderer.pictureFromCommands` - a cheap replay. Image XObjects are
/// serialized into the buffer, and the worker decodes them off-thread too
/// (the premultiplied pixels ride on each command), so the main thread runs
/// only the engine codec, never the pure-Dart inflate/colour-convert. Images
/// that need the platform JPEG codec ship un-decoded and decode locally.
///
/// The worker's document is a fixed snapshot of the bytes it was started with.
/// It is therefore only correct for a document whose pages don't change under
/// it: the read-only reader, or an editor between edits. Callers driving an
/// editing session must dispose and restart the worker when the document's
/// bytes change (or simply not use one).
abstract class PdfRenderWorker {
  const PdfRenderWorker();

  /// Starts the platform's worker over [bytes] (the document image the page
  /// indices passed to [record] refer to). Native: a long-lived background
  /// isolate that opens its own [PdfDocument]. Web: a Web Worker over the
  /// script at [pdfRenderWorkerScriptUrl] when one is configured (by default
  /// the bundled package asset, else a null worker). Platforms without either:
  /// a null worker whose [record] always defers to local rendering.
  ///
  /// With [pdfRenderWorkerPoolSize] > 1 the backend is a [PdfPooledRenderWorker]
  /// that fans page records across that many platform workers, so a raster-heavy
  /// document warms ~N× faster (see that class). Default 3 enables a small
  /// pool; set it to 1 for the historical single-worker path.
  ///
  /// The backend is wrapped in a [PdfCachingRenderWorker] so a page the lazy
  /// list recycles and rebuilds is served from cache instead of being re-decoded
  /// from scratch (see that class), and concurrent requests for one page share a
  /// single decode. The cache wraps the whole pool, so it is shared across every
  /// worker and is fresh for each document.
  static PdfRenderWorker start(Uint8List bytes) =>
      PdfCachingRenderWorker(_backend(bytes));

  /// Builds the uncached backend: a single platform worker, or - when
  /// [pdfRenderWorkerPoolSize] asks for more than one - a pool of them.
  static PdfRenderWorker _backend(Uint8List bytes) =>
      pdfRenderWorkerPoolSize > 1
          ? PdfPooledRenderWorker(bytes, pdfRenderWorkerPoolSize)
          : startRenderWorker(bytes);

  /// The raw platform worker, NOT wrapped in [PdfCachingRenderWorker]. Test-
  /// only: for exercising the inner queue/cancel/priority contract, which the
  /// cache is designed to short-circuit (a cached page never re-enters the
  /// queue). Production code uses [start]. (No `@visibleForTesting` annotation
  /// because this library stays Flutter-free so the web worker can compile via
  /// `dart compile js` without pulling in Flutter.)
  static PdfRenderWorker startUncached(Uint8List bytes) =>
      startRenderWorker(bytes);

  /// Records page [pageIndex] off-thread and returns its replayable command
  /// buffer (image XObjects decoded off-thread and attached), or null when the
  /// page can't be offloaded - it draws an inline image (`BI .. ID .. EI`,
  /// which can name a page-resource colour space the stream can't reach), the
  /// worker failed or was disposed, or this platform has no worker - and the
  /// caller must render the page locally.
  ///
  /// [annotations] mirrors `PdfPageRenderer.renderPicture`'s flag: when false
  /// the page's annotations are left out of the recording.
  ///
  /// [priority] orders the worker's single queue - lower is served first, so
  /// the on-screen page (0) preempts background prefetch (1) even though the
  /// isolate processes one page at a time.
  ///
  /// [imagePixelRatio] (screen pixels per page point, device pixel ratio
  /// included) caps each decoded image to display resolution before it is
  /// serialized - see `serializeCommands`'s `maxImagePixelRatio`. Pass the
  /// resolution the page will be shown at; a raster-heavy CAD sheet then ships
  /// a display-sized underlay instead of its native 100+ megapixels. Null
  /// leaves images at native resolution.
  ///
  /// [decodeImages] false records the page's vector/text but ships its images
  /// un-decoded (just their streams), or as placeholders when an image is not
  /// self-contained enough to serialize. The buffer comes back fast even on a
  /// page whose raster underlay takes seconds to decode - the fast first pass
  /// of progressive rendering. The caller replays it with
  /// `PdfPageRenderer.pictureFromCommands(includeImages: false)` to paint the
  /// linework immediately, then records again with [decodeImages] true for the
  /// images. Default true (decode in the worker, the normal full render).
  ///
  /// [imageDecodeRegion] is a PDF page-space rectangle for a transient
  /// deep-zoom/detail render. When set with [decodeImages] true, the worker
  /// may decode only the intersecting source pixels of axis-aligned image
  /// draws and retarget their transforms to that crop. Full-page cached
  /// renders must leave this null; a region-specific buffer is only correct
  /// for rasterizing that same visible slice.
  Future<List<PdfRenderCommand>?> record(int pageIndex,
      {bool annotations = true,
      int priority = 0,
      double? imagePixelRatio,
      bool decodeImages = true,
      int? commandLimit,
      PdfRect? imageDecodeRegion});

  /// Drops any QUEUED (not yet started) [record] request for [pageIndex] at
  /// [priority], completing its future with null - as if the page had declined
  /// to a local render. A cheap no-op when nothing matches.
  ///
  /// In-flight preemption is handled separately: when a higher-priority
  /// [record] arrives while a lower-priority one is executing, the worker
  /// cancels the in-flight job cooperatively (via [PdfCancellationToken]) and
  /// serves the urgent request next. This method only clears the queue.
  ///
  /// The point is to cancel prefetch the user has scrolled past: a page that
  /// left the viewport before its turn came no longer needs decoding, and
  /// leaving its request queued would make the worker spend its next slot - and
  /// ship a multi-megabyte decoded buffer - for a page nobody is looking at,
  /// delaying the page that is. The caller that abandons a cancelled result
  /// must not fall back to a local interpret (the work would be wasted);
  /// [PdfPageView] does this by abandoning when it is unmounted or superseded.
  void cancel(int pageIndex, {int priority = 0});

  /// Bins page [pageIndex]'s sparse strips off-thread for the exact device
  /// geometry a strip-routed zoom settle is about to rasterize, returning a
  /// [StripPlan] the caller feeds to `StripPdfDevice(precomputed:)` (via
  /// `PdfRetainedScene.rasterizeStrips(stripPlan:)`), or null when the page
  /// can't be binned off-thread - the platform has no worker, the worker
  /// failed/was disposed/was cancelled, or the page declines - and the
  /// caller bins locally.
  ///
  /// [pageToDevice] is the six coefficients (a, b, c, d, e, f) of the
  /// page-space -> device-pixel [PdfMatrix] the consuming device will be
  /// constructed with (the scene's own zoom/region transform); they round-
  /// trip bit-exactly, so the device's stale-plan guard can compare them
  /// with `==`. [deviceWidth]/[deviceHeight] are the strip viewport in
  /// pixels and [pixelRatio] the ratio baked into the matrix.
  ///
  /// [annotations] must match the recording the caller's retained scene was
  /// built from - the worker re-records the page in its own isolate
  /// (interpretation is deterministic, so the command list matches the
  /// scene's) and replays it through a headless strip binner.
  ///
  /// [priority] shares [record]'s queue ordering; the default 0 is the
  /// on-screen page - a zoom settle IS the visible page, so it preempts
  /// background prefetch exactly like a visible record.
  ///
  /// The base implementation declines (null): platforms and wrappers that
  /// don't offload strip binning - the stub and the web worker today -
  /// inherit it.
  Future<StripPlan?> binStrips(
    int pageIndex, {
    required bool annotations,
    required List<double> pageToDevice,
    required int deviceWidth,
    required int deviceHeight,
    required double pixelRatio,
    int priority = 0,
  }) async =>
      null;

  /// Records a region-detail command buffer and bins that exact buffer for a
  /// strip-routed deep-zoom patch in one worker job.
  ///
  /// A separate [record] followed by [binStrips] pays two queue/transfer
  /// round trips and, because one platform worker serves jobs serially, the
  /// two waits stack. This combined request decodes images for
  /// [imageDecodeRegion] at [pixelRatio], bins the resulting commands for the
  /// supplied device geometry, and returns both together. Replaying
  /// [PdfStripDetail.commands] with [PdfStripDetail.plan] therefore preserves
  /// painter order while giving the detail patch region-resolution images.
  ///
  /// The base implementation declines. Native workers override it; other
  /// backends keep the existing base-scene strip fallback until they support
  /// the combined protocol.
  Future<PdfStripDetail?> recordStripDetail(
    int pageIndex, {
    required bool annotations,
    required List<double> pageToDevice,
    required int deviceWidth,
    required int deviceHeight,
    required double pixelRatio,
    required PdfRect imageDecodeRegion,
    int priority = 0,
  }) async =>
      null;

  /// Drops any QUEUED (not yet started) [binStrips] request for [pageIndex]
  /// at [priority], completing its future with null - and, on the native
  /// isolate backend, also preempts a matching IN-FLIGHT bin cooperatively
  /// so the worker abandons the stale geometry mid-walk (its future resolves
  /// null too). Superseded settles and overtaken speculative bins call this
  /// so the worker bins the geometry the user is actually looking at instead
  /// of a stale one; the abandoning caller must not fall back to a local bin
  /// for the superseded settle (PdfPageView's generation guard takes care of
  /// that). Unlike [cancel], the in-flight preemption is safe here because
  /// strip plans are never shared between callers (the caching wrapper
  /// passes bins straight through).
  void cancelBinStrips(int pageIndex, {int priority = 0}) {}

  /// Whether this worker actually offloads. False for the null fallback, so
  /// callers can skip the round-trip and render locally without asking.
  bool get isActive;

  /// Tears the worker down (kills the isolate, fails pending requests with
  /// null). Idempotent.
  void dispose();
}

/// Fans [record] calls across a fixed set of platform workers so up to N pages
/// decode at once instead of one at a time. A single worker serializes every
/// page; on a document whose sheets are each a multi-second image decode that
/// makes the tail crawl. Spreading the work across a pool drains it ~N× faster -
/// the visible burst on load and the background prefetch alike.
///
/// New records are dispatched to the least-loaded active worker, where load is
/// the number of queued or in-flight records this pool has handed that worker.
/// A static `page % N` mapping is used only as the tie-break/fallback, so a
/// cluster of heavy pages that would all hash to one worker can spill onto idle
/// siblings. While a `(page, priority)` record is outstanding, later records for
/// the same pair reuse its worker; [cancel] routes through that lease table so
/// it still reaches the worker holding the queued request.
///
/// Each worker opens its own copy of the document. The bytes are copied per
/// worker ([Uint8List.fromList]) because a platform worker may transfer (and so
/// detach) the buffer it is handed - sharing one buffer would leave later
/// workers with an empty document. The cost is N copies of the bytes plus N
/// decode working sets; size the pool to the platform via
/// [pdfRenderWorkerPoolSize].
///
/// Normally wrapped in a [PdfCachingRenderWorker] (see [PdfRenderWorker.start]),
/// which dedups concurrent requests for one page - so the cache, not the pool,
/// prevents the same page being decoded by its worker twice at once.
///
/// Ultra-urgent records (currently the long-jump preview, priority -2000)
/// bypass the ordinary pool through a lazily-created one-off worker. A page
/// jump should not wait behind several already-started background records that
/// cannot receive cancellation until their synchronous parse step yields.
class PdfPooledRenderWorker extends PdfRenderWorker {
  /// Starts [size] platform workers over copies of [bytes]. [size] is clamped to
  /// at least 1; a pool of 1 is just a single worker with this routing wrapper.
  PdfPooledRenderWorker(Uint8List bytes, int size)
      : _urgentBytes = Uint8List.fromList(bytes),
        _workers = List.generate(
          size < 1 ? 1 : size,
          (_) => startRenderWorker(Uint8List.fromList(bytes)),
          growable: false,
        ) {
    _loads = List.filled(_workers.length, 0);
  }

  /// Test seam: a pool over already-constructed [workers], so the routing and
  /// teardown can be exercised with fakes instead of real platform workers.
  PdfPooledRenderWorker.fromWorkers(List<PdfRenderWorker> workers)
      : assert(workers.isNotEmpty),
        _urgentBytes = null,
        _workers = List.of(workers, growable: false) {
    _loads = List.filled(_workers.length, 0);
  }

  static const int _urgentPriority = -2000;

  final Uint8List? _urgentBytes;
  final List<PdfRenderWorker> _workers;
  late final List<int> _loads;
  final _routes = <(int, int), _PoolRoute>{};
  PdfRenderWorker? _urgentWorker;

  /// The static mapping used for a tie/fallback. Negative indices (none are
  /// expected) map through [int.abs] so routing never throws.
  int _staticWorkerIndex(int pageIndex) => pageIndex.abs() % _workers.length;

  int _leastLoadedWorker(int pageIndex) {
    if (_workers.length == 1) return 0;
    final anyActive = _workers.any((worker) => worker.isActive);
    final fallback = _staticWorkerIndex(pageIndex);

    var best = -1;
    var bestLoad = 1 << 62;
    for (var i = 0; i < _workers.length; i++) {
      if (anyActive && !_workers[i].isActive) continue;
      final load = _loads[i];
      if (load < bestLoad) {
        best = i;
        bestLoad = load;
      }
    }
    if (best < 0) return fallback;

    // When the preferred static worker is tied for least-loaded, keep using it.
    // That preserves the old distribution in balanced cases while still spilling
    // away from a hot modulo class.
    if ((!anyActive || _workers[fallback].isActive) &&
        _loads[fallback] == bestLoad) {
      return fallback;
    }
    return best;
  }

  int _lease(int pageIndex, int priority) {
    final key = (pageIndex, priority);
    final existing = _routes[key];
    final worker = existing?.worker ?? _leastLoadedWorker(pageIndex);
    _loads[worker]++;
    if (existing != null) {
      existing.count++;
    } else {
      _routes[key] = _PoolRoute(worker);
    }
    return worker;
  }

  void _release(int pageIndex, int priority, int worker) {
    if (_loads[worker] > 0) _loads[worker]--;
    final key = (pageIndex, priority);
    final route = _routes[key];
    if (route == null || route.worker != worker) return;
    route.count--;
    if (route.count <= 0) _routes.remove(key);
  }

  PdfRenderWorker _cancelWorkerFor(int pageIndex, int priority) {
    final route = _routes[(pageIndex, priority)];
    if (route != null) return _workers[route.worker];
    return _workers[_staticWorkerIndex(pageIndex)];
  }

  /// The pool can offload while any worker is still alive; a worker that dies
  /// (e.g. its watchdog gave up) only takes its own share of pages down to local
  /// rendering, the rest keep offloading.
  @override
  bool get isActive =>
      _workers.any((w) => w.isActive) || (_urgentWorker?.isActive ?? false);

  @override
  Future<List<PdfRenderCommand>?> record(int pageIndex,
      {bool annotations = true,
      int priority = 0,
      double? imagePixelRatio,
      bool decodeImages = true,
      int? commandLimit,
      PdfRect? imageDecodeRegion}) async {
    final urgent = _urgentWorkerFor(priority);
    if (urgent != null) {
      return urgent.record(pageIndex,
          annotations: annotations,
          priority: priority,
          imagePixelRatio: imagePixelRatio,
          decodeImages: decodeImages,
          commandLimit: commandLimit,
          imageDecodeRegion: imageDecodeRegion);
    }
    final worker = _lease(pageIndex, priority);
    try {
      return await _workers[worker].record(pageIndex,
          annotations: annotations,
          priority: priority,
          imagePixelRatio: imagePixelRatio,
          decodeImages: decodeImages,
          commandLimit: commandLimit,
          imageDecodeRegion: imageDecodeRegion);
    } finally {
      _release(pageIndex, priority, worker);
    }
  }

  @override
  void cancel(int pageIndex, {int priority = 0}) {
    final urgent = _urgentWorkerFor(priority, start: false);
    if (urgent != null) {
      urgent.cancel(pageIndex, priority: priority);
      return;
    }
    _cancelWorkerFor(pageIndex, priority).cancel(pageIndex, priority: priority);
  }

  /// Strip binning routes by the STATIC page index, not the least-loaded
  /// worker: each worker keeps a small per-isolate command cache (plus the
  /// process-global glyph/shape strip caches) warm for the pages it has
  /// binned, and a zoom session hammers ONE page with a fresh geometry per
  /// settle - stable affinity turns every settle after the first into a
  /// command-cache hit, while least-loaded routing would scatter the
  /// settles across workers and re-record the page on each of them.
  @override
  Future<StripPlan?> binStrips(
    int pageIndex, {
    required bool annotations,
    required List<double> pageToDevice,
    required int deviceWidth,
    required int deviceHeight,
    required double pixelRatio,
    int priority = 0,
  }) =>
      _workers[_staticWorkerIndex(pageIndex)].binStrips(
        pageIndex,
        annotations: annotations,
        pageToDevice: pageToDevice,
        deviceWidth: deviceWidth,
        deviceHeight: deviceHeight,
        pixelRatio: pixelRatio,
        priority: priority,
      );

  @override
  Future<PdfStripDetail?> recordStripDetail(
    int pageIndex, {
    required bool annotations,
    required List<double> pageToDevice,
    required int deviceWidth,
    required int deviceHeight,
    required double pixelRatio,
    required PdfRect imageDecodeRegion,
    int priority = 0,
  }) =>
      _workers[_staticWorkerIndex(pageIndex)].recordStripDetail(
        pageIndex,
        annotations: annotations,
        pageToDevice: pageToDevice,
        deviceWidth: deviceWidth,
        deviceHeight: deviceHeight,
        pixelRatio: pixelRatio,
        imageDecodeRegion: imageDecodeRegion,
        priority: priority,
      );

  @override
  void cancelBinStrips(int pageIndex, {int priority = 0}) =>
      _workers[_staticWorkerIndex(pageIndex)]
          .cancelBinStrips(pageIndex, priority: priority);

  @override
  void dispose() {
    _routes.clear();
    for (var i = 0; i < _loads.length; i++) {
      _loads[i] = 0;
    }
    for (final worker in _workers) {
      worker.dispose();
    }
    _urgentWorker?.dispose();
    _urgentWorker = null;
  }

  PdfRenderWorker? _urgentWorkerFor(int priority, {bool start = true}) {
    if (priority > _urgentPriority) return null;
    final existing = _urgentWorker;
    if (existing != null) {
      if (existing.isActive) return existing;
      existing.dispose();
      _urgentWorker = null;
    }
    final bytes = _urgentBytes;
    if (!start || bytes == null) return null;
    return _urgentWorker = startRenderWorker(Uint8List.fromList(bytes));
  }
}

class _PoolRoute {
  _PoolRoute(this.worker);

  final int worker;
  int count = 1;
}

typedef _RecordCacheKey = (int, bool, bool, int, int?, _RegionBucket?);

/// Wraps a [PdfRenderWorker] with an LRU cache of completed [record] results,
/// keyed by (page, annotations, decodeImages, image-ratio bucket,
/// command-limit, image-decode-region when decoded image bytes are present).
/// The lazy
/// page list recycles a [PdfPageView]'s State when it scrolls out of view and
/// re-creates it on the way back, dropping the State's cached picture - so
/// without this every scroll-back re-asks the worker to decode the page from
/// scratch (a multi-second inflate + colour-convert on a raster-heavy CAD
/// sheet, observed re-running ~7× for one page during a single scroll). A
/// page's bytes don't change under the worker (it holds a fixed snapshot), so
/// a completed buffer stays valid for the worker's whole life - caching it
/// makes a revisit a map lookup instead of a re-decode. The cache lives on the
/// worker, so it is shared across every recycled page widget and dies with the
/// worker (a new document opens a new worker, hence a fresh cache).
///
/// Bounded by total decoded image bytes ([budgetBytes]); the least-recently
/// used entries evict first. A single buffer larger than the whole budget (a
/// huge large-format sheet) is not cached at all rather than evicting
/// everything else for one page.
///
/// In-flight requests are also deduplicated: a second record for a key whose
/// decode is still running shares that pending future instead of starting a
/// new decode. This is the dominant win on a fast scroll - the render
/// scheduler re-grants the same window of pages every ~2s while the worker is
/// still chewing through the first batch (each heavy page is a multi-second
/// decode), so a completion-only cache never gets the chance to intercept; the
/// requests pile up before any finishes. Sharing the in-flight future collapses
/// those repeats into one decode per page. A scrolled-away page is cancelled
/// for every sharer at once, which is correct - none of them want it any more.
class PdfCachingRenderWorker extends PdfRenderWorker {
  PdfCachingRenderWorker(this._inner, {int? budgetBytes})
      : _budgetBytes = budgetBytes ?? pdfRenderWorkerCacheBudgetBytes;

  final PdfRenderWorker _inner;
  final int _budgetBytes;

  // LinkedHashMap iteration order doubles as LRU order: a hit re-inserts to
  // the end, eviction takes the oldest (first) key.
  final _cache = <_RecordCacheKey, _CachedRecord>{};
  // Keys whose decode is running now, so concurrent requests share one decode.
  final _inflight = <_RecordCacheKey, Future<List<PdfRenderCommand>?>>{};
  int _bytes = 0;

  @override
  bool get isActive => _inner.isActive;

  /// Decoded image bytes currently retained by completed cached records.
  ///
  /// This is intentionally the same weight used for eviction, not a full heap
  /// estimate. It gives callers a cheap signal for whether speculative warming
  /// is likely to evict useful full-image records before they are reused.
  int get cachedBytes => _bytes;

  /// Maximum decoded image bytes this cache tries to retain.
  int get cacheBudgetBytes => _budgetBytes;

  /// Fraction of [cacheBudgetBytes] currently occupied by decoded image data.
  double get cachePressure {
    if (_budgetBytes <= 0) return 1;
    return (_bytes / _budgetBytes).clamp(0.0, 1.0).toDouble();
  }

  @override
  Future<List<PdfRenderCommand>?> record(int pageIndex,
      {bool annotations = true,
      int priority = 0,
      double? imagePixelRatio,
      bool decodeImages = true,
      int? commandLimit,
      PdfRect? imageDecodeRegion}) {
    if (!_inner.isActive) {
      return _inner.record(pageIndex,
          annotations: annotations,
          priority: priority,
          imagePixelRatio: imagePixelRatio,
          decodeImages: decodeImages,
          commandLimit: commandLimit,
          imageDecodeRegion: imageDecodeRegion);
    }
    final effectiveCommandLimit = decodeImages ? null : commandLimit;
    final effectiveRegion = decodeImages ? imageDecodeRegion : null;
    final key = (
      pageIndex,
      annotations,
      decodeImages,
      _ratioBucket(imagePixelRatio),
      effectiveCommandLimit,
      _regionBucket(effectiveRegion),
    );
    final hit = _takeCached(key);
    if (hit != null) {
      return Future.value(hit.commands);
    }
    if (key.$6 != null) {
      final reusable = _takeCachedWeightless(_withoutRegion(key));
      if (reusable != null) return Future.value(reusable.commands);
    }
    final pending = _inflight[key];
    if (pending != null) return pending; // a decode for this key is running
    final future = _recordAndStore(key, pageIndex,
        annotations: annotations,
        priority: priority,
        imagePixelRatio: imagePixelRatio,
        decodeImages: decodeImages,
        imageDecodeRegion: effectiveRegion);
    _inflight[key] = future;
    return future;
  }

  Future<List<PdfRenderCommand>?> _recordAndStore(
      _RecordCacheKey key, int pageIndex,
      {required bool annotations,
      required int priority,
      required double? imagePixelRatio,
      required bool decodeImages,
      required PdfRect? imageDecodeRegion}) async {
    try {
      final timeout = pdfRenderWorkerRecordTimeout;
      final commands = await _inner
          .record(pageIndex,
              annotations: annotations,
              priority: priority,
              imagePixelRatio: imagePixelRatio,
              decodeImages: decodeImages,
              commandLimit: key.$5,
              imageDecodeRegion: imageDecodeRegion)
          .timeout(timeout, onTimeout: () {
        _inner.cancel(pageIndex, priority: priority);
        _inner.dispose();
        return null;
      });
      if (commands != null) {
        final weight = _weigh(commands);
        final storeKey =
            key.$6 != null && weight == 0 ? _withoutRegion(key) : key;
        _store(storeKey, commands, weight);
      }
      return commands;
    } finally {
      _inflight.remove(key);
    }
  }

  @override
  void cancel(int pageIndex, {int priority = 0}) =>
      _inner.cancel(pageIndex, priority: priority);

  /// Pure passthrough - strip plans are never cached. A plan is only valid
  /// for the exact zoom/region matrix it was binned for, and every settle
  /// carries a fresh one, so a cache entry could never be re-used (and a
  /// CAD-sheet plan is tens of MB the LRU would evict real records for).
  @override
  Future<StripPlan?> binStrips(
    int pageIndex, {
    required bool annotations,
    required List<double> pageToDevice,
    required int deviceWidth,
    required int deviceHeight,
    required double pixelRatio,
    int priority = 0,
  }) =>
      _inner.binStrips(
        pageIndex,
        annotations: annotations,
        pageToDevice: pageToDevice,
        deviceWidth: deviceWidth,
        deviceHeight: deviceHeight,
        pixelRatio: pixelRatio,
        priority: priority,
      );

  /// Pure passthrough: region details are transient and geometry-specific,
  /// like strip plans, so retaining them in the full-page record LRU would
  /// evict reusable page buffers for data that cannot be reused.
  @override
  Future<PdfStripDetail?> recordStripDetail(
    int pageIndex, {
    required bool annotations,
    required List<double> pageToDevice,
    required int deviceWidth,
    required int deviceHeight,
    required double pixelRatio,
    required PdfRect imageDecodeRegion,
    int priority = 0,
  }) =>
      _inner.recordStripDetail(
        pageIndex,
        annotations: annotations,
        pageToDevice: pageToDevice,
        deviceWidth: deviceWidth,
        deviceHeight: deviceHeight,
        pixelRatio: pixelRatio,
        imageDecodeRegion: imageDecodeRegion,
        priority: priority,
      );

  @override
  void cancelBinStrips(int pageIndex, {int priority = 0}) =>
      _inner.cancelBinStrips(pageIndex, priority: priority);

  @override
  void dispose() {
    _cache.clear();
    _inflight.clear();
    _bytes = 0;
    _inner.dispose();
  }

  _CachedRecord? _takeCached(_RecordCacheKey key) {
    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit; // re-insert: now most-recently used
    }
    return hit;
  }

  _CachedRecord? _takeCachedWeightless(_RecordCacheKey key) {
    final hit = _cache[key];
    if (hit == null || hit.weight != 0) return null;
    _cache.remove(key);
    _cache[key] = hit; // re-insert: now most-recently used
    return hit;
  }

  void _store(
      _RecordCacheKey key, List<PdfRenderCommand> commands, int weight) {
    if (weight > _budgetBytes) return; // one page bigger than the cache itself
    final previous = _cache.remove(key);
    if (previous != null) _bytes -= previous.weight;
    _cache[key] = _CachedRecord(commands, weight);
    _bytes += weight;
    // Evict the least-recently-used entries that actually hold bytes until
    // under budget. The budget bounds DECODED image memory, so evicting a
    // weight-0 buffer (a vector-first pass or an image-free page) frees
    // nothing - yet it would have to be re-decoded on the next revisit. On a
    // heavy CAD sheet the full-image buffers (tens of MB each) are exactly
    // what blows the budget while the cheap vector-first buffers are the ones
    // re-requested every scroll settle, so a blind oldest-first eviction
    // discarded the very entries the cache exists to keep. Skip the costless
    // ones and never evict the entry we just inserted.
    while (_bytes > _budgetBytes) {
      final victim = _oldestHeavyKey(except: key);
      if (victim == null) break; // nothing left worth evicting
      _bytes -= _cache.remove(victim)!.weight;
    }
  }

  /// The least-recently-used key whose buffer holds decoded bytes (weight > 0),
  /// other than [except] (the entry just inserted, which we keep). Null when no
  /// such entry exists - every remaining buffer is costless, so eviction stops.
  _RecordCacheKey? _oldestHeavyKey({required _RecordCacheKey except}) {
    for (final entry in _cache.entries) {
      if (entry.value.weight > 0 && entry.key != except) return entry.key;
    }
    return null;
  }

  /// Quantises the image-pixel ratio so tiny per-frame jitter (a 1px layout
  /// wobble) still hits the cache, while a real zoom step lands in a new
  /// bucket. Null (vector-first pass, no decode) gets its own bucket.
  static int _ratioBucket(double? ratio) =>
      ratio == null ? -1 : (ratio * 8).round();

  static _RegionBucket? _regionBucket(PdfRect? region) =>
      region == null ? null : _RegionBucket(region);

  static _RecordCacheKey _withoutRegion(_RecordCacheKey key) =>
      (key.$1, key.$2, key.$3, key.$4, key.$5, null);

  /// A buffer's weight ≈ its decoded image bytes (premultiplied RGBA), which
  /// dominate; command objects themselves are negligible. Recurses soft-mask
  /// groups, matching what the worker actually decoded.
  static int _weigh(List<PdfRenderCommand> commands) {
    var bytes = 0;
    void walk(List<PdfRenderCommand> cmds) {
      for (final c in cmds) {
        if (c is PdfDrawImageCommand) {
          final d = c.request.decoded;
          if (d != null) bytes += d.width * d.height * 4;
        } else if (c is PdfEndSoftMaskedCommand) {
          walk(c.maskCommands);
        }
      }
    }

    walk(commands);
    return bytes;
  }
}

class _CachedRecord {
  _CachedRecord(this.commands, this.weight);
  final List<PdfRenderCommand> commands;
  final int weight;
}

class _RegionBucket {
  _RegionBucket(PdfRect region)
      : left = _bucket(region.left),
        bottom = _bucket(region.bottom),
        right = _bucket(region.right),
        top = _bucket(region.top);

  final int left;
  final int bottom;
  final int right;
  final int top;

  static int _bucket(double value) => (value * 4).round();

  @override
  bool operator ==(Object other) =>
      other is _RegionBucket &&
      other.left == left &&
      other.bottom == bottom &&
      other.right == right &&
      other.top == top;

  @override
  int get hashCode => Object.hash(left, bottom, right, top);
}
