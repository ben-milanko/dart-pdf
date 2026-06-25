import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;
import 'package:pdf_document/pdf_document.dart';

import 'renderer.dart';

/// The raster encodings [PdfPageExport] can produce.
enum PdfRasterFormat {
  /// Lossless PNG (RGBA, preserves any transparent margins).
  png,

  /// Baseline JPEG (RGB, no alpha — translucent areas are flattened onto
  /// [PdfPageExport]'s page colour). Smaller files for photographic scans.
  jpeg,
}

/// Exports PDF pages to PNG/JPEG image bytes.
///
/// This is the public, documented entry point for the "PDF → image" side of
/// the conversion pipeline. It wraps the existing rasterizer
/// ([PdfPageRenderer.renderImage]) so a host can turn a page — or a whole
/// document — into image files at a chosen resolution and colour, without
/// touching `dart:ui` directly.
///
/// Resolution is given as [dpi] (dots per inch); a PDF point is 1/72 inch, so
/// the raster is `dpi / 72` pixels per point. Pass [scale] to override that
/// with an explicit pixels-per-point ratio instead (150 dpi == 2.083×).
///
/// ```dart
/// final doc = PdfDocument.open(bytes);
/// final png = await PdfPageExport.exportPage(doc.page(0), dpi: 200);
/// // write `png` to disk / upload it — these bytes are a complete PNG file.
/// ```
class PdfPageExport {
  PdfPageExport._();

  /// Renders [page] and encodes it as [format] bytes.
  ///
  /// [dpi] sets the resolution (default 150); [scale] overrides it with an
  /// explicit pixels-per-point ratio when given. [pageColor] is the paper
  /// painted under the content (and what JPEG flattens transparency onto);
  /// [annotations] toggles drawing the page's annotations; [rotation]
  /// overrides the page's own /Rotate for the export. [jpegQuality] (1–100)
  /// applies to [PdfRasterFormat.jpeg].
  ///
  /// Returns a complete image file's bytes — write them straight to disk or
  /// upload them.
  static Future<Uint8List> exportPage(
    PdfPage page, {
    PdfRasterFormat format = PdfRasterFormat.png,
    double dpi = 150,
    double? scale,
    Color pageColor = const Color(0xFFFFFFFF),
    bool annotations = true,
    int? rotation,
    int jpegQuality = 90,
  }) async {
    if (dpi <= 0) throw ArgumentError.value(dpi, 'dpi', 'must be positive');
    if (scale != null && scale <= 0) {
      throw ArgumentError.value(scale, 'scale', 'must be positive');
    }
    final pixelRatio = scale ?? dpi / 72;
    final image = await PdfPageRenderer.renderImage(
      page,
      pixelRatio: pixelRatio,
      pageColor: pageColor,
      annotations: annotations,
      rotation: rotation,
    );
    try {
      return await _encode(image, format, pageColor, jpegQuality);
    } finally {
      image.dispose();
    }
  }

  /// Exports a contiguous run of pages from [document], starting at
  /// [start] (inclusive) for [count] pages (default: to the end). Returns the
  /// encoded bytes in page order. See [exportPage] for the parameters.
  static Future<List<Uint8List>> exportPages(
    PdfDocument document, {
    int start = 0,
    int? count,
    PdfRasterFormat format = PdfRasterFormat.png,
    double dpi = 150,
    double? scale,
    Color pageColor = const Color(0xFFFFFFFF),
    bool annotations = true,
    int jpegQuality = 90,
  }) async {
    final end = count == null
        ? document.pageCount
        : (start + count).clamp(0, document.pageCount);
    if (start < 0 || start > document.pageCount) {
      throw RangeError.range(start, 0, document.pageCount, 'start');
    }
    final out = <Uint8List>[];
    for (var i = start; i < end; i++) {
      out.add(await exportPage(
        document.page(i),
        format: format,
        dpi: dpi,
        scale: scale,
        pageColor: pageColor,
        annotations: annotations,
        jpegQuality: jpegQuality,
      ));
    }
    return out;
  }

  static Future<Uint8List> _encode(
    ui.Image image,
    PdfRasterFormat format,
    Color pageColor,
    int jpegQuality,
  ) async {
    switch (format) {
      case PdfRasterFormat.png:
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) {
          throw StateError('failed to encode page as PNG');
        }
        return data.buffer.asUint8List();
      case PdfRasterFormat.jpeg:
        // dart:ui has no JPEG encoder, so pull raw RGBA and hand it to the
        // image package. JPEG carries no alpha; flatten onto the page colour
        // so transparent margins read as paper, not black.
        final raw =
            await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (raw == null) {
          throw StateError('failed to read page pixels for JPEG encoding');
        }
        final rgba = Uint8List.fromList(
            raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes));
        _flattenOnto(rgba, pageColor);
        final frame = img.Image.fromBytes(
          width: image.width,
          height: image.height,
          bytes: rgba.buffer,
          numChannels: 4,
          order: img.ChannelOrder.rgba,
        );
        return img.encodeJpg(frame, quality: jpegQuality.clamp(1, 100));
    }
  }

  /// Alpha-composites the RGBA [pixels] (straight alpha) over [background] in
  /// place, leaving them opaque — JPEG cannot store the alpha channel.
  static void _flattenOnto(Uint8List pixels, Color background) {
    final br = (background.r * 255).round();
    final bg = (background.g * 255).round();
    final bb = (background.b * 255).round();
    for (var i = 0; i < pixels.length; i += 4) {
      final a = pixels[i + 3];
      if (a == 255) continue;
      final ia = 255 - a;
      pixels[i] = (pixels[i] * a + br * ia) ~/ 255;
      pixels[i + 1] = (pixels[i + 1] * a + bg * ia) ~/ 255;
      pixels[i + 2] = (pixels[i + 2] * a + bb * ia) ~/ 255;
      pixels[i + 3] = 255;
    }
  }
}
