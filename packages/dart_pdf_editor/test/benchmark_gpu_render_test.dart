// Benchmarks the experimental flutter_gpu backend's full page rasterization
// (interpret + tessellate + GPU draw + readback) with the same protocol and
// JSON schema as benchmark_render_test.dart, so benchmark/compare.py lines it
// up against PDFium and the canvas renderer file-by-file.
//
//   cd packages/dart_pdf_editor
//   PDF_BENCHMARK_DIR=../../test_corpora/pdfjs \
//   PDF_BENCHMARK_SCALE=2 PDF_BENCHMARK_MAX_PAGES=10 \
//   PDF_BENCHMARK_OUT=../../benchmark/out/dart-gpu.json \
//     fvm flutter test --enable-impeller --enable-flutter-gpu \
//       test/benchmark_gpu_render_test.dart
//
// Requires the Impeller + Flutter GPU tester flags; skips otherwise. The
// toByteData(rawRgba) readback forces GPU completion so the clock stops when
// the raster is fully realized, matching the other harnesses. Each file's
// result carries an `unsupported` map - the features that page set needed
// but the GPU backend approximated or skipped (fidelity honesty).
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/gpu.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';

import 'render_smoke_test.dart' show loadSystemFonts;

/// PDF_GPU_PIPELINE=1 overlaps each page's CPU walk (parse + tessellate +
/// command encoding) with the previous page's GPU execution: renderImage
/// returns after submit, toByteData is the completion fence, and Metal
/// serializes command buffers so the reused render targets stay safe with
/// one page in flight. This is the realistic batch-rendering (thumbnails,
/// export) number; the default sequential mode matches the other harnesses'
/// strict per-page latency protocol.
final bool _pipelined = Platform.environment['PDF_GPU_PIPELINE'] == '1';

bool _gpuAvailable() {
  try {
    // ignore: unnecessary_statements
    gpu.gpuContext.defaultColorFormat;
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  final dir = Platform.environment['PDF_BENCHMARK_DIR'];
  final scale =
      double.tryParse(Platform.environment['PDF_BENCHMARK_SCALE'] ?? '') ?? 2.0;
  final maxPages =
      int.tryParse(Platform.environment['PDF_BENCHMARK_MAX_PAGES'] ?? '') ?? 10;
  final repeat =
      int.tryParse(Platform.environment['PDF_BENCHMARK_REPEAT'] ?? '') ?? 1;
  final outPath = Platform.environment['PDF_BENCHMARK_OUT'];

  testWidgets('benchmarks flutter_gpu rasterization vs PDFium', (tester) async {
    if (dir == null) {
      markTestSkipped('set PDF_BENCHMARK_DIR to run the GPU render benchmark');
      return;
    }
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        fail('flutter_gpu unavailable: run with '
            '--enable-impeller --enable-flutter-gpu');
      }
      // PDF_GPU_MSAA=0 renders aliased (minimum fixed cost per page).
      PdfGpuPageRenderer.msaaEnabled =
          Platform.environment['PDF_GPU_MSAA'] != '0';
      // PDF_GPU_STRIPS=1 routes fills through CPU sparse coverage strips
      // (AA without MSAA - Track A); strip mode ignores msaaEnabled.
      PdfGpuPageRenderer.stripsEnabled =
          Platform.environment['PDF_GPU_STRIPS'] == '1';
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
          final res = await _benchFile(file, scale, maxPages, name);
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
        print('  dart-gpu pass ${r + 1}/$repeat done (${files.length} files)');
      }

      final payload = {
        'tool': 'dart-pdf-gpu'
            '${Platform.environment['PDF_GPU_MSAA'] == '0' ? '-nomsaa' : ''}'
            '${_pipelined ? '-pipelined' : ''}',
        'scale': scale,
        'maxPages': maxPages,
        'engine':
            'dart-pdf (PdfGpuPageRenderer.renderImage, flutter_gpu/Impeller)',
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
  final unsupported = <String, int>{};
  final walk = Stopwatch()..start();
  ui.Image? inFlight; // pipelined mode: previous page still on the GPU
  Future<void> drain() async {
    final image = inFlight;
    if (image == null) return;
    inFlight = null;
    await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    rendered++;
  }

  for (var i = 0; i < limit; i++) {
    try {
      final image = await PdfGpuPageRenderer.renderImage(doc.page(i),
              pixelRatio: scale)
          .timeout(const Duration(seconds: 60));
      PdfGpuPageRenderer.lastUnsupported.forEach(
          (k, v) => unsupported[k] = (unsupported[k] ?? 0) + v);
      if (_pipelined) {
        // page i executes on the GPU while page i+1's CPU walk runs
        await drain();
        inFlight = image;
      } else {
        // strict per-page latency: realize the raster before the next page
        await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        image.dispose();
        rendered++;
      }
    } catch (e) {
      error ??= 'page $i: $e';
    }
  }
  try {
    await drain();
  } catch (e) {
    error ??= 'drain: $e';
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
    if (unsupported.isNotEmpty) 'unsupported': unsupported,
  };
}
