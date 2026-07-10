// PdfRetainedScene correctness: a replayed scene must rasterize
// byte-identically to the shipping cached-picture zoom path at every scale -
// same commands, same decoded images, same canvas transform stack, so any
// divergence is a bug in the scene's plumbing.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

Future<ByteData> _bytes(ui.Image image) async =>
    (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;

void main() {
  testWidgets('retained-scene replay matches the cached-picture raster',
      (tester) async {
    await tester.runAsync(() async {
      final doc = PdfDocument.open(buildClassicPdf());
      final page = doc.page(0);
      const plan = PdfPageRenderPlan();
      final size = plan.pageSize(page);

      final picture =
          await PdfPageRenderer.renderPictureRecordedWithPlan(page, plan);
      final scene = await PdfRetainedScene.record(page, plan: plan);

      for (final ratio in [0.7, 1.0, 2.4]) {
        final current = await PdfPageRenderer.rasterize(picture, size, ratio);
        final retained = await scene.rasterize(pixelRatio: ratio);
        expect(retained.width, current.width, reason: 'ratio $ratio');
        expect(retained.height, current.height, reason: 'ratio $ratio');
        final a = await _bytes(current);
        final b = await _bytes(retained);
        expect(a.buffer.asUint8List(), b.buffer.asUint8List(),
            reason: 'raster mismatch at ratio $ratio');
        current.dispose();
        retained.dispose();
      }

      // Region replay mirrors rasterizeRegion.
      final region = Rect.fromLTWH(
          size.width / 4, size.height / 4, size.width / 2, size.height / 2);
      final currentRegion =
          await PdfPageRenderer.rasterizeRegion(picture, region, 3.0);
      final retainedRegion =
          await scene.rasterizeRegion(region, pixelRatio: 3.0);
      expect(retainedRegion.width, currentRegion.width);
      expect(retainedRegion.height, currentRegion.height);
      final a = await _bytes(currentRegion);
      final b = await _bytes(retainedRegion);
      expect(a.buffer.asUint8List(), b.buffer.asUint8List(),
          reason: 'region raster mismatch');
      currentRegion.dispose();
      retainedRegion.dispose();

      // Replay is synchronous and reusable: two replays from one recording.
      final p1 = scene.replay(pixelRatio: 1.0);
      final p2 = scene.replay(pixelRatio: 2.0);
      expect(scene.commands, isNotEmpty);
      p1.dispose();
      p2.dispose();

      scene.dispose();
      picture.dispose();
    });
  });
}
