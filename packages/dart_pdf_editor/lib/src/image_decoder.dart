import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

import 'browser_jpeg_decode.dart';
import 'budgeted_cache.dart';
import 'performance_policy.dart';

/// Map key for a decoded image. Image XObjects key by stream identity -
/// the xref cache hands back the same [CosStream] on every interpretation
/// pass. Inline images are re-synthesized each pass, so they key by value
/// ([PdfInlineImageKey]) or the paint-time lookup could never hit.
///
/// A request carrying worker-decoded pixels ([PdfImageRequest.decoded]) folds
/// those pixels' dimensions into the key: the worker caps each image to display
/// resolution (see `serializeCommands`'s `maxImagePixelRatio`), so the *same*
/// source image can be decoded at two sizes - sharp for the on-screen page,
/// tiny for its 200px preview. Keying by content alone would let one resolution
/// evict and stand in for the other (a blurry page, or a needlessly huge
/// preview); the dimensions disambiguate them so each caches on its own.
Object pdfImageKey(PdfImageRequest request) {
  if (!request.isInline) return request.stream;
  final content = PdfInlineImageKey(request.stream);
  final decoded = request.decoded;
  return decoded == null
      ? content
      : PdfSizedImageKey(content, decoded.width, decoded.height);
}

/// A content key qualified by a decoded resolution - see [pdfImageKey].
///
/// The wrapped [content] is an inline image's value key ([PdfInlineImageKey])
/// or an XObject's stream identity ([CosStream]). Two renders that decode the
/// same source image to different sizes - a sharp on-screen page and a tiny
/// preview, or two zoom levels capped to different display resolutions - must
/// not evict or stand in for each other in the shared [PdfImageCache]; folding
/// the size into the key keeps each on its own.
class PdfSizedImageKey {
  PdfSizedImageKey(this.content, this.width, this.height);

  final Object content;
  final int width;
  final int height;

  @override
  bool operator ==(Object other) =>
      other is PdfSizedImageKey &&
      other.width == width &&
      other.height == height &&
      other.content == content;

  @override
  int get hashCode => Object.hash(content, width, height);
}

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
/// codec. The same image is decoded once and shared by every render path -
/// the on-screen page, its thumbnail, the fast-scroll preview, the
/// eyedropper sampler, and re-renders after a zoom/page-colour/annotation
/// change - for the life of the document.
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
  /// A cache holding at most [maxBytes] of decoded pixels, defaulting to the
  /// budget this platform can afford ([pdfDefaultImageCacheBytes]).
  ///
  /// [registerForPressure] wires the cache into the coordinated
  /// [PdfCacheRegistry] pressure path; only the process-wide [instance] sets
  /// it, so short-lived test caches stay out of the registry.
  PdfImageCache({int? maxBytes, bool registerForPressure = false})
      : _cache = PdfBudgetedCache<Object, ui.Image>(
          weigher: (image) => image.width * image.height * 4,
          maxWeight: maxBytes ?? pdfDefaultImageCacheBytes(),
          cloner: (image) => image.clone(),
          disposer: (image) => image.dispose(),
          clearsUnderMemoryPressure: registerForPressure,
          debugLabel: 'decoded-image',
        );

  /// The shared cache every render path consults by default.
  ///
  /// A host that knows better than the platform default - it has profiled its
  /// own documents, or it is sharing a process with something hungrier - can
  /// say so at startup:
  ///
  /// ```dart
  /// PdfImageCache.instance.maxBytes = 64 * 1024 * 1024;
  /// ```
  static final PdfImageCache instance =
      PdfImageCache(registerForPressure: true);

  // The one budgeted LRU under every in-package cache; the byte budget, LRU
  // order, clone-on-take and dispose-on-evict all live there (and are
  // property-tested in budgeted_cache_test.dart).
  final PdfBudgetedCache<Object, ui.Image> _cache;

  /// Eviction budget: the cache holds at most this many bytes of decoded
  /// pixels (estimated as width × height × 4), evicting the least-recently
  /// used master first. Lowering it trims to the new budget at once.
  int get maxBytes => _cache.maxWeight;
  set maxBytes(int value) => _cache.maxWeight = value;

  /// A clone of the cached image for [key] (the caller owns and disposes
  /// it), or null on a miss. Counts as a use for LRU ordering.
  ui.Image? take(Object key) => _cache.take(key);

  /// Stores [master] under [key] (the cache takes ownership of it) and
  /// returns a clone for the caller to use and dispose. The master stays
  /// cached until evicted.
  ui.Image put(Object key, ui.Image master) => _cache.putAndClone(key, master);

  /// Drops the cached master for [key] (e.g. an image whose stream changed).
  void evict(Object key) => _cache.evict(key);

  /// Empties the cache (a document close, a memory-pressure signal, test
  /// isolation). Outstanding clones the callers hold are unaffected.
  void clear() => _cache.clear();

  void dispose() => _cache.dispose();

  /// Estimated bytes of decoded pixels held right now, against [maxBytes].
  ///
  /// Occupancy, not a reservation: a document whose images fit well under the
  /// budget only ever costs what it uses.
  int get bytes => _cache.weight;

  /// Number of cached masters - for tests.
  @visibleForTesting
  int get debugLength => _cache.length;

  /// Lookups served from cached pixels - for tests and the budget benchmark.
  @visibleForTesting
  int get debugHits => _cache.hits;

  /// Lookups that had to decode - for tests and the budget benchmark.
  @visibleForTesting
  int get debugMisses => _cache.misses;

  /// Zeroes the hit/miss counters (they survive [clear], which is a cache
  /// operation, not a new measurement).
  @visibleForTesting
  void debugResetCounters() => _cache.resetCounters();
}

/// Collects every image a page references, without painting anything.
class ImageCollector implements PdfDevice, PdfTiledCellSink {
  final List<PdfImageRequest> streams = [];

  @override
  void drawImage(PdfImageRequest request) => streams.add(request);

  @override
  void drawTiledCell(PdfDrawTiledCellCommand command) =>
      // A cell's images decode once however many tiles stamp it.
      replayCommands(command.cellCommands, this);

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
  void setOverprint(
      {required bool fill, required bool stroke, required int mode}) {}
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
/// The heavy lifting - turning an image stream into RGBA pixels - is pure
/// Dart and lives in `pdf_graphics`' [decodePdfImagePixels], so it can run on
/// a worker (off the UI thread, and on the web where there is no separate
/// raster thread). This function is the thin `dart:ui` layer over it:
/// [decodePdfImagePixels] for everything it can decode, with the residual
/// platform-JPEG path (a non-CMYK DCTDecode base) handled here.
///
/// A request that carries worker-decoded pixels ([PdfImageRequest.decoded],
/// already premultiplied) bypasses the decode and only runs the engine codec -
/// the point of the offload - and the result still caches by content, so a
/// later local render of the same image hits the cache.
///
/// When a [cache] is given, decodes are shared across renders: a hit
/// returns a clone, a miss decodes once, caches the master, and returns a
/// clone. Without a cache every call decodes afresh (the cold path used by
/// probes and direct tests).
/// [maxImagePixelRatio] (screen pixels per page point, including the device
/// pixel ratio) caps each locally-decoded image to ~2× the pixels it covers on
/// screen, so a giant raster underlay on a CAD sheet is decoded (and cached,
/// and readback for its soft mask) at display resolution instead of its native
/// 100+ megapixels. This is the local-decode twin of the render worker's
/// `serializeCommands`'s `maxImagePixelRatio` - a non-CMYK JPEG needs the
/// platform codec and so can never be worker-decoded, so without this cap the
/// biggest images on the heaviest pages always decoded at full native size.
/// Null still applies the hard ceilings ([cappedImagePixelSize]'s 8192-px max
/// edge and 16 MP cap) so no path ever hands the engine a texture past the
/// common GPU limit; only the display-size refinement is skipped.
Future<Map<Object, ui.Image>> decodeImages(
    CosDocument cos, Iterable<PdfImageRequest> requests,
    {PdfImageCache? cache, double? maxImagePixelRatio}) async {
  final out = <Object, ui.Image>{};
  for (final request in requests) {
    final key = pdfImageKey(request);
    if (out.containsKey(key)) continue;
    // Worker-decoded pixels are already sized; only a local decode is capped.
    final target = request.decoded != null
        ? null
        : _decodeTarget(cos, request, maxImagePixelRatio);
    // The returned map keys by the ratio-independent [pdfImageKey] so the paint
    // side (which has no ratio) always matches. The shared cache keys by the
    // target size too, so two zoom levels of the same image cache separately.
    final cacheKey =
        target == null ? key : PdfSizedImageKey(key, target.$1, target.$2);
    final hit = cache?.take(cacheKey);
    if (hit != null) {
      out[key] = hit;
      continue;
    }
    try {
      final decoded = request.decoded;
      final image = decoded != null
          ? await _imageFromPremultiplied(
              decoded.rgba, decoded.width, decoded.height)
          : await _decodeOne(cos, request.stream,
              targetWidth: target?.$1, targetHeight: target?.$2);
      if (image != null) {
        out[key] = cache == null ? image : cache.put(cacheKey, image);
      }
    } on Exception {
      // undecodable image: the device will skip it
    }
  }
  return out;
}

/// The display-capped decode size for [request]'s image, or null to decode at
/// native resolution. Combines the image's native dimensions, its on-page
/// footprint (from [PdfImageRequest.transform]), and [ratio] through the shared
/// [cappedImagePixelSize] - the same cap the render worker applies - so the
/// local and worker paths agree on target sizes. With no [ratio] the hard
/// ceilings (8192-px max edge, 16 MP) still apply. Returns null when the cap is
/// a no-op (the image is already at or below the target), so those images keep
/// their byte-identical native decode and a bare cache key.
(int, int)? _decodeTarget(
    CosDocument cos, PdfImageRequest request, double? ratio) {
  final dict = request.stream.dictionary;
  final w = _intOrNull(cos.resolve(dict['Width']));
  final h = _intOrNull(cos.resolve(dict['Height']));
  if (w == null || h == null || w < 1 || h < 1) return null;
  final t = request.transform;
  // The unit image square maps to page space through [transform]; the edge
  // lengths in points are the column norms.
  final widthPts = math.sqrt(t.a * t.a + t.b * t.b);
  final heightPts = math.sqrt(t.c * t.c + t.d * t.d);
  final (tw, th) = ratio != null && ratio > 0 && widthPts > 0 && heightPts > 0
      ? cappedImagePixelSize(w, h, widthPts, heightPts, ratio)
      : _clampToCeilings(w, h);
  return (tw == w && th == h) ? null : (tw, th);
}

/// The ratio-free hard ceilings [cappedImagePixelSize] enforces (8192-px max
/// edge, 16 MP), so even a decode with no display ratio never exceeds the
/// common GPU max texture size or blows the decoded-image budget on one image.
(int, int) _clampToCeilings(int w, int h,
    {double maxDimension = 8192, int maxPixels = 1 << 24}) {
  var tw = w, th = h;
  final maxEdge = math.max(tw, th);
  if (maxEdge > maxDimension) {
    final s = maxDimension / maxEdge;
    tw = (tw * s).floor().clamp(1, w);
    th = (th * s).floor().clamp(1, h);
  }
  if (tw * th > maxPixels) {
    final s = math.sqrt(maxPixels / (tw * th));
    tw = (tw * s).floor().clamp(1, w);
    th = (th * s).floor().clamp(1, h);
  }
  return (tw, th);
}

int? _intOrNull(CosObject? o) => o is CosInteger ? o.value : null;

/// Decodes one image XObject to a [ui.Image]. The pure-Dart decode
/// ([decodePdfImagePixels]) covers everything but the platform JPEG codec;
/// the residual path here decodes a non-CMYK DCTDecode base and applies
/// /Decode, color-key, and soft/stencil masks on top.
///
/// [targetWidth]/[targetHeight], when set, decode the image at that display
/// size instead of its native resolution (see [_decodeTarget]) - the pure path
/// decodes scaled, the JPEG path asks the platform codec to downscale during
/// decode, and the soft mask is fitted to the base so the composited result
/// stays at the target size. The pixels are geometrically identical to a native
/// decode drawn through the same transform, just at fewer samples.
Future<ui.Image?> _decodeOne(CosDocument cos, CosStream stream,
    {int? targetWidth, int? targetHeight}) async {
  final scaled = targetWidth != null && targetHeight != null;
  final pixels = scaled
      ? decodePdfImage(cos, stream,
          targetWidth: targetWidth, targetHeight: targetHeight)
      : decodePdfImagePixels(cos, stream);
  if (pixels != null) {
    return _imageFromPremultiplied(pixels.rgba, pixels.width, pixels.height);
  }

  final dict = stream.dictionary;

  // A purely-decoded base that only returned null because its /SMask is
  // DCT-encoded: decode the base here and apply the JPEG mask via the codec
  // (e.g. a CMYK or Flate image under a DCTDecode soft mask).
  final pureBase = decodePdfImageBase(cos, stream);
  if (pureBase != null) {
    final mask = await _resolveDartUiMask(cos, dict,
        targetWidth: pureBase.width, targetHeight: pureBase.height);
    if (mask == null) {
      return pureBase.opaque
          ? _imageFromPremultiplied(
              pureBase.rgba, pureBase.width, pureBase.height)
          : _imageFromStraight(pureBase.rgba, pureBase.width, pureBase.height);
    }
    final fitted = _fitMask(mask, pureBase.width, pureBase.height);
    final m = pdfApplyImageAlpha(
        pureBase.rgba, pureBase.width, pureBase.height, fitted);
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
  // On web, decode through the browser's native codec first: it is far faster
  // than the engine's WASM codec under CanvasKit (a ~640 ms main-thread cost on
  // the reported doc) and lands a GPU image with no readback. The worker
  // already does this off-thread; this recovers the win on the main thread when
  // the worker declined - e.g. its scope lacked OffscreenCanvas. Returns null
  // off web and on any failure, falling through to the engine codec. #458.
  //
  // The platform codec downscales during decode when a target is given -
  // decisive on the web, where the alternative is decoding 100+ MP and reading
  // it back off the GPU for the soft-mask multiply.
  var base = scaled
      ? await decodeJpegWithBrowser(jpeg,
          targetWidth: targetWidth, targetHeight: targetHeight)
      : await decodeJpegWithBrowser(jpeg);
  if (base == null) {
    final codec = scaled
        ? await ui.instantiateImageCodec(jpeg,
            targetWidth: targetWidth, targetHeight: targetHeight)
        : await ui.instantiateImageCodec(jpeg);
    base = (await codec.getNextFrame()).image;
  }
  final mask = await _resolveDartUiMask(cos, dict,
      targetWidth: base.width, targetHeight: base.height);
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
      : pdfApplyImageAlpha(
          rgba, base.width, base.height, _fitMask(mask, base.width, base.height));
  return _imageFromStraight(m.$1, m.$2, m.$3);
}

/// The soft/stencil mask for a platform-decoded JPEG. A DCT-encoded /SMask is
/// decoded with the platform codec here (the one mask branch that needs
/// `dart:ui`); otherwise the pure non-DCT soft mask, then the stencil /Mask.
///
/// [targetWidth]/[targetHeight] is the size the base decoded to. The DCT mask
/// path decodes straight to it (the codec downscales); the pure paths decode at
/// the mask's own native size and are fitted to the base by the caller
/// ([_fitMask]) - so the whole composite lands at the target, never ballooning
/// back to a mask that is larger than the capped base.
Future<PdfImageSoftMask?> _resolveDartUiMask(CosDocument cos, CosDictionary dict,
    {int? targetWidth, int? targetHeight}) async {
  final dctBytes = pdfImageDctSoftMaskBytes(cos, dict);
  if (dctBytes != null) {
    try {
      final codec = targetWidth != null && targetHeight != null
          ? await ui.instantiateImageCodec(dctBytes,
              targetWidth: targetWidth, targetHeight: targetHeight)
          : await ui.instantiateImageCodec(dctBytes);
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

/// Nearest-samples [mask] down to at most [width]x[height] so the base image it
/// is applied to stays the composited size. [pdfApplyImageAlpha] upsamples the
/// *base* to the mask when the mask is larger - which would undo a display-res
/// cap on the base - so a mask that outsizes a capped base must be shrunk
/// first. A mask already within the base is returned untouched (the common
/// case, and the exact byte path when nothing is capped).
PdfImageSoftMask _fitMask(PdfImageSoftMask mask, int width, int height) {
  if (mask.width <= width && mask.height <= height) return mask;
  final tw = math.min(mask.width, width);
  final th = math.min(mask.height, height);
  final out = Uint8List(tw * th);
  for (var y = 0; y < th; y++) {
    final my = y * mask.height ~/ th;
    final row = my * mask.width;
    final orow = y * tw;
    for (var x = 0; x < tw; x++) {
      out[orow + x] = mask.alpha[row + (x * mask.width ~/ tw)];
    }
  }
  return PdfImageSoftMask(out, tw, th);
}

/// Hands already-premultiplied RGBA straight to the engine codec - the only
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
