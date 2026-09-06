// Display-pipeline-shaped companion to strip_worker_latency_test.dart.
//
// The older harness deliberately reads every raster back to RGBA so it can
// double as a pixel-correctness probe. That synchronous readback is not part
// of PdfPageView's settle path and can dwarf the latency a user sees. This
// harness stops at the first RawImage frame carrying the newly-rasterized
// page, records FrameTiming when the test backend exposes it, and never calls
// ui.Image.toByteData.
//
// Run on Impeller with the same corpus used by the correctness harness:
//
//   cd packages/dart_pdf_editor
//   ZOOM_CORPUS_DIR=/Users/ben/repos/dart-pdf/corpus \
//     fvm flutter test --enable-impeller test/strip_display_latency_test.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart' show deserializeCommandsMicros;
import 'package:pdf_graphics/raster.dart' show StripPlan;

import 'render_smoke_test.dart' show loadSystemFonts;

const _zoomSequence = [1.0, 1.5, 2.4, 1.2, 3.0];
const _targetWidth = 2382.0;
const _targetHeight = 1684.0;
const _maxPixels = PdfPageRasterGeometry.maxPixels;
const _maxDimension = 8192.0;
const _defaultFiles = ['WAT_L0001_S.pdf', 'ly9-far-cad.pdf#4'];

double _effectiveRatio(Size size, double desired) {
  var ratio = desired;
  ratio = math.min(ratio, math.sqrt(_maxPixels / (size.width * size.height)));
  ratio = math.min(ratio, _maxDimension / math.max(size.width, size.height));
  return math.max(ratio, 0.05);
}

class _Case {
  const _Case(this.label, this.pageIndex, this.page, this.scene, this.worker,
      this.fit, this.commandDecodeMs);

  final String label;
  final int pageIndex;
  final PdfPage page;
  final PdfRetainedScene scene;
  final PdfRenderWorker worker;
  final double fit;
  final double commandDecodeMs;
}

class _Prepared {
  const _Prepared(this.image, this.planWaitMs, this.buildMs, this.toImageMs);

  final ui.Image image;
  final double planWaitMs;
  final double buildMs;
  final double toImageMs;
}

class _Sample {
  double planWaitMs = 0;
  double buildMs = 0;
  double toImageMs = 0;
  double presentWallMs = 0;
  double frameBuildMs = 0;
  double frameRasterMs = 0;
  double frameTotalMs = 0;
  int n = 0;

  void add(_Prepared prepared, _Presented presented) {
    planWaitMs += prepared.planWaitMs;
    buildMs += prepared.buildMs;
    toImageMs += prepared.toImageMs;
    presentWallMs += presented.wallMs;
    frameBuildMs += presented.buildMs;
    frameRasterMs += presented.rasterMs;
    frameTotalMs += presented.totalMs;
    n++;
  }

  double mean(double value) => n == 0 ? 0 : value / n;
  double get firstPresentMs =>
      mean(planWaitMs + buildMs + toImageMs + presentWallMs);
}

class _Presented {
  const _Presented(this.wallMs, this.buildMs, this.rasterMs, this.totalMs);

  final double wallMs;
  final double buildMs;
  final double rasterMs;
  final double totalMs;
}

Future<_Prepared> _prepare(
  _Case testCase,
  double ratio,
  String path,
) async {
  final geometry = testCase.scene.stripGeometry(pixelRatio: ratio);
  final m = geometry.pageToDevice;
  Future<StripPlan?> requestPlan() => testCase.worker.binStrips(
        testCase.pageIndex,
        annotations: true,
        pageToDevice: [m.a, m.b, m.c, m.d, m.e, m.f],
        deviceWidth: geometry.width,
        deviceHeight: geometry.height,
        pixelRatio: ratio,
      );

  StripPlan? plan;
  var planWaitMs = 0.0;
  if (path == 'worker') {
    final sw = Stopwatch()..start();
    plan = await requestPlan();
    planWaitMs = sw.elapsedMicroseconds / 1000.0;
  } else if (path == 'primed') {
    final pending = requestPlan();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final sw = Stopwatch()..start();
    plan = await pending;
    planWaitMs = sw.elapsedMicroseconds / 1000.0;
  }
  if (path != 'local' && plan == null) {
    throw StateError('worker declined $path strip plan');
  }

  var sw = Stopwatch()..start();
  final picture =
      await testCase.scene.replayStrips(pixelRatio: ratio, stripPlan: plan);
  final buildMs = sw.elapsedMicroseconds / 1000.0;
  sw = Stopwatch()..start();
  final image = await picture.toImage(
    (testCase.scene.pageSize.width * ratio).ceil().clamp(1, 1 << 14),
    (testCase.scene.pageSize.height * ratio).ceil().clamp(1, 1 << 14),
  );
  final toImageMs = sw.elapsedMicroseconds / 1000.0;
  picture.dispose();
  return _Prepared(image, planWaitMs, buildMs, toImageMs);
}

Future<_Presented> _present(WidgetTester tester, ui.Image image) async {
  final timings = <FrameTiming>[];
  void onTimings(List<FrameTiming> batch) => timings.addAll(batch);
  SchedulerBinding.instance.addTimingsCallback(onTimings);
  final sw = Stopwatch()..start();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RawImage(
          key: ValueKey(image),
          image: image,
          fit: BoxFit.contain,
        ),
      ),
    ),
  );
  final wallMs = sw.elapsedMicroseconds / 1000.0;
  SchedulerBinding.instance.removeTimingsCallback(onTimings);
  final timing = timings.isEmpty ? null : timings.last;
  double ms(Duration? duration) =>
      duration == null ? 0 : duration.inMicroseconds / 1000.0;
  return _Presented(
    wallMs,
    ms(timing?.buildDuration),
    ms(timing?.rasterDuration),
    ms(timing?.totalSpan),
  );
}

void main() {
  final corpusDir = Platform.environment['ZOOM_CORPUS_DIR'] ?? '../../corpus';
  final passes =
      int.tryParse(Platform.environment['ZOOM_LATENCY_PASSES'] ?? '') ?? 3;
  final filesEnv = Platform.environment['STRIP_WORKER_FILES'];
  final files = filesEnv == null || filesEnv.trim().isEmpty
      ? _defaultFiles
      : filesEnv.split(',').map((value) => value.trim()).toList();

  testWidgets('strip settle latency to first displayed frame', (tester) async {
    final directory = Directory(corpusDir);
    if (!directory.existsSync()) {
      markTestSkipped('corpus directory not found at $corpusDir');
      return;
    }

    final testCase = await tester.runAsync<_Case?>(() async {
      await loadSystemFonts();
      for (final entry in files) {
        final hash = entry.lastIndexOf('#');
        final name = hash < 0 ? entry : entry.substring(0, hash);
        final requestedPage =
            hash < 0 ? 0 : int.tryParse(entry.substring(hash + 1)) ?? 0;
        final file =
            File(name.startsWith('/') ? name : '${directory.path}/$name');
        if (!file.existsSync()) continue;
        final bytes = file.readAsBytesSync();
        final document = PdfDocument.open(bytes);
        final pageIndex = requestedPage.clamp(0, document.pageCount - 1);
        final page = document.page(pageIndex);
        final size = const PdfPageRenderPlan().pageSize(page);
        final fit =
            math.min(_targetWidth / size.width, _targetHeight / size.height);
        final worker = PdfRenderWorker.startUncached(bytes);
        final decodeBefore = deserializeCommandsMicros;
        final commands = await worker.record(pageIndex,
            imagePixelRatio: _effectiveRatio(size, fit));
        final commandDecodeMs =
            (deserializeCommandsMicros - decodeBefore) / 1000.0;
        if (commands == null) {
          worker.dispose();
          continue;
        }
        final scene = await PdfRetainedScene.fromCommands(page, commands);
        if (scene.commands.length <=
            PdfPageView.retainedZoomReplayMaxCommands) {
          scene.dispose();
          worker.dispose();
          continue;
        }
        return _Case('${name.split('/').last}#$pageIndex', pageIndex, page,
            scene, worker, fit, commandDecodeMs);
      }
      return null;
    });
    if (testCase == null) {
      markTestSkipped('no worker-backed strip-routed corpus page found');
      return;
    }
    addTearDown(testCase.scene.dispose);
    addTearDown(testCase.worker.dispose);

    final samples = {
      'local': _Sample(),
      'worker': _Sample(),
      'primed': _Sample(),
    };
    for (var pass = 0; pass <= passes; pass++) {
      for (final zoom in _zoomSequence) {
        final ratio =
            _effectiveRatio(testCase.scene.pageSize, testCase.fit * zoom);
        for (final path in samples.keys) {
          final prepared =
              (await tester.runAsync(() => _prepare(testCase, ratio, path)))!;
          final presented = await _present(tester, prepared.image);
          if (pass > 0) samples[path]!.add(prepared, presented);
          await tester.pumpWidget(const SizedBox.shrink());
          prepared.image.dispose();
        }
      }
    }

    // ignore: avoid_print
    print('\nstrip first-present latency: ${testCase.label} '
        '(mean ms, $passes passes x ${_zoomSequence.length} steps; '
        'no pixel readback; initial command decode '
        '${testCase.commandDecodeMs.toStringAsFixed(1)} ms)');
    // ignore: avoid_print
    print('${'path'.padRight(10)} ${'binWait'.padLeft(8)} '
        '${'build'.padLeft(8)} ${'toImage'.padLeft(8)} '
        '${'present'.padLeft(8)} ${'first'.padLeft(8)} '
        '${'frmBuild'.padLeft(8)} ${'frmRast'.padLeft(8)} '
        '${'frmTotal'.padLeft(8)}');
    for (final entry in samples.entries) {
      final sample = entry.value;
      String value(double v) => sample.mean(v).toStringAsFixed(1).padLeft(8);
      // ignore: avoid_print
      print('${entry.key.padRight(10)} ${value(sample.planWaitMs)} '
          '${value(sample.buildMs)} ${value(sample.toImageMs)} '
          '${value(sample.presentWallMs)} '
          '${sample.firstPresentMs.toStringAsFixed(1).padLeft(8)} '
          '${value(sample.frameBuildMs)} ${value(sample.frameRasterMs)} '
          '${value(sample.frameTotalMs)}');
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}
