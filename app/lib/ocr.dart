import 'dart:async';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_ocr_ondevice/pdf_ocr_ondevice.dart';

/// Drives the app's on-device OCR flow: download the model (once, with a
/// confirm + progress dialog), then run it over every page of a document and
/// hand back the result.
///
/// All of the heavy work lives in [pdf_ocr_ondevice]; this is just the app's
/// UI around it — model gating, the download prompt, progress dialogs, and
/// turning failures into a toast.
class OnDeviceOcr {
  OnDeviceOcr();

  final PdfOcrModelManager _manager = PdfOcrModelManager();
  final PdfOcrModel _model = PdfOcrModels.ppOcrV5Mobile;

  /// Whether on-device OCR can run on this platform at all.
  static bool get isSupported => PdfOcrModelManager.isSupported;

  void dispose() => _manager.close();

  /// Runs OCR over [bytes] and returns the OCR'd PDF, or null if the user
  /// cancelled or something failed (in which case [onToast] has the reason).
  Future<Uint8List?> run(
    BuildContext context, {
    required Uint8List bytes,
    required String title,
    required void Function(String message) onToast,
  }) async {
    if (!isSupported) {
      onToast('On-device OCR is not available on this platform');
      return null;
    }

    // Make sure the model is present (download it on first use).
    try {
      if (!await _manager.isDownloaded(_model)) {
        if (!context.mounted) return null;
        final approved = await _confirmDownload(context);
        if (approved != true) return null;
        if (!context.mounted) return null;
        final ok = await _download(context);
        if (!ok) return null; // _download toasted the reason
      }
    } on PdfOcrModelException catch (e) {
      onToast('OCR model error: ${e.message}');
      return null;
    }

    if (!context.mounted) return null;

    // Recognize every page.
    final progress = ValueNotifier<String>('Preparing…');
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _OcrProgressDialog(
        title: 'Recognising text',
        progress: progress,
      ),
    ));

    OnDeviceOcrEngine? engine;
    try {
      engine = await OnDeviceOcrEngine.fromDownloadedModel(_manager, _model);
      final editor = PdfEditor(PdfDocument.open(bytes));
      final count = editor.document.pageCount;
      var spans = 0;
      for (var i = 0; i < count; i++) {
        progress.value = 'Recognising page ${i + 1} of $count…';
        spans += await editor.applyOcr(i, engine, pixelRatio: 2);
      }
      final result = editor.save();
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      onToast(spans == 0
          ? 'OCR found no text on these pages'
          : 'OCR added $spans text spans — the page text is now selectable');
      return result;
    } catch (e) {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      onToast('OCR failed: $e');
      return null;
    } finally {
      await engine?.dispose();
      progress.dispose();
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

  /// Downloads the model behind a progress dialog. Returns whether it
  /// succeeded; on failure it pops the dialog and shows nothing here (the
  /// caller's [run] toasts via the thrown exception path).
  Future<bool> _download(BuildContext context) async {
    final progress = ValueNotifier<double?>(null);
    final label = ValueNotifier<String>('Starting download…');
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _OcrDownloadDialog(progress: progress, label: label),
    ));
    try {
      await _manager.download(_model, onProgress: (p) {
        progress.value = p.fraction;
        final pct = p.fraction == null ? '' : ' ${(p.fraction! * 100).round()}%';
        label.value = 'Downloading ${p.fileName}$pct';
      });
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      return true;
    } on PdfOcrModelException catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            key: const ValueKey('ocr-download-error'),
            title: const Text('Could not download the OCR model'),
            content: Text('${e.message}\n\n'
                'See the pdf_ocr_ondevice README for how to host the model '
                'bundle.'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      return false;
    } finally {
      progress.dispose();
      label.dispose();
    }
  }
}

/// Determinate-or-indeterminate progress bar shown while the model downloads.
class _OcrDownloadDialog extends StatelessWidget {
  const _OcrDownloadDialog({required this.progress, required this.label});

  final ValueListenable<double?> progress;
  final ValueListenable<String> label;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey('ocr-download-progress'),
      title: const Text('Downloading OCR model'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ValueListenableBuilder<double?>(
            valueListenable: progress,
            builder: (context, value, _) =>
                LinearProgressIndicator(value: value),
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder<String>(
            valueListenable: label,
            builder: (context, value, _) =>
                Text(value, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

/// Spinner + per-page label shown while OCR runs.
class _OcrProgressDialog extends StatelessWidget {
  const _OcrProgressDialog({required this.title, required this.progress});

  final String title;
  final ValueListenable<String> progress;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey('ocr-progress'),
      title: Text(title),
      content: Row(
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ValueListenableBuilder<String>(
              valueListenable: progress,
              builder: (context, value, _) => Text(value),
            ),
          ),
        ],
      ),
    );
  }
}
