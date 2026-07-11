import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_graphics/raster.dart'
    show StripPlan, StripPlanBinner, decodeStripPlan, encodeStripPlan;

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
///
/// The same queue also serves [PdfRenderWorker.binStrips]: strip-binning
/// requests ride the identical priority/cancel/preemption machinery, they
/// just carry a different payload (device geometry in, an encoded [StripPlan]
/// out) and are cancelled through [PdfRenderWorker.cancelBinStrips] so a
/// record and a bin for the same page never cancel each other.
PdfRenderWorker startRenderWorker(Uint8List bytes) =>
    _IsolateRenderWorker(bytes);

class _IsolateRenderWorker extends PdfRenderWorker {
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
      // [int id, TransferableTypedData? data, ...] - null means "render
      // locally". Combined strip-detail responses carry command and plan
      // buffers as two separately transferable payloads.
      final response = message as List<Object?>;
      final id = response[0] as int;
      final request = _inFlight;
      if (request == null || request.id != id) return; // stale (disposed)
      _inFlight = null;
      final first = response[1] as TransferableTypedData?;
      if (first == null && request.requeueAfterPreemption && !_disposed) {
        // A higher-priority page cut in while this RECORD was interpreting.
        // Keep its original future alive and put the work back behind the
        // urgent request. PdfCachingRenderWorker may have several callers
        // sharing that future; completing null here would make every waiter
        // lose the record even though only its worker time slice was
        // preempted. Explicit cancel() never sets this flag and still drops a
        // stale queued record immediately.
        request
          ..requeueAfterPreemption = false
          ..id = -1;
        _queue.add(request);
        _pump();
        return;
      }
      request.completer.complete(first == null
          ? null
          : [
              first.materialize().asUint8List(),
              for (final data in response.skip(2).cast<TransferableTypedData>())
                data.materialize().asUint8List(),
            ]);
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
    final request = _PendingRequest.record(
        priority,
        _seq++,
        pageIndex,
        annotations,
        imagePixelRatio,
        decodeImages,
        commandLimit,
        imageDecodeRegion);
    _queue.add(request);
    _pump();
    final buffers = await request.completer.future;
    if (buffers == null) return null;
    try {
      return deserializeCommands(buffers.single);
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
    if (_disposed || _spawnFailed) return null;
    final request = _PendingRequest.bin(
        priority,
        _seq++,
        pageIndex,
        annotations,
        List.of(pageToDevice),
        deviceWidth,
        deviceHeight,
        pixelRatio);
    _queue.add(request);
    _pump();
    final buffers = await request.completer.future;
    if (buffers == null) return null;
    try {
      return decodeStripPlan(buffers.single);
    } catch (_) {
      return null; // corrupt plan → bin locally rather than crash
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
    if (_disposed || _spawnFailed) return null;
    final request = _PendingRequest.detail(
      priority,
      _seq++,
      pageIndex,
      annotations,
      List.of(pageToDevice),
      deviceWidth,
      deviceHeight,
      pixelRatio,
      imageDecodeRegion,
    );
    _queue.add(request);
    _pump();
    final buffers = await request.completer.future;
    if (buffers == null || buffers.length != 2) return null;
    try {
      return PdfStripDetail(
        deserializeCommands(buffers[0]),
        decodeStripPlan(buffers[1]),
      );
    } catch (_) {
      return null;
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
        if (_inFlight!.kind == _RequestKind.record) {
          _inFlight!.requeueAfterPreemption = true;
        }
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
    if (request.kind == _RequestKind.record) {
      port.send([
        'record',
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
    } else if (request.kind == _RequestKind.bin) {
      port.send([
        'bin',
        request.id,
        request.pageIndex,
        request.annotations,
        request.pageToDevice,
        request.deviceWidth,
        request.deviceHeight,
        request.binPixelRatio,
      ]);
    } else {
      port.send([
        'detail',
        request.id,
        request.pageIndex,
        request.annotations,
        request.pageToDevice,
        request.deviceWidth,
        request.deviceHeight,
        request.binPixelRatio,
        request.imageDecodeRegion!.left,
        request.imageDecodeRegion!.bottom,
        request.imageDecodeRegion!.right,
        request.imageDecodeRegion!.top,
      ]);
    }
  }

  @override
  void cancel(int pageIndex, {int priority = 0}) =>
      _cancelKind(_RequestKind.record, pageIndex, priority);

  @override
  void cancelBinStrips(int pageIndex, {int priority = 0}) {
    _cancelKind(_RequestKind.bin, pageIndex, priority);
    _cancelKind(_RequestKind.detail, pageIndex, priority);
  }

  /// Drops matching QUEUED requests of one [kind]. Completing with null makes
  /// their futures resolve to a local render/bin - the abandoning caller
  /// ignores that. Kinds cancel independently so a superseded zoom settle
  /// can't drop the page's pending record (or vice versa).
  ///
  /// For BIN and combined DETAIL kinds, a matching IN-FLIGHT job is also
  /// preempted (the cancel-port signal makes the worker abandon the stale
  /// walk and reply null; the abandoning caller ignores it), so a superseded
  /// settle or translated region speculation frees the worker immediately.
  /// Record cancels stay queued-only: [PdfCachingRenderWorker] dedups
  /// in-flight records across callers, so preempting one would null a waiter
  /// shared with a caller that still wants it.
  ///
  /// The in-flight signal carries a benign pre-existing race (the same one
  /// the priority-preemption path in [_pump] accepts): it can land on the
  /// worker after the job already completed and cancel the NEXT job instead,
  /// whose caller then resolves null and falls back to a local render/bin.
  void _cancelKind(_RequestKind kind, int pageIndex, int priority) {
    if (_disposed) return;
    _queue.removeWhere((request) {
      if (request.kind != kind ||
          request.pageIndex != pageIndex ||
          request.priority != priority) {
        return false;
      }
      if (!request.completer.isCompleted) request.completer.complete(null);
      return true;
    });
    final inFlight = _inFlight;
    if ((kind == _RequestKind.bin || kind == _RequestKind.detail) &&
        inFlight != null &&
        inFlight.kind == kind &&
        inFlight.pageIndex == pageIndex &&
        inFlight.priority == priority) {
      _toCancelPort?.send(null);
    }
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

enum _RequestKind { record, bin, detail }

/// One queued request (a page record or a strip bin) and its pending result.
class _PendingRequest {
  _PendingRequest.record(
      this.priority,
      this.seq,
      this.pageIndex,
      this.annotations,
      this.imagePixelRatio,
      this.decodeImages,
      this.commandLimit,
      this.imageDecodeRegion)
      : kind = _RequestKind.record,
        pageToDevice = null,
        deviceWidth = 0,
        deviceHeight = 0,
        binPixelRatio = 0;

  _PendingRequest.bin(
      this.priority,
      this.seq,
      this.pageIndex,
      this.annotations,
      this.pageToDevice,
      this.deviceWidth,
      this.deviceHeight,
      this.binPixelRatio)
      : kind = _RequestKind.bin,
        imagePixelRatio = null,
        decodeImages = false,
        commandLimit = null,
        imageDecodeRegion = null;

  _PendingRequest.detail(
      this.priority,
      this.seq,
      this.pageIndex,
      this.annotations,
      this.pageToDevice,
      this.deviceWidth,
      this.deviceHeight,
      this.binPixelRatio,
      this.imageDecodeRegion)
      : kind = _RequestKind.detail,
        imagePixelRatio = null,
        decodeImages = true,
        commandLimit = null;

  final _RequestKind kind;
  final int priority;
  final int seq;
  final int pageIndex;
  final bool annotations;

  // record-only
  final double? imagePixelRatio;
  final bool decodeImages;
  final int? commandLimit;
  final PdfRect? imageDecodeRegion;

  // bin-only
  final List<double>? pageToDevice; // a, b, c, d, e, f
  final int deviceWidth;
  final int deviceHeight;
  final double binPixelRatio;

  final completer = Completer<List<Uint8List>?>();
  bool requeueAfterPreemption = false;
  int id = -1;
}

class _WorkerInit {
  _WorkerInit(this.reply, this.bytes);

  /// The port the worker sends its own command port (and every response) on.
  final SendPort reply;

  /// The whole document, transferred (zero-copy) at spawn.
  final TransferableTypedData bytes;
}

/// Isolate entrypoint: open the document once, then serve record and bin
/// requests until the worker is killed. Uses the async walks so the event
/// loop can receive cancel messages mid-job.
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

  final binCommands = _BinCommandCache();

  PdfCancellationToken? activeToken;
  cancelPort.listen((_) {
    activeToken?.cancelled = true;
  });

  requests.listen((message) async {
    final request = message as List<Object?>;
    final kind = request[0] as String;
    final id = request[1] as int;
    final pageIndex = request[2] as int;
    final annotations = request[3] as bool;

    final token = PdfCancellationToken();
    activeToken = token;
    Uint8List? buffer;
    Uint8List? detailPlanBuffer;
    try {
      if (document != null) {
        if (kind == 'bin') {
          buffer = await _binStripsAsync(
              document,
              binCommands,
              pageIndex,
              annotations,
              (request[4] as List<Object?>).cast<double>(),
              request[5] as int,
              request[6] as int,
              request[7] as double,
              token);
        } else if (kind == 'detail') {
          final result = await _recordStripDetailAsync(
            document,
            binCommands,
            pageIndex,
            annotations,
            (request[4] as List<Object?>).cast<double>(),
            request[5] as int,
            request[6] as int,
            request[7] as double,
            PdfRect(request[8] as double, request[9] as double,
                request[10] as double, request[11] as double),
            token,
          );
          buffer = result?.$1;
          detailPlanBuffer = result?.$2;
        } else {
          final imagePixelRatio = request[4] as double?;
          final decodeImages = request[5] as bool;
          final commandLimit = request[6] as int?;
          final imageDecodeRegion = request[7] != null &&
                  request[8] != null &&
                  request[9] != null &&
                  request[10] != null
              ? PdfRect(request[7] as double, request[8] as double,
                  request[9] as double, request[10] as double)
              : null;
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
      }
    } on PdfCancelledException {
      buffer = null;
    } catch (_) {
      buffer = null; // any failure → caller renders this page locally
    }
    activeToken = null;
    if (buffer == null) {
      init.reply.send([id, null]);
    } else if (detailPlanBuffer != null) {
      init.reply.send([
        id,
        TransferableTypedData.fromList([buffer]),
        TransferableTypedData.fromList([detailPlanBuffer]),
      ]);
    } else {
      init.reply.send([
        id,
        TransferableTypedData.fromList([buffer])
      ]);
    }
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

/// Bins one page's strips for the requested device geometry and returns the
/// encoded [StripPlan], or null when the page can't be binned (bad index,
/// unserializable content, cancellation).
Future<Uint8List?> _binStripsAsync(
    PdfDocument document,
    _BinCommandCache cache,
    int pageIndex,
    bool annotations,
    List<double> matrix,
    int deviceWidth,
    int deviceHeight,
    double pixelRatio,
    PdfCancellationToken token) async {
  final commands =
      await cache.commandsFor(document, pageIndex, annotations, token);
  if (commands == null) return null;
  final binner = StripPlanBinner(
    pageToDevice: PdfMatrix(
        matrix[0], matrix[1], matrix[2], matrix[3], matrix[4], matrix[5]),
    deviceWidth: deviceWidth,
    deviceHeight: deviceHeight,
    pixelRatio: pixelRatio,
  );
  await binner.bin(commands, cancellation: token);
  return encodeStripPlan(binner.finish());
}

/// Produces the two halves of a deep-zoom detail patch in one queued worker
/// job. The cached weightless recording avoids another content-stream parse
/// after the page's first strip settle; only the region image decode and the
/// cancellable bin replay repeat as the viewport moves.
Future<(Uint8List, Uint8List)?> _recordStripDetailAsync(
  PdfDocument document,
  _BinCommandCache cache,
  int pageIndex,
  bool annotations,
  List<double> matrix,
  int deviceWidth,
  int deviceHeight,
  double pixelRatio,
  PdfRect imageDecodeRegion,
  PdfCancellationToken token,
) async {
  final sourceCommands =
      await cache.sourceCommandsFor(document, pageIndex, annotations, token);
  if (sourceCommands == null) return null;
  if (token.cancelled) throw const PdfCancelledException();

  final commandBuffer = serializeCommands(
    sourceCommands,
    cos: document.cos,
    decodeImages: true,
    maxImagePixelRatio: pixelRatio,
    imageDecodeRegion: imageDecodeRegion,
  );
  if (commandBuffer == null) return null;
  if (token.cancelled) throw const PdfCancelledException();

  // Bin the exact round-tripped commands the UI receives. Region image
  // cropping can retarget image transforms, so planning from baseCommands
  // would make the pair structurally inconsistent.
  final commands = deserializeCommands(commandBuffer);
  final binner = StripPlanBinner(
    pageToDevice: PdfMatrix(
        matrix[0], matrix[1], matrix[2], matrix[3], matrix[4], matrix[5]),
    deviceWidth: deviceWidth,
    deviceHeight: deviceHeight,
    pixelRatio: pixelRatio,
  );
  await binner.bin(commands, cancellation: token);
  return (commandBuffer, encodeStripPlan(binner.finish()));
}

/// Tiny per-worker LRU of the command lists strip bins replay, keyed
/// (pageIndex, annotations). A zoom session hammers one page with a fresh
/// geometry per settle, so 2 entries is plenty - and keeping the SAME list
/// across settles preserves the object identity of glyph outlines and paths,
/// which is what makes the process-global GlyphStripCache/ShapeStripCache
/// hits (the −42% steady-state effect) carry over to repeat settles.
///
/// The recorded commands are round-tripped through the wire codec before
/// caching so path/glyph geometry carries the same float32 truncation as the
/// buffer the UI's scene was built from ([serializeCommands] stores path
/// coordinates as float32): strips binned here are then bit-identical to a
/// local re-bin of that scene. Pages whose content can't round-trip (an
/// inline image with page-resource dependencies) decline - the same pages
/// [PdfRenderWorker.record] declines, so their scenes were locally recorded
/// and never ask for worker plans anyway.
class _BinCommandCache {
  final _entries = <(int, bool), _BinCommandEntry>{};
  static const int _capacity = 2;

  Future<List<PdfRenderCommand>?> commandsFor(PdfDocument document,
          int pageIndex, bool annotations, PdfCancellationToken token) async =>
      (await _entryFor(document, pageIndex, annotations, token))?.wireCommands;

  /// Original document-backed commands for a fresh serialization that must
  /// resolve/decode image COS streams. The wire-round-tripped commands used by
  /// [commandsFor] deliberately detach that object graph; feeding those back
  /// to [serializeCommands] works for vector geometry but can no longer safely
  /// resolve every image dependency.
  Future<List<PdfRenderCommand>?> sourceCommandsFor(PdfDocument document,
          int pageIndex, bool annotations, PdfCancellationToken token) async =>
      (await _entryFor(document, pageIndex, annotations, token))
          ?.sourceCommands;

  Future<_BinCommandEntry?> _entryFor(PdfDocument document, int pageIndex,
      bool annotations, PdfCancellationToken token) async {
    final key = (pageIndex, annotations);
    final hit = _entries.remove(key);
    if (hit != null) {
      _entries[key] = hit; // re-insert: most-recently used
      return hit;
    }
    if (pageIndex < 0 || pageIndex >= document.pageCount) return null;
    final page = document.page(pageIndex);
    final ops = ContentStreamParser.parse(page.contentBytes());
    final recorder = RecordingPdfDevice();
    final interpreter = PdfInterpreter(
        cos: document.cos, device: recorder, cancellation: token);
    await interpreter.drawPageOperationsAsync(page, ops);
    if (annotations) interpreter.drawAnnotations(page);
    final buffer = serializeCommands(recorder.commands,
        cos: document.cos, decodeImages: false, imagePlaceholders: true);
    if (buffer == null) return null;
    final entry = _BinCommandEntry(
      recorder.commands,
      deserializeCommands(buffer),
    );
    _entries[key] = entry;
    while (_entries.length > _capacity) {
      _entries.remove(_entries.keys.first);
    }
    return entry;
  }
}

class _BinCommandEntry {
  const _BinCommandEntry(this.sourceCommands, this.wireCommands);

  final List<PdfRenderCommand> sourceCommands;
  final List<PdfRenderCommand> wireCommands;
}
