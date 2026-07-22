import 'package:pdf_cos/perf.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

/// One end-to-end, per-phase record of a single page render, spanning both
/// isolates.
///
/// A page render is a pipeline whose phases live on different threads:
///
///   parse → interpret → serialize → transfer → deserialize → replay → rasterize
///   └───────────── worker/isolate half ──────────────┘ └──── main-isolate half ────┘
///
/// Before this type there was no shared record: the worker filled an isolate-
/// private [PdfWorkerPhaseTimings] and the main isolate assembled its own
/// separate string log, so nothing yielded one comparable breakdown. This
/// value type is the single record both halves fill - the worker attaches its
/// phases (via [addWorker]/direct field writes), and the main isolate completes
/// the transfer, deserialize, replay, and rasterize phases - and is the surface
/// the CI perf gate asserts against (see `test/render_trace_gate_test.dart`).
///
/// All phase fields are microseconds. They are mutable accumulators because one
/// worker job can serialize both a transcript and its image-bearing buffer, and
/// a progressive page is recorded in more than one pass; sum with `+=`. The
/// worker sub-phases ([streamUs], [interpretUs], [decodeUs], [serializeUs],
/// [binUs]) are a breakdown *within* [workerUs] (the worker's total wall time),
/// not additional to it; [endToEndUs] adds the phases that happen outside the
/// worker.
class PdfRenderTrace {
  PdfRenderTrace({this.pageIndex = -1});

  /// The page this trace describes, or -1 when not attributed to one page.
  int pageIndex;

  // --- Worker / isolate half -------------------------------------------------

  /// Content-stream tokenize time, when measured separately from interpret.
  ///
  /// The worker's async record path folds parse and interpret into [streamUs]
  /// because it cannot cheaply split them mid-walk; the synchronous
  /// [captureOffThread] path measures them apart and fills this.
  int parseUs = 0;

  /// Combined content-stream parse + interpret time (the worker's async path).
  int streamUs = 0;

  /// Interpreter walk time. In [captureOffThread] this is the content + annotation
  /// walk; in the worker's async path it is the annotation pass only (the
  /// content walk is folded into [streamUs]).
  int interpretUs = 0;

  /// Off-thread image decode time (pure-Dart / browser codec).
  int decodeUs = 0;

  /// Command-buffer serialization time (`serializeCommands`).
  int serializeUs = 0;

  /// Strip-binning time (`StripPlanBinner`), when the job binned strips.
  int binUs = 0;

  /// The worker's total wall time for the job, when the backend reports it.
  int workerUs = 0;

  /// Whether the worker served this page from its retained transcript cache.
  bool transcriptHit = false;

  // --- Main-isolate half -----------------------------------------------------

  /// Time the request waited in the main-side priority queue before dispatch.
  int queueUs = 0;

  /// Cross-isolate transfer time (round trip minus [workerUs]).
  int transferUs = 0;

  /// Command-buffer deserialization time (`deserializeCommands`).
  int deserializeUs = 0;

  /// Command-replay time - walking the deserialized commands into a device (a
  /// `ui.Picture` on the main isolate; a headless walk in [captureOffThread]).
  int replayUs = 0;

  /// Rasterization time (`Picture.toImage` + readback). Only filled by a
  /// Flutter-hosted capture; 0 in the pure-Dart [captureOffThread].
  int rasterizeUs = 0;

  /// Sum of the worker sub-phases. Approximates [workerUs] (which also carries
  /// scheduling/yield overhead the sub-phases don't).
  int get workerPhasesUs =>
      parseUs + streamUs + interpretUs + decodeUs + serializeUs + binUs;

  /// Sum of the main-isolate phases done after the buffer arrives.
  int get mainPhasesUs => deserializeUs + replayUs + rasterizeUs;

  /// Whole-pipeline wall time: the queue wait, the worker, the transfer, and
  /// the main-isolate finish. Uses [workerUs] when the backend reported it,
  /// otherwise the worker sub-phase sum (the [captureOffThread] case).
  int get endToEndUs =>
      queueUs +
      (workerUs > 0 ? workerUs : workerPhasesUs) +
      transferUs +
      mainPhasesUs;

  /// Folds another trace's phases into this one (used to accumulate a progressive
  /// page's several worker passes into one record).
  void add(PdfRenderTrace other) {
    parseUs += other.parseUs;
    streamUs += other.streamUs;
    interpretUs += other.interpretUs;
    decodeUs += other.decodeUs;
    serializeUs += other.serializeUs;
    binUs += other.binUs;
    workerUs += other.workerUs;
    queueUs += other.queueUs;
    transferUs += other.transferUs;
    deserializeUs += other.deserializeUs;
    replayUs += other.replayUs;
    rasterizeUs += other.rasterizeUs;
    transcriptHit = transcriptHit || other.transcriptHit;
  }

  /// A deep copy - a stable snapshot of a still-mutating accumulator.
  /// The COS-layer PdfPerf delta recorded across this capture (per-filter
  /// decode times, object loads, cache-relevant counters), attached by
  /// [captureOffThread] when `PdfPerf.enabled`. Null otherwise. Carried by
  /// [copy]; [min] keeps whichever side has one (it is a breakdown, not a
  /// timing to minimize).
  PdfPerfStats? cosStats;

  PdfRenderTrace copy() => PdfRenderTrace(pageIndex: pageIndex)
    ..cosStats = cosStats
    ..parseUs = parseUs
    ..streamUs = streamUs
    ..interpretUs = interpretUs
    ..decodeUs = decodeUs
    ..serializeUs = serializeUs
    ..binUs = binUs
    ..workerUs = workerUs
    ..transcriptHit = transcriptHit
    ..queueUs = queueUs
    ..transferUs = transferUs
    ..deserializeUs = deserializeUs
    ..replayUs = replayUs
    ..rasterizeUs = rasterizeUs;

  /// The per-phase minimum of `this` and [other] (each field taken from
  /// whichever trace is faster). Best-of-N over repeated captures defeats the
  /// GC/scheduler jitter that would otherwise make a wall-clock gate flaky.
  PdfRenderTrace min(PdfRenderTrace other) =>
      PdfRenderTrace(pageIndex: pageIndex == other.pageIndex ? pageIndex : -1)
        ..cosStats = cosStats ?? other.cosStats
        ..parseUs = _min(parseUs, other.parseUs)
        ..streamUs = _min(streamUs, other.streamUs)
        ..interpretUs = _min(interpretUs, other.interpretUs)
        ..decodeUs = _min(decodeUs, other.decodeUs)
        ..serializeUs = _min(serializeUs, other.serializeUs)
        ..binUs = _min(binUs, other.binUs)
        ..workerUs = _min(workerUs, other.workerUs)
        ..transcriptHit = transcriptHit || other.transcriptHit
        ..queueUs = _min(queueUs, other.queueUs)
        ..transferUs = _min(transferUs, other.transferUs)
        ..deserializeUs = _min(deserializeUs, other.deserializeUs)
        ..replayUs = _min(replayUs, other.replayUs)
        ..rasterizeUs = _min(rasterizeUs, other.rasterizeUs);

  /// One-line, human-readable breakdown; omits phases that never ran.
  String format() {
    final parts = <String>[
      if (parseUs > 0) 'parse=${_ms(parseUs)}',
      if (streamUs > 0) 'stream=${_ms(streamUs)}',
      if (interpretUs > 0) 'interpret=${_ms(interpretUs)}',
      if (decodeUs > 0) 'decode=${_ms(decodeUs)}',
      if (serializeUs > 0) 'serialize=${_ms(serializeUs)}',
      if (binUs > 0) 'bin=${_ms(binUs)}',
      if (workerUs > 0) 'worker=${_ms(workerUs)}',
      if (queueUs > 0) 'queue=${_ms(queueUs)}',
      if (transferUs > 0) 'transfer=${_ms(transferUs)}',
      if (deserializeUs > 0) 'deserialize=${_ms(deserializeUs)}',
      if (replayUs > 0) 'replay=${_ms(replayUs)}',
      if (rasterizeUs > 0) 'rasterize=${_ms(rasterizeUs)}',
    ];
    return 'page=$pageIndex ${parts.join(' ')} '
        'total=${_ms(endToEndUs)} transcript=${transcriptHit ? 'hit' : 'miss'}';
  }

  @override
  String toString() => 'PdfRenderTrace(${format()})';

  static int _min(int a, int b) => a < b ? a : b;
  static String _ms(int us) => '${(us / 1000).toStringAsFixed(2)}ms';

  /// Captures the VM-measurable, off-thread half of a page render as a single
  /// trace - the one interface that yields an end-to-end per-phase breakdown of
  /// one page without a browser, an isolate, or a raster backend.
  ///
  /// It mirrors exactly what the render worker does off the UI thread: tokenize
  /// the content stream ([parseUs]), interpret it plus the page's annotations
  /// ([interpretUs]), serialize the recorded commands to the wire buffer
  /// ([serializeUs]), then - the main-isolate finish the UI would do - deserialize
  /// that buffer ([deserializeUs]) and replay the commands ([replayUs]). The
  /// two phases that need `dart:ui` (paint into a real canvas and rasterize) are
  /// left 0; a Flutter-hosted probe fills [rasterizeUs].
  ///
  /// [decodeImages] serializes decoded image pixels into the buffer (charging
  /// the pure-Dart decode to [serializeUs], as the worker's serialize step does)
  /// when true; false ships image placeholders for the fast vector-first pass.
  /// Returns null when the page index is out of range or the page's content
  /// can't be serialized (an inline image with page-resource dependencies) - the
  /// same pages the worker declines.
  static PdfRenderTrace? captureOffThread(
    PdfDocument document,
    int pageIndex, {
    bool annotations = true,
    bool decodeImages = false,
  }) {
    if (pageIndex < 0 || pageIndex >= document.pageCount) return null;
    final page = document.page(pageIndex);
    final trace = PdfRenderTrace(pageIndex: pageIndex);
    final perfBefore = PdfPerf.enabled ? PdfPerf.snapshot() : null;
    final clock = Stopwatch()..start();

    final content = page.contentBytes();
    final operations = ContentStreamParser.parse(content);
    trace.parseUs = clock.elapsedMicroseconds;

    clock.reset();
    final recorder = RecordingPdfDevice();
    final interpreter = PdfInterpreter(cos: document.cos, device: recorder)
      ..drawPageOperations(page, operations);
    if (annotations) interpreter.drawAnnotations(page);
    trace.interpretUs = clock.elapsedMicroseconds;

    clock.reset();
    final buffer = serializeCommands(
      recorder.commands,
      cos: document.cos,
      decodeImages: decodeImages,
      imagePlaceholders: !decodeImages,
      compactStateScopes: true,
    );
    trace.serializeUs = clock.elapsedMicroseconds;
    if (buffer == null) return null;

    clock.reset();
    final commands = deserializeCommands(buffer);
    trace.deserializeUs = clock.elapsedMicroseconds;

    clock.reset();
    // Replay the round-tripped commands the way the UI does before handing them
    // to the canvas. Replaying into a recorder walks the whole graph (including
    // soft-mask groups) without needing dart:ui - a faithful CPU proxy for the
    // main-isolate replay phase.
    replayCommands(commands, RecordingPdfDevice());
    trace.replayUs = clock.elapsedMicroseconds;

    if (perfBefore != null) {
      // Attach the COS-layer breakdown as the delta across this capture.
      final delta = PdfPerfStats.empty();
      PdfPerf.snapshot().addInto(delta);
      for (var i = 0; i < delta.phaseUs.length; i++) {
        delta.phaseUs[i] -= perfBefore.phaseUs[i];
        delta.phaseCalls[i] -= perfBefore.phaseCalls[i];
      }
      for (var i = 0; i < delta.counts.length; i++) {
        delta.counts[i] -= perfBefore.counts[i];
      }
      for (var i = 0; i < delta.events.length; i++) {
        delta.events[i] -= perfBefore.events[i];
      }
      trace.cosStats = delta;
    }
    return trace;
  }
}

/// Worker-side accumulator for the off-thread phases of one render job.
///
/// Retained as the name the isolate/worker code writes to; it is now the same
/// type as the unified [PdfRenderTrace] (the worker fills its half of that
/// record). Prefer [PdfRenderTrace] in new code.
typedef PdfWorkerPhaseTimings = PdfRenderTrace;

/// Per-phase upper bounds for a [PdfRenderTrace], in microseconds.
///
/// A budget is a coarse regression tripwire, not a micro-benchmark: set each
/// bound with generous headroom over the observed best-of-N so ordinary CI
/// noise never trips it, but an order-of-magnitude blow-up in any one phase
/// does. A null bound skips that phase. See `test/render_trace_gate_test.dart`.
class PdfRenderPhaseBudget {
  const PdfRenderPhaseBudget({
    this.parseUs,
    this.interpretUs,
    this.serializeUs,
    this.deserializeUs,
    this.replayUs,
    this.endToEndUs,
  });

  final int? parseUs;
  final int? interpretUs;
  final int? serializeUs;
  final int? deserializeUs;
  final int? replayUs;
  final int? endToEndUs;

  /// Human-readable descriptions of every phase in [trace] that overran its
  /// bound, or an empty list when the trace is within budget.
  List<String> exceedances(PdfRenderTrace trace) {
    final over = <String>[];
    void check(String phase, int actual, int? bound) {
      if (bound != null && actual > bound) {
        over.add('$phase ${_ms(actual)} > budget ${_ms(bound)}');
      }
    }

    check('parse', trace.parseUs, parseUs);
    check('interpret', trace.interpretUs, interpretUs);
    check('serialize', trace.serializeUs, serializeUs);
    check('deserialize', trace.deserializeUs, deserializeUs);
    check('replay', trace.replayUs, replayUs);
    check('total', trace.endToEndUs, endToEndUs);
    return over;
  }

  static String _ms(int us) => '${(us / 1000).toStringAsFixed(2)}ms';
}
