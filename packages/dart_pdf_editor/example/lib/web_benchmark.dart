// In-browser rasterization benchmark entrypoint.
//
// This is NOT the demo app - it is a headless-friendly harness that runs the
// SAME page-rasterization pipeline as `test/benchmark_render_test.dart`
// (`PdfPageRenderer.renderImage` -> `toImage` -> `toByteData` readback) but
// inside a real browser, so the work actually flows through whichever web
// renderer the build selected (CanvasKit or the Wasm/skwasm engine). The
// `flutter test` benchmark can't see that difference because it rides the
// headless host engine, not the web renderer.
//
// Build it as an alternate entrypoint and drive it with the harness in
// `benchmark/web/` (see benchmark/web/run.sh):
//
//   fvm flutter build web --release -t lib/web_benchmark.dart            # CanvasKit
//   fvm flutter build web --release --wasm -t lib/web_benchmark.dart     # skwasm
//
// It fetches a manifest + the PDFs over HTTP (no asset bundling), times them,
// and publishes the results on `globalThis` for the Playwright driver:
//   globalThis.__benchReady    = true   (engine booted, first frame painted)
//   globalThis.__benchProgress = "<i>/<n> <file>"
//   globalThis.__benchResults  = JSON string  (set once, when done)
//   globalThis.__benchError    = JSON string  (fatal harness error)
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';

void main() {
  runApp(const _BenchApp());
}

class _BenchApp extends StatefulWidget {
  const _BenchApp();

  @override
  State<_BenchApp> createState() => _BenchAppState();
}

class _BenchAppState extends State<_BenchApp> {
  String _status = 'booting…';

  @override
  void initState() {
    super.initState();
    // Wait for the first frame so the web renderer is fully up before timing.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      globalContext['__benchReady'] = true.toJS;
      unawaited(_run());
    });
  }

  void _report(String s) {
    globalContext['__benchProgress'] = s.toJS;
    if (mounted) setState(() => _status = s);
  }

  Future<void> _run() async {
    try {
      final manifest = await _fetchJson('bench/manifest.json');
      final scale = (manifest['scale'] as num?)?.toDouble() ?? 2.0;
      final maxPages = (manifest['maxPages'] as num?)?.toInt() ?? 10;
      final repeat = (manifest['repeat'] as num?)?.toInt() ?? 1;
      final warmup = manifest['warmup'] as bool? ?? true;
      final files = (manifest['files'] as List).cast<String>();

      final best = <String, Map<String, Object?>>{};
      for (var r = 0; r < repeat; r++) {
        for (var i = 0; i < files.length; i++) {
          final name = files[i];
          _report('pass ${r + 1}/$repeat - file ${i + 1}/${files.length}: $name');
          final res = await _benchFile(name, scale, maxPages,
              warmup: warmup && r == 0);
          final prev = best[name];
          final better = prev == null ||
              (res['error'] == null &&
                  (prev['error'] != null ||
                      (res['renderMs'] as double) <
                          (prev['renderMs'] as double)));
          if (better) best[name] = res;
          // Yield so the event loop can breathe between files.
          await Future<void>.delayed(Duration.zero);
        }
      }

      final payload = <String, Object?>{
        'scale': scale,
        'maxPages': maxPages,
        'repeat': repeat,
        'results': [for (final f in files) best[f]],
      };
      globalContext['__benchResults'] =
          const JsonEncoder().convert(payload).toJS;
      _report('done - ${files.length} files');
    } catch (e, st) {
      globalContext['__benchError'] =
          jsonEncode({'error': e.toString(), 'stack': st.toString()}).toJS;
      _report('ERROR: $e');
    }
  }

  Future<Map<String, Object?>> _benchFile(
      String name, double scale, int maxPages,
      {required bool warmup}) async {
    final Uint8List bytes;
    try {
      bytes = await _fetchBytes('bench/pdfs/$name');
    } catch (e) {
      return _err(name, 'fetch: $e');
    }

    final open = Stopwatch()..start();
    PdfDocument doc;
    int pages;
    try {
      doc = PdfDocument.open(bytes);
      pages = doc.pageCount;
    } catch (e) {
      return _err(name, 'open: $e', openMs: open.elapsedMicroseconds / 1000);
    }
    final openMs = open.elapsedMicroseconds / 1000;
    final limit = maxPages <= 0 ? pages : (pages < maxPages ? pages : maxPages);

    // One untimed warm-up render so first-render engine costs (shader compile,
    // texture upload paths) don't land on the measured page.
    if (warmup && limit > 0) {
      try {
        final img = await PdfPageRenderer.renderImage(doc.page(0),
            pixelRatio: scale);
        await img.toByteData(format: ui.ImageByteFormat.rawRgba);
        img.dispose();
      } catch (_) {}
    }

    var rendered = 0;
    String? error;
    final walk = Stopwatch()..start();
    for (var i = 0; i < limit; i++) {
      try {
        final image =
            await PdfPageRenderer.renderImage(doc.page(i), pixelRatio: scale);
        // Force the GPU->CPU readback so rasterization is fully realized.
        await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        image.dispose();
        rendered++;
      } catch (e) {
        error ??= 'page $i: $e';
      }
    }
    walk.stop();
    return {
      'file': name,
      'pages': pages,
      'pagesRendered': rendered,
      'openMs': double.parse(openMs.toStringAsFixed(3)),
      'renderMs':
          double.parse((walk.elapsedMicroseconds / 1000).toStringAsFixed(3)),
      'error': error,
    };
  }

  Map<String, Object?> _err(String name, String error, {double openMs = 0}) => {
        'file': name,
        'pages': 0,
        'pagesRendered': 0,
        'openMs': double.parse(openMs.toStringAsFixed(3)),
        'renderMs': 0.0,
        'error': error,
      };

  Future<Uint8List> _fetchBytes(String url) async {
    final resp = await web.window.fetch(url.toJS).toDart;
    if (!resp.ok) throw 'HTTP ${resp.status} for $url';
    final buf = await resp.arrayBuffer().toDart;
    return buf.toDart.asUint8List();
  }

  Future<Map<String, Object?>> _fetchJson(String url) async {
    final resp = await web.window.fetch(url.toJS).toDart;
    if (!resp.ok) throw 'HTTP ${resp.status} for $url';
    final text = (await resp.text().toDart).toDart;
    return jsonDecode(text) as Map<String, Object?>;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF101418),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'dart-pdf web render benchmark\n$_status',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ),
      ),
    );
  }
}
