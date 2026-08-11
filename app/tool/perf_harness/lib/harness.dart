// ignore_for_file: invalid_use_of_visible_for_testing_member

// Reusable real-world web-performance harness for the dart-pdf viewer/editor.
//
// A standalone Flutter web entrypoint (NOT the shipping app) that fetches a PDF
// over HTTP, mounts the real [PdfViewer]/editing stack, runs one named
// *scenario* workload, and records perf data - so an off-browser driver
// (tool/perf/driver.mjs) can run it headless in real Chrome and get a
// repeatable number. This is the manual `flutter run -d chrome` perf check,
// generalized: one bundle, many workloads, driven entirely from the URL query
// so the prebuilt bundle never needs a rebuild to switch scenario.
//
// Build:  app/tool/perf/build.sh \
//           --dart-define=PDF_PERF_LOG=true
// (tool/perf/build.sh does this for you.)
//
// SCENARIOS (?scenario=<kind>, default `scroll`):
//   scroll  - scroll every page (+ optional zoom-settle + fast-fling pass);
//             frame smoothness and interpret/decode offload. The original
//             workload; its behaviour is byte-for-byte unchanged.
//   open    - cold-open profile: bytes -> PdfDocument.open -> pageCount ->
//             first painted content on a target page (time-to-first-content).
//   search  - full-document text search latency + match count (best-of-N).
//   edit    - apply a batch of annotations (highlight/rectangle/ink) through
//             the real PdfEditingController; incremental-save + appearance-gen
//             cost, revision count, and session-buffer growth.
//   hover   - mouse-move over the page with an editing tool armed: synthetic
//             PointerHoverEvents at frame cadence, measuring the build-phase
//             cost each one provokes (the cursor-overlay work of #403).
//   external - load the real viewer, then expose a deliberately tiny control
//             surface for the Puppeteer PDFium-parity runner. The browser
//             driver performs identical page-jump and zoom journeys against
//             dart-pdf and Chromium's built-in PDF viewer and decides when the
//             run is complete.
//
// Adding a scenario going forward = add one `_drive<Kind>()` method + a `case`
// in `_drive()`, and emit numbers with `_metric(name, value)`. The driver reads
// `window.__perfMetrics()` generically, so NO driver change is needed for a new
// scenario's headline numbers to appear in the summary and the A/B diff.
//
// Tunables (?query, each falling back to a --dart-define default):
//   scenario   scroll|open|search|edit          (default scroll)
//   url        PDF to fetch                      (default /perf.pdf)
//   dwell      scroll: pause on each page, ms    (default 220)
//   maxPages   scroll: cap pages visited, 0=all  (default 0)
//   passes     scroll: full step passes          (default 1)
//   fast       scroll: add a fast-fling pass     (default true)
//   zoom       scroll: zoom-settle cycles/page   (default 0)
//   targetPage open/scroll: page to profile      (default 0 for open)
//   query      search: text to search for        (default "the")
//   repeat     search: best-of-N internal runs   (default 3)
//   ops        edit: annotations to apply        (default 24)
//   events     hover: pointer-hover events        (default 240)
//   tool       hover: armed tool                  (default ink)
//   imageCacheMb  decoded-image cache budget, MB (default 0 = platform default)
//   workerCacheMb retained worker-record budget, MB (default 0 = package default)
//   rasterCacheMb exact full-page raster budget, MB (default 32; 0 disables)
//   previewWindow pages each side eligible for idle preview warming (default 6)
//   domSurface    present page rasters in a DOM canvas (default false)
//   directPicture present bounded retained pictures without toImage (default true)
//   finalFirst    skip bounded intermediate vector raster (default true)
//   outlineBatch  batch adjacent embedded-outline text fills (default true)
//   warmRadius    nearby pages to command/image-warm after ready (default 3)
//   heavyWarm     encoded-content heavy-tail candidate count (default 4)
//   warmImages    include decoded images in command warming (default true)
//   warmHandles   upload warmed images to the platform cache (default false)
//   source        full|range; range uses the public sparse-first HTTP loader
//
// The driver reads these JS globals this installs:
//   window.__perfDone     -> bool, true when the scenario finishes
//   window.__perfError    -> a fatal error string, if the harness threw
//   window.__perfDump()   -> all captured debugPrint/[perf] lines, '\n'-joined
//   window.__perfFrames() -> JSON [{s,b,r,t}] per FrameTiming
//                             (vsync start/build/raster/total milliseconds)
//   window.__perfMetrics() -> JSON {name: number} of this scenario's headline
//                             metrics (the generic surface new scenarios use)
// External mode additionally installs:
//   window.__perfExternalReady / __perfExternalDone
//   window.__perfExternalReadyAt / __perfPageReadyAt(index)
//   window.__perfPageCount() / __perfCurrentPage() / __perfZoom()
//   window.__perfScrollPosition() / __perfScrollToNormalized(fraction)
//   window.__perfBusy() / __perfPageReady(index) / __perfPageVisible(index)
//   window.__perfGoToPage(index) / __perfCenterPage(index)
//   window.__perfSetZoom(scale)
//   window.__perfViewSync() / __perfApplyViewSync(json)
//   window.__perfSearch(query) / __perfSearchBusy() / __perfSearchQuery()
//   window.__perfSearchCount()
//   window.__perfFinish()
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;
import 'dart:ui' show FramePhase;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
// PdfRect isn't in the dart_pdf_editor barrel's `show` list; pull it directly
// (app depends on pdf_document). Only the edit scenario's annotation coords.
import 'package:pdf_document/pdf_document.dart' show PdfRect;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

// ---------------------------------------------------------------------------
// Tunables - read from the URL query string at runtime (so the driver can vary
// them per run without a rebuild), each falling back to a --dart-define default.
// ---------------------------------------------------------------------------
final Map<String, String> _q = Uri.base.queryParameters;

int _qInt(String key, int fallback) => int.tryParse(_q[key] ?? '') ?? fallback;
bool _qBool(String key, bool fallback) {
  final v = _q[key];
  if (v == null) return fallback;
  return v == '1' || v.toLowerCase() == 'true';
}

final String _scenario = (_q['scenario'] ??
        const String.fromEnvironment('PERF_SCENARIO', defaultValue: 'scroll'))
    .toLowerCase();
final String _pdfUrl = _q['url'] ??
    const String.fromEnvironment('PERF_PDF_URL', defaultValue: '/perf.pdf');
final int _dwellMs = _qInt(
    'dwell', const int.fromEnvironment('PERF_DWELL_MS', defaultValue: 220));
final int _maxPages = _qInt(
    'maxPages', const int.fromEnvironment('PERF_MAX_PAGES', defaultValue: 0));
final int _passes =
    _qInt('passes', const int.fromEnvironment('PERF_PASSES', defaultValue: 1));
final bool _fastPass = _qBool(
    'fast', const bool.fromEnvironment('PERF_FAST_PASS', defaultValue: true));
final int _previewIdleMs = _qInt('previewIdleMs', -1);
final int _previewWindow = _qInt('previewWindow', 6);

/// `?targetPage=N`: the page whose first-content paint the `open` scenario
/// times (and, for `scroll`, an alternate single-page target mode). -1 uses a
/// scenario default (0 for `open`).
final int _targetPage = _qInt('targetPage', -1);

/// `?zoom=N`: after each scroll page dwell, run N zoom-in/out settle cycles
/// (1x -> 3x -> 1x via the controller's setZoom, waiting out the viewer's
/// settle debounce between legs) - the pan/zoom-settle workload. 0 = off.
final int _zoomCycles = _qInt('zoom', 0);

/// `?query=` / `?repeat=`: the `search` scenario's needle and best-of-N count.
final String _searchQuery = _q['query'] ??
    const String.fromEnvironment('PERF_QUERY', defaultValue: 'the');
final int _searchRepeat =
    _qInt('repeat', const int.fromEnvironment('PERF_REPEAT', defaultValue: 3));

/// `?ops=`: how many annotations the `edit` scenario applies.
final int _editOps =
    _qInt('ops', const int.fromEnvironment('PERF_OPS', defaultValue: 24));

/// `?events=` / `?tool=`: how many pointer-hover events the `hover` scenario
/// dispatches, and which editing tool is armed while they land (the tools with
/// a painted cursor - ink, eraser, count, stamp - are the interesting ones;
/// `none` arms nothing, for the plain-viewer baseline).
final int _hoverEvents = _qInt(
    'events', const int.fromEnvironment('PERF_EVENTS', defaultValue: 240));
final String _hoverToolName = (_q['tool'] ??
        const String.fromEnvironment('PERF_TOOL', defaultValue: 'ink'))
    .toLowerCase();

/// `?warm=`/`?warmBudgetMb=`/`?warmTarget=`: the `warm` scenario's levers.
/// `warm` is the idle full-raster warm mode - `off` (the control arm),
/// `document`, or `nearby` - `warmBudgetMb` is the exact-raster cache budget
/// the warm gets to fill, and `warmTarget` is the page the run navigates to
/// after idling. The two arms differ only in `warm`, so the A/B is the
/// feature itself (#614).
final String _warmMode = (_q['warm'] ?? 'off').toLowerCase();
final int _warmBudgetMb = _qInt('warmBudgetMb', 1024);
final int _warmWindow = _qInt('warmWindow', 3);
final int _warmIdleMs = _qInt('warmIdleMs', 6000);
final int _warmTarget = _qInt('warmTarget', -1);

/// `?rasterCacheMb=`: exact full-page raster budget for the competitive
/// viewer. Defaults to the package's 32 MiB policy; zero disables retention.
/// This is an A/B diagnostic for presentation/cache pressure, not a hidden
/// scenario default.
final int _rasterCacheMb = _qInt('rasterCacheMb', 32);

/// The warm policy the harness mounts its viewer with.
PdfPageRasterWarmPolicy get _warmPolicy => switch (_warmMode) {
      'document' => const PdfPageRasterWarmPolicy.document(),
      'nearby' => PdfPageRasterWarmPolicy.nearby(window: _warmWindow),
      _ => const PdfPageRasterWarmPolicy.disabled(),
    };

/// Decoded-image cache budget, MB. 0 leaves the platform default in place; the
/// driver sweeps it to measure what each budget costs a real tab (issue #281).
final int _imageCacheMb = _qInt('imageCacheMb', 0);

/// Retained worker command-buffer budget, MB. Zero keeps the package default.
/// This isolates CPU transcript retention from the decoded engine-image cache:
/// the real-world memory journey can reduce one without accidentally making
/// every navigation re-upload image pixels.
final int _workerCacheMb = _qInt('workerCacheMb', 0);

/// `?worker=N`: render-worker pool size; `?worker=0` disables the web render
/// worker entirely (`pdfRenderWorkerScriptUrl = null`), forcing every page -
/// interpret AND image decode - onto the main thread. That is the only way to
/// A/B the main-thread `_decodeOne` DCT path on desktop (#458's browser-JPEG
/// fallback): with the worker on, DCT images decode off-thread and the main
/// path never runs. Defaults to the production web policy so the parity
/// harness measures the configuration users actually get; `?worker=N` remains
/// the explicit fixed-pool experiment seam.
final int _workerPool = _qInt('worker', 1);

/// `?perGlyph=1` turns on per-glyph substituted-text composition (#454) so the
/// same build can A/B it: `?perGlyph=0` turns it OFF (whole-run shaping) - watch
/// the interpret line's `replay=`/`shape=` on `scroll-cad-labels`. Default on,
/// matching the app.
final bool _perGlyph = _qBool('perGlyph', true);

// ---------------------------------------------------------------------------
// Capture: every debugPrint line + every frame's timing + scenario metrics.
// ---------------------------------------------------------------------------
final List<String> _lines = <String>[];
final List<FrameTiming> _frames = <FrameTiming>[];
final Map<String, num> _metrics = <String, num>{};

void _record(String line) {
  _lines.add(line);
  // Mirror to the real console too, so a headful run / page.on('console') can
  // watch live. Guarded - console must exist in a browser.
  _consoleLog(line.toJS);
}

/// Publish one scenario metric. It lands in `window.__perfMetrics()` (the
/// generic surface the driver parses) AND as a trace line (so a headful run and
/// the raw dump show it too). New scenarios only need to call this.
void _metric(String name, num value) {
  _metrics[name] = value;
  _record('[perf.metric] $name=$value');
}

@JS('console.log')
external void _consoleLog(JSAny? msg);

@JS('performance.now')
external double _browserPerformanceNow();

@JS('performance.timeOrigin')
external double get _browserPerformanceTimeOrigin;

double _browserEpochNow() =>
    _browserPerformanceTimeOrigin + _browserPerformanceNow();

@JS('fetch')
external JSPromise<_FetchResponse> _fetch(String url);

extension type _FetchResponse(JSObject _) implements JSObject {
  external int get status;
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

Future<Uint8List> _loadPdf(String url) async {
  final prefetched = globalContext.getProperty('__perfPdfBytesPromise'.toJS);
  if (prefetched != null) {
    try {
      final buffer = await (prefetched as JSPromise<JSArrayBuffer>).toDart;
      return buffer.toDart.asUint8List();
    } catch (_) {
      // The pre-Flutter surface is strictly opportunistic. Its fetch or worker
      // may fail while the ordinary harness fetch still succeeds.
    }
  }
  final resp = await _fetch(url).toDart;
  if (resp.status != 200) {
    throw StateError('GET $url -> HTTP ${resp.status}');
  }
  final buffer = await resp.arrayBuffer().toDart;
  return buffer.toDart.asUint8List();
}

String _framesJson() {
  final out = _frames
      .map((t) => {
            's': t.timestampInMicroseconds(FramePhase.vsyncStart) / 1000.0,
            'b': t.buildDuration.inMicroseconds / 1000.0,
            'r': t.rasterDuration.inMicroseconds / 1000.0,
            't': t.totalSpan.inMicroseconds / 1000.0,
          })
      .toList();
  return jsonEncode(out);
}

void _setGlobal(String name, JSAny? value) =>
    globalContext.setProperty(name.toJS, value);

void main() {
  // The binding must exist before we touch SchedulerBinding.instance.
  WidgetsFlutterBinding.ensureInitialized();

  // Turn on the engine's perf trace and redirect ALL of it into our buffer.
  // Reassigning debugPrint (a mutable foundation global) captures every
  // PdfPerfLog line without the console throttle dropping any under load.
  PdfPerfLog.enabled = true;
  if (_workerCacheMb > 0) {
    pdfRenderWorkerCacheBudgetBytes = _workerCacheMb * 1024 * 1024;
  }
  if (_workerPool <= 0) {
    // Worker off: everything renders on the main thread. #458's A/B lever.
    pdfRenderWorkerScriptUrl = null;
  } else {
    pdfRenderWorkerScriptUrl = 'pdf_render_worker.dart.js';
    pdfRenderWorkerPoolSize = _workerPool;
  }
  _record('[perf] HARNESS workerPool=$_workerPool');
  _record('[perf] HARNESS workerCacheBudget='
      '${pdfRenderWorkerCacheBudgetBytes ~/ (1024 * 1024)}MB');
  CanvasPdfDevice.perGlyphSubstitutedText = _perGlyph;
  _record('[perf] HARNESS perGlyph=$_perGlyph');
  CanvasPdfDevice.batchEmbeddedTextOutlines = _qBool(
    'outlineBatch',
    CanvasPdfDevice.batchEmbeddedTextOutlines,
  );
  _record('[perf] HARNESS outlineBatch='
      '${CanvasPdfDevice.batchEmbeddedTextOutlines}');
  // `?progressive=1`: light up the #564 progressive top-down reveal (the
  // vector-first record streams growing linework prefixes into the preview),
  // so an `open` A/B can measure its first-content win vs the bounded prefix.
  PdfPageView.progressiveStreamingPaint = _qBool(
    'progressive',
    PdfPageView.progressiveStreamingPaint,
  );
  _record(
      '[perf] HARNESS progressive=${PdfPageView.progressiveStreamingPaint}');
  // `?fused=0`: restore the two-record vector-then-image path for an A/B.
  // Production defaults to one decoding record serving both paints.
  PdfPageView.fusedProgressiveRecord = _qBool('fused', true);
  _record('[perf] HARNESS fused=${PdfPageView.fusedProgressiveRecord}');
  // `?earlyPrefixMin=<bytes>`: lower the density gate that both the #527 bounded
  // early prefix and the #564 reveal share, so a portable-corpus page that sits
  // just under the 512 KB production default still engages both - letting the
  // A/B compare them on the same page. 0 leaves the default.
  final earlyMin = _qInt('earlyPrefixMin', 0);
  if (earlyMin > 0) PdfPageView.earlyPrefixMinContentBytes = earlyMin;
  _record('[perf] HARNESS earlyPrefixMin='
      '${PdfPageView.earlyPrefixMinContentBytes}');
  final localFirstMax = _qInt('localFirstMax', -1);
  if (localFirstMax >= 0) {
    PdfPageView.webLocalFirstPaintMaxRawContentBytes = localFirstMax;
  }
  _record('[perf] HARNESS localFirstMax='
      '${PdfPageView.webLocalFirstPaintMaxRawContentBytes}');
  PdfPageView.webDomRasterPresentation = _qBool('domSurface', false);
  _record('[perf] HARNESS domSurface='
      '${PdfPageView.webDomRasterPresentation}');
  PdfPageView.directPicturePresentation = _qBool(
    'directPicture',
    PdfPageView.directPicturePresentation,
  );
  _record('[perf] HARNESS directPicture='
      '${PdfPageView.directPicturePresentation}');
  // Dense-page strip replay is cross-platform (web plus supported Impeller
  // backends) and materially changes both CAD settle time and retained command
  // memory. Keep a harness-only A/B seam so real-document runs can prove the
  // tradeoff before production defaults move.
  PdfPageView.stripZoomReplay = _qBool(
    'stripZoom',
    PdfPageView.stripZoomReplay,
  );
  _record('[perf] HARNESS stripZoom=${PdfPageView.stripZoomReplay}');
  PdfPageView.retainedZoomReplay = _qBool(
    'retainedReplay',
    PdfPageView.retainedZoomReplay,
  );
  _record('[perf] HARNESS retainedReplay=${PdfPageView.retainedZoomReplay}');
  PdfPageView.retainDenseScenesOffFocus = _qBool(
    'denseScenesOffFocus',
    PdfPageView.retainDenseScenesOffFocus,
  );
  _record('[perf] HARNESS denseScenesOffFocus='
      '${PdfPageView.retainDenseScenesOffFocus}');
  PdfPageView.prioritizeBoundedFinalPicture = _qBool(
    'finalFirst',
    PdfPageView.prioritizeBoundedFinalPicture,
  );
  _record('[perf] HARNESS finalFirst='
      '${PdfPageView.prioritizeBoundedFinalPicture}');
  PdfViewer.speculativePageWarmRadius = _qInt(
    'warmRadius',
    PdfViewer.speculativePageWarmRadius,
  );
  _record('[perf] HARNESS warmRadius='
      '${PdfViewer.speculativePageWarmRadius}');
  PdfViewer.speculativeSerialWarmMaxPages = _qInt(
    'serialWarmMaxPages',
    PdfViewer.speculativeSerialWarmMaxPages,
  );
  _record('[perf] HARNESS serialWarmMaxPages='
      '${PdfViewer.speculativeSerialWarmMaxPages}');
  PdfViewer.speculativeHeavyPageWarmCount = _qInt(
    'heavyWarm',
    PdfViewer.speculativeHeavyPageWarmCount,
  );
  _record('[perf] HARNESS heavyWarm='
      '${PdfViewer.speculativeHeavyPageWarmCount}');
  PdfViewer.speculativePageWarmImages = _qBool(
    'warmImages',
    PdfViewer.speculativePageWarmImages,
  );
  _record('[perf] HARNESS warmImages='
      '${PdfViewer.speculativePageWarmImages}');
  PdfViewer.speculativePageWarmPlatformImages = _qBool(
    'warmHandles',
    PdfViewer.speculativePageWarmPlatformImages,
  );
  _record('[perf] HARNESS warmHandles='
      '${PdfViewer.speculativePageWarmPlatformImages}');
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) _record(message);
  };
  final isolated =
      (globalContext['crossOriginIsolated'] as JSBoolean?)?.toDart ?? false;
  _record('[perf] HARNESS scenario=$_scenario crossOriginIsolated=$isolated');
  if (_imageCacheMb > 0) {
    PdfImageCache.instance.maxBytes = _imageCacheMb * 1024 * 1024;
  }
  _record('[perf] HARNESS imageCacheBudget='
      '${PdfImageCache.instance.maxBytes ~/ (1024 * 1024)}MB');
  // The driver samples this alongside the tab's memory, so a run can show the
  // cache's own occupancy against the agent total it drives.
  _setGlobal(
      '__perfImageCacheBytes', (() => PdfImageCache.instance.bytes).toJS);

  // Expose the driver's read surface up front (so a poll never races startup).
  _setGlobal('__perfDone', false.toJS);
  _setGlobal('__perfError', null);
  _setGlobal('__perfScenario', _scenario.toJS);
  _setGlobal('__perfDump', (() => _lines.join('\n').toJS).toJS);
  _setGlobal('__perfFrames', (() => _framesJson().toJS).toJS);
  _setGlobal('__perfMetrics', (() => jsonEncode(_metrics).toJS).toJS);

  // Record every frame's timing (not just jank) so the driver can compute
  // p50/p95/max build times over the whole run.
  SchedulerBinding.instance.addTimingsCallback(_frames.addAll);

  runApp(const _PerfHarnessApp());
}

class _PerfHarnessApp extends StatefulWidget {
  const _PerfHarnessApp();

  @override
  State<_PerfHarnessApp> createState() => _PerfHarnessAppState();
}

class _PerfHarnessAppState extends State<_PerfHarnessApp> {
  final PdfViewerController _viewer = PdfViewerController();
  PdfDocument? _document;
  PdfRenderWorker? _worker;
  PdfHttpByteSource? _source;
  PdfEditingController? _editing;
  String? _error;
  bool _externalDone = false;
  bool _fullyLoaded = false;
  double _fullyLoadedAt = -1;
  int _sourceBytesReceived = 0;
  int _sourceSparseBytes = 0;
  bool _showingSparseSource = false;

  /// Both scenarios that touch the editor mount the editing stack.
  bool get _isEdit => _scenario == 'edit' || _scenario == 'hover';

  @override
  void initState() {
    super.initState();
    _setGlobal('__perfFullyLoaded', (() => _fullyLoaded.toJS).toJS);
    _setGlobal('__perfFullyLoadedAt', (() => _fullyLoadedAt.toJS).toJS);
    _setGlobal(
        '__perfSourceBytesReceived', (() => _sourceBytesReceived.toJS).toJS);
    _setGlobal('__perfSourceSparseBytes', (() => _sourceSparseBytes.toJS).toJS);
    if (_qBool('deferStart', false)) {
      // Competitive document-open runs start from a live viewer application,
      // not from Flutter/SkWasm process bootstrap. The driver first captures
      // the loading shell (an actual compositor boundary), then calls this
      // one-shot trigger. Navigation remains a separate cold-app diagnostic;
      // the first request is the comparable document-open boundary.
      var started = false;
      _setGlobal(
          '__perfStartDocument',
          (() {
            if (started) return;
            started = true;
            unawaited(_start());
          }).toJS);
    } else {
      unawaited(_start());
    }
  }

  Future<void> _start() async {
    // #450 A/B: warm the render worker up front (web: fetch + compile + boot the
    // worker script) so that cost overlaps the PDF load + parse instead of
    // blocking the first render. Gated on ?prewarm so one bundle measures both
    // arms - default on (matches the app), `?prewarm=0` for the baseline.
    if (_q['prewarm'] != '0') {
      PdfRenderWorker.prewarm();
    }
    // Cold-open stopwatch: covers fetch + parse + worker start + first paint,
    // exactly what a user waits through. Legal here - the harness is tool code,
    // not lib/ (the no-Stopwatch-in-lib rule is about shipping paths).
    final coldOpen = Stopwatch()..start();
    try {
      // First-content timing for `open` is computed driver-side from the
      // PdfPerfLog `[perf <ms>]` timestamps: the target page's first paint is
      // logged in the render-WORKER isolate, which never reaches this isolate's
      // captured lines - only the browser console the driver reads. Emit the
      // same start marker the driver's target machinery keys on, as early as
      // possible so the measured span is a true cold open.
      if (_scenario == 'open') {
        PdfPerfLog.log(
            'HARNESS TARGET start page=${_targetPage < 0 ? 0 : _targetPage}');
      }
      _record('[perf] HARNESS load url=$_pdfUrl');
      if (_q['source'] == 'range' && !_isEdit) {
        await _startRanged(coldOpen);
        return;
      }
      final bytes = await _loadPdf(_pdfUrl);
      _metric('openBytesMs', coldOpen.elapsedMicroseconds / 1000.0);
      _record('[perf] HARNESS loaded bytes=${bytes.length}');
      if (_isEdit) {
        // The edit scenario mounts the editing stack: PdfViewer(editing:) owns
        // the revision buffer and re-renders as annotations land. No render
        // worker - revisions would stale a worker started on the original.
        final editing = PdfEditingController(bytes);
        setState(() => _editing = editing);
      } else {
        final document = PdfDocument.open(bytes);
        _metric('openDocMs', coldOpen.elapsedMicroseconds / 1000.0);
        final worker = PdfRenderWorker.start(bytes);
        setState(() {
          _document = document;
          _worker = worker;
        });
      }
      _fullyLoaded = true;
      _fullyLoadedAt = _browserEpochNow();
      unawaited(_drive(coldOpen));
    } catch (e, st) {
      _record('[perf] HARNESS ERROR $e');
      _setGlobal('__perfError', '$e\n$st'.toJS);
      _setGlobal('__perfDone', true.toJS);
      setState(() => _error = '$e');
    }
  }

  /// Opens page one from the public HTTP Range path, then completes the file
  /// in the background exactly as [PdfReader.source] does. External mode is
  /// exposed as soon as the sparse document can render; the Puppeteer driver
  /// observes that first visual, then waits on [__perfFullyLoaded] before it
  /// starts actions that may touch pages outside the sparse closure.
  Future<void> _startRanged(Stopwatch coldOpen) async {
    final source = PdfHttpByteSource(
      Uri.base.resolve(_pdfUrl),
      onProgress: (received, _) => _sourceBytesReceived = received,
    );
    _source = source;
    var sparseFetched = 0;
    final first = await PdfDocument.openSource(
      source,
      options: PdfSourceLoadOptions(
        firstPaintPages: 1,
        completeFirstPaintPageTree: false,
        onProgress: (fetched, _) => sparseFetched = fetched,
      ),
    );
    _sourceSparseBytes = sparseFetched;
    _metric('openSourceSparseBytes', sparseFetched);
    _metric('openDocMs', coldOpen.elapsedMicroseconds / 1000.0);
    _record('[perf] HARNESS ranged first-paint sparse=$sparseFetched '
        'buffer=${first.cos.bytes.length}');
    setState(() {
      _document = first;
      _worker = null;
      _showingSparseSource = true;
    });
    unawaited(_drive(coldOpen));
    unawaited(_completeRanged(source, coldOpen));
  }

  Future<void> _completeRanged(
      PdfHttpByteSource source, Stopwatch coldOpen) async {
    try {
      final bytes = await readSourceFully(source);
      if (!mounted || !identical(_source, source)) return;
      // Do not let an immediately available full body steal the first frame
      // from the sparse document. Its first page is intentionally rendered
      // locally (small closure, no worker hand-off); once that real raster is
      // visible, start the pooled worker over the complete immutable bytes.
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (mounted &&
          !_viewer.isPageRasterReady(0) &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 8));
      }
      if (!mounted || !identical(_source, source)) return;
      // Raster-ready means the image exists, not that the browser compositor
      // has presented it. Keep the sparse page alive for several frame
      // boundaries before the full worker's SharedArrayBuffer copy occupies
      // the UI isolate. This mirrors PdfProgressiveSourceBuilder's production
      // handoff and lets the benchmark observe the same first paint a user sees.
      for (var frame = 0; frame < 4; frame++) {
        await SchedulerBinding.instance.endOfFrame;
        if (!mounted || !identical(_source, source)) return;
      }
      final document = PdfDocument.open(bytes);
      final worker = PdfRenderWorker.start(bytes);
      final oldWorker = _worker;
      setState(() {
        _document = document;
        _worker = worker;
        _showingSparseSource = false;
      });
      _fullyLoaded = true;
      _fullyLoadedAt = _browserEpochNow();
      _metric('openBytesMs', coldOpen.elapsedMicroseconds / 1000.0);
      _metric('openSourceTotalBytes', _sourceBytesReceived);
      _record('[perf] HARNESS ranged full bytes=${bytes.length} '
          'received=$_sourceBytesReceived');
      // Let the viewer bind to the replacement before retiring the sparse
      // worker; an in-flight first-page paint may still own it this frame.
      WidgetsBinding.instance.addPostFrameCallback((_) => oldWorker?.dispose());
    } catch (error, stack) {
      if (!mounted || !identical(_source, source)) return;
      _record('[perf] HARNESS ranged completion ERROR $error');
      _setGlobal('__perfError', '$error\n$stack'.toJS);
    }
  }

  /// Wait for the page tree to resolve so pageCount is real.
  Future<int> _awaitPageCount(Stopwatch coldOpen) async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (_viewer.pageCount <= 0 && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final count = _viewer.pageCount;
    _metric('openPageCountMs', coldOpen.elapsedMicroseconds / 1000.0);
    _record('[perf] HARNESS pageCount=$count');
    return count;
  }

  Future<void> _drive(Stopwatch coldOpen) async {
    try {
      switch (_scenario) {
        case 'external':
          await _driveExternal(coldOpen);
        case 'open':
          await _driveOpen(coldOpen);
        case 'search':
          await _driveSearch(coldOpen);
        case 'edit':
          await _driveEdit(coldOpen);
        case 'hover':
          await _driveHover(coldOpen);
        case 'warm':
          await _driveWarm(coldOpen);
        case 'scroll':
        default:
          await _driveScroll(coldOpen);
      }
    } catch (e, st) {
      _record('[perf] HARNESS DRIVE ERROR $e');
      _setGlobal('__perfError', '$e\n$st'.toJS);
    } finally {
      // Settle so trailing prerenders/decodes land in the trace.
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      _metric('frames', _frames.length);
      _metric(
          'textLayoutCacheEntries', CanvasPdfDevice.debugTextLayoutCacheLength);
      _metric('glyphLayoutCacheEntries',
          CanvasPdfDevice.debugGlyphLayoutCacheLength);
      _record('[perf] HARNESS DONE scenario=$_scenario '
          'frames=${_frames.length} lines=${_lines.length}');
      _setGlobal('__perfDone', true.toJS);
    }
  }

  // ----- external: common Puppeteer journey for PDFium parity --------------
  //
  // Keep this surface intentionally small. It exposes user-level viewer
  // operations, not renderer internals, so the competitive runner can drive
  // the same actions in both engines and judge the same visible result. The
  // callback argument/return types stay JS-native because dart2js callbacks
  // exported with `toJS` cannot rely on implicit number conversion.
  Future<void> _driveExternal(Stopwatch coldOpen) async {
    final count = await _awaitPageCount(coldOpen);
    if (count <= 0) throw StateError('pageCount never became positive');

    _setGlobal('__perfPageCount', (() => _viewer.pageCount.toJS).toJS);
    _setGlobal('__perfCurrentPage', (() => _viewer.currentPage.toJS).toJS);
    _setGlobal('__perfZoom', (() => _viewer.zoom.toJS).toJS);
    _setGlobal('__perfScrollPosition',
        (() => (_viewer.scrollMetrics?.position ?? -1.0).toJS).toJS);
    _setGlobal('__perfBusy', (() => _viewer.isPageRenderBusy.toJS).toJS);
    _setGlobal(
        '__perfPageVisible',
        ((JSNumber rawPage) =>
            (_viewer.visiblePageRegion(rawPage.toDartInt) != null).toJS).toJS);
    _setGlobal(
        '__perfPageReady',
        ((JSNumber rawPage) =>
            _viewer.isPageRasterReady(rawPage.toDartInt).toJS).toJS);
    // Keep the instant of each false -> true readiness transition in the
    // page's own monotonic clock. Full compositor screenshots can occupy CDP
    // long enough to delay the driver's evaluate() poll by hundreds of
    // milliseconds; returning the historical timestamp prevents that
    // instrumentation delay from becoming fake renderer latency.
    final pageReadyAt = <int, double>{};
    final wasPageReady = <int, bool>{};
    void recordPageReadiness() {
      final now = _browserEpochNow();
      for (var page = 0; page < _viewer.pageCount; page++) {
        final ready = _viewer.isPageRasterReady(page);
        if (ready && wasPageReady[page] != true) pageReadyAt[page] = now;
        wasPageReady[page] = ready;
      }
    }

    _viewer.pageRenderActivity.addListener(recordPageReadiness);
    recordPageReadiness();
    _setGlobal(
        '__perfPageReadyAt',
        ((JSNumber rawPage) => (pageReadyAt[rawPage.toDartInt] ?? -1.0).toJS)
            .toJS);
    _setGlobal('__perfSearchBusy', (() => _viewer.isSearching.toJS).toJS);
    _setGlobal('__perfSearchQuery', (() => _viewer.query.toJS).toJS);
    _setGlobal('__perfSearchCount', (() => _viewer.matchCount.toJS).toJS);
    _setGlobal(
        '__perfGoToPage',
        ((JSNumber rawPage) {
          final page = rawPage.toDartInt.clamp(0, _viewer.pageCount - 1);
          // Chromium's viewport.goToPage() snaps. Use the public zero-duration
          // path here so the common metric compares render/presentation work,
          // not DartPDF's optional 250ms near-page animation against an
          // instantaneous PDFium command.
          unawaited(_viewer.animateToPage(page, duration: Duration.zero));
        }).toJS);
    _setGlobal(
        '__perfCenterPage',
        ((JSNumber rawPage) {
          final page = rawPage.toDartInt.clamp(0, _viewer.pageCount - 1);
          // Correctness captures need both independent tabs looking at the
          // same page region. A full-crop showRect keeps the current zoom (the
          // API never zooms out) while centering the destination.
          unawaited(_viewer.showRect(page, _document!.page(page).cropBox));
        }).toJS);
    _setGlobal(
        '__perfSetZoom',
        ((JSNumber rawZoom) {
          _viewer.setZoom(rawZoom.toDartDouble);
        }).toJS);
    _setGlobal(
        '__perfScrollToNormalized',
        ((JSNumber rawPosition) {
          _viewer.jumpToNormalized(rawPosition.toDartDouble);
        }).toJS);
    _setGlobal(
        '__perfViewSync',
        (() {
          final sync = _viewer.viewSync;
          if (sync == null) return ''.toJS;
          return jsonEncode(<String, Object>{
            'scrollPixels': sync.scrollPixels,
            'layoutZoom': sync.layoutZoom,
            'transform': sync.transform.storage.toList(growable: false),
          }).toJS;
        }).toJS);
    _setGlobal(
        '__perfApplyViewSync',
        ((JSString rawSync) {
          final value = jsonDecode(rawSync.toDart) as Map<String, dynamic>;
          final transform = (value['transform'] as List<dynamic>)
              .map((entry) => (entry as num).toDouble())
              .toList(growable: false);
          if (transform.length != 16) {
            throw FormatException(
                'view-sync transform needs 16 entries, got ${transform.length}');
          }
          _viewer.applyViewSync(PdfViewSync(
            scrollPixels: (value['scrollPixels'] as num).toDouble(),
            layoutZoom: (value['layoutZoom'] as num).toDouble(),
            transform: Matrix4.fromList(transform),
          ));
        }).toJS);
    _setGlobal(
        '__perfSearch',
        ((JSString rawQuery) {
          unawaited(_viewer.search(rawQuery.toDart));
        }).toJS);
    _setGlobal(
        '__perfFinish',
        (() {
          _externalDone = true;
          _setGlobal('__perfExternalDone', true.toJS);
        }).toJS);
    _setGlobal('__perfExternalDone', false.toJS);
    _setGlobal('__perfExternalReadyAt', _browserEpochNow().toJS);
    _setGlobal('__perfExternalReady', true.toJS);
    _record('[perf] HARNESS EXTERNAL ready pages=$count');

    try {
      final deadline = DateTime.now().add(const Duration(minutes: 10));
      while (!_externalDone && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      if (!_externalDone) {
        throw StateError('external driver did not call __perfFinish()');
      }
      _metric('externalPages', count);
    } finally {
      _viewer.pageRenderActivity.removeListener(recordPageReadiness);
    }
  }

  // ----- scroll: the original workload, behaviour unchanged ------------------
  Future<void> _driveScroll(Stopwatch coldOpen) async {
    final count = await _awaitPageCount(coldOpen);
    if (count <= 0) {
      throw StateError('pageCount never became positive');
    }
    // Let the first visible page interpret before we start moving.
    await Future<void>.delayed(const Duration(milliseconds: 1500));

    final last = _maxPages > 0 ? (_maxPages.clamp(1, count)) : count;

    for (var pass = 0; pass < _passes; pass++) {
      _record('[perf] HARNESS PASS step $pass/$_passes pages=$last '
          'zoomCycles=$_zoomCycles');
      for (var i = 0; i < last; i++) {
        await _viewer.jumpToPage(i); // animates ~250ms
        await Future<void>.delayed(Duration(milliseconds: _dwellMs));
        for (var z = 0; z < _zoomCycles; z++) {
          _record('[perf] HARNESS ZOOM page=$i cycle=$z in');
          _viewer.setZoom(3);
          // Outwait the viewer's 200ms settle debounce plus refine headroom,
          // so the sharp re-raster (the settle cost being measured) lands
          // inside this window's frame timings.
          await Future<void>.delayed(const Duration(milliseconds: 600));
          _record('[perf] HARNESS ZOOM page=$i cycle=$z out');
          _viewer.setZoom(1);
          await Future<void>.delayed(const Duration(milliseconds: 600));
        }
      }
    }

    if (_fastPass && last > 8) {
      // A coarse, fast sweep to stress the velocity hold / preview path:
      // big strides, almost no dwell, forward then back.
      _record('[perf] HARNESS PASS fast pages=$last');
      final stride = (last / 12).ceil().clamp(1, last);
      for (var i = 0; i < last; i += stride) {
        await _viewer.jumpToPage(i);
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      for (var i = last - 1; i >= 0; i -= stride) {
        await _viewer.jumpToPage(i);
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
    }
    _metric('pagesVisited', last);
  }

  // ----- warm: idle full-raster warm, then arrive on a far page (#614) ------
  //
  // Both arms run the identical script; only `?warm=` differs. The number that
  // matters is `warmArriveMs` - wall time from asking for a far page to that
  // page's sharp raster being on screen - and it is only meaningful next to the
  // control arm's, so run this through `tool/perf.sh webdiff` or compare the
  // `warm-*-off` / `warm-*-document` scenarios.
  Future<void> _driveWarm(Stopwatch coldOpen) async {
    final count = await _awaitPageCount(coldOpen);
    if (count <= 0) throw StateError('pageCount never became positive');
    final target =
        (_warmTarget < 0 ? count - 1 : _warmTarget).clamp(0, count - 1);
    _record('[perf] HARNESS WARM mode=$_warmMode budgetMb=$_warmBudgetMb '
        'idleMs=$_warmIdleMs target=$target');
    // Idle. This is the whole point: the viewer is doing nothing a user asked
    // for, and the warm either uses that time or does not.
    await Future<void>.delayed(Duration(milliseconds: _warmIdleMs));
    final warmed = _viewer.pageRasterWarmStats;
    if (warmed != null) {
      _metric('warmAttempts', warmed.attempts);
      _metric('warmCompletions', warmed.completions);
      _metric('warmRejected', warmed.rejected);
      _metric('warmPreempted', warmed.preempted);
      _metric('warmRetainedMb', warmed.retainedBytes / (1 << 20));
      _metric('warmEvictions', warmed.evictions);
    }

    // Arrive. A warmed page restores its raster synchronously; an unwarmed one
    // interprets and reads back first, which is the difference being measured.
    final arrive = Stopwatch()..start();
    await _viewer.jumpToPage(target);
    // Poll for the sharp raster rather than sleeping a fixed time: the control
    // arm's cost is exactly what we must not average away.
    for (var i = 0; i < 200; i++) {
      final stats = _viewer.pageRasterWarmStats;
      if (stats != null && stats.hits > (warmed?.hits ?? 0)) break;
      if (!_viewer.isPageRenderBusy && i > 2) break;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    arrive.stop();
    _metric('warmArriveMs', arrive.elapsedMicroseconds / 1000.0);
    final after = _viewer.pageRasterWarmStats;
    if (after != null) {
      _metric('warmHits', after.hits);
      _metric('warmMisses', after.misses);
    }
    await Future<void>.delayed(const Duration(milliseconds: 800));
  }

  // ----- open: cold-open profile; first-content is computed driver-side ------
  Future<void> _driveOpen(Stopwatch coldOpen) async {
    final count = await _awaitPageCount(coldOpen);
    if (count <= 0) throw StateError('pageCount never became positive');
    final target = (_targetPage < 0 ? 0 : _targetPage).clamp(0, count - 1);
    _record('[perf] HARNESS OPEN target=$target');
    // The `HARNESS TARGET start` marker was emitted in _start(); page 0 renders
    // on its own, deeper targets need a jump. The driver reads the first-paint
    // timestamp off the trace and reports openFirstContentMs.
    if (target != 0) unawaited(_viewer.jumpToPage(target));
    // Let first content + refinement land in the trace before we finish.
    await Future<void>.delayed(const Duration(milliseconds: 2500));
  }

  // ----- search: full-document text search latency + match count ------------
  Future<void> _driveSearch(Stopwatch coldOpen) async {
    final count = await _awaitPageCount(coldOpen);
    if (count <= 0) throw StateError('pageCount never became positive');
    // Let the first page settle so search doesn't race initial layout.
    await Future<void>.delayed(const Duration(milliseconds: 800));
    _record(
        '[perf] HARNESS SEARCH query="$_searchQuery" repeat=$_searchRepeat');
    var bestMs = double.infinity;
    var matches = 0;
    for (var r = 0; r < _searchRepeat.clamp(1, 20); r++) {
      _viewer.clearSearch();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final sw = Stopwatch()..start();
      await _viewer.search(_searchQuery);
      sw.stop();
      final ms = sw.elapsedMicroseconds / 1000.0;
      matches = _viewer.matchCount;
      _record('[perf] HARNESS SEARCH run=$r ${ms.toStringAsFixed(1)}ms '
          'matches=$matches');
      if (ms < bestMs) bestMs = ms;
    }
    // Best-of-N within the run, matching the suite's timing convention.
    _metric('searchMs', bestMs.isFinite ? bestMs : 0);
    _metric('searchMatches', matches);
  }

  // ----- edit: apply a batch of annotations through the real controller -----
  Future<void> _driveEdit(Stopwatch coldOpen) async {
    final count = await _awaitPageCount(coldOpen);
    if (count <= 0) throw StateError('pageCount never became positive');
    final editing = _editing!;
    // Let the first page paint before we start mutating.
    await Future<void>.delayed(const Duration(milliseconds: 800));
    final ops = _editOps.clamp(1, 500);
    _record('[perf] HARNESS EDIT ops=$ops pages=$count');
    final bufferBefore = editing.sessionBufferBytes;
    final revBefore = editing.revisionCount;

    final apply = Stopwatch()..start();
    var applied = 0;
    for (var i = 0; i < ops; i++) {
      final page = i % count;
      switch (i % 3) {
        case 0:
          // Highlight: one synthetic quad. Appearance-stream generation cost is
          // coordinate-independent, so fixed low coords are fine for any page.
          editing.addMarkup(
            PdfMarkupKind.highlight,
            {
              page: [PdfRect(72, 100 + (i % 5) * 22, 320, 118 + (i % 5) * 22)],
            },
          );
        case 1:
          editing.addRectangle(page, const PdfRect(72, 200, 320, 260));
        case 2:
          editing.addInkStroke(page, const [
            (72, 300),
            (120, 340),
            (180, 300),
            (240, 350),
            (320, 300),
          ]);
          editing.finishInk();
      }
      applied++;
      // Yield so the viewer can re-render the new revision between ops (the
      // real interactive cadence, and it lets FrameTiming capture the repaint).
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    apply.stop();

    final applyMs = apply.elapsedMicroseconds / 1000.0;
    _metric('editApplyMs', applyMs);
    _metric('editApplyMsPerOp', applyMs / applied);
    _metric('editRevisions', editing.revisionCount - revBefore);
    _metric('editBufferGrowthKb',
        (editing.sessionBufferBytes - bufferBefore) / 1024.0);
    _record('[perf] HARNESS EDIT applied=$applied '
        'buffer=${editing.sessionBufferBytes}B revisions=${editing.revisionCount}');
    // Let the last repaint settle.
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  // ----- hover: what a mouse-move costs with an editing tool armed ---------
  //
  // The workload behind #403: with ink/eraser/count/stamp armed the overlay
  // paints its own cursor, and every pointer-hover event has to move it. The
  // question this answers is whether that move costs a *rebuild* of the
  // overlay subtree or a repaint of one small layer, and the frame timings
  // captured across the hover window answer it directly - build-phase ms is
  // the rebuild, raster ms is the repaint.
  Future<void> _driveHover(Stopwatch coldOpen) async {
    final count = await _awaitPageCount(coldOpen);
    if (count <= 0) throw StateError('pageCount never became positive');
    final editing = _editing!;
    // Let the first page paint before the pointer starts moving over it.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    // A typo'd ?tool= must not quietly arm nothing and then report numbers for
    // a workload that never happened - only the explicit 'none' disarms.
    editing.tool = switch (_hoverToolName) {
      'ink' => PdfEditTool.ink,
      'eraser' => PdfEditTool.eraser,
      'count' => PdfEditTool.count,
      'stamp' => PdfEditTool.stamp,
      'select' => PdfEditTool.select,
      'none' => null,
      _ => throw StateError('unknown ?tool=$_hoverToolName '
          '(ink|eraser|count|stamp|select|none)'),
    };
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final view = WidgetsBinding.instance.platformDispatcher.implicitView!;
    final size = view.physicalSize / view.devicePixelRatio;
    final center = Offset(size.width / 2, size.height / 2);
    // a circle well inside the page, so every event lands on the overlay
    final radius = math.min(size.width, size.height) * 0.22;
    final events = _hoverEvents.clamp(1, 4000);
    _record('[perf] HARNESS HOVER tool=$_hoverToolName events=$events '
        'view=${size.width.toStringAsFixed(0)}x${size.height.toStringAsFixed(0)}');

    const device = 77; // any id the engine won't also be using
    GestureBinding.instance.handlePointerEvent(PointerAddedEvent(
        position: center, kind: PointerDeviceKind.mouse, device: device));
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final framesBefore = _frames.length;
    final sw = Stopwatch()..start();
    for (var i = 0; i < events; i++) {
      // an irrational-ish step so no two consecutive events repeat a position
      // (the overlay short-circuits an unchanged one, which would flatter us)
      final angle = i * 0.37;
      GestureBinding.instance.handlePointerEvent(PointerHoverEvent(
        position: center + Offset(math.cos(angle), math.sin(angle)) * radius,
        kind: PointerDeviceKind.mouse,
        device: device,
        timeStamp: Duration(microseconds: sw.elapsedMicroseconds),
      ));
      // one event per frame: a real mouse at 60Hz, the cadence the cost is
      // paid at
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    sw.stop();
    // let the trailing frames land in the timing callback
    await Future<void>.delayed(const Duration(milliseconds: 400));

    final builds = <double>[
      for (final f in _frames.skip(framesBefore))
        f.buildDuration.inMicroseconds / 1000.0,
    ];
    final total = builds.fold<double>(0, (a, b) => a + b);
    builds.sort();
    _metric('hoverEvents', events);
    _metric('hoverFrames', builds.length);
    _metric('hoverBuildMsTotal', total);
    _metric('hoverBuildMsPerEvent', total / events);
    if (builds.isNotEmpty) {
      _metric('hoverBuildMsP50', builds[builds.length ~/ 2]);
      _metric('hoverBuildMsP95', builds[((builds.length - 1) * 0.95).round()]);
      _metric('hoverBuildMsMax', builds.last);
    }
  }

  @override
  void dispose() {
    _worker?.dispose();
    final source = _source;
    if (source != null) unawaited(source.close());
    _editing?.dispose();
    _viewer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_error != null) {
      body = Center(child: Text('harness error: $_error'));
    } else if (_isEdit) {
      body = _editing == null
          ? const Center(child: Text('loading…'))
          : PdfViewer(
              editing: _editing,
              controller: _viewer,
              initialFit: PdfViewerFit.width,
            );
    } else {
      body = _document == null
          ? const Center(child: Text('loading…'))
          : PdfViewer(
              document: _document!,
              controller: _viewer,
              // The competitive journey matches Chrome/PDFium's clean-profile
              // whole-page opening view. Existing diagnostic scenarios retain
              // their historical fit-width workload and numbers.
              initialFit: _scenario == 'external'
                  ? PdfViewerFit.page
                  : PdfViewerFit.width,
              renderWorker: _worker,
              autoRenderWorker: !_showingSparseSource,
              pagePreviews: _qBool('previews', true),
              previewWindow: _previewWindow,
              previewIdleDelay: _previewIdleMs < 0
                  ? null
                  : Duration(milliseconds: _previewIdleMs),
              pageRasterCachePolicy: _scenario == 'external'
                  ? (_rasterCacheMb <= 0
                      ? const PdfPageRasterCachePolicy.disabled()
                      : PdfPageRasterCachePolicy(
                          maxBytes: _rasterCacheMb * 1024 * 1024,
                          maxEntryBytes: math.min(
                            16 * 1024 * 1024,
                            _rasterCacheMb * 1024 * 1024,
                          ),
                        ))
                  : PdfPageRasterCachePolicy(
                      maxBytes: _warmBudgetMb * 1024 * 1024,
                      maxEntryBytes: 256 * 1024 * 1024,
                    ),
              pageRasterWarmPolicy: _warmPolicy,
            );
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'dart-pdf perf harness',
      home: Scaffold(body: body),
    );
  }
}
