import 'dart:async';
import 'dart:js_interop';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_ocr_ondevice/pp_ocr.dart';

import 'l10n/app_l10n.dart';
import 'ocr_status.dart';

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

  /// Web OCR is supported by the browser-local onnxruntime-web bridge.
  static bool get isSupported => true;

  /// Whether a job is in flight (only one runs at a time).
  bool get isBusy => status.value != null;

  void dispose() => status.dispose();

  /// Asks the running job to stop. It finishes the current page request and
  /// then bails without producing a result.
  void cancel() {
    if (isBusy) _cancelled = true;
  }

  /// Starts OCR over [bytes]. The first run confirms the model download, then
  /// recognition runs entirely in the browser process.
  Future<void> start(
    BuildContext context, {
    required Uint8List bytes,
    required String title,
    required void Function(String message) onToast,
    required void Function(Uint8List result) onComplete,
  }) async {
    final l10n = appL10n(context);
    if (isBusy) {
      onToast(l10n.ocrAlreadyRunning);
      return;
    }
    if (!_hasBridge) {
      onToast(l10n.ocrBrowserInitFailed);
      return;
    }

    final approved = await showPdfDialog<bool>(
      context: context,
      builder: (_) => const _WebOcrConfirmDialog(),
    );
    if (approved != true) return;
    _cancelled = false;

    final pipeline = PpOcrPipeline(_BrowserOcrInference());
    final engine = OcrRunnerEngine(pipeline);
    try {
      status.value = OcrJobStatus(phase: OcrPhase.downloading, title: title);
      // Feed the bridge's model-download progress into the chip. The bridge
      // counts only the weight files and reports 'preparing' once their last
      // byte is in (cache write + session setup follow, with no progress);
      // the fraction is still held monotonic as a guard.
      var shownFraction = 0.0;
      _setProgressListener((String stage, num loaded, num total) {
        if (stage == 'preparing') {
          status.value = OcrJobStatus(phase: OcrPhase.preparing, title: title);
          return;
        }
        if (total <= 0) return;
        final fraction = (loaded / total).clamp(0.0, 1.0);
        if (fraction > shownFraction) shownFraction = fraction;
        status.value = OcrJobStatus(
          phase: OcrPhase.downloading,
          title: title,
          downloadFraction: shownFraction,
        );
      });
      try {
        await pipeline.load();
      } finally {
        _setProgressListener(null);
      }
      if (_cancelled) {
        onToast(l10n.ocrCancelled);
        return;
      }

      final editor = PdfEditor(PdfDocument.open(bytes));
      final count = editor.document.pageCount;
      var spans = 0;
      for (var i = 0; i < count; i++) {
        if (_cancelled) break;
        void report([double? pageFraction]) => status.value = OcrJobStatus(
              phase: OcrPhase.recognising,
              title: title,
              page: i + 1,
              pageCount: count,
              pageFraction: pageFraction,
            );
        report();
        pipeline.onProgress = report;
        spans += await editor.applyOcr(i, engine,
            pixelRatio: OcrRunnerEngine.pixelRatioFor(editor.document.page(i)));
        await Future<void>.delayed(Duration.zero);
      }
      if (_cancelled) {
        onToast(l10n.ocrCancelledAfterSpans(spans));
        return;
      }
      status.value = OcrJobStatus(phase: OcrPhase.finishing, title: title);
      final result = editor.save();
      onToast(l10n.ocrResult(spans));
      onComplete(result);
    } catch (e) {
      onToast(l10n.ocrFailed(e.toString()));
    } finally {
      await engine.dispose();
      status.value = null;
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
