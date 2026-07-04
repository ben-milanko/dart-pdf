import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

import 'render_worker_stub.dart'
    if (dart.library.io) 'render_worker_isolate.dart'
    if (dart.library.js_interop) 'render_worker_web.dart';

/// On web, the URL of the compiled Web Worker script that backs the render
/// worker (its `main()` calls `runPdfRenderWorker`; see the web-only library
/// `package:dart_pdf_editor/render_worker_web.dart` and
/// `doc/render_worker_web.md` for the build wiring).
///
/// Set this once before opening a viewer to move page interpretation off the
/// main thread on web. Left null, web falls back to local rendering — exactly
/// the historical behavior — so apps that haven't built the worker script are
/// unaffected. Ignored on native, where the isolate backend needs no script.
String? pdfRenderWorkerScriptUrl;

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
/// sized to the platform — fewer on a memory-constrained device. Values below 1
/// mean 1.
int pdfRenderWorkerPoolSize = 3;

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
/// OFF the UI thread, so the dominant render cost — the content-stream parse
/// and interpreter walk — stops blocking frames while scrolling.
///
/// A worker owns a private copy of the document, opened from the same bytes on
/// its own isolate (native), and answers [record] with the page's replayable
/// [PdfRenderCommand] list, already deserialized from the wire format. The
/// caller turns that into a `ui.Picture` with
/// `PdfPageRenderer.pictureFromCommands` — a cheap replay. Image XObjects are
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
  /// Starts the platform's worker over [bytes] (the document image the page
  /// indices passed to [record] refer to). Native: a long-lived background
  /// isolate that opens its own [PdfDocument]. Web: a Web Worker over the
  /// script at [pdfRenderWorkerScriptUrl] when one is configured (else a null
  /// worker). Platforms without either: a null worker whose [record] always
  /// defers to local rendering.
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

  /// Builds the uncached backend: a single platform worker, or — when
  /// [pdfRenderWorkerPoolSize] asks for more than one — a pool of them.
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
  /// page can't be offloaded — it draws an inline image (`BI .. ID .. EI`,
  /// which can name a page-resource colour space the stream can't reach), the
  /// worker failed or was disposed, or this platform has no worker — and the
  /// caller must render the page locally.
  ///
  /// [annotations] mirrors `PdfPageRenderer.renderPicture`'s flag: when false
  /// the page's annotations are left out of the recording.
  ///
  /// [priority] orders the worker's single queue — lower is served first, so
  /// the on-screen page (0) preempts background prefetch (1) even though the
  /// isolate processes one page at a time.
  ///
  /// [imagePixelRatio] (screen pixels per page point, device pixel ratio
  /// included) caps each decoded image to display resolution before it is
  /// serialized — see `serializeCommands`'s `maxImagePixelRatio`. Pass the
  /// resolution the page will be shown at; a raster-heavy CAD sheet then ships
  /// a display-sized underlay instead of its native 100+ megapixels. Null
  /// leaves images at native resolution.
  ///
  /// [decodeImages] false records the page's vector/text but ships its images
  /// un-decoded (just their streams), or as placeholders when an image is not
  /// self-contained enough to serialize. The buffer comes back fast even on a
  /// page whose raster underlay takes seconds to decode — the fast first pass
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
  /// [priority], completing its future with null — as if the page had declined
  /// to a local render. A cheap no-op when nothing matches.
  ///
  /// In-flight preemption is handled separately: when a higher-priority
  /// [record] arrives while a lower-priority one is executing, the worker
  /// cancels the in-flight job cooperatively (via [PdfCancellationToken]) and
  /// serves the urgent request next. This method only clears the queue.
  ///
  /// The point is to cancel prefetch the user has scrolled past: a page that
  /// left the viewport before its turn came no longer needs decoding, and
  /// leaving its request queued would make the worker spend its next slot — and
  /// ship a multi-megabyte decoded buffer — for a page nobody is looking at,
  /// delaying the page that is. The caller that abandons a cancelled result
  /// must not fall back to a local interpret (the work would be wasted);
  /// [PdfPageView] does this by abandoning when it is unmounted or superseded.
  void cancel(int pageIndex, {int priority = 0});

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
/// makes the tail crawl. Spreading the work across a pool drains it ~N× faster —
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
/// detach) the buffer it is handed — sharing one buffer would leave later
/// workers with an empty document. The cost is N copies of the bytes plus N
/// decode working sets; size the pool to the platform via
/// [pdfRenderWorkerPoolSize].
///
/// Normally wrapped in a [PdfCachingRenderWorker] (see [PdfRenderWorker.start]),
/// which dedups concurrent requests for one page — so the cache, not the pool,
/// prevents the same page being decoded by its worker twice at once.
///
/// Ultra-urgent records (currently the long-jump preview, priority -2000)
/// bypass the ordinary pool through a lazily-created one-off worker. A page
/// jump should not wait behind several already-started background records that
/// cannot receive cancellation until their synchronous parse step yields.
class PdfPooledRenderWorker implements PdfRenderWorker {
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
/// re-creates it on the way back, dropping the State's cached picture — so
/// without this every scroll-back re-asks the worker to decode the page from
/// scratch (a multi-second inflate + colour-convert on a raster-heavy CAD
/// sheet, observed re-running ~7× for one page during a single scroll). A
/// page's bytes don't change under the worker (it holds a fixed snapshot), so
/// a completed buffer stays valid for the worker's whole life — caching it
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
/// new decode. This is the dominant win on a fast scroll — the render
/// scheduler re-grants the same window of pages every ~2s while the worker is
/// still chewing through the first batch (each heavy page is a multi-second
/// decode), so a completion-only cache never gets the chance to intercept; the
/// requests pile up before any finishes. Sharing the in-flight future collapses
/// those repeats into one decode per page. A scrolled-away page is cancelled
/// for every sharer at once, which is correct — none of them want it any more.
class PdfCachingRenderWorker implements PdfRenderWorker {
  PdfCachingRenderWorker(this._inner, {int budgetBytes = 96 << 20})
      : _budgetBytes = budgetBytes;

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
      final commands = await _inner.record(pageIndex,
          annotations: annotations,
          priority: priority,
          imagePixelRatio: imagePixelRatio,
          decodeImages: decodeImages,
          commandLimit: key.$5,
          imageDecodeRegion: imageDecodeRegion);
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
    // nothing — yet it would have to be re-decoded on the next revisit. On a
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
  /// such entry exists — every remaining buffer is costless, so eviction stops.
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
