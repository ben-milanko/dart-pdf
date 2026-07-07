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
/// is what makes that reordering possible - and when a higher-priority request
/// arrives while a lower-priority one is in flight, the worker cancels the
/// in-flight job mid-walk (cooperative preemption via [PdfCancellationToken])
/// and serves the urgent request next.
PdfRenderWorker startRenderWorker(Uint8List bytes) =>
    _IsolateRenderWorker(bytes);

class _IsolateRenderWorker implements PdfRenderWorker {
  _IsolateRenderWorker(Uint8List bytes) {
    unawaited(_spawn(bytes));
  }

  Isolate? _isolate;
  SendPort? _toWorker;
  SendPort? _toCancelPort;
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
      // isolates unsupported / spawn threw: behave like the null worker -
      // every queued and future record() resolves to null (local render).
      _spawnFailed = true;
      _failPending();
    }
  }

  Future<void> _spawnInner(Uint8List bytes) async {
    final handshake = Completer<List<SendPort>>();
    _fromWorker.listen((message) {
      if (message is List<SendPort>) {
        handshake.complete(message);
        return;
      }
      // [int id, TransferableTypedData? data] - null means "render locally".
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
      _WorkerInit(
          _fromWorker.sendPort, TransferableTypedData.fromList([bytes])),
      debugName: 'pdf-render-worker',
      errorsAreFatal: false,
    );
    // Disposed while the spawn was in flight (a widget test tearing down, a
    // fast document swap): kill the freshly-spawned isolate now - dispose
    // couldn't, _isolate was still null then.
    if (_disposed) {
      isolate.kill(priority: Isolate.immediate);
      return;
    }
    _isolate = isolate;
    final ports = await handshake.future;
    _toWorker = ports[0];
    _toCancelPort = ports[1];
    _pump(); // drain anything queued before the handshake landed
  }

  @override
  Future<List<PdfRenderCommand>?> record(int pageIndex,
      {bool annotations = true,
      int priority = 0,
      double? imagePixelRatio,
      bool decodeImages = true,
      int? commandLimit,
      PdfRect? imageDecodeRegion}) async {
    if (_disposed || _spawnFailed) return null;
    final request = _PendingRequest(priority, _seq++, pageIndex, annotations,
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

  /// Sends the highest-priority queued request to the worker when it is idle
  /// and spawned. Lower [priority] wins; ties break by submission order, so a
  /// freshly-requested visible page (priority 0) preempts pending prefetch.
  ///
  /// When a higher-priority request is queued while a lower-priority one is
  /// in flight, the in-flight job is cancelled via the cancel port so the
  /// worker abandons it mid-walk and serves the urgent request next.
  void _pump() {
    if (_disposed || _queue.isEmpty) return;
    final port = _toWorker;
    if (port == null) return; // not spawned yet; _spawn calls _pump when ready

    // If there's an in-flight request, check whether a queued request has
    // strictly higher priority (lower number). If so, cancel the in-flight
    // one so the worker yields and we can dispatch the urgent request.
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
        _toCancelPort?.send(null);
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
    port.send([
      request.id,
      request.pageIndex,
      request.annotations,
      request.imagePixelRatio,
      request.decodeImages,
      request.commandLimit,
      request.imageDecodeRegion?.left,
      request.imageDecodeRegion?.bottom,
      request.imageDecodeRegion?.right,
      request.imageDecodeRegion?.top,
    ]);
  }

  @override
  void cancel(int pageIndex, {int priority = 0}) {
    if (_disposed) return;
    // Drop matching QUEUED requests. Completing with null makes their record()
    // futures resolve to a local render - the abandoning caller ignores that.
    _queue.removeWhere((request) {
      if (request.pageIndex != pageIndex || request.priority != priority) {
        return false;
      }
      if (!request.completer.isCompleted) request.completer.complete(null);
      return true;
    });
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _toWorker = null;
    _toCancelPort = null;
    _fromWorker.close();
    _failPending();
  }

  /// Resolves every in-flight and queued request to null (local render) -
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
  _PendingRequest(
      this.priority,
      this.seq,
      this.pageIndex,
      this.annotations,
      this.imagePixelRatio,
      this.decodeImages,
      this.commandLimit,
      this.imageDecodeRegion);

  final int priority;
  final int seq;
  final int pageIndex;
  final bool annotations;
  final double? imagePixelRatio;
  final bool decodeImages;
  final int? commandLimit;
  final PdfRect? imageDecodeRegion;
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
/// until the worker is killed. Uses [drawPageOperationsAsync] so the event
/// loop can receive cancel messages mid-walk.
void _workerMain(_WorkerInit init) {
  final requests = ReceivePort();
  final cancelPort = ReceivePort();
  init.reply.send([requests.sendPort, cancelPort.sendPort]);

  PdfDocument? document;
  try {
    document = PdfDocument.open(init.bytes.materialize().asUint8List());
  } catch (_) {
    document = null; // a broken document fails every page → all local renders
  }

  PdfCancellationToken? activeToken;
  cancelPort.listen((_) {
    activeToken?.cancelled = true;
  });

  requests.listen((message) async {
    final request = message as List<Object?>;
    final id = request[0] as int;
    final pageIndex = request[1] as int;
    final annotations = request[2] as bool;
    final imagePixelRatio = request[3] as double?;
    final decodeImages = request[4] as bool;
    final commandLimit = request.length > 5 ? request[5] as int? : null;
    final imageDecodeRegion = request.length > 9 &&
            request[6] != null &&
            request[7] != null &&
            request[8] != null &&
            request[9] != null
        ? PdfRect(request[6] as double, request[7] as double,
            request[8] as double, request[9] as double)
        : null;

    final token = PdfCancellationToken();
    activeToken = token;
    Uint8List? buffer;
    try {
      if (document != null) {
        buffer = await _recordPageAsync(
            document,
            pageIndex,
            annotations,
            imagePixelRatio,
            decodeImages,
            commandLimit,
            imageDecodeRegion,
            token);
      }
    } on PdfCancelledException {
      buffer = null;
    } catch (_) {
      buffer = null; // any failure → caller renders this page locally
    }
    activeToken = null;
    init.reply.send([
      id,
      buffer == null ? null : TransferableTypedData.fromList([buffer]),
    ]);
  });
}

/// Records one page into a serialized command buffer, yielding periodically
/// so the cancel port's listener can fire and set [token.cancelled].
Future<Uint8List?> _recordPageAsync(
    PdfDocument document,
    int pageIndex,
    bool annotations,
    double? imagePixelRatio,
    bool decodeImages,
    int? commandLimit,
    PdfRect? imageDecodeRegion,
    PdfCancellationToken token) async {
  if (pageIndex < 0 || pageIndex >= document.pageCount) return null;
  final page = document.page(pageIndex);
  final previewOperationLimit = decodeImages ? null : commandLimit;
  final ops = ContentStreamParser.parse(page.contentBytes(),
      operationLimit: previewOperationLimit);
  final recorder = RecordingPdfDevice();
  final interpreter =
      PdfInterpreter(cos: document.cos, device: recorder, cancellation: token);
  await interpreter.drawPageOperationsAsync(page, ops);
  if (annotations) interpreter.drawAnnotations(page);
  return serializeCommands(recorder.commands,
      cos: document.cos,
      decodeImages: decodeImages,
      maxImagePixelRatio: imagePixelRatio,
      imageDecodeRegion: imageDecodeRegion,
      imagePlaceholders: !decodeImages,
      commandLimit: commandLimit);
}
