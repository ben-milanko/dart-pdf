import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

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

/// Reads a PNG/JPEG image from the browser clipboard. Browsers require a
/// secure context and a user-initiated paste gesture; denied access or a
/// clipboard without an image returns null.
Future<Uint8List?> readImageFromClipboard() async {
  try {
    final items = (await web.window.navigator.clipboard.read().toDart).toDart;
    for (final item in items) {
      for (final jsType in item.types.toDart) {
        final type = jsType.toDart;
        if (type != 'image/png' && type != 'image/jpeg') continue;
        final blob = await item.getType(type).toDart;
        final buffer = await blob.arrayBuffer().toDart;
        return Uint8List.fromList(buffer.toDart.asUint8List());
      }
    }
  } catch (_) {
    return null;
  }
  return null;
}
