import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:pdf_document/pdf_document.dart';

import 'page_export.dart';

/// Flattens [document] into a fresh, image-only PDF: every page is rendered
/// to a bitmap with this package's own engine and re-emitted as a single
/// full-page JPEG.
///
/// The result carries no fonts, vector content, or original object model -
/// just one DCTDecode image per page at its original point size. That makes
/// it trivially parseable by any conforming reader, which is the point:
/// some OS print backends embed a strict, third-party PDF rasteriser
/// (PDFium on Windows/Linux) that crashes on the broken-but-renderable
/// real-world files this engine is built to open. Printing a self-produced
/// raster copy instead of the original bytes keeps those documents printable
/// without handing the fragile backend something it can choke on.
///
/// [dpi] sets the raster resolution (200 by default - a good balance of print
/// sharpness against file size and memory); [jpegQuality] (1-100) trades size
/// for fidelity. Pages are rendered onto opaque white paper, so any
/// transparency flattens the way it would on a printer.
///
/// This needs `dart:ui` (it rasterises), so it runs wherever the viewer does.
/// Throws if [document] has no pages.
Future<Uint8List> rasterizePdfForPrinting(
  PdfDocument document, {
  double dpi = 200,
  int jpegQuality = 85,
}) async {
  final pages = await PdfPageExport.exportPages(
    document,
    format: PdfRasterFormat.jpeg,
    dpi: dpi,
    pageColor: const Color(0xFFFFFFFF),
    jpegQuality: jpegQuality,
  );
  // Size each page to its image at the same dpi, so the raster lands back at
  // the source page's physical dimensions (one image pixel = 72/dpi points).
  return PdfImageDocument.fromImageBytes(pages, dpi: dpi);
}
