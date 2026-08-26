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
import 'jpeg_accelerator.dart';
import 'perf_log.dart';
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
  final content = pdfImageContentKey(request);
  if (!request.isInline) return content;
  final width = request.decodedWidth;
  final height = request.decodedHeight;
  return width == null || height == null
      ? content
      : PdfSizedImageKey(content, width, height);
}

/// Identifies [request]'s source image irrespective of the resolution anything
/// decoded it at: stream identity for an XObject, a value key for an inline
/// image (whose stream is synthesized fresh on every interpretation pass).
///
/// This is the base the shared cache's key is built on - see [decodeImages],
/// which qualifies it with the size the image actually ends up at so every
/// path addressing the same pixels agrees on one entry.
Object pdfImageContentKey(PdfImageRequest request) {
  final content = request.sourceReference ??
      (request.isInline ? PdfInlineImageKey(request.stream) : request.stream);
  return request.isLuminosityMask ? (content, true) : content;
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

// A simple DCT grayscale /SMask can stay as its own GPU image and be applied
// when CanvasPdfDevice records the parent image. Keeping the association on the
// base ui.Image preserves the existing map API while avoiding an eager
// Picture.toImage barrier (and, more importantly, the old GPU readback + Dart
// pixel multiply). Every clone/dispose site for decoded images goes through the
// helpers below so the companion surface has exactly the base surface's
// lifetime.
final Expando<ui.Image> _gpuSoftMasks = Expando<ui.Image>('pdfGpuSoftMask');

ui.Image? pdfGpuSoftMaskOf(ui.Image image) => _gpuSoftMasks[image];

ui.Image clonePdfDecodedImage(ui.Image image) {
  final clone = image.clone();
  final mask = _gpuSoftMasks[image];
  if (mask != null) _gpuSoftMasks[clone] = mask.clone();
  return clone;
}

void disposePdfDecodedImage(ui.Image image) {
  final mask = _gpuSoftMasks[image];
  _gpuSoftMasks[image] = null;
  mask?.dispose();
  image.dispose();
}

int pdfDecodedImageBytes(ui.Image image) {
  final mask = _gpuSoftMasks[image];
  return (image.width * image.height +
          (mask == null ? 0 : mask.width * mask.height)) *
      4;
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
          weigher: pdfDecodedImageBytes,
          maxWeight: maxBytes ?? pdfDefaultImageCacheBytes(),
          cloner: clonePdfDecodedImage,
          disposer: disposePdfDecodedImage,
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
/// [imageDecodeHeadroom] is the linear resolution multiplier over the final
/// on-screen footprint. Local retained scenes keep the 2x default for future
/// zoom replay; worker command buffers pass 1x because their embedded-image
/// budget was recorded at 1x and deep zoom has its own region re-render.
///
/// When [deferSimpleDctSoftMasks] is true, a plain grayscale DCT /SMask stays
/// as a companion GPU image and [CanvasPdfDevice] applies it while recording
/// the draw. This avoids a GPU readback and a second upload. Set it to false
/// for consumers that inspect the returned image directly (for example with
/// [ui.Image.toByteData]) instead of drawing it through [CanvasPdfDevice].
///
/// When [retainDecodedPixels] is true, portable decoder results stay attached
/// to their requests until the retained-scene owner has uploaded or released
/// them. Platform-codec images still carry no CPU copy.
Future<Map<Object, ui.Image>> decodeImages(
    CosDocument cos, Iterable<PdfImageRequest> requests,
    {PdfImageCache? cache,
    double? maxImagePixelRatio,
    double imageDecodeHeadroom = 2,
    bool deferSimpleDctSoftMasks = true,
    bool retainDecodedPixels = false}) async {
  final batchClock = PdfPerfLog.enabled ? (Stopwatch()..start()) : null;
  installPdfJpegAccelerator();
  final grayDctImages = _DctGrayBatchCache();
  final out = <Object, ui.Image>{};
  // Plan the work synchronously first: dedup by key, resolve cache hits, and
  // collect the misses. Deciding all of this before the first await is what
  // makes the concurrent decode below safe - a repeated image is decoded once
  // and two tasks never race the cache on the same key (#454).
  final pending = <_PendingDecode>[];
  final seen = <Object>{};
  var cacheHits = 0;
  var requestCount = 0;
  for (final request in requests) {
    requestCount++;
    final key = pdfImageKey(request);
    if (!seen.add(key)) continue;
    final sourceRequest = _resolveReferencedImage(cos, request);
    // Worker-decoded pixels are already sized; only a local decode is capped.
    final target = sourceRequest.decoded != null
        ? null
        : _decodeTarget(
            cos,
            sourceRequest,
            maxImagePixelRatio,
            imageDecodeHeadroom,
          );
    // The returned map keys by the ratio-independent [pdfImageKey] so the paint
    // side (which has no ratio) always matches.
    //
    // The shared cache keys by the resolution the image *ends up at*, built on
    // the content key rather than on [key], and it does so on every path. That
    // is what lets a record carrying worker-decoded pixels and one that decodes
    // the same image locally address a single entry (#451). Before, the two
    // disagreed by shape: worker pixels produced a bare content key while a
    // capped local decode produced a sized one, so the same pixels could be
    // cached twice under different keys - and a record whose pixels were
    // dropped would miss the entry its own decode had populated. They happened
    // to coincide whenever the cap was a no-op, which hid it.
    final size = _decodedSize(cos, sourceRequest, target);
    final cacheKey = size == null
        ? key
        : PdfSizedImageKey(
            pdfImageContentKey(sourceRequest),
            size.$1,
            size.$2,
          );
    final hit = cache?.take(cacheKey);
    if (hit != null) {
      cacheHits++;
      if (retainDecodedPixels && sourceRequest.decoded == null) {
        pending.add(_PendingDecode(key, cacheKey, request, sourceRequest,
            target, deferSimpleDctSoftMasks,
            cachedImage: hit));
      } else {
        out[key] = hit;
      }
      continue;
    }
    pending.add(_PendingDecode(key, cacheKey, request, sourceRequest, target,
        deferSimpleDctSoftMasks));
  }
  final planUs = batchClock?.elapsedMicroseconds ?? 0;
  // Decode the misses concurrently. `instantiateImageCodec` / the browser codec
  // hand the work to a codec thread, so awaiting each image serially left that
  // thread idle between them - on an image-heavy page that serialisation was a
  // large slice of the first-paint wait (#454). Overlapping them keeps the
  // codec busy; the results land in a shared map and the distinct-key cache,
  // so single-threaded interleaving at the awaits cannot collide.
  try {
    await Future.wait(pending.map((p) async {
      try {
        final cachedImage = p.cachedImage;
        if (cachedImage != null) {
          out[p.key] = cachedImage;
          final pixels = await _decodePortablePixels(
            cos,
            p.request.stream,
            targetWidth: p.target?.$1,
            targetHeight: p.target?.$2,
            luminosityMask: p.request.isLuminosityMask,
          );
          if (pixels != null &&
              pixels.width == cachedImage.width &&
              pixels.height == cachedImage.height) {
            p.originalRequest.retainDecodedPixels(pixels);
          }
          return;
        }
        final decoded = p.request.decoded;
        ui.Image? image;
        if (decoded != null) {
          final clock = PdfPerfLog.enabled ? (Stopwatch()..start()) : null;
          image = await _imageFromPremultiplied(
              decoded.rgba, decoded.width, decoded.height);
          if (clock != null) {
            PdfPerfLog.log('image worker-upload '
                '${decoded.width}x${decoded.height} '
                'ms=${(clock.elapsedMicroseconds / 1000).toStringAsFixed(1)}');
          }
        } else {
          image = await _decodeOne(cos, p.request.stream,
              targetWidth: p.target?.$1,
              targetHeight: p.target?.$2,
              luminosityMask: p.request.isLuminosityMask,
              deferSimpleDctSoftMask: p.deferSimpleDctSoftMask,
              grayDctImages: grayDctImages,
              onDecodedPixels: retainDecodedPixels
                  ? p.originalRequest.retainDecodedPixels
                  : null);
        }
        if (image != null) {
          out[p.key] = cache == null ? image : cache.put(p.cacheKey, image);
        }
      } on Exception catch (error) {
        if (PdfPerfLog.enabled) {
          PdfPerfLog.log('image decode-failed '
              'family=${pdfImageColorFamily(cos, p.request.stream.dictionary)} '
              'filters=${pdfImageFilters(cos, p.request.stream.dictionary).join(',')} '
              'target=${p.target?.$1 ?? 0}x${p.target?.$2 ?? 0} '
              'error=$error');
        }
        // undecodable image: the device will skip it
      }
    }));
  } finally {
    await grayDctImages.dispose();
  }
  if (batchClock != null) {
    PdfPerfLog.log('image batch '
        'requests=$requestCount unique=${seen.length} hits=$cacheHits '
        'pending=${pending.length} '
        'plan=${(planUs / 1000).toStringAsFixed(1)}ms '
        'work=${((batchClock.elapsedMicroseconds - planUs) / 1000).toStringAsFixed(1)}ms '
        'total=${(batchClock.elapsedMicroseconds / 1000).toStringAsFixed(1)}ms');
  }
  return out;
}

PdfImageRequest _resolveReferencedImage(
  CosDocument cos,
  PdfImageRequest request,
) {
  final reference = request.sourceReference;
  if (reference == null) return request;
  final stream = cos.resolve(reference);
  if (stream is! CosStream) return request;
  return PdfImageRequest(
    stream: stream,
    transform: request.transform,
    alpha: request.alpha,
    isStencil: request.isStencil,
    stencilColor: request.stencilColor,
    isInline: false,
    isLuminosityMask: request.isLuminosityMask,
    decoded: request.decoded,
    sourceReference: reference,
  );
}

/// One image whose decode was deferred so [decodeImages] can run the misses
/// concurrently. Holds everything the synchronous planning pass resolved.
class _PendingDecode {
  _PendingDecode(this.key, this.cacheKey, this.originalRequest, this.request,
      this.target, this.deferSimpleDctSoftMask,
      {this.cachedImage});
  final Object key;
  final Object cacheKey;
  final PdfImageRequest originalRequest;
  final PdfImageRequest request;
  final (int, int)? target;
  final bool deferSimpleDctSoftMask;
  final ui.Image? cachedImage;
}

final class _DctGrayBatchKey {
  const _DctGrayBatchKey(this.stream, this.width, this.height);

  final CosStream stream;
  final int? width;
  final int? height;

  @override
  bool operator ==(Object other) =>
      other is _DctGrayBatchKey &&
      identical(stream, other.stream) &&
      width == other.width &&
      height == other.height;

  @override
  int get hashCode => Object.hash(identityHashCode(stream), width, height);
}

/// Shares one grayscale JPEG decode/upload between an XObject used directly
/// and the same XObject reused as another image's `/SMask` in one page batch.
/// Every caller receives a clone so normal image-cache disposal stays local.
final class _DctGrayBatchCache {
  final Map<_DctGrayBatchKey, Future<ui.Image?>> _masters = {};

  Future<ui.Image?> take(
    CosStream stream,
    int? width,
    int? height,
    Future<ui.Image?> Function() decode,
  ) async {
    final key = _DctGrayBatchKey(stream, width, height);
    final master = await _masters.putIfAbsent(key, () async {
      try {
        return await decode();
      } on Exception {
        return null;
      }
    });
    return master?.clone();
  }

  Future<void> dispose() async {
    for (final future in _masters.values) {
      (await future)?.dispose();
    }
    _masters.clear();
  }
}

/// The resolution [request]'s image ends up at, whichever path produced it:
/// the pixels a worker already decoded, an explicit local [target], or the
/// image's native size when nothing caps it. Null when the source declares no
/// usable dimensions and there are no decoded pixels to measure.
///
/// [decodeImages] folds this into the shared cache key so all three paths
/// address one entry - see the note there. Deliberately separate from
/// [_decodeTarget]: that one answers "what should I ask the codec for" and
/// keeps returning null for a no-op cap (so those images keep their
/// byte-identical native decode), while this answers "what size will the
/// result be", which is the question the cache key needs.
(int, int)? _decodedSize(
    CosDocument cos, PdfImageRequest request, (int, int)? target) {
  final decoded = request.decoded;
  if (decoded != null) return (decoded.width, decoded.height);
  if (target != null) return target;
  return _nativeSize(cos, request);
}

/// [request]'s declared source dimensions, or null when absent or degenerate.
(int, int)? _nativeSize(CosDocument cos, PdfImageRequest request) {
  final dict = request.stream.dictionary;
  final w = _intOrNull(cos.resolve(dict['Width']));
  final h = _intOrNull(cos.resolve(dict['Height']));
  if (w == null || h == null || w < 1 || h < 1) return null;
  return (w, h);
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
  CosDocument cos,
  PdfImageRequest request,
  double? ratio,
  double headroom,
) {
  final native = _nativeSize(cos, request);
  if (native == null) return null;
  final (w, h) = native;
  final t = request.transform;
  // The unit image square maps to page space through [transform]; the edge
  // lengths in points are the column norms.
  final widthPts = math.sqrt(t.a * t.a + t.b * t.b);
  final heightPts = math.sqrt(t.c * t.c + t.d * t.d);
  final (tw, th) = ratio != null && ratio > 0 && widthPts > 0 && heightPts > 0
      ? cappedImagePixelSize(w, h, widthPts, heightPts, ratio,
          headroom: headroom)
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

Future<PdfDecodedPixels?> _decodePortablePixels(
  CosDocument cos,
  CosStream stream, {
  int? targetWidth,
  int? targetHeight,
  required bool luminosityMask,
}) async {
  final filters = pdfImageFilters(cos, stream.dictionary);
  // The UI-side residual path owns bases that a worker intentionally left for
  // the platform JPEG codec (notably Flate DeviceN under a DCT soft mask).
  // Warm a simple Flate base with the same native browser inflater used for
  // portable masks before entering the synchronous colour conversion below.
  await _seedBrowserFlateImage(cos, stream, filters);
  if (pdfImageDctSoftMaskBytes(cos, stream.dictionary) != null) return null;
  return targetWidth != null && targetHeight != null
      ? decodePdfImage(
          cos,
          stream,
          targetWidth: targetWidth,
          targetHeight: targetHeight,
          luminosityMask: luminosityMask,
        )
      : decodePdfImagePixels(
          cos,
          stream,
          luminosityMask: luminosityMask,
        );
}

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
    {int? targetWidth,
    int? targetHeight,
    bool luminosityMask = false,
    bool deferSimpleDctSoftMask = true,
    _DctGrayBatchCache? grayDctImages,
    void Function(PdfDecodedPixels)? onDecodedPixels}) async {
  final scaled = targetWidth != null && targetHeight != null;
  final dict = stream.dictionary;
  final filters = pdfImageFilters(cos, dict);
  final dctMaskBytes = pdfImageDctSoftMaskBytes(cos, dict);
  // pdf_graphics can decode DCT masks portably for worker isolates. Once back
  // in a dart:ui isolate, keep the platform-codec path: it avoids running the
  // JPEG decoder synchronously here and lets the engine/browser codec handle
  // entropy decode before the unavoidable alpha readback.
  final pureClock = PdfPerfLog.enabled ? (Stopwatch()..start()) : null;
  final pixels = await _decodePortablePixels(
    cos,
    stream,
    targetWidth: targetWidth,
    targetHeight: targetHeight,
    luminosityMask: luminosityMask,
  );
  if (pixels != null) {
    onDecodedPixels?.call(pixels);
    final decodeMs =
        pureClock == null ? null : pureClock.elapsedMicroseconds / 1000.0;
    final uploadClock = PdfPerfLog.enabled ? (Stopwatch()..start()) : null;
    final image =
        await _imageFromPremultiplied(pixels.rgba, pixels.width, pixels.height);
    if (pureClock != null && uploadClock != null) {
      PdfPerfLog.log('image pure '
          'family=${pdfImageColorFamily(cos, dict)} '
          '${pixels.width}x${pixels.height} '
          'decode=${decodeMs!.toStringAsFixed(1)}ms '
          'upload=${(uploadClock.elapsedMicroseconds / 1000).toStringAsFixed(1)}ms');
    }
    return image;
  }

  // A purely-decoded base that only returned null because its /SMask is
  // DCT-encoded: decode the base here and apply the JPEG mask via the codec
  // (e.g. a CMYK or Flate image under a DCTDecode soft mask).
  final baseClock = dctMaskBytes != null && PdfPerfLog.enabled
      ? (Stopwatch()..start())
      : null;
  var pureBase = decodePdfImageBase(
    cos,
    stream,
    targetWidth: targetWidth,
    targetHeight: targetHeight,
    luminosityMask: luminosityMask,
  );
  if (baseClock != null) {
    PdfPerfLog.log('softmask base '
        'family=${pdfImageColorFamily(cos, dict)} '
        'target=${targetWidth ?? 0}x${targetHeight ?? 0} '
        'result=${pureBase?.width ?? 0}x${pureBase?.height ?? 0} '
        'ms=${(baseClock.elapsedMicroseconds / 1000).toStringAsFixed(1)}');
  }
  // decodePdfImagePixels cannot cross a DCT soft mask, so the generic scaled
  // façade above returns null and this split-base path takes over. Preserve
  // the caller's display cap here too: these bases are opaque (the mask is
  // separate), so area-averaging their straight RGBA is identical to the
  // premultiplied helper and avoids uploading/masking four times the pixels
  // on a worker replay configured for 1x headroom.
  if (pureBase != null &&
      pureBase.opaque &&
      scaled &&
      (pureBase.width != targetWidth || pureBase.height != targetHeight)) {
    final downsampled = downsamplePdfDecodedPixels(
      PdfDecodedPixels(pureBase.rgba, pureBase.width, pureBase.height),
      targetWidth,
      targetHeight,
    );
    pureBase = PdfImageBase(
      downsampled.rgba,
      downsampled.width,
      downsampled.height,
      opaque: true,
    );
  }
  if (pureBase != null) {
    // The common DCT /SMask shape needs no CPU access to the mask samples.
    // Decode both surfaces through the platform codec and let the rendering
    // backend apply the grayscale mask with dstIn. The old path below pulled
    // the mask texture back to RGBA, copied it, multiplied every base pixel on
    // the UI isolate, then uploaded the composite again - hundreds of
    // milliseconds on the large real-world sheets this renderer targets.
    // /Matte and non-default /Decode need per-pixel colour correction, so they
    // deliberately keep the established CPU path.
    final uploadClock = PdfPerfLog.enabled ? (Stopwatch()..start()) : null;
    final baseImage = pureBase.opaque
        ? await _imageFromPremultiplied(
            pureBase.rgba, pureBase.width, pureBase.height)
        : await _imageFromStraight(
            pureBase.rgba, pureBase.width, pureBase.height);
    if (uploadClock != null) {
      PdfPerfLog.log('softmask base-upload '
          '${pureBase.width}x${pureBase.height} '
          'ms=${(uploadClock.elapsedMicroseconds / 1000).toStringAsFixed(1)}');
    }
    final gpuMask = deferSimpleDctSoftMask
        ? await _decodeSimpleSoftMaskImage(
            cos,
            dict,
            baseImage,
            grayDctImages: grayDctImages,
          )
        : null;
    if (gpuMask != null) {
      _gpuSoftMasks[baseImage] = gpuMask;
      return baseImage;
    }
    baseImage.dispose();
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
      pureBase.rgba,
      pureBase.width,
      pureBase.height,
      fitted,
      premultiply: true,
    );
    return _imageFromPremultiplied(m.$1, m.$2, m.$3);
  }

  if (cos.resolve(dict['ImageMask']) == const CosBoolean(true)) return null;
  final dctName = filters.contains('DCTDecode')
      ? 'DCTDecode'
      : filters.contains('DCT')
          ? 'DCT'
          : null;
  if (dctName == null) return null; // not a JPEG base; nothing more to try

  // undo any wrapping filters (e.g. [/FlateDecode /DCTDecode])
  final jpeg = cos.decodeStreamData(stream, stopBeforeFilter: dctName);
  final colorFamily = pdfImageColorFamily(cos, dict);
  final acceleratedGrayRanges =
      colorFamily == 'DeviceGray' ? pdfImageDecodeRanges(cos, dict, 1) : null;
  final acceleratedGrayColorKey =
      colorFamily == 'DeviceGray' ? pdfImageColorKeyRanges(cos, dict, 1) : null;
  // Grayscale JPEGs occur both as direct images and as the image inside a
  // transparency-group soft mask. The browser ImageBitmap path is excellent
  // for colour JPEGs that can stay GPU-resident, but these one-channel images
  // were already being decoded by libjpeg-turbo when used as a direct /SMask
  // and then decoded a second time through ImageBitmap when the same XObject
  // appeared in the mask group's command stream. Reuse the same accelerator
  // for an ordinary, semantically plain DeviceGray DCT image. The strict gate
  // leaves /Decode, colour-key, and nested-mask semantics on the established
  // generic path below.
  if (colorFamily == 'DeviceGray' &&
      acceleratedGrayRanges == null &&
      acceleratedGrayColorKey == null &&
      cos.resolve(dict['SMask']) is! CosStream &&
      cos.resolve(dict['Mask']) is! CosStream &&
      cos.resolve(dict['Mask']) is! CosArray) {
    final grayClock = PdfPerfLog.enabled ? (Stopwatch()..start()) : null;
    final sharedWidth = targetWidth ?? _intOrNull(cos.resolve(dict['Width']));
    final sharedHeight =
        targetHeight ?? _intOrNull(cos.resolve(dict['Height']));
    final accelerated = await (grayDctImages?.take(
          stream,
          sharedWidth,
          sharedHeight,
          () => _acceleratedDctGrayImage(
            jpeg,
            targetWidth: targetWidth,
            targetHeight: targetHeight,
          ),
        ) ??
        _acceleratedDctGrayImage(
          jpeg,
          targetWidth: targetWidth,
          targetHeight: targetHeight,
        ));
    if (accelerated != null) {
      if (grayClock != null) {
        PdfPerfLog.log('jpeg gray-accelerated '
            '${accelerated.width}x${accelerated.height} '
            'ms=${(grayClock.elapsedMicroseconds / 1000).toStringAsFixed(1)}');
      }
      return accelerated;
    }
  }
  final acceleratedRgbRanges =
      colorFamily == 'DeviceRGB' ? pdfImageDecodeRanges(cos, dict, 3) : null;
  final acceleratedRgbColorKey =
      colorFamily == 'DeviceRGB' ? pdfImageColorKeyRanges(cos, dict, 3) : null;
  if (colorFamily == 'DeviceRGB' &&
      acceleratedRgbRanges == null &&
      acceleratedRgbColorKey == null) {
    final smask = cos.resolve(dict['SMask']);
    final mask = cos.resolve(dict['Mask']);
    // Keep an ordinary RGB JPEG compressed until the browser codec hands its
    // ImageBitmap directly to Flutter. Running libjpeg-turbo in this isolate
    // first expands the whole image to RGBA synchronously, then uploads it;
    // createImageBitmap performs the codec work asynchronously and the bitmap
    // stays GPU-resident. Masks still use the accelerator path below because
    // they may need CPU samples or a coordinated base/mask decode.
    if (smask is! CosStream && mask is! CosStream && mask is! CosArray) {
      final browserClock = PdfPerfLog.enabled ? (Stopwatch()..start()) : null;
      final browser = scaled
          ? await decodeJpegWithBrowser(
              jpeg,
              targetWidth: targetWidth,
              targetHeight: targetHeight,
            )
          : await decodeJpegWithBrowser(jpeg);
      if (browser != null) {
        if (browserClock != null) {
          PdfPerfLog.log('jpeg rgba-browser '
              '${browser.width}x${browser.height} '
              'ms=${(browserClock.elapsedMicroseconds / 1000).toStringAsFixed(1)}');
        }
        return browser;
      }
    }

    final rgbClock = PdfPerfLog.enabled ? (Stopwatch()..start()) : null;
    final accelerated = await _acceleratedDctRgbImage(
      jpeg,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    if (accelerated != null) {
      if (deferSimpleDctSoftMask && smask is CosStream) {
        final gpuMask = await _decodeSimpleSoftMaskImage(
          cos,
          dict,
          accelerated,
          allowNonDct: true,
          grayDctImages: grayDctImages,
        );
        if (gpuMask != null) {
          _gpuSoftMasks[accelerated] = gpuMask;
          if (rgbClock != null) {
            PdfPerfLog.log('jpeg rgba-accelerated '
                '${accelerated.width}x${accelerated.height} '
                'ms=${(rgbClock.elapsedMicroseconds / 1000).toStringAsFixed(1)}');
          }
          return accelerated;
        }
      } else if (smask is! CosStream &&
          mask is! CosStream &&
          mask is! CosArray) {
        if (rgbClock != null) {
          PdfPerfLog.log('jpeg rgba-accelerated '
              '${accelerated.width}x${accelerated.height} '
              'ms=${(rgbClock.elapsedMicroseconds / 1000).toStringAsFixed(1)}');
        }
        return accelerated;
      }
      accelerated.dispose();
    }
  }
  // On web, decode residual DCT cases through the browser's native codec first:
  // it is far faster than the engine's WASM codec under CanvasKit (a ~640 ms
  // main-thread cost on the reported doc) and lands a GPU image with no
  // readback. Semantically plain RGB JPEGs already returned through the
  // earlier fast path; this branch preserves the same preference for masks and
  // sample transforms that need the generic processing below. Returns null off
  // web and on any failure, falling through to the engine codec. #458.
  //
  // The platform codec downscales during decode when a target is given -
  // decisive on the web, where the alternative is decoding 100+ MP and reading
  // it back off the GPU for the soft-mask multiply.
  final jpegClock = PdfPerfLog.enabled ? (Stopwatch()..start()) : null;
  var browserDecoded = true;
  var base = scaled
      ? await decodeJpegWithBrowser(jpeg,
          targetWidth: targetWidth, targetHeight: targetHeight)
      : await decodeJpegWithBrowser(jpeg);
  if (base == null) {
    browserDecoded = false;
    final codec = scaled
        ? await ui.instantiateImageCodec(jpeg,
            targetWidth: targetWidth, targetHeight: targetHeight)
        : await ui.instantiateImageCodec(jpeg);
    try {
      base = (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }
  if (jpegClock != null) {
    PdfPerfLog.log('jpeg base '
        'codec=${browserDecoded ? 'browser' : 'engine'} '
        '${base.width}x${base.height} '
        'ms=${(jpegClock.elapsedMicroseconds / 1000).toStringAsFixed(1)}');
  }
  // /Decode and color-key /Mask apply to the decoded samples; gray
  // JPEGs decode to RGBA with the sample replicated, so one channel
  // stands in for the raw sample either way.
  final components = switch (colorFamily) {
    'DeviceGray' => 1,
    'DeviceRGB' => 3,
    _ => 0,
  };
  final ranges =
      components > 0 ? pdfImageDecodeRanges(cos, dict, components) : null;
  final colorKey =
      components > 0 ? pdfImageColorKeyRanges(cos, dict, components) : null;
  if (deferSimpleDctSoftMask && ranges == null && colorKey == null) {
    final gpuMask = await _decodeSimpleSoftMaskImage(
      cos,
      dict,
      base,
      allowNonDct: true,
      grayDctImages: grayDctImages,
    );
    if (gpuMask != null) {
      _gpuSoftMasks[base] = gpuMask;
      return base;
    }
  }
  final mask = await _resolveDartUiMask(cos, dict,
      targetWidth: base.width, targetHeight: base.height);
  if (mask == null && ranges == null && colorKey == null) {
    return base;
  }
  final raw = await base.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (raw == null) return base;
  final rgba = Uint8List.fromList(raw.buffer.asUint8List());
  if (ranges != null || colorKey != null) {
    pdfApplyImageDecodeAndColorKey(rgba, components, ranges, colorKey);
  }
  final m = mask == null
      ? (rgba, base.width, base.height)
      : pdfApplyImageAlpha(
          rgba,
          base.width,
          base.height,
          _fitMask(mask, base.width, base.height),
          premultiply: true,
        );
  final result = mask == null
      ? await _imageFromStraight(m.$1, m.$2, m.$3)
      : await _imageFromPremultiplied(m.$1, m.$2, m.$3);
  base.dispose();
  return result;
}

/// Keeps the simple and overwhelmingly common grayscale /SMask on the GPU.
///
/// DCT masks use the JPEG accelerator/browser codec. When [allowNonDct] is
/// true, a portable mask is decoded directly to its final size and uploaded;
/// either route avoids reading the already-decoded base image back to Dart.
///
/// Returns null for the uncommon semantics that genuinely require inspecting
/// and rewriting the base samples. The caller then uses [_resolveDartUiMask]
/// and [pdfApplyImageAlpha], preserving the existing correctness path.
Future<ui.Image?> _decodeSimpleSoftMaskImage(
  CosDocument cos,
  CosDictionary imageDict,
  ui.Image base, {
  bool allowNonDct = false,
  _DctGrayBatchCache? grayDctImages,
}) async {
  final smask = cos.resolve(imageDict['SMask']);
  if (smask is! CosStream) return null;
  final maskDict = smask.dictionary;
  final filters = pdfImageFilters(cos, maskDict);
  final isDct = filters.contains('DCTDecode') || filters.contains('DCT');
  if (!isDct && !allowNonDct) return null;
  if (maskDict.containsKey('Matte')) return null;
  if (!_isDefaultSoftMaskDecode(cos, maskDict['Decode'])) return null;

  final colorSpace = cos.resolve(maskDict['ColorSpace']);
  if (colorSpace is! CosName ||
      (colorSpace.value != 'DeviceGray' && colorSpace.value != 'G')) {
    return null;
  }
  if (cos.resolve(maskDict['SMask']) is CosStream ||
      cos.resolve(maskDict['Mask']) is CosStream ||
      cos.resolve(maskDict['Mask']) is CosArray) {
    return null;
  }

  final clock = PdfPerfLog.enabled ? (Stopwatch()..start()) : null;
  if (!isDct) {
    try {
      await _seedBrowserFlateImage(cos, smask, filters);
      final decodeClock = PdfPerfLog.enabled ? (Stopwatch()..start()) : null;
      final decoded = decodePdfImage(
        cos,
        smask,
        targetWidth: base.width,
        targetHeight: base.height,
      );
      if (decoded == null) return null;
      final decodeMs = decodeClock?.elapsedMicroseconds ?? 0;
      final mask = await uploadRgbaWithBrowser(
            decoded.rgba,
            decoded.width,
            decoded.height,
          ) ??
          await _imageFromPremultiplied(
            decoded.rgba,
            decoded.width,
            decoded.height,
          );
      if (clock != null) {
        PdfPerfLog.log('softmask decoded-mask '
            '${decoded.width}x${decoded.height} '
            'decode=${(decodeMs / 1000).toStringAsFixed(1)}ms '
            'ms=${(clock.elapsedMicroseconds / 1000).toStringAsFixed(1)}');
      }
      return mask;
    } on Exception {
      return null;
    }
  }

  Uint8List bytes;
  try {
    bytes = cos.decodeStreamData(
      smask,
      stopBeforeFilter: filters.contains('DCTDecode') ? 'DCTDecode' : 'DCT',
    );
  } on Exception {
    return null;
  }

  ui.Codec? codec;
  ui.Image? mask;
  try {
    final accelerated = await (grayDctImages?.take(
          smask,
          base.width,
          base.height,
          () => _acceleratedDctGrayImage(
            bytes,
            targetWidth: base.width,
            targetHeight: base.height,
          ),
        ) ??
        _acceleratedDctGrayImage(
          bytes,
          targetWidth: base.width,
          targetHeight: base.height,
        ));
    if (accelerated != null) {
      if (clock != null) {
        PdfPerfLog.log('softmask accelerated-mask '
            '${accelerated.width}x${accelerated.height} '
            'ms=${(clock.elapsedMicroseconds / 1000).toStringAsFixed(1)}');
      }
      return accelerated;
    }
    mask = await decodeJpegWithBrowser(
      bytes,
      targetWidth: base.width,
      targetHeight: base.height,
    );
    if (mask == null) {
      codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: base.width,
        targetHeight: base.height,
      );
      mask = (await codec.getNextFrame()).image;
    }

    if (clock != null) {
      PdfPerfLog.log('softmask gpu-mask '
          '${base.width}x${base.height} '
          'ms=${(clock.elapsedMicroseconds / 1000).toStringAsFixed(1)}');
    }
    final result = mask;
    mask = null;
    return result;
  } on Exception {
    return null;
  } finally {
    mask?.dispose();
    codec?.dispose();
  }
}

/// Seeds the shared decoded-stream cache using the browser's native zlib
/// implementation, then applies the PDF predictor in the portable layer.
///
/// This is intentionally opportunistic: native Flutter and browsers without
/// Compression Streams retain [CosDocument.decodeStreamData]'s normal path.
Future<void> _seedBrowserFlateImage(
  CosDocument cos,
  CosStream stream,
  List<String> filters,
) async {
  if (filters.length != 1 ||
      (filters.single != 'FlateDecode' && filters.single != 'Fl')) {
    return;
  }
  try {
    final encoded = cos.decodeStreamData(
      stream,
      stopBeforeFilter: filters.single,
    );
    final inflated = await inflateZlibWithBrowser(encoded);
    if (inflated == null) return;
    CosDictionary? params;
    final paramsObject = cos.resolve(
      stream.dictionary['DecodeParms'] ?? stream.dictionary['DP'],
    );
    if (paramsObject is CosDictionary) {
      params = paramsObject;
    } else if (paramsObject is CosArray && paramsObject.items.isNotEmpty) {
      final first = cos.resolve(paramsObject.items.first);
      if (first is CosDictionary) params = first;
    }
    final decoded = applyPredictor(inflated, params);
    cos.seedDecodedStreamData(stream, decoded, allowOversize: true);
  } on Exception {
    // The normal lenient decoder remains the fallback for malformed streams.
  }
}

/// Decodes a plain grayscale JPEG through the installed accelerator and
/// uploads its one-byte samples as opaque RGBA. Null preserves the caller's
/// browser/engine fallback when no accelerator is installed or it declines.
Future<ui.Image?> _acceleratedDctGrayImage(
  Uint8List bytes, {
  int? targetWidth,
  int? targetHeight,
}) async {
  final accelerated = pdfDctGrayDecoder?.call(
    bytes,
    targetWidth: targetWidth,
    targetHeight: targetHeight,
  );
  if (accelerated == null ||
      accelerated.width <= 0 ||
      accelerated.height <= 0 ||
      accelerated.samples.length < accelerated.width * accelerated.height) {
    return null;
  }
  final pixelCount = accelerated.width * accelerated.height;
  final rgba = Uint8List(pixelCount * 4);
  if (Endian.host == Endian.little) {
    final words = Uint32List.view(rgba.buffer);
    for (var i = 0; i < pixelCount; i++) {
      words[i] = 0xFF000000 | accelerated.samples[i] * 0x010101;
    }
  } else {
    for (var i = 0; i < pixelCount; i++) {
      final value = accelerated.samples[i];
      final offset = i * 4;
      rgba[offset] = value;
      rgba[offset + 1] = value;
      rgba[offset + 2] = value;
      rgba[offset + 3] = 255;
    }
  }
  return _imageFromPremultiplied(
    rgba,
    accelerated.width,
    accelerated.height,
  );
}

/// Decodes a semantically plain DeviceRGB JPEG through the installed
/// accelerator and uploads its already-opaque RGBA bytes. Null preserves the
/// browser/engine codec fallback on unsupported platforms or malformed data.
Future<ui.Image?> _acceleratedDctRgbImage(
  Uint8List bytes, {
  int? targetWidth,
  int? targetHeight,
}) async {
  final accelerated = pdfDctRgbaDecoder?.call(
    bytes,
    targetWidth: targetWidth,
    targetHeight: targetHeight,
  );
  if (accelerated == null ||
      accelerated.width <= 0 ||
      accelerated.height <= 0 ||
      accelerated.samples.length < accelerated.width * accelerated.height * 4) {
    return null;
  }
  return await uploadRgbaWithBrowser(
        accelerated.samples,
        accelerated.width,
        accelerated.height,
      ) ??
      _imageFromPremultiplied(
        accelerated.samples,
        accelerated.width,
        accelerated.height,
      );
}

bool _isDefaultSoftMaskDecode(CosDocument cos, CosObject? value) {
  if (value == null) return true;
  final resolved = cos.resolve(value);
  if (resolved is! CosArray || resolved.length != 2) return false;
  final low = cos.resolve(resolved[0]);
  final high = cos.resolve(resolved[1]);
  final lowValue = switch (low) {
    CosInteger(:final value) => value.toDouble(),
    CosReal(:final value) => value,
    _ => null,
  };
  final highValue = switch (high) {
    CosInteger(:final value) => value.toDouble(),
    CosReal(:final value) => value,
    _ => null,
  };
  return lowValue == 0 && highValue == 1;
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
Future<PdfImageSoftMask?> _resolveDartUiMask(
    CosDocument cos, CosDictionary dict,
    {int? targetWidth, int? targetHeight}) async {
  final dctBytes = pdfImageDctSoftMaskBytes(cos, dict);
  if (dctBytes != null) {
    final clock = PdfPerfLog.enabled ? (Stopwatch()..start()) : null;
    final gray = await decodeJpegGrayWithBrowser(
      dctBytes,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    if (gray != null) {
      if (clock != null) {
        PdfPerfLog.log('softmask browser-gray '
            '${gray.width}x${gray.height} '
            'ms=${(clock.elapsedMicroseconds / 1000).toStringAsFixed(1)}');
      }
      return PdfImageSoftMask(
        gray.alpha,
        gray.width,
        gray.height,
        sampleStride: gray.sampleStride,
      );
    }
    ui.Codec? codec;
    ui.Image? image;
    try {
      // Match the JPEG-base path above on web. Chromium's native decoder is
      // substantially faster than CanvasKit's codec for these grayscale masks;
      // the readback is unavoidable because the bytes become alpha, but JPEG
      // entropy decode no longer compounds it. Native platforms retain the
      // engine-codec fallback, whose work already runs on the raster thread.
      image = targetWidth != null && targetHeight != null
          ? await decodeJpegWithBrowser(dctBytes,
              targetWidth: targetWidth, targetHeight: targetHeight)
          : await decodeJpegWithBrowser(dctBytes);
      if (image == null) {
        codec = targetWidth != null && targetHeight != null
            ? await ui.instantiateImageCodec(dctBytes,
                targetWidth: targetWidth, targetHeight: targetHeight)
            : await ui.instantiateImageCodec(dctBytes);
        image = (await codec.getNextFrame()).image;
      }
      final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (raw != null) {
        final rgba = raw.buffer.asUint8List(
          raw.offsetInBytes,
          raw.lengthInBytes,
        );
        if (clock != null) {
          PdfPerfLog.log('softmask engine-readback '
              '${image.width}x${image.height} '
              'ms=${(clock.elapsedMicroseconds / 1000).toStringAsFixed(1)}');
        }
        return PdfImageSoftMask(
          rgba,
          image.width,
          image.height,
          sampleStride: 4,
        );
      }
    } on Exception {
      // fall through to a stencil /Mask, like the pre-extraction code did
    } finally {
      // These are intermediate mask surfaces, not images retained by the page
      // cache. Releasing both objects here avoids keeping one native texture
      // per masked XObject alive through a long navigation run.
      image?.dispose();
      codec?.dispose();
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
      out[orow + x] =
          mask.alpha[(row + (x * mask.width ~/ tw)) * mask.sampleStride];
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
