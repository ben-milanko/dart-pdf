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

  @override
  bool get isActive => !_disposed && !_failed;

  void _onMessage(web.MessageEvent event) {
    final data = event.data as JSObject?;
    if (data == null) return;
    final kind = (data.getProperty('kind'.toJS) as JSString?)?.toDart;
    if (kind == 'ready') {
      _wlog('ready (worker opened the document)');
      _ready = true;
      _pump();
      return;
    }
    if (kind != 'result') return;
    final id = (data.getProperty('id'.toJS) as JSNumber).toDartInt;
    final request = _inFlight;
    if (request == null || request.id != id) return; // stale (disposed)
    _inFlight = null;
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
  void _pump() {
    if (_disposed || !_ready || _inFlight != null || _queue.isEmpty) return;
    final worker = _worker;
    if (worker == null) return;
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
  }

  @override
  void cancel(int pageIndex, {int priority = 0}) {
    if (_disposed || _failed) return;
    // Drop matching QUEUED requests (the in-flight one can't be preempted) so
    // the worker's next slot serves a page the user is still looking at. The
    // cancelled record() futures resolve null; the abandoning caller ignores
    // them. Mirrors the isolate backend.
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
    _failPending();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _worker?.terminate();
    _worker = null;
    _failPending();
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
