import 'dart:async';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_ocr_ondevice/pdf_ocr_ondevice.dart';

import 'ocr_status.dart';

export 'ocr_status.dart';

/// Drives the app's on-device OCR flow: download the model (once, behind a
/// quick confirm), then run it over every page of a document — in the
/// **background**, so the user keeps interacting with the PDF while a long
/// (hundreds of pages) job runs. Progress is published on [status] for an
/// app-bar indicator; [cancel] stops it.
///
/// All of the heavy work lives in [pdf_ocr_ondevice]; this is just the app's
/// orchestration — model gating, the download prompt, progress reporting, and
/// turning failures into a toast.
class OnDeviceOcr {
  OnDeviceOcr();

  final PdfOcrModelManager _manager = PdfOcrModelManager();
  final PdfOcrModel _model = PdfOcrModels.ppOcrV5Mobile;

  /// The current job's progress, or null when nothing is running. The app bar
  /// listens to this to show a progress chip with a cancel button.
  final ValueNotifier<OcrJobStatus?> status = ValueNotifier(null);

  bool _cancelled = false;

  /// Whether on-device OCR can run on this platform at all.
  static bool get isSupported => PdfOcrModelManager.isSupported;

  /// Whether a job is in flight (only one runs at a time).
  bool get isBusy => status.value != null;

  void dispose() {
    _manager.close();
    status.dispose();
  }

  /// Asks the running job to stop. It finishes the current page (and any
  /// in-flight model download) and then bails without producing a result.
  void cancel() {
    if (isBusy) _cancelled = true;
  }

  /// Starts an OCR job over [bytes] in the background and returns once it
  /// finishes (so the caller can `unawaited` it). On success [onComplete] is
  /// handed the OCR'd PDF; cancellation and failures are reported through
  /// [onToast] and leave [onComplete] uncalled. A one-time confirm-download
  /// dialog may show first (hence [context]); after that nothing blocks the UI.
  Future<void> start(
    BuildContext context, {
    required Uint8List bytes,
    required String title,
    required void Function(String message) onToast,
    required void Function(Uint8List result) onComplete,
  }) async {
    if (isBusy) {
      onToast('OCR is already running — wait for it to finish or cancel it');
      return;
    }
    if (!isSupported) {
      onToast('On-device OCR is not available on this platform');
      return;
    }
    _cancelled = false;

    // Make sure the model is present (download it on first use).
    try {
      if (!await _manager.isDownloaded(_model)) {
        if (!context.mounted) return;
        final approved = await _confirmDownload(context);
        if (approved != true) return;
        status.value = OcrJobStatus(phase: OcrPhase.downloading, title: title);
        await _manager.download(_model, onProgress: (p) {
          status.value = OcrJobStatus(
            phase: OcrPhase.downloading,
            title: title,
            downloadFraction: p.fraction,
          );
        });
      }
    } on PdfOcrModelException catch (e) {
      status.value = null;
      onToast('Could not download the OCR model: ${e.message}');
      return;
    }
    if (_cancelled) {
      status.value = null;
      onToast('OCR cancelled');
      return;
    }

    // Recognize every page, yielding between pages so the UI stays responsive.
    OnDeviceOcrEngine? engine;
    try {
      engine = await OnDeviceOcrEngine.fromDownloadedModel(_manager, _model);
      final editor = PdfEditor(PdfDocument.open(bytes));
      final count = editor.document.pageCount;
      var spans = 0;
      for (var i = 0; i < count; i++) {
        if (_cancelled) break;
        status.value = OcrJobStatus(
          phase: OcrPhase.recognising,
          title: title,
          page: i + 1,
          pageCount: count,
        );
        spans += await editor.applyOcr(i, engine, pixelRatio: 2);
        // Hand the event loop a turn so taps/scrolls are serviced promptly.
        await Future<void>.delayed(Duration.zero);
      }
      if (_cancelled) {
        onToast('OCR cancelled after $spans text spans');
        return;
      }
      status.value = OcrJobStatus(phase: OcrPhase.finishing, title: title);
      final result = editor.save();
      onToast(spans == 0
          ? 'OCR found no text on these pages'
          : 'OCR added $spans text spans — the page text is now selectable');
      onComplete(result);
    } catch (e) {
      onToast('OCR failed: $e');
    } finally {
      await engine?.dispose();
      status.value = null;
    }
  }

  Future<bool?> _confirmDownload(BuildContext context) {
    final size = _model.approxSizeBytes;
    final sizeText =
        size == null ? '' : ' (~${(size / 1024 / 1024).round()} MB)';
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('ocr-download-confirm'),
        title: const Text('Download OCR model?'),
        content: Text(
          'Adding a selectable text layer needs the on-device OCR model'
          '$sizeText. It downloads once and then runs offline.\n\n'
          'Model: ${_model.displayName}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('ocr-download-confirm-ok'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Download'),
          ),
        ],
      ),
    );
  }
}
