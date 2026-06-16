import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart';

import 'ocr_status.dart';

export 'ocr_status.dart';

/// Drives the app's browser-local OCR flow.
///
/// Native builds use `pdf_ocr_ondevice` with ONNX Runtime. Web builds cannot
/// compile that FFI stack, so this implementation calls the JavaScript OCR
/// bridge registered by `web/index.html`. That bridge loads a Florence-2
/// vision-language model through Transformers.js and runs recognition in the
/// browser; page images and OCR results do not go to an app OCR server.
class OnDeviceOcr {
  OnDeviceOcr();

  /// The current job's progress, or null when nothing is running. The app bar
  /// listens to this to show a progress chip with a cancel button.
  final ValueNotifier<OcrJobStatus?> status = ValueNotifier(null);

  bool _cancelled = false;

  /// Web OCR is supported by the browser-local Florence-2 bridge.
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
    if (isBusy) {
      onToast('OCR is already running — wait for it to finish or cancel it');
      return;
    }
    if (!_hasBridge) {
      onToast('Browser OCR failed to initialise');
      return;
    }

    final approved = await showDialog<bool>(
      context: context,
      builder: (_) => const _WebOcrConfirmDialog(),
    );
    if (approved != true) return;
    _cancelled = false;

    final engine = _BrowserOcrEngine();
    try {
      status.value = OcrJobStatus(phase: OcrPhase.downloading, title: title);
      await engine.warmUp();
      if (_cancelled) {
        onToast('OCR cancelled');
        return;
      }

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
      status.value = null;
    }
  }

  static bool get _hasBridge => _ocrBridge != null;
}

@JS('__dartPdfOcrRecognize')
external JSAny? get _ocrBridge;

@JS('__dartPdfOcrRecognize')
external JSPromise<JSString> _recognizeWithBrowserOcr(String imageDataUrl);

class _BrowserOcrEngine implements PdfOcrEngine {
  Future<void> warmUp() async {
    await _recognizeDataUrl(
      'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==',
    );
  }

  @override
  Future<List<PdfOcrSpan>> recognize(PdfOcrPageImage page) async {
    final png = await _encodePng(page.image);
    final result = await _recognizeDataUrl(
      'data:image/png;base64,${base64Encode(png)}',
    );
    return _spansFromFlorence(result, page);
  }

  static List<PdfOcrSpan> _spansFromFlorence(
    Object? result,
    PdfOcrPageImage page,
  ) {
    final payload = _payload(result);
    final labels = _listOfStrings(payload['labels']) ??
        _listOfStrings(payload['text']) ??
        _listOfStrings(payload['texts']);
    final boxes = _listOfBoxes(payload['quad_boxes']) ??
        _listOfBoxes(payload['quadBoxes']) ??
        _listOfBoxes(payload['bboxes']) ??
        _listOfBoxes(payload['boxes']);

    if (labels != null && boxes != null) {
      final spans = <PdfOcrSpan>[];
      final count = labels.length < boxes.length ? labels.length : boxes.length;
      for (var i = 0; i < count; i++) {
        final text = labels[i].trim();
        final rect = boxes[i];
        if (text.isEmpty || rect.width <= 0 || rect.height <= 0) continue;
        spans.add(PdfOcrSpan(
          text: text,
          bounds: page.userSpaceRect(rect),
          confidence: 1,
        ));
      }
      return spans;
    }

    final text = _plainText(payload).trim();
    if (text.isEmpty) return const [];
    return [
      PdfOcrSpan(
        text: text,
        bounds: page.userSpaceRect(
          Rect.fromLTWH(0, 0, page.width.toDouble(), page.height.toDouble()),
        ),
        confidence: 1,
      ),
    ];
  }

  static Map<String, Object?> _payload(Object? value) {
    if (value is Map) {
      final ocrWithRegion = value['<OCR_WITH_REGION>'];
      if (ocrWithRegion is Map) return ocrWithRegion.cast<String, Object?>();
      final ocr = value['<OCR>'];
      if (ocr is Map) return ocr.cast<String, Object?>();
      return value.cast<String, Object?>();
    }
    if (value is String) return {'text': value};
    return const {};
  }

  static List<String>? _listOfStrings(Object? value) {
    if (value is String) return [value];
    if (value is! List) return null;
    return [
      for (final item in value)
        if (item != null) item.toString()
    ];
  }

  static List<Rect>? _listOfBoxes(Object? value) {
    if (value is! List) return null;
    final rects = <Rect>[];
    for (final item in value) {
      final rect = _rect(item);
      if (rect != null) rects.add(rect);
    }
    return rects.isEmpty ? null : rects;
  }

  static Rect? _rect(Object? value) {
    if (value is! List || value.length < 4) return null;
    final nums = [
      for (final v in value)
        if (v is num) v.toDouble()
    ];
    if (nums.length < 4) return null;
    if (nums.length >= 8) {
      var minX = double.infinity, minY = double.infinity;
      var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
      for (var i = 0; i + 1 < nums.length; i += 2) {
        final x = nums[i], y = nums[i + 1];
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
      }
      return Rect.fromLTRB(minX, minY, maxX, maxY);
    }
    return Rect.fromLTRB(nums[0], nums[1], nums[2], nums[3]);
  }

  static String _plainText(Map<String, Object?> payload) {
    for (final key in const ['text', 'ocr', 'generated_text']) {
      final value = payload[key];
      if (value is String) return value;
    }
    return '';
  }

  static Future<Uint8List> _encodePng(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('could not encode page raster to PNG');
    return data.buffer.asUint8List();
  }

  static Future<Object?> _recognizeDataUrl(String dataUrl) async {
    final result = await _recognizeWithBrowserOcr(dataUrl).toDart;
    return jsonDecode(result.toDart);
  }
}

class _WebOcrConfirmDialog extends StatelessWidget {
  const _WebOcrConfirmDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey('ocr-web-settings'),
      title: const Text('Run AI OCR in this browser?'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Text(
          'Web OCR downloads a Florence-2 vision-language model and runs it '
          'locally with WebGPU/WASM through Transformers.js. The PDF pages stay '
          'in this browser; only model files are fetched on first use.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('ocr-web-start'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Start OCR'),
        ),
      ],
    );
  }
}
