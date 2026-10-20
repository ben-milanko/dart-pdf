// Runs on the VM and in Chrome. For Chrome, build the real worker first:
// dart run dart_pdf_editor:build_web_worker --out lib/src/sparse_test_worker.js
// flutter test --platform chrome --no-cross-origin-isolation \
//   test/compression_worker_test.dart
// Delete the generated lib/src/sparse_test_worker.js after the run.
import 'dart:async';
import 'dart:typed_data';

import 'package:dart_pdf_editor/compression_worker.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart'
    show pdfRenderWorkerScriptUrl;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';

void main() {
  late String? previousWorkerUrl;

  setUp(() {
    previousWorkerUrl = pdfRenderWorkerScriptUrl;
    if (kIsWeb) {
      pdfRenderWorkerScriptUrl = '${Uri.base.origin}'
          '/packages/dart_pdf_editor/src/sparse_test_worker.js';
    }
  });

  tearDown(() => pdfRenderWorkerScriptUrl = previousWorkerUrl);

  test('compression leaves the event loop responsive after work starts',
      () async {
    final bytes = _compressionPdf(payloadLength: 8 * 1024 * 1024);
    final original = Uint8List.fromList(bytes);
    final task = PdfCompressionTask.start(bytes,
        options: const PdfCompressionOptions(
            removeUnusedResources: false,
            subsetFonts: false,
            deduplicate: false));
    addTearDown(task.cancel);

    // Startup alone must not satisfy this assertion: only count events after
    // the worker acknowledges the compression request. A Future/compute that
    // runs the compressor on the browser thread cannot service these ticks.
    var ticksDuringCompression = 0;
    var complete = false;
    final heartbeat = Timer.periodic(const Duration(milliseconds: 1), (_) {
      if (task.hasStarted && !complete) ticksDuringCompression++;
    });
    addTearDown(heartbeat.cancel);
    final result = await task.result.whenComplete(() => complete = true);
    heartbeat.cancel();

    expect(ticksDuringCompression, greaterThanOrEqualTo(3),
        reason: 'compression must run outside the UI event loop');
    expect(result.bytesSaved, greaterThan(bytes.length ~/ 2));
    expect(PdfDocument.open(result.bytes).pageCount, 1);
    expect(bytes, original,
        reason: 'transferring work must not detach or mutate the open PDF');
  });

  test('cancellation interrupts an active job and permits a fresh job',
      () async {
    final bytes = _compressionPdf(payloadLength: 8 * 1024 * 1024);
    final original = Uint8List.fromList(bytes);
    final task = PdfCompressionTask.start(bytes);
    addTearDown(task.cancel);
    var cancelledAfterStart = false;
    final completion = expectLater(
        task.result, throwsA(isA<PdfCompressionCancelledException>()));
    final cancelWhenStarted = Timer.periodic(
      const Duration(milliseconds: 1),
      (timer) {
        if (!task.hasStarted) return;
        cancelledAfterStart = true;
        task.cancel();
        task.cancel(); // Closing a dialog twice must be harmless.
        timer.cancel();
      },
    );
    addTearDown(cancelWhenStarted.cancel);
    await completion;
    expect(cancelledAfterStart, isTrue);
    expect(bytes, original);

    final retry = PdfCompressionTask.start(_compressionPdf());
    addTearDown(retry.cancel);
    expect((await retry.result).bytesSaved, greaterThan(0));
  });

  test('cancellation before worker startup completes the result', () async {
    final task = PdfCompressionTask.start(_compressionPdf());
    final completion = expectLater(
        task.result, throwsA(isA<PdfCompressionCancelledException>()));
    task.cancel();
    task.cancel();
    await completion;
  });

  for (final options in [
    const PdfCompressionOptions(
      targetDpi: 96,
      jpegQuality: 57,
      deflateLevel: 3,
    ),
    const PdfCompressionOptions(
      recompressStreams: false,
      removeUnusedResources: false,
      deduplicate: false,
      subsetFonts: false,
      deflateLevel: 1,
    ),
  ]) {
    test(
        'options and the complete report survive the worker boundary '
        '(recompress=${options.recompressStreams})', () async {
      final bytes = _compressionPdf();
      final expected =
          PdfCompressor.optimize(PdfDocument.open(bytes), options: options);
      final task = PdfCompressionTask.start(bytes, options: options);
      addTearDown(task.cancel);
      final actual = await task.result;

      expect(actual.bytes, expected.bytes);
      expect(actual.bytesBefore, expected.bytesBefore);
      expect(actual.bytesAfter, expected.bytesAfter);
      expect(actual.objectsBefore, expected.objectsBefore);
      expect(actual.objectsAfter, expected.objectsAfter);
      expect(actual.streamsDeflated, expected.streamsDeflated);
      expect(actual.compacted, expected.compacted);
      expect(actual.resourcesRemoved, expected.resourcesRemoved);
      expect(actual.duplicatesRemoved, expected.duplicatesRemoved);
      expect(actual.fontsSubset, expected.fontsSubset);
      expect(actual.imagesRecompressed, expected.imagesRecompressed);
      expect(actual.warnings, expected.warnings);
      expect(actual.steps.map((s) => (s.kind, s.bytesBefore, s.bytesAfter)),
          expected.steps.map((s) => (s.kind, s.bytesBefore, s.bytesAfter)));
      expect(actual.bytesSaved, expected.bytesSaved);
      expect(actual.savingsFraction, expected.savingsFraction);
      expect(actual.bytesSaved,
          actual.steps.fold<int>(0, (sum, step) => sum + step.bytesSaved));
      if (options.targetDpi != null) {
        expect(actual.warnings, isNotEmpty,
            reason: 'the mask preservation warning must cross the boundary');
        expect(actual.resourcesRemoved, greaterThan(0));
        expect(actual.duplicatesRemoved, greaterThan(0));
      } else {
        expect(actual.steps.map((s) => s.kind),
            everyElement(PdfCompressionKind.structure));
        expect(actual.streamsDeflated, 0);
        expect(actual.resourcesRemoved, 0);
        expect(actual.duplicatesRemoved, 0);
        expect(actual.fontsSubset, 0);
      }
    });
  }

  test('worker errors complete the result instead of leaving it pending',
      () async {
    final task = PdfCompressionTask.start(_compressionPdf(),
        options: const PdfCompressionOptions(jpegQuality: 0));
    addTearDown(task.cancel);
    await expectLater(
        task.result,
        throwsA(predicate<Object>(
            (error) => error.toString().contains('jpegQuality'))));
  });

  for (final missingScript in [null, '/missing-compression-worker.js']) {
    test(
        'an unavailable browser worker fails without main-thread fallback '
        '($missingScript)', () async {
      pdfRenderWorkerScriptUrl =
          missingScript == null ? null : '${Uri.base.origin}$missingScript';
      final bytes = _compressionPdf();
      final original = Uint8List.fromList(bytes);
      final task = PdfCompressionTask.start(bytes);
      addTearDown(task.cancel);

      await expectLater(task.result, throwsA(isA<StateError>()));
      expect(task.hasStarted, isFalse);
      expect(bytes, original);
    }, skip: !kIsWeb);
  }
}

/// A real PDF with a large reachable stream, an unused resource, and two
/// identical masks. The stream exercises deflate without spending the test's
/// time constructing millions of drawing operators. Small versions also cover
/// resource pruning, deduplication, and image-preservation warning transport.
Uint8List _compressionPdf({int payloadLength = 32 * 1024}) {
  final builder = CosDocumentBuilder();
  final pages = CosDictionary({'Type': const CosName('Pages')});
  final pagesRef = builder.add(pages);
  CosReference mask() => builder.add(CosStream(
        CosDictionary({
          'Type': const CosName('XObject'),
          'Subtype': const CosName('Image'),
          'Width': const CosInteger(64),
          'Height': const CosInteger(64),
          'BitsPerComponent': const CosInteger(1),
          'ImageMask': const CosBoolean(true),
        }),
        Uint8List(512)..fillRange(0, 512, 0x55),
      ));
  final payload = Uint8List(payloadLength);
  for (var i = 0; i < payload.length; i++) {
    payload[i] = 32 + (i % 95);
  }
  final page = builder.add(CosDictionary({
    'Type': const CosName('Page'),
    'Parent': pagesRef,
    'MediaBox': CosArray([
      const CosInteger(0),
      const CosInteger(0),
      const CosInteger(612),
      const CosInteger(792),
    ]),
    'Resources': CosDictionary({
      'XObject': CosDictionary({
        'First': mask(),
        'Second': mask(),
        'Unused': mask(),
      }),
    }),
    'Contents': builder.add(CosStream(
        CosDictionary(),
        Uint8List.fromList(
            'q 64 0 0 64 0 0 cm /First Do /Second Do Q'.codeUnits))),
  }));
  pages['Kids'] = CosArray([page]);
  pages['Count'] = const CosInteger(1);
  return builder.build(
    root: builder.add(CosDictionary({
      'Type': const CosName('Catalog'),
      'Pages': pagesRef,
      'CompressionTestPayload':
          builder.add(CosStream(CosDictionary(), payload)),
    })),
  );
}
