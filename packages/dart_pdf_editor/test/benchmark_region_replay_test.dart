// Opt-in real-document A/B for retained deep-zoom region replay. The document
// stays local; no PDF is copied into the repository. Example:
// PDF_PATH=/path/to/file.pdf PDF_PAGE=0 PDF_REGION_REPEAT=3 \
//   fvm flutter test test/benchmark_region_replay_test.dart
// PDF_REGIONS is a semicolon-separated list of x,y,width,height in page-view
// points. Defaults sweep five small regions across the page at 2 px/pt.
// Times exclude document recording, image decoding and one-time index build;
// each sample includes canvas replay, rasterization and realized RGBA readback.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_test/flutter_test.dart';

import 'render_smoke_test.dart' show loadSystemFonts;

double _median(List<double> values) {
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

void main() {
  testWidgets('real-document region replay A/B with exact pixel comparison',
      (tester) async {
    final path = Platform.environment['PDF_PATH'];
    if (path == null) {
      markTestSkipped('set PDF_PATH to run the region benchmark');
      return;
    }
    final previous = PdfRetainedScene.spatialRegionReplay;
    addTearDown(() => PdfRetainedScene.spatialRegionReplay = previous);
    await tester.runAsync(() async {
      await loadSystemFonts();
      final pageIndex = int.parse(Platform.environment['PDF_PAGE'] ?? '0');
      final repeats =
          int.parse(Platform.environment['PDF_REGION_REPEAT'] ?? '3');
      final ratio =
          double.parse(Platform.environment['PDF_PIXEL_RATIO'] ?? '2');
      expect(repeats, greaterThan(0));
      final document = PdfDocument.open(File(path).readAsBytesSync());
      final scene = await PdfRetainedScene.record(document.page(pageIndex),
          maxImagePixelRatio: ratio);
      try {
        final size = scene.pageSize;
        final encodedRegions = Platform.environment['PDF_REGIONS'];
        final regions = encodedRegions == null
            ? <ui.Rect>[
                for (var i = 0; i < 5; i++)
                  ui.Rect.fromLTWH((size.width - 128) * i / 4,
                      (size.height - 128) / 2, 128, 128)
              ]
            : <ui.Rect>[
                for (final item in encodedRegions.split(';'))
                  (() {
                    final v = item.split(',').map(double.parse).toList();
                    return ui.Rect.fromLTWH(v[0], v[1], v[2], v[3]);
                  })()
              ];
        PdfRetainedScene.spatialRegionReplay = true;
        final indexClock = Stopwatch()..start();
        final supported = scene.supportsRegionRaster;
        indexClock.stop();
        final rows = <Map<String, Object?>>[];
        for (final region in regions) {
          final fullMs = <double>[];
          final selectiveMs = <double>[];
          var selectedCommands = 0;
          // Discard one warmup pair; alternate order to avoid always giving
          // one route the warmed engine/path caches.
          for (var sample = -1; sample < repeats; sample++) {
            Uint8List? reference;
            for (final selective
                in sample.isEven ? [true, false] : [false, true]) {
              PdfRetainedScene.spatialRegionReplay = selective;
              final clock = Stopwatch()..start();
              final image =
                  await scene.rasterizeRegion(region, pixelRatio: ratio);
              try {
                final pixels = (await image.toByteData(
                        format: ui.ImageByteFormat.rawRgba))!
                    .buffer
                    .asUint8List();
                clock.stop();
                if (reference == null) {
                  reference = pixels;
                } else {
                  expect(listEquals(pixels, reference), isTrue,
                      reason: 'region pixels changed at $region');
                }
                if (selective) {
                  selectedCommands = scene.debugLastRegionReplayCommandCount;
                }
                if (sample >= 0) {
                  (selective ? selectiveMs : fullMs)
                      .add(clock.elapsedMicroseconds / 1000);
                }
              } finally {
                image.dispose();
              }
            }
          }
          rows.add({
            'region': [region.left, region.top, region.width, region.height],
            'fullCommands': scene.commands.length,
            'selectiveCommands': selectedCommands,
            'fullP50Ms': _median(fullMs),
            'selectiveP50Ms': _median(selectiveMs),
            'pixelsIdentical': true,
          });
        }
        final result = {
          'page': pageIndex + 1,
          'repeat': repeats,
          'pixelRatio': ratio,
          'indexSupported': supported,
          'indexBuildMs': indexClock.elapsedMicroseconds / 1000,
          'indexBytes': scene.debugRegionReplayEstimatedBytes,
          'regions': rows,
        };
        final output = Platform.environment['PDF_REGION_OUT'];
        final json = const JsonEncoder.withIndent('  ').convert(result);
        if (output != null) File(output).writeAsStringSync(json);
        // ignore: avoid_print
        print(json);
      } finally {
        scene.dispose();
      }
    });
  }, timeout: const Timeout(Duration(minutes: 10)));
}
