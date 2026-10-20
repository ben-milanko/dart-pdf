import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_graphics/pdf_graphics.dart' show pdfPageLooksScanned;
import 'package:pdf_ocr_ondevice/pdf_ocr_ondevice.dart';
import 'ocr_jobs.dart';
import 'ocr_status.dart';

typedef NativeOcrJobRunner = Future<void> Function(
    OcrJobs jobs, OcrSavedJob job,
    {void Function(OcrSavedJob)? onProgress, bool Function()? shouldPause});

Future<void> executeNativeOcrJob(OcrJobs jobs, OcrSavedJob job,
    {void Function(OcrSavedJob)? onProgress,
    bool Function()? shouldPause}) async {
  final manager = PdfOcrModelManager();
  OnDeviceOcrEngine? engine;
  try {
    final source = await jobs.source(job);
    final editor = PdfEditor(PdfDocument.open(source));
    if (editor.document.pageCount != job.pageCount) {
      throw const FormatException(
          'OCR job page count does not match its snapshot');
    }
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
      shouldPause: shouldPause,
      onProgress: (progress) {
        onProgress?.call(progress);
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
  }
}
