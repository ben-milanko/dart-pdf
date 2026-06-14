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
void runPdfRenderWorker() {
  final scope = globalContext as web.DedicatedWorkerGlobalScope;
  PdfDocument? document;

  scope.onmessage = ((web.MessageEvent event) {
    final data = event.data as JSObject?;
    if (data == null) return;
    final kind = (data.getProperty('kind'.toJS) as JSString?)?.toDart;

    if (kind == 'init') {
      final buffer = data.getProperty('bytes'.toJS) as JSArrayBuffer;
      try {
        document = PdfDocument.open(buffer.toDart.asUint8List());
      } catch (_) {
        document = null; // a broken document fails every page → local renders
      }
      scope.postMessage(JSObject()..setProperty('kind'.toJS, 'ready'.toJS));
      return;
    }

    if (kind != 'record') return;
    final id = (data.getProperty('id'.toJS) as JSNumber).toDartInt;
    final page = (data.getProperty('page'.toJS) as JSNumber).toDartInt;
    final annotations =
        (data.getProperty('annotations'.toJS) as JSBoolean).toDart;

    Uint8List? out;
    // A page can decline (image it can't serialize) or throw; surface the reason
    // to the main thread so it lands in a PdfPerfLog trace instead of being lost
    // in the worker's own console.
    String? error;
    final doc = document;
    try {
      if (doc != null) out = _recordPage(doc, page, annotations);
    } catch (e, st) {
      out = null; // any failure → the main thread renders this page locally
      error = '$e\n$st';
    }

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
  }).toJS;
}

/// Records one page into a serialized command buffer, or null when it is out of
/// range or draws an image that cannot be serialized (an inline image — see
/// [serializeCommands]). Image XObjects serialize via [document]'s `cos`.
///
/// Duplicated from the isolate backend deliberately: that file imports
/// `dart:isolate`, which does not exist on web, so this entry can't share it.
Uint8List? _recordPage(PdfDocument document, int pageIndex, bool annotations) {
  if (pageIndex < 0 || pageIndex >= document.pageCount) return null;
  final page = document.page(pageIndex);
  final ops = ContentStreamParser.parse(page.contentBytes());
  final recorder = RecordingPdfDevice();
  final interpreter = PdfInterpreter(cos: document.cos, device: recorder)
    ..drawPageOperations(page, ops);
  if (annotations) interpreter.drawAnnotations(page);
  return serializeCommands(recorder.commands, cos: document.cos);
}
