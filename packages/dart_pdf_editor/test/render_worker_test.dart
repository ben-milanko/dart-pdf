// The background-isolate render worker: a page recorded off-thread must
// replay to pixels identical to the on-thread recorded render, image-bearing
// pages must decline (null → local render), and the worker's lifecycle
// (active, dispose, out-of-range) must behave. Runs on the Dart VM under
// flutter_test, which supports isolates; every body uses tester.runAsync so
// the isolate spawn and the GPU readback actually complete.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

Future<Uint8List> _rasterBytes(ui.Picture picture, Size size) async {
  final image = await PdfPageRenderer.rasterize(picture, size, 1);
  try {
    final data = await image.toByteData();
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

void main() {
  testWidgets('records a vector page off-thread, replays pixel-identically',
      (tester) async {
    await tester.runAsync(() async {
      final bytes = buildClassicPdf();
      final doc = PdfDocument.open(bytes);
      final page = doc.page(0);

      final worker = PdfRenderWorker.start(bytes);
      addTearDown(worker.dispose);
      expect(worker.isActive, isTrue);

      final commands = await worker.record(0);
      expect(commands, isNotNull,
          reason: 'an image-free page should serialize and offload');

      final size = PdfPageRenderer.pageSize(page);
      final workerPicture =
          PdfPageRenderer.pictureFromCommands(page, commands!);
      final localPicture = await PdfPageRenderer.renderPictureRecorded(page);
      try {
        final workerPixels = await _rasterBytes(workerPicture, size);
        final localPixels = await _rasterBytes(localPicture, size);
        expect(workerPixels, equals(localPixels),
            reason: 'replayed worker buffer must match the local render');
      } finally {
        workerPicture.dispose();
        localPicture.dispose();
      }
    });
  });

  testWidgets('an image-bearing page declines (null → local render)',
      (tester) async {
    await tester.runAsync(() async {
      final bytes = PdfImageDocument.fromImageBytes([buildTestJpeg()]);
      final worker = PdfRenderWorker.start(bytes);
      addTearDown(worker.dispose);

      final commands = await worker.record(0);
      expect(commands, isNull,
          reason: 'a page that draws an image is not serializable yet');
    });
  });

  testWidgets('out-of-range page returns null', (tester) async {
    await tester.runAsync(() async {
      final worker = PdfRenderWorker.start(buildClassicPdf());
      addTearDown(worker.dispose);
      expect(await worker.record(999), isNull);
      expect(await worker.record(-1), isNull);
    });
  });

  testWidgets('dispose stops the worker and fails further records to null',
      (tester) async {
    await tester.runAsync(() async {
      final worker = PdfRenderWorker.start(buildClassicPdf());
      // record once so the isolate is fully spawned, then tear it down
      expect(await worker.record(0), isNotNull);
      worker.dispose();
      expect(worker.isActive, isFalse);
      expect(await worker.record(0), isNull);
      worker.dispose(); // idempotent
    });
  });

  testWidgets('serves many pages over one long-lived isolate', (tester) async {
    await tester.runAsync(() async {
      final bytes = buildMultiPagePdf(3);
      final doc = PdfDocument.open(bytes);
      final worker = PdfRenderWorker.start(bytes);
      addTearDown(worker.dispose);

      for (var i = 0; i < doc.pageCount; i++) {
        final commands = await worker.record(i);
        // multi-page fixture pages are vector text, so all should offload
        expect(commands, isNotNull, reason: 'page $i should offload');
        final picture = PdfPageRenderer.pictureFromCommands(doc.page(i), commands!);
        picture.dispose();
      }
    });
  });
}
