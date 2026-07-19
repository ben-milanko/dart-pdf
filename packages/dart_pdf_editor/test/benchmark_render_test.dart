// Benchmarks dart-pdf's full page rasterization (interpret + paint + toImage),
// the apples-to-apples comparison with PDFium. Rasterization needs Flutter, so
// this rides `flutter test`'s headless engine - it is NOT a CI test and skips
// unless PDF_BENCHMARK_DIR is set:
//
//   cd packages/dart_pdf_editor
//   PDF_BENCHMARK_DIR=../../test_corpora/pdfjs \
//   PDF_BENCHMARK_SCALE=2 PDF_BENCHMARK_MAX_PAGES=10 \
//   PDF_BENCHMARK_OUT=../../benchmark/out/dart-render.json \
//     fvm flutter test test/benchmark_render_test.dart
//
// Emits the JSON schema shared with the PDFium harness
// (benchmark/pdfium_benchmark.py) so benchmark/compare.py lines the tools up
// file-by-file. `renderMs` is the wall time to rasterize `pagesRendered` pages
// to a bitmap at PDF_BENCHMARK_SCALE (1.0 == 72 DPI == pixelRatio 1, matching
// PDFium's scale); `openMs` is parse/load. File I/O is excluded (bytes are read
// up front). toByteData(rawRgba) forces the GPU→CPU readback so the raster is
// fully realized before the clock stops.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
// Import PdfDocument directly rather than relying on dart_pdf_editor to
// re-export it (older releases don't), so this benchmark grafts cleanly onto
// historical commits for the perf backfill.
// ignore: unnecessary_import
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';

import 'render_smoke_test.dart' show loadSystemFonts;

void main() {
  final dir = Platform.environment['PDF_BENCHMARK_DIR'];
  final scale =
      double.tryParse(Platform.environment['PDF_BENCHMARK_SCALE'] ?? '') ?? 2.0;
  final maxPages =
      int.tryParse(Platform.environment['PDF_BENCHMARK_MAX_PAGES'] ?? '') ?? 10;
  final repeat =
      int.tryParse(Platform.environment['PDF_BENCHMARK_REPEAT'] ?? '') ?? 1;
  final outPath = Platform.environment['PDF_BENCHMARK_OUT'];
  final scenario = Platform.environment['PDF_BENCHMARK_SCENARIO'];
  final appendPath = Platform.environment['PDF_BENCHMARK_APPEND_HISTORY'];

  testWidgets('benchmarks dart-pdf rasterization vs PDFium', (tester) async {
    if (dir == null) {
      markTestSkipped('set PDF_BENCHMARK_DIR to run the render benchmark');
      return;
    }
    await tester.runAsync(() async {
      await loadSystemFonts();
      final corpus = Directory(dir);
      final files = corpus
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.pdf'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

      final root = corpus.path.endsWith('/') ? corpus.path : '${corpus.path}/';
      final best = <String, Map<String, Object?>>{};

      for (var r = 0; r < repeat; r++) {
        for (final file in files) {
          final name = file.path.startsWith(root)
              ? file.path.substring(root.length)
              : file.uri.pathSegments.last;
          final res =
              await _benchFile(file, scale, maxPages, name);
          final prev = best[file.path];
          final better = prev == null ||
              (res['error'] == null &&
                  (prev['error'] != null ||
                      (res['renderMs'] as double) <
                          (prev['renderMs'] as double)));
          if (better) {
            best[file.path] = res;
          }
        }
        // ignore: avoid_print
        print('  dart-render pass ${r + 1}/$repeat done (${files.length} files)');
      }

      String git(List<String> a) {
        final r = Process.runSync('git', a);
        return r.exitCode == 0 ? (r.stdout as String).trim() : '';
      }

      final resultList = [for (final f in files) best[f.path]];
      final payload = {
        // Envelope fields (tool/perf/SCHEMA.md); the legacy fields below are
        // unchanged so benchmark/compare.py keeps working.
        'schema': 1,
        'suite': 'flutter-render',
        'scenario': scenario,
        // Aggregated distribution so the trend dashboard (build_report.mjs
        // charts each numeric key in `metrics`) plots the render trend, not
        // just the per-file `results` below.
        'metrics': _aggregate(resultList),
        'rev': {
          'sha': git(['rev-parse', 'HEAD']),
          'branch': git(['rev-parse', '--abbrev-ref', 'HEAD']),
          'dirty': git(['status', '--porcelain']).isNotEmpty,
          'date': git(['show', '-s', '--format=%cI', 'HEAD']),
        },
        'env': {
          'os': Platform.operatingSystem,
          'cpus': Platform.numberOfProcessors,
          'ci': Platform.environment['CI'] == 'true',
          'runner': Platform.environment['RUNNER_OS'] != null
              ? 'github-actions'
              : 'local',
        },
        'ts': DateTime.now().toUtc().toIso8601String(),
        'tool': 'dart-pdf-render',
        'scale': scale,
        'maxPages': maxPages,
        'engine': 'dart-pdf (PdfPageRenderer.renderImage, Flutter raster)',
        'results': resultList,
      };
      final text = const JsonEncoder.withIndent('  ').convert(payload);
      if (outPath != null) {
        File(outPath)
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(text);
        // ignore: avoid_print
        print('wrote $outPath');
      } else {
        // ignore: avoid_print
        print(text);
      }
      // One NDJSON line per run for the trend history (mirrors perf_sweep's
      // --append-history), used by the nightly + render backfill.
      if (appendPath != null) {
        final line = jsonEncode(payload);
        File(appendPath)
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('$line\n', mode: FileMode.append);
        // ignore: avoid_print
        print('appended to $appendPath');
      }
    });
  }, timeout: const Timeout(Duration(minutes: 60)));
}

Future<Map<String, Object?>> _benchFile(
    File file, double scale, int maxPages, String name) async {
  final bytes = file.readAsBytesSync();
  final sw = Stopwatch()..start();
  PdfDocument doc;
  int pages;
  try {
    doc = PdfDocument.open(bytes);
    pages = doc.pageCount;
  } catch (e) {
    return {
      'file': name,
      'pages': 0,
      'pagesRendered': 0,
      'openMs': sw.elapsedMicroseconds / 1000,
      'renderMs': 0.0,
      'error': e.toString(),
    };
  }
  final openMs = sw.elapsedMicroseconds / 1000;

  final limit = maxPages <= 0 ? pages : (pages < maxPages ? pages : maxPages);
  var rendered = 0;
  String? error;
  final walk = Stopwatch()..start();
  for (var i = 0; i < limit; i++) {
    try {
      final image = await PdfPageRenderer.renderImage(doc.page(i),
              pixelRatio: scale)
          .timeout(const Duration(seconds: 60));
      // Force the readback so rasterization is fully realized, then free it.
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
    'renderMs': double.parse((walk.elapsedMicroseconds / 1000).toStringAsFixed(3)),
    'error': error,
  };
}

/// Aggregates per-file results into the `metrics` distribution the trend
/// dashboard charts (same p50/p95/max shape perf_sweep emits for vm-sweep).
Map<String, Object?> _aggregate(List<Map<String, Object?>?> results) {
  final rows = results.whereType<Map<String, Object?>>().toList();
  double round(double v) => double.parse(v.toStringAsFixed(3));
  double pct(List<double> v, num p) {
    if (v.isEmpty) return 0;
    final s = [...v]..sort();
    return s[((p / 100) * (s.length - 1)).round()];
  }
  List<double> vals(String key, {bool perPage = false}) => [
        for (final r in rows)
          if (r['error'] == null &&
              r[key] is num &&
              (!perPage || (r['pagesRendered'] as int? ?? 0) > 0))
            perPage
                ? (r[key] as num) / (r['pagesRendered'] as int)
                : (r[key] as num).toDouble(),
      ];
  Map<String, Object?> dist(String key, String name, {bool perPage = false}) {
    final v = vals(key, perPage: perPage);
    if (v.isEmpty) return <String, Object?>{};
    return {
      'p50$name': round(pct(v, 50)),
      'p95$name': round(pct(v, 95)),
      'max$name': round(pct(v, 100)),
    };
  }

  return {
    'files': rows.length,
    'errors': rows.where((r) => r['error'] != null).length,
    ...dist('openMs', 'OpenMs'),
    ...dist('renderMs', 'RenderMs'),
    ...dist('renderMs', 'RenderMsPerPage', perPage: true),
  };
}
