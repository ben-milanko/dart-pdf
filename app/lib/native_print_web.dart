import 'dart:convert';
import 'dart:js_interop';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:web/web.dart' as web;

/// Prints [document] in a browser without any bundled PDF engine.
///
/// Each page is rendered with our own engine to a PNG, laid out one-per-sheet
/// in a hidden iframe, and printed with the browser's own print dialog
/// (`window.print()`). This replaces the `printing` plugin's web path so the
/// whole app drops the dependency.
///
/// [name] titles the print job (browsers use the document title as the default
/// filename for "Save as PDF"). [onProgress] is called `(rendered, total)`
/// after each page renders, so the host can show progress.
Future<void> printDocumentPages(
  PdfDocument document, {
  required String name,
  void Function(int rendered, int total)? onProgress,
}) async {
  final images = StringBuffer();
  for (var i = 0; i < document.pageCount; i++) {
    final png = await PdfPageExport.exportPage(
      document.page(i),
      format: PdfRasterFormat.png,
      dpi: 150,
    );
    final b64 = base64Encode(png);
    images.write(
        '<img class="page" src="data:image/png;base64,$b64" alt="page ${i + 1}"/>');
    onProgress?.call(i + 1, document.pageCount);
  }

  // One image per printed sheet; @page removes the browser's default margins so
  // the raster fills the paper, and each image breaks to a new page.
  final html = '<!doctype html><html><head><title>${_escape(name)}</title>'
      '<style>'
      '@page { margin: 0; }'
      'html, body { margin: 0; padding: 0; }'
      '.page { display: block; width: 100%; page-break-after: always; }'
      '.page:last-child { page-break-after: auto; }'
      '</style></head><body>$images</body></html>';

  final iframe = web.HTMLIFrameElement()
    ..style.position = 'fixed'
    ..style.right = '0'
    ..style.bottom = '0'
    ..style.width = '0'
    ..style.height = '0'
    ..style.border = '0';
  web.document.body!.appendChild(iframe);

  final frameWindow = iframe.contentWindow;
  final frameDoc = iframe.contentDocument;
  if (frameWindow == null || frameDoc == null) {
    iframe.remove();
    throw StateError('could not open a print frame');
  }
  frameDoc.open();
  frameDoc.write(html.toJS);
  frameDoc.close();

  // Give the images a beat to decode before printing, then tear the frame down
  // after the (modal) print dialog returns.
  await Future<void>.delayed(const Duration(milliseconds: 250));
  frameWindow.focus();
  frameWindow.print();
  await Future<void>.delayed(const Duration(seconds: 1));
  iframe.remove();
}

/// Minimal HTML-escaping for the job title in the document <title>.
String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
