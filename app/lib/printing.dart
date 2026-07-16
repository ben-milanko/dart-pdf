import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:printing/printing.dart';

/// Signature for the app's "Print…" action: hands a PDF's [bytes] to the
/// platform print system under a job [title]. Injectable through
/// [EditorScreen.printDocument] so widget tests can assert the wiring without
/// driving the real print plugin (which needs platform channels).
typedef PdfPrinter = Future<void> Function({
  required Uint8List bytes,
  required String title,
});

/// Turns a finished PDF into an image-only copy for printing. Injectable so
/// tests can assert the Windows path without driving the real rasteriser.
typedef PrintRasterizer = Future<Uint8List> Function(Uint8List bytes);

/// Sends [bytes] to the OS print dialog via the `printing` plugin, which covers
/// iOS, Android, macOS, Windows, Linux, and the web.
///
/// On Windows the plugin prints through a bundled PDFium, which crashes the
/// whole process on some of the broken-but-renderable real-world files this
/// engine happily opens. So on Windows we don't hand it the original bytes:
/// we rasterise the document with our own engine and print a flat, image-only
/// PDF that any reader parses safely (see [rasterizePdfForPrinting]). If that
/// rasterisation fails for any reason we fall back to the original bytes, so
/// this is never worse than printing directly. Every other platform keeps the
/// crisp, vector document - their native renderers are robust.
///
/// [platform] and [rasterize] are test seams; production uses the running
/// platform and [rasterizePdfForPrinting].
Future<void> printPdfBytes({
  required Uint8List bytes,
  required String title,
  @visibleForTesting TargetPlatform? platform,
  @visibleForTesting PrintRasterizer? rasterize,
}) async {
  var document = bytes;
  if (_needsRasterPrint(platform ?? defaultTargetPlatform)) {
    try {
      document = await (rasterize ?? _rasterizeForPrint)(bytes);
    } catch (_) {
      // A rasterisation failure is not fatal: print the original document and
      // let the platform backend do what it can with it.
      document = bytes;
    }
  }
  await Printing.layoutPdf(
    onLayout: (_) => document,
    name: printJobName(title),
  );
}

/// Whether prints on [platform] should be flattened to a raster PDF first.
/// Only Windows, whose print backend is the one that crashes; the web (where
/// [defaultTargetPlatform] can still report Windows) prints through the
/// browser, so it is excluded.
bool _needsRasterPrint(TargetPlatform platform) =>
    !kIsWeb && platform == TargetPlatform.windows;

/// Opens [bytes] with our own engine and rasterises it for printing.
Future<Uint8List> _rasterizeForPrint(Uint8List bytes) =>
    rasterizePdfForPrinting(PdfDocument.open(bytes));

/// A clean print-job / suggested-filename label: the tab title without a
/// trailing `.pdf`, falling back to a default when it would be empty.
String printJobName(String title) {
  var name = title.trim();
  if (name.toLowerCase().endsWith('.pdf')) {
    name = name.substring(0, name.length - 4).trim();
  }
  return name.isEmpty ? 'Document' : name;
}
