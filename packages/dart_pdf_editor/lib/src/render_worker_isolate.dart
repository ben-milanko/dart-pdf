import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

import 'render_worker.dart';

/// Native backend: a long-lived background isolate that opens its own
/// [PdfDocument] from the bytes once and records pages on request, sending the
/// serialized command buffer back over a port. The heavy content-stream parse
/// and interpreter walk happen entirely off the UI thread.
///
/// Requests are served one at a time through a main-side priority queue: the
/// on-screen page (priority 0) jumps ahead of background prefetch (priority 1),
/// so the visible page never waits behind a storm of prerenders even though
/// the single isolate processes serially. Keeping just one request in flight
/// is what makes that reordering possible — and when the UI thread is busy it
/// couldn't consume more results anyway.
PdfRenderWorker startRenderWorker(Uint8List bytes) =>
    _IsolateRenderWorker(bytes);

class _IsolateRenderWorker implements PdfRenderWorker {
  _IsolateRenderWorker(Uint8List bytes) {
    unawaited(_spawn(bytes));
  }

  Isolate? _isolate;
  SendPort? _toWorker;
  final _fromWorker = ReceivePort();

  final _queue = <_PendingRequest>[];
  _PendingRequest? _inFlight;
  int _nextId = 0;
  int _seq = 0;
  bool _disposed = false;
  bool _spawnFailed = false;

  @override
  bool get isActive => !_disposed && !_spawnFailed;

  Future<void> _spawn(Uint8List bytes) async {
    try {
      await _spawnInner(bytes);
    } catch (_) {
      // isolates unsupported / spawn threw: behave like the null worker —
      // every queued and future record() resolves to null (local render).
      _spawnFailed = true;
      _failPending();
    }
  }

  Future<void> _spawnInner(Uint8List bytes) async {
    final handshake = Completer<SendPort>();
    _fromWorker.listen((message) {
      if (message is SendPort) {
        handshake.complete(message);
        return;
      }
      // [int id, TransferableTypedData? data] — null means "render locally".
      final response = message as List<Object?>;
      final id = response[0] as int;
      final request = _inFlight;
      if (request == null || request.id != id) return; // stale (disposed)
      _inFlight = null;
      final data = response[1] as TransferableTypedData?;
      request.completer.complete(data?.materialize().asUint8List());
      _pump();
    });
    final isolate = await Isolate.spawn(
      _workerMain,
      _WorkerInit(_fromWorker.sendPort, TransferableTypedData.fromList([bytes])),
      debugName: 'pdf-render-worker',
      errorsAreFatal: false,
    );
    // Disposed while the spawn was in flight (a widget test tearing down, a
    // fast document swap): kill the freshly-spawned isolate now — dispose
    // couldn't, _isolate was still null then.
    if (_disposed) {
      isolate.kill(priority: Isolate.immediate);
      return;
    }
    _isolate = isolate;
    _toWorker = await handshake.future;
    _pump(); // drain anything queued before the handshake landed
  }

  @override
  Future<List<PdfRenderCommand>?> record(int pageIndex,
      {bool annotations = true, int priority = 0}) async {
    if (_disposed || _spawnFailed) return null;
    final request = _PendingRequest(priority, _seq++, pageIndex, annotations);
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
  /// and spawned. Lower [priority] wins; ties break by submission order, so a
  /// freshly-requested visible page (priority 0) preempts pending prefetch.
  void _pump() {
    if (_disposed || _inFlight != null || _queue.isEmpty) return;
    final port = _toWorker;
    if (port == null) return; // not spawned yet; _spawn calls _pump when ready
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
    port.send([request.id, request.pageIndex, request.annotations]);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _toWorker = null;
    _fromWorker.close();
    _failPending();
  }

  /// Resolves every in-flight and queued request to null (local render) —
  /// on dispose, or when the spawn fails.
  void _failPending() {
    final orphaned = [if (_inFlight != null) _inFlight!, ..._queue];
    _inFlight = null;
    _queue.clear();
    for (final request in orphaned) {
      if (!request.completer.isCompleted) request.completer.complete(null);
    }
  }
}

/// One queued record request and its pending result.
class _PendingRequest {
  _PendingRequest(this.priority, this.seq, this.pageIndex, this.annotations);

  final int priority;
  final int seq;
  final int pageIndex;
  final bool annotations;
  final completer = Completer<Uint8List?>();
  int id = -1;
}

class _WorkerInit {
  _WorkerInit(this.reply, this.bytes);

  /// The port the worker sends its own command port (and every response) on.
  final SendPort reply;

  /// The whole document, transferred (zero-copy) at spawn.
  final TransferableTypedData bytes;
}

/// Isolate entrypoint: open the document once, then serve record requests
/// until the worker is killed.
void _workerMain(_WorkerInit init) {
  final requests = ReceivePort();
  init.reply.send(requests.sendPort);

  PdfDocument? document;
  try {
    document = PdfDocument.open(init.bytes.materialize().asUint8List());
  } catch (_) {
    document = null; // a broken document fails every page → all local renders
  }

  requests.listen((message) {
    final request = message as List<Object?>;
    final id = request[0] as int;
    final pageIndex = request[1] as int;
    final annotations = request[2] as bool;

    Uint8List? buffer;
    try {
      if (document != null) {
        buffer = _recordPage(document, pageIndex, annotations);
      }
    } catch (_) {
      buffer = null; // any failure → caller renders this page locally
    }
    init.reply.send([
      id,
      buffer == null ? null : TransferableTypedData.fromList([buffer]),
    ]);
  });
}

/// Records one page into a serialized command buffer, or null when it is out of
/// range or draws an image that cannot be serialized (an inline image — see
/// [serializeCommands]). Image XObjects serialize via [document]'s `cos`.
Uint8List? _recordPage(PdfDocument document, int pageIndex, bool annotations) {
  if (pageIndex < 0 || pageIndex >= document.pageCount) return null;
  final page = document.page(pageIndex);
  final ops = ContentStreamParser.parse(page.contentBytes());
  final recorder = RecordingPdfDevice();
  final interpreter = PdfInterpreter(cos: document.cos, device: recorder)
    ..drawPageOperations(page, ops);
  if (annotations) interpreter.drawAnnotations(page);
  return serializeCommands(recorder.commands, cos: document.cos);
}
