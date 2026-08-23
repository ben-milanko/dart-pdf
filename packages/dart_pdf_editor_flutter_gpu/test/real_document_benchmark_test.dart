import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor_flutter_gpu/dart_pdf_editor_flutter_gpu.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';

const _defaultPages = [27, 30, 29, 32, 31, 34, 37, 39, 28];

bool _gpuAvailable() {
  try {
    gpu.gpuContext.defaultColorFormat;
    return true;
  } catch (_) {
    return false;
  }
}

List<int> _pages() {
  final value = Platform.environment['PDF_GPU_BENCHMARK_PAGES'];
  if (value == null || value.trim().isEmpty) return _defaultPages;
  return value
      .split(',')
      .map((part) => int.tryParse(part.trim()))
      .whereType<int>()
      .toList();
}

Future<(int, ByteData, int, int)> _render(
  Future<ui.Image> Function() callback, {
  String? pngPath,
}) async {
  final clock = Stopwatch()..start();
  final image = await callback();
  // This benchmark measures visual settle, not command submission: force the
  // image complete before stopping the clock. Production never performs this
  // readback; it hands Texture.asImage() directly to the compositor.
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  if (pngPath != null) {
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (png != null) {
      File(pngPath).writeAsBytesSync(
        png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
      );
    }
  }
  final width = image.width, height = image.height;
  clock.stop();
  image.dispose();
  return (clock.elapsedMicroseconds, bytes, width, height);
}

double _meanDiff(ByteData a, ByteData b) {
  final aa = a.buffer.asUint8List(a.offsetInBytes, a.lengthInBytes);
  final bb = b.buffer.asUint8List(b.offsetInBytes, b.lengthInBytes);
  var total = 0;
  for (var i = 0; i < aa.length; i++) {
    total += (aa[i] - bb[i]).abs().toInt();
  }
  return total / aa.length;
}

void main() {
  testWidgets('real document: cold scene plus two 512px LoDs', (tester) async {
    final path = Platform.environment['PDF_GPU_BENCHMARK_PDF'];
    if (path == null) {
      markTestSkipped('set PDF_GPU_BENCHMARK_PDF');
      return;
    }
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final document = PdfDocument.open(File(path).readAsBytesSync());
      final configuredPages =
          Platform.environment['PDF_GPU_BENCHMARK_PAGES']?.trim();
      final requestedPages = _pages();
      final pages = [
        for (final page in requestedPages)
          if (page >= 0 && page < document.pageCount) page,
      ];
      if (pages.isEmpty &&
          (configuredPages == null || configuredPages.isEmpty) &&
          document.pageCount > 0) {
        pages.add(0);
      }
      final msaa = Platform.environment['PDF_GPU_BENCHMARK_MSAA'] != '0';
      final approximateOverprint =
          Platform.environment['PDF_GPU_BENCHMARK_OVERPRINT'] != '0';
      final backend = FlutterGpuTileRasterBackend(
        msaa: msaa,
        allowOverprintApproximation: approximateOverprint,
      );
      if (Platform.environment['PDF_GPU_BENCHMARK_WARMUP'] == '1') {
        final warmUp = Stopwatch()..start();
        await backend.warmUp();
        // ignore: avoid_print
        print('REAL_GPU_BENCHMARK warmUpUs=${warmUp.elapsedMicroseconds}');
      }
      final output = Platform.environment['PDF_GPU_BENCHMARK_OUT'];
      if (output != null) Directory(output).createSync(recursive: true);
      final rssStart = ProcessInfo.currentRss;
      var peakRss = rssStart;
      final rows = <String>[];

      for (final pageIndex in pages) {
        PdfImageCache.instance.clear();
        final timing = PdfSceneBuildTiming();
        final record = Stopwatch()..start();
        final scene = await PdfRetainedScene.record(
          document.page(pageIndex),
          timing: timing,
        );
        record.stop();
        try {
          final session = backend.createSession(scene);
          if (session == null) {
            rows.add('page=$pageIndex recordUs=${record.elapsedMicroseconds} '
                'decodeUs=${(timing.decodeMs * 1000).round()} '
                'gpu=rejected reason=${backend.stats.lastRejection} '
                'commands=${scene.commands.length}');
            continue;
          }
          try {
            if (Platform.environment['PDF_GPU_BENCHMARK_SCENE_WARMUP'] == '1' &&
                session is PdfTileRasterWarmUp) {
              final warmUp = Stopwatch()..start();
              await (session as PdfTileRasterWarmUp).warmUp();
              // ignore: avoid_print
              print('REAL_GPU_BENCHMARK sceneWarmUpUs='
                  '${warmUp.elapsedMicroseconds}');
            }
            final size = scene.pageSize;
            final center = Offset(size.width / 2, size.height / 2);
            final lod1 = 1.0;
            final region1 = Rect.fromCenter(
              center: center,
              width: math.min(size.width, 512 / lod1),
              height: math.min(size.height, 512 / lod1),
            );
            try {
              final coldGpu = await _render(
                () => session.rasterizeRegion(region1, pixelRatio: lod1),
                pngPath:
                    output == null ? null : '$output/page-$pageIndex-gpu.png',
              );
              final warmCanvas = await _render(
                () => scene.rasterizeRegion(region1, pixelRatio: lod1),
                pngPath: output == null
                    ? null
                    : '$output/page-$pageIndex-canvas.png',
              );

              final lod2 = 2.0;
              final region2 = Rect.fromCenter(
                center: center,
                width: math.min(size.width, 512 / lod2),
                height: math.min(size.height, 512 / lod2),
              );
              final warmGpu = await _render(
                  () => session.rasterizeRegion(region2, pixelRatio: lod2));
              peakRss = math.max(peakRss, ProcessInfo.currentRss);
              rows.add('page=$pageIndex recordUs=${record.elapsedMicroseconds} '
                  'decodeUs=${(timing.decodeMs * 1000).round()} '
                  'gpuColdUs=${coldGpu.$1} gpuWarmUs=${warmGpu.$1} '
                  'canvasUs=${warmCanvas.$1} '
                  'meanDiff=${_meanDiff(coldGpu.$2, warmCanvas.$2).toStringAsFixed(3)}');
            } catch (error) {
              final canvas = await _render(
                  () => scene.rasterizeRegion(region1, pixelRatio: lod1));
              peakRss = math.max(peakRss, ProcessInfo.currentRss);
              rows.add('page=$pageIndex recordUs=${record.elapsedMicroseconds} '
                  'decodeUs=${(timing.decodeMs * 1000).round()} '
                  'gpu=fallback canvasUs=${canvas.$1} '
                  'error=${error.toString().replaceAll('\n', ' ')}');
            }
          } finally {
            session.dispose();
          }
        } finally {
          scene.dispose();
        }
      }

      // ignore: avoid_print
      print('REAL_GPU_BENCHMARK pages=$pages msaa=$msaa '
          'approximateOverprint=$approximateOverprint');
      for (final row in rows) {
        // ignore: avoid_print
        print('REAL_GPU_BENCHMARK $row');
      }
      // ignore: avoid_print
      print('REAL_GPU_BENCHMARK rssStart=$rssStart peakRss=$peakRss '
          'delta=${peakRss - rssStart} stats=${backend.stats}');
      expect(rows, isNotEmpty);
    });
  }, timeout: const Timeout(Duration(minutes: 20)));
}
