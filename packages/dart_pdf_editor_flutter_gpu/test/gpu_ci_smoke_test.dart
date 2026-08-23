import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor_flutter_gpu/dart_pdf_editor_flutter_gpu.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

Future<Uint8List> _pixels(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

void main() {
  testWidgets('CI renders an accepted tile through flutter_gpu',
      (tester) async {
    await tester.runAsync(() async {
      try {
        gpu.gpuContext.defaultColorFormat;
      } catch (error) {
        fail('This smoke job requires a real flutter_gpu context: $error');
      }

      final scene = await PdfRetainedScene.record(
        PdfDocument.open(buildEmbeddedFontImagePdf()).page(0),
      );
      try {
        final backend = FlutterGpuTileRasterBackend();
        final session = backend.createSession(scene);
        expect(session, isNotNull, reason: backend.stats.lastRejection);
        try {
          const region = Rect.fromLTWH(40, 50, 330, 190);
          final canvas = await scene.rasterizeRegion(region, pixelRatio: 2);
          final accelerated =
              await session!.rasterizeRegion(region, pixelRatio: 2);
          try {
            expect(accelerated.width, canvas.width);
            expect(accelerated.height, canvas.height);
            final expected = await _pixels(canvas);
            final actual = await _pixels(accelerated);
            var difference = 0;
            for (var i = 0; i < expected.length; i++) {
              difference += (expected[i] - actual[i]).abs();
            }
            expect(difference / expected.length, lessThan(12),
                reason: 'the designated GPU fixture must agree with Canvas');
          } finally {
            canvas.dispose();
            accelerated.dispose();
          }

          expect(backend.stats.contextsSeen, greaterThan(0));
          expect(backend.stats.sessionsCreated, 1);
          expect(backend.stats.tilesRendered, 1);
          expect(backend.stats.rasterFallbacks, 0);
          expect(backend.stats.completedSubmissions, 1);
          expect(backend.stats.lastTileRoute, 'flutter_gpu');
        } finally {
          session?.dispose();
        }
      } finally {
        scene.dispose();
      }
    });
  }, timeout: const Timeout(Duration(minutes: 2)));
}
