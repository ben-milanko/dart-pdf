import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdf_document/pdf_document.dart';

/// Persists low-resolution page rasters to a [PdfDiskCache] so a document
/// reopened in a later session shows soft page content immediately —
/// instead of blank paper — while the (heavy, twice-over-the-content-
/// stream) full render computes.
///
/// This is the raster half of the library's on-disk caching, layered on
/// the same pluggable [PdfCacheStore] seam as the text cache. It only
/// stores the small preview rasters (see [PdfPagePreviewCache]) — a few
/// tens of KB of PNG per page — not full-resolution page images, so the
/// budget stays modest and the win (instant navigable content on cold
/// open) is large. Rasters are encoded as PNG via [ui.Image] (no extra
/// dependency) and decoded back with [ui.instantiateImageCodec].
///
/// A cache is bound to one document via [documentKey]; call [forDocument]
/// to derive a view for the currently-open file (its [pdfContentKey], or
/// a host-supplied stable id). With an empty key every operation no-ops,
/// so an un-bound cache is harmless.
class PdfRasterCache {
  PdfRasterCache(this.cache, {this.documentKey = ''});

  /// The byte store these rasters persist into.
  final PdfDiskCache cache;

  /// Identifies the document these rasters belong to; empty disables I/O.
  final String documentKey;

  /// A view of this cache bound to [documentKey] — share one underlying
  /// [PdfDiskCache] (and its byte budget) across every document the
  /// session opens.
  PdfRasterCache forDocument(String documentKey) =>
      PdfRasterCache(cache, documentKey: documentKey);

  String _key(int pageIndex) => '$documentKey/$pageIndex';

  /// The stored preview for [pageIndex] decoded to a [ui.Image] the caller
  /// owns (and must dispose), or null on a miss / decode failure.
  Future<ui.Image?> loadPreview(int pageIndex) async {
    if (documentKey.isEmpty) return null;
    final bytes = await cache.read(_key(pageIndex));
    if (bytes == null) return null;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final frame = await codec.getNextFrame();
        return frame.image;
      } finally {
        codec.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  /// Encodes [image] as PNG and writes it as [pageIndex]'s preview.
  /// Best-effort and fire-and-forget at the call sites; [image] stays
  /// owned by the caller.
  Future<void> storePreview(int pageIndex, ui.Image image) async {
    if (documentKey.isEmpty) return;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;
      await cache.write(_key(pageIndex), data.buffer.asUint8List());
    } catch (_) {
      // a readback can fail mid page-swap; a missing preview just means
      // the page renders blank-then-full as it did before this cache
    }
  }

  /// Reads the raw stored PNG bytes for [pageIndex] (test hook / advanced
  /// callers that decode themselves).
  Future<Uint8List?> readBytes(int pageIndex) =>
      documentKey.isEmpty ? Future.value(null) : cache.read(_key(pageIndex));
}
