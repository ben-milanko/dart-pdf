import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Web [copyPngToClipboard]: writes the PNG [bytes] to the browser clipboard
/// through the Async Clipboard API directly, rather than super_clipboard's
/// legacy `dart:html` web layer (which mis-handles image writes on modern
/// Flutter web). Returns true on success; rejects (e.g. an unsupported
/// browser, an insecure context, or a denied permission) surface as a thrown
/// error that [clipboardSnapshotHandler] reports as a failed copy.
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
