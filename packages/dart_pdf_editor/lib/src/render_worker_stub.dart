import 'dart:typed_data';

import 'package:pdf_graphics/pdf_graphics.dart';

import 'render_worker.dart';

/// Fallback used where `dart:isolate` is unavailable (the web) until a Web
/// Worker backend lands: a worker that never offloads, so every page renders
/// locally exactly as it did before the worker existed.
PdfRenderWorker startRenderWorker(Uint8List bytes) => const _NullRenderWorker();

class _NullRenderWorker implements PdfRenderWorker {
  const _NullRenderWorker();

  @override
  bool get isActive => false;

  @override
  Future<List<PdfRenderCommand>?> record(int pageIndex,
          {bool annotations = true, int priority = 0}) async =>
      null;

  @override
  void cancel(int pageIndex, {int priority = 0}) {}

  @override
  void dispose() {}
}
