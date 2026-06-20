// Automated real-world web-performance harness for the render worker.
//
// A standalone Flutter web entrypoint (NOT the shipping app) that loads a big
// PDF over HTTP, mounts the real [PdfEditorView] with the web render worker
// enabled, and then auto-scrolls every page while recording perf data — so an
// off-browser driver (tool/perf/driver.mjs) can run it headless in real Chrome
// and assert the decode/interpret offload keeps the UI thread smooth, exactly
// the manual `flutter run -d chrome` check but repeatable and unattended.
//
// Build:  flutter build web --release --target tool/perf/perf_harness.dart \
//           --dart-define=PDF_PERF_LOG=true
// (the driver does this for you).
//
// Tunables (--dart-define):
//   PERF_PDF_URL    URL to fetch the PDF from        (default /perf.pdf)
//   PERF_DWELL_MS   pause on each page, ms           (default 220)
//   PERF_MAX_PAGES  cap pages visited, 0 = all       (default 0)
//   PERF_PASSES     number of full step passes       (default 1)
//   PERF_FAST_PASS  add a coarse fast-fling pass     (default true)
//
// The driver reads three JS globals this installs:
//   window.__perfDone   -> bool, true when the scroll script finishes
//   window.__perfDump()  -> all captured debugPrint/[perf] lines, '\n'-joined
//   window.__perfFrames()-> JSON [{b,r,t}] per FrameTiming (build/raster/total ms)
//   window.__perfError   -> a fatal error string, if the harness threw
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

// ---------------------------------------------------------------------------
// Tunables — read from the URL query string at runtime (so the driver can vary
// them per run without a rebuild), each falling back to a --dart-define default.
//   ?url=/perf.pdf&dwell=220&maxPages=0&passes=1&fast=1
// ---------------------------------------------------------------------------
final Map<String, String> _q = Uri.base.queryParameters;

int _qInt(String key, int fallback) => int.tryParse(_q[key] ?? '') ?? fallback;
bool _qBool(String key, bool fallback) {
  final v = _q[key];
  if (v == null) return fallback;
  return v == '1' || v.toLowerCase() == 'true';
}

final String _pdfUrl = _q['url'] ??
    const String.fromEnvironment('PERF_PDF_URL', defaultValue: '/perf.pdf');
final int _dwellMs =
    _qInt('dwell', const int.fromEnvironment('PERF_DWELL_MS', defaultValue: 220));
final int _maxPages =
    _qInt('maxPages', const int.fromEnvironment('PERF_MAX_PAGES', defaultValue: 0));
final int _passes =
    _qInt('passes', const int.fromEnvironment('PERF_PASSES', defaultValue: 1));
final bool _fastPass =
    _qBool('fast', const bool.fromEnvironment('PERF_FAST_PASS', defaultValue: true));

// ---------------------------------------------------------------------------
// Capture: every debugPrint line + every frame's timing.
// ---------------------------------------------------------------------------
final List<String> _lines = <String>[];
final List<FrameTiming> _frames = <FrameTiming>[];

void _record(String line) {
  _lines.add(line);
  // Mirror to the real console too, so a headful run / page.on('console')
  // can watch live. Guarded — console must exist in a browser.
  _consoleLog(line.toJS);
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
  pdfRenderWorkerScriptUrl = 'pdf_render_worker.dart.js';
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) _record(message);
  };

  // Expose the driver's read surface up front (so a poll never races startup).
  _setGlobal('__perfDone', false.toJS);
  _setGlobal('__perfError', null);
  _setGlobal('__perfDump', (() => _lines.join('\n').toJS).toJS);
  _setGlobal('__perfFrames', (() => _framesJson().toJS).toJS);

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
  Uint8List? _bytes;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      _record('[perf] HARNESS load url=$_pdfUrl');
      final bytes = await _loadPdf(_pdfUrl);
      _record('[perf] HARNESS loaded bytes=${bytes.length}');
      setState(() => _bytes = bytes);
      // Let the first frame + the viewer's first page settle, then drive.
      unawaited(_drive());
    } catch (e, st) {
      _record('[perf] HARNESS ERROR $e');
      _setGlobal('__perfError', '$e\n$st'.toJS);
      _setGlobal('__perfDone', true.toJS);
      setState(() => _error = '$e');
    }
  }

  Future<void> _drive() async {
    // Wait for the page tree to resolve so pageCount is real.
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (_viewer.pageCount <= 0 && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final count = _viewer.pageCount;
    _record('[perf] HARNESS pageCount=$count');
    if (count <= 0) {
      _setGlobal('__perfError', 'pageCount never became positive'.toJS);
      _setGlobal('__perfDone', true.toJS);
      return;
    }

    // Let the first visible page interpret before we start moving.
    await Future<void>.delayed(const Duration(milliseconds: 1500));

    final last = _maxPages > 0 ? (_maxPages.clamp(1, count)) : count;

    for (var pass = 0; pass < _passes; pass++) {
      _record('[perf] HARNESS PASS step $pass/$_passes pages=$last');
      for (var i = 0; i < last; i++) {
        await _viewer.jumpToPage(i); // animates ~250ms
        await Future<void>.delayed(Duration(milliseconds: _dwellMs));
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

    // Settle so trailing prerenders/decodes land in the trace.
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    _record('[perf] HARNESS DONE frames=${_frames.length} lines=${_lines.length}');
    _setGlobal('__perfDone', true.toJS);
  }

  @override
  void dispose() {
    _viewer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'dart-pdf perf harness',
      home: Scaffold(
        body: _error != null
            ? Center(child: Text('harness error: $_error'))
            : _bytes == null
                ? const Center(child: Text('loading…'))
                : PdfEditorView(
                    bytes: _bytes,
                    documentId: 'perf-harness',
                    viewerController: _viewer,
                    initialFit: PdfViewerFit.width,
                  ),
      ),
    );
  }
}
