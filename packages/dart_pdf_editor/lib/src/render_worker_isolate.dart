import 'dart:async';
import 'dart:developer' as developer;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:pdf_cos/perf.dart';
import 'package:pdf_document/pdf_document.dart';

import 'perf_log.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_graphics/raster.dart'
    show StripPlan, StripPlanBinner, decodeStripPlan, encodeStripPlan;

import 'region_replay_index.dart';
import 'render_worker.dart';
import 'render_worker_transcript_cache.dart'
    show compactTranscriptSourceCommands, retainedCommandGraphsWeight;

/// Test hook: hold a requested cancellation until the cancelled job answers
/// and the next queued request is dispatched. That deterministically recreates
/// the late-signal race request-scoped cancellation must reject.
bool debugDeferPdfRenderWorkerCancelUntilNextRequest = false;

/// Number of stale request-scoped cancel messages ignored by native workers.
/// Test/diagnostic counter; reset it before a focused probe.
int debugPdfRenderWorkerIgnoredStaleCancels = 0;

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
///
/// The command buffer crosses the seam as a serialized [Uint8List] wrapped in
/// [TransferableTypedData] (zero-copy transfer), and is rebuilt with
/// [deserializeCommands] on the main isolate. Passing the live
/// `List<PdfRenderCommand>` graph over the port instead (issue #309's
/// "transfer half") was measured and rejected: the VM's general object-graph
/// copy is ~3–4x slower than the compact byte codec on a dense page and lands
/// on the receiving UI isolate, and `Isolate.exit`'s zero-copy hand-off would
/// kill this long-lived pooled worker. See
/// `packages/pdf_graphics/tool/bench_render_seam.dart` and
/// `doc/dev-log/2026-07-17-seam-transfer-measurement.md`.
PdfRenderWorker startRenderWorker(Uint8List bytes) =>
    _IsolateRenderWorker(bytes);

/// No-op on native: spawning a background isolate carries no fetch/compile cost
/// (the ~1.45 s #450 warm-up is dart2js-on-the-web specific), so there is
/// nothing worth prewarming ahead of the document.
void prewarmRenderWorkers(int count) {}

/// No-op counterpart to [prewarmRenderWorkers].
void disposePrewarmedRenderWorkers() {}

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
  int? _deferredCancelId;

  @override
  bool get isActive => !_disposed && !_spawnFailed;

  @override
  bool get supportsRevisionUpdate => true;

  static const int _updatePriority = -1000;

  @override
  void updateRevision(
    int baseLength,
    Uint8List appendedBytes,
    int newLength,
    Set<int>? changedPages,
  ) {
    if (_disposed || _spawnFailed) return;
    // Route the update through the ordinary priority queue so it runs only when
    // the worker is idle: it mutates the worker's document in place, so it must
    // not overlap an in-flight record/bin walk. Its high priority preempts a
    // running record (which requeues and then re-runs against the new revision)
    // and jumps ahead of queued prefetch.
    final request = _PendingRequest.update(
      _updatePriority,
      _seq++,
      baseLength,
      appendedBytes,
      newLength,
      changedPages,
    );
    _queue.add(request);
    _pump();
  }

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
      if (message is List<Object?> &&
          message.isNotEmpty &&
          message.first == 'cancelIgnored') {
        debugPdfRenderWorkerIgnoredStaleCancels++;
        developer.log(
          'ignored stale cancel target=${message[1]} active=${message[2]}',
          name: 'dart_pdf_editor.render_worker',
        );
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
      _deliverDeferredCancelToNextRequest();
    });
    final isolate = await Isolate.spawn(
      _workerMain,
      _WorkerInit(_fromWorker.sendPort, TransferableTypedData.fromList([bytes]),
          perfEnabled: PdfPerfLog.enabled),
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
    bool slugGlyphs = false,
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
        pixelRatio,
        slugGlyphs);
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

  @override
  Future<PdfRegionReplayIndex?> buildRegionIndex(
    int pageIndex, {
    required bool annotations,
    required int maxCommands,
    required bool buildGrid,
    int priority = 0,
  }) async {
    if (_disposed || _spawnFailed) return null;
    final request = _PendingRequest.regionIndex(
        priority, _seq++, pageIndex, annotations, maxCommands, buildGrid);
    _queue.add(request);
    _pump();
    final buffers = await request.completer.future;
    if (buffers == null) return null;
    try {
      return deserializeRegionReplayIndex(buffers.single);
    } catch (_) {
      return null; // corrupt buffer → build in-isolate rather than crash
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
        _cancelRequest(_inFlight!);
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
    if (request.kind == _RequestKind.update) {
      port.send([
        'update',
        request.id,
        request.baseLength,
        TransferableTypedData.fromList([request.appendedBytes!]),
        request.newLength,
        request.changedPages?.toList(),
      ]);
    } else if (request.kind == _RequestKind.record) {
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
        request.slugGlyphs,
      ]);
    } else if (request.kind == _RequestKind.regionIndex) {
      port.send([
        'regionIndex',
        request.id,
        request.pageIndex,
        request.annotations,
        request.regionMaxCommands,
        request.regionBuildGrid,
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
  /// The cancel message carries the target request id. A signal that arrives
  /// after that job replied is ignored by the worker instead of cancelling the
  /// next request occupying the slot (issue #220).
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
      _cancelRequest(inFlight);
    }
  }

  void _cancelRequest(_PendingRequest request) {
    if (debugDeferPdfRenderWorkerCancelUntilNextRequest) {
      _deferredCancelId = request.id;
      return;
    }
    _toCancelPort?.send(request.id);
  }

  void _deliverDeferredCancelToNextRequest() {
    final id = _deferredCancelId;
    if (!debugDeferPdfRenderWorkerCancelUntilNextRequest ||
        id == null ||
        _inFlight == null) {
      return;
    }
    _deferredCancelId = null;
    // Give the worker event loop time to enter the just-dispatched request;
    // this branch exists only for the deterministic late-delivery test hook.
    Timer(const Duration(milliseconds: 5), () {
      if (!_disposed) _toCancelPort?.send(id);
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

enum _RequestKind { record, bin, detail, update, regionIndex }

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
        binPixelRatio = 0,
        slugGlyphs = false,
        baseLength = 0,
        appendedBytes = null,
        newLength = 0,
        changedPages = null,
        regionMaxCommands = 0,
        regionBuildGrid = false;

  _PendingRequest.bin(
      this.priority,
      this.seq,
      this.pageIndex,
      this.annotations,
      this.pageToDevice,
      this.deviceWidth,
      this.deviceHeight,
      this.binPixelRatio,
      this.slugGlyphs)
      : kind = _RequestKind.bin,
        imagePixelRatio = null,
        decodeImages = false,
        commandLimit = null,
        imageDecodeRegion = null,
        baseLength = 0,
        appendedBytes = null,
        newLength = 0,
        changedPages = null,
        regionMaxCommands = 0,
        regionBuildGrid = false;

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
        commandLimit = null,
        slugGlyphs = false,
        baseLength = 0,
        appendedBytes = null,
        newLength = 0,
        changedPages = null,
        regionMaxCommands = 0,
        regionBuildGrid = false;

  _PendingRequest.regionIndex(
      this.priority,
      this.seq,
      this.pageIndex,
      this.annotations,
      this.regionMaxCommands,
      this.regionBuildGrid)
      : kind = _RequestKind.regionIndex,
        imagePixelRatio = null,
        decodeImages = false,
        commandLimit = null,
        imageDecodeRegion = null,
        pageToDevice = null,
        deviceWidth = 0,
        deviceHeight = 0,
        binPixelRatio = 0,
        slugGlyphs = false,
        baseLength = 0,
        appendedBytes = null,
        newLength = 0,
        changedPages = null;

  _PendingRequest.update(
      this.priority,
      this.seq,
      this.baseLength,
      this.appendedBytes,
      this.newLength,
      this.changedPages)
      : kind = _RequestKind.update,
        pageIndex = -1,
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
  final bool slugGlyphs;

  // update-only
  final int baseLength;
  final Uint8List? appendedBytes;
  final int newLength;
  final Set<int>? changedPages;

  // regionIndex-only
  final int regionMaxCommands;
  final bool regionBuildGrid;

  final completer = Completer<List<Uint8List>?>();
  bool requeueAfterPreemption = false;
  int id = -1;
}

class _WorkerInit {
  _WorkerInit(this.reply, this.bytes, {this.perfEnabled = false});

  /// The port the worker sends its own command port (and every response) on.
  final SendPort reply;

  /// The whole document, transferred (zero-copy) at spawn.
  final TransferableTypedData bytes;

  /// Switch on the worker isolate's own (isolate-local) PdfPerf facade.
  final bool perfEnabled;
}

/// Isolate entrypoint: open the document once, then serve record and bin
/// requests until the worker is killed. Uses the async walks so the event
/// loop can receive cancel messages mid-job.
void _workerMain(_WorkerInit init) {
  // Statics are isolate-local: the worker's PdfPerf must be switched on here
  // (mirroring the spawner's PdfPerfLog state). Rare structural events route
  // to developer.log; accumulated stats stay in-isolate for future protocol
  // messages to fetch.
  if (init.perfEnabled) {
    PdfPerf.enabled = true;
    PdfPerf.sink = (line) =>
        developer.log(line, name: 'dart_pdf_editor.render_worker');
  }
  final requests = ReceivePort();
  final cancelPort = ReceivePort();
  init.reply.send([requests.sendPort, cancelPort.sendPort]);

  // The worker's own copy of the document image. It grows in place as
  // append-only revisions arrive ('update' messages), so the buffer the open
  // document parses from stays valid across edits.
  var workerBytes = init.bytes.materialize().asUint8List();
  PdfDocument? document;
  try {
    document = PdfDocument.open(workerBytes);
  } catch (_) {
    document = null; // a broken document fails every page → all local renders
  }

  final binCommands = _BinCommandCache();

  PdfCancellationToken? activeToken;
  int? activeRequestId;
  cancelPort.listen((message) {
    // A cancel can arrive after its target already replied and the next job
    // became active. Ignore that stale id instead of aborting the next (often
    // urgent) page. This is the native half of issue #220.
    if (message is int && message == activeRequestId) {
      activeToken?.cancelled = true;
    } else if (message is int) {
      init.reply.send(['cancelIgnored', message, activeRequestId]);
    }
  });

  requests.listen((message) async {
    final request = message as List<Object?>;
    final kind = request[0] as String;
    final id = request[1] as int;

    if (kind == 'update') {
      // The main side only dispatches an update when the worker is idle, so it
      // never overlaps an in-flight record/bin walk that would see the document
      // mutate mid-interpret. The whole body is guarded so a malformed update
      // (an inconsistent length triple) can never throw past the ack below and
      // leave the main side's slot pinned - that would wedge the worker.
      try {
        final baseLength = request[2] as int;
        final appended =
            (request[3] as TransferableTypedData).materialize().asUint8List();
        final newLength = request[4] as int;
        final changed = (request[5] as List?)?.cast<int>().toSet();
        final rebuilt = Uint8List(baseLength + appended.length)
          ..setRange(0, baseLength, workerBytes)
          ..setRange(baseLength, baseLength + appended.length, appended);
        final live = Uint8List.sublistView(rebuilt, 0, newLength);
        var incremental = false;
        final doc = document;
        if (doc != null) {
          try {
            doc.applyIncrementalUpdate(live);
            incremental = true;
          } catch (_) {
            // Not a forward append (an undo shrinks to a prefix) or an
            // unsupported document: re-open from the target prefix instead.
          }
        }
        if (!incremental) {
          try {
            document = PdfDocument.open(live);
          } catch (_) {
            document = null;
          }
        }
        // Commit the grown buffer only once the document reflects it.
        workerBytes = rebuilt;
        // On the in-place fast path only the changed pages' cached commands are
        // stale; a re-open makes a fresh document, so every cached command
        // (which referenced the old one) must go.
        binCommands.evictPages(incremental ? changed : null);
      } catch (_) {
        // Malformed update: leave the document and buffer as they were and just
        // free the worker slot below so it keeps serving other pages.
      }
      init.reply.send([id, null]);
      return;
    }

    final pageIndex = request[2] as int;
    final annotations = request[3] as bool;

    final token = PdfCancellationToken();
    activeToken = token;
    activeRequestId = id;
    Uint8List? buffer;
    Uint8List? detailPlanBuffer;
    // Snapshot the (reassignable) document so an 'update' arriving between
    // yields of this walk can't null it out mid-flight - and so the compiler
    // can type-promote it.
    final doc = document;
    try {
      if (doc != null) {
        if (kind == 'bin') {
          buffer = await _binStripsAsync(
              doc,
              binCommands,
              pageIndex,
              annotations,
              (request[4] as List<Object?>).cast<double>(),
              request[5] as int,
              request[6] as int,
              request[7] as double,
              request[8] as bool,
              token);
        } else if (kind == 'detail') {
          final result = await _recordStripDetailAsync(
            doc,
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
        } else if (kind == 'regionIndex') {
          buffer = await _buildRegionIndexAsync(
              doc,
              binCommands,
              pageIndex,
              annotations,
              request[4] as int,
              request[5] as bool,
              token);
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
              doc,
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
    if (activeRequestId == id) {
      activeToken = null;
      activeRequestId = null;
    }
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
  final recorder = RecordingPdfDevice();
  final interpreter =
      PdfInterpreter(cos: document.cos, device: recorder, cancellation: token);
  await interpreter.drawPageContentAsync(page, page.contentBytes(),
      operationLimit: previewOperationLimit);
  if (annotations) interpreter.drawAnnotations(page);
  return serializeCommands(recorder.commands,
      cos: document.cos,
      decodeImages: decodeImages,
      maxImagePixelRatio: imagePixelRatio,
      imageDecodeRegion: imageDecodeRegion,
      imagePlaceholders: !decodeImages,
      commandLimit: commandLimit,
      compactStateScopes: true);
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
    bool slugGlyphs,
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
    slugGlyphs: slugGlyphs,
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
    compactStateScopes: true,
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

/// Builds the region-replay spatial index from the page's cached wire
/// transcript and serializes it, or null when the page can't be offloaded
/// (unserializable content declines in [_BinCommandCache], as [binStrips]).
///
/// The transcript is the SAME round-tripped command list the strip bins replay
/// (compacted, float32 path coordinates), which is byte-for-byte what a
/// worker-recorded retained scene holds - so the index's unit indices line up
/// with that scene's transcript on the UI isolate. The grid build itself is a
/// synchronous pass over the commands; the cancellable work is the re-record
/// inside [_BinCommandCache.commandsFor], already checked below.
Future<Uint8List?> _buildRegionIndexAsync(
    PdfDocument document,
    _BinCommandCache cache,
    int pageIndex,
    bool annotations,
    int maxCommands,
    bool buildGrid,
    PdfCancellationToken token) async {
  final commands =
      await cache.commandsFor(document, pageIndex, annotations, token);
  if (commands == null) return null;
  if (token.cancelled) throw const PdfCancelledException();
  final index = PdfRegionReplayIndex.build(commands,
      maxCommands: maxCommands, buildGrid: buildGrid);
  return serializeRegionReplayIndex(index);
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
/// and never ask for worker plans anyway. A command-slot budget supplements
/// the two-entry cap while always retaining the most recently used page.
class _BinCommandCache {
  final _entries = <(int, bool), _BinCommandEntry>{};
  static const int _capacity = 2;
  static const int _maxRetainedCommands = 250000;

  int get _retainedCommandWeight => _entries.values.fold(
        0,
        (total, entry) => total + entry.retainedCommandWeight,
      );

  /// Drops the cached commands for [pages] (or every page when null) after a
  /// revision update, so a later bin re-records them from the new document.
  void evictPages(Set<int>? pages) {
    if (pages == null) {
      _entries.clear();
    } else {
      _entries.removeWhere((key, _) => pages.contains(key.$1));
    }
  }

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
    final recorder = RecordingPdfDevice();
    final interpreter = PdfInterpreter(
        cos: document.cos, device: recorder, cancellation: token);
    await interpreter.drawPageContentAsync(page, page.contentBytes());
    if (annotations) interpreter.drawAnnotations(page);
    final buffer = serializeCommands(recorder.commands,
        cos: document.cos,
        decodeImages: false,
        imagePlaceholders: true,
        compactStateScopes: true);
    if (buffer == null) return null;
    recorder.commands.clear();
    final wireCommands =
        List<PdfRenderCommand>.unmodifiable(deserializeCommands(buffer));
    final sourceCommands = compactTranscriptSourceCommands(
      wireCommands,
      recorder.imageRequests,
    );
    if (sourceCommands == null) return null;
    final entry = _BinCommandEntry(
      sourceCommands,
      wireCommands,
    );
    _entries[key] = entry;
    while (_entries.length > 1 &&
        (_entries.length > _capacity ||
            _retainedCommandWeight > _maxRetainedCommands)) {
      _entries.remove(_entries.keys.first);
    }
    return entry;
  }
}

class _BinCommandEntry {
  _BinCommandEntry(this.sourceCommands, this.wireCommands)
      : retainedCommandWeight =
            retainedCommandGraphsWeight(sourceCommands, wireCommands);

  final List<PdfRenderCommand> sourceCommands;
  final List<PdfRenderCommand> wireCommands;
  final int retainedCommandWeight;
}
