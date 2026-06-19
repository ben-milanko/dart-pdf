import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:web/web.dart' as web;

import 'perf_log.dart';
import 'render_worker.dart';

// Worker lifecycle diagnostics, routed through PdfPerfLog so they ride the same
// zero-overhead toggle as the rest of the perf trace (a single bool branch when
// disabled) — and show up in a user-captured trace when something declines.
void _wlog(String m) => PdfPerfLog.log('webworker $m');

/// How long to wait for the worker to post `'ready'` (it opens the document
/// first) before giving up and rendering every page locally. The document
/// bytes are transferred to the worker at start; on some hosts — notably a
/// dart2wasm main app driving a dart2js worker — a large transfer or open can
/// silently never complete, and with no bound the viewer would spin forever on
/// such a document while small ones (a fast transfer/open) work. Generous: a
/// healthy worker opens even a large CAD document in well under a second, so
/// this only fires when the worker is genuinely wedged.
Duration pdfRenderWorkerReadyTimeout = const Duration(seconds: 12);

/// How long to wait for a single [PdfRenderWorker.record] reply before treating
/// the worker as unresponsive and falling back to local rendering. The worst
/// real page records in well under a second, so this only fires on a hang.
Duration pdfRenderWorkerRecordTimeout = const Duration(seconds: 20);

/// Web backend: a dedicated [web.Worker] that opens its own [PdfDocument] from
/// the bytes once and records pages on request, posting the serialized command
/// buffer back over `postMessage` (the document and result buffers travel as
/// transferred `ArrayBuffer`s — zero-copy, not structured-cloned). The heavy
/// content-stream parse and interpreter walk happen entirely off the main
/// thread, mirroring the native isolate backend.
///
/// The worker only runs when [pdfRenderWorkerScriptUrl] names a compiled
/// worker script (whose `main()` calls `runPdfRenderWorker`). With no URL — or
/// if the [web.Worker] fails to construct — this degrades to a null worker
/// ([isActive] false), so web apps that haven't built the worker script behave
/// exactly as before (local rendering). See `doc/render_worker_web.md`.
PdfRenderWorker startRenderWorker(Uint8List bytes) {
  final url = pdfRenderWorkerScriptUrl;
  _wlog('startRenderWorker url=$url bytes=${bytes.length}');
  if (url == null) return _WebRenderWorker.disabled();
  try {
    return _WebRenderWorker(bytes, url);
  } catch (e) {
    // Worker construction can throw (bad URL, blocked by CSP): fall back.
    _wlog('construction threw: $e — falling back to local');
    return _WebRenderWorker.disabled();
  }
}

class _WebRenderWorker implements PdfRenderWorker {
  _WebRenderWorker(Uint8List bytes, String scriptUrl) {
    final worker = web.Worker(scriptUrl.toJS);
    _worker = worker;
    worker.onmessage = ((web.MessageEvent event) => _onMessage(event)).toJS;
    // A worker-level error (script failed to load/parse) is terminal: behave
    // like the null worker so every record resolves to a local render.
    worker.onerror = ((web.Event e) {
      _wlog('onerror: ${e.type} — worker script failed; falling back to local');
      _fail();
    }).toJS;
    _wlog('worker constructed from $scriptUrl');

    // Transfer the whole document to the worker once at start (copy first so
    // the transferred buffer is exactly the document, not a view into a larger
    // backing store the caller still holds).
    final jsBuffer = Uint8List.fromList(bytes).buffer.toJS;
    final init = JSObject()
      ..setProperty('kind'.toJS, 'init'.toJS)
      ..setProperty('bytes'.toJS, jsBuffer);
    worker.postMessage(init, <JSAny>[jsBuffer].toJS);

    // Watchdog: if the worker never reports 'ready' (e.g. the transferred
    // document never arrived/opened on this host), give up and render locally
    // rather than spin forever. Cancelled the moment 'ready' lands.
    _readyWatchdog = Timer(pdfRenderWorkerReadyTimeout, () {
      if (_ready || _disposed || _failed) return;
      _wlog('ready watchdog fired after ${pdfRenderWorkerReadyTimeout.inSeconds}'
          's — worker never opened the document; falling back to local');
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

  @override
  bool get isActive => !_disposed && !_failed;

  void _onMessage(web.MessageEvent event) {
    final data = event.data as JSObject?;
    if (data == null) return;
    final kind = (data.getProperty('kind'.toJS) as JSString?)?.toDart;
    if (kind == 'ready') {
      _wlog('ready (worker opened the document)');
      _readyWatchdog?.cancel();
      _readyWatchdog = null;
      _ready = true;
      _pump();
      return;
    }
    if (kind != 'result') return;
    final id = (data.getProperty('id'.toJS) as JSNumber).toDartInt;
    final request = _inFlight;
    if (request == null || request.id != id) return; // stale (disposed)
    _inFlight = null;
    _recordWatchdog?.cancel();
    _recordWatchdog = null;
    final buffer = data.getProperty('buffer'.toJS) as JSArrayBuffer?;
    final bytes = buffer?.toDart.asUint8List();
    final err = (data.getProperty('error'.toJS) as JSString?)?.toDart;
    _wlog('result page=${request.pageIndex} '
        '${bytes == null ? 'declined (null) → local' : '${bytes.length}B → worker'}'
        '${err == null ? '' : '\n  worker error: $err'}');
    request.completer.complete(bytes);
    _pump();
  }

  @override
  Future<List<PdfRenderCommand>?> record(int pageIndex,
      {bool annotations = true, int priority = 0}) async {
    if (_disposed || _failed) {
      _wlog('record page=$pageIndex skipped (disposed=$_disposed '
          'failed=$_failed) → local');
      return null;
    }
    final request = _WebPending(priority, _seq++, pageIndex, annotations);
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

  /// Sends the highest-priority queued request to the worker when it is idle
  /// and ready. Lower [priority] wins; ties break by submission order, so a
  /// freshly-requested visible page (priority 0) preempts pending prefetch —
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
        worker.postMessage(
            JSObject()..setProperty('kind'.toJS, 'cancel'.toJS));
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
      ..setProperty('kind'.toJS, 'record'.toJS)
      ..setProperty('id'.toJS, request.id.toJS)
      ..setProperty('page'.toJS, request.pageIndex.toJS)
      ..setProperty('annotations'.toJS, request.annotations.toJS);
    worker.postMessage(message);

    // Watchdog: a record that never comes back wedges the single in-flight slot
    // (and so every queued page) forever. Bound it — on a miss, treat the
    // worker as unresponsive and degrade to local rendering for this and all
    // subsequent pages.
    _recordWatchdog?.cancel();
    final inFlightId = request.id;
    _recordWatchdog = Timer(pdfRenderWorkerRecordTimeout, () {
      if (_disposed || _failed) return;
      if (_inFlight?.id != inFlightId) return; // already answered
      _wlog('record watchdog fired for page=${request.pageIndex} after '
          '${pdfRenderWorkerRecordTimeout.inSeconds}s — worker unresponsive; '
          'falling back to local');
      _fail();
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
      if (request.pageIndex != pageIndex || request.priority != priority) {
        return false;
      }
      if (!request.completer.isCompleted) request.completer.complete(null);
      dropped++;
      return true;
    });
    if (dropped > 0) {
      _wlog('cancel page=$pageIndex priority=$priority dropped=$dropped queued');
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

  /// Resolves every in-flight and queued request to null (local render) — on
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

/// One queued record request and its pending result (mirrors the isolate
/// backend's `_PendingRequest`).
class _WebPending {
  _WebPending(this.priority, this.seq, this.pageIndex, this.annotations);

  final int priority;
  final int seq;
  final int pageIndex;
  final bool annotations;
  final completer = Completer<Uint8List?>();
  int id = -1;
}
