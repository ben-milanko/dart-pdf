import 'dart:async';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_ocr_ondevice/pdf_ocr_ondevice.dart';

import 'l10n/app_l10n.dart';
import 'l10n/app_localizations.dart';
import 'ocr_jobs.dart';
import 'ocr_job_store.dart';
import 'ocr_worker_io.dart';
import 'ocr_status.dart';

export 'ocr_status.dart';

/// Drives the app's on-device OCR flow: download the model (once, behind a
/// quick confirm), then run it over every page of a document - in the
/// **background**, so the user keeps interacting with the PDF while a long
/// (hundreds of pages) job runs. Progress is published on [status] for an
/// app-bar indicator; [cancel] stops it.
///
/// All of the heavy work lives in [pdf_ocr_ondevice]; this is just the app's
/// orchestration - model gating, the download prompt, progress reporting, and
/// turning failures into a toast.
class OnDeviceOcr {
  OnDeviceOcr();

  final PdfOcrModelManager _manager = PdfOcrModelManager();
  final PdfOcrModel _model = PdfOcrModels.ppOcrV5Mobile;

  /// The current job's progress, or null when nothing is running. The app bar
  /// listens to this to show a progress chip with a cancel button.
  final ValueNotifier<OcrJobStatus?> status = ValueNotifier(null);

  bool _cancelled = false;
  bool _disposed = false;
  String? _jobId;
  bool _recovering = false;
  final OcrJobs _jobs = OcrJobs(openOcrJobStorage());
  late final OcrResultDelivery _delivery = OcrResultDelivery(_jobs);

  void _status(OcrJobStatus? value) {
    if (!_disposed) status.value = value;
  }

  Future<void> acknowledgeResult(Uint8List result) async {
    await _delivery.acknowledge(result);
  }

  Future<void> recover(
    BuildContext context, {
    required void Function(String) onToast,
    required void Function(Uint8List, String) onComplete,
  }) async {
    if (isBusy || _disposed || _recovering) return;
    _recovering = true;
    try {
      for (final job in await _jobs.list()) {
        if (_disposed || !context.mounted) return;
        if (job.state == OcrJobState.cancelled) {
          await _jobs.delete(job.id);
          continue;
        }
        if (job.state == OcrJobState.failed) continue;
        await _runSaved(job,
            onToast: onToast,
            onComplete: (bytes) => onComplete(bytes, job.title),
            l10n: appL10n(context));
      }
    } on MissingPluginException {
      // Hosts without the app storage plugin have no persisted jobs.
    } catch (e) {
      if (!_disposed && context.mounted) {
        onToast(appL10n(context).ocrFailed(e.toString()));
      }
    } finally {
      _jobId = null;
      _status(null);
      _recovering = false;
    }
  }

  Future<void> _runSaved(
    OcrSavedJob job, {
    required void Function(String) onToast,
    required AppLocalizations l10n,
    void Function(Uint8List)? onComplete,
    void Function(Map<int, List<PdfOcrSpan>>)? onRecognized,
  }) async {
    _jobId = job.id;
    void progress(OcrSavedJob j) => _status(OcrJobStatus(
          phase: j.workPhase,
          title: j.title,
          page: (j.nextPage + 1).clamp(1, j.pageCount),
          pageCount: j.pageCount,
        ));
    _status(OcrJobStatus(phase: OcrPhase.preparing, title: job.title));
    if (job.state != OcrJobState.complete) {
      if (ocrDetachedSupported) {
        final lease = await _jobs.storage.claim(job.id);
        var shouldLaunch = false;
        if (lease != null) {
          try {
            // A worker may have completed (and a different window may have
            // adopted it) since list/create returned this snapshot.
            final current = await _jobs.read(job.id);
            if (current == null) return;
            job = current;
            if (job.state != OcrJobState.complete &&
                job.state != OcrJobState.cancelled) {
              job.state = OcrJobState.pending;
              await _jobs.save(job);
              shouldLaunch = true;
            }
          } finally {
            await lease.release();
          }
          if (shouldLaunch) await launchOcrWorker(job.id);
        } else {
          final current = await _jobs.read(job.id);
          if (current == null) return;
          job = current;
        }
        final started = DateTime.now();
        // Poll durable progress, not a pipe owned by this editor process. The
        // detached worker keeps running after the last editor window closes.
        while (!_disposed &&
            (job.state == OcrJobState.pending ||
                job.state == OcrJobState.running)) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          final current = await _jobs.read(job.id);
          if (current == null) throw StateError('OCR job disappeared');
          job = current;
          progress(job);
          if (job.state != OcrJobState.pending &&
              job.state != OcrJobState.running) {
            break;
          }
          // Failed startup/native crash must not leave an eternal progress
          // chip. A live worker owns the OS lock even during long pages.
          if (DateTime.now().difference(started).inSeconds > 30) {
            final abandoned = await _jobs.storage.claim(job.id);
            if (abandoned != null) {
              await abandoned.release();
              throw StateError(
                  'OCR worker stopped; choose OCR again to resume');
            }
          }
        }
      } else {
        final lease = await _jobs.storage.claim(job.id);
        if (lease == null) return;
        try {
          final current = await _jobs.read(job.id);
          if (current == null) return;
          job = current;
          if (job.state != OcrJobState.complete &&
              job.state != OcrJobState.cancelled) {
            await executeNativeOcrJob(_jobs, job, onProgress: progress);
          }
        } finally {
          await lease.release();
        }
      }
    }
    if (_disposed) return;
    if (job.state == OcrJobState.complete) {
      if (onRecognized != null) {
        onRecognized(await _jobs.recognized(job));
        // Keep the established live-session revision guard. A completed live
        // callback consumes this job; an interrupted job recovers as a copy.
        await _jobs.delete(job.id);
      } else {
        final result = await _delivery.take(job);
        if (result == null) return;
        final spans = (await _jobs.recognized(job))
            .values
            .fold<int>(0, (n, s) => n + s.length);
        onComplete?.call(result);
        onToast(l10n.ocrResult(spans));
      }
    } else if (job.state == OcrJobState.cancelled) {
      await _jobs.delete(job.id);
      onToast(l10n.ocrCancelled);
    } else if (job.state == OcrJobState.failed) {
      onToast(l10n.ocrFailed(job.error ?? 'OCR worker stopped'));
    }
    _jobId = null;
    _status(null);
  }

  /// Set when the user turns down the model download for an automatic run:
  /// later scans this session don't ask again (the Settings switch or the
  /// OCR menu item still can).
  bool _autoDeclined = false;

  /// Whether on-device OCR can run on this platform at all.
  static bool get isSupported => PdfOcrModelManager.isSupported;

  /// Whether a job is in flight (only one runs at a time).
  bool get isBusy => status.value != null || _recovering;

  void dispose() {
    _disposed = true;
    _delivery.dispose();
    _manager.close();
    status.dispose();
  }

  /// Asks the running job to stop. It finishes the current page (and any
  /// in-flight model download) and then bails without producing a result.
  void cancel() {
    if (isBusy) {
      _cancelled = true;
      final id = _jobId;
      if (id != null) unawaited(_jobs.cancel(id));
    }
  }

  /// Starts an OCR job over [bytes] in the background and returns once it
  /// finishes (so the caller can `unawaited` it). On success [onComplete] is
  /// handed the OCR'd PDF - or, when [onRecognized] is given instead, the
  /// recognized spans by page index, for the caller to lay onto its live
  /// session (and toast about) itself. Cancellation and failures are reported
  /// through [onToast] and leave both uncalled. A one-time confirm-download
  /// dialog may show first (hence [context]); after that nothing blocks the UI.
  ///
  /// An [automatic] job (a scan was just opened) stays quiet where a user's
  /// request would explain itself: it doesn't toast when another job is
  /// running, only recognizes pages that look scanned, and once its download
  /// prompt is declined it doesn't ask again this session.
  Future<void> start(
    BuildContext context, {
    required Uint8List bytes,
    required String title,
    required void Function(String message) onToast,
    void Function(Uint8List result)? onComplete,
    void Function(Map<int, List<PdfOcrSpan>> spans)? onRecognized,
    bool automatic = false,
  }) async {
    final l10n = appL10n(context);
    if (isBusy) {
      if (!automatic) onToast(l10n.ocrAlreadyRunning);
      return;
    }
    if (!isSupported) {
      if (!automatic) onToast(l10n.ocrNotAvailable);
      return;
    }
    _cancelled = false;
    _status(OcrJobStatus(phase: OcrPhase.preparing, title: title));

    // Make sure the model is present (download it on first use).
    try {
      if (!await _manager.isDownloaded(_model)) {
        if (automatic && _autoDeclined) {
          _status(null);
          return;
        }
        if (!context.mounted) {
          _status(null);
          return;
        }
        final approved = await _confirmDownload(context);
        if (approved != true) {
          if (automatic) _autoDeclined = true;
          _status(null);
          return;
        }
      }
    } catch (e) {
      _status(null);
      onToast(l10n.ocrDownloadFailed(e.toString()));
      return;
    }
    if (_cancelled) {
      _status(null);
      onToast(l10n.ocrCancelled);
      return;
    }

    try {
      final job = await _jobs.create(bytes, title, automatic: automatic);
      await _runSaved(job,
          l10n: l10n,
          onToast: onToast,
          onComplete: onComplete,
          onRecognized: onRecognized);
    } catch (e) {
      if (!_disposed) onToast(l10n.ocrFailed(e.toString()));
    } finally {
      _jobId = null;
      _status(null);
    }
  }

  Future<bool?> _confirmDownload(BuildContext context) {
    final size = _model.approxSizeBytes;
    final sizeText = size == null
        ? ''
        : ' ${appL10n(context).ocrModelApproxSize((size / 1024 / 1024).round())}';
    return showPdfDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('ocr-download-confirm'),
        title: Text(appL10n(context).ocrDownloadPromptTitle),
        content: Text(
          appL10n(context).ocrDownloadPromptBody(sizeText, _model.displayName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(appL10n(context).cancel),
          ),
          PdfDialogSubmit.action(
              onSubmit: () => Navigator.of(context).pop(true),
              child: FilledButton(
                key: const ValueKey('ocr-download-confirm-ok'),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(appL10n(context).ocrDownload),
              )),
        ],
      ),
    );
  }
}
