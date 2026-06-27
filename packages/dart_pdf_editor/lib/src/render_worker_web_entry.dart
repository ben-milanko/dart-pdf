import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:web/web.dart' as web;

/// Runs the render worker inside a dedicated Web Worker. A consuming web app
/// ships a tiny worker script that calls this:
///
/// ```dart
/// // web/pdf_render_worker.dart
/// import 'package:dart_pdf_editor/render_worker_web.dart';
/// void main() => runPdfRenderWorker();
/// ```
///
/// compiled with `dart compile js web/pdf_render_worker.dart -o
/// web/pdf_render_worker.dart.js` and served alongside the app; the app then
/// sets `pdfRenderWorkerScriptUrl = 'pdf_render_worker.dart.js'` before opening
/// a viewer. See `doc/render_worker_web.md` for the full wiring.
///
/// Protocol (mirrors the native isolate backend):
/// - `{kind:'init', bytes:ArrayBuffer}` → opens the document, replies
///   `{kind:'ready'}`.
/// - `{kind:'record', id, page, annotations}` → replies `{kind:'result', id,
///   buffer:ArrayBuffer|null}` (null = the page can't be offloaded; the main
///   thread renders it locally).
/// - `{kind:'cancel'}` → sets the active cancellation token so the in-flight
///   interpreter walk abandons early, replying with `buffer:null`.
void runPdfRenderWorker() {
  final scope = globalContext as web.DedicatedWorkerGlobalScope;
  PdfDocument? document;
  PdfCancellationToken? activeToken;

  // The handler MUST stay synchronous (return void): `.toJS` cannot convert a
  // Future-returning function, so an `async` handler fails `dart compile js`
  // ("invalid types in its function signature: Future<Null> Function(...)").
  // The cancellable record below therefore runs in a fire-and-forget inner
  // async closure instead of making the handler itself async.
  scope.onmessage = ((web.MessageEvent event) {
    final data = event.data as JSObject?;
    if (data == null) return;
    final kind = (data.getProperty('kind'.toJS) as JSString?)?.toDart;

    if (kind == 'init') {
      // Extract AND open inside the try: a malformed transfer (the cast or the
      // ArrayBuffer view can throw on some hosts) must NOT skip the 'ready'
      // reply below, or the main thread waits on it forever. A null document
      // simply declines every page to a local render.
      try {
        final buffer = data.getProperty('bytes'.toJS) as JSArrayBuffer;
        document = PdfDocument.open(buffer.toDart.asUint8List());
      } catch (_) {
        document = null; // bad transfer / broken document → local renders
      }
      // ALWAYS reply ready, even on failure, so the client never hangs.
      scope.postMessage(JSObject()..setProperty('kind'.toJS, 'ready'.toJS));
      return;
    }

    if (kind == 'cancel') {
      activeToken?.cancelled = true;
      return;
    }

    if (kind != 'record') return;
    final id = (data.getProperty('id'.toJS) as JSNumber).toDartInt;
    final page = (data.getProperty('page'.toJS) as JSNumber).toDartInt;
    final annotations =
        (data.getProperty('annotations'.toJS) as JSBoolean).toDart;
    final imagePixelRatio =
        (data.getProperty('imageRatio'.toJS) as JSNumber?)?.toDartDouble;
    // Default true so an older client that doesn't send the flag still decodes.
    final decodeImages =
        (data.getProperty('decodeImages'.toJS) as JSBoolean?)?.toDart ?? true;

    final token = PdfCancellationToken();
    activeToken = token;
    // Fire-and-forget: launch the cancellable walk without awaiting it here, so
    // the message handler returns void (see the note above) while a subsequent
    // 'cancel' message can still flip token.cancelled mid-walk.
    () async {
      Uint8List? out;
      String? error;
      final doc = document;
      try {
        if (doc != null) {
          out = await _recordPageAsync(
              doc, page, annotations, imagePixelRatio, decodeImages, token);
        }
      } on PdfCancelledException {
        out = null;
      } catch (e, st) {
        out = null; // any failure → the main thread renders this page locally
        error = '$e\n$st';
      }
      // Only clear the active token if it is still ours — a newer record may
      // have replaced it while this one was running.
      if (identical(activeToken, token)) activeToken = null;

      final result = JSObject()
        ..setProperty('kind'.toJS, 'result'.toJS)
        ..setProperty('id'.toJS, id.toJS);
      if (out == null) {
        result.setProperty('buffer'.toJS, null);
        if (error != null) result.setProperty('error'.toJS, error.toJS);
        scope.postMessage(result);
      } else {
        // Copy to an exact-length buffer, then transfer it (zero-copy).
        final jsBuffer = Uint8List.fromList(out).buffer.toJS;
        result.setProperty('buffer'.toJS, jsBuffer);
        scope.postMessage(result, <JSAny>[jsBuffer].toJS);
      }
    }();
  }).toJS;
}

/// Records one page into a serialized command buffer, yielding periodically
/// so the cancel message handler can fire and set [token.cancelled].
///
/// Duplicated from the isolate backend deliberately: that file imports
/// `dart:isolate`, which does not exist on web, so this entry can't share it.
Future<Uint8List?> _recordPageAsync(
    PdfDocument document,
    int pageIndex,
    bool annotations,
    double? imagePixelRatio,
    bool decodeImages,
    PdfCancellationToken token) async {
  if (pageIndex < 0 || pageIndex >= document.pageCount) return null;
  final page = document.page(pageIndex);
  final ops = ContentStreamParser.parse(page.contentBytes());
  final recorder = RecordingPdfDevice();
  final interpreter =
      PdfInterpreter(cos: document.cos, device: recorder, cancellation: token);
  await interpreter.drawPageOperationsAsync(page, ops);
  if (annotations) interpreter.drawAnnotations(page);
  // Decode the page's images in the worker too: the buffer carries
  // premultiplied RGBA so the main thread only runs the engine codec. On web
  // this matters more than on native — there is no separate raster thread, so
  // the pure-Dart inflate/colour-convert would otherwise block frames. #73.
  // imagePixelRatio caps each image to display resolution before it crosses the
  // postMessage boundary, so a sheet-sized raster underlay ships at a few MB
  // instead of hundreds. decodeImages false skips the decode entirely for the
  // fast vector-first pass of progressive rendering.
  return serializeCommands(recorder.commands,
      cos: document.cos,
      decodeImages: decodeImages,
      maxImagePixelRatio: imagePixelRatio,
      imagePlaceholders: !decodeImages);
}
