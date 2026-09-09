import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'print_printer.dart';

/// Prints the PDF [pdfBytes] in a browser without any bundled PDF engine.
///
/// The PDF is loaded into a hidden iframe as a `blob:` URL and printed with the
/// browser's own print dialog (`window.print()`), so the browser renders the
/// document's vector content directly - crisp and selectable. This replaces the
/// `printing` plugin's web path so the whole app drops the dependency.
///
/// [name] titles the print job. [onProgress] is unused on the web (there is
/// nothing to render here); it exists to match the native signature.
/// [useDocumentPageSize] marks an already composed PDF. Its page dimensions
/// remain intact, but browsers own the final paper size and scaling controls;
/// browser scripts cannot force those print-dialog preferences.
Future<void> printDocumentPages(
  Uint8List pdfBytes, {
  required String name,
  void Function(int rendered, int total)? onProgress,
  bool useDocumentPageSize = false,
  PrintDestination? destination,
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
    ..title = name
    ..src = url;

  final loaded = Completer<void>();
  iframe.addEventListener(
      'load',
      (web.Event _) {
        if (!loaded.isCompleted) loaded.complete();
      }.toJS);
  iframe.addEventListener(
      'error',
      (web.Event _) {
        if (!loaded.isCompleted) {
          loaded
              .completeError(StateError('The browser could not load the PDF.'));
        }
      }.toJS);

  try {
    final body = web.document.body;
    if (body == null) throw StateError('Printing requires a browser document.');
    body.appendChild(iframe);
    await loaded.future.timeout(const Duration(seconds: 5));
    final window = iframe.contentWindow;
    if (window == null) {
      throw StateError('The browser PDF frame is unavailable.');
    }
    window.focus();
    window.print();
    // Allow the system dialog to open before releasing its PDF URL. Browsers
    // that reject cross-frame printing throw; let the host report that error.
    await Future<void>.delayed(const Duration(seconds: 1));
  } finally {
    iframe.remove();
    web.URL.revokeObjectURL(url);
  }
}
