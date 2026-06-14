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
import 'package:image/image.dart' as img;
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

/// The first image draw request in a recorded buffer, or null if it draws none.
PdfImageRequest? _firstImage(List<PdfRenderCommand> commands) {
  for (final c in commands) {
    if (c is PdfDrawImageCommand) return c.request;
  }
  return null;
}

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
          await PdfPageRenderer.pictureFromCommands(page, commands!);
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

  testWidgets('an image XObject page offloads and replays identically',
      (tester) async {
    await tester.runAsync(() async {
      final bytes = PdfImageDocument.fromImageBytes([buildTestJpeg()]);
      final doc = PdfDocument.open(bytes);
      final page = doc.page(0);

      final worker = PdfRenderWorker.start(bytes);
      addTearDown(worker.dispose);

      // The worker inline-resolves the image's stream subgraph and ships it;
      // the main thread reconstructs and decodes it. The result must match the
      // local recorded render pixel-for-pixel.
      final commands = await worker.record(0);
      expect(commands, isNotNull,
          reason: 'an image XObject serializes via its inlined stream');
      // A baseline JPEG needs the platform codec, so the worker can't decode
      // it off-thread: it ships un-decoded and decodes locally.
      expect(_firstImage(commands!)?.decoded, isNull,
          reason: 'a JPEG image declines the off-thread decode');

      final size = PdfPageRenderer.pageSize(page);
      final workerPicture =
          await PdfPageRenderer.pictureFromCommands(page, commands);
      final localPicture = await PdfPageRenderer.renderPictureRecorded(page);
      try {
        final workerPixels = await _rasterBytes(workerPicture, size);
        final localPixels = await _rasterBytes(localPicture, size);
        expect(workerPixels, equals(localPixels),
            reason: 'the decoded image must replay identically');
      } finally {
        workerPicture.dispose();
        localPicture.dispose();
      }
    });
  });

  testWidgets('an image with an /SMask (nested stream) replays identically',
      (tester) async {
    await tester.runAsync(() async {
      // A PNG with alpha embeds as a Flate RGB XObject plus an indirect /SMask
      // stream — so inlining must descend into and decrypt the nested stream,
      // and the decoder must rebuild the alpha. Compare worker vs local pixels.
      final bytes = PdfImageDocument.fromImageBytes([_alphaPng()]);
      final doc = PdfDocument.open(bytes);
      final page = doc.page(0);

      final worker = PdfRenderWorker.start(bytes);
      addTearDown(worker.dispose);

      final commands = await worker.record(0);
      expect(commands, isNotNull,
          reason: 'the image XObject and its /SMask serialize together');
      // A Flate RGB base under a soft mask is purely decodable, so the worker
      // decodes it off-thread and ships premultiplied pixels — the offload.
      final decoded = _firstImage(commands!)?.decoded;
      expect(decoded, isNotNull,
          reason: 'a Flate+SMask image decodes off-thread');
      expect(decoded!.rgba.length, decoded.width * decoded.height * 4);

      final size = PdfPageRenderer.pageSize(page);
      final workerPicture =
          await PdfPageRenderer.pictureFromCommands(page, commands);
      final localPicture = await PdfPageRenderer.renderPictureRecorded(page);
      try {
        final workerPixels = await _rasterBytes(workerPicture, size);
        final localPixels = await _rasterBytes(localPicture, size);
        expect(workerPixels, equals(localPixels),
            reason: 'the soft-masked image must replay identically');
      } finally {
        workerPicture.dispose();
        localPicture.dispose();
      }
    });
  });

  testWidgets('an inline image still declines (null → local render)',
      (tester) async {
    await tester.runAsync(() async {
      // A 4x4 inline image (BI .. ID .. EI) — declined because its /CS can name
      // a page-resource colour space unreachable from the stream alone.
      final bytes = _inlineImagePdf();
      final worker = PdfRenderWorker.start(bytes);
      addTearDown(worker.dispose);

      final commands = await worker.record(0);
      expect(commands, isNull,
          reason: 'an inline image is not serialized; the page renders locally');
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

  testWidgets('priority: the on-screen page preempts queued prefetch',
      (tester) async {
    await tester.runAsync(() async {
      final worker = PdfRenderWorker.start(buildMultiPagePdf(2));
      addTearDown(worker.dispose);
      await worker.record(0); // warm up: the isolate is now spawned and idle

      // Fire six prefetch records (priority 1) then one on-screen record
      // (priority 0), all synchronously — so the first prefetch is in flight
      // and the rest queue behind it. The high-priority request must be served
      // next, ahead of the five still queued: completion order is
      // [low0, HIGH, low1, ...]. Deterministic because record() enqueues
      // synchronously before any isolate response can arrive.
      final order = <String>[];
      final futures = <Future<void>>[
        for (var i = 0; i < 6; i++)
          worker.record(0, priority: 1).then((_) => order.add('low$i')),
        worker.record(1, priority: 0).then((_) => order.add('HIGH')),
      ];
      await Future.wait(futures);

      expect(order.length, 7);
      expect(order.indexOf('HIGH'), 1,
          reason: 'high priority is served right after the in-flight prefetch');
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
        final picture =
            await PdfPageRenderer.pictureFromCommands(doc.page(i), commands!);
        picture.dispose();
      }
    });
  });

  testWidgets('cancel drops a queued request without disturbing others',
      (tester) async {
    await tester.runAsync(() async {
      final worker = PdfRenderWorker.start(buildMultiPagePdf(3));
      addTearDown(worker.dispose);
      await worker.record(0); // warm up: the isolate is spawned and idle

      // record() enqueues synchronously, so these resolve deterministically:
      // page 0 goes in flight, pages 1 and 2 queue behind it.
      final inFlight = worker.record(0, priority: 1);
      final stale = worker.record(1, priority: 1);
      final wanted = worker.record(2, priority: 1);
      // Page 1 "scrolled away" before its turn — drop it from the queue.
      worker.cancel(1, priority: 1);

      expect(await stale, isNull,
          reason: 'a cancelled queued request resolves to a local render');
      expect(await inFlight, isNotNull,
          reason: 'the in-flight request is untouched and still completes');
      expect(await wanted, isNotNull,
          reason: 'an unrelated queued request still completes');
    });
  });

  testWidgets('cancel does not preempt the in-flight request', (tester) async {
    await tester.runAsync(() async {
      final worker = PdfRenderWorker.start(buildMultiPagePdf(2));
      addTearDown(worker.dispose);
      await worker.record(0); // warm up

      final inFlight = worker.record(0, priority: 1); // now in flight
      worker.cancel(0, priority: 1); // targets page 0, but it already started
      expect(await inFlight, isNotNull,
          reason: 'the single in-flight request cannot be cancelled');
    });
  });

  testWidgets('cancel only matches the given page and priority', (tester) async {
    await tester.runAsync(() async {
      final worker = PdfRenderWorker.start(buildMultiPagePdf(3));
      addTearDown(worker.dispose);
      await worker.record(0); // warm up

      final inFlight = worker.record(0, priority: 1);
      final otherPriority = worker.record(1, priority: 2);
      final target = worker.record(1, priority: 1);
      // Same page as otherPriority, but a different priority bucket: only the
      // priority-1 request for page 1 is dropped.
      worker.cancel(1, priority: 1);

      expect(await target, isNull, reason: 'the matching request is cancelled');
      expect(await inFlight, isNotNull);
      expect(await otherPriority, isNotNull,
          reason: 'a same-page request at another priority is left alone');
    });
  });
}

/// A small RGBA PNG with a varying alpha channel (so it embeds with an /SMask).
Uint8List _alphaPng() {
  final image = img.Image(width: 8, height: 8, numChannels: 4);
  for (var y = 0; y < 8; y++) {
    for (var x = 0; x < 8; x++) {
      image.setPixelRgba(x, y, x * 32, y * 32, 128, (x + y) * 16);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

/// A one-page PDF whose only content is a 4x4 inline image (BI .. ID .. EI).
Uint8List _inlineImagePdf() {
  const content = 'q 100 0 0 100 50 50 cm '
      'BI /W 4 /H 4 /CS /RGB /BPC 8 /F /AHx ID\n'
      'e63030 ffffff e63030 ffffff\n'
      'ffffff e63030 ffffff e63030\n'
      'e63030 ffffff e63030 ffffff\n'
      'ffffff e63030 ffffff e63030 >\nEI Q\n';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
  ];
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = buffer.length;
  buffer.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final o in offsets) {
    buffer.write('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer.write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
      'startxref\n$xref\n%%EOF\n');
  return Uint8List.fromList(buffer.toString().codeUnits);
}
