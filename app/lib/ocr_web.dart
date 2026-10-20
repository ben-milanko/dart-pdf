import 'dart:async';
import 'dart:js_interop';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart' show pdfPageLooksScanned;
import 'package:pdf_ocr_ondevice/pp_ocr.dart';

import 'l10n/app_l10n.dart';
import 'ocr_jobs.dart';
import 'ocr_lifecycle.dart';
import 'ocr_job_store.dart';
import 'ocr_status.dart';
import 'ocr_web_budget.dart';

export 'ocr_status.dart';

/// Drives the app's browser-local OCR flow.
///
/// The same PP-OCR pipeline the native apps run (`pdf_ocr_ondevice`'s
/// [PpOcrPipeline]: resize, normalize, box extraction, CTC decoding), with
/// its two network calls handed to the onnxruntime-web bridge registered by
/// `web/index.html` instead of native ONNX Runtime, which can't compile here.
/// The models come from this app's own origin; page images and OCR results
/// never leave the browser.
class OnDeviceOcr {
  OnDeviceOcr();

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
    if (isBusy || _disposed || _recovering || ocrShouldPause) return;
    _recovering = true;
    try {
      for (final job in await _jobs.list()) {
        if (_disposed || !context.mounted) return;
        if (job.state == OcrJobState.cancelled ||
            await _jobs.isCancelled(job.id)) {
          await _jobs.delete(job.id);
          continue;
        }
        if (job.state == OcrJobState.failed) continue;
        {
          final source = await _jobs.source(job);
          if (!context.mounted) return;
          await _start(context,
              bytes: source,
              title: job.title,
              automatic: job.automatic,
              resume: job,
              onToast: onToast,
              onComplete: (bytes) => onComplete(bytes, job.title));
        }
      }
    } on MissingPluginException {
      // Hosts without the app storage plugin have no persisted jobs.
    } catch (e) {
      if (!_disposed && context.mounted) {
        onToast(appL10n(context).ocrFailed(e.toString()));
      }
    } finally {
      _recovering = false;
    }
  }

  /// Whether the user started browser OCR this session - an automatic run
  /// then goes ahead without asking again. [_autoDeclined] is the opposite:
  /// they turned down an automatic run, so later scans stay quiet.
  bool _approved = false;
  bool _autoDeclined = false;

  /// Web OCR is supported by the browser-local onnxruntime-web bridge.
  static bool get isSupported => true;

  /// Whether a job is in flight (only one runs at a time).
  bool get isBusy => status.value != null || _recovering;

  void dispose() {
    _disposed = true;
    _delivery.dispose();
    status.dispose();
  }

  /// Asks the running job to stop. It finishes the current page request and
  /// then bails without producing a result.
  void cancel() {
    if (isBusy) {
      _cancelled = true;
      final id = _jobId;
      if (id != null) unawaited(_jobs.cancel(id));
    }
  }

  /// Starts OCR over [bytes]. The first run confirms the model download, then
  /// recognition runs entirely in the browser process. [onComplete],
  /// [onRecognized] and [automatic] behave as in the native implementation;
  /// an automatic run skips the confirmation once the user has started
  /// browser OCR this session.
  Future<void> start(
    BuildContext context, {
    required Uint8List bytes,
    required String title,
    required void Function(String message) onToast,
    void Function(Uint8List result)? onComplete,
    void Function(Map<int, List<PdfOcrSpan>> spans)? onRecognized,
    bool automatic = false,
  }) async {
    return _start(context,
        bytes: bytes,
        title: title,
        onToast: onToast,
        onComplete: onComplete,
        onRecognized: onRecognized,
        automatic: automatic);
  }

  Future<void> _start(
    BuildContext context, {
    required Uint8List bytes,
    required String title,
    required void Function(String message) onToast,
    void Function(Uint8List result)? onComplete,
    void Function(Map<int, List<PdfOcrSpan>> spans)? onRecognized,
    bool automatic = false,
    OcrSavedJob? resume,
  }) async {
    final l10n = appL10n(context);
    if (status.value != null || (_recovering && resume == null)) {
      if (!automatic) onToast(l10n.ocrAlreadyRunning);
      return;
    }
    if (!_hasBridge) {
      if (!automatic) onToast(l10n.ocrBrowserInitFailed);
      return;
    }

    _status(OcrJobStatus(phase: OcrPhase.preparing, title: title));
    if (resume == null && (!automatic || !_approved)) {
      if (automatic && _autoDeclined) {
        _status(null);
        return;
      }
      final approved = await showPdfDialog<bool>(
        context: context,
        builder: (_) => const _WebOcrConfirmDialog(),
      );
      if (approved != true) {
        if (automatic) _autoDeclined = true;
        _status(null);
        return;
      }
      _approved = true;
    }
    _cancelled = false;

    OcrRunnerEngine? engine;
    OcrJobLease? lease;
    try {
      var job =
          resume ?? await _jobs.create(bytes, title, automatic: automatic);
      _jobId = job.id;
      lease = await _jobs.storage.claim(job.id);
      if (lease == null) return;
      // The list/create snapshot can become stale while another tab finishes
      // or adopts the result. Ownership must precede the canonical read.
      final current = await _jobs.read(job.id);
      if (current == null) return;
      job = current;
      if (job.state == OcrJobState.cancelled) {
        await _jobs.delete(job.id);
        onToast(l10n.ocrCancelled);
        return;
      }
      if (job.state == OcrJobState.complete) {
        final result = await _delivery.take(job);
        if (result == null) return;
        onComplete?.call(result);
        return;
      }
      _status(OcrJobStatus(phase: OcrPhase.downloading, title: title));
      // Feed the bridge's model-download progress into the chip. The bridge
      // counts only the weight files and reports 'preparing' once their last
      // byte is in (cache write + session setup follow, with no progress);
      // the fraction is still held monotonic as a guard.
      var shownFraction = 0.0;
      _setProgressListener((String stage, num loaded, num total) {
        if (stage == 'preparing') {
          _status(OcrJobStatus(phase: OcrPhase.preparing, title: title));
          return;
        }
        if (total <= 0) return;
        final fraction = (loaded / total).clamp(0.0, 1.0);
        if (fraction > shownFraction) shownFraction = fraction;
        _status(OcrJobStatus(
          phase: OcrPhase.downloading,
          title: title,
          downloadFraction: shownFraction,
        ));
      });
      try {
        await _ocrLoad().toDart;
      } finally {
        _setProgressListener(null);
      }
      // The bridge is up, so the heap it got is known; size the work to it.
      final pipeline = browserOcrPipeline(_BrowserOcrInference(),
          heapBytes: _ocrHeapLimitHook == null ? 0 : _ocrHeapLimit().toDartInt);
      engine = OcrRunnerEngine(pipeline);
      await pipeline.load();
      if (_cancelled) {
        onToast(l10n.ocrCancelled);
        return;
      }

      final editor = PdfEditor(PdfDocument.open(bytes));
      void onPage(int i, int count) {
        void report([double? pageFraction]) => _status(OcrJobStatus(
              phase: OcrPhase.recognising,
              title: title,
              page: i + 1,
              pageCount: count,
              pageFraction: pageFraction,
            ));
        report();
        pipeline.onProgress = report;
      }

      await _jobs.run(
        job,
        shouldPause: () => _disposed || ocrShouldPause,
        onProgress: (j) =>
            onPage(j.nextPage.clamp(0, j.pageCount - 1), j.pageCount),
        recognize: (i) async {
          if (automatic && !pdfPageLooksScanned(editor.document, i)) return [];
          return editor.recognizeOcr(i, engine!,
              pixelRatio:
                  OcrRunnerEngine.pixelRatioFor(editor.document.page(i)));
        },
        finish: (recognized) async {
          for (final entry in recognized.entries) {
            editor.injectTextLayer(entry.key, entry.value);
          }
          return editor.save();
        },
      );
      if (_disposed) return;
      if (job.state == OcrJobState.cancelled) {
        onToast(l10n.ocrCancelled);
        await _jobs.delete(job.id);
        return;
      }
      if (job.state != OcrJobState.complete) return;
      if (onRecognized != null) {
        onRecognized(await _jobs.recognized(job));
        await _jobs.delete(job.id);
      } else {
        final result = await _delivery.take(job);
        if (result == null) return;
        final spans = (await _jobs.recognized(job))
            .values
            .fold<int>(0, (n, s) => n + s.length);
        onToast(l10n.ocrResult(spans));
        onComplete?.call(result);
      }
    } catch (e) {
      if (!_disposed) onToast(l10n.ocrFailed(e.toString()));
    } finally {
      await engine?.dispose();
      await lease?.release();
      _jobId = null;
      _status(null);
    }
  }

  static bool get _hasBridge => _ocrBridge != null;

  /// Registers (or with null, clears) the bridge's model-load progress
  /// listener. A no-op against an older cached `index.html` without the hook.
  static void _setProgressListener(
    void Function(String stage, num loaded, num total)? listener,
  ) {
    if (_ocrProgressHook == null) return;
    _registerOcrProgress(
      listener == null
          ? null
          : ((JSString stage, JSNumber loaded, JSNumber total) => listener(
                stage.toDart,
                loaded.toDartDouble,
                total.toDartDouble,
              )).toJS,
    );
  }
}

@JS('__dartPdfOcrOnProgress')
external JSAny? get _ocrProgressHook;

@JS('__dartPdfOcrOnProgress')
external void _registerOcrProgress(JSFunction? listener);

@JS('__dartPdfOcrRun')
external JSAny? get _ocrBridge;

/// The OCR wasm heap's maximum when the bridge had to cap it, else 0. Null
/// against an older cached `index.html` without the hook.
@JS('__dartPdfOcrHeapLimit')
external JSAny? get _ocrHeapLimitHook;

@JS('__dartPdfOcrHeapLimit')
external JSNumber _ocrHeapLimit();

@JS('__dartPdfOcrLoad')
external JSPromise<JSString> _ocrLoad();

@JS('__dartPdfOcrRun')
external JSPromise<_OcrRunResult> _ocrRun(
    String name, JSFloat32Array data, JSArray<JSNumber> dims);

extension type _OcrRunResult(JSObject _) implements JSObject {
  external JSFloat32Array get data;
  external JSArray<JSNumber> get dims;
}

/// [PpOcrInference] over the onnxruntime-web bridge in `web/index.html`.
class _BrowserOcrInference implements PpOcrInference {
  @override
  Future<String> load() async => (await _ocrLoad().toDart).toDart;

  @override
  Future<OcrTensor> detect(Float32List input, int width, int height) =>
      _run('det', input, [1, 3, height, width]);

  @override
  Future<OcrTensor> recognize(
          Float32List input, int batch, int height, int width) =>
      _run('rec', input, [batch, 3, height, width]);

  static Future<OcrTensor> _run(
      String name, Float32List input, List<int> dims) async {
    final result =
        await _ocrRun(name, input.toJS, [for (final d in dims) d.toJS].toJS)
            .toDart;
    return (
      data: result.data.toDart,
      shape: [for (final d in result.dims.toDart) d.toDartInt],
    );
  }

  // The sessions live for the page; a later job reuses them.
  @override
  Future<void> dispose() async {}
}

class _WebOcrConfirmDialog extends StatelessWidget {
  const _WebOcrConfirmDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey('ocr-web-settings'),
      title: Text(appL10n(context).ocrWebPromptTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Text(appL10n(context).ocrWebPromptBody),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(appL10n(context).cancel),
        ),
        PdfDialogSubmit.action(
            onSubmit: () => Navigator.of(context).pop(true),
            child: FilledButton(
              key: const ValueKey('ocr-web-start'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(appL10n(context).ocrWebStart),
            )),
      ],
    );
  }
}
