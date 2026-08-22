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

/// Whether the platform's own print flow already shows the user what the job
/// will look like.
///
/// iOS, macOS and Android hand the whole PDF to the OS print system, which
/// previews it; on the web the browser's print dialog does the same. Windows
/// and Linux have no such surface. The Win32 common print dialog is
/// settings-only, and since Windows 11 22H2 the modern dialog that replaced it
/// answers a preview request with "This app doesn't support print preview" -
/// the legacy print API (`PrintDlgEx`, which the runner drives) gives Windows
/// no document content to render there, so no application calling it can fill
/// that pane. DartPDF previews the job itself where this is false; see
/// `showPrintPreviewDialog`.
///
/// [platform] is a test seam; it defaults to the running platform.
bool platformProvidesPrintPreview({TargetPlatform? platform}) {
  if (kIsWeb) return true;
  final target = platform ?? defaultTargetPlatform;
  return target != TargetPlatform.windows && target != TargetPlatform.linux;
}
