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

PdfDrawTextCommand _outlinedText({
  required PdfMatrix transform,
  required PdfColor color,
  double alpha = 1,
  bool fill = true,
  PdfColor? strokeColor,
  double strokeWidth = 0,
  double strokeAlpha = 1,
}) =>
    PdfDrawTextCommand(PdfTextRun(
      text: 'A',
      transform: transform,
      color: color,
      width: 1,
      glyphs: const [
        PdfGlyphPlacement(
          offset: 0,
          text: 'A',
          outline: PdfPath([
            PdfMoveTo(0.05, 0),
            PdfLineTo(0.5, 1),
            PdfLineTo(0.95, 0),
            PdfLineTo(0.7, 0),
            PdfLineTo(0.6, 0.3),
            PdfLineTo(0.4, 0.3),
            PdfLineTo(0.3, 0),
            PdfClosePath(),
          ]),
        ),
      ],
      fill: fill,
      fillAlpha: alpha,
      strokeColor: strokeColor,
      strokeWidth: strokeWidth,
      strokeAlpha: strokeAlpha,
    ));

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

  testWidgets(
      'simple and advanced interior clears preserve paper and edge coverage',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      for (final advanced in [false, true]) {
        final scene = await PdfRetainedScene.fromCommands(
          page,
          [
            if (advanced) const PdfSetBlendModeCommand(PdfBlendMode.overlay),
            PdfFillPathCommand(
              _rect(40, 40, 572, 752),
              const PdfColor(0.85, 0.12, 0.28),
              PdfFillRule.nonzero,
              0.7,
            ),
            if (advanced) const PdfSetBlendModeCommand(PdfBlendMode.normal),
          ],
          plan: const PdfPageRenderPlan(
            pageColor: Color(0x8066AA22),
            rotation: 90,
          ),
        );
        final backend = FlutterGpuTileRasterBackend();
        final session = backend.createSession(scene);
        expect(session, isNotNull,
            reason: '$advanced: ${backend.stats.lastRejection}');
        final liveSession = session!;
        try {
          for (final (region, clears) in const [
            (Rect.fromLTWH(60, 60, 240, 200), 1),
            (Rect.fromLTWH(0, 0, 240, 200), 1),
          ]) {
            final expected =
                await scene.rasterizeRegion(region, pixelRatio: 1.5);
            final actual =
                await liveSession.rasterizeRegion(region, pixelRatio: 1.5);
            try {
              final a = await _pixels(expected), b = await _pixels(actual);
              var difference = 0;
              var minimumAlpha = 255;
              for (var index = 0; index < a.length; index++) {
                difference += (a[index] - b[index]).abs();
                if (index % 4 == 3 && b[index] < minimumAlpha) {
                  minimumAlpha = b[index];
                }
              }
              expect(difference / a.length, lessThan(3),
                  reason: advanced ? 'advanced route' : 'simple route');
              expect(minimumAlpha, 255);
              expect(backend.stats.paperClearTiles, clears);
            } finally {
              expected.dispose();
              actual.dispose();
            }
          }
        } finally {
          liveSession.dispose();
          scene.dispose();
        }
      }
    });
  });

  testWidgets('content-free interior tiles skip raster attachments and draws',
      (tester) async {
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
          rotation: 270,
        ),
      );
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);

      for (final (region, paperOnly) in const [
        (Rect.fromLTWH(60, 60, 240, 200), 1),
        (Rect.fromLTWH(0, 0, 240, 200), 1),
      ]) {
        final expected = await scene.rasterizeRegion(region, pixelRatio: 1.5);
        final actual = await session.rasterizeRegion(region, pixelRatio: 1.5);
        try {
          final a = await _pixels(expected), b = await _pixels(actual);
          expect(b, a);
          expect(backend.stats.paperOnlyTiles, paperOnly);
        } finally {
          expected.dispose();
          actual.dispose();
        }
      }
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

  testWidgets('sub-MSAA positive strokes request exact Canvas fallback',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final scene = await PdfRetainedScene.fromCommands(page, [
        for (var index = 0; index < 128; index++)
          PdfStrokePathCommand(
            PdfPath([
              PdfMoveTo(60, index == 127 ? 400 : 240 + index * 0.01),
              PdfLineTo(550, index == 127 ? 400 : 240 + index * 0.01),
            ]),
            const PdfColor(0.05, 0.1, 0.2),
            const PdfStroke(width: 0.24),
            1,
          ),
      ]);
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);
      const region = Rect.fromLTWH(40, 500, 520, 100);

      final expected = await scene.rasterizeRegion(region, pixelRatio: 2);
      final accelerated = await session.rasterizeRegion(region, pixelRatio: 2);
      try {
        final a = await _pixels(expected), b = await _pixels(accelerated);
        var difference = 0;
        for (var index = 0; index < a.length; index++) {
          difference += (a[index] - b[index]).abs();
        }
        expect(difference / a.length, lessThan(3));
      } finally {
        expected.dispose();
        accelerated.dispose();
      }

      final belowThreshold =
          await session.rasterizeRegion(region, pixelRatio: 0.5);
      belowThreshold.dispose();
      expect(backend.stats.subpixelStrokeFallbacks, 0);

      await expectLater(
        session.rasterizeRegion(
          Offset.zero & scene.pageSize,
          pixelRatio: 0.5,
        ),
        throwsA(isA<StateError>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('128 paint units contain positive-width strokes'),
            contains('below the 0.25 flutter_gpu coverage quantum'),
          ),
        )),
      );
      expect(backend.stats.subpixelStrokeFallbacks, 1);
      expect(backend.stats.rasterFallbacks, 1);
      expect(backend.stats.lastTileRoute, 'canvas-fallback');
    });
  });

  testWidgets('dense hairlines roll transient buffers without crossing blocks',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      PdfPath densePath(int points, double baseline) => PdfPath([
            PdfMoveTo(35, baseline),
            for (var index = 1; index < points; index++)
              PdfLineTo(
                35 + (index % 520),
                baseline + (index.isEven ? 2 : -2),
              ),
          ]);
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final scene = await PdfRetainedScene.fromCommands(page, [
        for (final (points, baseline) in const [(6200, 240.0), (4200, 300.0)])
          PdfStrokePathCommand(
            densePath(points, baseline),
            const PdfColor(0.05, 0.12, 0.3),
            const PdfStroke(width: 0, cap: 1, join: 1),
            1,
          ),
      ]);
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend(msaa: false);
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);

      final image = await session.rasterizeRegion(
        const Rect.fromLTWH(0, 400, 612, 220),
        pixelRatio: 0.5,
      );
      addTearDown(image.dispose);
      final pixels = await _pixels(image);
      expect(
        pixels.indexed.any((item) => item.$1 % 4 != 3 && item.$2 < 240),
        isTrue,
      );
      expect(
        backend.stats.transientEmplacedBytes,
        greaterThan(1024000),
        reason: 'the regression must cross Flutter HostBuffer\'s old block',
      );
      expect(backend.stats.transientBuffers, greaterThan(1));
      expect(backend.stats.peakTransientTileBytes, lessThan(4 << 20));
    });
  });

  testWidgets('filled, stroked, and hairline text retain exact GPU outlines',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final scene = await PdfRetainedScene.fromCommands(page, [
        _outlinedText(
          transform: const PdfMatrix(120, 0, 0, 120, 70, 110),
          color: const PdfColor(0.95, 0.65, 0.08),
          alpha: 0.85,
          strokeColor: const PdfColor(0.08, 0.16, 0.6),
          strokeWidth: 7,
          strokeAlpha: 0.75,
        ),
        _outlinedText(
          transform: const PdfMatrix(120, 0, 0, 120, 260, 110),
          color: const PdfColor(0, 0, 0),
          fill: false,
          strokeColor: const PdfColor(0.75, 0.1, 0.22),
          strokeWidth: 0,
          strokeAlpha: 0.9,
        ),
      ]);
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);

      const region = Rect.fromLTWH(40, 520, 390, 180);
      for (final ratio in [0.5, 1.5, 3.0]) {
        final expected = await scene.rasterizeRegion(region, pixelRatio: ratio);
        final actual = await session.rasterizeRegion(region, pixelRatio: ratio);
        try {
          final a = await _pixels(expected), b = await _pixels(actual);
          var difference = 0;
          for (var i = 0; i < a.length; i++) {
            difference += (a[i] - b[i]).abs();
          }
          expect(difference / a.length, lessThan(8), reason: 'ratio=$ratio');
        } finally {
          expected.dispose();
          actual.dispose();
        }
      }
      expect(backend.stats.analyticTextRuns, 1);
      expect(backend.stats.analyticGlyphQuads, 1);
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
        const region = Rect.fromLTWH(40, 390, 320, 320);
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

  testWidgets('advanced blend modes sample the exact retained backdrop',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      for (final mode in PdfBlendMode.values.skip(3)) {
        final sourceColor = switch (mode) {
          // Exercise the exact PDF boundary branches rather than relying on
          // division by a tiny epsilon to approximate them.
          PdfBlendMode.colorDodge => const PdfColor(1, 0.26, 0.12),
          PdfBlendMode.colorBurn => const PdfColor(0, 0.26, 0.12),
          _ => const PdfColor(0.88, 0.26, 0.12),
        };
        final scene = await PdfRetainedScene.fromCommands(page, [
          PdfFillPathCommand(
            _rect(50, 100, 350, 400),
            const PdfColor(0.16, 0.52, 0.82),
            PdfFillRule.nonzero,
            1,
          ),
          PdfSetBlendModeCommand(mode),
          PdfFillPathCommand(
            _rect(20, 180, 180, 350),
            sourceColor,
            PdfFillRule.nonzero,
            0.63,
          ),
          const PdfSetBlendModeCommand(PdfBlendMode.normal),
        ]);
        final backend = FlutterGpuTileRasterBackend();
        final session = backend.createSession(scene);
        expect(session, isNotNull,
            reason: '${mode.name}: ${backend.stats.lastRejection}');
        const region = Rect.fromLTWH(40, 390, 320, 320);
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
          expect(backend.stats.advancedBlendPasses, 1);
          expect(backend.stats.advancedBlendCroppedSources, 1);
          expect(
            backend.stats.peakAdvancedBlendBytes,
            lessThan(480 * 480 * 48),
          );
        } finally {
          expected.dispose();
          actual.dispose();
          session.dispose();
          scene.dispose();
        }
      }
    });
  });

  testWidgets('disjoint advanced blends share one destination-sampling pass',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final scene = await PdfRetainedScene.fromCommands(page, [
        PdfFillPathCommand(
          _rect(40, 100, 500, 400),
          const PdfColor(0.16, 0.52, 0.82),
          PdfFillRule.nonzero,
          1,
        ),
        const PdfSetBlendModeCommand(PdfBlendMode.overlay),
        PdfFillPathCommand(
          _rect(70, 150, 200, 350),
          const PdfColor(0.88, 0.26, 0.12),
          PdfFillRule.nonzero,
          0.63,
        ),
        const PdfSetBlendModeCommand(PdfBlendMode.colorBurn),
        PdfFillPathCommand(
          _rect(300, 150, 430, 350),
          const PdfColor(0.2, 0.85, 0.35),
          PdfFillRule.nonzero,
          0.72,
        ),
        const PdfSetBlendModeCommand(PdfBlendMode.normal),
      ]);
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);

      const region = Rect.fromLTWH(20, 370, 500, 340);
      final expected = await scene.rasterizeRegion(region, pixelRatio: 1.5);
      final actual = await session.rasterizeRegion(region, pixelRatio: 1.5);
      addTearDown(expected.dispose);
      addTearDown(actual.dispose);
      final a = await _pixels(expected), b = await _pixels(actual);
      var difference = 0;
      for (var i = 0; i < a.length; i++) {
        difference += (a[i] - b[i]).abs();
      }
      expect(difference / a.length, lessThan(3));
      expect(backend.stats.advancedBlendPasses, 1);
    });
  });

  testWidgets('overlapping advanced blends preserve painter order',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final scene = await PdfRetainedScene.fromCommands(page, [
        PdfFillPathCommand(
          _rect(40, 100, 500, 400),
          const PdfColor(0.16, 0.52, 0.82),
          PdfFillRule.nonzero,
          1,
        ),
        const PdfSetBlendModeCommand(PdfBlendMode.overlay),
        PdfFillPathCommand(
          _rect(70, 150, 330, 350),
          const PdfColor(0.88, 0.26, 0.12),
          PdfFillRule.nonzero,
          0.63,
        ),
        const PdfSetBlendModeCommand(PdfBlendMode.colorBurn),
        PdfFillPathCommand(
          _rect(240, 150, 430, 350),
          const PdfColor(0.2, 0.85, 0.35),
          PdfFillRule.nonzero,
          0.72,
        ),
        const PdfSetBlendModeCommand(PdfBlendMode.normal),
      ]);
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);

      const region = Rect.fromLTWH(20, 370, 500, 340);
      final expected = await scene.rasterizeRegion(region, pixelRatio: 1.5);
      final actual = await session.rasterizeRegion(region, pixelRatio: 1.5);
      addTearDown(expected.dispose);
      addTearDown(actual.dispose);
      final a = await _pixels(expected), b = await _pixels(actual);
      var difference = 0;
      for (var i = 0; i < a.length; i++) {
        difference += (a[i] - b[i]).abs();
      }
      expect(difference / a.length, lessThan(3));
      expect(backend.stats.advancedBlendPasses, 2);
      expect(backend.stats.advancedBlendBlits, 2);
    });
  });

  testWidgets('repeated thin advanced-blend strokes preserve opaque backdrop',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final commands = <PdfRenderCommand>[
        PdfFillPathCommand(
          _rect(0, 0, 300, 160),
          const PdfColor(0.82, 0.68, 0.34),
          PdfFillRule.nonzero,
          1,
        ),
        const PdfSetBlendModeCommand(PdfBlendMode.darken),
        for (var index = 0; index < 8; index++)
          PdfStrokePathCommand(
            PdfPath([
              PdfMoveTo(15, 20 + index * 3),
              PdfLineTo(285, 110 + index * 3),
            ]),
            PdfColor(0.12 + index * 0.03, 0.24, 0.72),
            const PdfStroke(width: 0.4),
            1,
          ),
        const PdfSetBlendModeCommand(PdfBlendMode.normal),
      ];
      final scene = await PdfRetainedScene.fromCommands(page, commands);
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
      var minimumAlpha = 255;
      for (var index = 0; index < a.length; index++) {
        difference += (a[index] - b[index]).abs();
        if (index % 4 == 3 && b[index] < minimumAlpha) {
          minimumAlpha = b[index];
        }
      }
      expect(difference / a.length, lessThan(3));
      expect(minimumAlpha, 255);
      expect(backend.stats.advancedBlendPasses, 1);
      expect(backend.stats.advancedBlendBlits, 1);
    });
  });

  testWidgets('advanced blends surrounding offscreen groups stay exact',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      const backdrop = PdfColor(0.24, 0.58, 0.72);
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final commands = <PdfRenderCommand>[
        PdfFillPathCommand(
          _rect(0, 0, 300, 160),
          backdrop,
          PdfFillRule.nonzero,
          1,
        ),
        const PdfSetBlendModeCommand(PdfBlendMode.overlay),
        PdfFillPathCommand(
          _rect(25, 65, 205, 155),
          const PdfColor(0.86, 0.64, 0.18),
          PdfFillRule.nonzero,
          0.58,
        ),
        const PdfSetBlendModeCommand(PdfBlendMode.normal),
        const PdfBeginGroupCommand(
          1,
          knockout: true,
          bounds: PdfRect(55, 75, 175, 150),
          backdropColor: backdrop,
        ),
        PdfClipPathCommand(_rect(55, 75, 175, 150), PdfFillRule.nonzero),
        PdfFillPathCommand(
          _rect(65, 85, 145, 140),
          const PdfColor(0.92, 0.24, 0.16),
          PdfFillRule.nonzero,
          1,
        ),
        PdfFillPathCommand(
          _rect(105, 95, 165, 145),
          const PdfColor(0.14, 0.38, 0.94),
          PdfFillRule.nonzero,
          1,
        ),
        const PdfEndGroupCommand(),
        const PdfSetBlendModeCommand(PdfBlendMode.darken),
        for (var index = 0; index < 8; index++)
          PdfStrokePathCommand(
            PdfPath([
              PdfMoveTo(15, 20 + index * 3),
              PdfLineTo(285, 110 + index * 3),
            ]),
            PdfColor(0.12 + index * 0.03, 0.24, 0.72),
            const PdfStroke(width: 0.4),
            1,
          ),
        const PdfSetBlendModeCommand(PdfBlendMode.normal),
      ];
      final scene = await PdfRetainedScene.fromCommands(page, commands);
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
      var minimumAlpha = 255;
      for (var index = 0; index < a.length; index++) {
        difference += (a[index] - b[index]).abs();
        if (index % 4 == 3 && b[index] < minimumAlpha) {
          minimumAlpha = b[index];
        }
      }
      expect(difference / a.length, lessThan(3));
      expect(minimumAlpha, 255);
      expect(backend.stats.offscreenGroupPasses, 1);
      expect(backend.stats.advancedBlendPasses, 2);
    });
  });

  testWidgets('disjoint advanced-blend strokes share one source and blend',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final commands = <PdfRenderCommand>[
        PdfFillPathCommand(
          _rect(0, 0, 612, 792),
          const PdfColor(0.24, 0.58, 0.72),
          PdfFillRule.nonzero,
          1,
        ),
        const PdfSetBlendModeCommand(PdfBlendMode.darken),
        for (var index = 0; index < 6; index++)
          PdfStrokePathCommand(
            PdfPath([
              PdfMoveTo(55, 105 + index * 10),
              PdfLineTo(557, 465 + index * 10),
            ]),
            PdfColor(0.12 + index * 0.05, 0.24, 0.72),
            const PdfStroke(width: 2.5),
            1,
          ),
        const PdfSetBlendModeCommand(PdfBlendMode.normal),
      ];
      final scene = await PdfRetainedScene.fromCommands(page, commands);
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);

      const region = Rect.fromLTWH(50, 120, 512, 512);
      final expected = await scene.rasterizeRegion(region, pixelRatio: 1);
      final actual = await session.rasterizeRegion(region, pixelRatio: 1);
      addTearDown(expected.dispose);
      addTearDown(actual.dispose);
      final a = await _pixels(expected), b = await _pixels(actual);
      var difference = 0;
      for (var index = 0; index < a.length; index++) {
        difference += (a[index] - b[index]).abs();
      }
      expect(difference / a.length, lessThan(3));
      // This point lies inside the strokes' overlapping conservative bounds
      // but outside every thin source contour. The blend target already holds
      // the copied backdrop, so a transparent-source fragment must leave it
      // byte-identical.
      const transparentGap = (200 * 512 + 250) * 4;
      expect(
        b.sublist(transparentGap, transparentGap + 4),
        a.sublist(transparentGap, transparentGap + 4),
      );
      expect(backend.stats.advancedBlendPasses, 1);
      expect(backend.stats.advancedBlendBlits, 1);
    });
  });

  testWidgets('overlapping advanced-blend strokes keep ordered blends',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final scene = await PdfRetainedScene.fromCommands(page, [
        PdfFillPathCommand(
          _rect(0, 0, 612, 792),
          const PdfColor(0.24, 0.58, 0.72),
          PdfFillRule.nonzero,
          1,
        ),
        const PdfSetBlendModeCommand(PdfBlendMode.darken),
        for (var index = 0; index < 2; index++)
          PdfStrokePathCommand(
            PdfPath([
              PdfMoveTo(55, 105 + index * 2),
              PdfLineTo(557, 465 + index * 2),
            ]),
            PdfColor(0.15 + index * 0.45, 0.24, 0.72),
            const PdfStroke(width: 2.5),
            1,
          ),
        const PdfSetBlendModeCommand(PdfBlendMode.normal),
      ]);
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);

      const region = Rect.fromLTWH(50, 120, 512, 512);
      final expected = await scene.rasterizeRegion(region, pixelRatio: 1);
      final actual = await session.rasterizeRegion(region, pixelRatio: 1);
      addTearDown(expected.dispose);
      addTearDown(actual.dispose);
      final a = await _pixels(expected), b = await _pixels(actual);
      var difference = 0;
      for (var index = 0; index < a.length; index++) {
        difference += (a[index] - b[index]).abs();
      }
      expect(difference / a.length, lessThan(3));
      expect(backend.stats.advancedBlendPasses, 2);
      expect(backend.stats.advancedBlendBlits, 2);
    });
  });

  testWidgets('offscreen groups retain an advanced outer blend',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final scene = await PdfRetainedScene.fromCommands(page, [
        PdfFillPathCommand(
          _rect(30, 90, 310, 370),
          const PdfColor(0.45, 0.55, 0.7),
          PdfFillRule.nonzero,
          1,
        ),
        const PdfSetBlendModeCommand(PdfBlendMode.overlay),
        const PdfBeginGroupCommand(
          0.72,
          isolated: true,
          bounds: PdfRect(50, 110, 290, 350),
        ),
        const PdfSetBlendModeCommand(PdfBlendMode.normal),
        PdfClipPathCommand(_rect(50, 110, 290, 350), PdfFillRule.nonzero),
        PdfFillPathCommand(
          _rect(70, 140, 230, 310),
          const PdfColor(0.95, 0.25, 0.15),
          PdfFillRule.nonzero,
          0.65,
        ),
        PdfFillPathCommand(
          _rect(150, 160, 270, 325),
          const PdfColor(0.15, 0.45, 0.95),
          PdfFillRule.nonzero,
          0.55,
        ),
        PdfStrokePathCommand(
          PdfPath(const [
            PdfMoveTo(62, 125),
            PdfLineTo(278, 338),
          ]),
          const PdfColor(0.12, 0.78, 0.32),
          const PdfStroke(width: 28),
          0.8,
        ),
        const PdfEndGroupCommand(),
        const PdfSetBlendModeCommand(PdfBlendMode.normal),
      ]);
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);

      final region = Offset.zero & scene.pageSize;
      final expected = await scene.rasterizeRegion(region, pixelRatio: 1);
      final actual = await session.rasterizeRegion(region, pixelRatio: 1);
      addTearDown(expected.dispose);
      addTearDown(actual.dispose);
      final a = await _pixels(expected), b = await _pixels(actual);
      var difference = 0;
      var minimumAlpha = 255;
      for (var index = 0; index < a.length; index++) {
        difference += (a[index] - b[index]).abs();
        if (index % 4 == 3 && b[index] < minimumAlpha) {
          minimumAlpha = b[index];
        }
      }
      expect(difference / a.length, lessThan(3));
      expect(minimumAlpha, 255);
      expect(backend.stats.offscreenGroupPasses, 1);
      expect(backend.stats.advancedBlendPasses, 1);
      expect(backend.stats.advancedBlendCroppedSources, 1);
    });
  });

  testWidgets('advanced blend budget rejects before allocating ping-pong tiles',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final scene = await PdfRetainedScene.fromCommands(page, [
        const PdfSetBlendModeCommand(PdfBlendMode.overlay),
        PdfFillPathCommand(
          _rect(40, 100, 500, 400),
          const PdfColor(0.88, 0.26, 0.12),
          PdfFillRule.nonzero,
          0.63,
        ),
      ]);
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);

      await expectLater(
        session.rasterizeRegion(
          const Rect.fromLTWH(0, 0, 612, 792),
          pixelRatio: 8,
        ),
        throwsA(isA<StateError>()),
      );
      expect(backend.stats.advancedBlendBudgetFallbacks, 1);
      expect(backend.stats.advancedBlendAllocatedBytes, 0);
      expect(backend.stats.advancedBlendPasses, 0);
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

  testWidgets('geometry buffers stay bounded and reuse retired size classes',
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
        maxGeometryBytes: 64 << 10,
      );
      const region = Rect.fromLTWH(0, 0, 320, 320);

      final pinned = backend.createSession(scene)!;
      final firstImage = await pinned.rasterizeRegion(region, pixelRatio: 0.25);
      await _pixels(firstImage);
      firstImage.dispose();
      expect(backend.stats.geometryBuffers, 1);
      expect(backend.stats.geometryBytes, 64 << 10);
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
          reason: 'the retired 64 KiB size class should be reused');
      expect(backend.stats.geometryBytes, 64 << 10);
      expect(backend.stats.peakGeometryBytes, 64 << 10);
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

  testWidgets('solid black overprint remains exact inside groups',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final scene = await PdfRetainedScene.fromCommands(page, [
        PdfFillPathCommand(
          _rect(30, 90, 310, 370),
          const PdfColor(0.35, 0.65, 0.85),
          PdfFillRule.nonzero,
          1,
        ),
        const PdfBeginGroupCommand(1),
        const PdfSetOverprintCommand(fill: true, stroke: false, mode: 1),
        PdfFillPathCommand(
          _rect(65, 125, 145, 325),
          PdfColor.black,
          PdfFillRule.nonzero,
          1,
        ),
        const PdfEndGroupCommand(),
        const PdfBeginGroupCommand(1, isolated: true),
        const PdfSetOverprintCommand(fill: false, stroke: false, mode: 1),
        PdfFillPathCommand(
          _rect(150, 125, 275, 325),
          const PdfColor(0.9, 0.55, 0.2),
          PdfFillRule.nonzero,
          1,
        ),
        const PdfSetOverprintCommand(fill: true, stroke: false, mode: 1),
        PdfFillPathCommand(
          _rect(205, 160, 290, 290),
          PdfColor.black,
          PdfFillRule.nonzero,
          1,
        ),
        const PdfEndGroupCommand(),
      ]);
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.lastSessionRejection);
      addTearDown(session!.dispose);

      const region = Rect.fromLTWH(20, 410, 310, 310);
      final expected = await scene.rasterizeRegion(region, pixelRatio: 1.25);
      final actual = await session.rasterizeRegion(region, pixelRatio: 1.25);
      addTearDown(expected.dispose);
      addTearDown(actual.dispose);
      final a = await _pixels(expected), b = await _pixels(actual);
      var difference = 0;
      for (var index = 0; index < a.length; index++) {
        difference += (a[index] - b[index]).abs();
      }
      expect(difference / a.length, lessThan(4));
    });
  });

  testWidgets('colored overprint inside a group reports the exact fallback',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final scene = await PdfRetainedScene.fromCommands(page, [
        const PdfBeginGroupCommand(1, isolated: true),
        const PdfSetOverprintCommand(fill: true, stroke: false, mode: 1),
        PdfFillPathCommand(
          _rect(70, 140, 220, 310),
          const PdfColor(0.95, 0.7, 0.2),
          PdfFillRule.nonzero,
          1,
        ),
        PdfFillPathCommand(
          _rect(150, 140, 270, 310),
          const PdfColor(0.2, 0.8, 0.85),
          PdfFillRule.nonzero,
          1,
        ),
        const PdfEndGroupCommand(),
      ]);
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      expect(backend.createSession(scene), isNull);
      expect(
        backend.stats.lastRejection,
        'non-black overprint requires Canvas fallback',
      );
    });
  });

  testWidgets('empty clipped transparency groups remain no-ops',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final scene = await PdfRetainedScene.fromCommands(page, [
        PdfFillPathCommand(
          _rect(20, 80, 180, 240),
          const PdfColor(0.1, 0.7, 0.25),
          PdfFillRule.nonzero,
          1,
        ),
        const PdfBeginGroupCommand(1),
        PdfClipPathCommand(_rect(80, 100, 80, 220), PdfFillRule.nonzero),
        const PdfEndGroupCommand(),
        PdfFillPathCommand(
          _rect(210, 80, 370, 240),
          const PdfColor(0.75, 0.2, 0.15),
          PdfFillRule.nonzero,
          1,
        ),
      ]);
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);
      const region = Rect.fromLTWH(0, 60, 400, 200);
      final expected = await scene.rasterizeRegion(region, pixelRatio: 1);
      final actual = await session.rasterizeRegion(region, pixelRatio: 1);
      addTearDown(expected.dispose);
      addTearDown(actual.dispose);
      final a = await _pixels(expected), b = await _pixels(actual);
      var difference = 0;
      for (var i = 0; i < a.length; i++) {
        difference += (a[i] - b[i]).abs();
      }
      expect(difference / a.length, lessThan(1));
      expect(backend.stats.lastTileRoute, 'flutter_gpu');

      final painted = await PdfRetainedScene.fromCommands(page, [
        const PdfBeginGroupCommand(1),
        PdfClipPathCommand(_rect(80, 100, 80, 220), PdfFillRule.nonzero),
        PdfFillPathCommand(
          _rect(60, 90, 100, 230),
          const PdfColor(0.8, 0.2, 0.1),
          PdfFillRule.nonzero,
          1,
        ),
        const PdfEndGroupCommand(),
      ]);
      addTearDown(painted.dispose);
      final paintedBackend = FlutterGpuTileRasterBackend();
      final paintedSession = paintedBackend.createSession(painted);
      expect(paintedSession, isNotNull,
          reason: paintedBackend.stats.lastRejection);
      addTearDown(paintedSession!.dispose);
      const paintedRegion = Rect.fromLTWH(40, 70, 80, 180);
      final paintedExpected =
          await painted.rasterizeRegion(paintedRegion, pixelRatio: 1);
      final paintedActual =
          await paintedSession.rasterizeRegion(paintedRegion, pixelRatio: 1);
      addTearDown(paintedExpected.dispose);
      addTearDown(paintedActual.dispose);
      expect(await _pixels(paintedActual), await _pixels(paintedExpected));

      final restored = await PdfRetainedScene.fromCommands(page, [
        const PdfBeginGroupCommand(1),
        const PdfSaveCommand(),
        PdfClipPathCommand(_rect(80, 100, 80, 220), PdfFillRule.nonzero),
        PdfFillPathCommand(
          _rect(60, 90, 100, 230),
          const PdfColor(0.8, 0.2, 0.1),
          PdfFillRule.nonzero,
          1,
        ),
        const PdfRestoreCommand(),
        PdfFillPathCommand(
          _rect(140, 90, 260, 230),
          const PdfColor(0.15, 0.45, 0.85),
          PdfFillRule.nonzero,
          0.8,
        ),
        const PdfEndGroupCommand(),
      ]);
      addTearDown(restored.dispose);
      final restoredBackend = FlutterGpuTileRasterBackend();
      final restoredSession = restoredBackend.createSession(restored);
      expect(restoredSession, isNotNull,
          reason: restoredBackend.stats.lastRejection);
      addTearDown(restoredSession!.dispose);
      const restoredRegion = Rect.fromLTWH(40, 70, 240, 180);
      final restoredExpected =
          await restored.rasterizeRegion(restoredRegion, pixelRatio: 1);
      final restoredActual =
          await restoredSession.rasterizeRegion(restoredRegion, pixelRatio: 1);
      addTearDown(restoredExpected.dispose);
      addTearDown(restoredActual.dispose);
      final restoredA = await _pixels(restoredExpected);
      final restoredB = await _pixels(restoredActual);
      var restoredDifference = 0;
      for (var index = 0; index < restoredA.length; index++) {
        restoredDifference += (restoredA[index] - restoredB[index]).abs();
      }
      expect(restoredDifference / restoredA.length, lessThan(1));

      final transform = const PdfMatrix(80, 0, 0, 80, 60, 90);
      final maskedEmpty = await PdfRetainedScene.fromCommands(
        page,
        [
          const PdfBeginGroupCommand(1),
          const PdfSaveCommand(),
          PdfClipPathCommand(_rect(80, 100, 80, 220), PdfFillRule.nonzero),
          const PdfBeginSoftMaskedCommand(),
          _decodedImage(
            Uint8List.fromList([
              for (var i = 0; i < 4; i++) ...const [200, 40, 20, 255],
            ]),
            transform,
            'empty-clipped-content',
          ),
          PdfEndSoftMaskedCommand(
            luminosity: false,
            backdrop: page.cropBox,
            maskCommands: [
              _decodedImage(
                Uint8List.fromList([
                  for (var i = 0; i < 4; i++) ...const [255, 255, 255, 255],
                ]),
                transform,
                'empty-clipped-mask',
              ),
            ],
          ),
          const PdfRestoreCommand(),
          const PdfEndGroupCommand(),
          PdfFillPathCommand(
            _rect(180, 90, 300, 230),
            const PdfColor(0.2, 0.55, 0.85),
            PdfFillRule.nonzero,
            0.9,
          ),
        ],
        retainDecodedPixels: true,
      );
      addTearDown(maskedEmpty.dispose);
      final maskedBackend = FlutterGpuTileRasterBackend();
      final maskedSession = maskedBackend.createSession(maskedEmpty);
      expect(maskedSession, isNotNull,
          reason: maskedBackend.stats.lastRejection);
      addTearDown(maskedSession!.dispose);
      const maskedRegion = Rect.fromLTWH(40, 70, 280, 180);
      final maskedExpected =
          await maskedEmpty.rasterizeRegion(maskedRegion, pixelRatio: 1);
      final maskedActual =
          await maskedSession.rasterizeRegion(maskedRegion, pixelRatio: 1);
      addTearDown(maskedExpected.dispose);
      addTearDown(maskedActual.dispose);
      expect(await _pixels(maskedActual), await _pixels(maskedExpected));
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

  testWidgets('isolated single-text groups preserve clip blend and alpha',
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
        const PdfSetBlendModeCommand(PdfBlendMode.multiply),
        const PdfBeginGroupCommand(0.58),
        PdfClipPathCommand(_rect(75, 130, 275, 330), PdfFillRule.nonzero),
        _outlinedText(
          transform: const PdfMatrix(170, 0, 0, 170, 95, 145),
          color: const PdfColor(0.2, 0.28, 0.9),
          alpha: 0.75,
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

  testWidgets('isolated single-image groups preserve clip blend and alpha',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final scene = await PdfRetainedScene.fromCommands(
        page,
        [
          PdfFillPathCommand(
            _rect(40, 100, 300, 360),
            const PdfColor(0.72, 0.68, 0.2),
            PdfFillRule.nonzero,
            1,
          ),
          const PdfSetBlendModeCommand(PdfBlendMode.multiply),
          const PdfBeginGroupCommand(0.58),
          PdfClipPathCommand(_rect(75, 130, 275, 330), PdfFillRule.nonzero),
          _decodedImage(
            Uint8List.fromList(const [
              220,
              35,
              40,
              255,
              25,
              180,
              215,
              255,
              45,
              90,
              225,
              255,
              235,
              195,
              30,
              255,
            ]),
            const PdfMatrix(190, 0, 0, 190, 80, 135),
            'single-group-image',
          ),
          const PdfEndGroupCommand(),
          const PdfSetBlendModeCommand(PdfBlendMode.normal),
        ],
        retainDecodedPixels: true,
      );
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
      expect(backend.stats.offscreenGroupPasses, 1);
    });
  });

  testWidgets('single-paint groups with a seeded backdrop keep Canvas',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final scene = await PdfRetainedScene.fromCommands(page, [
        const PdfBeginGroupCommand(
          0.8,
          backdropColor: PdfColor(0.2, 0.3, 0.4),
        ),
        PdfFillPathCommand(
          _rect(70, 120, 280, 340),
          const PdfColor(0.85, 0.18, 0.3),
          PdfFillRule.nonzero,
          0.7,
        ),
        const PdfEndGroupCommand(),
      ]);
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      expect(backend.createSession(scene), isNull);
      expect(
        backend.stats.lastRejection,
        'non-identity single-paint transparency group',
      );
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

  testWidgets('disjoint fills retain a transparency group outer blend',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final scene = await PdfRetainedScene.fromCommands(page, [
        PdfFillPathCommand(
          _rect(30, 90, 310, 370),
          const PdfColor(0.45, 0.55, 0.7),
          PdfFillRule.nonzero,
          1,
        ),
        const PdfSetBlendModeCommand(PdfBlendMode.multiply),
        const PdfBeginGroupCommand(1),
        const PdfSetBlendModeCommand(PdfBlendMode.normal),
        PdfClipPathCommand(_rect(50, 110, 290, 350), PdfFillRule.nonzero),
        PdfFillPathCommand(
          _rect(70, 140, 140, 310),
          const PdfColor(0.95, 0.7, 0.2),
          PdfFillRule.nonzero,
          1,
        ),
        PdfFillPathCommand(
          _rect(210, 140, 270, 310),
          const PdfColor(0.2, 0.8, 0.85),
          PdfFillRule.nonzero,
          1,
        ),
        const PdfEndGroupCommand(),
        const PdfSetBlendModeCommand(PdfBlendMode.normal),
      ]);
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);

      const region = Rect.fromLTWH(20, 410, 310, 310);
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

  testWidgets('disjoint group paints retain distinct clips', (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final scene = await PdfRetainedScene.fromCommands(page, [
        PdfFillPathCommand(
          _rect(20, 80, 380, 260),
          const PdfColor(0.35, 0.65, 0.85),
          PdfFillRule.nonzero,
          1,
        ),
        const PdfSetBlendModeCommand(PdfBlendMode.multiply),
        const PdfBeginGroupCommand(1),
        const PdfSetBlendModeCommand(PdfBlendMode.normal),
        const PdfSaveCommand(),
        PdfClipPathCommand(_rect(40, 100, 170, 240), PdfFillRule.nonzero),
        PdfFillPathCommand(
          _rect(30, 90, 180, 250),
          const PdfColor(0.9, 0.3, 0.2),
          PdfFillRule.nonzero,
          0.8,
        ),
        const PdfRestoreCommand(),
        const PdfSaveCommand(),
        PdfClipPathCommand(_rect(220, 100, 350, 240), PdfFillRule.nonzero),
        PdfFillPathCommand(
          _rect(210, 90, 360, 250),
          const PdfColor(0.25, 0.85, 0.35),
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
      expect(difference / a.length, lessThan(2));
      expect(backend.stats.lastTileRoute, 'flutter_gpu');
    });
  });

  testWidgets('nested identity groups retain distinct paint clips',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final scene = await PdfRetainedScene.fromCommands(page, [
        PdfFillPathCommand(
          _rect(20, 80, 380, 300),
          const PdfColor(0.35, 0.65, 0.85),
          PdfFillRule.nonzero,
          1,
        ),
        const PdfSetBlendModeCommand(PdfBlendMode.multiply),
        const PdfBeginGroupCommand(
          0.68,
          isolated: true,
          bounds: PdfRect(35, 95, 365, 285),
        ),
        const PdfSetBlendModeCommand(PdfBlendMode.normal),
        PdfFillPathCommand(
          _rect(45, 105, 355, 275),
          const PdfColor(0.86, 0.72, 0.22),
          PdfFillRule.nonzero,
          0.75,
        ),
        const PdfBeginGroupCommand(1),
        const PdfSaveCommand(),
        PdfClipPathCommand(_rect(55, 115, 190, 260), PdfFillRule.nonzero),
        PdfFillPathCommand(
          _rect(40, 100, 205, 275),
          const PdfColor(0.92, 0.2, 0.3),
          PdfFillRule.nonzero,
          0.8,
        ),
        const PdfRestoreCommand(),
        const PdfSaveCommand(),
        PdfClipPathCommand(_rect(210, 115, 345, 260), PdfFillRule.nonzero),
        PdfFillPathCommand(
          _rect(195, 100, 360, 275),
          const PdfColor(0.15, 0.82, 0.38),
          PdfFillRule.nonzero,
          0.7,
        ),
        const PdfRestoreCommand(),
        const PdfEndGroupCommand(),
        const PdfBeginGroupCommand(1, isolated: true),
        const PdfSaveCommand(),
        PdfClipPathCommand(_rect(105, 125, 235, 245), PdfFillRule.nonzero),
        PdfFillPathCommand(
          _rect(90, 110, 250, 260),
          const PdfColor(0.72, 0.18, 0.82),
          PdfFillRule.nonzero,
          0.55,
        ),
        const PdfRestoreCommand(),
        const PdfBeginGroupCommand(1),
        PdfClipPathCommand(_rect(165, 145, 300, 255), PdfFillRule.nonzero),
        PdfFillPathCommand(
          _rect(150, 130, 315, 270),
          const PdfColor(0.15, 0.78, 0.88),
          PdfFillRule.nonzero,
          0.6,
        ),
        const PdfEndGroupCommand(),
        const PdfEndGroupCommand(),
        PdfStrokePathCommand(
          _rect(80, 130, 320, 250),
          const PdfColor(0.18, 0.3, 0.92),
          const PdfStroke(width: 9, join: 1),
          0.85,
        ),
        const PdfEndGroupCommand(),
        const PdfSetBlendModeCommand(PdfBlendMode.normal),
      ]);
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);

      const region = Rect.fromLTWH(10, 390, 380, 330);
      final expected = await scene.rasterizeRegion(region, pixelRatio: 1.25);
      final actual = await session.rasterizeRegion(region, pixelRatio: 1.25);
      addTearDown(expected.dispose);
      addTearDown(actual.dispose);
      final a = await _pixels(expected), b = await _pixels(actual);
      var difference = 0;
      for (var i = 0; i < a.length; i++) {
        difference += (a[i] - b[i]).abs();
      }
      expect(difference / a.length, lessThan(4));
      expect(backend.stats.offscreenGroupPasses, 1);
    });
  });

  testWidgets('isolated overlapping paints composite through an offscreen tile',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final scene = await PdfRetainedScene.fromCommands(page, [
        PdfFillPathCommand(
          _rect(30, 90, 310, 370),
          const PdfColor(0.45, 0.55, 0.7),
          PdfFillRule.nonzero,
          1,
        ),
        const PdfSetBlendModeCommand(PdfBlendMode.multiply),
        const PdfBeginGroupCommand(
          0.62,
          isolated: true,
          bounds: PdfRect(50, 110, 290, 350),
        ),
        const PdfSetBlendModeCommand(PdfBlendMode.normal),
        PdfClipPathCommand(_rect(50, 110, 290, 350), PdfFillRule.nonzero),
        PdfFillPathCommand(
          _rect(70, 140, 230, 310),
          const PdfColor(0.95, 0.7, 0.2),
          PdfFillRule.nonzero,
          0.8,
        ),
        PdfStrokePathCommand(
          _rect(150, 160, 270, 325),
          const PdfColor(0.2, 0.8, 0.85),
          const PdfStroke(width: 12, join: 1),
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

      const region = Rect.fromLTWH(20, 410, 310, 310);
      final expected = await scene.rasterizeRegion(region, pixelRatio: 1.5);
      final actual = await session.rasterizeRegion(region, pixelRatio: 1.5);
      addTearDown(expected.dispose);
      addTearDown(actual.dispose);
      final a = await _pixels(expected), b = await _pixels(actual);
      var difference = 0;
      for (var i = 0; i < a.length; i++) {
        difference += (a[i] - b[i]).abs();
      }
      expect(difference / a.length, lessThan(4));
      expect(backend.stats.offscreenGroupPasses, 1);
      expect(backend.stats.offscreenGroupAllocatedBytes, greaterThan(0));
      expect(
        backend.stats.peakOffscreenGroupBytes,
        backend.stats.offscreenGroupAllocatedBytes,
      );
    });
  });

  testWidgets('isolated text and path composite through an offscreen tile',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final scene = await PdfRetainedScene.fromCommands(page, [
        PdfFillPathCommand(
          _rect(30, 90, 310, 370),
          const PdfColor(0.45, 0.55, 0.7),
          PdfFillRule.nonzero,
          1,
        ),
        const PdfSetBlendModeCommand(PdfBlendMode.multiply),
        const PdfBeginGroupCommand(
          0.62,
          isolated: true,
          bounds: PdfRect(50, 110, 290, 350),
        ),
        const PdfSetBlendModeCommand(PdfBlendMode.normal),
        PdfClipPathCommand(_rect(50, 110, 290, 350), PdfFillRule.nonzero),
        PdfFillPathCommand(
          _rect(70, 140, 230, 310),
          const PdfColor(0.95, 0.7, 0.2),
          PdfFillRule.nonzero,
          0.8,
        ),
        _outlinedText(
          transform: const PdfMatrix(155, 0, 0, 155, 125, 150),
          color: const PdfColor(0.2, 0.8, 0.85),
          alpha: 0.75,
        ),
        const PdfEndGroupCommand(),
        const PdfSetBlendModeCommand(PdfBlendMode.normal),
      ]);
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);

      const region = Rect.fromLTWH(20, 410, 310, 310);
      final expected = await scene.rasterizeRegion(region, pixelRatio: 1.5);
      final actual = await session.rasterizeRegion(region, pixelRatio: 1.5);
      addTearDown(expected.dispose);
      addTearDown(actual.dispose);
      final a = await _pixels(expected), b = await _pixels(actual);
      var difference = 0;
      for (var i = 0; i < a.length; i++) {
        difference += (a[i] - b[i]).abs();
      }
      expect(difference / a.length, lessThan(4));
      expect(backend.stats.offscreenGroupPasses, 1);
    });
  });

  testWidgets('isolated image and path composite through an offscreen tile',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final scene = await PdfRetainedScene.fromCommands(
        page,
        [
          PdfFillPathCommand(
            _rect(30, 90, 310, 370),
            const PdfColor(0.45, 0.55, 0.7),
            PdfFillRule.nonzero,
            1,
          ),
          const PdfSetBlendModeCommand(PdfBlendMode.multiply),
          const PdfBeginGroupCommand(
            0.62,
            isolated: true,
            bounds: PdfRect(50, 110, 290, 350),
          ),
          const PdfSetBlendModeCommand(PdfBlendMode.normal),
          PdfClipPathCommand(_rect(50, 110, 290, 350), PdfFillRule.nonzero),
          PdfFillPathCommand(
            _rect(70, 140, 230, 310),
            const PdfColor(0.95, 0.7, 0.2),
            PdfFillRule.nonzero,
            0.8,
          ),
          _decodedImage(
            Uint8List.fromList(const [
              220,
              35,
              40,
              255,
              25,
              180,
              215,
              255,
              45,
              90,
              225,
              255,
              235,
              195,
              30,
              255,
            ]),
            const PdfMatrix(155, 0, 0, 155, 125, 150),
            'mixed-group-image',
          ),
          const PdfEndGroupCommand(),
          const PdfSetBlendModeCommand(PdfBlendMode.normal),
        ],
        retainDecodedPixels: true,
      );
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);

      const region = Rect.fromLTWH(20, 410, 310, 310);
      final expected = await scene.rasterizeRegion(region, pixelRatio: 1.5);
      final actual = await session.rasterizeRegion(region, pixelRatio: 1.5);
      addTearDown(expected.dispose);
      addTearDown(actual.dispose);
      final a = await _pixels(expected), b = await _pixels(actual);
      var difference = 0;
      for (var i = 0; i < a.length; i++) {
        difference += (a[i] - b[i]).abs();
      }
      expect(difference / a.length, lessThan(4));
      expect(backend.stats.offscreenGroupPasses, 1);
    });
  });

  testWidgets('offscreen groups preserve fixed-function blends per paint',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final scene = await PdfRetainedScene.fromCommands(
        page,
        [
          PdfFillPathCommand(
            _rect(30, 90, 310, 370),
            const PdfColor(0.45, 0.55, 0.7),
            PdfFillRule.nonzero,
            1,
          ),
          const PdfSetBlendModeCommand(PdfBlendMode.multiply),
          const PdfBeginGroupCommand(
            0.72,
            isolated: true,
            bounds: PdfRect(50, 110, 290, 350),
          ),
          const PdfSetBlendModeCommand(PdfBlendMode.normal),
          PdfClipPathCommand(_rect(50, 110, 290, 350), PdfFillRule.nonzero),
          PdfFillPathCommand(
            _rect(70, 140, 230, 310),
            const PdfColor(0.95, 0.7, 0.2),
            PdfFillRule.nonzero,
            0.8,
          ),
          const PdfSetBlendModeCommand(PdfBlendMode.multiply),
          _outlinedText(
            transform: const PdfMatrix(155, 0, 0, 155, 125, 150),
            color: const PdfColor(0.2, 0.8, 0.85),
            alpha: 0.75,
          ),
          const PdfSetBlendModeCommand(PdfBlendMode.screen),
          _decodedImage(
            Uint8List.fromList(const [
              220,
              35,
              40,
              255,
              25,
              180,
              215,
              255,
              45,
              90,
              225,
              255,
              235,
              195,
              30,
              255,
            ]),
            const PdfMatrix(90, 0, 0, 90, 175, 185),
            'blended-group-image',
          ),
          const PdfEndGroupCommand(),
          const PdfSetBlendModeCommand(PdfBlendMode.normal),
        ],
        retainDecodedPixels: true,
      );
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);

      const region = Rect.fromLTWH(20, 410, 310, 310);
      final expected = await scene.rasterizeRegion(region, pixelRatio: 1.5);
      final actual = await session.rasterizeRegion(region, pixelRatio: 1.5);
      addTearDown(expected.dispose);
      addTearDown(actual.dispose);
      final a = await _pixels(expected), b = await _pixels(actual);
      var difference = 0;
      for (var i = 0; i < a.length; i++) {
        difference += (a[i] - b[i]).abs();
      }
      expect(difference / a.length, lessThan(4));
      expect(backend.stats.offscreenGroupPasses, 1);
    });
  });

  testWidgets('offscreen groups retain gradient and mesh paints',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final scene = await PdfRetainedScene.fromCommands(page, [
        PdfFillPathCommand(
          _rect(30, 90, 310, 370),
          const PdfColor(0.45, 0.55, 0.7),
          PdfFillRule.nonzero,
          1,
        ),
        const PdfSetBlendModeCommand(PdfBlendMode.multiply),
        const PdfBeginGroupCommand(
          0.72,
          isolated: true,
          bounds: PdfRect(50, 110, 290, 350),
        ),
        const PdfSetBlendModeCommand(PdfBlendMode.normal),
        PdfClipPathCommand(_rect(50, 110, 290, 350), PdfFillRule.nonzero),
        PdfFillPathGradientCommand(
          _rect(70, 140, 240, 310),
          PdfFillRule.nonzero,
          const PdfGradient(
            isRadial: false,
            coords: [70, 140, 240, 310],
            colors: [
              PdfColor(0.95, 0.2, 0.1),
              PdfColor(0.1, 0.8, 0.9),
            ],
            stops: [0, 1],
            transform: PdfMatrix.identity,
          ),
          0.8,
        ),
        const PdfSetBlendModeCommand(PdfBlendMode.screen),
        const PdfFillMeshCommand(
          PdfMesh(
            [
              PdfMeshVertex(125, 150, PdfColor(0.9, 0.1, 0.2)),
              PdfMeshVertex(275, 170, PdfColor(0.1, 0.9, 0.25)),
              PdfMeshVertex(205, 325, PdfColor(0.15, 0.25, 0.95)),
            ],
            [0, 1, 2],
          ),
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

      const region = Rect.fromLTWH(20, 410, 310, 310);
      final expected = await scene.rasterizeRegion(region, pixelRatio: 1.5);
      final actual = await session.rasterizeRegion(region, pixelRatio: 1.5);
      addTearDown(expected.dispose);
      addTearDown(actual.dispose);
      final a = await _pixels(expected), b = await _pixels(actual);
      var difference = 0;
      for (var i = 0; i < a.length; i++) {
        difference += (a[i] - b[i]).abs();
      }
      expect(difference / a.length, lessThan(4));
      expect(backend.stats.offscreenGroupPasses, 1);
    });
  });

  testWidgets('isolated knockout fills replace earlier overlapping shapes',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final scene = await PdfRetainedScene.fromCommands(page, [
        PdfFillPathCommand(
          _rect(30, 90, 310, 370),
          const PdfColor(0.45, 0.55, 0.7),
          PdfFillRule.nonzero,
          1,
        ),
        const PdfSetBlendModeCommand(PdfBlendMode.multiply),
        const PdfBeginGroupCommand(
          0.72,
          isolated: true,
          knockout: true,
          bounds: PdfRect(50, 110, 290, 350),
        ),
        const PdfSetBlendModeCommand(PdfBlendMode.normal),
        PdfClipPathCommand(_rect(50, 110, 290, 350), PdfFillRule.nonzero),
        PdfFillPathCommand(
          _rect(70, 140, 230, 310),
          const PdfColor(0.95, 0.25, 0.15),
          PdfFillRule.nonzero,
          0.65,
        ),
        PdfFillPathCommand(
          _rect(150, 160, 270, 325),
          const PdfColor(0.15, 0.45, 0.95),
          PdfFillRule.nonzero,
          0.55,
        ),
        const PdfEndGroupCommand(),
        const PdfSetBlendModeCommand(PdfBlendMode.normal),
      ]);
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);

      const region = Rect.fromLTWH(20, 410, 310, 310);
      final expected = await scene.rasterizeRegion(region, pixelRatio: 1.5);
      final actual = await session.rasterizeRegion(region, pixelRatio: 1.5);
      addTearDown(expected.dispose);
      addTearDown(actual.dispose);
      final a = await _pixels(expected), b = await _pixels(actual);
      var difference = 0;
      for (var index = 0; index < a.length; index++) {
        difference += (a[index] - b[index]).abs();
      }
      expect(difference / a.length, lessThan(4));
      expect(backend.stats.offscreenGroupPasses, 1);
    });
  });

  testWidgets('opaque knockout groups retain a uniform seeded backdrop',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      const backdrop = PdfColor(0.24, 0.58, 0.72);
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final scene = await PdfRetainedScene.fromCommands(page, [
        PdfFillPathCommand(
          _rect(40, 100, 340, 370),
          backdrop,
          PdfFillRule.nonzero,
          1,
        ),
        const PdfBeginGroupCommand(
          1,
          knockout: true,
          bounds: PdfRect(60, 120, 320, 350),
          backdropColor: backdrop,
        ),
        PdfClipPathCommand(_rect(60, 120, 320, 350), PdfFillRule.nonzero),
        PdfFillPathCommand(
          _rect(75, 140, 235, 320),
          const PdfColor(0.95, 0.25, 0.15),
          PdfFillRule.nonzero,
          1,
        ),
        PdfFillPathCommand(
          _rect(150, 160, 300, 335),
          const PdfColor(0.15, 0.42, 0.95),
          PdfFillRule.nonzero,
          1,
        ),
        PdfStrokePathCommand(
          _rect(115, 180, 275, 305),
          const PdfColor(0.2, 0.85, 0.38),
          const PdfStroke(width: 10),
          1,
        ),
        const PdfEndGroupCommand(),
      ]);
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);

      const region = Rect.fromLTWH(30, 390, 330, 330);
      final expected = await scene.rasterizeRegion(region, pixelRatio: 1.25);
      final actual = await session.rasterizeRegion(region, pixelRatio: 1.25);
      addTearDown(expected.dispose);
      addTearDown(actual.dispose);
      final a = await _pixels(expected), b = await _pixels(actual);
      var difference = 0;
      for (var index = 0; index < a.length; index++) {
        difference += (a[index] - b[index]).abs();
      }
      expect(difference / a.length, lessThan(4));
      expect(backend.stats.offscreenGroupPasses, 1);
    });
  });

  testWidgets('isolated knockout groups retain a vector-soft-masked fill',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final scene = await PdfRetainedScene.fromCommands(page, [
        const PdfBeginGroupCommand(
          0.78,
          isolated: true,
          knockout: true,
          bounds: PdfRect(40, 90, 300, 360),
        ),
        PdfClipPathCommand(_rect(40, 90, 300, 360), PdfFillRule.nonzero),
        PdfFillPathCommand(
          _rect(60, 120, 220, 310),
          const PdfColor(0.9, 0.25, 0.15),
          PdfFillRule.nonzero,
          1,
        ),
        const PdfBeginSoftMaskedCommand(),
        PdfFillPathCommand(
          _rect(140, 140, 280, 330),
          const PdfColor(0.15, 0.45, 0.9),
          PdfFillRule.nonzero,
          0.85,
        ),
        PdfEndSoftMaskedCommand(
          luminosity: true,
          backdrop: page.cropBox,
          maskCommands: [
            PdfClipPathCommand(
              _rect(40, 90, 300, 360),
              PdfFillRule.nonzero,
            ),
            PdfFillPathCommand(
              _rect(170, 170, 260, 300),
              const PdfColor(1, 1, 1),
              PdfFillRule.nonzero,
              1,
            ),
          ],
        ),
        const PdfEndGroupCommand(),
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
      for (var index = 0; index < a.length; index++) {
        difference += (a[index] - b[index]).abs();
      }
      expect(difference / a.length, lessThan(4));
      expect(backend.stats.offscreenGroupPasses, 1);
    });
  });

  testWidgets('single-sample group targets preserve diagonal edge coverage',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      PdfPath triangle(
        double ax,
        double ay,
        double bx,
        double by,
        double cx,
        double cy,
      ) =>
          PdfPath([
            PdfMoveTo(ax, ay),
            PdfLineTo(bx, by),
            PdfLineTo(cx, cy),
            const PdfClosePath(),
          ]);

      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final scene = await PdfRetainedScene.fromCommands(page, [
        PdfFillPathCommand(
          _rect(35, 95, 365, 365),
          const PdfColor(0.28, 0.44, 0.66),
          PdfFillRule.nonzero,
          1,
        ),
        const PdfSetBlendModeCommand(PdfBlendMode.multiply),
        const PdfBeginGroupCommand(
          0.72,
          isolated: true,
          bounds: PdfRect(55, 115, 345, 345),
        ),
        const PdfSetBlendModeCommand(PdfBlendMode.normal),
        PdfFillPathCommand(
          triangle(63.3, 126.7, 332.4, 159.6, 118.8, 337.2),
          const PdfColor(0.94, 0.24, 0.34),
          PdfFillRule.nonzero,
          0.82,
        ),
        PdfFillPathCommand(
          triangle(79.6, 311.4, 301.7, 121.8, 339.2, 329.5),
          const PdfColor(0.2, 0.82, 0.42),
          PdfFillRule.nonzero,
          0.68,
        ),
        const PdfEndGroupCommand(),
        const PdfSetBlendModeCommand(PdfBlendMode.normal),
      ]);
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);

      const region = Rect.fromLTWH(30, 390, 340, 340);
      final expected = await scene.rasterizeRegion(region, pixelRatio: 1.25);
      final actual = await session.rasterizeRegion(region, pixelRatio: 1.25);
      addTearDown(expected.dispose);
      addTearDown(actual.dispose);
      final a = await _pixels(expected), b = await _pixels(actual);
      var difference = 0;
      var changedPixels = 0;
      for (var pixel = 0; pixel < a.length; pixel += 4) {
        var pixelDifference = 0;
        for (var channel = 0; channel < 4; channel++) {
          final delta = (a[pixel + channel] - b[pixel + channel]).abs();
          difference += delta;
          if (delta > pixelDifference) pixelDifference = delta;
        }
        if (pixelDifference > 16) changedPixels++;
      }
      expect(difference / a.length, lessThan(4));
      expect(changedPixels / (a.length / 4), lessThan(0.02));
      expect(backend.stats.offscreenGroupPasses, 1);
    });
  });

  testWidgets('offscreen group budget rejects before submitting group passes',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final commands = <PdfRenderCommand>[];
      for (var index = 0; index < 129; index++) {
        commands.addAll([
          const PdfBeginGroupCommand(
            0.8,
            isolated: true,
            bounds: PdfRect(0, 0, 612, 792),
          ),
          PdfFillPathCommand(
            _rect(0, 0, 612, 792),
            const PdfColor(0.8, 0.2, 0.1),
            PdfFillRule.nonzero,
            1,
          ),
          PdfFillPathCommand(
            _rect(0, 0, 612, 792),
            const PdfColor(0.1, 0.3, 0.8),
            PdfFillRule.nonzero,
            1,
          ),
          const PdfEndGroupCommand(),
        ]);
      }
      final scene = await PdfRetainedScene.fromCommands(page, commands);
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);

      await expectLater(
        session.rasterizeRegion(
          const Rect.fromLTWH(0, 0, 512, 512),
          pixelRatio: 1,
        ),
        throwsA(isA<StateError>()),
      );
      expect(backend.stats.offscreenGroupBudgetFallbacks, 1);
      expect(backend.stats.offscreenGroupPasses, 0);
      expect(backend.stats.offscreenGroupAllocatedBytes, 0);
    });
  });

  testWidgets('overlapping fills keep non-normal groups on Canvas',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final scene = await PdfRetainedScene.fromCommands(page, [
        const PdfSetBlendModeCommand(PdfBlendMode.multiply),
        const PdfBeginGroupCommand(1),
        const PdfSetBlendModeCommand(PdfBlendMode.normal),
        PdfFillPathCommand(
          _rect(70, 140, 220, 310),
          const PdfColor(0.95, 0.7, 0.2),
          PdfFillRule.nonzero,
          1,
        ),
        PdfFillPathCommand(
          _rect(150, 140, 270, 310),
          const PdfColor(0.2, 0.8, 0.85),
          PdfFillRule.nonzero,
          1,
        ),
        const PdfEndGroupCommand(),
      ]);
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      expect(backend.createSession(scene), isNull);
      expect(
        backend.stats.lastRejection,
        'non-identity multi-paint transparency group',
      );
    });
  });

  testWidgets('zero-alpha and degenerate groups are exact no-ops',
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
          const PdfColor(0.2, 0.65, 0.8),
          PdfFillRule.nonzero,
          1,
        ),
        const PdfBeginGroupCommand(
          1,
          isolated: true,
          bounds: PdfRect(170, 100, 170, 360),
        ),
        const PdfSetBlendModeCommand(PdfBlendMode.overlay),
        PdfFillPathCommand(
          _rect(70, 130, 270, 330),
          const PdfColor(0.95, 0.15, 0.35),
          PdfFillRule.nonzero,
          1,
        ),
        const PdfBeginGroupCommand(0.5, knockout: true),
        PdfStrokePathCommand(
          _rect(80, 140, 260, 320),
          const PdfColor(0.2, 0.9, 0.25),
          const PdfStroke(width: 8),
          1,
        ),
        const PdfEndGroupCommand(),
        const PdfEndGroupCommand(),
        const PdfBeginGroupCommand(
          0,
          isolated: false,
          bounds: PdfRect(60, 120, 280, 340),
        ),
        const PdfSetBlendModeCommand(PdfBlendMode.colorBurn),
        PdfFillPathCommand(
          _rect(70, 130, 270, 330),
          const PdfColor(0.9, 0.25, 0.1),
          PdfFillRule.nonzero,
          1,
        ),
        const PdfEndGroupCommand(),
      ]);
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);

      const region = Rect.fromLTWH(30, 420, 290, 290);
      final expected = await scene.rasterizeRegion(region, pixelRatio: 1.5);
      final actual = await session.rasterizeRegion(region, pixelRatio: 1.5);
      addTearDown(expected.dispose);
      addTearDown(actual.dispose);
      final a = await _pixels(expected), b = await _pixels(actual);
      var difference = 0;
      for (var i = 0; i < a.length; i++) {
        difference += (a[i] - b[i]).abs();
      }
      expect(difference / a.length, lessThan(2));
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
            maskCommands: [
              const PdfSaveCommand(),
              mask,
              const PdfSetBlendModeCommand(PdfBlendMode.multiply),
              const PdfRestoreCommand(),
            ],
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

  testWidgets('positive-width strokes use an image soft mask directly',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      PdfDrawImageCommand mask(String id) => _decodedImage(
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
            const PdfMatrix(220, 0, 0, 220, 40, 90),
            id,
          );
      const path = PdfPath([
        PdfMoveTo(60, 120),
        PdfLineTo(225, 170),
        PdfLineTo(75, 285),
      ]);
      final maskedStroke = mask('stroke-mask');
      final scene = await PdfRetainedScene.fromCommands(
        page,
        [
          const PdfBeginSoftMaskedCommand(),
          const PdfClipPathCommand(
            PdfPath([
              PdfMoveTo(50, 100),
              PdfLineTo(250, 100),
              PdfLineTo(250, 300),
              PdfLineTo(50, 300),
              PdfClosePath(),
            ]),
            PdfFillRule.nonzero,
          ),
          const PdfStrokePathCommand(
            path,
            PdfColor(0.12, 0.38, 0.84),
            PdfStroke(
              width: 18,
              cap: 1,
              join: 1,
              dashArray: [32, 13],
              dashPhase: 5,
            ),
            0.8,
          ),
          PdfEndSoftMaskedCommand(
            luminosity: true,
            backdrop: page.cropBox,
            maskCommands: [maskedStroke],
            backdropLuminance: 0.15,
            transferScale: 0.8,
            transferOffset: 0.05,
          ),
        ],
        retainDecodedPixels: true,
      );
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);
      const region = Rect.fromLTWH(30, 80, 240, 240);
      final expected = await scene.rasterizeRegion(region, pixelRatio: 1.5);
      final actual = await session.rasterizeRegion(region, pixelRatio: 1.5);
      addTearDown(expected.dispose);
      addTearDown(actual.dispose);
      final a = await _pixels(expected), b = await _pixels(actual);
      var difference = 0;
      for (var index = 0; index < a.length; index++) {
        difference += (a[index] - b[index]).abs();
      }
      expect(difference / a.length, lessThan(8));
      expect(backend.stats.texturesUploaded, 1);
      expect(backend.stats.textureDirectUploads, 1);
      expect(maskedStroke.request.decoded, isNull);

      final hairlineMask = mask('hairline-mask');
      final hairlineScene = await PdfRetainedScene.fromCommands(
        page,
        [
          const PdfBeginSoftMaskedCommand(),
          const PdfStrokePathCommand(
            path,
            PdfColor(0, 0, 0),
            PdfStroke(width: 0),
            1,
          ),
          PdfEndSoftMaskedCommand(
            luminosity: false,
            backdrop: page.cropBox,
            maskCommands: [hairlineMask],
          ),
        ],
        retainDecodedPixels: true,
      );
      addTearDown(hairlineScene.dispose);
      final hairlineBackend = FlutterGpuTileRasterBackend();
      expect(hairlineBackend.createSession(hairlineScene), isNull);
      expect(
        hairlineBackend.lastSessionRejection,
        'image soft-mask hairline requires Canvas fallback',
      );
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

  testWidgets('opaque vector masks flatten nested image-masked fills',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      PdfDrawImageCommand maskImage(String key) => _decodedImage(
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
            const PdfMatrix(180, 0, 0, 180, 60, 100),
            key,
          );

      final mask = maskImage('nested-vector-mask');
      final scene = await PdfRetainedScene.fromCommands(
        page,
        [
          PdfFillPathCommand(
            _rect(20, 60, 300, 360),
            const PdfColor(0.2, 0.45, 0.85),
            PdfFillRule.nonzero,
            1,
          ),
          const PdfBeginSoftMaskedCommand(),
          PdfClipPathCommand(
            _rect(60, 100, 240, 280),
            PdfFillRule.nonzero,
          ),
          PdfFillPathCommand(
            _rect(60, 100, 240, 280),
            const PdfColor(0.95, 0.75, 0.15),
            PdfFillRule.nonzero,
            1,
          ),
          const PdfSetBlendModeCommand(PdfBlendMode.multiply),
          const PdfBeginSoftMaskedCommand(),
          PdfFillPathCommand(
            _rect(50, 90, 250, 290),
            const PdfColor(0.25, 0.7, 0.4),
            PdfFillRule.nonzero,
            0.75,
          ),
          PdfEndSoftMaskedCommand(
            luminosity: true,
            backdrop: page.cropBox,
            maskCommands: [mask],
          ),
          const PdfSetBlendModeCommand(PdfBlendMode.normal),
          PdfEndSoftMaskedCommand(
            luminosity: true,
            backdrop: page.cropBox,
            maskCommands: [
              PdfFillPathCommand(
                _rect(60, 100, 240, 280),
                const PdfColor(1, 1, 1),
                PdfFillRule.nonzero,
                1,
              ),
            ],
          ),
          PdfFillPathCommand(
            _rect(260, 120, 290, 260),
            const PdfColor(0.9, 0.3, 0.2),
            PdfFillRule.nonzero,
            0.8,
          ),
        ],
        retainDecodedPixels: true,
      );
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);
      const region = Rect.fromLTWH(20, 410, 280, 300);
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
      expect(backend.stats.lastTileRoute, 'flutter_gpu');
      expect(backend.stats.texturesUploaded, 1);

      final partial = await PdfRetainedScene.fromCommands(page, [
        const PdfBeginSoftMaskedCommand(),
        PdfFillPathCommand(
          _rect(60, 100, 240, 280),
          const PdfColor(0.95, 0.75, 0.15),
          PdfFillRule.nonzero,
          0.9,
        ),
        const PdfBeginSoftMaskedCommand(),
        PdfFillPathCommand(
          _rect(50, 90, 250, 290),
          const PdfColor(0.25, 0.7, 0.4),
          PdfFillRule.nonzero,
          0.75,
        ),
        PdfEndSoftMaskedCommand(
          luminosity: true,
          backdrop: page.cropBox,
          maskCommands: [maskImage('unsafe-nested-vector-mask')],
        ),
        PdfEndSoftMaskedCommand(
          luminosity: true,
          backdrop: page.cropBox,
          maskCommands: [
            PdfFillPathCommand(
              _rect(60, 100, 240, 280),
              const PdfColor(1, 1, 1),
              PdfFillRule.nonzero,
              1,
            ),
          ],
        ),
      ]);
      addTearDown(partial.dispose);
      final conservative = FlutterGpuTileRasterBackend();
      expect(conservative.createSession(partial), isNull);
      expect(conservative.stats.lastRejection, contains('multiple'));
    });
  });

  testWidgets('axial gradient soft masks tint retained vector fills',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      const maskGradient = PdfGradient(
        isRadial: false,
        coords: [0, 0, 1, 0],
        colors: [PdfColor(0, 0, 0), PdfColor(1, 1, 1)],
        stops: [0, 1],
        transform: PdfMatrix(180, 0, 0, 180, 60, 100),
      );
      final scene = await PdfRetainedScene.fromCommands(page, [
        const PdfBeginSoftMaskedCommand(),
        PdfFillPathCommand(
          _rect(60, 100, 240, 280),
          const PdfColor(0.85, 0.2, 0.45),
          PdfFillRule.nonzero,
          0.8,
        ),
        PdfEndSoftMaskedCommand(
          luminosity: true,
          backdrop: page.cropBox,
          maskCommands: [
            PdfFillPathGradientCommand(
              _rect(50, 90, 250, 290),
              PdfFillRule.nonzero,
              maskGradient,
              1,
            ),
          ],
        ),
      ]);
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);
      const region = Rect.fromLTWH(40, 490, 220, 220);
      final expected = await scene.rasterizeRegion(region, pixelRatio: 1.25);
      final actual = await session.rasterizeRegion(region, pixelRatio: 1.25);
      addTearDown(expected.dispose);
      addTearDown(actual.dispose);
      final a = await _pixels(expected), b = await _pixels(actual);
      var difference = 0;
      for (var i = 0; i < a.length; i++) {
        difference += (a[i] - b[i]).abs();
      }
      expect(difference / a.length, lessThan(6));
      expect(backend.stats.lastTileRoute, 'flutter_gpu');
      expect(backend.stats.texturesUploaded, 0);
    });
  });

  testWidgets('single soft-masked groups retain their layer alpha exactly',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      const maskGradient = PdfGradient(
        isRadial: false,
        coords: [0, 0, 1, 0],
        colors: [PdfColor(0.05, 0.05, 0.05), PdfColor(1, 1, 1)],
        stops: [0, 1],
        transform: PdfMatrix(210, 0, 0, 210, 45, 85),
      );
      final scene = await PdfRetainedScene.fromCommands(page, [
        PdfBeginGroupCommand(
          0.42,
          knockout: false,
          isolated: false,
          bounds: const PdfRect(40, 80, 260, 310),
        ),
        const PdfSaveCommand(),
        PdfClipPathCommand(
          _rect(50, 90, 250, 300),
          PdfFillRule.nonzero,
        ),
        const PdfBeginSoftMaskedCommand(),
        const PdfSetOverprintCommand(fill: false, stroke: false, mode: 1),
        PdfFillPathCommand(
          _rect(35, 75, 265, 315),
          const PdfColor(0.82, 0.24, 0.48),
          PdfFillRule.nonzero,
          0.8,
        ),
        PdfEndSoftMaskedCommand(
          luminosity: true,
          backdrop: page.cropBox,
          maskCommands: [
            PdfFillPathGradientCommand(
              _rect(30, 70, 270, 320),
              PdfFillRule.nonzero,
              maskGradient,
              1,
            ),
          ],
        ),
        const PdfSetOverprintCommand(fill: false, stroke: false, mode: 1),
        const PdfRestoreCommand(),
        const PdfEndGroupCommand(),
      ]);
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);
      const region = Rect.fromLTWH(30, 460, 250, 270);
      final expected = await scene.rasterizeRegion(region, pixelRatio: 1.25);
      final actual = await session.rasterizeRegion(region, pixelRatio: 1.25);
      addTearDown(expected.dispose);
      addTearDown(actual.dispose);
      final a = await _pixels(expected), b = await _pixels(actual);
      var difference = 0;
      for (var index = 0; index < a.length; index++) {
        difference += (a[index] - b[index]).abs();
      }
      expect(difference / a.length, lessThan(6));
      expect(backend.stats.lastTileRoute, 'flutter_gpu');
      expect(backend.stats.offscreenGroupPasses, 1,
          reason: 'the group alpha applies after the masked source resolves');

      final unsafe = await PdfRetainedScene.fromCommands(page, [
        PdfBeginGroupCommand(
          0.42,
          knockout: false,
          isolated: false,
          bounds: const PdfRect(40, 80, 260, 310),
        ),
        const PdfSetBlendModeCommand(PdfBlendMode.multiply),
        const PdfBeginSoftMaskedCommand(),
        PdfFillPathCommand(
          _rect(50, 90, 250, 300),
          const PdfColor(0.82, 0.24, 0.48),
          PdfFillRule.nonzero,
          0.8,
        ),
        PdfEndSoftMaskedCommand(
          luminosity: true,
          backdrop: page.cropBox,
          maskCommands: [
            PdfFillPathGradientCommand(
              _rect(30, 70, 270, 320),
              PdfFillRule.nonzero,
              maskGradient,
              1,
            ),
          ],
        ),
        const PdfEndGroupCommand(),
      ]);
      addTearDown(unsafe.dispose);
      final conservative = FlutterGpuTileRasterBackend();
      expect(conservative.createSession(unsafe), isNull);
      expect(
        conservative.lastSessionRejection,
        contains('soft-mask group contains'),
      );

      final overprint = await PdfRetainedScene.fromCommands(page, [
        PdfBeginGroupCommand(
          0.42,
          knockout: false,
          isolated: false,
          bounds: const PdfRect(40, 80, 260, 310),
        ),
        const PdfBeginSoftMaskedCommand(),
        const PdfSetOverprintCommand(fill: true, stroke: true, mode: 1),
        PdfFillPathCommand(
          _rect(50, 90, 250, 300),
          const PdfColor(0.82, 0.24, 0.48),
          PdfFillRule.nonzero,
          0.8,
        ),
        PdfEndSoftMaskedCommand(
          luminosity: true,
          backdrop: page.cropBox,
          maskCommands: [
            PdfFillPathGradientCommand(
              _rect(30, 70, 270, 320),
              PdfFillRule.nonzero,
              maskGradient,
              1,
            ),
          ],
        ),
        const PdfEndGroupCommand(),
      ]);
      addTearDown(overprint.dispose);
      final overprintBackend = FlutterGpuTileRasterBackend();
      expect(overprintBackend.createSession(overprint), isNull);
      expect(
        overprintBackend.lastSessionRejection,
        contains('soft-mask group contains'),
      );
    });
  });

  testWidgets('axial gradient soft masks tint retained vector strokes',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      const maskGradient = PdfGradient(
        isRadial: false,
        coords: [0, 0, 1, 0],
        colors: [PdfColor(0, 0, 0), PdfColor(1, 1, 1)],
        stops: [0, 1],
        transform: PdfMatrix(220, 0, 0, 220, 40, 80),
      );
      final scene = await PdfRetainedScene.fromCommands(page, [
        const PdfBeginSoftMaskedCommand(),
        const PdfStrokePathCommand(
          PdfPath([
            PdfMoveTo(60, 110),
            PdfLineTo(235, 175),
            PdfLineTo(70, 280),
          ]),
          PdfColor(0.18, 0.62, 0.85),
          PdfStroke(
            width: 16,
            cap: 1,
            join: 1,
            dashArray: [27, 11],
            dashPhase: 4,
          ),
          0.75,
        ),
        PdfEndSoftMaskedCommand(
          luminosity: true,
          backdrop: page.cropBox,
          maskCommands: [
            PdfFillPathGradientCommand(
              _rect(35, 75, 265, 305),
              PdfFillRule.nonzero,
              maskGradient,
              0.9,
            ),
          ],
        ),
      ]);
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);
      const region = Rect.fromLTWH(25, 470, 250, 250);
      final expected = await scene.rasterizeRegion(region, pixelRatio: 1.25);
      final actual = await session.rasterizeRegion(region, pixelRatio: 1.25);
      addTearDown(expected.dispose);
      addTearDown(actual.dispose);
      final a = await _pixels(expected), b = await _pixels(actual);
      var difference = 0;
      for (var index = 0; index < a.length; index++) {
        difference += (a[index] - b[index]).abs();
      }
      expect(difference / a.length, lessThan(6));
      expect(backend.stats.lastTileRoute, 'flutter_gpu');
      expect(backend.stats.texturesUploaded, 0);
    });
  });

  testWidgets('image and axial masks retain outlined text', (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final imageMask = _decodedImage(
        Uint8List.fromList([
          0,
          0,
          0,
          255,
          255,
          255,
          255,
          255,
          255,
          255,
          255,
          255,
          0,
          0,
          0,
          255,
        ]),
        const PdfMatrix(612, 0, 0, 792, 0, 0),
        'outlined-text-mask',
      );
      const gradient = PdfGradient(
        isRadial: false,
        coords: [0, 0, 1, 0],
        colors: [PdfColor(0, 0, 0), PdfColor(1, 1, 1)],
        stops: [0, 1],
        transform: PdfMatrix(612, 0, 0, 792, 0, 0),
      );
      final scene = await PdfRetainedScene.fromCommands(
          page,
          [
            const PdfBeginSoftMaskedCommand(),
            _outlinedText(
              transform: const PdfMatrix(120, 0, 0, 120, 70, 100),
              color: const PdfColor(0.1, 0.55, 0.9),
            ),
            PdfEndSoftMaskedCommand(
              luminosity: true,
              backdrop: page.cropBox,
              maskCommands: [imageMask],
            ),
            const PdfBeginSoftMaskedCommand(),
            _outlinedText(
              transform: const PdfMatrix(120, 0, 0, 120, 300, 100),
              color: const PdfColor(0.9, 0.2, 0.45),
            ),
            PdfEndSoftMaskedCommand(
              luminosity: true,
              backdrop: page.cropBox,
              maskCommands: [
                PdfFillPathGradientCommand(
                  _rect(0, 0, 612, 792),
                  PdfFillRule.nonzero,
                  gradient,
                  1,
                ),
              ],
            ),
          ],
          retainDecodedPixels: true);
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);
      const region = Rect.fromLTWH(50, 550, 500, 170);
      final expected = await scene.rasterizeRegion(region, pixelRatio: 1.5);
      final actual = await session.rasterizeRegion(region, pixelRatio: 1.5);
      addTearDown(expected.dispose);
      addTearDown(actual.dispose);
      final a = await _pixels(expected), b = await _pixels(actual);
      var difference = 0;
      for (var i = 0; i < a.length; i++) {
        difference += (a[i] - b[i]).abs();
      }
      expect(difference / a.length, lessThan(6));
      expect(backend.stats.texturesUploaded, 1);

      final stroked = await PdfRetainedScene.fromCommands(
          page,
          [
            const PdfBeginSoftMaskedCommand(),
            _outlinedText(
              transform: const PdfMatrix(120, 0, 0, 120, 70, 100),
              color: const PdfColor(0.1, 0.55, 0.9),
              strokeColor: const PdfColor(0, 0, 0),
              strokeWidth: 5,
            ),
            PdfEndSoftMaskedCommand(
              luminosity: true,
              backdrop: page.cropBox,
              maskCommands: [imageMask],
            ),
          ],
          retainDecodedPixels: true);
      addTearDown(stroked.dispose);
      final strokeBackend = FlutterGpuTileRasterBackend();
      final strokeSession = strokeBackend.createSession(stroked);
      expect(strokeSession, isNotNull,
          reason: strokeBackend.stats.lastRejection);
      addTearDown(strokeSession!.dispose);
      final strokeExpected =
          await stroked.rasterizeRegion(region, pixelRatio: 1.5);
      final strokeActual =
          await strokeSession.rasterizeRegion(region, pixelRatio: 1.5);
      addTearDown(strokeExpected.dispose);
      addTearDown(strokeActual.dispose);
      final strokeA = await _pixels(strokeExpected);
      final strokeB = await _pixels(strokeActual);
      var strokeDifference = 0;
      for (var i = 0; i < strokeA.length; i++) {
        strokeDifference += (strokeA[i] - strokeB[i]).abs();
      }
      expect(strokeDifference / strokeA.length, lessThan(6));
    });
  });

  testWidgets('matched text masks flatten one nested image-masked fill',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      PdfDrawImageCommand maskImage(String key) => _decodedImage(
            Uint8List.fromList([
              0,
              0,
              0,
              255,
              255,
              255,
              255,
              255,
              255,
              255,
              255,
              255,
              0,
              0,
              0,
              255,
            ]),
            const PdfMatrix(180, 0, 0, 180, 80, 100),
            key,
          );
      const textTransform = PdfMatrix(180, 0, 0, 180, 80, 100);
      List<PdfRenderCommand> commands(
              PdfMatrix outerMaskTransform, String key) =>
          [
            const PdfBeginSoftMaskedCommand(),
            _outlinedText(
              transform: textTransform,
              color: const PdfColor(0.95, 0.75, 0.1),
            ),
            const PdfSetBlendModeCommand(PdfBlendMode.multiply),
            const PdfBeginSoftMaskedCommand(),
            PdfFillPathCommand(
              _rect(60, 80, 280, 320),
              const PdfColor(0.15, 0.15, 0.15),
              PdfFillRule.nonzero,
              0.7,
            ),
            PdfEndSoftMaskedCommand(
              luminosity: true,
              backdrop: page.cropBox,
              maskCommands: [maskImage(key)],
            ),
            const PdfSetBlendModeCommand(PdfBlendMode.normal),
            PdfEndSoftMaskedCommand(
              luminosity: true,
              backdrop: page.cropBox,
              maskCommands: [
                _outlinedText(
                  transform: outerMaskTransform,
                  color: const PdfColor(1, 1, 1),
                ),
              ],
            ),
          ];
      final scene = await PdfRetainedScene.fromCommands(
        page,
        commands(textTransform, 'nested-text-mask'),
        retainDecodedPixels: true,
      );
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);
      const region = Rect.fromLTWH(50, 450, 260, 280);
      final expected = await scene.rasterizeRegion(region, pixelRatio: 1.25);
      final actual = await session.rasterizeRegion(region, pixelRatio: 1.25);
      addTearDown(expected.dispose);
      addTearDown(actual.dispose);
      final a = await _pixels(expected), b = await _pixels(actual);
      var difference = 0;
      for (var i = 0; i < a.length; i++) {
        difference += (a[i] - b[i]).abs();
      }
      // The retained stencil intersects coverage per MSAA sample; Canvas
      // resolves the source layer before applying the identical mask. Their
      // edge pixels differ slightly, while the continuous PDF geometry and
      // every fully covered sample are identical.
      expect(difference / a.length, lessThan(12));

      final unmatched = await PdfRetainedScene.fromCommands(
        page,
        commands(
          const PdfMatrix(180, 0, 0, 180, 84, 100),
          'unmatched-text-mask',
        ),
        retainDecodedPixels: true,
      );
      addTearDown(unmatched.dispose);
      final conservative = FlutterGpuTileRasterBackend();
      expect(conservative.createSession(unmatched), isNull);
      expect(conservative.stats.lastRejection, contains('multiple paints'));
    });
  });

  testWidgets('matched path masks retain nested fills and reject mismatches',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final shape = PdfPath([
        const PdfMoveTo(80, 100),
        const PdfLineTo(180, 300),
        const PdfLineTo(280, 100),
        const PdfLineTo(220, 160),
        const PdfLineTo(140, 160),
        const PdfClosePath(),
      ]);
      final shifted = PdfPath([
        const PdfMoveTo(84, 100),
        const PdfLineTo(184, 300),
        const PdfLineTo(284, 100),
        const PdfLineTo(224, 160),
        const PdfLineTo(144, 160),
        const PdfClosePath(),
      ]);
      PdfDrawImageCommand maskImage(String key) => _decodedImage(
            Uint8List.fromList([
              0,
              0,
              0,
              255,
              255,
              255,
              255,
              255,
              255,
              255,
              255,
              255,
              0,
              0,
              0,
              255,
            ]),
            const PdfMatrix(220, 0, 0, 220, 70, 90),
            key,
          );
      List<PdfRenderCommand> commands(PdfPath maskPath, String key) => [
            const PdfBeginSoftMaskedCommand(),
            PdfFillPathCommand(
              shape,
              const PdfColor(0.2, 0.65, 0.9),
              PdfFillRule.nonzero,
              1,
            ),
            const PdfSetBlendModeCommand(PdfBlendMode.screen),
            const PdfBeginSoftMaskedCommand(),
            PdfFillPathCommand(
              _rect(60, 80, 300, 320),
              const PdfColor(0.9, 0.3, 0.15),
              PdfFillRule.nonzero,
              0.8,
            ),
            PdfEndSoftMaskedCommand(
              luminosity: true,
              backdrop: page.cropBox,
              maskCommands: [maskImage(key)],
            ),
            const PdfSetBlendModeCommand(PdfBlendMode.normal),
            PdfEndSoftMaskedCommand(
              luminosity: true,
              backdrop: page.cropBox,
              maskCommands: [
                const PdfSetOverprintCommand(
                  fill: true,
                  stroke: false,
                  mode: 1,
                ),
                PdfFillPathCommand(
                  maskPath,
                  const PdfColor(1, 1, 1),
                  PdfFillRule.nonzero,
                  1,
                ),
              ],
            ),
          ];
      final scene = await PdfRetainedScene.fromCommands(
        page,
        commands(shape, 'matched-path-mask'),
        retainDecodedPixels: true,
      );
      addTearDown(scene.dispose);
      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);
      const region = Rect.fromLTWH(50, 450, 260, 280);
      final expected = await scene.rasterizeRegion(region, pixelRatio: 1.25);
      final actual = await session.rasterizeRegion(region, pixelRatio: 1.25);
      addTearDown(expected.dispose);
      addTearDown(actual.dispose);
      final a = await _pixels(expected), b = await _pixels(actual);
      var difference = 0;
      for (var i = 0; i < a.length; i++) {
        difference += (a[i] - b[i]).abs();
      }
      // Same per-sample stencil-vs-intermediate-resolution edge difference as
      // the matched text-mask case above.
      expect(difference / a.length, lessThan(12));

      final unmatched = await PdfRetainedScene.fromCommands(
        page,
        commands(shifted, 'unmatched-path-mask'),
        retainDecodedPixels: true,
      );
      addTearDown(unmatched.dispose);
      final conservative = FlutterGpuTileRasterBackend();
      expect(conservative.createSession(unmatched), isNull);
      expect(conservative.stats.lastRejection, contains('multiple paints'));
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

      final face = FlutterGpuTrueTypeFontFace(buildTestTrueTypeFont());
      final outliner = FlutterGpuTrueTypeTextOutliner((_) => face);
      const substituteRun = PdfTextRun(
        text: 'AB',
        transform: PdfMatrix(80, 0, 0, 80, 80, 180),
        color: PdfColor(0.1, 0.2, 0.7),
        width: 1.6,
        fontName: 'Helvetica',
        fontSize: 80,
        charOffsets: [0, 0.6, 1.6],
      );
      final substituteScene = await PdfRetainedScene.fromCommands(page, const [
        PdfDrawTextCommand(substituteRun),
      ]);
      addTearDown(substituteScene.dispose);
      final throwingBackend = FlutterGpuTileRasterBackend(
        textOutliner: FlutterGpuTrueTypeTextOutliner(
          (_) => throw StateError('broken host resolver'),
        ),
      );
      expect(throwingBackend.createSession(substituteScene), isNull);
      expect(
        throwingBackend.stats.lastRejection,
        'unsupported text: missing glyph outlines',
      );
      final outlinedRun = outliner.outline(substituteRun)!;
      final outlineControl = await PdfRetainedScene.fromCommands(page, [
        PdfDrawTextCommand(outlinedRun),
      ]);
      addTearDown(outlineControl.dispose);
      final outlineBackend = FlutterGpuTileRasterBackend(
        textOutliner: outliner,
      );
      final outlineSession = outlineBackend.createSession(substituteScene);
      expect(outlineSession, isNotNull,
          reason: outlineBackend.lastSessionRejection);
      addTearDown(outlineSession!.dispose);
      const textRegion = Rect.fromLTWH(60, 560, 180, 160);
      final textExpected =
          await outlineControl.rasterizeRegion(textRegion, pixelRatio: 1);
      final textActual = await outlineSession.rasterizeRegion(
        textRegion,
        pixelRatio: 1,
      );
      addTearDown(textExpected.dispose);
      addTearDown(textActual.dispose);
      final expectedPixels = await _pixels(textExpected);
      final actualPixels = await _pixels(textActual);
      var textDifference = 0;
      for (var i = 0; i < expectedPixels.length; i++) {
        textDifference += (expectedPixels[i] - actualPixels[i]).abs();
      }
      expect(textDifference / expectedPixels.length, lessThan(8));
      expect(outlineBackend.stats.analyticTextRuns, 1);
      expect(outlineBackend.stats.analyticGlyphQuads, 2);
      expect(outlineBackend.stats.analyticGlyphSlots, 2);
      expect(outlineBackend.stats.analyticAtlasBytes, greaterThan(0));
      expect(outlineBackend.stats.analyticTextFallbackRuns, 0);

      final flattenedBackend = FlutterGpuTileRasterBackend(
        textOutliner: outliner,
        analyticText: false,
      );
      final flattenedSession = flattenedBackend.createSession(substituteScene);
      expect(flattenedSession, isNotNull,
          reason: flattenedBackend.lastSessionRejection);
      addTearDown(flattenedSession!.dispose);
      final flattened = await flattenedSession.rasterizeRegion(
        textRegion,
        pixelRatio: 1,
      );
      addTearDown(flattened.dispose);
      expect(
        outlineBackend.stats.geometryVertices,
        lessThan(flattenedBackend.stats.geometryVertices),
        reason: 'retained glyph quads must replace outline stencil fans',
      );

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

  testWidgets('failed image decodes are exact no-ops, not progressive gaps',
      (tester) async {
    await tester.runAsync(() async {
      if (!_gpuAvailable()) {
        markTestSkipped('run with --enable-impeller --enable-flutter-gpu');
        return;
      }
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final request = PdfImageRequest(
        stream: CosStream(
          CosDictionary({
            'Subtype': const CosName('Image'),
            'Width': const CosInteger(2),
            'Height': const CosInteger(2),
            'BitsPerComponent': const CosInteger(8),
            'ColorSpace': const CosName('DeviceRGB'),
            'Filter': const CosName('UnsupportedDecode'),
          }),
          Uint8List.fromList([1, 2, 3]),
        ),
        transform: const PdfMatrix(140, 0, 0, 140, 50, 50),
      );
      final command = PdfDrawImageCommand(request);
      final scene = await PdfRetainedScene.fromCommands(
        page,
        [command],
        retainDecodedPixels: true,
      );
      addTearDown(scene.dispose);
      expect(scene.imageDecodingAttempted, isTrue);
      expect(scene.imageFor(request), isNull);

      final backend = FlutterGpuTileRasterBackend();
      final session = backend.createSession(scene);
      expect(session, isNotNull, reason: backend.stats.lastRejection);
      addTearDown(session!.dispose);
      const region = Rect.fromLTWH(0, 0, 240, 240);
      final expected = await scene.rasterizeRegion(region, pixelRatio: 1);
      final actual = await session.rasterizeRegion(region, pixelRatio: 1);
      addTearDown(expected.dispose);
      addTearDown(actual.dispose);
      expect(await _pixels(actual), await _pixels(expected));

      final progressive = await PdfRetainedScene.fromCommands(
        page,
        [command],
        includeImages: false,
      );
      addTearDown(progressive.dispose);
      expect(progressive.imageDecodingAttempted, isFalse);
      final conservative = FlutterGpuTileRasterBackend();
      expect(conservative.createSession(progressive), isNull);
      expect(conservative.stats.lastRejection, 'missing image pixels');
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
