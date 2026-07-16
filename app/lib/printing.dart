import 'package:flutter/foundation.dart';
import 'package:pdf_document/pdf_document.dart';

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
/// Every page is rendered with our own engine and handed to the OS print
/// system (GDI on Windows, `NSPrintOperation` on macOS,
/// `UIPrintInteractionController` on iOS, `PrintManager` on Android,
/// `GtkPrintOperation` on Linux) or the browser's print dialog on the web -
/// see [printDocumentPages]. This replaces the `printing` plugin, whose
/// desktop backend spooled through a bundled PDFium that crashed the process
/// on some of the broken-but-renderable files this engine opens.
Future<void> printPdfBytes({
  required Uint8List bytes,
  required String title,
}) async {
  await printDocumentPages(PdfDocument.open(bytes), name: printJobName(title));
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
