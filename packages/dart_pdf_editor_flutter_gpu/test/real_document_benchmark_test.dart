import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor_flutter_gpu/dart_pdf_editor_flutter_gpu.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

import '../tool/advanced_blend_stress_fixture.dart';

const _defaultPages = [27, 30, 29, 32, 31, 34, 37, 39, 28];
const _buildCommit = String.fromEnvironment('PDF_BUILD_COMMIT');
const _advancedBlendStressScenario = 'advanced-blend-stress';
const _deferredMaskFixture = 'deferred-mask';

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

String? _scenarioName(String? label, String stage, {int? page}) {
  if (label == null || label.isEmpty) return null;
  return 'gpu-$label${page == null ? '' : '-page-$page'}-$stage';
}

void _startScenario(String? name) {
  if (name != null) PdfPerfLog.log('scenario name=$name phase=start');
}

void _finishScenario(String? name, int elapsedUs, {int? page}) {
  if (name == null) return;
  PdfPerfLog.log(
    'raster page=${page ?? '-'} kind=$name '
    'ms=${(elapsedUs / 1000).toStringAsFixed(3)}',
  );
  PdfPerfLog.log('scenario name=$name phase=validated');
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

Uint8List _deferredMaskDocument() {
  const width = 1024, height = 768;
  final source = img.Image(width: width, height: height, numChannels: 3);
  img.fill(source, color: img.ColorRgb8(38, 112, 168));
  final jpeg = Uint8List.fromList(img.encodeJpg(source, quality: 82));
  return buildSyntheticRasterUnderlaySheet(
    underlays: [
      PdfUnderlaySpec(width: width, height: height, payload: jpeg),
    ],
    layers: 4,
    ops: 200,
    pageW: 612,
    pageH: 792,
  );
}

Uint8List _benchmarkDocumentBytes(String? path, String? fixture) {
  if (path != null && fixture != null) {
    throw ArgumentError(
      'Set either PDF_GPU_BENCHMARK_PDF or PDF_GPU_BENCHMARK_FIXTURE, not both',
    );
  }
  if (path != null) return File(path).readAsBytesSync();
  return switch (fixture) {
    _deferredMaskFixture => _deferredMaskDocument(),
    null => throw ArgumentError(
        'Set PDF_GPU_BENCHMARK_PDF or PDF_GPU_BENCHMARK_FIXTURE',
      ),
    _ => throw ArgumentError('Unknown PDF_GPU_BENCHMARK_FIXTURE: $fixture'),
  };
}

Future<void> _registerMacSystemFonts() async {
  Future<void> load(String family, String path) async {
    final bytes = File(path).readAsBytesSync();
    await (FontLoader(family)
          ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes))))
        .load();
  }

  await load('Helvetica', '/System/Library/Fonts/Helvetica.ttc');
  await load('Symbol', '/System/Library/Fonts/Symbol.ttf');
  await load(
    'STSong',
    '/System/Library/Fonts/Supplemental/Songti.ttc',
  );
  await load('Heiti SC', '/System/Library/Fonts/STHeiti Medium.ttc');
  await load(
    'Hiragino Sans',
    '/System/Library/Fonts/ヒラギノ角ゴシック W4.ttc',
  );
  await load(
    'Hiragino Mincho ProN',
    '/System/Library/Fonts/ヒラギノ明朝 ProN.ttc',
  );
}

void main() {
  if (_buildCommit.isNotEmpty) PdfPerfLog.buildTag = 'commit=$_buildCommit';

  testWidgets('advanced-blend stress fixture records twelve ordered strokes',
      (tester) async {
    await tester.runAsync(() async {
      final document = PdfDocument.open(buildAdvancedBlendStressPdf());
      final scene = await PdfRetainedScene.record(document.page(0));
      try {
        expect(
          scene.commands.whereType<PdfStrokePathCommand>(),
          hasLength(12),
        );
        expect(
          scene.commands.whereType<PdfSetBlendModeCommand>().map((c) => c.mode),
          contains(PdfBlendMode.darken),
        );
      } finally {
        scene.dispose();
      }
    });
  });

  testWidgets('deferred-mask fixture keeps its companion image surface',
      (tester) async {
    await tester.runAsync(() async {
      final document = PdfDocument.open(_deferredMaskDocument());
      final scene = await PdfRetainedScene.record(document.page(0));
      try {
        final request = scene.commands
            .whereType<PdfDrawImageCommand>()
            .map((command) => command.request)
            .single;
        final image = scene.imageFor(request);
        expect(image, isNotNull);
        expect(pdfGpuSoftMaskOf(image!), isNotNull);
      } finally {
        scene.dispose();
      }
    });
  });

  testWidgets('real document: cold scene plus two 512px LoDs', (tester) async {
    final path = Platform.environment['PDF_GPU_BENCHMARK_PDF'];
    final fixture = Platform.environment['PDF_GPU_BENCHMARK_FIXTURE']?.trim();
    if (path == null && (fixture == null || fixture.isEmpty)) {
      markTestSkipped(
        'set PDF_GPU_BENCHMARK_PDF or PDF_GPU_BENCHMARK_FIXTURE',
      );
      return;
    }
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      if (Platform.isMacOS &&
          Platform.environment['PDF_GPU_BENCHMARK_REGISTER_SYSTEM_FONTS'] ==
              '1') {
        await _registerMacSystemFonts();
      }
      final fixtureName = fixture == null || fixture.isEmpty ? null : fixture;
      final document = PdfDocument.open(
        _benchmarkDocumentBytes(path, fixtureName),
      );
      final productionRoute = fixtureName == _deferredMaskFixture ||
          Platform.environment['PDF_GPU_BENCHMARK_ROUTE_CHANGE'] == '1';
      final configuredPages =
          Platform.environment['PDF_GPU_BENCHMARK_PAGES']?.trim();
      final scenarioLabel =
          Platform.environment['PDF_GPU_BENCHMARK_SCENARIO']?.trim();
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
      final gpuBackend = FlutterGpuTileRasterBackend(
        msaa: msaa,
        allowOverprintApproximation: approximateOverprint,
        analyticText:
            Platform.environment['PDF_GPU_BENCHMARK_ANALYTIC_TEXT'] != '0',
        systemTextOutlines:
            Platform.environment['PDF_GPU_BENCHMARK_SYSTEM_TEXT'] == '1',
      );
      if (Platform.environment['PDF_GPU_BENCHMARK_WARMUP'] == '1') {
        final scenario = productionRoute
            ? null
            : _scenarioName(scenarioLabel, 'pipeline-warm');
        _startScenario(scenario);
        final warmUp = Stopwatch()..start();
        await gpuBackend.warmUp();
        final elapsedUs = warmUp.elapsedMicroseconds;
        // ignore: avoid_print
        print('REAL_GPU_BENCHMARK warmUpUs=$elapsedUs');
        _finishScenario(scenario, elapsedUs);
      }
      final output = Platform.environment['PDF_GPU_BENCHMARK_OUT'];
      if (output != null) Directory(output).createSync(recursive: true);
      final PdfTileRasterBackend backend = gpuBackend;
      final rssStart = ProcessInfo.currentRss;
      var peakRss = rssStart;
      final rows = <String>[];

      for (final pageIndex in pages) {
        PdfImageCache.instance.clear();
        final timing = PdfSceneBuildTiming();
        final record = Stopwatch()..start();
        final scene = await PdfRetainedScene.record(
          document.page(pageIndex),
          retainDecodedPixelsForCommands:
              gpuBackend.shouldRetainLocallyDecodedImagePixels,
          timing: timing,
        );
        record.stop();
        try {
          final size = scene.pageSize;
          final center = Offset(size.width / 2, size.height / 2);
          const lod1 = 1.0;
          final region1 = Rect.fromCenter(
            center: center,
            width: math.min(size.width, 512 / lod1),
            height: math.min(size.height, 512 / lod1),
          );
          final sessionClock = Stopwatch()..start();
          var session = backend.createSession(scene);
          if (session == null && backend is PdfTileRasterRetryBackend) {
            final retry =
                (backend as PdfTileRasterRetryBackend).retrySession(scene);
            if (retry != null) session = await retry;
          }
          sessionClock.stop();
          final accelerated = session;
          if (accelerated == null) {
            final firstScenario = _scenarioName(
              scenarioLabel,
              'first-tile',
              page: pageIndex,
            );
            _startScenario(firstScenario);
            final fallback = await _render(
              () => scene.rasterizeRegion(region1, pixelRatio: lod1),
              pngPath: output == null
                  ? null
                  : '$output/page-$pageIndex-fallback.png',
            );
            _finishScenario(firstScenario, fallback.$1, page: pageIndex);
            if (productionRoute) {
              // The fallback itself warmed Canvas. Repeat the unmeasured pass
              // so both routes take one explicit warm-up immediately before
              // the measured Canvas control below.
              await _render(
                () => scene.rasterizeRegion(region1, pixelRatio: lod1),
              );
            }
            final canvasScenario = _scenarioName(
              scenarioLabel,
              'canvas-tile',
              page: pageIndex,
            );
            _startScenario(canvasScenario);
            final canvas = await _render(
              () => scene.rasterizeRegion(region1, pixelRatio: lod1),
              pngPath:
                  output == null ? null : '$output/page-$pageIndex-canvas.png',
            );
            _finishScenario(canvasScenario, canvas.$1, page: pageIndex);
            peakRss = math.max(peakRss, ProcessInfo.currentRss);
            rows.add('page=$pageIndex recordUs=${record.elapsedMicroseconds} '
                'decodeUs=${(timing.decodeMs * 1000).round()} '
                'sessionUs=${sessionClock.elapsedMicroseconds} '
                'gpu=rejected reason=${gpuBackend.stats.lastRejection} '
                'firstRoute=canvas-fallback firstUs=${fallback.$1} '
                'canvasUs=${canvas.$1} '
                'meanDiff=${_meanDiff(fallback.$2, canvas.$2).toStringAsFixed(3)} '
                'commands=${scene.commands.length}');
            continue;
          }
          try {
            final warmable = accelerated is PdfTileRasterWarmUp
                ? accelerated as PdfTileRasterWarmUp
                : null;
            if (Platform.environment['PDF_GPU_BENCHMARK_SCENE_WARMUP'] == '1' &&
                warmable != null) {
              // Route-change cohorts compare a Canvas base with a GPU
              // candidate, so only one side can produce a scene-warm timing.
              // Still perform the warm-up—the viewer does—while suppressing
              // the unmatched marker from the comparison report.
              final scenario = productionRoute
                  ? null
                  : _scenarioName(
                      scenarioLabel,
                      'scene-warm',
                      page: pageIndex,
                    );
              _startScenario(scenario);
              final warmUp = Stopwatch()..start();
              await warmable.warmUp();
              final elapsedUs = warmUp.elapsedMicroseconds;
              // ignore: avoid_print
              print('REAL_GPU_BENCHMARK sceneWarmUpUs=$elapsedUs');
              _finishScenario(scenario, elapsedUs, page: pageIndex);
            }
            try {
              final coldScenario = _scenarioName(
                scenarioLabel,
                'first-tile',
                page: pageIndex,
              );
              _startScenario(coldScenario);
              final coldGpu = await _render(
                () => accelerated.rasterizeRegion(region1, pixelRatio: lod1),
                pngPath:
                    output == null ? null : '$output/page-$pageIndex-gpu.png',
              );
              _finishScenario(coldScenario, coldGpu.$1, page: pageIndex);
              if (productionRoute) {
                // A GPU first tile does not warm Canvas. Keep the reference
                // control comparable with the fallback route without moving
                // this work into the cold production-settle scenario.
                await _render(
                  () => scene.rasterizeRegion(region1, pixelRatio: lod1),
                );
              }
              final canvasScenario = _scenarioName(
                scenarioLabel,
                'canvas-tile',
                page: pageIndex,
              );
              _startScenario(canvasScenario);
              final warmCanvas = await _render(
                () => scene.rasterizeRegion(region1, pixelRatio: lod1),
                pngPath: output == null
                    ? null
                    : '$output/page-$pageIndex-canvas.png',
              );
              _finishScenario(
                canvasScenario,
                warmCanvas.$1,
                page: pageIndex,
              );

              final lod2 = 2.0;
              final region2 = Rect.fromCenter(
                center: center,
                width: math.min(size.width, 512 / lod2),
                height: math.min(size.height, 512 / lod2),
              );
              final warmGpu = await _render(
                  () => accelerated.rasterizeRegion(region2, pixelRatio: lod2));
              peakRss = math.max(peakRss, ProcessInfo.currentRss);
              rows.add('page=$pageIndex recordUs=${record.elapsedMicroseconds} '
                  'decodeUs=${(timing.decodeMs * 1000).round()} '
                  'sessionUs=${sessionClock.elapsedMicroseconds} '
                  'firstRoute=flutter_gpu '
                  'gpuColdUs=${coldGpu.$1} gpuWarmUs=${warmGpu.$1} '
                  'canvasUs=${warmCanvas.$1} '
                  'meanDiff=${_meanDiff(coldGpu.$2, warmCanvas.$2).toStringAsFixed(3)}');
            } catch (error) {
              final canvas = await _render(
                  () => scene.rasterizeRegion(region1, pixelRatio: lod1));
              peakRss = math.max(peakRss, ProcessInfo.currentRss);
              rows.add('page=$pageIndex recordUs=${record.elapsedMicroseconds} '
                  'decodeUs=${(timing.decodeMs * 1000).round()} '
                  'sessionUs=${sessionClock.elapsedMicroseconds} '
                  'gpu=fallback canvasUs=${canvas.$1} '
                  'error=${error.toString().replaceAll('\n', ' ')}');
            }
          } finally {
            accelerated.dispose();
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
          'delta=${peakRss - rssStart} stats=${gpuBackend.stats}');
      expect(rows, isNotEmpty);
      if (scenarioLabel == _advancedBlendStressScenario) {
        final sceneWarmUp =
            Platform.environment['PDF_GPU_BENCHMARK_SCENE_WARMUP'] == '1';
        // The two measured LoDs each coalesce the twelve disjoint strokes
        // into one blend. A one-pixel scene warm-up deliberately stays
        // conservative because all strokes resolve into the same pixel.
        expect(gpuBackend.stats.advancedBlendPasses, sceneWarmUp ? 14 : 2);
        expect(
          gpuBackend.stats.advancedBlendBlits,
          gpuBackend.stats.advancedBlendPasses,
        );
      }
    });
  }, timeout: const Timeout(Duration(minutes: 20)));
}
