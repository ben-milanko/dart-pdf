// Phase profiling for the flutter_gpu backend: renders representative corpus
// pages several times (warm caches, best pass) and prints where the wall
// time goes (parse/collect/decode/upload/paint/submit/readback) plus the
// device work counters. Skips unless GPU_PROFILE_DIR points at the corpus.
//
//   cd packages/dart_pdf_editor
//   GPU_PROFILE_DIR=../../corpus fvm flutter test \
//     --enable-impeller --enable-flutter-gpu test/gpu_profile_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/gpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';

import 'render_smoke_test.dart' show loadSystemFonts;

const _pages = <(String, int, String)>[
  ('CTC 10 - Demo 20220622.pdf', 0, 'text-dense (worst gpu/cpu ratio)'),
  ('NPR3JZA-WP11-162 - Rev A (002)KR.pdf', 0, 'text+vector, 4x slower'),
  ('WAT_L0001_S.pdf', 1, 'CAD linework, 3.4x slower'),
  ('ly9-far-cad.pdf', 0, 'huge CAD, 2.5x slower'),
  ('AO-PR-23-000595.pdf', 0, 'scan images, ~parity'),
  ('TRAX ARTC BRIEF 010622.pdf', 0, 'transparency groups, gpu wins'),
];

void main() {
  final dir = Platform.environment['GPU_PROFILE_DIR'];
  // GPU_PROFILE_FILE=name.pdf GPU_PROFILE_PAGES=0,3,7 overrides the stock
  // page list for ad-hoc single-file investigation.
  final overrideFile = Platform.environment['GPU_PROFILE_FILE'];
  final overridePages = [
    for (final p
        in (Platform.environment['GPU_PROFILE_PAGES'] ?? '0').split(','))
      int.parse(p.trim()),
  ];

  testWidgets('profiles gpu render phases', (tester) async {
    if (dir == null) {
      markTestSkipped('set GPU_PROFILE_DIR to profile');
      return;
    }
    await tester.runAsync(() async {
      await loadSystemFonts();
      // Same env knobs as the benchmark harness.
      PdfGpuPageRenderer.msaaEnabled =
          Platform.environment['PDF_GPU_MSAA'] != '0';
      PdfGpuPageRenderer.stripsEnabled =
          Platform.environment['PDF_GPU_STRIPS'] == '1';
      final cases = overrideFile != null
          ? [for (final p in overridePages) (overrideFile, p, 'ad-hoc')]
          : _pages;
      for (final (name, pageIndex, why) in cases) {
        final file = File('$dir/$name');
        if (!file.existsSync()) continue;
        final doc = PdfDocument.open(file.readAsBytesSync());
        final page = doc.page(pageIndex);

        var bestTotal = double.infinity;
        var bestRead = 0.0;
        var bestSecond = 0.0;
        PdfGpuRenderStats best = PdfGpuRenderStats();
        for (var i = 0; i < 3; i++) {
          final sw = Stopwatch()..start();
          final image =
              await PdfGpuPageRenderer.renderImage(page, pixelRatio: 2);
          final afterRender = sw.elapsedMicroseconds / 1000;
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
          final total = sw.elapsedMicroseconds / 1000;
          // Second read of the already-realized texture: pure transfer cost.
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
          final second = sw.elapsedMicroseconds / 1000 - total;
          image.dispose();
          if (total < bestTotal) {
            bestTotal = total;
            bestRead = total - afterRender;
            bestSecond = second;
            best = PdfGpuPageRenderer.lastStats;
          }
        }

        // canvas comparison, same protocol
        var cpuBest = double.infinity;
        for (var i = 0; i < 3; i++) {
          final sw = Stopwatch()..start();
          final image = await PdfPageRenderer.renderImage(page, pixelRatio: 2);
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
          cpuBest = (sw.elapsedMicroseconds / 1000) < cpuBest
              ? sw.elapsedMicroseconds / 1000
              : cpuBest;
          image.dispose();
        }

        // ignore: avoid_print
        print('--- $name p$pageIndex ($why)\n'
            '    gpu total ${bestTotal.toStringAsFixed(1)}ms '
            '(readback ${bestRead.toStringAsFixed(1)}, of which pure '
            'transfer ${bestSecond.toStringAsFixed(1)}) vs canvas '
            '${cpuBest.toStringAsFixed(1)}ms\n'
            '    $best');
      }
    });
  }, timeout: const Timeout(Duration(minutes: 15)));
}
