import 'package:flutter/foundation.dart';
import 'package:printing/printing.dart';

/// Signature for the app's "Print…" action: hands a PDF's [bytes] to the
/// platform print system under a job [title]. Injectable through
/// [EditorScreen.printDocument] so widget tests can assert the wiring without
/// driving the real print plugin (which needs platform channels).
typedef PdfPrinter = Future<void> Function({
  required Uint8List bytes,
  required String title,
});

/// Sends [bytes] to the OS print dialog via the `printing` plugin, which covers
/// iOS, Android, macOS, Windows, Linux, and the web. The document is already a
/// finished PDF, so the layout callback returns it verbatim regardless of the
/// paper [format] the user picks — the engine here renders, it doesn't reflow.
Future<void> printPdfBytes({
  required Uint8List bytes,
  required String title,
}) async {
  await Printing.layoutPdf(
    onLayout: (_) => bytes,
    name: printJobName(title),
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
