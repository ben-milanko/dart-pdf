// Opt-in, paired visible-region benchmark. Never rasterizes the whole page at
// extreme zoom: a 1280x800 logical viewport at DPR 2 is always 2560x1600 pixels.
// PDF_PATH=/path/to/drawing.pdf PDF_BENCHMARK_OUT=/tmp/extreme-zoom.json \
//   fvm flutter test --no-pub test/benchmark_extreme_zoom_test.dart
// Optional: PDF_BENCHMARK_SCALES=30,60,100 (3000%, 6000%, 10000%),
// PDF_BENCHMARK_SCENARIOS=center,lower,upper-right, PDF_BENCHMARK_TRIALS=7,
// PDF_BENCHMARK_DPR=2, PDF_BENCHMARK_VIEWPORT=1280x800,
// PDF_BENCHMARK_PNG_DIR=/tmp/extreme-zoom-crops,
// PDF_BENCHMARK_REQUIRE_SELECTIVE=1 (fail instead of measuring a fallback).
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';

import 'render_smoke_test.dart' show loadSystemFonts;

// Fractions of the displayed page, with y down. The right-hand locations
// exercise small transparency islands on the local engineering drawing that
// motivated this benchmark, without bundling that private document.
const _locations = <String, ui.Offset>{
  'center': ui.Offset(0.5, 0.5),
  'lower': ui.Offset(0.5, 2 / 3),
  'upper-right': ui.Offset(400 / 421, 18 / 269),
  'middle-right': ui.Offset(405 / 421, 84 / 269),
  'lower-right': ui.Offset(345 / 421, 169 / 269),
  'bottom-right': ui.Offset(345 / 421, 214 / 269),
};

void main() {
  testWidgets('paired visible-region replay at extreme zoom', (tester) async {
    final path = Platform.environment['PDF_PATH'];
    if (path == null) {
      markTestSkipped('set PDF_PATH');
      return;
    }
    final oldRegion = PdfRetainedScene.spatialRegionReplay;
    final oldGrid = PdfRetainedScene.spatialGridReplay;
    addTearDown(() {
      PdfRetainedScene.spatialRegionReplay = oldRegion;
      PdfRetainedScene.spatialGridReplay = oldGrid;
    });
    await tester.runAsync(() async {
      await loadSystemFonts();
      final env = Platform.environment;
      final scales = (env['PDF_BENCHMARK_SCALES'] ?? '30,60,100')
          .split(',')
          .map(double.parse)
          .toList();
      final names = (env['PDF_BENCHMARK_SCENARIOS'] ??
              'center,lower,upper-right,middle-right,lower-right,bottom-right')
          .split(',');
      final trials = int.parse(env['PDF_BENCHMARK_TRIALS'] ?? '7');
      final dpr = double.parse(env['PDF_BENCHMARK_DPR'] ?? '2');
      final viewport = (env['PDF_BENCHMARK_VIEWPORT'] ?? '1280x800')
          .split('x')
          .map(double.parse)
          .toList();
      expect(viewport, hasLength(2));
      expect(trials, greaterThan(0));
      expect(dpr, greaterThan(0));
      for (final scale in scales) {
        expect(scale, greaterThan(0));
      }
      final width = (viewport[0] * dpr).round();
      final height = (viewport[1] * dpr).round();
      expect(width, inInclusiveRange(1, 1 << 14));
      expect(height, inInclusiveRange(1, 1 << 14));
      final pngDir = env['PDF_BENCHMARK_PNG_DIR'];
      if (pngDir != null) Directory(pngDir).createSync(recursive: true);
      final bytes = File(path).readAsBytesSync();
      final pageIndex = int.parse(env['PDF_PAGE'] ?? '0');
      final page = PdfDocument.open(bytes).page(pageIndex);
      final worker = PdfRenderWorker.start(bytes);
      try {
        final maxRatio = scales.reduce(math.max) * dpr;
        final recordClock = Stopwatch()..start();
        final commands =
            (await worker.record(pageIndex, imagePixelRatio: maxRatio))!;
        final recordMs = recordClock.elapsedMicroseconds / 1000;
        recordClock.reset();
        final scene = await PdfRetainedScene.fromCommands(page, commands,
            maxImagePixelRatio: maxRatio);
        final sceneMs = recordClock.elapsedMicroseconds / 1000;
        try {
          final results = <Map<String, Object>>[];
          final failures = <String>[];
          final indexClock = Stopwatch()..start();
          final indexSupported = scene.debugRegionReplaySupported;
          final indexBuildMs = indexClock.elapsedMicroseconds / 1000;
          if (env['PDF_BENCHMARK_REQUIRE_SELECTIVE'] == '1') {
            expect(indexSupported, isTrue,
                reason: 'this run must exercise selective region replay');
          }
          for (final name in names) {
            final location = _locations[name];
            expect(location, isNotNull, reason: 'unknown scenario $name');
            for (final scale in scales) {
              final ratio = scale * dpr;
              final regionWidth = width / ratio;
              final regionHeight = height / ratio;
              final region = ui.Rect.fromLTWH(
                (scene.pageSize.width * location!.dx - regionWidth / 2).clamp(
                    0.0, math.max(0.0, scene.pageSize.width - regionWidth)),
                (scene.pageSize.height * location.dy - regionHeight / 2).clamp(
                    0.0, math.max(0.0, scene.pageSize.height - regionHeight)),
                regionWidth,
                regionHeight,
              );
              final measurements = {
                false: <_Measurement>[],
                true: <_Measurement>[]
              };
              var maxChangedPixels = 0;
              var maxChannelDifference = 0;
              var maxMeanChannelDifference = 0.0;
              var wasSelective = false;
              var selectedCommands = 0;
              // The initial pair warms BOTH modes and compares their pixels;
              // seven further measured pairs alternate their execution order.
              for (var trial = 0; trial <= trials; trial++) {
                Uint8List? reference;
                for (final selective
                    in trial.isEven ? [false, true] : [true, false]) {
                  PdfRetainedScene.spatialRegionReplay = selective;
                  PdfRetainedScene.spatialGridReplay = selective;
                  final clock = Stopwatch()..start();
                  final picture = scene.replayRegion(region, pixelRatio: ratio);
                  final replayMs = clock.elapsedMicroseconds / 1000;
                  if (selective) {
                    wasSelective = scene.debugLastRegionReplayWasSelective;
                    selectedCommands = scene.debugLastRegionReplayCommandCount;
                  }
                  clock.reset();
                  final image = await picture.toImage(width, height);
                  final rasterMs = clock.elapsedMicroseconds / 1000;
                  try {
                    clock.reset();
                    final data = (await image.toByteData(
                        format: ui.ImageByteFormat.rawRgba))!;
                    final pixels = data.buffer
                        .asUint8List(data.offsetInBytes, data.lengthInBytes);
                    final readbackMs = clock.elapsedMicroseconds / 1000;
                    if (reference == null) {
                      reference = pixels;
                    } else {
                      final diff = _pixelDiff(reference, pixels);
                      maxChangedPixels = math.max(maxChangedPixels, diff.$1);
                      maxChannelDifference =
                          math.max(maxChannelDifference, diff.$2);
                      maxMeanChannelDifference =
                          math.max(maxMeanChannelDifference, diff.$3);
                    }
                    if (trial > 0) {
                      measurements[selective]!
                          .add(_Measurement(replayMs, rasterMs, readbackMs));
                    } else if (pngDir != null) {
                      final png = (await image.toByteData(
                          format: ui.ImageByteFormat.png))!;
                      File('$pngDir/$name-${scale.toInt()}x-'
                              '${selective ? 'selective' : 'full'}.png')
                          .writeAsBytesSync(png.buffer.asUint8List(
                              png.offsetInBytes, png.lengthInBytes));
                    }
                  } finally {
                    image.dispose();
                    picture.dispose();
                  }
                }
              }
              results.add({
                'scenario': name,
                'viewPercent': scale * 100,
                'logicalZoom': scale,
                'physicalPixelsPerPoint': ratio,
                'rasterRegionPoints': [
                  region.left,
                  region.top,
                  region.width,
                  region.height
                ],
                'full': _summarize(measurements[false]!),
                'selective': _summarize(measurements[true]!),
                'wasSelective': wasSelective,
                'selectedCommands': selectedCommands,
                'identicalPixels': maxChangedPixels == 0,
                'maxChangedPixels': maxChangedPixels,
                'maxChangedPixelFraction': maxChangedPixels / (width * height),
                'maxChannelDifference': maxChannelDifference,
                'maxMeanChannelDifference': maxMeanChannelDifference,
              });
              if (env['PDF_BENCHMARK_REQUIRE_SELECTIVE'] == '1' &&
                  !wasSelective) {
                failures.add('$name ${scale}x fell back to full replay');
              }
              if (maxChangedPixels > 0) {
                failures.add('$name ${scale}x: $maxChangedPixels pixels, '
                    'maximum channel difference $maxChannelDifference');
              }
              // ignore: avoid_print
              print(
                  'measured $name ${scale}x: $selectedCommands/${commands.length} '
                  'commands; changed pixels=$maxChangedPixels');
            }
          }
          final result = {
            'pageIndex': pageIndex,
            'pageSizePoints': [scene.pageSize.width, scene.pageSize.height],
            'viewportLogicalPixels': viewport,
            'devicePixelRatio': dpr,
            'imagePhysicalPixels': [width, height],
            'commands': commands.length,
            'warmupPairs': 1,
            'measuredPairs': trials,
            'workerRecordMs': recordMs,
            'sceneBuildMs': sceneMs,
            'indexSupported': indexSupported,
            'tileEligible': scene.supportsTiledRegionRaster,
            'indexBuildMs': indexBuildMs,
            'indexUnits': scene.debugRegionReplayUnitCount,
            'indexEstimatedBytes': scene.debugRegionReplayEstimatedBytes,
            'results': results,
          };
          final json = const JsonEncoder.withIndent('  ').convert(result);
          final out = env['PDF_BENCHMARK_OUT'];
          if (out != null) File(out).writeAsStringSync(json);
          // ignore: avoid_print
          print(json);
          expect(failures, isEmpty,
              reason: 'selective replay must preserve every RGBA pixel');
        } finally {
          scene.dispose();
        }
      } finally {
        worker.dispose();
      }
    });
  }, timeout: const Timeout(Duration(minutes: 15)));
}

class _Measurement {
  const _Measurement(this.replayMs, this.rasterMs, this.readbackMs);
  final double replayMs;
  final double rasterMs;
  final double readbackMs;
}

Map<String, Object> _summarize(List<_Measurement> measurements) => {
      'medianReplayMs': _median(measurements.map((m) => m.replayMs)),
      'medianRasterMs': _median(measurements.map((m) => m.rasterMs)),
      'medianReplayAndRasterMs':
          _median(measurements.map((m) => m.replayMs + m.rasterMs)),
      'medianReadbackMs': _median(measurements.map((m) => m.readbackMs)),
      'samples': [
        for (final m in measurements)
          {
            'replayMs': m.replayMs,
            'rasterMs': m.rasterMs,
            'readbackMs': m.readbackMs
          }
      ],
    };

double _median(Iterable<double> values) {
  final sorted = values.toList()..sort();
  return sorted[sorted.length ~/ 2];
}

(int, int, double) _pixelDiff(Uint8List a, Uint8List b) {
  expect(a.length, b.length);
  var changedPixels = 0;
  var maxDifference = 0;
  var sumDifference = 0;
  for (var i = 0; i < a.length; i += 4) {
    var changed = false;
    for (var channel = 0; channel < 4; channel++) {
      final delta = (a[i + channel] - b[i + channel]).abs();
      changed |= delta != 0;
      maxDifference = math.max(maxDifference, delta);
      sumDifference += delta;
    }
    if (changed) changedPixels++;
  }
  return (changedPixels, maxDifference, sumDifference / a.length);
}
