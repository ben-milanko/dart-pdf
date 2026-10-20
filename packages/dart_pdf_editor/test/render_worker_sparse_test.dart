import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

import 'fixtures/sparse_worker_pdf.dart';

List<PdfRenderCommand> _record(PdfDocument document, int index) {
  final page = document.page(index);
  final device = RecordingPdfDevice();
  PdfInterpreter(cos: document.cos, device: device)
    ..drawPageContent(page, page.contentBytes())
    ..drawAnnotations(page);
  return device.commands;
}

Future<void> _expectSparse(PdfRenderWorker worker, PdfDocument local,
    {int priority = 0}) async {
  final commands = await worker.record(0, priority: priority);
  expect(commands, isNotNull);
  expect(commands!.whereType<PdfStrokePathCommand>().length,
      _record(local, 0).whereType<PdfStrokePathCommand>().length,
      reason: 'the unfetched annotation appearance must stay missing');
  final text = await worker.extractText(1, priority: priority);
  expect(text, isNotNull);
  expect(text!.text, isEmpty,
      reason: 'unfetched page content must not be extracted');
  expect((await worker.extractText(2, priority: priority))!.text,
      contains('Page 3'),
      reason: 'populated neighbours still resolve');
}

void main() {
  for (final mode in ['uncached', 'cached', 'single', 'pool', 'shared pool']) {
    testWidgets('$mode worker carries inherited holes across the byte copy',
        (tester) async {
      await tester.runAsync(() async {
        final fixture = sparseWorkerPdf();
        final whole = PdfDocument.open(Uint8List.fromList(fixture.bytes));
        final local =
            PdfDocument.open(fixture.bytes, populatedRanges: fixture.ranges);
        expect(_record(whole, 0).length, greaterThan(_record(local, 0).length));
        expect(PdfTextExtractor.extract(whole, 1).text, isNotEmpty);
        final worker = switch (mode) {
          'uncached' => PdfRenderWorker.startUncached(fixture.bytes),
          'cached' => PdfRenderWorker.start(fixture.bytes),
          'single' =>
            startPdfRenderWorker(fixture.bytes, pageCount: 3, workerCount: 1),
          _ =>
            PdfPooledRenderWorker(fixture.bytes, 2, copySource: mode == 'pool'),
        };
        addTearDown(worker.dispose);
        await _expectSparse(worker, local);
        if (worker is PdfPooledRenderWorker) {
          await _expectSparse(worker, local, priority: -2000);
        }
      });
    });
  }

  for (final pooled in [false, true]) {
    testWidgets('explicit holes survive edit, undo, redo (pooled=$pooled)',
        (tester) async {
      await tester.runAsync(() async {
        final fixture = sparseWorkerPdf();
        final worker = pooled
            ? PdfPooledRenderWorker(fixture.bytes, 2,
                populatedRanges: fixture.ranges)
            : PdfRenderWorker.startUncached(fixture.bytes,
                populatedRanges: fixture.ranges);
        addTearDown(worker.dispose);
        final local = PdfDocument.open(Uint8List.fromList(fixture.bytes),
            populatedRanges: fixture.ranges);
        await _expectSparse(worker, local);
        final edited = (PdfEditor(local)
              ..addSquare(0, const PdfRect(150, 20, 250, 120)))
            .save();
        local.applyIncrementalUpdate(edited);
        final append = Uint8List.sublistView(edited, fixture.bytes.length);
        worker.updateRevision(fixture.bytes.length, append, edited.length, {0});
        await _expectSparse(worker, local);
        if (pooled) await _expectSparse(worker, local, priority: -2000);

        // Undo forces a full reopen; redo extends the sparse map again.
        worker.updateRevision(
            fixture.bytes.length, Uint8List(0), fixture.bytes.length, {0});
        final original = PdfDocument.open(Uint8List.fromList(fixture.bytes),
            populatedRanges: fixture.ranges);
        await _expectSparse(worker, original);
        if (pooled) await _expectSparse(worker, original, priority: -2000);
        worker.updateRevision(fixture.bytes.length, append, edited.length, {0});
        await _expectSparse(worker, local);
        if (pooled) await _expectSparse(worker, local, priority: -2000);
      });
    });
  }

  testWidgets('overprint retry inherits the document map after an edit',
      (tester) async {
    await tester.runAsync(() async {
      final fixture = sparseWorkerPdf();
      final document =
          PdfDocument.open(fixture.bytes, populatedRanges: fixture.ranges);
      final edited = (PdfEditor(document)
            ..addSquare(0, const PdfRect(150, 20, 250, 120)))
          .save();
      document.applyIncrementalUpdate(edited);
      final source = await PdfRetainedScene.record(document.page(0));
      addTearDown(source.dispose);
      final retry = await source.rerecordWithOverprintMaxDimension(768)!;
      addTearDown(retry.dispose);
      expect(retry.commands.length, source.commands.length);
      expect(retry.commands.length, _record(document, 0).length);
    });
  });

  test('range snapshots cannot mutate a document or an earlier revision', () {
    final fixture = sparseWorkerPdf();
    final document =
        PdfDocument.open(fixture.bytes, populatedRanges: fixture.ranges);
    final before = document.cos.populatedRanges!;
    expect(() => before.clear(), throwsUnsupportedError);
    fixture.ranges.clear();
    expect(document.cos.populatedRanges, before);
    final edited = (PdfEditor(document)
          ..addSquare(0, const PdfRect(150, 20, 250, 120)))
        .save();
    document.applyIncrementalUpdate(edited);
    expect(document.cos.populatedRanges!.last, edited.length);
    expect(before.last, fixture.bytes.length);
    expect(CosDocument.open(fixture.bytes).populatedRanges, before);
    expect(PdfDocument.open(edited).cos.populatedRanges,
        document.cos.populatedRanges);
    final copy = PdfDocument.open(Uint8List.fromList(edited),
        populatedRanges: document.cos.populatedRanges);
    expect(PdfTextExtractor.extract(copy, 1).text, isEmpty);
  });
}
