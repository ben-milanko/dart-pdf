import 'package:flutter/foundation.dart';

import 'native_print.dart';

/// Signature for the app's "Print…" action: hands a PDF's [bytes] to the
/// platform print system under a job [title]. Injectable through
/// [EditorScreen.printDocument] so widget tests can assert the wiring without
/// driving the real print backend (which needs platform channels / a browser).
typedef PdfPrinter = Future<void> Function({
  required Uint8List bytes,
  required String title,
});

/// Prints [bytes] through the running platform's own print system, without any
/// bundled PDF engine.
///
/// Where a platform can print a PDF natively (iOS, macOS, Android, web), the
/// document's own vector content is handed straight to the OS print system -
/// crisp, selectable, and fast. Windows and Linux have no native PDF-print
/// API, so there each page is rendered by our own engine and streamed as a
/// raster. Either way there is no third-party PDF engine: this replaces the
/// `printing` plugin, whose desktop backend spooled through a bundled PDFium
/// that crashed on some of the broken-but-renderable files this engine opens.
/// See [printDocumentPages].
///
/// [onProgress] is called `(rendered, total)` as each page is rendered on the
/// raster path, so the caller can show progress (the vector path renders
/// nothing here and completes at once).
Future<void> printPdfBytes({
  required Uint8List bytes,
  required String title,
  void Function(int rendered, int total)? onProgress,
}) async {
  await printDocumentPages(
    bytes,
    name: printJobName(title),
    onProgress: onProgress,
  );
}

/// A clean print-job / suggested-filename label: the tab title without a
/// trailing `.pdf`, falling back to a default when it would be empty.
String printJobName(String title) {
  var name = title.trim();
  if (name.toLowerCase().endsWith('.pdf')) {
    name = name.substring(0, name.length - 4).trim();
  }
  return name.isEmpty ? 'Document' : name;
}
