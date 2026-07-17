import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Prints the PDF [pdfBytes] in a browser without any bundled PDF engine.
///
/// The PDF is loaded into a hidden iframe as a `blob:` URL and printed with the
/// browser's own print dialog (`window.print()`), so the browser renders the
/// document's vector content directly - crisp and selectable. This replaces the
/// `printing` plugin's web path so the whole app drops the dependency.
///
/// [name] titles the print job. [onProgress] is unused on the web (there is
/// nothing to render here); it exists to match the native signature.
Future<void> printDocumentPages(
  Uint8List pdfBytes, {
  required String name,
  void Function(int rendered, int total)? onProgress,
}) async {
  final blob = web.Blob(
    <JSUint8Array>[pdfBytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/pdf'),
  );
  final url = web.URL.createObjectURL(blob);

  final iframe = web.HTMLIFrameElement()
    ..style.position = 'fixed'
    ..style.right = '0'
    ..style.bottom = '0'
    ..style.width = '0'
    ..style.height = '0'
    ..style.border = '0'
    ..src = url;

  // Print once the PDF has loaded into the frame, then clean up. Some browsers
  // won't print a cross-frame PDF viewer; the frame still offers the document
  // for a manual print in that case.
  final loaded = Completer<void>();
  iframe.addEventListener(
    'load',
    (web.Event _) {
      if (!loaded.isCompleted) loaded.complete();
    }.toJS,
  );
  web.document.body!.appendChild(iframe);

  await loaded.future.timeout(const Duration(seconds: 5), onTimeout: () {});
  try {
    iframe.contentWindow?.focus();
    iframe.contentWindow?.print();
  } catch (_) {
    // Printing the frame isn't available; leave the loaded PDF in place.
  }

  // Give the (modal) print dialog time to open before revoking the URL.
  await Future<void>.delayed(const Duration(seconds: 1));
  web.URL.revokeObjectURL(url);
  iframe.remove();
}
