import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

import 'render_worker.dart';

/// Fallback used where `dart:isolate` is unavailable (the web) until a Web
/// Worker backend lands: a worker that never offloads, so every page renders
/// locally exactly as it did before the worker existed.
PdfRenderWorker startRenderWorker(Uint8List bytes) => const _NullRenderWorker();

/// No-op: there is no worker to prewarm on this platform (#450 is web-specific).
void prewarmRenderWorkers(int count) {}

/// No-op counterpart to [prewarmRenderWorkers].
void disposePrewarmedRenderWorkers() {}

class _NullRenderWorker extends PdfRenderWorker {
  const _NullRenderWorker();

  @override
  bool get isActive => false;

  @override
  Future<List<PdfRenderCommand>?> record(int pageIndex,
          {bool annotations = true,
          int priority = 0,
          double? imagePixelRatio,
          bool decodeImages = true,
          int? commandLimit,
          PdfRect? imageDecodeRegion,
          PdfPartialRecordSink? onPartial}) async =>
      null;

  @override
  void cancel(int pageIndex, {int priority = 0}) {}

  @override
  void dispose() {}
}
