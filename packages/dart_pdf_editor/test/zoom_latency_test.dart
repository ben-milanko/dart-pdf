// Zoom-settle latency harness (Track C, retained-scene zoom experiment).
//
// Measures the per-step cost of re-rendering a page at a new zoom level for
// three paths, at a scale-to-fit baseline for a ~2382x1684 target device:
//
//   (a) current   - the shipping pdf_page_view path: a cached ui.Picture is
//                   re-rasterized via PdfPageRenderer.rasterize (drawPicture
//                   at the new ratio + toImage).
//   (b) retained  - PdfRetainedScene.replay: the recorded command buffer is
//                   re-issued through CanvasPdfDevice at the new ratio (no
//                   re-interpret, no re-decode), then toImage.
//   (c) full      - reference: full re-render (re-interpret + decode via the
//                   warm PdfImageCache + paint) then toImage.
//
// Each timed step splits into build (picture production), raster (toImage)
// and readback (toByteData(rawRgba), forcing full realization so GPU-backed
// backends can't defer the raster past the clock). Run both ways:
//
//   cd packages/dart_pdf_editor
//   ZOOM_CORPUS_DIR=/Users/ben/repos/dart-pdf/corpus \
//     fvm flutter test test/zoom_latency_test.dart
//   ZOOM_CORPUS_DIR=/Users/ben/repos/dart-pdf/corpus \
//     fvm flutter test --enable-impeller test/zoom_latency_test.dart
//
// Skips cleanly when the corpus directory is absent (it is git-ignored and
// only exists in the main checkout). Override the page set with
// ZOOM_LATENCY_FILES (comma-separated, relative to the corpus dir or
// absolute) and ZOOM_LATENCY_PAGE (page index, default 0); passes with
// ZOOM_LATENCY_PASSES (default 3); label the backend column with
// ZOOM_BACKEND (e.g. "impeller") since the flag is invisible from inside.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/strips.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';

import 'render_smoke_test.dart' show loadSystemFonts;

/// The zoom sequence a settle-by-settle pinch session produces.
const zoomSequence = [1.0, 1.5, 2.4, 1.2, 3.0];

/// Target device size the page is scale-to-fit into at zoom 1.
const targetWidth = 2382.0;
const targetHeight = 1684.0;

// pdf_page_view's full-page raster caps, applied identically to every path
// so the numbers reflect what the viewer would actually rasterize.
const _maxPixels = 1 << 24;
const _maxDimension = 8192.0;

const _defaultFiles = [
  'Flutter_CTO_Report_2024_by_LeanCode.pdf', // office: report, text + images
  'INVOICE-1000664832.pdf', // office: invoice, text-heavy
  // CAD: the known dense-vector stress case; page 4 is its heaviest sheet
  // (~677k content operators - page 0 is a light title sheet).
  'ly9-far-cad.pdf#4',
];

class _Sample {
  double buildMs = 0;
  double rasterMs = 0;
  double readbackMs = 0;
  int n = 0;

  void add(double build, double raster, double readback) {
    buildMs += build;
    rasterMs += raster;
    readbackMs += readback;
    n++;
  }

  double get meanBuild => n == 0 ? 0 : buildMs / n;
  double get meanRaster => n == 0 ? 0 : rasterMs / n;
  double get meanReadback => n == 0 ? 0 : readbackMs / n;
  double get meanTotal => meanBuild + meanRaster + meanReadback;
}

double _effectiveRatio(Size size, double desired) {
  final width = math.max(1.0, size.width);
  final height = math.max(1.0, size.height);
  var ratio = desired;
  ratio = math.min(ratio, math.sqrt(_maxPixels / (width * height)));
  ratio = math.min(ratio, _maxDimension / math.max(width, height));
  return math.max(ratio, 0.05);
}

Future<(ui.Image, double, double)> _timeRaster(
    ui.Picture picture, int width, int height) async {
  final sw = Stopwatch()..start();
  final image = await picture.toImage(
      width.clamp(1, 1 << 14), height.clamp(1, 1 << 14));
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
  final pageIndex =
      int.tryParse(Platform.environment['ZOOM_LATENCY_PAGE'] ?? '') ?? 0;
  final passes =
      int.tryParse(Platform.environment['ZOOM_LATENCY_PASSES'] ?? '') ?? 3;
  final filesEnv = Platform.environment['ZOOM_LATENCY_FILES'];
  final fileNames = filesEnv == null || filesEnv.trim().isEmpty
      ? _defaultFiles
      : filesEnv.split(',').map((s) => s.trim()).toList();

  testWidgets('zoom-settle latency: cached-picture vs retained-scene vs full',
      (tester) async {
    final dir = Directory(corpusDir);
    if (!dir.existsSync()) {
      markTestSkipped('corpus directory not found at $corpusDir '
          '(set ZOOM_CORPUS_DIR); skipping the zoom latency harness');
      return;
    }
    await tester.runAsync(() async {
      await loadSystemFonts();

      final rows = <String>[];
      final stepRows = <String>[];

      for (final entry in fileNames) {
        // "name.pdf#12" selects a page for that file; bare names use
        // ZOOM_LATENCY_PAGE.
        final hash = entry.lastIndexOf('#');
        final name = hash < 0 ? entry : entry.substring(0, hash);
        final filePage = hash < 0
            ? pageIndex
            : int.tryParse(entry.substring(hash + 1)) ?? pageIndex;
        final path = name.startsWith('/') ? name : '${dir.path}/$name';
        final file = File(path);
        if (!file.existsSync()) {
          // ignore: avoid_print
          print('zoom-latency: $path missing, skipped');
          continue;
        }
        final doc = PdfDocument.open(file.readAsBytesSync());
        final page = doc.page(filePage.clamp(0, doc.pageCount - 1));
        const plan = PdfPageRenderPlan();
        final size = plan.pageSize(page);
        final fit = [targetWidth / size.width, targetHeight / size.height]
            .reduce((a, b) => a < b ? a : b);

        // --- Untimed one-off costs (reported for context) ---------------
        var sw = Stopwatch()..start();
        final cachedPicture =
            await PdfPageRenderer.renderPictureRecordedWithPlan(page, plan);
        final interpretMs = sw.elapsedMicroseconds / 1000.0;
        sw = Stopwatch()..start();
        final scene = await PdfRetainedScene.record(page, plan: plan);
        final recordMs = sw.elapsedMicroseconds / 1000.0;

        final label = '${name.split('/').last}#$filePage';
        // ignore: avoid_print
        print('zoom-latency: $label page=$filePage '
            'size=${size.width.toStringAsFixed(0)}x'
            '${size.height.toStringAsFixed(0)}pt fit=${fit.toStringAsFixed(2)} '
            'commands=${scene.commands.length} '
            'interpret=${interpretMs.toStringAsFixed(1)}ms '
            'record+decode=${recordMs.toStringAsFixed(1)}ms');

        final samples = {
          'a-current': _Sample(),
          'b-retained': _Sample(),
          'c-full': _Sample(),
        };
        final perStep = {
          for (final key in samples.keys)
            key: [for (final _ in zoomSequence) _Sample()],
        };

        // pass 0 is warmup (codec/shader/pipeline caches) and is discarded
        for (var pass = 0; pass <= passes; pass++) {
          final record = pass > 0;
          for (var step = 0; step < zoomSequence.length; step++) {
            final ratio = _effectiveRatio(size, fit * zoomSequence[step]);
            final w = (size.width * ratio).ceil();
            final h = (size.height * ratio).ceil();

            // (a) current: re-rasterize the cached ui.Picture (what
            // pdf_page_view._renderNow does via PdfPageRenderer.rasterize).
            var t = Stopwatch()..start();
            final scaledRecorder = ui.PictureRecorder();
            Canvas(scaledRecorder)
              ..scale(ratio)
              ..drawPicture(cachedPicture);
            final scaled = scaledRecorder.endRecording();
            final buildA = t.elapsedMicroseconds / 1000.0;
            final (imageA, rasterA, readbackA) = await _timeRaster(scaled, w, h);
            scaled.dispose();
            imageA.dispose();
            if (record) {
              samples['a-current']!.add(buildA, rasterA, readbackA);
              perStep['a-current']![step].add(buildA, rasterA, readbackA);
            }

            // (b) retained scene: replay the command buffer at the new ratio.
            t = Stopwatch()..start();
            final replayed = scene.replay(pixelRatio: ratio);
            final buildB = t.elapsedMicroseconds / 1000.0;
            final (imageB, rasterB, readbackB) =
                await _timeRaster(replayed, w, h);
            replayed.dispose();
            imageB.dispose();
            if (record) {
              samples['b-retained']!.add(buildB, rasterB, readbackB);
              perStep['b-retained']![step].add(buildB, rasterB, readbackB);
            }

            // (c) full re-render: re-interpret + decode (warm cache) + paint.
            t = Stopwatch()..start();
            final full =
                await PdfPageRenderer.renderPictureRecordedWithPlan(page, plan);
            final fullRecorder = ui.PictureRecorder();
            Canvas(fullRecorder)
              ..scale(ratio)
              ..drawPicture(full);
            final fullScaled = fullRecorder.endRecording();
            final buildC = t.elapsedMicroseconds / 1000.0;
            final (imageC, rasterC, readbackC) =
                await _timeRaster(fullScaled, w, h);
            fullScaled.dispose();
            full.dispose();
            imageC.dispose();
            if (record) {
              samples['c-full']!.add(buildC, rasterC, readbackC);
              perStep['c-full']![step].add(buildC, rasterC, readbackC);
            }
          }
        }

        for (final entry in samples.entries) {
          final s = entry.value;
          rows.add('${label.padRight(44).substring(0, 44)} '
              '${entry.key.padRight(11)} '
              '${s.meanBuild.toStringAsFixed(1).padLeft(8)} '
              '${s.meanRaster.toStringAsFixed(1).padLeft(8)} '
              '${s.meanReadback.toStringAsFixed(1).padLeft(9)} '
              '${s.meanTotal.toStringAsFixed(1).padLeft(8)}');
        }
        for (var step = 0; step < zoomSequence.length; step++) {
          final parts = [
            for (final key in samples.keys)
              '$key=${perStep[key]![step].meanTotal.toStringAsFixed(1)}'
          ];
          stepRows.add('${label.padRight(44).substring(0, 44)} '
              'zoom=${zoomSequence[step].toStringAsFixed(1)} '
              '${parts.join('  ')}');
        }

        scene.dispose();
        cachedPicture.dispose();
      }

      if (rows.isEmpty) {
        markTestSkipped('no test PDFs found under $corpusDir');
        return;
      }
      // ignore: avoid_print
      print('\nzoom-settle latency (backend=$backend, mean ms/step over '
          '$passes passes x ${zoomSequence.length} steps, '
          'target ${targetWidth.toInt()}x${targetHeight.toInt()} fit)');
      // ignore: avoid_print
      print('${'page'.padRight(44)} ${'path'.padRight(11)} '
          '${'build'.padLeft(8)} ${'toImage'.padLeft(8)} '
          '${'readback'.padLeft(9)} ${'total'.padLeft(8)}');
      for (final row in rows) {
        // ignore: avoid_print
        print(row);
      }
      // ignore: avoid_print
      print('\nper-zoom-step totals (ms, build+toImage+readback):');
      for (final row in stepRows) {
        // ignore: avoid_print
        print(row);
      }
    });
  }, timeout: const Timeout(Duration(minutes: 15)));
}
