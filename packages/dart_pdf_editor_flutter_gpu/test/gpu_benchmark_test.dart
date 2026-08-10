import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor_flutter_gpu/dart_pdf_editor_flutter_gpu.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

bool _gpuAvailable() {
  try {
    gpu.gpuContext.defaultColorFormat;
    return true;
  } catch (_) {
    return false;
  }
}

double _median(List<int> samples) {
  samples.sort();
  final middle = samples.length ~/ 2;
  return samples.length.isOdd
      ? samples[middle].toDouble()
      : (samples[middle - 1] + samples[middle]) / 2;
}

Future<int> _timeImage(Future<ui.Image> Function() render) async {
  final clock = Stopwatch()..start();
  final image = await render();
  clock.stop();
  image.dispose();
  return clock.elapsedMicroseconds;
}

void main() {
  testWidgets('reports cold compile and warm tile replay separately',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }

      final scene = await PdfRetainedScene.record(
          PdfDocument.open(buildEmbeddedFontImagePdf()).page(0));
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);

      // Creating the session is intentionally cheap: first paint has already
      // happened before the viewer asks for a deep-zoom tile, and even scene
      // compilation waits until this first raster call.
      expect(backend.stats.scenesCompiled, 0);
      expect(backend.stats.texturesUploaded, 0);

      final page = Offset.zero & scene.pageSize;
      final region = Rect.fromLTWH(
        40,
        50,
        (page.width - 40).clamp(1, 330),
        (page.height - 50).clamp(1, 190),
      );
      final coldGpu = await _timeImage(
          () => session.rasterizeRegion(region, pixelRatio: 2));
      final buffers = backend.stats.geometryBuffers;
      final uploads = backend.stats.texturesUploaded;

      final warmGpu = <int>[];
      final warmCanvas = <int>[];
      for (var i = 0; i < 7; i++) {
        final shifted =
            region.shift(Offset(i * 2.0, i.toDouble())).intersect(page);
        warmGpu.add(await _timeImage(
            () => session.rasterizeRegion(shifted, pixelRatio: 2)));
        warmCanvas.add(await _timeImage(
            () => scene.rasterizeRegion(shifted, pixelRatio: 2)));
      }

      expect(backend.stats.scenesCompiled, 1);
      expect(backend.stats.geometryBuffers, buffers);
      expect(backend.stats.texturesUploaded, uploads);
      expect(backend.stats.tilesRendered, 8);
      expect(backend.stats.selectedCommands, greaterThan(0));

      final summary = 'flutter_gpu tile benchmark: cold=${coldGpu}us '
          'warmMedian=${_median(warmGpu).toStringAsFixed(0)}us '
          'canvasMedian=${_median(warmCanvas).toStringAsFixed(0)}us '
          '${backend.stats}';
      // Keep an always-visible machine-readable-ish line in benchmark runs.
      // ignore: avoid_print
      print(summary);
    });
  }, timeout: const Timeout(Duration(minutes: 2)));
}
