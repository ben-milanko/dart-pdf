import 'dart:io';
import 'dart:typed_data';

import 'package:dart_pdf_editor_app/ocr_jobs.dart';
import 'package:dart_pdf_editor_app/ocr_job_store_io.dart';
import 'package:dart_pdf_editor_app/ocr_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  late Directory directory;
  late OcrJobs jobs;
  late BuildContext context;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ocr-resume-ui-');
    jobs = OcrJobs(FileOcrJobStorage(directory: directory));
  });
  tearDown(() => directory.delete(recursive: true));

  Future<void> mount(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (value) {
      context = value;
      return const SizedBox();
    })));
  }

  Future<Uint8List> assemble(
      OcrJobs owner, OcrSavedJob job, Map<int, List<PdfOcrSpan>> spans) async {
    final editor = PdfEditor(PdfDocument.open(await owner.source(job)));
    for (final page in spans.entries) {
      editor.injectTextLayer(page.key, page.value);
    }
    return editor.save();
  }

  testWidgets(
      'reopening resumes after saved pages and acknowledges output once',
      (tester) async {
    await mount(tester);
    final calls = <int>[];
    Uint8List? output;
    final toasts = <String>[];
    await tester.runAsync(() async {
      final job =
          await jobs.create(buildMultiPagePdf(3), 'scan.pdf', automatic: false);
      await jobs.savePage(job.id, 0, []);
      final ocr = OnDeviceOcr(
          jobs: jobs,
          runJob: (owner, saved, {onProgress, shouldPause}) => owner.run(saved,
              onProgress: onProgress,
              shouldPause: shouldPause,
              recognize: (page) async {
                calls.add(page);
                return [
                  PdfOcrSpan(
                      text: 'saved$page', bounds: const PdfRect(10, 10, 80, 30))
                ];
              },
              finish: (spans) => assemble(owner, saved, spans)));
      try {
        await ocr.recover(context, onToast: toasts.add,
            onComplete: (bytes, title) {
          expect(title, 'scan.pdf');
          output = bytes;
        });
        expect(calls, [1, 2]);
        expect(output, isNotNull);
        expect(ocr.isBusy, isFalse);
        expect(await jobs.read(job.id), isNotNull,
            reason: 'output is retained until the tab is persisted');
        await ocr.acknowledgeResult(output!);
        expect(await jobs.list(), isEmpty);
        await ocr.recover(context,
            onToast: toasts.add,
            onComplete: (_, __) => fail('already delivered'));
      } finally {
        ocr.dispose();
      }
    });
    expect(toasts, hasLength(1));
  });

  testWidgets('hiding the app checkpoints the page, then foreground resumes',
      (tester) async {
    await mount(tester);
    final calls = <int>[];
    Uint8List? output;
    await tester.runAsync(() async {
      final job =
          await jobs.create(buildMultiPagePdf(3), 'scan', automatic: false);
      final ocr = OnDeviceOcr(
          jobs: jobs,
          runJob: (owner, saved, {onProgress, shouldPause}) => owner.run(saved,
              onProgress: onProgress,
              shouldPause: shouldPause,
              recognize: (page) async {
                calls.add(page);
                if (page == 0) {
                  tester.binding
                      .handleAppLifecycleStateChanged(AppLifecycleState.hidden);
                }
                return [];
              },
              finish: (spans) => assemble(owner, saved, spans)));
      try {
        await ocr.recover(context,
            onToast: (_) {}, onComplete: (bytes, _) => output = bytes);
        expect(calls, [0]);
        expect((await jobs.read(job.id))!.state, OcrJobState.pending);
        expect((await jobs.read(job.id))!.nextPage, 1);
        expect(output, isNull);
        await ocr.recover(context, onToast: (_) {}, onComplete: (_, __) {});
        expect(calls, [0], reason: 'a hidden app must not start another page');
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await ocr.recover(context,
            onToast: (_) {}, onComplete: (bytes, _) => output = bytes);
        expect(calls, [0, 1, 2]);
        expect(output, isNotNull);
        await ocr.acknowledgeResult(output!);
      } finally {
        ocr.dispose();
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      }
    });
  });

  testWidgets('disabled automatic OCR stays paused while manual OCR resumes',
      (tester) async {
    await mount(tester);
    await tester.runAsync(() async {
      final automatic =
          await jobs.create(buildMultiPagePdf(2), 'automatic', automatic: true);
      await jobs.savePage(automatic.id, 0, []);
      automatic.nextPage = 1;
      await jobs.save(automatic);
      final manual =
          await jobs.create(buildMultiPagePdf(1), 'manual', automatic: false);
      final resumed = <String>[];
      var enabled = false;
      final ocr = OnDeviceOcr(
          jobs: jobs,
          runJob: (owner, job, {onProgress, shouldPause}) async {
            resumed.add(job.id);
          });
      try {
        await ocr.recover(context,
            automaticEnabled: () => enabled,
            onToast: (_) => fail('unexpected toast'),
            onComplete: (_, __) => fail('must not deliver'));
        expect(resumed, [manual.id]);
        final retained = (await jobs.read(automatic.id))!;
        expect(retained.state, OcrJobState.pending);
        expect(retained.nextPage, 1);
        expect(await jobs.page(automatic.id, 0), isEmpty);

        enabled = true;
        resumed.clear();
        await ocr.recover(context,
            automaticEnabled: () => enabled,
            onToast: (_) {},
            onComplete: (_, __) {});
        expect(resumed, contains(automatic.id));
      } finally {
        ocr.dispose();
      }
    });
  });

  testWidgets('recovery rechecks the choice before each automatic job',
      (tester) async {
    await mount(tester);
    await tester.runAsync(() async {
      final manual =
          await jobs.create(buildMultiPagePdf(1), 'manual', automatic: false);
      final automatic =
          await jobs.create(buildMultiPagePdf(2), 'automatic', automatic: true);
      var enabled = true;
      final resumed = <String>[];
      final ocr = OnDeviceOcr(
          jobs: jobs,
          runJob: (_, job, {onProgress, shouldPause}) async {
            resumed.add(job.id);
            enabled = false;
          });
      try {
        await ocr.recover(context,
            automaticEnabled: () => enabled,
            onToast: (_) {},
            onComplete: (_, __) {});
        expect(resumed, [manual.id]);
        expect((await jobs.read(automatic.id))!.state, OcrJobState.pending);
      } finally {
        ocr.dispose();
      }
    });
  });

  testWidgets('completed automatic results remain recoverable while off',
      (tester) async {
    await mount(tester);
    await tester.runAsync(() async {
      final job =
          await jobs.create(buildMultiPagePdf(1), 'finished', automatic: true);
      await jobs.run(job,
          recognize: (_) async => [],
          finish: (spans) => assemble(jobs, job, spans));
      expect((await jobs.read(job.id))!.state, OcrJobState.complete);
      Uint8List? output;
      final ocr = OnDeviceOcr(
          jobs: jobs,
          runJob: (_, __, {onProgress, shouldPause}) async =>
              fail('completed recognition must not run again'));
      try {
        await ocr.recover(context,
            automaticEnabled: () => false,
            onToast: (_) {},
            onComplete: (bytes, _) => output = bytes);
        expect(output, isNotNull);
        await ocr.acknowledgeResult(output!);
        expect(await jobs.list(), isEmpty);
      } finally {
        ocr.dispose();
      }
    });
  });

  testWidgets('cancelled jobs are discarded, failed jobs await explicit retry',
      (tester) async {
    await mount(tester);
    await tester.runAsync(() async {
      final cancelled = await jobs.create(buildMultiPagePdf(1), 'cancelled',
          automatic: false);
      await jobs.cancel(cancelled.id);
      final failed =
          await jobs.create(buildMultiPagePdf(2), 'failed', automatic: false);
      failed.state = OcrJobState.failed;
      await jobs.save(failed);
      final ocr = OnDeviceOcr(
          jobs: jobs,
          runJob: (_, __, {onProgress, shouldPause}) async =>
              fail('must not run'));
      try {
        await ocr.recover(context,
            onToast: (_) => fail('unexpected toast'),
            onComplete: (_, __) => fail('must not deliver'));
        expect(await jobs.read(cancelled.id), isNull);
        expect((await jobs.list()).single.id, failed.id);
      } finally {
        ocr.dispose();
      }
    });
  });

  testWidgets('another window owning a job prevents duplicate processing',
      (tester) async {
    await mount(tester);
    await tester.runAsync(() async {
      final job =
          await jobs.create(buildMultiPagePdf(1), 'scan', automatic: false);
      final lease = (await jobs.storage.claim(job.id))!;
      final ocr = OnDeviceOcr(
          jobs: jobs,
          runJob: (_, __, {onProgress, shouldPause}) async =>
              fail('job already owned'));
      try {
        await ocr.recover(context,
            onToast: (_) {}, onComplete: (_, __) => fail('must not deliver'));
        expect((await jobs.read(job.id))!.state, OcrJobState.pending);
      } finally {
        ocr.dispose();
        await lease.release();
      }
    });
  });
}
