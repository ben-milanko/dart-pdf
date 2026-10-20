// Benchmarks full page rasterization through the experimental strip shader
// device (interpret + strip-generate + atlas decode + tape replay +
// toImage) - the Track B counterpart of benchmark_render_test.dart, same
// JSON schema, engine "dart-pdf-strips". Skips unless PDF_BENCHMARK_DIR is
// set:
//
//   cd packages/dart_pdf_editor
//   PDF_BENCHMARK_DIR=../../test_corpora/pdfjs \
//   PDF_BENCHMARK_SCALE=2 PDF_BENCHMARK_MAX_PAGES=10 \
//   PDF_BENCHMARK_OUT=../../benchmark/out/dart-strips.json \
//     fvm flutter test test/benchmark_strip_render_test.dart
//
// Besides the shared schema it reports strip statistics (flushes/page,
// strip quads/page, alpha atlas KB/page, delegated paints/page) and the
// phase split (interpret+stripgen / atlas decode / tape replay / raster)
// as a top-level `stripStats` object plus a printed summary.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/strips.dart';

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

  testWidgets('benchmarks strip-device rasterization', (tester) async {
    if (dir == null) {
      markTestSkipped('set PDF_BENCHMARK_DIR to run the strip benchmark');
      return;
    }
    await tester.runAsync(() async {
      await loadSystemFonts();
      PdfPageRenderer.deviceMode = PdfRenderDeviceMode.strips;
      StripPdfDevice.debugNoShader =
          Platform.environment['STRIP_BENCH_NO_SHADER'] == '1';
      try {
        final corpus = Directory(dir);
        final files = corpus
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.toLowerCase().endsWith('.pdf'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

        final root =
            corpus.path.endsWith('/') ? corpus.path : '${corpus.path}/';
        final best = <String, Map<String, Object?>>{};

        for (var r = 0; r < repeat; r++) {
          // stats reflect the final pass (counters are process-global)
          StripPdfDevice.resetStats();
          PdfPageRenderer.stripInterpretMicros = 0;
          PdfPageRenderer.stripRasterMicros = 0;
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
            if (better) best[file.path] = res;
          }
          // ignore: avoid_print
          print('  dart-strips pass ${r + 1}/$repeat done '
              '(${files.length} files)');
        }

        var pages = 0;
        var renderMs = 0.0;
        for (final f in files) {
          final r = best[f.path]!;
          if (r['error'] != null) continue;
          pages += r['pagesRendered'] as int;
          renderMs += r['renderMs'] as double;
        }
        final stripStats = {
          'pages': pages,
          'renderMsPerPage': pages == 0
              ? null
              : double.parse((renderMs / pages).toStringAsFixed(2)),
          'flushesPerPage':
              pages == 0 ? null : StripPdfDevice.totalFlushes / pages,
          'stripQuadsPerPage':
              pages == 0 ? null : StripPdfDevice.totalStripQuads ~/ pages,
          'atlasKBPerPage': pages == 0
              ? null
              : StripPdfDevice.totalAtlasTexels * 4 ~/ 1024 ~/ pages,
          'delegatedPaintsPerPage':
              pages == 0 ? null : StripPdfDevice.totalDelegatedPaints ~/ pages,
          'interpretStripGenMsPerPage': pages == 0
              ? null
              : PdfPageRenderer.stripInterpretMicros / 1000 / pages,
          'atlasDecodeMsPerPage': pages == 0
              ? null
              : StripPdfDevice.totalAtlasDecodeMicros / 1000 / pages,
          'tapeReplayMsPerPage': pages == 0
              ? null
              : StripPdfDevice.totalReplayMicros / 1000 / pages,
          'rasterMsPerPage': pages == 0
              ? null
              : PdfPageRenderer.stripRasterMicros / 1000 / pages,
        };
        // ignore: avoid_print
        print('  strip stats: $stripStats');

        final payload = {
          'tool': 'dart-pdf-strips-render',
          'scale': scale,
          'maxPages': maxPages,
          'engine': 'dart-pdf-strips (StripPdfDevice: drawVertices + '
              'FragmentShader strips, canvas fallback)',
          'stripStats': stripStats,
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
      } finally {
        PdfPageRenderer.deviceMode = PdfRenderDeviceMode.canvas;
        StripPdfDevice.debugNoShader = false;
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
    'renderMs':
        double.parse((walk.elapsedMicroseconds / 1000).toStringAsFixed(3)),
    'error': error,
  };
}
