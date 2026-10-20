// Paired A/B of retained native geometry against rebuilding the same paths.
// PDF_PATH=/path/to/dense.pdf fvm flutter test --no-pub \
//   test/benchmark_path_replay_test.dart --reporter expanded
// The PDF stays local. Each pair uses identical commands, images and scale;
// alternating order controls warming. The first pair also compares RGBA bytes.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/image_decoder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

import 'render_smoke_test.dart' show loadSystemFonts;

void main() {
  testWidgets('paired dense-page path replay benchmark', (tester) async {
    final path = Platform.environment['PDF_PATH'];
    if (path == null) {
      markTestSkipped('set PDF_PATH');
      return;
    }
    await tester.runAsync(() async {
      await loadSystemFonts();
      final bytes = File(path).readAsBytesSync();
      final pageIndex =
          int.tryParse(Platform.environment['PDF_PAGE'] ?? '') ?? 0;
      final page = PdfDocument.open(bytes).page(pageIndex);
      final worker = PdfRenderWorker.start(bytes);
      try {
        final commands = (await worker.record(pageIndex, imagePixelRatio: 8))!;
        final scene = await PdfRetainedScene.fromCommands(page, commands,
            maxImagePixelRatio: 8);
        try {
          final requests = <PdfImageRequest>[];
          PdfPageRenderer.collectImageRequests(commands, requests);
          final images = <Object, ui.Image>{
            for (final request in requests)
              if (scene.imageFor(request) case final image?)
                pdfImageKey(request): image,
          };
          final scales =
              (Platform.environment['PDF_BENCHMARK_SCALES'] ?? '2,4,8')
                  .split(',')
                  .map(double.parse);
          final results = <Object>[];
          for (final ratio in scales) {
            final timings = {false: <double>[], true: <double>[]};
            final rasterTimings = {false: <double>[], true: <double>[]};
            Uint8List? reference;
            for (var trial = 0; trial < 8; trial++) {
              for (final cached
                  in trial.isEven ? [false, true] : [true, false]) {
                final clock = Stopwatch()..start();
                final picture = cached
                    ? scene.replay(pixelRatio: ratio)
                    : _uncachedReplay(scene, images, ratio);
                final replayMs = clock.elapsedMicroseconds / 1000;
                clock.reset();
                final image = await picture.toImage(
                    (scene.pageSize.width * ratio).ceil(),
                    (scene.pageSize.height * ratio).ceil());
                try {
                  final pixels = (await image.toByteData(
                          format: ui.ImageByteFormat.rawRgba))!
                      .buffer
                      .asUint8List();
                  final rasterMs = clock.elapsedMicroseconds / 1000;
                  if (trial == 0) {
                    if (reference == null) {
                      reference = pixels;
                    } else {
                      expect(_sameBytes(reference, pixels), isTrue,
                          reason: 'cached raster changed pixels at $ratio');
                      reference = null;
                    }
                  } else {
                    timings[cached]!.add(replayMs);
                    rasterTimings[cached]!.add(rasterMs);
                  }
                } finally {
                  image.dispose();
                  picture.dispose();
                }
              }
            }
            results.add({
              'scale': ratio,
              'uncachedReplayMs': _median(timings[false]!),
              'cachedReplayMs': _median(timings[true]!),
              'uncachedRasterMs': _median(rasterTimings[false]!),
              'cachedRasterMs': _median(rasterTimings[true]!),
              'identicalPixels': true,
            });
          }
          final result = {
            'commands': commands.length,
            'results': results,
            'geometryCaches': [
              for (final entry in PdfCacheRegistry.instance.snapshot())
                if (entry.label == 'canvas-paths')
                  {
                    'entries': entry.length,
                    'estimatedBytes': entry.weight,
                    'hits': entry.hits,
                    'misses': entry.misses,
                    'evictions': entry.evictions
                  },
            ],
          };
          final json = const JsonEncoder.withIndent('  ').convert(result);
          // ignore: avoid_print
          print(json);
          final out = Platform.environment['PDF_BENCHMARK_OUT'];
          if (out != null) File(out).writeAsStringSync(json);
        } finally {
          scene.dispose();
        }
      } finally {
        worker.dispose();
      }
    });
  }, timeout: const Timeout(Duration(minutes: 10)));
}

ui.Picture _uncachedReplay(
    PdfRetainedScene scene, Map<Object, ui.Image> images, double ratio) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)..scale(ratio);
  PdfPageRenderer.preparePageCanvas(canvas, scene.page, scene.plan);
  replayCommands(scene.commands, CanvasPdfDevice(canvas, images: images));
  return recorder.endRecording();
}

double _median(List<double> values) {
  values.sort();
  return values[values.length ~/ 2];
}

bool _sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
