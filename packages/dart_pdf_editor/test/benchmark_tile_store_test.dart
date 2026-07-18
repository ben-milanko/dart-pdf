// Before/after benchmark for the PdfTileStore deep-zoom path (issue #314):
// the shipping single detail patch re-rasterizes the whole visible region on
// every settle, while the tile pyramid rasterizes only the missing tiles and
// reuses the rest. This harness drives three raster strategies - the legacy
// patch, the per-tile store (batchRasters: false), and the batched store
// (one slab readback per settle, sliced GPU-side) - through the same pinch-in
// and deep-zoom pan sequences over a page's retained scene and reports the
// raster work each pays (calls, megapixels, wall time), the settle-loop wall
// clock (which for the batched store includes slab slicing), the tile reuse
// ratio, and retained bytes.
//
// Both strategies share one up-front PdfRetainedScene.record (interpret +
// decode) - the cost the zoom must never re-pay - so the numbers isolate the
// re-raster the issue targets, not the one-time record.
//
// Skips unless PDF_BENCHMARK_DIR is set:
//
//   cd packages/dart_pdf_editor
//   PDF_BENCHMARK_DIR=../../test_corpora/pdfjs \
//   PDF_BENCHMARK_TILE_RATIO=8 PDF_BENCHMARK_PAN_STEPS=10 \
//   PDF_BENCHMARK_MAX_FILES=8 \
//   PDF_BENCHMARK_OUT=../../benchmark/out/tile-store.json \
//     fvm flutter test test/benchmark_tile_store_test.dart
//
// Env knobs: PDF_BENCHMARK_VIEWPORT ("1280x1600"), PDF_BENCHMARK_TILE_RATIO
// (deep-zoom pixel ratio, 8), PDF_BENCHMARK_PAN_STEPS (10), PDF_BENCHMARK_TILE_PX
// (512), PDF_BENCHMARK_MAX_FILES (8), PDF_BENCHMARK_REPEAT (best-of-N, 1),
// PDF_BENCHMARK_OUT (JSON path; prints when unset).
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';

import 'render_smoke_test.dart' show loadSystemFonts;

/// Accumulates the region rasters a strategy issues over a settle sequence.
class _RasterMeter {
  int calls = 0;
  int pixels = 0;
  int micros = 0;

  /// Instruments one region raster from the retained scene.
  Future<ui.Image> raster(PdfRetainedScene scene, Rect region, double ratio) async {
    final sw = Stopwatch()..start();
    final image = await scene.rasterizeRegion(region, pixelRatio: ratio);
    micros += sw.elapsedMicroseconds;
    calls++;
    pixels += image.width * image.height;
    return image;
  }

  Map<String, Object?> summary(int settles) => {
        'settles': settles,
        'rasterCalls': calls,
        'rasterMegapixels': double.parse((pixels / 1e6).toStringAsFixed(2)),
        'rasterMs': double.parse((micros / 1000).toStringAsFixed(2)),
      };
}

Size _parseViewport(String? raw) {
  final parts = (raw ?? '1280x1600').split('x');
  final w = double.tryParse(parts.first) ?? 1280.0;
  final h = parts.length > 1 ? double.tryParse(parts[1]) ?? 1600.0 : 1600.0;
  return Size(w, h);
}

/// The visible page-point rect for a [viewport] (device px) at [ratio], its
/// top-left at ([ox],[oy]) page points, clamped to the page.
Rect _visibleRegion(
    Size pageSize, Size viewport, double ratio, double ox, double oy) {
  final w = math.min(viewport.width / ratio, pageSize.width);
  final h = math.min(viewport.height / ratio, pageSize.height);
  final left = ox.clamp(0.0, math.max(0.0, pageSize.width - w)).toDouble();
  final top = oy.clamp(0.0, math.max(0.0, pageSize.height - h)).toDouble();
  return Rect.fromLTWH(left, top, w, h);
}

void main() {
  final dir = Platform.environment['PDF_BENCHMARK_DIR'];
  final viewport = _parseViewport(Platform.environment['PDF_BENCHMARK_VIEWPORT']);
  final tileRatio =
      double.tryParse(Platform.environment['PDF_BENCHMARK_TILE_RATIO'] ?? '') ??
          8.0;
  final panSteps =
      int.tryParse(Platform.environment['PDF_BENCHMARK_PAN_STEPS'] ?? '') ?? 10;
  final panFraction =
      double.tryParse(Platform.environment['PDF_BENCHMARK_PAN_FRACTION'] ?? '') ??
          0.35;
  final tilePx =
      int.tryParse(Platform.environment['PDF_BENCHMARK_TILE_PX'] ?? '') ?? 512;
  final maxFiles =
      int.tryParse(Platform.environment['PDF_BENCHMARK_MAX_FILES'] ?? '') ?? 8;
  final repeat =
      int.tryParse(Platform.environment['PDF_BENCHMARK_REPEAT'] ?? '') ?? 1;
  final outPath = Platform.environment['PDF_BENCHMARK_OUT'];

  testWidgets('benchmarks tile-store vs single-patch deep-zoom detail',
      (tester) async {
    if (dir == null) {
      markTestSkipped('set PDF_BENCHMARK_DIR to run the tile-store benchmark');
      return;
    }
    await tester.runAsync(() async {
      await loadSystemFonts();
      final corpus = Directory(dir);
      final root = corpus.path.endsWith('/') ? corpus.path : '${corpus.path}/';
      final files = corpus
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.pdf'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      final selected =
          maxFiles <= 0 ? files : files.take(maxFiles).toList();

      final results = <Map<String, Object?>>[];
      for (final file in selected) {
        final name = file.path.startsWith(root)
            ? file.path.substring(root.length)
            : file.uri.pathSegments.last;
        Map<String, Object?>? best;
        for (var r = 0; r < repeat; r++) {
          final res = await _benchFile(file, name, viewport, tileRatio,
              panSteps, panFraction, tilePx, tester);
          if (res['error'] != null) {
            best ??= res;
            continue;
          }
          // Best-of-N: keep the run whose tile pan raster was fastest.
          if (best == null ||
              best['error'] != null ||
              ((res['tilePan'] as Map)['rasterMs'] as double) <
                  ((best['tilePan'] as Map)['rasterMs'] as double)) {
            best = res;
          }
        }
        results.add(best ?? {'file': name, 'error': 'not run'});
      }

      // Aggregate the raster work each strategy paid across every page.
      final ok = results.where((r) => r['error'] == null).toList();
      double sumOf(String key, String field) => ok.fold(
          0.0,
          (t, r) =>
              t + (((r[key] as Map)[field] ?? 0) as num).toDouble());
      double round1(double v) => double.parse(v.toStringAsFixed(1));
      double ratio(double a, double b) =>
          b == 0 ? 0 : double.parse((a / b).toStringAsFixed(2));

      // One phase ('Pan'/'Revisit'/'Pinch') across the three strategies.
      Map<String, Object?> phaseAgg(String phase) => {
            for (final strat in ['patch', 'tile', 'batch']) ...{
              '${strat}Megapixels':
                  round1(sumOf('$strat$phase', 'rasterMegapixels')),
              '${strat}Ms': round1(sumOf('$strat$phase', 'rasterMs')),
              '${strat}Calls': sumOf('$strat$phase', 'rasterCalls').round(),
            },
            'tileSettleMs': round1(sumOf('tile$phase', 'settleMs')),
            'batchSettleMs': round1(sumOf('batch$phase', 'settleMs')),
            'tileMegapixelSpeedup': ratio(
                sumOf('patch$phase', 'rasterMegapixels'),
                sumOf('tile$phase', 'rasterMegapixels')),
            'batchMegapixelSpeedup': ratio(
                sumOf('patch$phase', 'rasterMegapixels'),
                sumOf('batch$phase', 'rasterMegapixels')),
            'tileMsSpeedup': ratio(sumOf('patch$phase', 'rasterMs'),
                sumOf('tile$phase', 'rasterMs')),
            'batchMsSpeedup': ratio(sumOf('patch$phase', 'rasterMs'),
                sumOf('batch$phase', 'rasterMs')),
          };

      final patchRevMp = sumOf('patchRevisit', 'rasterMegapixels');
      final aggregate = {
        'pagesBenched': ok.length,
        'pan': phaseAgg('Pan'),
        'revisit': {
          ...phaseAgg('Revisit'),
          // How much of the legacy re-raster the tile cache avoided on revisit.
          'tileReusePct': patchRevMp == 0
              ? null
              : round1(100 *
                  (1 - sumOf('tileRevisit', 'rasterMegapixels') / patchRevMp)),
          'batchReusePct': patchRevMp == 0
              ? null
              : round1(100 *
                  (1 - sumOf('batchRevisit', 'rasterMegapixels') / patchRevMp)),
        },
        'pinch': phaseAgg('Pinch'),
      };
      // ignore: avoid_print
      print('  tile-store aggregate: ${const JsonEncoder().convert(aggregate)}');

      final payload = {
        'tool': 'dart-pdf-tile-store',
        'viewport': '${viewport.width.toInt()}x${viewport.height.toInt()}',
        'tileRatio': tileRatio,
        'panSteps': panSteps,
        'tilePx': tilePx,
        'aggregate': aggregate,
        'results': results,
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
  File file,
  String name,
  Size viewport,
  double tileRatio,
  int panSteps,
  double panFraction,
  int tilePx,
  WidgetTester tester,
) async {
  PdfRetainedScene scene;
  try {
    final doc = PdfDocument.open(file.readAsBytesSync());
    scene = await PdfRetainedScene.record(doc.page(0));
  } catch (e) {
    return {'file': name, 'error': e.toString()};
  }
  try {
    final pageSize = scene.pageSize;
    if (pageSize.width <= 0 || pageSize.height <= 0) {
      return {'file': name, 'error': 'empty page'};
    }
    final identity = PdfTilePageIdentity(
      pageIndex: 0,
      pageEpoch: 0,
      contentStamp: 0,
      destructiveStamp: 0,
      plan: scene.plan,
    );

    // --- Pinch-in: settle at each zoom bucket, center-anchored. ---
    final pinchRatios = <double>[1.0, 1.5, 2.0, 3.0, 4.0, tileRatio]
        .where((r) => r <= tileRatio)
        .toList();
    final patchPinch = _RasterMeter();
    for (final ratio in pinchRatios) {
      final region = _visibleRegion(
        pageSize,
        viewport,
        ratio,
        (pageSize.width - viewport.width / ratio) / 2,
        (pageSize.height - viewport.height / ratio) / 2,
      );
      (await patchPinch.raster(scene, region, ratio)).dispose();
    }

    // --- Pan geometry: fixed deep zoom, incremental drag (overlapping
    // viewports, the case tile reuse targets - each step reveals a leading
    // strip and keeps the rest). stepDx = a fraction of the visible width. ---
    final visW = math.min(viewport.width / tileRatio, pageSize.width);
    final stepDx = visW * panFraction;

    final patchPan = _RasterMeter();
    for (var i = 0; i < panSteps; i++) {
      final region =
          _visibleRegion(pageSize, viewport, tileRatio, i * stepDx, 0);
      (await patchPan.raster(scene, region, tileRatio)).dispose();
    }

    // Revisit: drag back over the just-seen area. Legacy re-rasters the full
    // region every step; a tile store reuses cached tiles (the "pan = zero
    // re-raster" claim), so its revisit raster work should be near zero.
    final patchRevisit = _RasterMeter();
    for (var i = panSteps - 2; i >= 0; i--) {
      final region =
          _visibleRegion(pageSize, viewport, tileRatio, i * stepDx, 0);
      (await patchRevisit.raster(scene, region, tileRatio)).dispose();
    }

    // One tile strategy (per-tile or batched slab), through the same pinch /
    // pan / revisit settles. settleMs is the loop's wall clock - for the
    // batched store that includes the GPU-side slab slicing the raster meter
    // can't see (both tile strategies share the same pump overhead, so they
    // compare apples-to-apples).
    Future<Map<String, Object?>> runTileStrategy({required bool batch}) async {
      final pinch = _RasterMeter();
      final pinchStore = PdfTileStore(
        tilePixels: tilePx,
        batchRasters: batch,
        registerForMemoryPressure: false,
      );
      final pinchClock = Stopwatch()..start();
      for (final ratio in pinchRatios) {
        final region = _visibleRegion(
          pageSize,
          viewport,
          ratio,
          (pageSize.width - viewport.width / ratio) / 2,
          (pageSize.height - viewport.height / ratio) / 2,
        );
        pinchStore.viewFor(
          id: identity,
          pageSize: pageSize,
          desiredRatio: ratio,
          visiblePageRect: region,
          rasterize: (r, pr) => pinch.raster(scene, r, pr),
        );
        await tester.pumpAndSettle(const Duration(milliseconds: 1));
        // Settle-to-sharp: the settle isn't over until every scheduled tile
        // has landed (or been sliced), so drain in-flight rasters inside the
        // clock window.
        while (pinchStore.inFlightCount > 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }
      pinchClock.stop();
      final pinchRetained = pinchStore.retainedBytes;
      final pinchTiles = pinchStore.tileCount;
      pinchStore.dispose();

      final panStore = PdfTileStore(
        tilePixels: tilePx,
        batchRasters: batch,
        registerForMemoryPressure: false,
      );
      Future<void> settleAt(double ox, _RasterMeter meter) async {
        final region = _visibleRegion(pageSize, viewport, tileRatio, ox, 0);
        panStore.viewFor(
          id: identity,
          pageSize: pageSize,
          desiredRatio: tileRatio,
          visiblePageRect: region,
          rasterize: (r, pr) => meter.raster(scene, r, pr),
        );
        await tester.pumpAndSettle(const Duration(milliseconds: 1));
        // Settle-to-sharp: drain in-flight rasters inside the clock window.
        while (panStore.inFlightCount > 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }

      final pan = _RasterMeter();
      final panClock = Stopwatch()..start();
      for (var i = 0; i < panSteps; i++) {
        await settleAt(i * stepDx, pan);
      }
      panClock.stop();
      final panRetained = panStore.retainedBytes;
      final panTiles = panStore.tileCount;

      final revisit = _RasterMeter();
      final revisitClock = Stopwatch()..start();
      for (var i = panSteps - 2; i >= 0; i--) {
        await settleAt(i * stepDx, revisit);
      }
      revisitClock.stop();
      panStore.dispose();

      double ms(Stopwatch sw) =>
          double.parse((sw.elapsedMicroseconds / 1000).toStringAsFixed(2));
      return {
        'pinch': {
          ...pinch.summary(pinchRatios.length),
          'settleMs': ms(pinchClock),
          'retainedKB': pinchRetained ~/ 1024,
          'tiles': pinchTiles,
        },
        'pan': {
          ...pan.summary(panSteps),
          'settleMs': ms(panClock),
          'retainedKB': panRetained ~/ 1024,
          'tiles': panTiles,
        },
        'revisit': {
          ...revisit.summary(panSteps - 1),
          'settleMs': ms(revisitClock),
        },
      };
    }

    final tiles = await runTileStrategy(batch: false);
    final batched = await runTileStrategy(batch: true);

    double mp(Map<String, Object?> s) => (s['rasterMegapixels'] as num).toDouble();
    double speedup(double a, double b) =>
        b == 0 ? 0 : double.parse((a / b).toStringAsFixed(2));

    return {
      'file': name,
      'error': null,
      'pageSize': '${pageSize.width.toInt()}x${pageSize.height.toInt()}',
      'commands': scene.commands.length,
      'regionCullable': scene.supportsRegionRaster,
      'patchPinch': patchPinch.summary(pinchRatios.length),
      'tilePinch': tiles['pinch'],
      'batchPinch': batched['pinch'],
      'patchPan': patchPan.summary(panSteps),
      'tilePan': tiles['pan'],
      'batchPan': batched['pan'],
      'patchRevisit': patchRevisit.summary(panSteps - 1),
      'tileRevisit': tiles['revisit'],
      'batchRevisit': batched['revisit'],
      'tileRevisitSpeedup': speedup(patchRevisit.pixels / 1e6,
          mp(tiles['revisit'] as Map<String, Object?>)),
      'tilePanSpeedup': speedup(
          patchPan.pixels / 1e6, mp(tiles['pan'] as Map<String, Object?>)),
      'tilePinchSpeedup': speedup(
          patchPinch.pixels / 1e6, mp(tiles['pinch'] as Map<String, Object?>)),
      'batchPanSpeedup': speedup(
          patchPan.pixels / 1e6, mp(batched['pan'] as Map<String, Object?>)),
      'batchPinchSpeedup': speedup(patchPinch.pixels / 1e6,
          mp(batched['pinch'] as Map<String, Object?>)),
    };
  } finally {
    scene.dispose();
  }
}
