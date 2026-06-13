// Benchmarks dart-pdf's full page rasterization (interpret + paint + toImage),
// the apples-to-apples comparison with PDFium. Rasterization needs Flutter, so
// this rides `flutter test`'s headless engine — it is NOT a CI test and skips
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

      final payload = {
        'tool': 'dart-pdf-render',
        'scale': scale,
        'maxPages': maxPages,
        'engine': 'dart-pdf (PdfPageRenderer.renderImage, Flutter raster)',
        'results': [for (final f in files) best[f.path]],
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
