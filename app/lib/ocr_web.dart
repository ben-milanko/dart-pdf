import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart';

import 'l10n/app_l10n.dart';
import 'ocr_status.dart';
import 'ocr_tiling.dart';

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
    final l10n = appL10n(context);
    if (isBusy) {
      onToast(l10n.ocrAlreadyRunning);
      return;
    }
    if (!_hasBridge) {
      onToast(l10n.ocrBrowserInitFailed);
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
        onToast(l10n.ocrCancelled);
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
    // Florence-2 resizes whatever image it is handed to 768x768, so feeding it
    // the whole page crushes small print to a few unreadable pixels and it
    // hallucinates. Recognize the page in overlapping tiles small enough to
    // survive that resize, lift each tile's boxes back into page-pixel space,
    // then drop the duplicates the overlaps produce.
    final image = page.image;
    final tiles = ocrTiles(image.width, image.height);
    final raw = <OcrRawSpan>[];
    for (final tile in tiles) {
      final png = await _encodeTilePng(image, tile);
      final result = await _recognizeDataUrl(
        'data:image/png;base64,${base64Encode(png)}',
      );
      final spans = parseFlorenceSpans(
        result,
        fallbackWidth: tile.width.round(),
        fallbackHeight: tile.height.round(),
      );
      for (final span in spans) {
        raw.add(span.shifted(tile.left, tile.top));
      }
    }
    return [
      for (final span in mergeOcrSpans(raw))
        PdfOcrSpan(
          text: span.text,
          bounds: page.userSpaceRect(span.box),
          confidence: span.confidence,
        ),
    ];
  }

  /// Encodes the sub-rectangle [src] of [image] to PNG, the form the JS bridge
  /// accepts. Cropping happens on the raster thread (draw the source rect into
  /// a tile-sized image) so only the tile's pixels cross to JavaScript.
  static Future<Uint8List> _encodeTilePng(ui.Image image, Rect src) async {
    final w = src.width.round();
    final h = src.height.round();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      image,
      src,
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint(),
    );
    final picture = recorder.endRecording();
    final ui.Image tile;
    try {
      tile = await picture.toImage(w, h);
    } finally {
      picture.dispose();
    }
    try {
      final data = await tile.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('could not encode OCR tile to PNG');
      return data.buffer.asUint8List();
    } finally {
      tile.dispose();
    }
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
        FilledButton(
          key: const ValueKey('ocr-web-start'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(appL10n(context).ocrWebStart),
        ),
      ],
    );
  }
}
