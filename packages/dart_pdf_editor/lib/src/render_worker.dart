import 'dart:typed_data';

import 'package:pdf_graphics/pdf_graphics.dart';

import 'render_worker_stub.dart'
    if (dart.library.io) 'render_worker_isolate.dart'
    if (dart.library.js_interop) 'render_worker_web.dart';

/// On web, the URL of the compiled Web Worker script that backs the render
/// worker (its `main()` calls `runPdfRenderWorker`; see the web-only library
/// `package:dart_pdf_editor/render_worker_web.dart` and
/// `doc/render_worker_web.md` for the build wiring).
///
/// Set this once before opening a viewer to move page interpretation off the
/// main thread on web. Left null, web falls back to local rendering — exactly
/// the historical behavior — so apps that haven't built the worker script are
/// unaffected. Ignored on native, where the isolate backend needs no script.
String? pdfRenderWorkerScriptUrl;

/// Records a PDF page's interpreter callbacks into a portable command buffer
/// OFF the UI thread, so the dominant render cost — the content-stream parse
/// and interpreter walk — stops blocking frames while scrolling.
///
/// A worker owns a private copy of the document, opened from the same bytes on
/// its own isolate (native), and answers [record] with the page's replayable
/// [PdfRenderCommand] list, already deserialized from the wire format. The
/// caller turns that into a `ui.Picture` with
/// `PdfPageRenderer.pictureFromCommands` — a cheap replay. Image XObjects are
/// serialized into the buffer, and the worker decodes them off-thread too
/// (the premultiplied pixels ride on each command), so the main thread runs
/// only the engine codec, never the pure-Dart inflate/colour-convert. Images
/// that need the platform JPEG codec ship un-decoded and decode locally.
///
/// The worker's document is a fixed snapshot of the bytes it was started with.
/// It is therefore only correct for a document whose pages don't change under
/// it: the read-only reader, or an editor between edits. Callers driving an
/// editing session must dispose and restart the worker when the document's
/// bytes change (or simply not use one).
abstract class PdfRenderWorker {
  /// Starts the platform's worker over [bytes] (the document image the page
  /// indices passed to [record] refer to). Native: a long-lived background
  /// isolate that opens its own [PdfDocument]. Web: a Web Worker over the
  /// script at [pdfRenderWorkerScriptUrl] when one is configured (else a null
  /// worker). Platforms without either: a null worker whose [record] always
  /// defers to local rendering.
  static PdfRenderWorker start(Uint8List bytes) => startRenderWorker(bytes);

  /// Records page [pageIndex] off-thread and returns its replayable command
  /// buffer (image XObjects decoded off-thread and attached), or null when the
  /// page can't be offloaded — it draws an inline image (`BI .. ID .. EI`,
  /// which can name a page-resource colour space the stream can't reach), the
  /// worker failed or was disposed, or this platform has no worker — and the
  /// caller must render the page locally.
  ///
  /// [annotations] mirrors `PdfPageRenderer.renderPicture`'s flag: when false
  /// the page's annotations are left out of the recording.
  ///
  /// [priority] orders the worker's single queue — lower is served first, so
  /// the on-screen page (0) preempts background prefetch (1) even though the
  /// isolate processes one page at a time.
  ///
  /// [imagePixelRatio] (screen pixels per page point, device pixel ratio
  /// included) caps each decoded image to display resolution before it is
  /// serialized — see `serializeCommands`'s `maxImagePixelRatio`. Pass the
  /// resolution the page will be shown at; a raster-heavy CAD sheet then ships
  /// a display-sized underlay instead of its native 100+ megapixels. Null
  /// leaves images at native resolution.
  ///
  /// [decodeImages] false records the page's vector/text but ships its images
  /// un-decoded (just their streams), so the buffer comes back fast even on a
  /// page whose raster underlay takes seconds to decode — the fast first pass
  /// of progressive rendering. The caller replays it with
  /// `PdfPageRenderer.pictureFromCommands(includeImages: false)` to paint the
  /// linework immediately, then records again with [decodeImages] true for the
  /// images. Default true (decode in the worker, the normal full render).
  Future<List<PdfRenderCommand>?> record(int pageIndex,
      {bool annotations = true,
      int priority = 0,
      double? imagePixelRatio,
      bool decodeImages = true});

  /// Drops any QUEUED (not yet started) [record] request for [pageIndex] at
  /// [priority], completing its future with null — as if the page had declined
  /// to a local render. A cheap no-op when nothing matches.
  ///
  /// In-flight preemption is handled separately: when a higher-priority
  /// [record] arrives while a lower-priority one is executing, the worker
  /// cancels the in-flight job cooperatively (via [PdfCancellationToken]) and
  /// serves the urgent request next. This method only clears the queue.
  ///
  /// The point is to cancel prefetch the user has scrolled past: a page that
  /// left the viewport before its turn came no longer needs decoding, and
  /// leaving its request queued would make the worker spend its next slot — and
  /// ship a multi-megabyte decoded buffer — for a page nobody is looking at,
  /// delaying the page that is. The caller that abandons a cancelled result
  /// must not fall back to a local interpret (the work would be wasted);
  /// [PdfPageView] does this by abandoning when it is unmounted or superseded.
  void cancel(int pageIndex, {int priority = 0});

  /// Whether this worker actually offloads. False for the null fallback, so
  /// callers can skip the round-trip and render locally without asking.
  bool get isActive;

  /// Tears the worker down (kills the isolate, fails pending requests with
  /// null). Idempotent.
  void dispose();
}
