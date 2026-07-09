// Visual smoke + rough parity check for the experimental flutter_gpu
// backend: renders pages through both PdfPageRenderer (canvas) and
// PdfGpuPageRenderer, writes side-by-side PNGs to GPU_RENDER_OUT (if set),
// and asserts the two rasters roughly agree.
//
//   cd packages/dart_pdf_editor
//   GPU_RENDER_OUT=/tmp/gpu_smoke fvm flutter test \
//     --enable-impeller --enable-flutter-gpu test/gpu_render_smoke_test.dart
//
// Skips when flutter_gpu is unavailable (a plain `flutter test` run).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/gpu.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';

import 'render_smoke_test.dart' show loadSystemFonts;

bool _gpuAvailable() {
  try {
    // ignore: unnecessary_statements
    gpu.gpuContext.defaultColorFormat;
    return true;
  } catch (_) {
    return false;
  }
}

const _pages = <(String, int)>[
  // vector + text heavy composite test page
  ('../../test_corpora/ghent/1-CMYK/Ghent_PDF-Output-Test-V50_CMYK_X4.pdf', 0),
  // shading patterns (gradient pipeline)
  ('../../test_corpora/ghent/1-CMYK/GWG060_Shading_x1a.pdf', 0),
  // embedded font support page (glyph outline fills)
  ('../../test_corpora/ghent/1-CMYK/GWG090_Font-Support_x3.pdf', 0),
  // simple text
  ('../../test_corpora/pdfjs/helloworld-bad.pdf', 0),
];

void main() {
  testWidgets('gpu renderer roughly matches the canvas renderer',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped(
            'flutter_gpu unavailable; run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      await loadSystemFonts();
      final outDir = Platform.environment['GPU_RENDER_OUT'];
      // Same env knobs as the benchmark harness, so this test doubles as
      // the AA-evidence render (strips vs MSAA vs aliased PNG dumps).
      PdfGpuPageRenderer.msaaEnabled =
          Platform.environment['PDF_GPU_MSAA'] != '0';
      PdfGpuPageRenderer.stripsEnabled =
          Platform.environment['PDF_GPU_STRIPS'] == '1';

      for (final (path, pageIndex) in _pages) {
        final file = File(path);
        if (!file.existsSync()) {
          fail('missing corpus file $path');
        }
        final doc = PdfDocument.open(file.readAsBytesSync());
        final page = doc.page(pageIndex);
        final name = file.uri.pathSegments.last.replaceAll('.pdf', '');

        final cpuImage =
            await PdfPageRenderer.renderImage(page, pixelRatio: 2);
        final gpuImage =
            await PdfGpuPageRenderer.renderImage(page, pixelRatio: 2);
        // ignore: avoid_print
        print('$name: cpu=${cpuImage.width}x${cpuImage.height} '
            'gpu=${gpuImage.width}x${gpuImage.height} '
            'unsupported=${PdfGpuPageRenderer.lastUnsupported}');
        expect(gpuImage.width, cpuImage.width);
        expect(gpuImage.height, cpuImage.height);

        final cpu = (await cpuImage.toByteData(
                format: ui.ImageByteFormat.rawStraightRgba))!
            .buffer
            .asUint8List();
        final gpuBytes = (await gpuImage.toByteData(
                format: ui.ImageByteFormat.rawStraightRgba))!
            .buffer
            .asUint8List();

        // Loose agreement: mean absolute channel difference. The backends
        // differ legitimately (substituted text, soft masks, AA), so this
        // guards against "blank page" or "garbage" regressions, not pixels.
        var sum = 0;
        for (var i = 0; i < cpu.length; i++) {
          sum += (cpu[i] - gpuBytes[i]).abs();
        }
        final mean = sum / cpu.length;
        // ignore: avoid_print
        print('$name: mean channel diff ${mean.toStringAsFixed(2)}');

        if (outDir != null) {
          Directory(outDir).createSync(recursive: true);
          for (final (suffix, image) in [('cpu', cpuImage), ('gpu', gpuImage)]) {
            final png =
                await image.toByteData(format: ui.ImageByteFormat.png);
            File('$outDir/$name-$suffix.png')
                .writeAsBytesSync(png!.buffer.asUint8List());
          }
        }
        expect(mean, lessThan(40),
            reason: '$name diverged badly from the canvas render');
        cpuImage.dispose();
        gpuImage.dispose();
      }
    });
  }, timeout: const Timeout(Duration(minutes: 10)));
}
