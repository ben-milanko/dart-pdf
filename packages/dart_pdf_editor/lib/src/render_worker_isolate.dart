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
PdfRenderWorker startRenderWorker(Uint8List bytes) =>
    _IsolateRenderWorker(bytes);

class _IsolateRenderWorker implements PdfRenderWorker {
  _IsolateRenderWorker(Uint8List bytes) {
    _ready = _spawn(bytes);
  }

  Isolate? _isolate;
  SendPort? _toWorker;
  late final Future<void> _ready;
  final _fromWorker = ReceivePort();
  final _pending = <int, Completer<Uint8List?>>{};
  int _nextId = 0;
  bool _disposed = false;

  @override
  bool get isActive => !_disposed;

  Future<void> _spawn(Uint8List bytes) async {
    final handshake = Completer<SendPort>();
    _fromWorker.listen((message) {
      if (message is SendPort) {
        handshake.complete(message);
        return;
      }
      // [int id, TransferableTypedData? data] — null means "render locally".
      final response = message as List<Object?>;
      final completer = _pending.remove(response[0] as int);
      if (completer == null) return; // disposed mid-flight
      final data = response[1] as TransferableTypedData?;
      completer.complete(data?.materialize().asUint8List());
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
  }

  @override
  Future<List<PdfRenderCommand>?> record(int pageIndex,
      {bool annotations = true}) async {
    if (_disposed) return null;
    try {
      await _ready; // spawn + handshake
    } catch (_) {
      return null; // isolate unsupported / spawn failed → local render
    }
    final port = _toWorker;
    if (_disposed || port == null) return null;

    final id = _nextId++;
    final completer = Completer<Uint8List?>();
    _pending[id] = completer;
    port.send([id, pageIndex, annotations]);
    final bytes = await completer.future;
    if (bytes == null) return null;
    try {
      return deserializeCommands(bytes);
    } catch (_) {
      return null; // corrupt buffer → render locally rather than crash
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _toWorker = null;
    _fromWorker.close();
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.complete(null);
    }
    _pending.clear();
  }
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

/// Records one page into a serialized command buffer, or null when it draws
/// images (not serializable yet) or is out of range.
Uint8List? _recordPage(PdfDocument document, int pageIndex, bool annotations) {
  if (pageIndex < 0 || pageIndex >= document.pageCount) return null;
  final page = document.page(pageIndex);
  final ops = ContentStreamParser.parse(page.contentBytes());
  final recorder = RecordingPdfDevice();
  final interpreter = PdfInterpreter(cos: document.cos, device: recorder)
    ..drawPageOperations(page, ops);
  if (annotations) interpreter.drawAnnotations(page);
  return serializeCommands(recorder.commands);
}
