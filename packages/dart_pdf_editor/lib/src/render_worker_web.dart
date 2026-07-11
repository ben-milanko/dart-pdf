import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_graphics/raster.dart' show StripPlan, decodeStripPlan;
import 'package:web/web.dart' as web;

import 'perf_log.dart';
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
  if (url == null) return _WebRenderWorker.disabled();
  try {
    return _WebRenderWorker(bytes, url);
  } catch (e) {
    // Worker construction can throw (bad URL, blocked by CSP): fall back.
    _wlog('construction threw: $e - falling back to local');
    return _WebRenderWorker.disabled();
  }
}

class _WebRenderWorker extends PdfRenderWorker {
  _WebRenderWorker(Uint8List bytes, String scriptUrl) {
    final worker = web.Worker(scriptUrl.toJS);
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
          's - worker never opened the document; falling back to local');
      _fail();
    });
  }

  _WebRenderWorker.disabled() : _failed = true;

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

  void _onMessage(web.MessageEvent event) {
    final data = event.data as JSObject?;
    if (data == null) return;
    final kind = (data.getProperty('kind'.toJS) as JSString?)?.toDart;
    if (kind == 'ready') {
      final shared =
          (data.getProperty('shared'.toJS) as JSBoolean?)?.toDart ?? false;
      _wlog('ready (worker opened the document, sharedBytes=$shared)');
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
    final buffer = data.getProperty('buffer'.toJS) as JSArrayBuffer?;
    final bytes = buffer?.toDart.asUint8List();
    final err = (data.getProperty('error'.toJS) as JSString?)?.toDart;
    _wlog('result kind=${request.kind.name} page=${request.pageIndex} '
        '${bytes == null ? 'declined (null) → local' : '${bytes.length}B → worker'}'
        '${err == null ? '' : '\n  worker error: $err'}');
    if (bytes == null &&
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
    request.completer.complete(bytes);
    _pump();
  }

  @override
  Future<List<PdfRenderCommand>?> record(int pageIndex,
      {bool annotations = true,
      int priority = 0,
      double? imagePixelRatio,
      bool decodeImages = true,
      int? commandLimit,
      PdfRect? imageDecodeRegion}) async {
    if (_disposed || _failed) {
      _wlog('record page=$pageIndex skipped (disposed=$_disposed '
          'failed=$_failed) → local');
      return null;
    }
    final request = _WebPending.record(priority, _seq++, pageIndex, annotations,
        imagePixelRatio, decodeImages, commandLimit, imageDecodeRegion);
    _queue.add(request);
    _pump();
    final bytes = await request.completer.future;
    if (bytes == null) return null;
    try {
      return deserializeCommands(bytes);
    } catch (_) {
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
    );
    _queue.add(request);
    _pump();
    final bytes = await request.completer.future;
    if (bytes == null) return null;
    try {
      return decodeStripPlan(bytes);
    } catch (_) {
      return null;
    }
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
        worker.postMessage(JSObject()
          ..setProperty('kind'.toJS, 'cancel'.toJS)
          ..setProperty('id'.toJS, _inFlight!.id.toJS));
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
    } else {
      final matrix = request.pageToDevice!;
      for (var i = 0; i < 6; i++) {
        message.setProperty('m$i'.toJS, matrix[i].toJS);
      }
      message
        ..setProperty('deviceWidth'.toJS, request.deviceWidth.toJS)
        ..setProperty('deviceHeight'.toJS, request.deviceHeight.toJS)
        ..setProperty('pixelRatio'.toJS, request.binPixelRatio.toJS);
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
        _wlog('record watchdog: page=${request.pageIndex} timed out after '
            '${pdfRenderWorkerRecordTimeout.inSeconds}s - '
            '$_consecutiveTimeouts misses in a row; worker is dead, '
            'falling back to local for all pages');
        _fail();
        return;
      }
      _wlog('record watchdog: page=${request.pageIndex} timed out after '
          '${pdfRenderWorkerRecordTimeout.inSeconds}s - dropping this page to '
          'local; worker stays up ($_consecutiveTimeouts/'
          '$pdfRenderWorkerTimeoutsBeforeFail before giving up)');
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
          'cancel page=$pageIndex priority=$priority dropped=$dropped queued');
    }
  }

  @override
  void cancelBinStrips(int pageIndex, {int priority = 0}) {
    if (_disposed || _failed) return;
    _queue.removeWhere((request) {
      if (request.kind != _WebRequestKind.bin ||
          request.pageIndex != pageIndex ||
          request.priority != priority) {
        return false;
      }
      if (!request.completer.isCompleted) request.completer.complete(null);
      return true;
    });
    final inFlight = _inFlight;
    if (inFlight != null &&
        inFlight.kind == _WebRequestKind.bin &&
        inFlight.pageIndex == pageIndex &&
        inFlight.priority == priority) {
      _worker?.postMessage(JSObject()..setProperty('kind'.toJS, 'cancel'.toJS));
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

enum _WebRequestKind { record, bin }

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
      this.imageDecodeRegion)
      : kind = _WebRequestKind.record,
        pageToDevice = null,
        deviceWidth = 0,
        deviceHeight = 0,
        binPixelRatio = 0;

  _WebPending.bin(
      this.priority,
      this.seq,
      this.pageIndex,
      this.annotations,
      this.pageToDevice,
      this.deviceWidth,
      this.deviceHeight,
      this.binPixelRatio)
      : kind = _WebRequestKind.bin,
        imagePixelRatio = null,
        decodeImages = false,
        commandLimit = null,
        imageDecodeRegion = null;

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
  final completer = Completer<Uint8List?>();
  bool requeueAfterPreemption = false;
  int id = -1;
}

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
