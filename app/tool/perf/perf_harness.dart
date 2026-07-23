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
// Build:  flutter build web --release --target tool/perf/perf_harness.dart \
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
//   imageCacheMb  decoded-image cache budget, MB (default 0 = platform default)
//
// The driver reads these JS globals this installs:
//   window.__perfDone     -> bool, true when the scenario finishes
//   window.__perfError    -> a fatal error string, if the harness threw
//   window.__perfDump()   -> all captured debugPrint/[perf] lines, '\n'-joined
//   window.__perfFrames() -> JSON [{b,r,t}] per FrameTiming (build/raster/total ms)
//   window.__perfMetrics() -> JSON {name: number} of this scenario's headline
//                             metrics (the generic surface new scenarios use)
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
// PdfRect isn't in the dart_pdf_editor barrel's `show` list; pull it directly
// (app depends on pdf_document). Only the edit scenario's annotation coords.
import 'package:pdf_document/pdf_document.dart' show PdfRect;
import 'package:flutter/foundation.dart';
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

/// Decoded-image cache budget, MB. 0 leaves the platform default in place; the
/// driver sweeps it to measure what each budget costs a real tab (issue #281).
final int _imageCacheMb = _qInt('imageCacheMb', 0);

/// `?worker=N`: render-worker pool size; `?worker=0` disables the web render
/// worker entirely (`pdfRenderWorkerScriptUrl = null`), forcing every page -
/// interpret AND image decode - onto the main thread. That is the only way to
/// A/B the main-thread `_decodeOne` DCT path on desktop (#458's browser-JPEG
/// fallback): with the worker on, DCT images decode off-thread and the main
/// path never runs. Default 4 (the app's normal pool).
final int _workerPool = _qInt('worker', 4);

/// `?perGlyph=1` turns on per-glyph substituted-text composition (#454) so the
/// same build can A/B it against the whole-run shaping default - watch the
/// interpret line's `replay=`/`shape=` on `scroll-cad-labels`.
final bool _perGlyph = _qBool('perGlyph', false);

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

@JS('fetch')
external JSPromise<_FetchResponse> _fetch(String url);

extension type _FetchResponse(JSObject _) implements JSObject {
  external int get status;
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

Future<Uint8List> _loadPdf(String url) async {
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
  if (_workerPool <= 0) {
    // Worker off: everything renders on the main thread. #458's A/B lever.
    pdfRenderWorkerScriptUrl = null;
  } else {
    pdfRenderWorkerScriptUrl = 'pdf_render_worker.dart.js';
    pdfRenderWorkerPoolSize = _workerPool;
  }
  _record('[perf] HARNESS workerPool=$_workerPool');
  CanvasPdfDevice.perGlyphSubstitutedText = _perGlyph;
  _record('[perf] HARNESS perGlyph=$_perGlyph');
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
  PdfEditingController? _editing;
  String? _error;

  bool get _isEdit => _scenario == 'edit';

  @override
  void initState() {
    super.initState();
    _start();
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
        PdfPerfLog.log('HARNESS TARGET start page=${_targetPage < 0 ? 0 : _targetPage}');
      }
      _record('[perf] HARNESS load url=$_pdfUrl');
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
      unawaited(_drive(coldOpen));
    } catch (e, st) {
      _record('[perf] HARNESS ERROR $e');
      _setGlobal('__perfError', '$e\n$st'.toJS);
      _setGlobal('__perfDone', true.toJS);
      setState(() => _error = '$e');
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
        case 'open':
          await _driveOpen(coldOpen);
        case 'search':
          await _driveSearch(coldOpen);
        case 'edit':
          await _driveEdit(coldOpen);
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
      _record('[perf] HARNESS DONE scenario=$_scenario '
          'frames=${_frames.length} lines=${_lines.length}');
      _setGlobal('__perfDone', true.toJS);
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
    _record('[perf] HARNESS SEARCH query="$_searchQuery" repeat=$_searchRepeat');
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
    _metric(
        'editBufferGrowthKb',
        (editing.sessionBufferBytes - bufferBefore) / 1024.0);
    _record('[perf] HARNESS EDIT applied=$applied '
        'buffer=${editing.sessionBufferBytes}B revisions=${editing.revisionCount}');
    // Let the last repaint settle.
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  @override
  void dispose() {
    _worker?.dispose();
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
              initialFit: PdfViewerFit.width,
              renderWorker: _worker,
            );
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'dart-pdf perf harness',
      home: Scaffold(body: body),
    );
  }
}
