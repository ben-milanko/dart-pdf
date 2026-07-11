// Corpus probe for issue #227's dense transform-time Slug path.
//
//   cd packages/dart_pdf_editor
//   SLUG_WORKER_PDF=../../corpus/ly9-far-cad.pdf \
//   SLUG_WORKER_PAGE=4 fvm flutter test test/slug_worker_latency_test.dart
//
// Reports the off-thread plan wall time, transferred plan size, residual UI
// upload/replay time, and the local-build time deliberately excluded from the
// production path. Skips when the corpus file is absent or the selected page
// is image-bearing / has no embedded-outline text.
import 'dart:io';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/strips.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';

void main() {
  final path =
      Platform.environment['SLUG_WORKER_PDF'] ?? '../../corpus/ly9-far-cad.pdf';
  final pageIndex =
      int.tryParse(Platform.environment['SLUG_WORKER_PAGE'] ?? '') ?? 4;

  testWidgets('dense Slug worker plan latency', (tester) async {
    final file = File(path);
    if (!file.existsSync()) {
      markTestSkipped('corpus file missing: $path');
      return;
    }
    await tester.runAsync(() async {
      final bytes = file.readAsBytesSync();
      final document = PdfDocument.open(bytes);
      final index = pageIndex.clamp(0, document.pageCount - 1);
      final page = document.page(index);
      final worker = PdfRenderWorker.startUncached(bytes);
      addTearDown(worker.dispose);
      final commands = await worker.record(index, decodeImages: false);
      expect(commands, isNotNull);
      final scene = await PdfRetainedScene.fromCommands(page, commands!);
      addTearDown(scene.dispose);
      if (!scene.hasSlugTextCandidates ||
          PdfPageRenderer.hasImageDraws(scene.commands)) {
        markTestSkipped('page $index is not an image-free Slug candidate');
        return;
      }

      final geometry = scene.stripGeometry(pixelRatio: 1);
      final m = geometry.pageToDevice;
      var sw = Stopwatch()..start();
      final plan = await worker.binStrips(index,
          annotations: true,
          pageToDevice: [m.a, m.b, m.c, m.d, m.e, m.f],
          deviceWidth: geometry.width,
          deviceHeight: geometry.height,
          pixelRatio: 1,
          slugGlyphs: true);
      final workerMs = sw.elapsedMicroseconds / 1000;
      expect(plan, isNotNull);

      StripPdfDevice.resetStats();
      sw = Stopwatch()..start();
      final planned = await scene.replayStrips(
          pixelRatio: 1, stripPlan: plan, slugGlyphs: true);
      final uploadMs = sw.elapsedMicroseconds / 1000;
      planned.dispose();
      expect(StripPdfDevice.totalPlanPictures, 1);

      StripPdfDevice.resetStats();
      sw = Stopwatch()..start();
      final local = await scene.replayStrips(pixelRatio: 1, slugGlyphs: true);
      final localMs = sw.elapsedMicroseconds / 1000;
      local.dispose();

      final planMb = encodeStripPlan(plan!).length / (1024 * 1024);
      // ignore: avoid_print
      print('SLUG-WORKER page=$index commands=${scene.commands.length} '
          'quads=${plan.slugQuadCount} '
          'fallbacks=${plan.slugFallbackOutlineRuns} '
          'plan=${planMb.toStringAsFixed(2)}MB '
          'worker=${workerMs.toStringAsFixed(1)}ms '
          'ui=${uploadMs.toStringAsFixed(1)}ms '
          'local=${localMs.toStringAsFixed(1)}ms');
    });
  }, timeout: const Timeout(Duration(minutes: 10)));
}
