import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

import 'image_decoder.dart';

/// Encodes [page] as a vector-print op stream (see [encodeVectorPrintPage])
/// using the app's full `dart:ui`-backed image decode, so baseline-JPEG
/// underlays - the one image class the pure-Dart path can't turn into pixels -
/// still reach the print stream.
///
/// This is the Windows/Linux vector-print entry point the print action calls:
/// the OS there has no native PDF-print API, so instead of rasterising every
/// page we hand the print system the page's own vector primitives (paths,
/// glyph outlines, selectable substituted text) plus decoded image rasters.
Future<Uint8List> encodePageForVectorPrinting(PdfPage page,
        {int? rotation, bool annotations = true}) =>
    encodeVectorPrintPage(
      page,
      rotation: rotation,
      annotations: annotations,
      decodeImages: _decodeVectorPrintImages,
    );

/// Resolves image pixels for the vector-print encoder through the same
/// `dart:ui` decoder the renderer uses, then reads each decoded image back to
/// premultiplied RGBA. Undecodable images are omitted (the encoder skips them),
/// exactly as the on-screen renderer skips an image it can't decode.
Future<Map<PdfImageRequest, PdfDecodedPixels>> _decodeVectorPrintImages(
    CosDocument cos, List<PdfImageRequest> requests) async {
  // Cold decode (no cache): printing is infrequent and we dispose the images
  // right after reading their bytes, so we don't want to churn the render cache.
  final images = await decodeImages(cos, requests);
  final out = <PdfImageRequest, PdfDecodedPixels>{};
  try {
    for (final request in requests) {
      final image = images[pdfImageKey(request)];
      if (image == null) continue;
      final data =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) continue;
      out[request] = PdfDecodedPixels(
        data.buffer.asUint8List(),
        image.width,
        image.height,
      );
    }
  } finally {
    for (final image in images.values) {
      image.dispose();
    }
  }
  return out;
}
