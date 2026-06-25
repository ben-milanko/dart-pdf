import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf_graphics/pdf_graphics.dart';

import 'perf_log.dart';
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

/// How many [PdfRenderWorker]s the reader/editor spin up as a
/// [PdfRenderWorkerPool] for a multi-page document, so pages interpret in
/// parallel (most visibly: a page grid of a heavy document fills up to this
/// many times faster). 1 keeps the historical single-worker behavior.
///
/// Each worker holds its own copy of the document, so this trades memory for
/// throughput — a few is plenty. Small documents fall back to a single worker
/// regardless (the parallelism has nothing to spread). Tune it once at
/// launch, like [pdfRenderWorkerScriptUrl].
int pdfRenderWorkerPoolSize = 3;

/// Documents with at least this many pages use a [PdfRenderWorkerPool]
/// ([pdfRenderWorkerPoolSize] workers); shorter ones use a single worker,
/// where spinning up extra workers would cost more (startup, memory) than the
/// parallelism saves.
const int pdfRenderWorkerPoolMinPages = 12;

/// Starts the right worker for a [pageCount]-page document: a
/// [PdfRenderWorkerPool] when the document is long enough and the pool size is
/// above 1, otherwise a single [PdfRenderWorker].
PdfRenderWorker startPdfRenderWorker(Uint8List bytes, {required int pageCount}) {
  if (pdfRenderWorkerPoolSize > 1 && pageCount >= pdfRenderWorkerPoolMinPages) {
    return PdfRenderWorkerPool(bytes, size: pdfRenderWorkerPoolSize);
  }
  return PdfRenderWorker.start(bytes);
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
  static PdfRenderWorker start(Uint8List bytes) => startRenderWorker(bytes);

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
  Future<List<PdfRenderCommand>?> record(int pageIndex,
      {bool annotations = true, int priority = 0});

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

/// Fans page interpretation out across several [PdfRenderWorker]s running in
/// parallel, so independent pages (a grid of thumbnails, a fast scroll
/// through a heavy document) interpret concurrently instead of queueing
/// behind one worker.
///
/// The dominant render cost is the content-stream walk, and a single worker
/// does them strictly one at a time — so a page of thumbnails of a heavy CAD
/// document fills only as fast as that one worker can churn. A pool of
/// [size] workers cuts that wall by up to [size]×: each [record] is routed to
/// the least-busy worker, so up to [size] pages are interpreting at once.
///
/// Itself a [PdfRenderWorker], so it drops in wherever one is expected with
/// no caller changes. Each worker opens its own copy of the document from the
/// same bytes, so memory scales with [size] — keep it modest (a few), and on
/// web especially, where each worker is a separate script instance holding
/// its own copy of the file.
class PdfRenderWorkerPool implements PdfRenderWorker {
  PdfRenderWorkerPool(Uint8List bytes, {int size = 3})
      : _workers = [
          for (var i = 0; i < math.max(1, size); i++)
            PdfRenderWorker.start(bytes)
        ],
        _inflight = List<int>.filled(math.max(1, size), 0) {
    PdfPerfLog.log('worker pool started size=${_workers.length}');
  }

  final List<PdfRenderWorker> _workers;

  /// In-flight [record] count per worker, so the next request goes to the
  /// least-loaded one — keeps every worker busy when there's work to spread.
  final List<int> _inflight;

  /// The active worker with the fewest in-flight requests, or -1 when none is
  /// active (the caller then renders locally, exactly as for a single worker).
  int _pick() {
    var best = -1;
    var bestLoad = 1 << 30;
    for (var i = 0; i < _workers.length; i++) {
      if (!_workers[i].isActive) continue;
      if (_inflight[i] < bestLoad) {
        bestLoad = _inflight[i];
        best = i;
      }
    }
    return best;
  }

  @override
  Future<List<PdfRenderCommand>?> record(int pageIndex,
      {bool annotations = true, int priority = 0}) {
    final i = _pick();
    if (i < 0) return Future<List<PdfRenderCommand>?>.value(null);
    _inflight[i]++;
    return _workers[i]
        .record(pageIndex, annotations: annotations, priority: priority)
        .whenComplete(() => _inflight[i]--);
  }

  @override
  void cancel(int pageIndex, {int priority = 0}) {
    // a queued request lives on exactly one worker, but we don't track which —
    // clearing it from all is a cheap no-op on the rest
    for (final worker in _workers) {
      worker.cancel(pageIndex, priority: priority);
    }
  }

  @override
  bool get isActive => _workers.any((worker) => worker.isActive);

  @override
  void dispose() {
    for (final worker in _workers) {
      worker.dispose();
    }
  }
}
