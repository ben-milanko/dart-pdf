import 'dart:async';
import 'dart:io' show ZLibCodec;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor_flutter_gpu/dart_pdf_editor_flutter_gpu.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:vector_math/vector_math.dart' as vm;

bool _gpuAvailable() {
  try {
    gpu.gpuContext.defaultColorFormat;
    return true;
  } catch (_) {
    return false;
  }
}

Future<Uint8List> _pixels(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

PdfPath _rect(double left, double bottom, double right, double top) => PdfPath([
      PdfMoveTo(left, bottom),
      PdfLineTo(right, bottom),
      PdfLineTo(right, top),
      PdfLineTo(left, top),
      const PdfClosePath(),
    ]);

PdfDrawImageCommand _decodedImage(
    Uint8List rgba, PdfMatrix transform, Object identity,
    {bool workerReconstructed = false}) {
  final stream = CosStream(
    CosDictionary({
      'Identity': CosString.fromText(identity.toString()),
      'Width': const CosInteger(2),
      'Height': const CosInteger(2),
    }),
    Uint8List(0),
  );
  return PdfDrawImageCommand(PdfImageRequest(
    stream: stream,
    transform: transform,
    isInline: workerReconstructed,
    decoded: PdfDecodedPixels(rgba, 2, 2),
  ));
}

Future<ui.Image> _renderDestinationBlendProbe({
  required List<double> destination,
  required List<double> source,
  required bool hardLight,
}) async {
  final context = gpu.gpuContext;
  final library = await Future<gpu.ShaderLibrary?>.value(
    gpu.ShaderLibrary.fromAsset(
      'assets/shaders/pdf_tile_gpu.shaderbundle',
    ),
  );
  if (library == null) {
    throw StateError('destination blend shader bundle failed to load');
  }
  final vertex = library['PdfTileDestinationBlendVertex']!;
  final fragment = library['PdfTileDestinationBlendFragment']!;
  final pipeline = context.createRenderPipeline(vertex, fragment);
  final destinationTexture = context.createTexture(
    gpu.StorageMode.devicePrivate,
    8,
    8,
    format: context.defaultColorFormat,
    enableRenderTargetUsage: true,
    enableShaderReadUsage: true,
  );
  final sourceTexture = context.createTexture(
    gpu.StorageMode.devicePrivate,
    8,
    8,
    format: context.defaultColorFormat,
    enableRenderTargetUsage: true,
    enableShaderReadUsage: true,
  );
  final outputTexture = context.createTexture(
    gpu.StorageMode.devicePrivate,
    8,
    8,
    format: context.defaultColorFormat,
    enableRenderTargetUsage: true,
    enableShaderReadUsage: true,
  );
  final transient = context.createHostBuffer();
  final vertices = transient.emplace(ByteData.sublistView(
    Float32List.fromList(const [
      -1,
      -1,
      0,
      1,
      1,
      -1,
      1,
      1,
      1,
      1,
      1,
      0,
      -1,
      -1,
      0,
      1,
      1,
      1,
      1,
      0,
      -1,
      1,
      0,
      0,
    ]),
  ));
  final blendInfo = transient.emplace(ByteData.sublistView(
    Float32List.fromList([
      (hardLight ? PdfBlendMode.hardLight.index : PdfBlendMode.colorBurn.index)
          .toDouble(),
      0,
      0,
      0,
    ]),
  ));

  final destinationCommandBuffer = context.createCommandBuffer();
  final destinationPass =
      destinationCommandBuffer.createRenderPass(gpu.RenderTarget.singleColor(
    gpu.ColorAttachment(
      texture: destinationTexture,
      clearValue: vm.Vector4(
        destination[0],
        destination[1],
        destination[2],
        destination[3],
      ),
      storeAction: gpu.StoreAction.store,
    ),
  ));
  final destinationCompleter = Completer<void>();
  final destinationResources = <Object>[
    destinationTexture,
    destinationCommandBuffer,
    destinationPass,
  ];
  destinationCommandBuffer.submit(completionCallback: (success) {
    if (destinationResources.isEmpty) return;
    if (success) {
      destinationCompleter.complete();
    } else {
      destinationCompleter.completeError(
        StateError('destination blend backdrop submission failed'),
      );
    }
  });

  final sourceCommandBuffer = context.createCommandBuffer();
  final sourcePass =
      sourceCommandBuffer.createRenderPass(gpu.RenderTarget.singleColor(
    gpu.ColorAttachment(
      texture: sourceTexture,
      clearValue: vm.Vector4(
        source[0] * source[3],
        source[1] * source[3],
        source[2] * source[3],
        source[3],
      ),
      storeAction: gpu.StoreAction.store,
    ),
  ));
  final sourceCompleter = Completer<void>();
  final sourceResources = <Object>[
    sourceTexture,
    sourceCommandBuffer,
    sourcePass,
  ];
  sourceCommandBuffer.submit(completionCallback: (success) {
    if (sourceResources.isEmpty) return;
    if (success) {
      sourceCompleter.complete();
    } else {
      sourceCompleter.completeError(
        StateError('destination blend source submission failed'),
      );
    }
  });
  final blendCommandBuffer = context.createCommandBuffer();
  final blendPass =
      blendCommandBuffer.createRenderPass(gpu.RenderTarget.singleColor(
    gpu.ColorAttachment(
      texture: outputTexture,
      clearValue: vm.Vector4.zero(),
      storeAction: gpu.StoreAction.store,
    ),
  ));
  blendPass
    ..setCullMode(gpu.CullMode.none)
    ..setWindingOrder(gpu.WindingOrder.counterClockwise)
    ..setPrimitiveType(gpu.PrimitiveType.triangle)
    ..setColorBlendEnable(false)
    ..bindPipeline(pipeline)
    ..bindUniform(fragment.getUniformSlot('BlendInfo'), blendInfo)
    ..bindTexture(
      fragment.getUniformSlot('destination_tex'),
      destinationTexture,
      sampler: gpu.SamplerOptions(
        minFilter: gpu.MinMagFilter.nearest,
        magFilter: gpu.MinMagFilter.nearest,
      ),
    )
    ..bindTexture(
      fragment.getUniformSlot('source_tex'),
      sourceTexture,
      sampler: gpu.SamplerOptions(
        minFilter: gpu.MinMagFilter.nearest,
        magFilter: gpu.MinMagFilter.nearest,
      ),
    )
    ..bindVertexBuffer(vertices)
    ..draw(6);

  final blendCompleter = Completer<void>();
  final resources = <Object>[
    library,
    pipeline,
    destinationTexture,
    sourceTexture,
    outputTexture,
    transient,
    blendCommandBuffer,
    blendPass,
  ];
  blendCommandBuffer.submit(completionCallback: (success) {
    if (resources.isEmpty) return;
    if (success) {
      blendCompleter.complete();
    } else {
      blendCompleter.completeError(
        StateError('destination blend probe submission failed'),
      );
    }
  });
  await Future.wait([
    destinationCompleter.future,
    sourceCompleter.future,
    blendCompleter.future,
  ]);
  return outputTexture.asImage();
}

List<int> _destinationBlendExpected({
  required List<double> destination,
  required List<double> source,
  required bool hardLight,
}) {
  double blend(double backdrop, double foreground) {
    if (hardLight) {
      return foreground <= 0.5
          ? 2 * foreground * backdrop
          : 1 - 2 * (1 - foreground) * (1 - backdrop);
    }
    return foreground <= 0
        ? 0
        : 1 - (1 - backdrop) / foreground.clamp(0.0, 1.0);
  }

  final alpha = source[3].clamp(0.0, 1.0);
  return <int>[
    for (var channel = 0; channel < 3; channel++)
      ((destination[channel] * (1 - alpha) +
                  blend(destination[channel], source[channel]).clamp(0.0, 1.0) *
                      alpha) *
              255)
          .round(),
    ((alpha + destination[3] * (1 - alpha)) * 255).round(),
  ];
}

void main() {
  testWidgets('shader-readable render targets preserve destination blends',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      const destination = <double>[0.72, 0.35, 0.18, 1];
      const source = <double>[0.62, 0.78, 0.27, 0.65];
      for (final hardLight in [false, true]) {
        final image = await _renderDestinationBlendProbe(
          destination: destination,
          source: source,
          hardLight: hardLight,
        );
        addTearDown(image.dispose);
        final pixels = await _pixels(image);
        final offset = (4 * 8 + 4) * 4;
        final actual = pixels.sublist(offset, offset + 4);
        final expected = _destinationBlendExpected(
          destination: destination,
          source: source,
          hardLight: hardLight,
        );
        for (var channel = 0; channel < 4; channel++) {
          expect(
            actual[channel],
            closeTo(expected[channel], 2),
            reason: '${hardLight ? 'HardLight' : 'ColorBurn'} channel '
                '$channel sampled the first render target',
          );
        }
      }
    });
  });

  testWidgets('unavailable context declines without affecting the host',
      (tester) async {
    if (_gpuAvailable()) {
      markTestSkipped('this assertion targets a run without flutter_gpu flags');
      return;
    }
    await tester.runAsync(() async {
      final scene = await PdfRetainedScene.record(
          PdfDocument.open(buildEmbeddedFontImagePdf()).page(0));
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      expect(backend.createSession(scene), isNull);
      expect(backend.stats.sessionsRejected, 1);
    });
  });

  testWidgets('pipeline warm-up is shared by the Impeller context',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final first = FlutterGpuTileRasterBackend();
      await first.warmUp();
      expect(first.stats.warmUpRequests, 1);
      expect(first.stats.warmUpSubmissions, 1);
      expect(first.stats.warmUpCompletions, 1);
      expect(first.stats.warmUpFailures, 0);
      expect(first.stats.warmUpMicros, greaterThan(0));

      await first.warmUp();
      expect(first.stats.warmUpRequests, 2);
      expect(first.stats.warmUpSubmissions, 1,
          reason: 'the same backend reuses the completed context warm-up');

      final second = FlutterGpuTileRasterBackend();
      await second.warmUp();
      expect(second.stats.warmUpRequests, 1);
      expect(second.stats.warmUpSubmissions, 0,
          reason: 'backend instances share context-owned pipeline work');
      expect(second.stats.warmUpCompletions, 1);
    });
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('scene warm-up prepares retained resources before the first tile',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final scene = await PdfRetainedScene.record(
          PdfDocument.open(buildEmbeddedFontImagePdf()).page(0));
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isA<PdfTileRasterWarmUp>(),
          reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);

      await (session as PdfTileRasterWarmUp).warmUp();
      expect(backend.stats.sceneWarmUpRequests, 1);
      expect(backend.stats.sceneWarmUpCompletions, 1);
      expect(backend.stats.sceneWarmUpFailures, 0);
      expect(backend.stats.scenesCompiled, 1);
      expect(backend.stats.tilesRendered, 0);

      final image = await session.rasterizeRegion(
        const Rect.fromLTWH(40, 50, 330, 190),
        pixelRatio: 2,
      );
      addTearDown(image.dispose);
      expect(backend.stats.scenesCompiled, 1,
          reason: 'the first real tile reuses the prepared scene');
      expect(backend.stats.tilesRendered, 1);
    });
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('compiles once and replays retained buffers across tiles',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final scene = await PdfRetainedScene.record(
          PdfDocument.open(buildEmbeddedFontImagePdf()).page(0));
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);
      expect(session, isA<PdfTileRasterScheduling>());
      final scheduling = session as PdfTileRasterScheduling;
      expect(scheduling.batchAdjacentTiles, isFalse);
      expect(scheduling.maxNewTilesPerPaint, 1);
      expect(backend.stats.activeSessions, 1);
      expect(backend.stats.lastTileRoute, 'flutter_gpu-session');

      const firstRegion = Rect.fromLTWH(40, 50, 330, 190);
      final canvas = await scene.rasterizeRegion(firstRegion, pixelRatio: 2);
      final accelerated = await session.rasterizeRegion(
        firstRegion,
        pixelRatio: 2,
      );
      addTearDown(canvas.dispose);
      addTearDown(accelerated.dispose);
      expect(accelerated.width, canvas.width);
      expect(accelerated.height, canvas.height);

      final expected = await _pixels(canvas);
      final actual = await _pixels(accelerated);
      var difference = 0;
      for (var i = 0; i < expected.length; i++) {
        difference += (expected[i] - actual[i]).abs();
      }
      expect(difference / expected.length, lessThan(12),
          reason: 'GPU tile should agree with Canvas apart from AA edges');
      expect(backend.stats.completedSubmissions, 1);
      expect(backend.stats.maxCompletionMicros, greaterThan(0));
      expect(backend.stats.inFlightSubmissions, 0,
          reason: 'pixel readback waits for the submitted render to finish');
      expect(backend.stats.scenesCompiled, 1);
      expect(backend.stats.texturesUploaded, 1);
      final buffers = backend.stats.geometryBuffers;

      final second = await session.rasterizeRegion(
        const Rect.fromLTWH(60, 70, 180, 120),
        pixelRatio: 3,
      );
      second.dispose();
      expect(backend.stats.scenesCompiled, 1);
      expect(backend.stats.texturesUploaded, 1);
      expect(backend.stats.geometryBuffers, buffers);
      expect(backend.stats.tilesRendered, 2);
      expect(backend.stats.lastTileRoute, 'flutter_gpu');
      session.dispose();
      expect(backend.stats.activeSessions, 0);
      expect(backend.stats.sessionsDisposed, 1);
    });
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('rotation and rectangular clips match Canvas', (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final scene = await PdfRetainedScene.fromCommands(
        page,
        [
          const PdfSaveCommand(),
          PdfClipPathCommand(_rect(100, 200, 360, 620), PdfFillRule.nonzero),
          PdfFillPathCommand(
            _rect(40, 100, 500, 700),
            const PdfColor(0.1, 0.4, 0.8),
            PdfFillRule.nonzero,
            0.75,
          ),
          const PdfRestoreCommand(),
        ],
        plan: const PdfPageRenderPlan(rotation: 90),
      );
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);

      final region = Offset.zero & scene.pageSize;
      final canvas = await scene.rasterizeRegion(region, pixelRatio: 0.75);
      final accelerated =
          await session.rasterizeRegion(region, pixelRatio: 0.75);
      addTearDown(canvas.dispose);
      addTearDown(accelerated.dispose);
      final expected = await _pixels(canvas);
      final actual = await _pixels(accelerated);
      var difference = 0;
      for (var i = 0; i < expected.length; i++) {
        difference += (expected[i] - actual[i]).abs();
      }
      expect(difference / expected.length, lessThan(3));
    });
  });

  testWidgets('zero-width strokes remain one device pixel at every LoD',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      const scenePath = PdfPath([
        PdfMoveTo(70, 130),
        PdfLineTo(320, 350),
        PdfLineTo(510, 150),
      ]);
      const dashedPath = PdfPath([
        PdfMoveTo(55, 250),
        PdfLineTo(530, 250),
      ]);
      final scene = await PdfRetainedScene.fromCommands(page, const [
        PdfStrokePathCommand(
          scenePath,
          PdfColor(0.08, 0.24, 0.82),
          PdfStroke(width: 0, cap: 1, join: 1),
          0.8,
        ),
        PdfStrokePathCommand(
          dashedPath,
          PdfColor(0.82, 0.12, 0.08),
          PdfStroke(width: 0, cap: 2, dashArray: [18, 11]),
          1,
        ),
      ]);
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);

      const region = Rect.fromLTWH(40, 420, 510, 270);
      for (final ratio in [0.25, 1.0, 4.0]) {
        final expected = await scene.rasterizeRegion(region, pixelRatio: ratio);
        final actual = await session.rasterizeRegion(region, pixelRatio: ratio);
        try {
          final a = await _pixels(expected), b = await _pixels(actual);
          var difference = 0;
          var painted = 0;
          for (var i = 0; i < a.length; i += 4) {
            difference += (a[i] - b[i]).abs() +
                (a[i + 1] - b[i + 1]).abs() +
                (a[i + 2] - b[i + 2]).abs() +
                (a[i + 3] - b[i + 3]).abs();
            if (a[i] < 245 || a[i + 1] < 245 || a[i + 2] < 245) painted++;
          }
          expect(painted, greaterThan(0), reason: 'ratio=$ratio');
          expect(difference / a.length, lessThan(3),
              reason: 'ratio=$ratio hairlines must agree with Canvas');
        } finally {
          expected.dispose();
          actual.dispose();
        }
      }
      expect(backend.stats.lastTileRoute, 'flutter_gpu');
    });
  });

  testWidgets('Multiply and Screen use exact opaque-page blend equations',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      for (final mode in [PdfBlendMode.multiply, PdfBlendMode.screen]) {
        final scene = await PdfRetainedScene.fromCommands(page, [
          PdfFillPathCommand(
            _rect(50, 100, 350, 400),
            const PdfColor(0.16, 0.52, 0.82),
            PdfFillRule.nonzero,
            1,
          ),
          PdfSetBlendModeCommand(mode),
          PdfFillPathCommand(
            _rect(140, 180, 310, 350),
            const PdfColor(0.88, 0.26, 0.12),
            PdfFillRule.nonzero,
            0.63,
          ),
          const PdfSetBlendModeCommand(PdfBlendMode.normal),
        ]);
        final backend = FlutterGpuTileRasterBackend();
        final session = backend.createSession(scene);
        expect(session, isNotNull,
            reason: '${mode.name}: ${backend.stats.lastRejection}');
        const region = Rect.fromLTWH(40, 90, 320, 320);
        final expected = await scene.rasterizeRegion(region, pixelRatio: 1.5);
        final actual = await session!.rasterizeRegion(
          region,
          pixelRatio: 1.5,
        );
        try {
          final a = await _pixels(expected), b = await _pixels(actual);
          var difference = 0;
          for (var i = 0; i < a.length; i++) {
            difference += (a[i] - b[i]).abs();
          }
          expect(difference / a.length, lessThan(3),
              reason: '${mode.name} must agree with Canvas');
        } finally {
          expected.dispose();
          actual.dispose();
          session.dispose();
          scene.dispose();
        }
      }
    });
  });

  testWidgets('tiling cells expand once and preserve painter order',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final scene = await PdfRetainedScene.fromCommands(page, [
        PdfDrawTiledCellCommand(
          [
            PdfFillPathCommand(
              _rect(80, 180, 170, 300),
              const PdfColor(0.9, 0.1, 0.15),
              PdfFillRule.nonzero,
              0.55,
            ),
            PdfFillPathCommand(
              _rect(135, 225, 225, 345),
              const PdfColor(0.05, 0.25, 0.9),
              PdfFillRule.nonzero,
              0.55,
            ),
            PdfDrawTiledCellCommand(
              [
                PdfFillPathCommand(
                  _rect(112, 205, 128, 221),
                  const PdfColor(0.1, 0.75, 0.25),
                  PdfFillRule.nonzero,
                  0.8,
                ),
              ],
              Float64List.fromList([0, 24]),
              Float64List.fromList([0, 18]),
            ),
          ],
          Float64List.fromList([0, 55, 110, 165]),
          Float64List.fromList([0, 35, 70, 105]),
        ),
      ]);
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);

      const region = Rect.fromLTWH(50, 120, 430, 420);
      final canvas = await scene.rasterizeRegion(region, pixelRatio: 1.25);
      final accelerated =
          await session.rasterizeRegion(region, pixelRatio: 1.25);
      addTearDown(canvas.dispose);
      addTearDown(accelerated.dispose);
      final expected = await _pixels(canvas);
      final actual = await _pixels(accelerated);
      var difference = 0;
      for (var i = 0; i < expected.length; i++) {
        difference += (expected[i] - actual[i]).abs();
      }
      expect(difference / expected.length, lessThan(4),
          reason: 'overlapping cell repeats must retain tile-major order');
    });
  });

  testWidgets('axial gradients use exact path stencil and stop geometry',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      const path = PdfPath([
        PdfMoveTo(45, 120),
        PdfLineTo(520, 120),
        PdfLineTo(520, 510),
        PdfLineTo(45, 510),
        PdfClosePath(),
        PdfMoveTo(210, 245),
        PdfLineTo(355, 245),
        PdfLineTo(355, 390),
        PdfLineTo(210, 390),
        PdfClosePath(),
      ]);
      final scene = await PdfRetainedScene.fromCommands(page, [
        const PdfFillPathGradientCommand(
          path,
          PdfFillRule.evenOdd,
          PdfGradient(
            isRadial: false,
            coords: [0, 0, 180, 0],
            colors: [
              PdfColor(0.9, 0.05, 0.1),
              PdfColor(0.1, 0.75, 0.2),
              PdfColor(0.05, 0.2, 0.95),
            ],
            stops: [0, 0.38, 1],
            transform: PdfMatrix(2.1, 0.35, -0.2, 1.6, 90, 170),
            extendStart: false,
            extendEnd: false,
          ),
          0.72,
        ),
        const PdfDrawTextCommand(PdfTextRun(
          text: 'H',
          transform: PdfMatrix(150, 12, 8, 165, 185, 185),
          color: PdfColor.black,
          width: 1,
          fontName: 'EmbeddedGradient',
          fontSize: 1,
          fillAlpha: 0.68,
          glyphs: [
            PdfGlyphPlacement(
              offset: 0,
              outline: PdfPath([
                PdfMoveTo(0, 0),
                PdfLineTo(0.18, 0),
                PdfLineTo(0.18, 0.42),
                PdfLineTo(0.62, 0.42),
                PdfLineTo(0.62, 0),
                PdfLineTo(0.8, 0),
                PdfLineTo(0.8, 1),
                PdfLineTo(0.62, 1),
                PdfLineTo(0.62, 0.6),
                PdfLineTo(0.18, 0.6),
                PdfLineTo(0.18, 1),
                PdfLineTo(0, 1),
                PdfClosePath(),
              ]),
            ),
          ],
          gradient: PdfGradient(
            isRadial: false,
            coords: [170, 180, 330, 360],
            colors: [PdfColor(1, 0.5, 0), PdfColor(0.4, 0, 0.9)],
            stops: [0, 1],
            transform: PdfMatrix.identity,
          ),
        )),
      ]);
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);

      const region = Rect.fromLTWH(20, 90, 540, 450);
      final canvas = await scene.rasterizeRegion(region, pixelRatio: 1.25);
      final accelerated =
          await session.rasterizeRegion(region, pixelRatio: 1.25);
      addTearDown(canvas.dispose);
      addTearDown(accelerated.dispose);
      final expected = await _pixels(canvas);
      final actual = await _pixels(accelerated);
      var difference = 0;
      for (var i = 0; i < expected.length; i++) {
        difference += (expected[i] - actual[i]).abs();
      }
      expect(difference / expected.length, lessThan(8),
          reason: 'translucent gradient and stencil AA must stay within the '
              'GPU corpus parity budget');
    });
  });

  testWidgets('nested radial gradients use bounded ring geometry',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final scene = await PdfRetainedScene.fromCommands(page, [
        PdfFillPathGradientCommand(
          _rect(35, 90, 560, 610),
          PdfFillRule.nonzero,
          const PdfGradient(
            isRadial: true,
            coords: [150, 220, 18, 205, 250, 190],
            colors: [
              PdfColor(1, 0.9, 0.1),
              PdfColor(0.9, 0.1, 0.2),
              PdfColor(0.05, 0.15, 0.8),
            ],
            stops: [0, 0.45, 1],
            transform: PdfMatrix(1.15, 0.12, -0.08, 1.05, 35, 20),
            extendStart: true,
            extendEnd: true,
          ),
          0.8,
        ),
      ]);
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);

      const region = Rect.fromLTWH(10, 70, 580, 570);
      final canvas = await scene.rasterizeRegion(region, pixelRatio: 1);
      final accelerated = await session.rasterizeRegion(region, pixelRatio: 1);
      addTearDown(canvas.dispose);
      addTearDown(accelerated.dispose);
      final expected = await _pixels(canvas);
      final actual = await _pixels(accelerated);
      var difference = 0;
      for (var i = 0; i < expected.length; i++) {
        difference += (expected[i] - actual[i]).abs();
      }
      expect(difference / expected.length, lessThan(12));
    });
  });

  testWidgets('nested arbitrary clips and restored ancestors match Canvas',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      const triangle = PdfPath([
        PdfMoveTo(50, 80),
        PdfLineTo(500, 120),
        PdfLineTo(260, 700),
        PdfClosePath(),
      ]);
      const evenOdd = PdfPath([
        PdfMoveTo(100, 150),
        PdfLineTo(450, 150),
        PdfLineTo(450, 600),
        PdfLineTo(100, 600),
        PdfClosePath(),
        PdfMoveTo(190, 260),
        PdfLineTo(360, 260),
        PdfLineTo(360, 490),
        PdfLineTo(190, 490),
        PdfClosePath(),
      ]);
      final scene = await PdfRetainedScene.fromCommands(page, [
        PdfFillPathCommand(_rect(0, 0, 612, 792),
            const PdfColor(0.92, 0.92, 0.92), PdfFillRule.nonzero, 1),
        const PdfSaveCommand(),
        const PdfClipPathCommand(triangle, PdfFillRule.nonzero),
        PdfFillPathCommand(_rect(0, 0, 612, 792), const PdfColor(0.1, 0.4, 0.9),
            PdfFillRule.nonzero, 0.8),
        const PdfSaveCommand(),
        const PdfClipPathCommand(evenOdd, PdfFillRule.evenOdd),
        PdfFillPathCommand(_rect(0, 0, 612, 792),
            const PdfColor(0.9, 0.15, 0.1), PdfFillRule.nonzero, 0.75),
        const PdfRestoreCommand(),
        PdfFillPathCommand(_rect(20, 300, 580, 390),
            const PdfColor(0.1, 0.75, 0.25), PdfFillRule.nonzero, 0.7),
        const PdfRestoreCommand(),
        PdfFillPathCommand(_rect(520, 650, 590, 740),
            const PdfColor(1, 0.75, 0), PdfFillRule.nonzero, 1),
      ]);
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);
      final region = Offset.zero & scene.pageSize;
      final expected = await scene.rasterizeRegion(region, pixelRatio: 0.75);
      final actual = await session.rasterizeRegion(region, pixelRatio: 0.75);
      addTearDown(expected.dispose);
      addTearDown(actual.dispose);
      final a = await _pixels(expected), b = await _pixels(actual);
      var difference = 0;
      for (var i = 0; i < a.length; i++) {
        difference += (a[i] - b[i]).abs();
      }
      expect(difference / a.length, lessThan(4));
      expect(backend.stats.clipPathsCompiled, 2);
      expect(backend.stats.clipMaskRebuilds, greaterThanOrEqualTo(3),
          reason: 'nested state and restored ancestor are rebuilt exactly');
    });
  });

  testWidgets('image textures survive sessions under a byte budget',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final scene = await PdfRetainedScene.record(
          PdfDocument.open(buildEmbeddedFontImagePdf()).page(0));
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend(maxTextureBytes: 1 << 20);
      final region = Offset.zero & scene.pageSize;

      final first = backend.createSession(scene)!;
      final firstImage = await first.rasterizeRegion(region, pixelRatio: 0.25);
      await _pixels(firstImage);
      firstImage.dispose();
      first.dispose();
      expect(backend.stats.texturesUploaded, 1);
      expect(backend.stats.textureBytes, greaterThan(0));

      final second = backend.createSession(scene)!;
      final secondImage =
          await second.rasterizeRegion(region, pixelRatio: 0.25);
      await _pixels(secondImage);
      secondImage.dispose();
      second.dispose();
      expect(backend.stats.texturesUploaded, 1);
      expect(backend.stats.textureCacheHits, 1);

      backend.clearImageCache();
      expect(backend.stats.textureBytes, 0);
      final third = backend.createSession(scene)!;
      final thirdImage = await third.rasterizeRegion(region, pixelRatio: 0.25);
      await _pixels(thirdImage);
      thirdImage.dispose();
      third.dispose();
      expect(backend.stats.texturesUploaded, 2);
    });
  });

  testWidgets('disposing an in-flight scene keeps its image texture leased',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final scene = await PdfRetainedScene.record(
          PdfDocument.open(buildEmbeddedFontImagePdf()).page(0));
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend(maxTextureBytes: 1 << 20);
      final session = backend.createSession(scene)!;

      // rasterizeRegion returns the resolve image as soon as the Metal command
      // buffer is submitted; the readback below is what waits for completion.
      // A page-tree edit can dispose the session in precisely this window.
      final image = await session.rasterizeRegion(
        Offset.zero & scene.pageSize,
        pixelRatio: 2,
      );
      expect(backend.stats.inFlightSubmissions, 1);
      expect(backend.stats.activeTextureLeases, 1);

      session.dispose();
      expect(backend.stats.activeTextureLeases, 1,
          reason: 'the submitted render pass still references the texture');

      await _pixels(image);
      image.dispose();
      for (var i = 0; i < 100 && backend.stats.activeTextureLeases != 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(backend.stats.inFlightSubmissions, 0);
      expect(backend.stats.activeTextureLeases, 0,
          reason: 'the completion fence releases the retired scene');
    });
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('content identity survives worker-reconstructed scenes',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final pixels = Uint8List.fromList([
        for (var i = 0; i < 4; i++) ...const [30, 90, 180, 255],
      ]);
      const transform = PdfMatrix(100, 0, 0, 100, 20, 30);
      final firstScene = await PdfRetainedScene.fromCommands(
        page,
        [
          _decodedImage(pixels, transform, 'shared-worker-image',
              workerReconstructed: true),
        ],
        retainDecodedPixels: true,
      );
      final secondScene = await PdfRetainedScene.fromCommands(
        page,
        [
          _decodedImage(pixels, transform, 'shared-worker-image',
              workerReconstructed: true),
        ],
        retainDecodedPixels: true,
      );
      addTearDown(firstScene.dispose);
      addTearDown(secondScene.dispose);
      final backend = FlutterGpuTileRasterBackend(maxTextureBytes: 1 << 20);
      final region = const Rect.fromLTWH(0, 0, 140, 150);

      final first = backend.createSession(firstScene)!;
      (await first.rasterizeRegion(region, pixelRatio: 1)).dispose();
      first.dispose();
      final second = backend.createSession(secondScene)!;
      (await second.rasterizeRegion(region, pixelRatio: 2)).dispose();
      second.dispose();

      expect(backend.stats.texturesUploaded, 1);
      expect(backend.stats.textureDirectUploads, 1);
      expect(backend.stats.textureCacheHits, 1);
      expect(
        (firstScene.commands.single as PdfDrawImageCommand).request.decoded,
        isNull,
        reason: 'the GPU upload releases the duplicate worker RGBA',
      );
      expect(
        (secondScene.commands.single as PdfDrawImageCommand).request.decoded,
        isNull,
      );
    });
  });

  testWidgets('texture budget counts resources pinned by active scenes',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      const transform = PdfMatrix(100, 0, 0, 100, 20, 30);
      PdfDrawImageCommand image(String id, List<int> color) => _decodedImage(
            Uint8List.fromList([for (var i = 0; i < 4; i++) ...color]),
            transform,
            id,
          );
      final firstScene = await PdfRetainedScene.fromCommands(page, [
        image('budget-a', const [20, 40, 60, 255]),
      ]);
      final secondScene = await PdfRetainedScene.fromCommands(page, [
        image('budget-b', const [120, 80, 40, 255]),
      ]);
      addTearDown(firstScene.dispose);
      addTearDown(secondScene.dispose);
      final backend = FlutterGpuTileRasterBackend(maxTextureBytes: 16);
      const region = Rect.fromLTWH(0, 0, 140, 150);

      final pinned = backend.createSession(firstScene)!;
      (await pinned.rasterizeRegion(region, pixelRatio: 1)).dispose();
      expect(backend.stats.textureBytes, 16);
      expect(backend.stats.activeTextureLeases, 1);

      final blocked = backend.createSession(secondScene)!;
      await expectLater(
        blocked.rasterizeRegion(region, pixelRatio: 1),
        throwsA(isA<StateError>()),
      );
      blocked.dispose();
      expect(backend.stats.textureBudgetFallbacks, 1);
      expect(backend.stats.rasterFallbacks, 1);
      expect(backend.stats.lastTileRoute, 'canvas-fallback');
      expect(backend.stats.texturesUploaded, 1,
          reason: 'a refused scene must not overshoot the byte ceiling');

      pinned.dispose();
      for (var i = 0; i < 100 && backend.stats.activeTextureLeases != 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(backend.stats.activeTextureLeases, 0);
      final admitted = backend.createSession(secondScene)!;
      (await admitted.rasterizeRegion(region, pixelRatio: 1)).dispose();
      admitted.dispose();
      expect(backend.stats.textureEvictions, 1);
      expect(backend.stats.textureBytes, 16);
      expect(backend.stats.peakTextureBytes, 16);
    });
  });

  testWidgets('geometry buffers stay bounded and reuse retired scene blocks',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final scene = await PdfRetainedScene.fromCommands(page, [
        PdfFillPathCommand(
          _rect(0, 0, 300, 300),
          const PdfColor(0.2, 0.6, 0.8),
          PdfFillRule.nonzero,
          1,
        ),
      ]);
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend(
        maxGeometryBytes: 16 << 20,
      );
      const region = Rect.fromLTWH(0, 0, 320, 320);

      final pinned = backend.createSession(scene)!;
      final firstImage = await pinned.rasterizeRegion(region, pixelRatio: 0.25);
      await _pixels(firstImage);
      firstImage.dispose();
      expect(backend.stats.geometryBuffers, 1);
      expect(backend.stats.geometryBytes, 16 << 20);
      expect(backend.stats.activeGeometryLeases, 1);

      final blocked = backend.createSession(scene)!;
      await expectLater(
        blocked.rasterizeRegion(region, pixelRatio: 0.25),
        throwsA(isA<StateError>()),
      );
      blocked.dispose();
      expect(backend.stats.geometryBudgetFallbacks, 1);
      expect(backend.stats.rasterFallbacks, 1);
      expect(backend.stats.lastTileRoute, 'canvas-fallback');
      expect(backend.stats.geometryBuffers, 1,
          reason: 'a pinned scene must not overshoot the byte ceiling');

      pinned.dispose();
      for (var i = 0; i < 100 && backend.stats.activeGeometryLeases != 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(backend.stats.activeGeometryLeases, 0);

      final admitted = backend.createSession(scene)!;
      final secondImage =
          await admitted.rasterizeRegion(region, pixelRatio: 0.25);
      await _pixels(secondImage);
      secondImage.dispose();
      admitted.dispose();
      expect(backend.stats.geometryBuffers, 1,
          reason: 'the retired 16 MiB block should be reused');
      expect(backend.stats.geometryBytes, 16 << 20);
      expect(backend.stats.peakGeometryBytes, 16 << 20);
    });
  });

  testWidgets('non-black overprint falls back unless explicitly approximated',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final scene = await PdfRetainedScene.fromCommands(page, [
        const PdfSetOverprintCommand(fill: true, stroke: false, mode: 1),
        PdfFillPathCommand(_rect(0, 0, 100, 100), const PdfColor(0.2, 0.6, 0.8),
            PdfFillRule.nonzero, 1),
      ]);
      addTearDown(scene.dispose);
      final exact = FlutterGpuTileRasterBackend();
      expect(exact.createSession(scene), isNull);
      expect(exact.stats.lastRejection, contains('overprint'));
      expect(exact.stats.lastTileRoute, 'canvas-fallback');

      final benchmark =
          FlutterGpuTileRasterBackend(allowOverprintApproximation: true);
      final session = benchmark.createSession(scene);
      expect(session, isNotNull, reason: benchmark.stats.lastRejection);
      expect(benchmark.stats.overprintApproximationSessions, 1);
      session!.dispose();
    });
  });

  testWidgets('isolated single-fill groups preserve clip blend and alpha',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final scene = await PdfRetainedScene.fromCommands(page, [
        PdfFillPathCommand(
          _rect(40, 100, 300, 360),
          const PdfColor(0.15, 0.75, 0.65),
          PdfFillRule.nonzero,
          1,
        ),
        const PdfSetBlendModeCommand(PdfBlendMode.multiply),
        const PdfBeginGroupCommand(0.55, knockout: true),
        const PdfSetBlendModeCommand(PdfBlendMode.screen),
        PdfClipPathCommand(_rect(100, 145, 255, 310), PdfFillRule.nonzero),
        const PdfSaveCommand(),
        PdfFillPathCommand(
          _rect(70, 120, 280, 340),
          const PdfColor(0.85, 0.18, 0.3),
          PdfFillRule.nonzero,
          0.7,
        ),
        const PdfRestoreCommand(),
        const PdfEndGroupCommand(),
        const PdfSetBlendModeCommand(PdfBlendMode.normal),
      ]);
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);

      const region = Rect.fromLTWH(30, 420, 300, 300);
      final expected = await scene.rasterizeRegion(region, pixelRatio: 1);
      final actual = await session.rasterizeRegion(region, pixelRatio: 1);
      addTearDown(expected.dispose);
      addTearDown(actual.dispose);
      final a = await _pixels(expected), b = await _pixels(actual);
      var difference = 0;
      for (var i = 0; i < a.length; i++) {
        difference += (a[i] - b[i]).abs();
      }
      expect(difference / a.length, lessThan(4));
    });
  });

  testWidgets('isolated single-stroke groups preserve clip blend and alpha',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final scene = await PdfRetainedScene.fromCommands(page, [
        PdfFillPathCommand(
          _rect(40, 100, 300, 360),
          const PdfColor(0.72, 0.68, 0.2),
          PdfFillRule.nonzero,
          1,
        ),
        const PdfSetBlendModeCommand(PdfBlendMode.screen),
        const PdfBeginGroupCommand(0.6),
        PdfClipPathCommand(_rect(75, 130, 275, 330), PdfFillRule.nonzero),
        const PdfStrokePathCommand(
          PdfPath([
            PdfMoveTo(50, 145),
            PdfLineTo(250, 315),
            PdfLineTo(295, 170),
          ]),
          PdfColor(0.2, 0.28, 0.9),
          PdfStroke(width: 9, cap: 1, join: 1, dashArray: [24, 8]),
          0.75,
        ),
        const PdfEndGroupCommand(),
        const PdfSetBlendModeCommand(PdfBlendMode.normal),
      ]);
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);

      const region = Rect.fromLTWH(30, 420, 300, 300);
      final expected = await scene.rasterizeRegion(region, pixelRatio: 1);
      final actual = await session.rasterizeRegion(region, pixelRatio: 1);
      addTearDown(expected.dispose);
      addTearDown(actual.dispose);
      final a = await _pixels(expected), b = await _pixels(actual);
      var difference = 0;
      for (var i = 0; i < a.length; i++) {
        difference += (a[i] - b[i]).abs();
      }
      expect(difference / a.length, lessThan(4));
    });
  });

  testWidgets('identity groups retain ordered fill and stroke paints',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final path = _rect(90, 145, 260, 315);
      final scene = await PdfRetainedScene.fromCommands(page, [
        const PdfBeginGroupCommand(1),
        const PdfSetBlendModeCommand(PdfBlendMode.normal),
        PdfClipPathCommand(_rect(75, 130, 275, 330), PdfFillRule.nonzero),
        const PdfSaveCommand(),
        PdfFillPathCommand(
          path,
          const PdfColor(0.82, 0.26, 0.68),
          PdfFillRule.nonzero,
          1,
        ),
        const PdfRestoreCommand(),
        const PdfSaveCommand(),
        PdfStrokePathCommand(
          path,
          const PdfColor(0.15, 0.72, 0.3),
          const PdfStroke(width: 7, join: 1),
          1,
        ),
        const PdfRestoreCommand(),
        const PdfEndGroupCommand(),
      ]);
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);

      const region = Rect.fromLTWH(50, 440, 260, 260);
      final expected = await scene.rasterizeRegion(region, pixelRatio: 1);
      final actual = await session.rasterizeRegion(region, pixelRatio: 1);
      addTearDown(expected.dispose);
      addTearDown(actual.dispose);
      final a = await _pixels(expected), b = await _pixels(actual);
      var difference = 0;
      for (var i = 0; i < a.length; i++) {
        difference += (a[i] - b[i]).abs();
      }
      expect(difference / a.length, lessThan(4));
    });
  });

  testWidgets(
      'single-image knockout luminosity masks stay as two retained textures',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final transform = const PdfMatrix(180, 0, 0, 180, 50, 100);
      final content = _decodedImage(
        Uint8List.fromList([
          for (var i = 0; i < 4; i++) ...const [220, 40, 20, 255],
        ]),
        transform,
        'content',
      );
      final mask = _decodedImage(
        Uint8List.fromList([
          0,
          0,
          0,
          255,
          255,
          255,
          255,
          255,
          0,
          0,
          0,
          255,
          255,
          255,
          255,
          255,
        ]),
        transform,
        'mask',
      );
      final scene = await PdfRetainedScene.fromCommands(
        page,
        [
          const PdfSaveCommand(),
          PdfClipPathCommand(_rect(80, 120, 190, 250), PdfFillRule.nonzero),
          const PdfBeginGroupCommand(0.75, knockout: true),
          const PdfBeginSoftMaskedCommand(),
          content,
          PdfEndSoftMaskedCommand(
            luminosity: true,
            backdrop: page.cropBox,
            maskCommands: [mask],
          ),
          const PdfEndGroupCommand(),
          const PdfRestoreCommand(),
        ],
        retainDecodedPixels: true,
      );
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);
      final region = const Rect.fromLTWH(40, 90, 200, 200);
      final expected = await scene.rasterizeRegion(region, pixelRatio: 1);
      final actual = await session.rasterizeRegion(region, pixelRatio: 1);
      addTearDown(expected.dispose);
      addTearDown(actual.dispose);
      final a = await _pixels(expected), b = await _pixels(actual);
      var difference = 0;
      for (var i = 0; i < a.length; i++) {
        difference += (a[i] - b[i]).abs();
      }
      expect(difference / a.length, lessThan(8));
      expect(backend.stats.texturesUploaded, 2);
      expect(backend.stats.textureDirectUploads, 2);
      expect(backend.stats.textureReadbacks, 0);
      expect(backend.stats.textureCacheMisses, 2);
      expect(content.request.decoded, isNull);
      expect(mask.request.decoded, isNull);
    });
  });

  testWidgets('single vector fills use an image soft mask directly',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final mask = _decodedImage(
        Uint8List.fromList([
          0,
          0,
          0,
          255,
          255,
          255,
          255,
          255,
          0,
          0,
          0,
          255,
          255,
          255,
          255,
          255,
        ]),
        const PdfMatrix(180, 0, 0, 180, 50, 100),
        'vector-mask',
      );
      final scene = await PdfRetainedScene.fromCommands(
        page,
        [
          const PdfBeginSoftMaskedCommand(),
          const PdfSetBlendModeCommand(PdfBlendMode.multiply),
          const PdfSetOverprintCommand(fill: true, stroke: true, mode: 1),
          PdfFillPathCommand(
            _rect(50, 100, 230, 280),
            const PdfColor(0.1, 0.7, 0.25),
            PdfFillRule.nonzero,
            0.8,
          ),
          PdfEndSoftMaskedCommand(
            luminosity: true,
            backdrop: page.cropBox,
            maskCommands: [mask],
          ),
        ],
        retainDecodedPixels: true,
      );
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);
      const region = Rect.fromLTWH(40, 90, 200, 200);
      final expected = await scene.rasterizeRegion(region, pixelRatio: 1);
      final actual = await session.rasterizeRegion(region, pixelRatio: 1);
      addTearDown(expected.dispose);
      addTearDown(actual.dispose);
      final a = await _pixels(expected), b = await _pixels(actual);
      var difference = 0;
      for (var i = 0; i < a.length; i++) {
        difference += (a[i] - b[i]).abs();
      }
      expect(difference / a.length, lessThan(8));
      expect(backend.stats.texturesUploaded, 1);
      expect(backend.stats.textureDirectUploads, 1);
      expect(mask.request.decoded, isNull);
    });
  });

  testWidgets('rectangular vector masks retain backdrop and transfer values',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final cases = <({bool luminosity, List<PdfRenderCommand> mask})>[
        (
          luminosity: false,
          mask: [
            PdfClipPathCommand(
              _rect(90, 150, 240, 300),
              PdfFillRule.nonzero,
            ),
            PdfFillPathCommand(
              _rect(60, 120, 270, 330),
              const PdfColor(1, 1, 1),
              PdfFillRule.nonzero,
              1,
            ),
          ],
        ),
        (
          luminosity: true,
          mask: [
            PdfFillPathCommand(
              _rect(90, 150, 165, 300),
              const PdfColor(0, 0, 0),
              PdfFillRule.nonzero,
              1,
            ),
            PdfFillPathCommand(
              _rect(165, 150, 240, 300),
              const PdfColor(1, 1, 1),
              PdfFillRule.nonzero,
              1,
            ),
          ],
        ),
      ];
      for (final testCase in cases) {
        final scene = await PdfRetainedScene.fromCommands(page, [
          const PdfBeginSoftMaskedCommand(),
          PdfFillPathCommand(
            _rect(50, 100, 280, 350),
            const PdfColor(0.2, 0.6, 0.9),
            PdfFillRule.nonzero,
            0.85,
          ),
          PdfEndSoftMaskedCommand(
            luminosity: testCase.luminosity,
            backdrop: page.cropBox,
            maskCommands: testCase.mask,
            backdropLuminance: 0.6,
            transferScale: 0.5,
            transferOffset: 0.25,
          ),
        ]);
        final backend = FlutterGpuTileRasterBackend();
        final session = backend.createSession(scene);
        expect(session, isNotNull, reason: backend.stats.lastRejection);
        const region = Rect.fromLTWH(40, 90, 250, 270);
        final expected = await scene.rasterizeRegion(region, pixelRatio: 1.5);
        final actual = await session!.rasterizeRegion(
          region,
          pixelRatio: 1.5,
        );
        try {
          final a = await _pixels(expected), b = await _pixels(actual);
          var difference = 0;
          for (var i = 0; i < a.length; i++) {
            difference += (a[i] - b[i]).abs();
          }
          expect(difference / a.length, lessThan(4),
              reason: testCase.luminosity ? 'luminosity mask' : 'alpha mask');
          expect(backend.stats.texturesUploaded, 0,
              reason: 'solid vector masks need no retained image surface');
        } finally {
          expected.dispose();
          actual.dispose();
          session.dispose();
          scene.dispose();
        }
      }
    });
  });

  testWidgets('unsupported pages are rejected instead of approximated',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final substituted = await PdfRetainedScene.record(page);
      addTearDown(substituted.dispose);
      final backend = FlutterGpuTileRasterBackend();
      expect(backend.createSession(substituted), isNull);
      expect(backend.stats.lastRejection,
          'unsupported text: missing glyph outlines');

      final radial = await PdfRetainedScene.fromCommands(page, [
        PdfFillPathGradientCommand(
          _rect(40, 40, 300, 300),
          PdfFillRule.nonzero,
          const PdfGradient(
            isRadial: true,
            coords: [80, 100, 50, 260, 100, 60],
            colors: [PdfColor(1, 0, 0), PdfColor(0, 0, 1)],
            stops: [0, 1],
            transform: PdfMatrix.identity,
          ),
          1,
        ),
      ]);
      addTearDown(radial.dispose);
      expect(backend.createSession(radial), isNull);
      expect(backend.stats.lastRejection,
          'unsupported non-nested radial gradient');

      final nonRectClip = await PdfRetainedScene.fromCommands(page, [
        const PdfSaveCommand(),
        PdfClipPathCommand(
          const PdfPath([
            PdfMoveTo(0, 0),
            PdfLineTo(300, 0),
            PdfLineTo(150, 300),
            PdfClosePath(),
          ]),
          PdfFillRule.nonzero,
        ),
        PdfFillPathCommand(_rect(0, 0, 300, 300), const PdfColor(1, 0, 0),
            PdfFillRule.nonzero, 1),
        const PdfRestoreCommand(),
      ]);
      addTearDown(nonRectClip.dispose);
      final clipSession = backend.createSession(nonRectClip);
      expect(clipSession, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(clipSession!.dispose);
      const clipRegion = Rect.fromLTWH(0, 0, 320, 320);
      final expected =
          await nonRectClip.rasterizeRegion(clipRegion, pixelRatio: 1);
      final actual =
          await clipSession.rasterizeRegion(clipRegion, pixelRatio: 1);
      addTearDown(expected.dispose);
      addTearDown(actual.dispose);
      final a = await _pixels(expected), b = await _pixels(actual);
      var difference = 0;
      for (var i = 0; i < a.length; i++) {
        difference += (a[i] - b[i]).abs();
      }
      expect(difference / a.length, lessThan(3),
          reason: 'arbitrary PDF clips should use the exact stencil route');
    });
  });

  testWidgets('tiled stencil images use scene-wide mipmaps', (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      const sourceSize = 64;
      final pixels = Uint8List(sourceSize * sourceSize * 4);
      for (var y = 0; y < sourceSize; y++) {
        for (var x = 0; x < sourceSize; x++) {
          final offset = 4 * (y * sourceSize + x);
          final on = ((x ~/ 2 + y ~/ 2).isEven) ? 255 : 0;
          pixels[offset] = on;
          pixels[offset + 1] = on;
          pixels[offset + 2] = on;
          pixels[offset + 3] = on;
        }
      }
      final stream = CosStream(
        CosDictionary({
          'Identity': CosString.fromText('minified-tiled-stencil'),
          'Width': const CosInteger(sourceSize),
          'Height': const CosInteger(sourceSize),
        }),
        Uint8List(0),
      );
      final origins = Float64List.fromList([
        for (var y = 0; y < 10; y++)
          for (var x = 0; x < 10; x++) x * 9.0,
      ]);
      final originsY = Float64List.fromList([
        for (var y = 0; y < 10; y++)
          for (var x = 0; x < 10; x++) y * 9.0,
      ]);
      final scene = await PdfRetainedScene.fromCommands(
        page,
        [
          PdfDrawTiledCellCommand(
            [
              PdfDrawImageCommand(PdfImageRequest(
                stream: stream,
                transform: const PdfMatrix(8, 0, 0, 8, 10, 10),
                isStencil: true,
                stencilColor: const PdfColor(0.1, 0.2, 0.8),
                decoded: PdfDecodedPixels(pixels, sourceSize, sourceSize),
              )),
            ],
            origins,
            originsY,
          ),
        ],
        retainDecodedPixels: true,
      );
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);

      const region = Rect.fromLTWH(0, 0, 110, 110);
      final expected = await scene.rasterizeRegion(region, pixelRatio: 1);
      final actual = await session.rasterizeRegion(region, pixelRatio: 1);
      addTearDown(expected.dispose);
      addTearDown(actual.dispose);
      final a = await _pixels(expected), b = await _pixels(actual);
      var difference = 0;
      for (var i = 0; i < a.length; i++) {
        difference += (a[i] - b[i]).abs();
      }
      expect(difference / a.length, lessThan(16));
      expect(backend.stats.textureBytes, 21840,
          reason: '64x64 RGBA plus every mip level flutter_gpu supports');
    });
  });

  testWidgets('an image whose /SMask stayed a companion surface renders',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      // A non-CMYK JPEG decodes through the platform codec, which keeps a
      // simple grayscale /SMask as a companion `ui.Image`. The GPU backend
      // keeps both surfaces as separate cached textures and combines them in
      // one shader pass; painting only the base would leave the JPEG opaque
      // and regress the black-rectangle failure from #675.
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final scene = await PdfRetainedScene.fromCommands(page, [
        PdfDrawImageCommand(PdfImageRequest(
          stream: _maskedJpegStream(),
          transform: PdfMatrix(100, 0, 0, 100, 50, 50),
        )),
      ]);
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);

      const region = Rect.fromLTWH(0, 0, 200, 200);
      final expected = await scene.rasterizeRegion(region, pixelRatio: 1);
      final actual = await session.rasterizeRegion(region, pixelRatio: 1);
      addTearDown(expected.dispose);
      addTearDown(actual.dispose);
      final a = await _pixels(expected), b = await _pixels(actual);
      var difference = 0;
      for (var i = 0; i < a.length; i++) {
        difference += (a[i] - b[i]).abs();
      }
      expect(difference / a.length, lessThan(2));
      expect(backend.stats.texturesUploaded, 2);
      expect(backend.stats.textureBytes, 8192,
          reason: '32x32 RGBA base plus its 32x32 RGBA mask');
    });
  });
}

/// A solid-colour JPEG with a Flate grayscale /SMask: the shape whose mask the
/// decoder defers to paint time as a companion GPU surface.
CosStream _maskedJpegStream() {
  const size = 32;
  final rgb = img.Image(width: size, height: size);
  for (final p in rgb) {
    p
      ..r = 40
      ..g = 200
      ..b = 90;
  }
  final mask = Uint8List(size * size)..fillRange(0, size * size ~/ 2, 0xFF);
  final maskBytes = Uint8List.fromList(ZLibCodec(level: 6).encode(mask));
  return CosStream(
    CosDictionary({
      'Subtype': const CosName('Image'),
      'Width': const CosInteger(size),
      'Height': const CosInteger(size),
      'BitsPerComponent': const CosInteger(8),
      'ColorSpace': const CosName('DeviceRGB'),
      'Filter': const CosName('DCTDecode'),
      'SMask': CosStream(
        CosDictionary({
          'Subtype': const CosName('Image'),
          'Width': const CosInteger(size),
          'Height': const CosInteger(size),
          'BitsPerComponent': const CosInteger(8),
          'ColorSpace': const CosName('DeviceGray'),
          'Filter': const CosName('FlateDecode'),
          'Length': CosInteger(maskBytes.length),
        }),
        maskBytes,
      ),
    }),
    Uint8List.fromList(img.encodeJpg(rgb, quality: 100)),
  );
}
