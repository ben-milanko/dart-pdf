// Worker-binned strip settles vs #210's local-bin path (the measurement
// behind flipping PdfPageView.stripZoomReplay's default).
//
// For each corpus page, a worker-backed retained scene runs the zoom
// sequence through:
//
//   (L) local-bin   - scene.replayStrips(ratio): the strip re-bin runs on
//                     this (the UI) thread, #210's shipping path;
//   (W) worker-plan - worker.binStrips(...) off-thread, then
//                     scene.replayStrips(ratio, stripPlan:): the UI thread
//                     only decodes the plan, creates engine objects, and
//                     replays the tape.
//
// Reported per path: total settle latency (bin/plan wait + build + toImage
// + readback) and the UI-THREAD BLOCKING share - the synchronous sections
// only: route+bin (StripPdfDevice.totalRouteMicros), tape replay
// (totalReplayMicros), and for (W) the plan decode (decodeStripPlanMicros).
// The worker wait and the GPU raster are awaited, not blocking.
//
// Passes: pass 0 warms codec/shader/worker caches and is discarded; the
// per-pass worker bin wait is also printed so the worker-side command/
// glyph/shape cache steady-state effect is visible.
//
// Run on Impeller (the only backend that strip-routes in production):
//
//   cd packages/dart_pdf_editor
//   ZOOM_CORPUS_DIR=/Users/ben/repos/dart-pdf/corpus \
//     fvm flutter test --enable-impeller test/strip_worker_latency_test.dart
//
// Skips cleanly when the corpus directory is absent.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/strips.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/raster.dart' as raster show decodeStripPlanMicros;

import 'render_smoke_test.dart' show loadSystemFonts;

const zoomSequence = [1.0, 1.5, 2.4, 1.2, 3.0];
const targetWidth = 2382.0;
const targetHeight = 1684.0;
const _maxPixels = 1 << 24;
const _maxDimension = 8192.0;

const _defaultFiles = [
  'WAT_L0001_S.pdf', // the WAT CAD sheet from #210's numbers
  'ly9-far-cad.pdf#4', // heaviest ly9 sheet (~99k retained commands)
  'INVOICE-1000664832.pdf', // office control: under the ceiling, no strips
];

double _effectiveRatio(Size size, double desired) {
  final width = math.max(1.0, size.width);
  final height = math.max(1.0, size.height);
  var ratio = desired;
  ratio = math.min(ratio, math.sqrt(_maxPixels / (width * height)));
  ratio = math.min(ratio, _maxDimension / math.max(width, height));
  return math.max(ratio, 0.05);
}

class _PathSample {
  double planWaitMs = 0; // (W) worker bin round-trip wall
  double buildMs = 0; // replayStrips wall
  double rasterMs = 0; // toImage
  double readbackMs = 0; // toByteData
  double uiBlockMs = 0; // synchronous UI-thread sections
  int n = 0;

  void add(
      {required double planWait,
      required double build,
      required double rasterize,
      required double readback,
      required double uiBlock}) {
    planWaitMs += planWait;
    buildMs += build;
    rasterMs += rasterize;
    readbackMs += readback;
    uiBlockMs += uiBlock;
    n++;
  }

  double _mean(double v) => n == 0 ? 0 : v / n;
  double get meanPlanWait => _mean(planWaitMs);
  double get meanBuild => _mean(buildMs);
  double get meanRaster => _mean(rasterMs);
  double get meanReadback => _mean(readbackMs);
  double get meanUiBlock => _mean(uiBlockMs);
  double get meanTotal =>
      meanPlanWait + meanBuild + meanRaster + meanReadback;
}

Future<(ui.Image, double, double)> _timeRaster(
    ui.Picture picture, int width, int height) async {
  final sw = Stopwatch()..start();
  final image =
      await picture.toImage(width.clamp(1, 1 << 14), height.clamp(1, 1 << 14));
  final rasterMs = sw.elapsedMicroseconds / 1000.0;
  sw
    ..reset()
    ..start();
  await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final readbackMs = sw.elapsedMicroseconds / 1000.0;
  return (image, rasterMs, readbackMs);
}

void main() {
  final corpusDir = Platform.environment['ZOOM_CORPUS_DIR'] ?? '../../corpus';
  final backend = Platform.environment['ZOOM_BACKEND'] ?? 'default';
  final passes =
      int.tryParse(Platform.environment['ZOOM_LATENCY_PASSES'] ?? '') ?? 3;
  final filesEnv = Platform.environment['STRIP_WORKER_FILES'];
  final fileNames = filesEnv == null || filesEnv.trim().isEmpty
      ? _defaultFiles
      : filesEnv.split(',').map((s) => s.trim()).toList();

  testWidgets('strip settle latency: local bin vs worker plan',
      (tester) async {
    final dir = Directory(corpusDir);
    if (!dir.existsSync()) {
      markTestSkipped('corpus directory not found at $corpusDir '
          '(set ZOOM_CORPUS_DIR); skipping the strip worker harness');
      return;
    }
    await tester.runAsync(() async {
      await loadSystemFonts();

      final rows = <String>[];
      final binWaitRows = <String>[];

      for (final entry in fileNames) {
        final hash = entry.lastIndexOf('#');
        final name = hash < 0 ? entry : entry.substring(0, hash);
        final filePage =
            hash < 0 ? 0 : int.tryParse(entry.substring(hash + 1)) ?? 0;
        final path = name.startsWith('/') ? name : '${dir.path}/$name';
        final file = File(path);
        if (!file.existsSync()) {
          // ignore: avoid_print
          print('strip-worker-latency: $path missing, skipped');
          continue;
        }
        final bytes = file.readAsBytesSync();
        final doc = PdfDocument.open(bytes);
        final pageIndex = filePage.clamp(0, doc.pageCount - 1);
        final page = doc.page(pageIndex);
        const plan = PdfPageRenderPlan();
        final size = plan.pageSize(page);
        final fit = [targetWidth / size.width, targetHeight / size.height]
            .reduce((a, b) => a < b ? a : b);

        final worker = PdfRenderWorker.startUncached(bytes);
        final commands = await worker.record(pageIndex,
            imagePixelRatio: _effectiveRatio(size, fit));
        if (commands == null) {
          // ignore: avoid_print
          print('strip-worker-latency: $entry declined by the worker, '
              'skipped (would keep local binning in production)');
          worker.dispose();
          continue;
        }
        final scene =
            await PdfRetainedScene.fromCommands(page, commands, plan: plan);
        final label = '${name.split('/').last}#$pageIndex';
        final overCeiling = scene.commands.length >
            PdfPageView.retainedZoomReplayMaxCommands;
        // ignore: avoid_print
        print('strip-worker-latency: $label commands=${scene.commands.length}'
            ' stripRouted=$overCeiling'
            '${overCeiling ? '' : ' (control: keeps the flat canvas replay)'}');

        if (!overCeiling) {
          // Office control: the page never strip-routes; its settle path
          // (scene.rasterize, untouched by this work) is timed for the
          // regression row.
          final s = _PathSample();
          for (var pass = 0; pass <= passes; pass++) {
            for (final zoom in zoomSequence) {
              final ratio = _effectiveRatio(size, fit * zoom);
              final sw = Stopwatch()..start();
              final image = await scene.rasterize(pixelRatio: ratio);
              final total = sw.elapsedMicroseconds / 1000.0;
              await image.toByteData(format: ui.ImageByteFormat.rawRgba);
              final readback =
                  sw.elapsedMicroseconds / 1000.0 - total;
              image.dispose();
              if (pass > 0) {
                s.add(
                    planWait: 0,
                    build: total,
                    rasterize: 0,
                    readback: readback,
                    uiBlock: 0);
              }
            }
          }
          rows.add('${label.padRight(28).substring(0, 28)} '
              '${'b-retained'.padRight(12)} '
              '${'-'.padLeft(8)} ${s.meanBuild.toStringAsFixed(1).padLeft(8)} '
              '${'-'.padLeft(8)} '
              '${s.meanReadback.toStringAsFixed(1).padLeft(9)} '
              '${'-'.padLeft(8)} ${s.meanTotal.toStringAsFixed(1).padLeft(8)}');
          scene.dispose();
          worker.dispose();
          continue;
        }

        final local = _PathSample();
        final workerPlan = _PathSample();
        final perPassBinWait = List<double>.filled(passes + 1, 0);

        for (var pass = 0; pass <= passes; pass++) {
          final record = pass > 0;
          for (final zoom in zoomSequence) {
            final ratio = _effectiveRatio(size, fit * zoom);
            final w = (size.width * ratio).ceil();
            final h = (size.height * ratio).ceil();

            // (L) local bin on this thread.
            StripPdfDevice.resetStats();
            var t = Stopwatch()..start();
            final localPicture = await scene.replayStrips(pixelRatio: ratio);
            final buildL = t.elapsedMicroseconds / 1000.0;
            final uiBlockL = (StripPdfDevice.totalRouteMicros +
                    StripPdfDevice.totalReplayMicros) /
                1000.0;
            final (imageL, rasterL, readbackL) =
                await _timeRaster(localPicture, w, h);
            localPicture.dispose();
            imageL.dispose();
            if (record) {
              local.add(
                  planWait: 0,
                  build: buildL,
                  rasterize: rasterL,
                  readback: readbackL,
                  uiBlock: uiBlockL);
            }

            // (W) worker-binned plan.
            StripPdfDevice.resetStats();
            final decode0 = raster.decodeStripPlanMicros;
            final geometry = scene.stripGeometry(pixelRatio: ratio);
            final m = geometry.pageToDevice;
            t = Stopwatch()..start();
            final stripPlan = await worker.binStrips(pageIndex,
                annotations: true,
                pageToDevice: [m.a, m.b, m.c, m.d, m.e, m.f],
                deviceWidth: geometry.width,
                deviceHeight: geometry.height,
                pixelRatio: ratio);
            final planWait = t.elapsedMicroseconds / 1000.0;
            expect(stripPlan, isNotNull,
                reason: '$label must bin off-thread');
            t = Stopwatch()..start();
            final plannedPicture = await scene.replayStrips(
                pixelRatio: ratio, stripPlan: stripPlan);
            final buildW = t.elapsedMicroseconds / 1000.0;
            expect(StripPdfDevice.totalPlanMismatches, 0);
            expect(StripPdfDevice.totalPlanPictures, 1,
                reason: 'the plan must actually be consumed');
            final uiBlockW = (StripPdfDevice.totalRouteMicros +
                    StripPdfDevice.totalReplayMicros +
                    (raster.decodeStripPlanMicros - decode0)) /
                1000.0;
            final (imageW, rasterW, readbackW) =
                await _timeRaster(plannedPicture, w, h);
            plannedPicture.dispose();
            imageW.dispose();
            perPassBinWait[pass] += planWait;
            if (record) {
              workerPlan.add(
                  planWait: planWait,
                  build: buildW,
                  rasterize: rasterW,
                  readback: readbackW,
                  uiBlock: uiBlockW);
            }
          }
        }

        for (final (key, s) in [('L-local-bin', local), ('W-worker', workerPlan)]) {
          rows.add('${label.padRight(28).substring(0, 28)} '
              '${key.padRight(12)} '
              '${s.meanPlanWait.toStringAsFixed(1).padLeft(8)} '
              '${s.meanBuild.toStringAsFixed(1).padLeft(8)} '
              '${s.meanRaster.toStringAsFixed(1).padLeft(8)} '
              '${s.meanReadback.toStringAsFixed(1).padLeft(9)} '
              '${s.meanUiBlock.toStringAsFixed(1).padLeft(8)} '
              '${s.meanTotal.toStringAsFixed(1).padLeft(8)}');
        }
        binWaitRows.add('${label.padRight(28).substring(0, 28)} '
            'binWait/settle by pass: ${[
          for (var p = 0; p <= passes; p++)
            (perPassBinWait[p] / zoomSequence.length).toStringAsFixed(1)
        ].join('  ')}  (pass 0 = cold)');

        scene.dispose();
        worker.dispose();
      }

      if (rows.isEmpty) {
        markTestSkipped('no test PDFs found under $corpusDir');
        return;
      }
      // ignore: avoid_print
      print('\nstrip settle latency (backend=$backend, mean ms/step over '
          '$passes passes x ${zoomSequence.length} steps, '
          'target ${targetWidth.toInt()}x${targetHeight.toInt()} fit)');
      // ignore: avoid_print
      print('${'page'.padRight(28)} ${'path'.padRight(12)} '
          '${'binWait'.padLeft(8)} ${'build'.padLeft(8)} '
          '${'toImage'.padLeft(8)} ${'readback'.padLeft(9)} '
          '${'uiBlock'.padLeft(8)} ${'total'.padLeft(8)}');
      for (final row in rows) {
        // ignore: avoid_print
        print(row);
      }
      // ignore: avoid_print
      print('\nworker bin wait per settle by pass (worker-side command/'
          'glyph/shape caches warming):');
      for (final row in binWaitRows) {
        // ignore: avoid_print
        print(row);
      }
    });
  }, timeout: const Timeout(Duration(minutes: 15)));
}
