import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf_cos/perf.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_graphics/raster.dart' show StripPlan, decodeStripPlan;
import 'package:web/web.dart' as web;

import 'perf_log.dart';
import 'region_replay_index.dart';
import 'render_trace.dart';
import 'render_worker.dart';

// Worker lifecycle diagnostics, routed through PdfPerfLog so they ride the same
// zero-overhead toggle as the rest of the perf trace (a single bool branch when
// disabled) - and show up in a user-captured trace when something declines.
void _wlog(String m) => PdfPerfLog.log('webworker $m');

/// How long to wait for the worker to post `'ready'` (it opens the document
/// first) before giving up and rendering every page locally. The document
/// bytes are transferred to the worker at start; on some hosts - notably a
/// dart2wasm main app driving a dart2js worker - a large transfer or open can
/// silently never complete, and with no bound the viewer would spin forever on
/// such a document while small ones (a fast transfer/open) work. Generous: a
/// healthy worker opens even a large CAD document in well under a second, so
/// this only fires when the worker is genuinely wedged.
Duration pdfRenderWorkerReadyTimeout = const Duration(seconds: 12);

/// How long to wait for a single [PdfRenderWorker.record] reply before giving up
/// on that one in-flight page. A heavy large-format CAD sheet's image decode can
/// genuinely take tens of seconds in the web worker (pure-Dart zlib inflate of a
/// multi-megapixel raster, compiled to JS/WASM), so this is generous - it exists
/// to free a wedged in-flight slot, not to police slow-but-progressing decodes.
/// A single miss drops only its own page (see [_WebRenderWorker]); the worker
/// keeps serving every other page. Only [pdfRenderWorkerTimeoutsBeforeFail]
/// consecutive misses - the signature of a genuinely dead worker - tear it down.
Duration pdfRenderWorkerRecordTimeout = const Duration(seconds: 90);

/// Consecutive record timeouts that mark the worker dead (so the viewer stops
/// round-tripping and renders locally). One slow page is not a dead worker;
/// several misses in a row with no successful reply in between is.
int pdfRenderWorkerTimeoutsBeforeFail = 3;

/// Whether web render workers may share the document bytes through
/// `SharedArrayBuffer` when the host page is cross-origin isolated.
///
/// When unavailable, disabled, or rejected by the browser, the worker falls
/// back to the older transferable `ArrayBuffer` path. This is web-only and has
/// no effect on the native isolate backend.
bool pdfRenderWorkerUseSharedArrayBuffer = true;

/// Web backend: a dedicated [web.Worker] that opens its own [PdfDocument] from
/// the bytes once and records pages on request, posting the serialized command
/// buffer back over `postMessage` (result buffers travel as transferred
/// `ArrayBuffer`s - zero-copy, not structured-cloned). On cross-origin isolated
/// pages, the document bytes are copied once into a `SharedArrayBuffer` and
/// shared by all workers instead of cloned per worker; otherwise startup falls
/// back to a transferable `ArrayBuffer`. The heavy content-stream parse and
/// interpreter walk happen entirely off the main thread, mirroring the native
/// isolate backend.
///
/// The worker runs when [pdfRenderWorkerScriptUrl] names a compiled worker
/// script (whose `main()` calls `runPdfRenderWorker`). By default this points at
/// dart_pdf_editor's bundled package asset. With a null URL - or if the
/// [web.Worker] fails to construct - this degrades to a null worker
/// ([isActive] false), so hosts can force local rendering. See
/// `doc/render_worker_web.md`.
PdfRenderWorker startRenderWorker(Uint8List bytes) {
  final url = pdfRenderWorkerScriptUrl;
  _wlog('startRenderWorker url=$url bytes=${bytes.length}');
  if (url == null) {
    _warnMainThreadRendering();
    return _WebRenderWorker.disabled();
  }
  try {
    return _WebRenderWorker(bytes, url);
  } catch (e) {
    // Worker construction can throw (bad URL, blocked by CSP): fall back.
    _wlog('construction threw: $e - falling back to local');
    return _WebRenderWorker.disabled();
  }
}

/// Whether the one-time main-thread-rendering advisory has already fired.
bool _warnedMainThreadRendering = false;

/// Warns once, in debug builds only, that web page rendering is falling back to
/// the main thread because no render-worker script is configured
/// ([pdfRenderWorkerScriptUrl] is null) - the silent performance cliff an app
/// hits after upgrading if it never opted into the worker asset. Points at the
/// one-line fix.
///
/// The whole body runs inside an `assert`, so release and profile builds strip
/// it and stay silent; it is emitted once per session to avoid spamming the
/// console on every document open. A host that deliberately forces main-thread
/// rendering can ignore it.
void _warnMainThreadRendering() {
  assert(() {
    if (_warnedMainThreadRendering) return true;
    _warnedMainThreadRendering = true;
    developer.log(
      'Web page rendering is running on the MAIN THREAD: no render-worker '
      'script is configured (pdfRenderWorkerScriptUrl is null), so scrolling '
      'and page decode will jank on large documents. For off-main-thread '
      'rendering, depend on the dart_pdf_editor_assets package and call '
      'registerBundledEditorAssets() once at startup, or set '
      'pdfRenderWorkerScriptUrl to your own compiled worker URL. (Debug-only '
      'notice, shown once; ignore it if main-thread rendering is intentional.)',
      name: 'dart_pdf_editor.render_worker',
      level: 900, // WARNING
    );
    return true;
  }());
}

/// Pre-booted Web Workers waiting for their first `init`. The expensive part of
/// web worker startup is fetching + compiling the ~1 MB dart2js worker script
/// and booting its runtime (#450: ~1.45 s on a phone), and none of it depends on
/// the document. Constructing the Web Worker at app boot lets that happen while
/// the user is still choosing a file; the real worker then adopts a pre-booted
/// instance and only posts `init` (the document hand-off, a few tens of ms). The
/// worker is silent until it receives `init`, so nothing is lost before adoption.
final _prewarmedWorkers = <web.Worker>[];

/// Constructs up to [count] Web Workers now (fetch + compile + boot the worker
/// script) so a later [startRenderWorker] adopts a pre-booted one instead of
/// paying the full startup on the critical path. Tops the pool up to [count]
/// rather than doubling it, so repeated calls are safe. No-op when no worker
/// script is configured ([pdfRenderWorkerScriptUrl] null) or construction throws
/// (bad URL / CSP) - the normal path then just constructs on demand as before.
void prewarmRenderWorkers(int count) {
  final url = pdfRenderWorkerScriptUrl;
  if (url == null) return;
  while (_prewarmedWorkers.length < count) {
    try {
      final worker = web.Worker(url.toJS);
      // Swallow a boot-time error rather than leave it unhandled; the adopter
      // installs the real handler, and its ready-watchdog falls back to local
      // if a broken worker never opens the document.
      worker.onerror = ((web.Event _) {}).toJS;
      _prewarmedWorkers.add(worker);
      _wlog('prewarmed worker ${_prewarmedWorkers.length}/$count from $url');
    } catch (e) {
      _wlog('prewarm construction threw: $e - skipping');
      return;
    }
  }
}

/// Terminates any prewarmed workers not yet adopted (host teardown, or a host
/// opting out of worker rendering after prewarming). Adopted workers are owned
/// by their [_WebRenderWorker] and unaffected.
void disposePrewarmedRenderWorkers() {
  for (final worker in _prewarmedWorkers) {
    worker.terminate();
  }
  _prewarmedWorkers.clear();
}

class _WebRenderWorker extends PdfRenderWorker {
  _WebRenderWorker(Uint8List bytes, String scriptUrl) {
    // Adopt a pre-booted worker (its fetch/compile/boot already overlapped the
    // file pick) when one is available, else construct on demand as before.
    final worker = _prewarmedWorkers.isNotEmpty
        ? _prewarmedWorkers.removeAt(0)
        : web.Worker(scriptUrl.toJS);
    _worker = worker;
    worker.onmessage = ((web.MessageEvent event) => _onMessage(event)).toJS;
    // A worker-level error (script failed to load/parse) is terminal: behave
    // like the null worker so every record resolves to a local render.
    worker.onerror = ((web.Event e) {
      _wlog('onerror: ${e.type} - worker script failed; falling back to local');
      _fail();
    }).toJS;
    _wlog('worker constructed from $scriptUrl');

    final init = JSObject()..setProperty('kind'.toJS, 'init'.toJS);
    init.setProperty('timings'.toJS, (_perfClock != null).toJS);
    init.setProperty(
      'reuseTranscripts'.toJS,
      pdfRenderWorkerReuseTranscripts.toJS,
    );
    final sharedBuffer = _sharedDocumentBuffer(bytes);
    if (sharedBuffer != null) {
      init
        ..setProperty('bytes'.toJS, sharedBuffer)
        ..setProperty('shared'.toJS, true.toJS);
      worker.postMessage(init);
      _wlog('init posted via SharedArrayBuffer bytes=${bytes.length}');
    } else {
      // Transfer the whole document to the worker once at start (copy first so
      // the transferred buffer is exactly the document, not a view into a
      // larger backing store the caller still holds).
      final jsBuffer = Uint8List.fromList(bytes).buffer.toJS;
      init
        ..setProperty('bytes'.toJS, jsBuffer)
        ..setProperty('shared'.toJS, false.toJS);
      worker.postMessage(init, <JSAny>[jsBuffer].toJS);
      _wlog('init posted via transferred ArrayBuffer bytes=${bytes.length}');
    }

    // Watchdog: if the worker never reports 'ready' (e.g. the transferred
    // document never arrived/opened on this host), give up and render locally
    // rather than spin forever. Cancelled the moment 'ready' lands.
    _readyWatchdog = Timer(pdfRenderWorkerReadyTimeout, () {
      if (_ready || _disposed || _failed) return;
      _wlog(
        'ready watchdog fired after ${pdfRenderWorkerReadyTimeout.inSeconds}'
        's - worker never opened the document; falling back to local',
      );
      _fail();
    });
  }

  _WebRenderWorker.disabled() : _failed = true;

  static int _nextWorkerNumber = 0;

  final int _workerNumber = _nextWorkerNumber++;
  final Stopwatch? _perfClock = PdfPerfLog.enabled
      ? (Stopwatch()..start())
      : null;

  web.Worker? _worker;
  final _queue = <_WebPending>[];
  _WebPending? _inFlight;
  int _nextId = 0;
  int _seq = 0;
  bool _disposed = false;
  bool _failed = false;
  // The worker posts 'ready' once it has opened the document; records sent
  // before then would race the open, so they queue until it lands.
  bool _ready = false;
  // Watchdogs that bound how long we wait on a silent worker before degrading
  // to local rendering: one for the initial 'ready', one for each in-flight
  // record's reply. See pdfRenderWorkerReadyTimeout / pdfRenderWorkerRecordTimeout.
  Timer? _readyWatchdog;
  Timer? _recordWatchdog;
  // Consecutive record watchdog misses with no reply in between. A healthy
  // worker chewing through one heavy page resets this the moment any reply
  // lands; only a run of misses ([pdfRenderWorkerTimeoutsBeforeFail]) condemns
  // the worker as dead.
  int _consecutiveTimeouts = 0;

  @override
  bool get isActive => !_disposed && !_failed;

  PdfRenderTrace? _lastRenderTrace;

  @override
  PdfRenderTrace? get lastRenderTrace => _lastRenderTrace;

  void _onMessage(web.MessageEvent event) {
    final data = event.data as JSObject?;
    if (data == null) return;
    final kind = (data.getProperty('kind'.toJS) as JSString?)?.toDart;
    if (kind == 'ready') {
      final shared =
          (data.getProperty('shared'.toJS) as JSBoolean?)?.toDart ?? false;
      final openUs = (data.getProperty('openUs'.toJS) as JSNumber?)?.toDartInt;
      final browserImageDecode =
          (data.getProperty('browserImageDecode'.toJS) as JSBoolean?)?.toDart;
      final browserImageDecodeMissing =
          (data.getProperty('browserImageDecodeMissing'.toJS) as JSString?)
              ?.toDart;
      final startupUs = _perfClock?.elapsedMicroseconds;
      _wlog(
        'ready worker=$_workerNumber '
        '(worker opened the document, sharedBytes=$shared)'
        '${browserImageDecode == null ? '' : ' browserImageDecode=$browserImageDecode'}'
        '${browserImageDecodeMissing == null ? '' : ' missing=$browserImageDecodeMissing'}'
        '${startupUs == null ? '' : ' startup=${_traceMs(startupUs)}'}'
        '${openUs == null ? '' : ' open=${_traceMs(openUs)}'}',
      );
      _readyWatchdog?.cancel();
      _readyWatchdog = null;
      _ready = true;
      _pump();
      return;
    }
    if (kind == 'cancelIgnored') {
      final target =
          (data.getProperty('targetId'.toJS) as JSNumber?)?.toDartInt;
      final active =
          (data.getProperty('activeId'.toJS) as JSNumber?)?.toDartInt;
      _wlog('ignored stale cancel target=$target active=$active');
      return;
    }
    if (kind != 'result') return;
    final id = (data.getProperty('id'.toJS) as JSNumber).toDartInt;
    final request = _inFlight;
    if (request == null || request.id != id) return; // stale (disposed)
    _inFlight = null;
    _recordWatchdog?.cancel();
    _recordWatchdog = null;
    _consecutiveTimeouts = 0; // a reply landed: the worker is alive
    request.trace?.receive(data, _perfClock!.elapsedMicroseconds);
    final buffer = data.getProperty('buffer'.toJS) as JSArrayBuffer?;
    final planBuffer = data.getProperty('planBuffer'.toJS) as JSArrayBuffer?;
    final buffers = buffer == null
        ? null
        : <Uint8List>[
            buffer.toDart.asUint8List(),
            if (planBuffer != null) planBuffer.toDart.asUint8List(),
          ];
    final byteLength = buffers?.fold<int>(
      0,
      (sum, bytes) => sum + bytes.length,
    );
    final err = (data.getProperty('error'.toJS) as JSString?)?.toDart;
    _wlog(
      'result kind=${request.kind.name} page=${request.pageIndex} '
      '${buffers == null ? 'declined (null) → local' : '${byteLength}B → worker'}'
      '${err == null ? '' : '\n  worker error: $err'}',
    );
    if (buffers == null &&
        request.kind == _WebRequestKind.record &&
        request.requeueAfterPreemption &&
        !_disposed) {
      request
        ..requeueAfterPreemption = false
        ..id = -1;
      _queue.add(request);
      _wlog('requeued preempted shared record page=${request.pageIndex}');
      _pump();
      return;
    }
    request.completer.complete(buffers);
    _pump();
  }

  @override
  Future<List<PdfRenderCommand>?> record(
    int pageIndex, {
    bool annotations = true,
    int priority = 0,
    double? imagePixelRatio,
    bool decodeImages = true,
    int? commandLimit,
    PdfRect? imageDecodeRegion,
  }) async {
    if (_disposed || _failed) {
      _wlog(
        'record page=$pageIndex skipped (disposed=$_disposed '
        'failed=$_failed) → local',
      );
      return null;
    }
    final request = _WebPending.record(
      priority,
      _seq++,
      pageIndex,
      annotations,
      imagePixelRatio,
      decodeImages,
      commandLimit,
      imageDecodeRegion,
    );
    _trace(request);
    _queue.add(request);
    _pump();
    final buffers = await request.completer.future;
    if (buffers == null || buffers.length != 1) {
      request.trace?.log(_workerNumber, request, outcome: 'declined');
      return null;
    }
    try {
      final deserializeClock = request.trace == null
          ? null
          : (Stopwatch()..start());
      final commands = deserializeCommands(buffers.single);
      if (deserializeClock != null) {
        deserializeClock.stop();
        request.trace!.deserializeUs = deserializeClock.elapsedMicroseconds;
      }
      request.trace?.log(_workerNumber, request, outcome: 'ok');
      _recordTrace(request);
      return commands;
    } catch (_) {
      request.trace?.log(_workerNumber, request, outcome: 'corrupt');
      return null; // corrupt buffer → render locally rather than crash
    }
  }

  @override
  Future<StripPlan?> binStrips(
    int pageIndex, {
    required bool annotations,
    required List<double> pageToDevice,
    required int deviceWidth,
    required int deviceHeight,
    required double pixelRatio,
    bool slugGlyphs = false,
    int priority = 0,
  }) async {
    if (_disposed || _failed || pageToDevice.length != 6) return null;
    final request = _WebPending.bin(
      priority,
      _seq++,
      pageIndex,
      annotations,
      List<double>.of(pageToDevice),
      deviceWidth,
      deviceHeight,
      pixelRatio,
      slugGlyphs,
    );
    _trace(request);
    _queue.add(request);
    _pump();
    final buffers = await request.completer.future;
    if (buffers == null || buffers.length != 1) {
      request.trace?.log(_workerNumber, request, outcome: 'declined');
      return null;
    }
    try {
      final deserializeClock = request.trace == null
          ? null
          : (Stopwatch()..start());
      final plan = decodeStripPlan(buffers.single);
      if (deserializeClock != null) {
        deserializeClock.stop();
        request.trace!.deserializeUs = deserializeClock.elapsedMicroseconds;
      }
      request.trace?.log(_workerNumber, request, outcome: 'ok');
      _recordTrace(request);
      return plan;
    } catch (_) {
      request.trace?.log(_workerNumber, request, outcome: 'corrupt');
      return null;
    }
  }

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
  }) async {
    if (_disposed ||
        _failed ||
        pageToDevice.length != 6 ||
        deviceWidth <= 0 ||
        deviceHeight <= 0) {
      return null;
    }
    final request = _WebPending.detail(
      priority,
      _seq++,
      pageIndex,
      annotations,
      List<double>.of(pageToDevice),
      deviceWidth,
      deviceHeight,
      pixelRatio,
      imageDecodeRegion,
    );
    _trace(request);
    _queue.add(request);
    _pump();
    final buffers = await request.completer.future;
    if (buffers == null || buffers.length != 2) {
      request.trace?.log(_workerNumber, request, outcome: 'declined');
      return null;
    }
    try {
      final deserializeClock = request.trace == null
          ? null
          : (Stopwatch()..start());
      final detail = PdfStripDetail(
        deserializeCommands(buffers[0]),
        decodeStripPlan(buffers[1]),
      );
      if (deserializeClock != null) {
        deserializeClock.stop();
        request.trace!.deserializeUs = deserializeClock.elapsedMicroseconds;
      }
      request.trace?.log(_workerNumber, request, outcome: 'ok');
      _recordTrace(request);
      return detail;
    } catch (_) {
      request.trace?.log(_workerNumber, request, outcome: 'corrupt');
      return null;
    }
  }

  @override
  Future<PdfRegionReplayIndex?> buildRegionIndex(
    int pageIndex, {
    required bool annotations,
    required int maxCommands,
    required bool buildGrid,
    int priority = 0,
  }) async {
    if (_disposed || _failed) return null;
    final request = _WebPending.regionIndex(
      priority,
      _seq++,
      pageIndex,
      annotations,
      maxCommands,
      buildGrid,
    );
    _trace(request);
    _queue.add(request);
    _pump();
    final buffers = await request.completer.future;
    if (buffers == null || buffers.length != 1) return null;
    try {
      return deserializeRegionReplayIndex(buffers.single);
    } catch (_) {
      return null; // corrupt buffer → build in-isolate rather than crash
    }
  }

  @override
  Future<PdfPageText?> extractText(int pageIndex, {int priority = 0}) async {
    if (_disposed || _failed) return null;
    final request = _WebPending.extractText(priority, _seq++, pageIndex);
    _trace(request);
    _queue.add(request);
    _pump();
    final buffers = await request.completer.future;
    if (buffers == null || buffers.length != 1) return null;
    try {
      return deserializePageText(buffers.single);
    } catch (_) {
      return null; // corrupt buffer → extract in-isolate rather than crash
    }
  }

  void _trace(_WebPending request) {
    final clock = _perfClock;
    if (clock == null) return;
    request.trace = _WebRequestTrace(clock.elapsedMicroseconds);
  }

  /// Snapshots the just-completed request's trace onto [lastRenderTrace] so a
  /// caller can read the end-to-end per-phase breakdown of the last job through
  /// one worker call (in addition to the string line [_WebRequestTrace.log]
  /// prints to the perf console).
  void _recordTrace(_WebPending request) {
    final trace = request.trace;
    if (trace != null) _lastRenderTrace = trace.toRenderTrace(request.pageIndex);
  }

  /// Sends the highest-priority queued request to the worker when it is idle
  /// and ready. Lower [priority] wins; ties break by submission order, so a
  /// freshly-requested visible page (priority 0) preempts pending prefetch -
  /// the same one-in-flight reordering the isolate backend uses.
  ///
  /// When a higher-priority request is queued while a lower-priority one is
  /// in flight, the in-flight job is cancelled via a `{kind:'cancel'}`
  /// message so the worker abandons it mid-walk and serves the urgent request
  /// next.
  void _pump() {
    if (_disposed || !_ready || _queue.isEmpty) return;
    final worker = _worker;
    if (worker == null) return;

    if (_inFlight != null) {
      var bestQueued = 0;
      for (var i = 1; i < _queue.length; i++) {
        final a = _queue[i], b = _queue[bestQueued];
        if (a.priority < b.priority ||
            (a.priority == b.priority && a.seq < b.seq)) {
          bestQueued = i;
        }
      }
      if (_queue[bestQueued].priority < _inFlight!.priority) {
        if (_inFlight!.kind == _WebRequestKind.record) {
          _inFlight!.requeueAfterPreemption = true;
        }
        worker.postMessage(
          JSObject()
            ..setProperty('kind'.toJS, 'cancel'.toJS)
            ..setProperty('id'.toJS, _inFlight!.id.toJS),
        );
      }
      return;
    }

    var best = 0;
    for (var i = 1; i < _queue.length; i++) {
      final a = _queue[i], b = _queue[best];
      if (a.priority < b.priority ||
          (a.priority == b.priority && a.seq < b.seq)) {
        best = i;
      }
    }
    final request = _queue.removeAt(best)..id = _nextId++;
    _inFlight = request;
    final clock = _perfClock;
    if (clock != null) request.trace?.sentUs = clock.elapsedMicroseconds;
    final message = JSObject()
      ..setProperty('kind'.toJS, request.kind.name.toJS)
      ..setProperty('id'.toJS, request.id.toJS)
      ..setProperty('page'.toJS, request.pageIndex.toJS)
      ..setProperty('annotations'.toJS, request.annotations.toJS);
    if (request.kind == _WebRequestKind.record) {
      message.setProperty('decodeImages'.toJS, request.decodeImages.toJS);
      final ratio = request.imagePixelRatio;
      if (ratio != null) message.setProperty('imageRatio'.toJS, ratio.toJS);
      final limit = request.commandLimit;
      if (limit != null) message.setProperty('commandLimit'.toJS, limit.toJS);
      final region = request.imageDecodeRegion;
      if (region != null) {
        message
          ..setProperty('regionLeft'.toJS, region.left.toJS)
          ..setProperty('regionBottom'.toJS, region.bottom.toJS)
          ..setProperty('regionRight'.toJS, region.right.toJS)
          ..setProperty('regionTop'.toJS, region.top.toJS);
      }
    } else if (request.kind == _WebRequestKind.bin ||
        request.kind == _WebRequestKind.detail) {
      final matrix = request.pageToDevice!;
      for (var i = 0; i < 6; i++) {
        message.setProperty('m$i'.toJS, matrix[i].toJS);
      }
      message
        ..setProperty('deviceWidth'.toJS, request.deviceWidth.toJS)
        ..setProperty('deviceHeight'.toJS, request.deviceHeight.toJS)
        ..setProperty('pixelRatio'.toJS, request.binPixelRatio.toJS)
        ..setProperty('slugGlyphs'.toJS, request.slugGlyphs.toJS);
      if (request.kind == _WebRequestKind.detail) {
        final region = request.imageDecodeRegion!;
        message
          ..setProperty('regionLeft'.toJS, region.left.toJS)
          ..setProperty('regionBottom'.toJS, region.bottom.toJS)
          ..setProperty('regionRight'.toJS, region.right.toJS)
          ..setProperty('regionTop'.toJS, region.top.toJS);
      }
    }
    if (request.kind == _WebRequestKind.regionIndex) {
      message
        ..setProperty('maxCommands'.toJS, request.regionMaxCommands.toJS)
        ..setProperty('buildGrid'.toJS, request.regionBuildGrid.toJS);
    }
    worker.postMessage(message);

    // Watchdog: a record that never comes back wedges the single in-flight slot
    // (and so every queued page) forever. Bound it - but a miss frees only THIS
    // page (the worker keeps serving the rest), because a heavy sheet that is
    // merely slow is not a dead worker. Killing the whole worker on one slow
    // page is what dumped the entire document onto the UI thread. Only a run of
    // misses with no reply in between condemns the worker.
    _recordWatchdog?.cancel();
    final inFlightId = request.id;
    _recordWatchdog = Timer(pdfRenderWorkerRecordTimeout, () {
      if (_disposed || _failed) return;
      if (_inFlight?.id != inFlightId) return; // already answered
      _inFlight = null;
      _recordWatchdog = null;
      _consecutiveTimeouts++;
      if (_consecutiveTimeouts >= pdfRenderWorkerTimeoutsBeforeFail) {
        _wlog(
          'record watchdog: page=${request.pageIndex} timed out after '
          '${pdfRenderWorkerRecordTimeout.inSeconds}s - '
          '$_consecutiveTimeouts misses in a row; worker is dead, '
          'falling back to local for all pages',
        );
        _fail();
        return;
      }
      _wlog(
        'record watchdog: page=${request.pageIndex} timed out after '
        '${pdfRenderWorkerRecordTimeout.inSeconds}s - dropping this page to '
        'local; worker stays up ($_consecutiveTimeouts/'
        '$pdfRenderWorkerTimeoutsBeforeFail before giving up)',
      );
      if (!request.completer.isCompleted) request.completer.complete(null);
      _pump(); // serve the next queued page
    });
  }

  @override
  void cancel(int pageIndex, {int priority = 0}) {
    if (_disposed || _failed) return;
    // Drop matching QUEUED requests so the worker's next slot serves a page
    // the user is still looking at. The cancelled record() futures resolve
    // null; the abandoning caller ignores them. In-flight preemption is
    // handled by _pump when a higher-priority request arrives.
    var dropped = 0;
    _queue.removeWhere((request) {
      if (request.kind != _WebRequestKind.record ||
          request.pageIndex != pageIndex ||
          request.priority != priority) {
        return false;
      }
      if (!request.completer.isCompleted) request.completer.complete(null);
      dropped++;
      return true;
    });
    if (dropped > 0) {
      _wlog(
        'cancel page=$pageIndex priority=$priority dropped=$dropped queued',
      );
    }
  }

  @override
  void cancelBinStrips(int pageIndex, {int priority = 0}) {
    if (_disposed || _failed) return;
    _queue.removeWhere((request) {
      if ((request.kind != _WebRequestKind.bin &&
              request.kind != _WebRequestKind.detail) ||
          request.pageIndex != pageIndex ||
          request.priority != priority) {
        return false;
      }
      if (!request.completer.isCompleted) request.completer.complete(null);
      return true;
    });
    final inFlight = _inFlight;
    if (inFlight != null &&
        (inFlight.kind == _WebRequestKind.bin ||
            inFlight.kind == _WebRequestKind.detail) &&
        inFlight.pageIndex == pageIndex &&
        inFlight.priority == priority) {
      _worker?.postMessage(
        JSObject()
          ..setProperty('kind'.toJS, 'cancel'.toJS)
          ..setProperty('id'.toJS, inFlight.id.toJS),
      );
    }
  }

  void _fail() {
    if (_failed) return;
    _failed = true;
    _cancelWatchdogs();
    _failPending();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancelWatchdogs();
    _worker?.terminate();
    _worker = null;
    _failPending();
  }

  void _cancelWatchdogs() {
    _readyWatchdog?.cancel();
    _readyWatchdog = null;
    _recordWatchdog?.cancel();
    _recordWatchdog = null;
  }

  /// Resolves every in-flight and queued request to null (local render) - on
  /// dispose, or when the worker errors out.
  void _failPending() {
    final orphaned = [if (_inFlight != null) _inFlight!, ..._queue];
    _inFlight = null;
    _queue.clear();
    for (final request in orphaned) {
      if (!request.completer.isCompleted) request.completer.complete(null);
    }
  }
}

enum _WebRequestKind { record, bin, detail, regionIndex, extractText }

/// One queued record or strip-bin request (mirrors the isolate backend's
/// `_PendingRequest`).
class _WebPending {
  _WebPending.record(
    this.priority,
    this.seq,
    this.pageIndex,
    this.annotations,
    this.imagePixelRatio,
    this.decodeImages,
    this.commandLimit,
    this.imageDecodeRegion,
  ) : kind = _WebRequestKind.record,
      pageToDevice = null,
      deviceWidth = 0,
      deviceHeight = 0,
      binPixelRatio = 0,
      slugGlyphs = false,
      regionMaxCommands = 0,
      regionBuildGrid = false;

  _WebPending.bin(
    this.priority,
    this.seq,
    this.pageIndex,
    this.annotations,
    this.pageToDevice,
    this.deviceWidth,
    this.deviceHeight,
    this.binPixelRatio,
    this.slugGlyphs,
  ) : kind = _WebRequestKind.bin,
      imagePixelRatio = null,
      decodeImages = false,
      commandLimit = null,
      imageDecodeRegion = null,
      regionMaxCommands = 0,
      regionBuildGrid = false;

  _WebPending.detail(
    this.priority,
    this.seq,
    this.pageIndex,
    this.annotations,
    this.pageToDevice,
    this.deviceWidth,
    this.deviceHeight,
    this.binPixelRatio,
    this.imageDecodeRegion,
  ) : kind = _WebRequestKind.detail,
      imagePixelRatio = null,
      decodeImages = true,
      commandLimit = null,
      slugGlyphs = false,
      regionMaxCommands = 0,
      regionBuildGrid = false;

  _WebPending.regionIndex(
    this.priority,
    this.seq,
    this.pageIndex,
    this.annotations,
    this.regionMaxCommands,
    this.regionBuildGrid,
  ) : kind = _WebRequestKind.regionIndex,
      imagePixelRatio = null,
      decodeImages = false,
      commandLimit = null,
      imageDecodeRegion = null,
      pageToDevice = null,
      deviceWidth = 0,
      deviceHeight = 0,
      binPixelRatio = 0,
      slugGlyphs = false;

  _WebPending.extractText(this.priority, this.seq, this.pageIndex)
      : kind = _WebRequestKind.extractText,
        annotations = false,
        imagePixelRatio = null,
        decodeImages = false,
        commandLimit = null,
        imageDecodeRegion = null,
        pageToDevice = null,
        deviceWidth = 0,
        deviceHeight = 0,
        binPixelRatio = 0,
        slugGlyphs = false,
        regionMaxCommands = 0,
        regionBuildGrid = false;

  final _WebRequestKind kind;
  final int priority;
  final int seq;
  final int pageIndex;
  final bool annotations;
  final double? imagePixelRatio;
  final bool decodeImages;
  final int? commandLimit;
  final PdfRect? imageDecodeRegion;
  final List<double>? pageToDevice;
  final int deviceWidth;
  final int deviceHeight;
  final double binPixelRatio;
  final bool slugGlyphs;
  final int regionMaxCommands;
  final bool regionBuildGrid;
  final completer = Completer<List<Uint8List>?>();
  bool requeueAfterPreemption = false;
  int id = -1;
  _WebRequestTrace? trace;
}

class _WebRequestTrace {
  _WebRequestTrace(this.queuedUs);

  final int queuedUs;
  int sentUs = 0;
  int receivedUs = 0;
  int workerUs = 0;
  int parseUs = 0;
  int interpretUs = 0;
  int streamUs = 0;
  int serializeUs = 0;
  int decodeUs = 0;
  int binUs = 0;
  int deserializeUs = 0;
  bool transcriptHit = false;
  String? cosStatsJson;
  String? imageDecodeSummary;

  void receive(JSObject data, int nowUs) {
    receivedUs = nowUs;
    workerUs = _intProperty(data, 'workerUs');
    parseUs = _intProperty(data, 'parseUs');
    interpretUs = _intProperty(data, 'interpretUs');
    streamUs = _intProperty(data, 'streamUs');
    serializeUs = _intProperty(data, 'serializeUs');
    decodeUs = _intProperty(data, 'decodeUs');
    binUs = _intProperty(data, 'binUs');
    transcriptHit =
        (data.getProperty('transcriptHit'.toJS) as JSBoolean?)?.toDart ?? false;
    cosStatsJson = (data.getProperty('cosStats'.toJS) as JSString?)?.toDart;
    imageDecodeSummary =
        (data.getProperty('imageDecode'.toJS) as JSString?)?.toDart;
  }

  /// Assembles this request's collected halves into one unified [PdfRenderTrace]
  /// - the worker phases it reported plus the queue/transfer/deserialize the
  /// main isolate measured.
  PdfRenderTrace toRenderTrace(int pageIndex) {
    final roundTripUs = receivedUs > 0 && sentUs > 0 ? receivedUs - sentUs : 0;
    return PdfRenderTrace(pageIndex: pageIndex)
      ..queueUs = sentUs > 0 ? sentUs - queuedUs : 0
      ..workerUs = workerUs
      ..parseUs = parseUs
      ..interpretUs = interpretUs
      ..streamUs = streamUs
      ..serializeUs = serializeUs
      ..decodeUs = decodeUs
      ..binUs = binUs
      ..transferUs = math.max(0, roundTripUs - workerUs)
      ..deserializeUs = deserializeUs
      ..transcriptHit = transcriptHit
      ..imageDecodeSummary = imageDecodeSummary
      ..cosStats = cosStatsJson == null
          ? null
          : PdfPerfStats.fromJson(
              jsonDecode(cosStatsJson!) as Map<String, Object?>);
  }

  void log(int workerNumber, _WebPending request, {required String outcome}) {
    final queueUs = sentUs > 0 ? sentUs - queuedUs : 0;
    final roundTripUs = receivedUs > 0 && sentUs > 0 ? receivedUs - sentUs : 0;
    final transferUs = math.max(0, roundTripUs - workerUs);
    final totalUs = receivedUs > 0 ? receivedUs - queuedUs + deserializeUs : 0;
    _wlog(
      'phase worker=$workerNumber kind=${request.kind.name} '
      'page=${request.pageIndex} outcome=$outcome '
      'queue=${_traceMs(queueUs)} worker=${_traceMs(workerUs)} '
      'parse=${_traceMs(parseUs)} interpret=${_traceMs(interpretUs)} '
      'stream=${_traceMs(streamUs)} '
      'decode=${_traceMs(decodeUs)} serialize=${_traceMs(serializeUs)} '
      'bin=${_traceMs(binUs)} transfer=${_traceMs(transferUs)} '
      'deserialize=${_traceMs(deserializeUs)} total=${_traceMs(totalUs)} '
      'transcript=${transcriptHit ? 'hit' : 'miss'}'
      '${imageDecodeSummary == null ? '' : ' imageDecode=$imageDecodeSummary'}',
    );
  }
}

int _intProperty(JSObject object, String name) =>
    (object.getProperty(name.toJS) as JSNumber?)?.toDartInt ?? 0;

String _traceMs(int microseconds) =>
    '${(microseconds / 1000).toStringAsFixed(1)}ms';

JSObject? _sharedDocumentBuffer(Uint8List bytes) {
  if (!_canUseSharedDocumentBytes) return null;
  try {
    final buffer = _constructJsObject('SharedArrayBuffer', bytes.length.toJS);
    final view = _constructJsObject('Uint8Array', buffer) as JSUint8Array;
    view.toDart.setAll(0, bytes);
    return buffer;
  } catch (e) {
    _wlog('SharedArrayBuffer unavailable at runtime: $e');
    return null;
  }
}

bool get _canUseSharedDocumentBytes {
  if (!pdfRenderWorkerUseSharedArrayBuffer) return false;
  if (!globalContext.has('SharedArrayBuffer')) return false;
  return (globalContext['crossOriginIsolated'] as JSBoolean?)?.toDart ?? false;
}

JSObject _constructJsObject(String constructorName, JSAny arg) {
  final constructor = globalContext[constructorName] as JSFunction?;
  if (constructor == null) {
    throw StateError('$constructorName is not available');
  }
  return constructor.callAsConstructor<JSObject>(arg);
}
