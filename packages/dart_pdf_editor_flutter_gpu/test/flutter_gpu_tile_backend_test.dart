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

void main() {
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

  testWidgets('single-image luminosity masks stay as two retained textures',
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
          const PdfBeginGroupCommand(0.75),
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

  testWidgets('an image whose /SMask stayed a companion surface falls back',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      // A non-CMYK JPEG decodes through the platform codec, which keeps a
      // simple grayscale /SMask as a companion `ui.Image` that only
      // CanvasPdfDevice knows how to compose. This backend uploads one texture
      // per image, so it must decline the scene rather than paint the base
      // opaque - the JPEG's masked-out area is solid black (#675).
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final scene = await PdfRetainedScene.fromCommands(page, [
        PdfDrawImageCommand(PdfImageRequest(
          stream: _maskedJpegStream(),
          transform: PdfMatrix(100, 0, 0, 100, 50, 50),
        )),
      ]);
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      expect(backend.createSession(scene), isNull);
      expect(backend.stats.lastRejection, contains('soft mask'));
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
