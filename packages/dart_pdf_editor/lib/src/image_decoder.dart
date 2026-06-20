import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

/// Map key for a decoded image. Image XObjects key by stream identity —
/// the xref cache hands back the same [CosStream] on every interpretation
/// pass. Inline images are re-synthesized each pass, so they key by value
/// ([PdfInlineImageKey]) or the paint-time lookup could never hit.
Object pdfImageKey(PdfImageRequest request) =>
    request.isInline ? PdfInlineImageKey(request.stream) : request.stream;

/// Value identity for an inline image: its parameter dictionary plus the
/// raw data bytes.
class PdfInlineImageKey {
  PdfInlineImageKey(CosStream stream)
      : _dict = stream.dictionary.toString(),
        _data = stream.rawBytes;

  final String _dict;
  final Uint8List _data;

  @override
  bool operator ==(Object other) {
    if (other is! PdfInlineImageKey) return false;
    if (other._dict != _dict || other._data.length != _data.length) {
      return false;
    }
    for (var i = 0; i < _data.length; i++) {
      if (other._data[i] != _data[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(_dict, _data.length,
      _data.isEmpty ? 0 : _data.first, _data.isEmpty ? 0 : _data.last);
}

/// A process-wide cache of decoded image XObjects, so repeat renders of a
/// page reuse the already-decoded [ui.Image] instead of re-running the
/// codec. The same image is decoded once and shared by every render path —
/// the on-screen page, its thumbnail, the fast-scroll preview, the
/// eyedropper sampler, and re-renders after a zoom/page-colour/annotation
/// change — for the life of the document.
///
/// Lifetime mirrors the other [ui.Image] caches in this package
/// ([PdfPagePreviewCache], the thumbnail strip): the cache holds a master
/// and hands out [ui.Image.clone]s, so a caller disposing its copy (or
/// eviction dropping the master) can never pull pixels out from under a
/// recorded picture that is still painting.
///
/// Keys are image identity: an XObject keys by its [CosStream] (the xref
/// cache returns the same instance across passes and renders of one
/// document), an inline image by its content ([PdfInlineImageKey]). A new
/// document revision opens fresh streams, so its images miss and re-decode;
/// the dead entries age out under the byte budget. Decoded pixels vary
/// enormously in size (a thumbnail icon vs. a full-page scan), so eviction
/// is by total decoded bytes ([maxBytes]), oldest-touched first, not by a
/// flat entry count.
class PdfImageCache {
  PdfImageCache({this.maxBytes = 256 * 1024 * 1024});

  /// The shared cache every render path consults by default.
  static final PdfImageCache instance = PdfImageCache();

  /// Eviction budget: the cache holds at most this many bytes of decoded
  /// pixels (estimated as width × height × 4), evicting the least-recently
  /// used master first.
  final int maxBytes;

  // LinkedHashMap insertion order is the LRU order: a hit re-inserts to the
  // back, eviction takes the front.
  final _entries = <Object, _CachedImage>{};
  int _bytes = 0;
  bool _disposed = false;

  /// A clone of the cached image for [key] (the caller owns and disposes
  /// it), or null on a miss. Counts as a use for LRU ordering.
  ui.Image? take(Object key) {
    final entry = _entries.remove(key);
    if (entry == null) return null;
    _entries[key] = entry; // touch
    return entry.image.clone();
  }

  /// Stores [master] under [key] (the cache takes ownership of it) and
  /// returns a clone for the caller to use and dispose. The master stays
  /// cached until evicted.
  ui.Image put(Object key, ui.Image master) {
    if (_disposed) return master; // not cached; caller owns it outright
    _entries.remove(key)?.dispose(this);
    final entry = _CachedImage(master);
    _entries[key] = entry;
    _bytes += entry.bytes;
    // Keep at least the just-added entry even if it alone exceeds the
    // budget — it is still useful for this render's clones; it ages out on
    // the next insert.
    while (_bytes > maxBytes && _entries.length > 1) {
      _entries.remove(_entries.keys.first)!.dispose(this);
    }
    return master.clone();
  }

  /// Drops the cached master for [key] (e.g. an image whose stream changed).
  void evict(Object key) => _entries.remove(key)?.dispose(this);

  /// Empties the cache (a document close, a memory-pressure signal, test
  /// isolation). Outstanding clones the callers hold are unaffected.
  void clear() {
    for (final entry in _entries.values) {
      entry.image.dispose();
    }
    _entries.clear();
    _bytes = 0;
  }

  void dispose() {
    _disposed = true;
    clear();
  }

  /// Number of cached masters — for tests.
  @visibleForTesting
  int get debugLength => _entries.length;

  /// Estimated cached bytes — for tests.
  @visibleForTesting
  int get debugBytes => _bytes;
}

class _CachedImage {
  _CachedImage(this.image) : bytes = image.width * image.height * 4;

  final ui.Image image;
  final int bytes;

  void dispose(PdfImageCache cache) {
    cache._bytes -= bytes;
    image.dispose();
  }
}

/// Collects every image a page references, without painting anything.
class ImageCollector implements PdfDevice {
  final List<PdfImageRequest> streams = [];

  @override
  void drawImage(PdfImageRequest request) => streams.add(request);

  @override
  void save() {}
  @override
  void restore() {}
  @override
  void fillPath(PdfPath path, PdfColor color, PdfFillRule rule, double a) {}
  @override
  void fillPathGradient(
      PdfPath path, PdfFillRule rule, PdfGradient gradient, double a) {}
  @override
  void fillMesh(PdfMesh mesh, double a) {}
  @override
  void strokePath(PdfPath path, PdfColor color, PdfStroke stroke, double a) {}
  @override
  void clipPath(PdfPath path, PdfFillRule rule) {}
  @override
  void drawText(PdfTextRun run) {}
  @override
  void setBlendMode(PdfBlendMode mode) {}
  @override
  void beginGroup(double alpha, {bool knockout = false}) {}
  @override
  void endGroup() {}
  @override
  void beginSoftMasked() {}
  @override
  void endSoftMasked(
      {required bool luminosity,
      required PdfRect backdrop,
      required void Function() drawMask,
      double backdropLuminance = 0,
      double transferScale = 1,
      double transferOffset = 0}) {
    drawMask(); // mask groups can reference images that need decoding
  }
}

/// Decodes image XObjects to [ui.Image]s ahead of the (synchronous) paint.
///
/// The heavy lifting — turning an image stream into RGBA pixels — is pure
/// Dart and lives in `pdf_graphics`' [decodePdfImagePixels], so it can run on
/// a worker (off the UI thread, and on the web where there is no separate
/// raster thread). This function is the thin `dart:ui` layer over it:
/// [decodePdfImagePixels] for everything it can decode, with the residual
/// platform-JPEG path (a non-CMYK DCTDecode base) handled here.
///
/// A request that carries worker-decoded pixels ([PdfImageRequest.decoded],
/// already premultiplied) bypasses the decode and only runs the engine codec —
/// the point of the offload — and the result still caches by content, so a
/// later local render of the same image hits the cache.
///
/// When a [cache] is given, decodes are shared across renders: a hit
/// returns a clone, a miss decodes once, caches the master, and returns a
/// clone. Without a cache every call decodes afresh (the cold path used by
/// probes and direct tests).
Future<Map<Object, ui.Image>> decodeImages(
    CosDocument cos, Iterable<PdfImageRequest> requests,
    {PdfImageCache? cache}) async {
  final out = <Object, ui.Image>{};
  for (final request in requests) {
    final key = pdfImageKey(request);
    if (out.containsKey(key)) continue;
    final hit = cache?.take(key);
    if (hit != null) {
      out[key] = hit;
      continue;
    }
    try {
      final decoded = request.decoded;
      final image = decoded != null
          ? await _imageFromPremultiplied(
              decoded.rgba, decoded.width, decoded.height)
          : await _decodeOne(cos, request.stream);
      if (image != null) {
        out[key] = cache == null ? image : cache.put(key, image);
      }
    } on Exception {
      // undecodable image: the device will skip it
    }
  }
  return out;
}

/// Decodes one image XObject to a [ui.Image]. The pure-Dart decode
/// ([decodePdfImagePixels]) covers everything but the platform JPEG codec;
/// the residual path here decodes a non-CMYK DCTDecode base and applies
/// /Decode, color-key, and soft/stencil masks on top.
Future<ui.Image?> _decodeOne(CosDocument cos, CosStream stream) async {
  final pixels = decodePdfImagePixels(cos, stream);
  if (pixels != null) {
    return _imageFromPremultiplied(pixels.rgba, pixels.width, pixels.height);
  }

  final dict = stream.dictionary;

  // A purely-decoded base that only returned null because its /SMask is
  // DCT-encoded: decode the base here and apply the JPEG mask via the codec
  // (e.g. a CMYK or Flate image under a DCTDecode soft mask).
  final pureBase = decodePdfImageBase(cos, stream);
  if (pureBase != null) {
    final mask = await _resolveDartUiMask(cos, dict);
    if (mask == null) {
      return pureBase.opaque
          ? _imageFromPremultiplied(
              pureBase.rgba, pureBase.width, pureBase.height)
          : _imageFromStraight(pureBase.rgba, pureBase.width, pureBase.height);
    }
    final m =
        pdfApplyImageAlpha(pureBase.rgba, pureBase.width, pureBase.height, mask);
    return _imageFromStraight(m.$1, m.$2, m.$3);
  }

  if (cos.resolve(dict['ImageMask']) == const CosBoolean(true)) return null;
  final filters = pdfImageFilters(cos, dict);
  final dctName = filters.contains('DCTDecode')
      ? 'DCTDecode'
      : filters.contains('DCT')
          ? 'DCT'
          : null;
  if (dctName == null) return null; // not a JPEG base; nothing more to try

  // undo any wrapping filters (e.g. [/FlateDecode /DCTDecode])
  final jpeg = cos.decodeStreamData(stream, stopBeforeFilter: dctName);
  final codec = await ui.instantiateImageCodec(jpeg);
  final base = (await codec.getNextFrame()).image;
  final mask = await _resolveDartUiMask(cos, dict);
  // /Decode and color-key /Mask apply to the decoded samples; gray
  // JPEGs decode to RGBA with the sample replicated, so one channel
  // stands in for the raw sample either way.
  final components = switch (pdfImageColorFamily(cos, dict)) {
    'DeviceGray' => 1,
    'DeviceRGB' => 3,
    _ => 0,
  };
  final ranges =
      components > 0 ? pdfImageDecodeRanges(cos, dict, components) : null;
  final colorKey =
      components > 0 ? pdfImageColorKeyRanges(cos, dict, components) : null;
  if (mask == null && ranges == null && colorKey == null) return base;
  final raw = await base.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (raw == null) return base;
  final rgba = Uint8List.fromList(raw.buffer.asUint8List());
  if (ranges != null || colorKey != null) {
    pdfApplyImageDecodeAndColorKey(rgba, components, ranges, colorKey);
  }
  final m = mask == null
      ? (rgba, base.width, base.height)
      : pdfApplyImageAlpha(rgba, base.width, base.height, mask);
  return _imageFromStraight(m.$1, m.$2, m.$3);
}

/// The soft/stencil mask for a platform-decoded JPEG. A DCT-encoded /SMask is
/// decoded with the platform codec here (the one mask branch that needs
/// `dart:ui`); otherwise the pure non-DCT soft mask, then the stencil /Mask.
Future<PdfImageSoftMask?> _resolveDartUiMask(
    CosDocument cos, CosDictionary dict) async {
  final dctBytes = pdfImageDctSoftMaskBytes(cos, dict);
  if (dctBytes != null) {
    try {
      final codec = await ui.instantiateImageCodec(dctBytes);
      final image = (await codec.getNextFrame()).image;
      final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (raw != null) {
        final rgba = raw.buffer.asUint8List();
        final alpha = Uint8List(image.width * image.height);
        for (var i = 0; i < alpha.length; i++) {
          alpha[i] = rgba[i * 4]; // gray: any channel works
        }
        return PdfImageSoftMask(alpha, image.width, image.height);
      }
    } on Exception {
      // fall through to a stencil /Mask, like the pre-extraction code did
    }
  }
  return pdfImageSoftMask(cos, dict) ?? pdfImageStencilMask(cos, dict);
}

/// Hands already-premultiplied RGBA straight to the engine codec — the only
/// per-image UI-thread cost once the decode itself runs on a worker.
Future<ui.Image> _imageFromPremultiplied(
    Uint8List rgba, int width, int height) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
      rgba, width, height, ui.PixelFormat.rgba8888, completer.complete);
  return completer.future;
}

/// Premultiplies straight-alpha RGBA (the JPEG post-process path produces it),
/// then hands it to the engine codec.
Future<ui.Image> _imageFromStraight(Uint8List rgba, int width, int height) {
  pdfPremultiplyRgba(rgba);
  return _imageFromPremultiplied(rgba, width, height);
}
