import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_pdf_editor_app/ocr_jobs.dart';
import 'package:dart_pdf_editor_app/ocr_job_store_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  late Directory dir;
  late FileOcrJobStorage storage;
  late OcrJobs jobs;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('dartpdf-ocr-jobs-');
    storage = FileOcrJobStorage(directory: dir);
    jobs = OcrJobs(storage);
  });
  tearDown(() => dir.delete(recursive: true));

  List<PdfOcrSpan> recognize(int page) => page == 1
      ? []
      : [
          PdfOcrSpan(
              text: 'word$page',
              bounds: const PdfRect(10, 20, 80, 40),
              confidence: .875),
        ];
  Future<Uint8List> finish(
      OcrSavedJob job, Map<int, List<PdfOcrSpan>> recognized) async {
    final editor = PdfEditor(PdfDocument.open(await jobs.source(job)));
    for (final e in recognized.entries) {
      editor.injectTextLayer(e.key, e.value);
    }
    return editor.save();
  }

  test('reopen resumes completed and empty pages without repeating OCR',
      () async {
    final source = buildMultiPagePdf(4);
    final job = await jobs.create(source, 'scan.pdf', automatic: false);
    final firstCalls = <int>[];
    await expectLater(
        jobs.run(job,
            recognize: (i) async {
              firstCalls.add(i);
              if (i == 2) throw StateError('simulated process interruption');
              return recognize(i);
            },
            finish: (r) => finish(job, r)),
        throwsStateError);
    expect(firstCalls, [0, 1, 2]);
    expect((await jobs.read(job.id))!.nextPage, 2);
    expect(await jobs.page(job.id, 1), isEmpty);

    jobs = OcrJobs(FileOcrJobStorage(directory: dir));
    final recovered = (await jobs.list()).single;
    final resumedCalls = <int>[];
    await jobs.run(recovered,
        recognize: (i) async {
          resumedCalls.add(i);
          return recognize(i);
        },
        finish: (r) => finish(recovered, r));
    expect(resumedCalls, [2, 3]);
    expect((await jobs.read(job.id))!.state, OcrJobState.complete);
    expect(await jobs.source(job), source);
    final reopened = PdfDocument.open((await jobs.result(job.id))!);
    for (final i in [0, 2, 3]) {
      final content = latin1.decode(reopened.page(i).contentBytes());
      expect('word$i'.allMatches(content), hasLength(1));
    }
    final restoredSpan = (await jobs.page(job.id, 0))!.single;
    expect(restoredSpan.bounds, const PdfRect(10, 20, 80, 40));
    expect(restoredSpan.confidence, .875);
  });

  test('a page committed before its progress cursor survives a hard kill',
      () async {
    final job =
        await jobs.create(buildMultiPagePdf(3), 'scan', automatic: true);
    await jobs.savePage(job.id, 0, recognize(0));
    await jobs.savePage(job.id, 1, []);
    // No manifest advance: simulate termination in the exact commit gap.
    final recovered =
        (await OcrJobs(FileOcrJobStorage(directory: dir)).list()).single;
    expect(recovered.nextPage, 0);
    final calls = <int>[];
    await jobs.run(recovered,
        recognize: (i) async {
          calls.add(i);
          return recognize(i);
        },
        finish: (r) => finish(recovered, r));
    expect(calls, [2]);
  });

  test('retrying the finish stage does not duplicate text layers', () async {
    final job =
        await jobs.create(buildMultiPagePdf(1), 'scan', automatic: false);
    await expectLater(
        jobs.run(job,
            recognize: (i) async => recognize(i),
            finish: (_) async =>
                throw StateError('out of space while finishing')),
        throwsStateError);
    await jobs.run((await jobs.read(job.id))!,
        recognize: (_) async => fail('completed page must not run again'),
        finish: (r) => finish(job, r));
    final result = PdfDocument.open((await jobs.result(job.id))!);
    expect('word0'.allMatches(latin1.decode(result.page(0).contentBytes())),
        hasLength(1));
  });

  test('expiry checkpoints the in-flight page and resumes on reopen', () async {
    final job =
        await jobs.create(buildMultiPagePdf(3), 'scan', automatic: false);
    var expired = false;
    await jobs.run(job,
        shouldPause: () => expired,
        recognize: (i) async {
          expired = true;
          return recognize(i);
        },
        finish: (_) async => fail('must not finish a paused job'));
    expect(job.state, OcrJobState.pending);
    expect(job.nextPage, 1);
    final calls = <int>[];
    await jobs.run(job,
        recognize: (i) async {
          calls.add(i);
          return recognize(i);
        },
        finish: (r) => finish(job, r));
    expect(calls, [1, 2]);
  });

  test('cancel is durable, produces no result, and can be explicitly discarded',
      () async {
    final job =
        await jobs.create(buildMultiPagePdf(3), 'scan', automatic: false);
    await jobs.run(job,
        recognize: (i) async {
          await jobs.cancel(job.id);
          return recognize(i);
        },
        finish: (_) async => fail('cancelled job must not finish'));
    expect((await jobs.read(job.id))!.state, OcrJobState.cancelled);
    expect(await jobs.result(job.id), isNull);
    await jobs.delete(job.id);
    expect(await jobs.list(), isEmpty);
    expect(await storage.keys(), isEmpty);
  });

  test('same snapshot and OCR mode resume, changed bytes get a separate job',
      () async {
    final bytes = buildMultiPagePdf(2);
    final a = await jobs.create(bytes, 'original', automatic: false);
    final b = await jobs.create(bytes, 'renamed', automatic: false);
    final c =
        await jobs.create(buildMultiPagePdf(3), 'different', automatic: false);
    final d = await jobs.create(bytes, 'automatic', automatic: true);
    expect(a.id, b.id);
    expect(c.id, isNot(a.id));
    expect(d.id, isNot(a.id));
  });

  test('exclusive owner is released, and damaged source cannot silently run',
      () async {
    final job =
        await jobs.create(buildMultiPagePdf(1), 'scan', automatic: false);
    final lease = await storage.claim(job.id);
    expect(lease, isNotNull);
    expect(await FileOcrJobStorage(directory: dir).claim(job.id), isNull);
    await lease!.release();
    final next = await storage.claim(job.id);
    expect(next, isNotNull);
    await next!.release();
    await storage.write('${job.id}_source', Uint8List.fromList([1, 2, 3]));
    await expectLater(jobs.source(job), throwsFormatException);
  });

  test('bad records and uncommitted temporary files do not hide valid jobs',
      () async {
    final job =
        await jobs.create(buildMultiPagePdf(1), 'scan', automatic: false);
    await storage.write('bad_job', Uint8List.fromList(utf8.encode('{')));
    await File('${dir.path}/half_job.tmp-123').writeAsString('partial');
    expect((await jobs.list()).single.id, job.id);
    await expectLater(
        storage.write('../escape', Uint8List(0)), throwsArgumentError);
  });

  test(
      'one window adopts a result, and closing without saving leaves it recoverable',
      () async {
    final job =
        await jobs.create(buildMultiPagePdf(1), 'scan', automatic: false);
    await jobs.run(job,
        recognize: (i) async => recognize(i), finish: (r) => finish(job, r));
    final first = OcrResultDelivery(jobs);
    final second = OcrResultDelivery(jobs);
    expect(await first.take(job), isNotNull);
    expect(await second.take(job), isNull);
    await first.releaseUnacknowledged();
    final recovered = await second.take(job);
    expect(recovered, isNotNull);
    expect((await jobs.list()).single.state, OcrJobState.complete);
    await second.acknowledge(recovered!);
    expect(await jobs.list(), isEmpty);
    expect(await storage.keys(), isEmpty);
  });

  test(
      'checkpoint write failure never advances the cursor or reports completion',
      () async {
    final failing = OcrJobs(_FailingPageStorage(directory: dir));
    final job =
        await failing.create(buildMultiPagePdf(2), 'scan', automatic: false);
    await expectLater(
        failing.run(job,
            recognize: (i) async => recognize(i),
            finish: (_) async => fail('failed checkpoint must not finish')),
        throwsA(isA<FileSystemException>()));
    final saved = (await jobs.read(job.id))!;
    expect(saved.state, OcrJobState.failed);
    expect(saved.nextPage, 0);
    expect(await jobs.page(job.id, 0), isNull);
    expect(await jobs.result(job.id), isNull);
  });
}

class _FailingPageStorage extends FileOcrJobStorage {
  _FailingPageStorage({required super.directory});
  @override
  Future<void> write(String key, Uint8List bytes) async {
    if (key.contains('_page_')) {
      throw const FileSystemException('synthetic disk full');
    }
    await super.write(key, bytes);
  }
}
