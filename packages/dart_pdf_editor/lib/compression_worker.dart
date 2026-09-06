/// Cancellable PDF optimisation on a native isolate or browser Web Worker.
library;

import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';

import 'src/compression_worker_native.dart'
    if (dart.library.js_interop) 'src/compression_worker_web.dart';

/// A single optimisation job. The source bytes remain owned by the caller.
///
/// Web jobs use a dedicated instance of the configured PDF render-worker
/// script, so cancelling a job never interrupts the viewer's workers. Hosts
/// must bundle the current worker and configure `pdfRenderWorkerScriptUrl`
/// (normally through `registerBundledEditorAssets`). Worker failures are
/// reported through [result]; optimisation never falls back to the UI thread.
abstract class PdfCompressionTask {
  static PdfCompressionTask start(
    Uint8List bytes, {
    PdfCompressionOptions options = const PdfCompressionOptions(),
  }) =>
      startCompressionTask(bytes, options);

  Future<PdfCompressionResult> get result;

  /// Whether the worker has acknowledged starting the optimisation.
  /// Remains true after completion if work started successfully.
  bool get hasStarted;

  /// Terminates the worker and completes [result] with
  /// [PdfCompressionCancelledException]. Harmless after completion.
  void cancel();
}

class PdfCompressionCancelledException implements Exception {
  const PdfCompressionCancelledException();

  @override
  String toString() => 'PDF optimisation was cancelled.';
}
