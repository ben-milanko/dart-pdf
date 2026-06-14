import 'dart:typed_data';

import 'package:pdf_graphics/pdf_graphics.dart';

import 'render_worker_stub.dart'
    if (dart.library.io) 'render_worker_isolate.dart';

/// Records a PDF page's interpreter callbacks into a portable command buffer
/// OFF the UI thread, so the dominant render cost — the content-stream parse
/// and interpreter walk — stops blocking frames while scrolling.
///
/// A worker owns a private copy of the document, opened from the same bytes on
/// its own isolate (native), and answers [record] with the page's replayable
/// [PdfRenderCommand] list, already deserialized from the wire format. The
/// caller turns that into a `ui.Picture` with
/// `PdfPageRenderer.pictureFromCommands` — no image decode is needed because
/// image-bearing pages return null and are rendered locally instead.
///
/// The worker's document is a fixed snapshot of the bytes it was started with.
/// It is therefore only correct for a document whose pages don't change under
/// it: the read-only reader, or an editor between edits. Callers driving an
/// editing session must dispose and restart the worker when the document's
/// bytes change (or simply not use one).
abstract class PdfRenderWorker {
  /// Starts the platform's worker over [bytes] (the document image the page
  /// indices passed to [record] refer to). Native: a long-lived background
  /// isolate that opens its own [PdfDocument]. Web and other platforms without
  /// isolates: a null worker whose [record] always defers to local rendering
  /// (until a Web Worker backend lands).
  static PdfRenderWorker start(Uint8List bytes) => startRenderWorker(bytes);

  /// Records page [pageIndex] off-thread and returns its replayable command
  /// buffer, or null when the page can't be offloaded — it draws images (not
  /// serializable in this cut), the worker failed or was disposed, or this
  /// platform has no worker — and the caller must render the page locally.
  ///
  /// [annotations] mirrors `PdfPageRenderer.renderPicture`'s flag: when false
  /// the page's annotations are left out of the recording.
  ///
  /// [priority] orders the worker's single queue — lower is served first, so
  /// the on-screen page (0) preempts background prefetch (1) even though the
  /// isolate processes one page at a time.
  Future<List<PdfRenderCommand>?> record(int pageIndex,
      {bool annotations = true, int priority = 0});

  /// Whether this worker actually offloads. False for the null fallback, so
  /// callers can skip the round-trip and render locally without asking.
  bool get isActive;

  /// Tears the worker down (kills the isolate, fails pending requests with
  /// null). Idempotent.
  void dispose();
}
