import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/render_worker_text_cache.dart';
import 'package:dart_pdf_editor/src/render_worker_transcript_cache.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

// Browser integration uses the same real bundle as render_worker_sparse_web_test:
// dart run dart_pdf_editor:build_web_worker --out lib/src/sparse_test_worker.js
void main() {
  test('complete transcript retains exact page text before annotations',
      () async {
    final doc = PdfDocument.open(_pdf());
    final cache = PdfWorkerTranscriptCache();
    final transcript =
        await cache.transcriptFor(doc, 0, true, PdfCancellationToken());
    expect(transcript, isNotNull);
    expect(
        transcript!.wireCommands
            .whereType<PdfDrawTextCommand>()
            .any((c) => c.run.text.contains('Annotation only')),
        isTrue);
    final text = cache.textCache.extract(0);
    expect(text, isNotNull);
    expect(cache.textCache.hits, 1,
        reason: 'the complete recording must populate the text cache');
    _expectSame(text!, PdfTextExtractor.extract(doc, 0));
    expect(text.text, contains('OCR text'));
    expect(text.text, isNot(contains('Annotation only')));
    expect(text.runs.any((r) => r.mcid == 3), isTrue);

    cache.evictPages({1});
    expect(cache.textCache.extract(0), isNotNull);
    cache.evictPages({0});
    expect(cache.textCache.extract(0), isNull);
    await cache.transcriptFor(doc, 0, false, PdfCancellationToken());
    expect(cache.textCache.extract(0), isNotNull);
    cache.clear();
    expect(cache.textCache.length, 0);
  });

  test('preempted partial text is published only after a resumed full walk',
      () async {
    final doc = PdfDocument.open(_pdf(lines: 1000));
    final cache = PdfWorkerTranscriptCache(resumeChunkOperations: 32);
    final token = PdfCancellationToken();
    var partials = 0;
    await expectLater(
      cache.transcriptFor(doc, 0, true, token, onPartial: (_) {
        partials++;
        token.cancelled = true;
      }),
      throwsA(isA<PdfCancelledException>()),
    );
    expect(partials, greaterThan(0));
    expect(cache.textCache.extract(0), isNull);
    await cache.transcriptFor(doc, 0, true, PdfCancellationToken());
    _expectSame(cache.textCache.extract(0)!, PdfTextExtractor.extract(doc, 0));
  });

  test('text cache bounds metadata and entries, with strict oversize rejection',
      () {
    final doc = PdfDocument.open(_pdf());
    final recorder = RecordingPdfDevice();
    PdfInterpreter(cos: doc.cos, device: recorder, collectCharOffsets: true)
        .drawPage(doc.page(0));
    final bytes = PdfRecordedText.capture(recorder.commands).estimatedBytes;
    expect(bytes, greaterThan(0));
    final cache = PdfWorkerTextCache(maxBytes: bytes * 2, maxPages: 2);
    cache.record(0, recorder.commands);
    cache.record(1, recorder.commands);
    expect(cache.extract(0), isNotNull); // Page 1 is least recently used.
    cache.record(2, recorder.commands);
    expect(cache.extract(1), isNull);
    expect(cache.extract(0), isNotNull);
    expect(cache.extract(2), isNotNull);
    expect(cache.retainedBytes, lessThanOrEqualTo(bytes * 2));
    cache.evictPages(null);
    expect(cache.retainedBytes, 0);
    final tiny = PdfWorkerTextCache(maxBytes: bytes - 1);
    tiny.record(0, recorder.commands);
    expect(tiny.length, 0);
    expect(tiny.retainedBytes, 0);
  });

  for (final path in ['full', 'vector', 'progressive', 'prefix', 'index']) {
    testWidgets('real worker preserves text after $path recording',
        (tester) async {
      await tester.runAsync(() async {
        final oldUrl = pdfRenderWorkerScriptUrl;
        if (kIsWeb) {
          pdfRenderWorkerScriptUrl = '${Uri.base.origin}'
              '/packages/dart_pdf_editor/src/sparse_test_worker.js';
        }
        addTearDown(() => pdfRenderWorkerScriptUrl = oldUrl);
        final bytes = _pdf(lines: path == 'prefix' ? 1000 : 0);
        final worker = PdfRenderWorker.startUncached(bytes);
        addTearDown(worker.dispose);
        if (path == 'index') {
          expect(
              await worker.buildRegionIndex(0,
                  annotations: true, maxCommands: 10000, buildGrid: true),
              isNotNull);
        } else {
          expect(
              await worker.record(0,
                  decodeImages: path == 'full',
                  commandLimit: path == 'prefix' ? 16 : null,
                  onPartial: path == 'progressive' ? (_) {} : null),
              isNotNull);
        }
        final text = await worker.extractText(0);
        expect(text, isNotNull);
        _expectSame(
            text!, PdfTextExtractor.extract(PdfDocument.open(bytes), 0));
        expect(text.text, contains('OCR text'),
            reason: 'a bounded prefix must fall back to complete extraction');
      });
    });
  }

  testWidgets('worker text invalidates on edit and undo', (tester) async {
    await tester.runAsync(() async {
      final original = _pdf();
      final worker = PdfRenderWorker.startUncached(original);
      addTearDown(worker.dispose);
      expect(worker.supportsRevisionUpdate, isTrue);
      expect(await worker.record(0), isNotNull);
      final editor = PdfEditor(PdfDocument.open(original))
        ..stampPage(0, (stamp) => stamp.text('New content', x: 50, y: 300));
      final updated = editor.save();
      worker.updateRevision(original.length,
          Uint8List.sublistView(updated, original.length), updated.length, {0});
      final text = await worker.extractText(0);
      _expectSame(
          text!, PdfTextExtractor.extract(PdfDocument.open(updated), 0));
      expect(text.text, contains('New content'));
      expect(await worker.record(0), isNotNull);
      worker
          .updateRevision(original.length, Uint8List(0), original.length, {0});
      final undone = await worker.extractText(0);
      _expectSame(
          undone!, PdfTextExtractor.extract(PdfDocument.open(original), 0));
      expect(undone.text, isNot(contains('New content')));
    });
  }, skip: kIsWeb); // Web revisions replace the worker instead of updating it.
}

void _expectSame(PdfPageText actual, PdfPageText expected) {
  expect(serializePageText(actual), serializePageText(expected),
      reason: 'Unicode, exact advances, MCIDs and geometry must all survive');
  for (final word in ['AV', 'OCR']) {
    expect(actual.findAll(word).map((m) => m.quads.map((q) => q.corners)),
        expected.findAll(word).map((m) => m.quads.map((q) => q.corners)));
  }
  final run = expected.runs.first;
  final x = (run.bounds.left + run.bounds.right) / 2;
  final y = (run.bounds.bottom + run.bounds.top) / 2;
  expect(actual.positionNear(x, y), expected.positionNear(x, y));
}

Uint8List _pdf({int lines = 0}) {
  final builder = CosDocumentBuilder();
  final pages = CosDictionary({'Type': const CosName('Pages')});
  final pagesRef = builder.add(pages);
  final font = builder.add(CosDictionary({
    'Type': const CosName('Font'),
    'Subtype': const CosName('Type1'),
    'BaseFont': const CosName('Helvetica'),
  }));
  final content =
      StringBuffer('BT /F1 12 Tf 1 Tc 2 Tw 72 720 Td (AV fi) Tj ET\n');
  for (var i = 0; i < lines; i++) {
    content.writeln('10 10 m 20 20 l S');
  }
  content.write('/P << /MCID 3 >> BDC BT /F1 12 Tf 3 Tr 72 680 Td '
      '(OCR text) Tj ET EMC');
  final page = builder.add(CosDictionary({
    'Type': const CosName('Page'),
    'Parent': pagesRef,
    'MediaBox': CosArray([0, 0, 612, 792].map(CosInteger.new).toList()),
    'Resources': CosDictionary({
      'Font': CosDictionary({'F1': font})
    }),
    'Contents': builder.add(CosStream(
        CosDictionary(), Uint8List.fromList(content.toString().codeUnits))),
  }));
  pages['Kids'] = CosArray([page]);
  pages['Count'] = const CosInteger(1);
  final bytes = builder.build(
      root: builder.add(CosDictionary({
    'Type': const CosName('Catalog'),
    'Pages': pagesRef,
  })));
  return (PdfEditor(PdfDocument.open(bytes))
        ..addFreeText(0, const PdfRect(50, 400, 300, 450), 'Annotation only'))
      .save();
}
