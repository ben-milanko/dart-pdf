import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;
import 'package:dart_pdf_editor/dart_pdf_editor.dart' show PdfClipboardPdf;

/// Web [copyPngToClipboard]: writes the PNG [bytes] to the browser clipboard
/// through the Async Clipboard API directly. Returns true on success; rejects
/// (e.g. an unsupported browser, an insecure context, or a denied permission)
/// surface as a thrown error that [clipboardSnapshotHandler] reports as a
/// failed copy.
Future<bool> copyPngToClipboard(Uint8List bytes) async {
  final blob = web.Blob(
    <JSAny>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'image/png'),
  );
  // ClipboardItem takes a { mimeType: Blob } JS object.
  final items = JSObject()..setProperty('image/png'.toJS, blob);
  final item = web.ClipboardItem(items);
  await web.window.navigator.clipboard
      .write(<web.ClipboardItem>[item].toJS)
      .toDart;
  return true;
}

/// One paste triggers an image read immediately followed (when there's no
/// image) by a text read. Browsers gate `navigator.clipboard.read()` on a
/// user gesture, and a second gesture-less read within the same paste can be
/// rejected, so we read the clipboard **once** and let the text reader reuse
/// that result. The image reader always runs first and refreshes this, so the
/// text reader never sees a stale payload.
({Uint8List? image, String? text})? _pending;

Future<({Uint8List? image, String? text})> _readClipboard() async {
  final items = (await web.window.navigator.clipboard.read().toDart).toDart;
  Uint8List? image;
  String? text;
  for (final item in items) {
    for (final jsType in item.types.toDart) {
      final type = jsType.toDart;
      if (image == null && (type == 'image/png' || type == 'image/jpeg')) {
        final blob = await item.getType(type).toDart;
        final buffer = await blob.arrayBuffer().toDart;
        image = Uint8List.fromList(buffer.toDart.asUint8List());
      } else if (text == null && type == 'text/plain') {
        final blob = await item.getType(type).toDart;
        text = (await blob.text().toDart).toDart;
      }
    }
  }
  return (image: image, text: text);
}

/// Reads a PNG/JPEG image from the browser clipboard. Browsers require a
/// secure context and a user-initiated paste gesture; denied access or a
/// clipboard without an image returns null. Any text found alongside is
/// stashed for a following [readTextFromClipboard] so the pair costs a single
/// clipboard read.
Future<Uint8List?> readImageFromClipboard() async {
  try {
    final read = await _readClipboard();
    _pending = read;
    return read.image;
  } catch (_) {
    _pending = null;
    return null;
  }
}

/// Reads plain text from the browser clipboard. Reuses the payload from a
/// preceding [readImageFromClipboard] (same paste) when available so the two
/// share one gesture-gated read; otherwise reads directly. Flutter's own
/// `Clipboard.getData` is unreliable on the web, which is why the editor uses
/// this instead.
Future<String?> readTextFromClipboard() async {
  final pending = _pending;
  if (pending != null) {
    _pending = null;
    return pending.text;
  }
  try {
    return (await _readClipboard()).text;
  } catch (_) {
    return null;
  }
}

/// Browsers retain the interoperable PNG clipboard path. PDF clipboard
/// transport is provided by the desktop runners.
Future<bool> copySnapshotToClipboard(Uint8List pdf, Uint8List png) =>
    copyPngToClipboard(png);

Future<PdfClipboardPdf?> readPdfFromClipboard() async => null;

const supportsPdfClipboard = false;

Future<void> markLocalClipboardCopy() async {}
