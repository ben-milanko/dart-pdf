import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor_assets/dart_pdf_editor_assets.dart';
import 'package:pdf_graphics/pdf_graphics.dart' show pdfPageLooksScanned;
import 'package:pdf_ocr_ondevice/pdf_ocr_ondevice.dart';
import 'ocr_background.dart';
import 'ocr_jobs.dart';
import 'ocr_status.dart';
import 'ocr_job_store.dart';

bool get ocrDetachedSupported =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

Future<void> launchOcrWorker(String id) async {
  await Process.start(Platform.resolvedExecutable, ['--ocr-worker', id],
      mode: ProcessStartMode.detached);
}

Future<bool> runOcrWorkerIfRequested(List<String> args) async {
  if (args.length != 2 || args.first != '--ocr-worker') return false;
  WidgetsFlutterBinding.ensureInitialized();
  registerBundledEditorAssets();
  final jobs = OcrJobs(openOcrJobStorage());
  final lease = await jobs.storage.claim(args[1]);
  if (lease == null) exit(0);
  var resultCode = 0;
  try {
    final job = await jobs.read(args[1]);
    if (job != null) await executeNativeOcrJob(jobs, job);
  } catch (_) {
    // The saved failed state is the receipt. Do not leave a windowless engine
    // alive after an uncaught asynchronous entrypoint error.
    resultCode = 1;
  } finally {
    await lease.release();
  }
  exit(resultCode);
}

Future<void> executeNativeOcrJob(OcrJobs jobs, OcrSavedJob job,
    {void Function(OcrSavedJob)? onProgress}) async {
  final manager = PdfOcrModelManager();
  OnDeviceOcrEngine? engine;
  final background = OcrBackground();
  try {
    final source = await jobs.source(job);
    final editor = PdfEditor(PdfDocument.open(source));
    if (editor.document.pageCount != job.pageCount) {
      throw const FormatException(
          'OCR job page count does not match its snapshot');
    }
    await background.begin(job.title, job.pageCount,
        automatic: job.automatic, onCancel: () => jobs.cancel(job.id));
    if (!await manager.isDownloaded(PdfOcrModels.ppOcrV5Mobile)) {
      job.workPhase = OcrPhase.downloading;
      await jobs.save(job);
      onProgress?.call(job);
      await manager.download(PdfOcrModels.ppOcrV5Mobile);
    }
    if (await jobs.isCancelled(job.id)) {
      job.state = OcrJobState.cancelled;
      await jobs.save(job);
      return;
    }
    job.workPhase = OcrPhase.preparing;
    await jobs.save(job);
    engine = await OnDeviceOcrEngine.fromDownloadedModel(
        manager, PdfOcrModels.ppOcrV5Mobile);
    await jobs.run(
      job,
      shouldPause: () =>
          background.expired &&
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed,
      onProgress: (progress) {
        onProgress?.call(progress);
        // Progress updates are advisory. Checkpoint writes remain awaited.
        background.progress(progress.nextPage, progress.pageCount);
      },
      recognize: (i) async {
        if (job.automatic && !pdfPageLooksScanned(editor.document, i)) {
          return [];
        }
        return editor.recognizeOcr(i, engine!,
            pixelRatio: OcrRunnerEngine.pixelRatioFor(editor.document.page(i)));
      },
      finish: (recognized) async {
        for (final entry in recognized.entries) {
          editor.injectTextLayer(entry.key, entry.value);
        }
        return editor.save();
      },
    );
  } catch (error) {
    job
      ..state = OcrJobState.failed
      ..error = error.toString();
    await jobs.save(job);
    rethrow;
  } finally {
    await engine?.dispose();
    manager.close();
    await background.end(success: job.state == OcrJobState.complete);
  }
}
