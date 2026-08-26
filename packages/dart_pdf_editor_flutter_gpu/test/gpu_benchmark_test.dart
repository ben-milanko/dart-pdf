import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor_flutter_gpu/dart_pdf_editor_flutter_gpu.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart' show PdfRect;
import 'package:pdf_graphics/pdf_graphics.dart';
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

Future<int> _timeSettledImage(Future<ui.Image> Function() render) async {
  final clock = Stopwatch()..start();
  final image = await render();
  await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  clock.stop();
  image.dispose();
  return clock.elapsedMicroseconds;
}

Future<(int, Uint8List)> _timePixels(Future<ui.Image> Function() render) async {
  final clock = Stopwatch()..start();
  final image = await render();
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  clock.stop();
  image.dispose();
  if (data == null) throw StateError('tile readback failed');
  return (clock.elapsedMicroseconds, Uint8List.sublistView(data));
}

PdfPath _rect(double left, double bottom, double right, double top) => PdfPath([
      PdfMoveTo(left, bottom),
      PdfLineTo(right, bottom),
      PdfLineTo(right, top),
      PdfLineTo(left, top),
      const PdfClosePath(),
    ]);

void main() {
  testWidgets('reports cold compile and warm tile replay separately',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }

      final backend = FlutterGpuTileRasterBackend();
      final scene = await PdfRetainedScene.record(
        PdfDocument.open(buildEmbeddedFontImagePdf()).page(0),
        retainDecodedPixelsForCommands:
            backend.shouldRetainLocallyDecodedImagePixels,
      );
      addTearDown(scene.dispose);
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

  testWidgets('reports dense analytic text submission cost', (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }

      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final face = FlutterGpuTrueTypeFontFace(buildTestTrueTypeFont());
      final outliner = FlutterGpuTrueTypeTextOutliner((_) => face);
      final commands = <PdfRenderCommand>[];
      for (var row = 0; row < 16; row++) {
        for (var column = 0; column < 16; column++) {
          final run = PdfTextRun(
            text: 'AB',
            transform: PdfMatrix(
              12,
              0,
              0,
              12,
              18 + column * 34,
              760 - row * 44,
            ),
            color: PdfColor(
              0.1 + (column % 4) * 0.15,
              0.2 + (row % 4) * 0.12,
              0.55,
            ),
            width: 1.2,
            fontName: 'Helvetica',
            fontSize: 12,
            charOffsets: const [0, 0.6, 1.2],
          );
          commands.add(PdfDrawTextCommand(outliner.outline(run)!));
        }
      }
      final scene = await PdfRetainedScene.fromCommands(page, commands);
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);

      final region = Offset.zero & scene.pageSize;
      final warm = await session.rasterizeRegion(region, pixelRatio: 0.5);
      await warm.toByteData(format: ui.ImageByteFormat.rawRgba);
      warm.dispose();
      expect(backend.stats.analyticTextRuns, commands.length);

      backend.stats.reset();
      final settled = <int>[];
      for (var index = 0; index < 15; index++) {
        settled.add(await _timeSettledImage(
          () => session.rasterizeRegion(region, pixelRatio: 0.5),
        ));
      }
      // ignore: avoid_print
      print('flutter_gpu analytic text benchmark: runs=${commands.length} '
          'settledMedian=${_median(settled).toStringAsFixed(0)}us '
          'issueMean=${(backend.stats.issueMicros / settled.length).toStringAsFixed(0)}us '
          '${backend.stats}');
    });
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('reports dense texture submission cost', (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }

      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final stream = CosStream(
        CosDictionary({
          'Width': const CosInteger(2),
          'Height': const CosInteger(2),
        }),
        Uint8List(0),
      );
      final pixels = PdfDecodedPixels(
        Uint8List.fromList([
          235,
          55,
          45,
          255,
          45,
          120,
          235,
          255,
          55,
          205,
          95,
          255,
          240,
          190,
          40,
          255,
        ]),
        2,
        2,
      );
      final commands = <PdfRenderCommand>[
        for (var row = 0; row < 16; row++)
          for (var column = 0; column < 16; column++)
            PdfDrawImageCommand(PdfImageRequest(
              stream: stream,
              transform: PdfMatrix(
                28,
                0,
                0,
                28,
                18 + column * 34,
                748 - row * 44,
              ),
              decoded: pixels,
            )),
      ];
      final scene = await PdfRetainedScene.fromCommands(page, commands);
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);

      final region = Offset.zero & scene.pageSize;
      final warm = await session.rasterizeRegion(region, pixelRatio: 0.5);
      await warm.toByteData(format: ui.ImageByteFormat.rawRgba);
      warm.dispose();
      expect(backend.stats.texturesUploaded, 1);
      final compileMicros = backend.stats.compileMicros;
      final compileCacheHits = backend.stats.textureCacheHits;
      final compileLeases = backend.stats.activeTextureLeases;
      final compileStandaloneUniformBuffers =
          backend.stats.standaloneUniformBuffers;
      expect(compileStandaloneUniformBuffers, 0,
          reason: 'immutable image metadata belongs in the retained arena');
      expect(backend.stats.geometryBuffers, 1,
          reason: 'all image vertices and aligned uniforms fit one arena');

      backend.stats.reset();
      final settled = <int>[];
      for (var index = 0; index < 15; index++) {
        settled.add(await _timeSettledImage(
          () => session.rasterizeRegion(region, pixelRatio: 0.5),
        ));
      }
      // ignore: avoid_print
      print('flutter_gpu texture benchmark: draws=${commands.length} '
          'compile=${compileMicros}us compileCacheHits=$compileCacheHits '
          'compileLeases=$compileLeases '
          'compileStandaloneUniformBuffers=$compileStandaloneUniformBuffers '
          'settledMedian=${_median(settled).toStringAsFixed(0)}us '
          'issueMean=${(backend.stats.issueMicros / settled.length).toStringAsFixed(0)}us '
          '${backend.stats}');
    });
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('reports content-free interior tile settle', (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }

      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final scene = await PdfRetainedScene.fromCommands(
        page,
        const [],
        plan: const PdfPageRenderPlan(
          pageColor: Color(0x8066AA22),
          rotation: 90,
        ),
      );
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      await backend.warmUp();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      final liveSession = session!;
      addTearDown(liveSession.dispose);
      if (liveSession is PdfTileRasterWarmUp) {
        await (liveSession as PdfTileRasterWarmUp).warmUp();
      }

      const region = Rect.fromLTWH(50, 50, 512, 512);
      final firstGpu = await _timePixels(
        () => liveSession.rasterizeRegion(region, pixelRatio: 1),
      );
      final firstCanvas = await _timePixels(
        () => scene.rasterizeRegion(region, pixelRatio: 1),
      );
      expect(firstGpu.$2, firstCanvas.$2);

      final warmGpu = <int>[], warmCanvas = <int>[];
      for (var index = 0; index < 7; index++) {
        late (int, Uint8List) gpuResult, canvasResult;
        if (index.isEven) {
          gpuResult = await _timePixels(
            () => liveSession.rasterizeRegion(region, pixelRatio: 1),
          );
          canvasResult = await _timePixels(
            () => scene.rasterizeRegion(region, pixelRatio: 1),
          );
        } else {
          canvasResult = await _timePixels(
            () => scene.rasterizeRegion(region, pixelRatio: 1),
          );
          gpuResult = await _timePixels(
            () => liveSession.rasterizeRegion(region, pixelRatio: 1),
          );
        }
        expect(gpuResult.$2, canvasResult.$2);
        warmGpu.add(gpuResult.$1);
        warmCanvas.add(canvasResult.$1);
      }

      // ignore: avoid_print
      print('flutter_gpu paper-only benchmark: first=${firstGpu.$1}us '
          'firstCanvas=${firstCanvas.$1}us '
          'warmMedian=${_median(warmGpu).toStringAsFixed(0)}us '
          'canvasMedian=${_median(warmCanvas).toStringAsFixed(0)}us '
          '${backend.stats}');
    });
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('reports isolated group settle against Canvas', (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }

      final commands = <PdfRenderCommand>[
        PdfFillPathCommand(
          _rect(0, 0, 612, 792),
          const PdfColor(0.32, 0.4, 0.52),
          PdfFillRule.nonzero,
          1,
        ),
        const PdfBeginGroupCommand(
          0.72,
          isolated: true,
          bounds: PdfRect(40, 80, 572, 730),
        ),
      ];
      for (var index = 0; index < 32; index++) {
        final offset = index * 11.0;
        commands.add(PdfFillPathCommand(
          _rect(
            45 + offset % 170,
            90 + offset % 230,
            355 + offset % 170,
            430 + offset % 230,
          ),
          PdfColor(
            0.2 + (index % 5) * 0.14,
            0.18 + (index % 7) * 0.1,
            0.25 + (index % 4) * 0.16,
          ),
          PdfFillRule.nonzero,
          0.6,
        ));
      }
      commands.add(const PdfEndGroupCommand());
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final scene = await PdfRetainedScene.fromCommands(page, commands);
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);

      const region = Rect.fromLTWH(50, 120, 512, 512);
      final coldGpu = await _timeSettledImage(
        () => session.rasterizeRegion(region, pixelRatio: 1),
      );
      final issueGpu = <int>[];
      for (var index = 0; index < 7; index++) {
        issueGpu.add(await _timeImage(
          () => session.rasterizeRegion(region, pixelRatio: 1),
        ));
      }
      // Wait for the issue-only samples before measuring visual settle.
      await _timeSettledImage(
        () => session.rasterizeRegion(region, pixelRatio: 1),
      );

      final settledGpu = <int>[];
      final warmCanvas = <int>[];
      for (var index = 0; index < 7; index++) {
        if (index.isEven) {
          settledGpu.add(await _timeSettledImage(
            () => session.rasterizeRegion(region, pixelRatio: 1),
          ));
          warmCanvas.add(await _timeSettledImage(
            () => scene.rasterizeRegion(region, pixelRatio: 1),
          ));
        } else {
          warmCanvas.add(await _timeSettledImage(
            () => scene.rasterizeRegion(region, pixelRatio: 1),
          ));
          settledGpu.add(await _timeSettledImage(
            () => session.rasterizeRegion(region, pixelRatio: 1),
          ));
        }
      }

      final issueMedian = _median(issueGpu);
      final settleMedian = _median(settledGpu);
      final canvasMedian = _median(warmCanvas);
      expect(backend.stats.offscreenGroupPasses, 16);
      expect(backend.stats.offscreenGroupAllocatedBytes, greaterThan(0));
      // ignore: avoid_print
      print('flutter_gpu isolated group benchmark: cold=${coldGpu}us '
          'issueMedian=${issueMedian.toStringAsFixed(0)}us '
          'settleMedian=${settleMedian.toStringAsFixed(0)}us '
          'canvasMedian=${canvasMedian.toStringAsFixed(0)}us '
          'issueVsCanvas=${(issueMedian / canvasMedian).toStringAsFixed(2)}x '
          'settleVsCanvas=${(settleMedian / canvasMedian).toStringAsFixed(2)}x '
          '${backend.stats}');
    });
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('reports mixed offscreen group and advanced-blend settle',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }

      final commands = <PdfRenderCommand>[
        PdfFillPathCommand(
          _rect(0, 0, 612, 792),
          const PdfColor(0.24, 0.58, 0.72),
          PdfFillRule.nonzero,
          1,
        ),
        const PdfSetBlendModeCommand(PdfBlendMode.overlay),
        const PdfBeginGroupCommand(
          0.72,
          isolated: true,
          bounds: PdfRect(40, 80, 572, 730),
        ),
        const PdfSetBlendModeCommand(PdfBlendMode.normal),
      ];
      for (var index = 0; index < 24; index++) {
        final offset = index * 13.0;
        commands.add(PdfFillPathCommand(
          _rect(
            45 + offset % 190,
            90 + offset % 250,
            355 + offset % 190,
            430 + offset % 250,
          ),
          PdfColor(
            0.18 + (index % 5) * 0.15,
            0.2 + (index % 7) * 0.1,
            0.24 + (index % 4) * 0.17,
          ),
          PdfFillRule.nonzero,
          1,
        ));
      }
      commands
        ..add(const PdfEndGroupCommand())
        ..add(const PdfSetBlendModeCommand(PdfBlendMode.darken));
      for (var index = 0; index < 12; index++) {
        commands.add(PdfStrokePathCommand(
          PdfPath([
            PdfMoveTo(55, 105 + index * 9),
            PdfLineTo(557, 465 + index * 9),
          ]),
          PdfColor(0.12 + index * 0.035, 0.24, 0.72),
          const PdfStroke(width: 2.5),
          1,
        ));
      }
      commands.add(const PdfSetBlendModeCommand(PdfBlendMode.normal));

      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final scene = await PdfRetainedScene.fromCommands(page, commands);
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);

      const region = Rect.fromLTWH(50, 120, 512, 512);
      final coldGpu = await _timeSettledImage(
        () => session.rasterizeRegion(region, pixelRatio: 1),
      );
      final issueGpu = <int>[];
      for (var index = 0; index < 7; index++) {
        issueGpu.add(await _timeImage(
          () => session.rasterizeRegion(region, pixelRatio: 1),
        ));
      }
      // Drain the issue-only samples before measuring visual settle.
      await _timeSettledImage(
        () => session.rasterizeRegion(region, pixelRatio: 1),
      );
      final settledGpu = <int>[];
      final warmCanvas = <int>[];
      for (var index = 0; index < 7; index++) {
        if (index.isEven) {
          settledGpu.add(await _timeSettledImage(
            () => session.rasterizeRegion(region, pixelRatio: 1),
          ));
          warmCanvas.add(await _timeSettledImage(
            () => scene.rasterizeRegion(region, pixelRatio: 1),
          ));
        } else {
          warmCanvas.add(await _timeSettledImage(
            () => scene.rasterizeRegion(region, pixelRatio: 1),
          ));
          settledGpu.add(await _timeSettledImage(
            () => session.rasterizeRegion(region, pixelRatio: 1),
          ));
        }
      }

      final issueMedian = _median(issueGpu);
      final settleMedian = _median(settledGpu);
      final canvasMedian = _median(warmCanvas);
      expect(backend.stats.offscreenGroupPasses, 16);
      expect(backend.stats.advancedBlendPasses, 32);
      expect(backend.stats.advancedBlendBlits, 32);
      // ignore: avoid_print
      print('flutter_gpu mixed group+blend benchmark: cold=${coldGpu}us '
          'issueMedian=${issueMedian.toStringAsFixed(0)}us '
          'settleMedian=${settleMedian.toStringAsFixed(0)}us '
          'canvasMedian=${canvasMedian.toStringAsFixed(0)}us '
          'issueVsCanvas=${(issueMedian / canvasMedian).toStringAsFixed(2)}x '
          'settleVsCanvas=${(settleMedian / canvasMedian).toStringAsFixed(2)}x '
          '${backend.stats}');
    });
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('reports advanced blends inside an offscreen group',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }

      final commands = <PdfRenderCommand>[
        PdfFillPathCommand(
          _rect(0, 0, 612, 792),
          const PdfColor(0.88, 0.91, 0.94),
          PdfFillRule.nonzero,
          1,
        ),
        const PdfBeginGroupCommand(
          0.82,
          isolated: true,
          bounds: PdfRect(40, 80, 572, 730),
        ),
        const PdfSetBlendModeCommand(PdfBlendMode.normal),
        PdfFillPathCommand(
          _rect(55, 95, 520, 555),
          const PdfColor(0.12, 0.55, 0.78),
          PdfFillRule.nonzero,
          1,
        ),
        const PdfSetBlendModeCommand(PdfBlendMode.overlay),
        PdfFillPathCommand(
          _rect(110, 140, 560, 610),
          const PdfColor(0.92, 0.35, 0.18),
          PdfFillRule.nonzero,
          0.86,
        ),
        const PdfSetBlendModeCommand(PdfBlendMode.multiply),
        PdfFillPathCommand(
          _rect(70, 250, 475, 690),
          const PdfColor(0.28, 0.77, 0.32),
          PdfFillRule.nonzero,
          0.74,
        ),
        const PdfEndGroupCommand(),
        const PdfSetBlendModeCommand(PdfBlendMode.normal),
      ];

      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final scene = await PdfRetainedScene.fromCommands(page, commands);
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);

      const region = Rect.fromLTWH(50, 120, 512, 512);
      final coldGpu = await _timeSettledImage(
        () => session.rasterizeRegion(region, pixelRatio: 1),
      );
      final issueGpu = <int>[];
      for (var index = 0; index < 7; index++) {
        issueGpu.add(await _timeImage(
          () => session.rasterizeRegion(region, pixelRatio: 1),
        ));
      }
      await _timeSettledImage(
        () => session.rasterizeRegion(region, pixelRatio: 1),
      );
      final settledGpu = <int>[];
      final warmCanvas = <int>[];
      for (var index = 0; index < 7; index++) {
        if (index.isEven) {
          settledGpu.add(await _timeSettledImage(
            () => session.rasterizeRegion(region, pixelRatio: 1),
          ));
          warmCanvas.add(await _timeSettledImage(
            () => scene.rasterizeRegion(region, pixelRatio: 1),
          ));
        } else {
          warmCanvas.add(await _timeSettledImage(
            () => scene.rasterizeRegion(region, pixelRatio: 1),
          ));
          settledGpu.add(await _timeSettledImage(
            () => session.rasterizeRegion(region, pixelRatio: 1),
          ));
        }
      }

      final issueMedian = _median(issueGpu);
      final settleMedian = _median(settledGpu);
      final canvasMedian = _median(warmCanvas);
      expect(backend.stats.offscreenGroupPasses, 16);
      expect(backend.stats.advancedBlendPasses, 32);
      expect(backend.stats.advancedBlendBlits, 32);
      // ignore: avoid_print
      print('flutter_gpu internal group blend benchmark: '
          'cold=${coldGpu}us '
          'issueMedian=${issueMedian.toStringAsFixed(0)}us '
          'settleMedian=${settleMedian.toStringAsFixed(0)}us '
          'canvasMedian=${canvasMedian.toStringAsFixed(0)}us '
          'issueVsCanvas=${(issueMedian / canvasMedian).toStringAsFixed(2)}x '
          'settleVsCanvas=${(settleMedian / canvasMedian).toStringAsFixed(2)}x '
          '${backend.stats}');
    });
  }, timeout: const Timeout(Duration(minutes: 2)));
}
