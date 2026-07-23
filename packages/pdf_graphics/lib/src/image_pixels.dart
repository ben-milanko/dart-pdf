/// The pure-Dart half of image-XObject decoding: everything that turns an
/// image stream into RGBA pixels without touching `dart:ui`.
///
/// This is `dart:ui`-free on purpose, so it runs on a bare worker - a native
/// background isolate, and (crucially) a Web Worker, which has no Flutter
/// engine at all. The `dart:ui` glue (the platform JPEG codec and
/// `decodeImageFromPixels`) lives one layer up in `dart_pdf_editor`'s
/// `image_decoder.dart`, which calls [decodePdfImagePixels] as a fast path and
/// reuses the exported helpers below for the residual JPEG path.
///
/// See `doc/render_worker_web.md` and issue #73: moving this decode off the UI
/// thread is what stops raster-heavy CAD sheets from blocking frames while the
/// page goes crisp.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf_cos/pdf_cos.dart';

import 'calibrated_color.dart';
import 'color.dart';
import 'color_space.dart';
import 'icc.dart';

/// A fully decoded image: premultiplied RGBA8888, ready to hand straight to
/// `decodeImageFromPixels` with no further per-pixel work. [decodePdfImagePixels]
/// produces this for every image it can decode without the platform codec.
class PdfDecodedPixels {
  PdfDecodedPixels(this.rgba, this.width, this.height);

  /// Premultiplied RGBA, row-major, `width * height * 4` bytes.
  final Uint8List rgba;
  final int width;
  final int height;
}

/// A grayscale alpha plane lifted from an /SMask or stencil /Mask
/// (§11.6.5.2 / §8.9.6.3), to be baked into a base image's alpha channel.
class PdfImageSoftMask {
  PdfImageSoftMask(this.alpha, this.width, this.height);

  final Uint8List alpha;
  final int width;
  final int height;
}

/// The base image samples decoded to straight-alpha RGBA, with **no** /SMask
/// or stencil /Mask applied yet. [decodePdfImageBase] produces this; the
/// caller bakes in the mask (which may need the platform codec for a DCT
/// /SMask) and premultiplies.
class PdfImageBase {
  PdfImageBase(this.rgba, this.width, this.height, {required this.opaque});

  /// Straight-alpha RGBA, row-major. Color-key /Mask transparency (§8.9.6.4)
  /// and /ImageMask stencil alpha are already written here; a soft/stencil
  /// /Mask is not.
  final Uint8List rgba;
  final int width;
  final int height;

  /// True when every base pixel is fully opaque (no color-key, not a stencil):
  /// premultiplication is then the identity, and a soft mask is the only thing
  /// that can introduce transparency.
  final bool opaque;
}

/// Decodes the base image samples of [stream] to straight-alpha RGBA, WITHOUT
/// applying any /SMask or stencil /Mask. Returns null for a non-CMYK DCTDecode
/// base (needs the platform codec) or an undecodable image.
///
/// CMYK JPEGs decode here (the component decode is pure, via `package:image`),
/// as do Flate/raw DeviceRGB/Gray/Indexed, CCITT, JBIG2, JPX, and /ImageMask
/// stencils. Splitting the base out lets the `dart:ui` layer pair a purely
/// decoded base with a DCT-encoded soft mask (e.g. a CMYK image under a JPEG
/// /SMask) without re-decoding the base.
PdfImageBase? decodePdfImageBase(CosDocument cos, CosStream stream) {
  final dict = stream.dictionary;
  final filters = pdfImageFilters(cos, dict);
  final isMask = cos.resolve(dict['ImageMask']) == const CosBoolean(true);

  // A color-key /Mask (an array of sample ranges, §8.9.6.4) is the only thing
  // besides an /SMask or stencil /Mask that can turn a base pixel transparent.
  final colorKeyed = cos.resolve(dict['Mask']) is CosArray;

  final dctName = filters.contains('DCTDecode')
      ? 'DCTDecode'
      : filters.contains('DCT')
          ? 'DCT'
          : null;
  if (!isMask && dctName != null) {
    // undo any wrapping filters (e.g. [/FlateDecode /DCTDecode])
    final jpeg = cos.decodeStreamData(stream, stopBeforeFilter: dctName);
    if (pdfImageColorFamily(cos, dict) != 'DeviceCMYK') {
      return null; // non-CMYK JPEG → platform codec
    }
    final cmyk = _decodeDctCmyk(jpeg);
    if (cmyk == null) return null;
    final rgba = _toRgba(cos, dict, cmyk.samples, cmyk.width, cmyk.height, 8,
        icc: _iccProfileFor(cos, dict));
    if (rgba == null) return null;
    return PdfImageBase(rgba, cmyk.width, cmyk.height, opaque: !colorKeyed);
  }

  if (filters.contains('JPXDecode')) {
    final jpx = JpxDecoder.decode(
        cos.decodeStreamData(stream, stopBeforeFilter: 'JPXDecode'));
    if (jpx == null) return null;
    // An /Indexed JPX carries palette indices in its single component, not
    // colour: the samples must run through the lookup table, exactly as a raw
    // /Indexed image does. Treating them as gray paints the raw index value -
    // for a single-entry palette (hival 0) that is index 0 → solid black,
    // which is how GWG170/GWG172 rendered a black square over the "no X must
    // be visible" marker (issue #431).
    final rgba = pdfImageColorFamily(cos, dict) == 'Indexed'
        ? _jpxIndexedToRgba(cos, dict, jpx)
        : _jpxToRgba(jpx);
    if (rgba == null) return null;
    // The mappers write alpha 255 throughout (JPX carries no color key).
    return PdfImageBase(rgba, jpx.width, jpx.height, opaque: true);
  }

  // CCITTFaxDecode runs as a regular stream filter (pure-Dart decoder in
  // pdf_cos) and lands here as 1-bit gray samples.
  final width = _intOf(cos.resolve(dict['Width']));
  final height = _intOf(cos.resolve(dict['Height']));
  if (width <= 0 || height <= 0) return null;
  final bits = _intOf(cos.resolve(dict['BitsPerComponent']), fallback: 8);
  final Uint8List data;
  if (filters.contains('JBIG2Decode')) {
    final decoded = Jbig2Decoder.decode(
      data: cos.decodeStreamData(stream, stopBeforeFilter: 'JBIG2Decode'),
      globals: _jbig2Globals(cos, dict),
      width: width,
      height: height,
    );
    if (decoded == null) return null;
    data = decoded;
  } else {
    data = cos.decodeStreamData(stream);
  }

  final rgba = isMask
      ? _stencilToRgba(cos, dict, data, width, height)
      : _toRgba(cos, dict, data, width, height, bits,
          icc: _iccProfileFor(cos, dict));
  if (rgba == null) return null;
  // An /ImageMask decodes to a stencil with real (0/255) alpha.
  return PdfImageBase(rgba, width, height, opaque: !isMask && !colorKeyed);
}

/// Decodes an image XObject [stream] to premultiplied, codec-ready RGBA
/// **purely** (no `dart:ui`), or returns null when the platform JPEG codec is
/// needed - a non-CMYK DCTDecode base, or any image paired with a DCTDecode-
/// encoded /SMask - or the image can't be decoded. On null the caller falls
/// back to the `dart:ui` decode path ([decodePdfImageBase] + the codec).
PdfDecodedPixels? decodePdfImagePixels(CosDocument cos, CosStream stream) {
  final dict = stream.dictionary;
  final isStencil = cos.resolve(dict['ImageMask']) == const CosBoolean(true);

  // Bail before decoding the base, not after: a DCTDecode /SMask sends the
  // image to the `dart:ui` path whatever the base holds, and that path decodes
  // the base itself ([decodePdfImageBase]), so a base decoded here is thrown
  // away and paid for twice. A stencil ignores the soft mask, so it stays.
  if (!isStencil && _softMaskIsDct(cos, dict)) return null;

  final base = decodePdfImageBase(cos, stream);
  if (base == null) return null;

  if (isStencil) {
    // A stencil's alpha is already in base.rgba; no soft mask applies.
    return _finish(base.rgba, base.width, base.height, hasAlpha: true);
  }
  final mask = pdfImageSoftMask(cos, dict) ?? pdfImageStencilMask(cos, dict);
  if (mask == null) {
    return _finish(base.rgba, base.width, base.height, hasAlpha: !base.opaque);
  }
  final m = pdfApplyImageAlpha(base.rgba, base.width, base.height, mask);
  return _finish(m.$1, m.$2, m.$3, hasAlpha: true);
}

/// A rectangular source-pixel region of an image, in the top-left origin of
/// decoded samples (the same coordinates a decode produces). Hand one to
/// [decodePdfImage] to decode only the visible slice of a large raster.
class PdfImageRegion {
  const PdfImageRegion(
      this.sourceX, this.sourceY, this.sourceWidth, this.sourceHeight);

  final int sourceX;
  final int sourceY;
  final int sourceWidth;
  final int sourceHeight;
}

/// Decodes image XObject [stream] to premultiplied, codec-ready RGBA by
/// stating *what pixels you want*, not which decoder can produce them:
///
///  * [region] - decode only this source-pixel rectangle (deep-zoom detail
///    renders that must not ship the whole raster underlay).
///  * [targetWidth]/[targetHeight] - the display size to decode to; a target
///    smaller than the source (or region) avoids expanding a huge native
///    raster only to downsample it. Omit both to decode at native size.
///
/// The façade picks the narrowest fast path that fits - region-scaled,
/// whole-image scaled, or a plain full decode - and, when that fast path
/// can't handle the stream (a stacked filter, an Indexed-8/ICC/Lab space, a
/// 16-bit or /SMask'd image; the fast paths only cover single-filter Flate/
/// raw/CCITT), transparently falls back to a full decode cropped and
/// downsampled to the request. That fall-back-and-downscale policy used to be
/// copied into each caller.
///
/// Returns null only when even the full pure-Dart decode can't produce pixels
/// - a non-CMYK DCTDecode base, or an image under a DCT-encoded /SMask, needs
/// the platform JPEG codec. Those callers decode the base via
/// [decodePdfImageBase] and pair it with the platform codec one layer up.
PdfDecodedPixels? decodePdfImage(
  CosDocument cos,
  CosStream stream, {
  PdfImageRegion? region,
  int? targetWidth,
  int? targetHeight,
}) {
  if (region != null) {
    final tw = targetWidth ?? region.sourceWidth;
    final th = targetHeight ?? region.sourceHeight;
    final fast = decodePdfImagePixelsRegionScaled(
      cos,
      stream,
      region.sourceX,
      region.sourceY,
      region.sourceWidth,
      region.sourceHeight,
      tw,
      th,
    );
    if (fast != null) return fast;
    final full = decodePdfImagePixels(cos, stream);
    if (full == null) return null;
    return cropDownsamplePdfDecodedPixels(
      full,
      region.sourceX,
      region.sourceY,
      region.sourceWidth,
      region.sourceHeight,
      tw,
      th,
    );
  }

  if (targetWidth != null && targetHeight != null) {
    final fast = decodePdfImagePixelsScaled(cos, stream, targetWidth, targetHeight);
    if (fast != null) return fast;
    final full = decodePdfImagePixels(cos, stream);
    if (full == null) return null;
    return downsamplePdfDecodedPixels(full, targetWidth, targetHeight);
  }

  return decodePdfImagePixels(cos, stream);
}

/// Crops premultiplied [decoded] to the source rectangle and downsamples it to
/// [targetWidth]×[targetHeight]. Returns null when the rectangle falls outside
/// [decoded]. Shared by [decodePdfImage]'s full-decode fallback and callers
/// that already hold a decoded image to slice (a cached whole-image raster).
PdfDecodedPixels? cropDownsamplePdfDecodedPixels(
  PdfDecodedPixels decoded,
  int sourceX,
  int sourceY,
  int sourceWidth,
  int sourceHeight,
  int targetWidth,
  int targetHeight,
) {
  if (sourceX < 0 ||
      sourceY < 0 ||
      sourceWidth <= 0 ||
      sourceHeight <= 0 ||
      sourceX + sourceWidth > decoded.width ||
      sourceY + sourceHeight > decoded.height) {
    return null;
  }
  final cropped = Uint8List(sourceWidth * sourceHeight * 4);
  for (var y = 0; y < sourceHeight; y++) {
    final srcOffset = ((sourceY + y) * decoded.width + sourceX) * 4;
    final dstOffset = y * sourceWidth * 4;
    cropped.setRange(
        dstOffset, dstOffset + sourceWidth * 4, decoded.rgba, srcOffset);
  }
  final pixels = PdfDecodedPixels(cropped, sourceWidth, sourceHeight);
  return downsamplePdfDecodedPixels(pixels, targetWidth, targetHeight);
}

/// Decodes a simple Flate/raw or CCITT image directly to
/// [targetWidth]×[targetHeight], or returns null when the stream needs the full
/// general decoder.
///
/// This is the first region/tile-decode fast path for CAD sheets split into
/// many large Flate tiles: the worker already knows the capped display size,
/// so expanding a 2048×2048 tile to native RGBA and then downsampling it wastes
/// both CPU and memory. The implementation is deliberately narrow and
/// correctness-first: RGB/gray 8-bit streams with identity decode and no masks,
/// plus 1-bit gray, Indexed, and /ImageMask streams. The 1-bit route matters
/// especially for large CCITT scans: the filter expands to a compact packed
/// bitmap, which can be averaged straight into the display raster without
/// ever allocating the native-size RGBA buffer. Everything else falls back to
/// [decodePdfImagePixels].
PdfDecodedPixels? decodePdfImagePixelsScaled(
  CosDocument cos,
  CosStream stream,
  int targetWidth,
  int targetHeight,
) {
  final dict = stream.dictionary;
  final width = _intOf(cos.resolve(dict['Width']));
  final height = _intOf(cos.resolve(dict['Height']));
  return decodePdfImagePixelsRegionScaled(
      cos, stream, 0, 0, width, height, targetWidth, targetHeight,
      wholeImageOnlyIfDownscaled: true);
}

/// Decodes a rectangular source-region of a simple Flate/raw or CCITT image
/// directly to [targetWidth]×[targetHeight], or returns null when the stream
/// needs the full general decoder.
///
/// [sourceX], [sourceY], [sourceWidth], and [sourceHeight] are native image
/// pixels in the same top-left origin as decoded image samples. Unlike
/// [decodePdfImagePixelsScaled], this may return a result even when
/// [targetWidth]×[targetHeight] is the same size as the requested region: the
/// crop itself is the saving. Used by deep-zoom worker detail renders, where a
/// visible page slice should not ship the whole raster underlay.
PdfDecodedPixels? decodePdfImagePixelsRegionScaled(
  CosDocument cos,
  CosStream stream,
  int sourceX,
  int sourceY,
  int sourceWidth,
  int sourceHeight,
  int targetWidth,
  int targetHeight, {
  bool wholeImageOnlyIfDownscaled = false,
}) {
  final dict = stream.dictionary;
  final width = _intOf(cos.resolve(dict['Width']));
  final height = _intOf(cos.resolve(dict['Height']));
  if (width <= 0 || height <= 0 || targetWidth <= 0 || targetHeight <= 0) {
    return null;
  }
  final sx = sourceX.clamp(0, width - 1);
  final sy = sourceY.clamp(0, height - 1);
  final sw = sourceWidth.clamp(1, width - sx);
  final sh = sourceHeight.clamp(1, height - sy);
  var tw = targetWidth.clamp(1, sw);
  var th = targetHeight.clamp(1, sh);
  final wholeImage = sx == 0 && sy == 0 && sw == width && sh == height;
  if (wholeImage && wholeImageOnlyIfDownscaled && tw >= width && th >= height) {
    return null;
  }

  final filters = pdfImageFilters(cos, dict);
  if (filters.length != 1) {
    return null;
  }
  final filter = filters.single;
  final supportedFilter = filter == 'FlateDecode' ||
      filter == 'Fl' ||
      filter == 'CCITTFaxDecode' ||
      filter == 'CCF';
  if (!supportedFilter) return null;

  final isMask = cos.resolve(dict['ImageMask']) == const CosBoolean(true);
  final mask = cos.resolve(dict['Mask']);
  if (!isMask && dict.containsKey('SMask')) return null;

  final data = cos.decodeStreamData(stream);
  if (isMask) {
    return _scaledImageMaskRegion(
        cos, dict, data, width, height, sx, sy, sw, sh, tw, th);
  }

  final bits = _intOf(cos.resolve(dict['BitsPerComponent']), fallback: 8);
  final space = pdfImageColorFamily(cos, dict);
  if (space == 'DeviceGray' && bits == 1) {
    if (mask is! CosNull && mask is! CosArray) return null;
    if (!_isDirectDeviceColorSpace(cos, dict, space)) return null;
    return _scaledGray1Region(
        cos, dict, data, width, height, sx, sy, sw, sh, tw, th);
  }
  if (space == 'Indexed' && bits == 1) {
    if (mask is! CosNull && mask is! CosStream) return null;
    return _scaledIndexed1Region(cos, dict, data, width, height, sx, sy, sw, sh,
        tw, th, mask is CosStream ? mask : null);
  }
  if (mask is! CosNull) return null;
  if (bits != 8) return null;
  final components = switch (space) {
    'DeviceRGB' => 3,
    'DeviceGray' => 1,
    _ => 0,
  };
  if (components == 0) return null;
  if (!_isDirectDeviceColorSpace(cos, dict, space)) return null;
  if (pdfImageDecodeRanges(cos, dict, components) != null) return null;

  return switch (components) {
    3 => _scaledRgb8Region(data, width, height, sx, sy, sw, sh, tw, th),
    1 => _scaledGray8Region(data, width, height, sx, sy, sw, sh, tw, th),
    _ => null,
  };
}

bool _isDirectDeviceColorSpace(
    CosDocument cos, CosDictionary dict, String family) {
  final space = cos.resolve(dict['ColorSpace']);
  if (space is! CosName) return false;
  return switch ((family, space.value)) {
    ('DeviceRGB', 'DeviceRGB') || ('DeviceRGB', 'RGB') => true,
    ('DeviceGray', 'DeviceGray') || ('DeviceGray', 'G') => true,
    _ => false,
  };
}

/// Wraps decoded straight-alpha [rgba] as a codec-ready result: premultiplies
/// when the pixels can carry transparency, skips the scan when they're opaque
/// (premultiplying by alpha 255 is the identity).
PdfDecodedPixels _finish(Uint8List rgba, int width, int height,
    {required bool hasAlpha}) {
  if (hasAlpha) pdfPremultiplyRgba(rgba);
  return PdfDecodedPixels(rgba, width, height);
}

/// Area-average (box filter) downsample of premultiplied RGBA [pixels] to
/// [targetWidth]×[targetHeight]. Each destination pixel is the mean of the
/// source pixels in its cell, so a large raster underlay shrinks to the
/// resolution it is actually displayed at - the whole point on heavy CAD
/// sheets, where a 160-megapixel scan blocks the raster thread (and blows the
/// decoded-image cache) when drawn into a page only a few thousand pixels wide.
///
/// Averaging premultiplied samples directly is correct: alpha rides along with
/// the colour it weights. Never upscales - returns [pixels] unchanged when the
/// target is at least as large on both axes. The caller passes target
/// dimensions that already preserve the aspect it wants; this only resamples.
PdfDecodedPixels downsamplePdfDecodedPixels(
    PdfDecodedPixels pixels, int targetWidth, int targetHeight) {
  final sw = pixels.width;
  final sh = pixels.height;
  var tw = targetWidth < 1 ? 1 : targetWidth;
  var th = targetHeight < 1 ? 1 : targetHeight;
  if (tw >= sw && th >= sh) return pixels; // already small enough; no upscale
  if (tw > sw) tw = sw;
  if (th > sh) th = sh;
  final src = pixels.rgba;
  final dst = Uint8List(tw * th * 4);
  var di = 0;
  for (var ty = 0; ty < th; ty++) {
    final sy0 = ty * sh ~/ th;
    var sy1 = (ty + 1) * sh ~/ th;
    if (sy1 <= sy0) sy1 = sy0 + 1;
    for (var tx = 0; tx < tw; tx++) {
      final sx0 = tx * sw ~/ tw;
      var sx1 = (tx + 1) * sw ~/ tw;
      if (sx1 <= sx0) sx1 = sx0 + 1;
      // Local int accumulators: a cell spans (sw/tw)·(sh/th) source pixels, so
      // the worst sum is bounded by the source pixel count × 255 - well within
      // a 64-bit int (native) and float64's 2^53 (web).
      var r = 0, g = 0, b = 0, a = 0, n = 0;
      for (var sy = sy0; sy < sy1; sy++) {
        var si = (sy * sw + sx0) * 4;
        for (var sx = sx0; sx < sx1; sx++) {
          r += src[si];
          g += src[si + 1];
          b += src[si + 2];
          a += src[si + 3];
          si += 4;
          n++;
        }
      }
      dst[di] = r ~/ n;
      dst[di + 1] = g ~/ n;
      dst[di + 2] = b ~/ n;
      dst[di + 3] = a ~/ n;
      di += 4;
    }
  }
  return PdfDecodedPixels(dst, tw, th);
}

PdfDecodedPixels? _scaledRgb8Region(
  Uint8List data,
  int width,
  int height,
  int sourceX,
  int sourceY,
  int sourceWidth,
  int sourceHeight,
  int targetWidth,
  int targetHeight,
) {
  if (data.length < width * height * 3) return null;
  final out = Uint8List(targetWidth * targetHeight * 4);
  var di = 0;
  for (var y = 0; y < targetHeight; y++) {
    final sy =
        _sourceCoordInRegion(y, sourceY, sourceHeight, height, targetHeight);
    final y0 = sy.$1;
    final y1 = sy.$2;
    final wy = sy.$3;
    for (var x = 0; x < targetWidth; x++) {
      final sx =
          _sourceCoordInRegion(x, sourceX, sourceWidth, width, targetWidth);
      final x0 = sx.$1;
      final x1 = sx.$2;
      final wx = sx.$3;
      final i00 = (y0 * width + x0) * 3;
      final i01 = (y0 * width + x1) * 3;
      final i10 = (y1 * width + x0) * 3;
      final i11 = (y1 * width + x1) * 3;
      out[di] =
          _bilinearByte(data[i00], data[i01], data[i10], data[i11], wx, wy);
      out[di + 1] = _bilinearByte(
          data[i00 + 1], data[i01 + 1], data[i10 + 1], data[i11 + 1], wx, wy);
      out[di + 2] = _bilinearByte(
          data[i00 + 2], data[i01 + 2], data[i10 + 2], data[i11 + 2], wx, wy);
      out[di + 3] = 255;
      di += 4;
    }
  }
  return PdfDecodedPixels(out, targetWidth, targetHeight);
}

PdfDecodedPixels? _scaledGray8Region(
  Uint8List data,
  int width,
  int height,
  int sourceX,
  int sourceY,
  int sourceWidth,
  int sourceHeight,
  int targetWidth,
  int targetHeight,
) {
  if (data.length < width * height) return null;
  final out = Uint8List(targetWidth * targetHeight * 4);
  var di = 0;
  for (var y = 0; y < targetHeight; y++) {
    final sy =
        _sourceCoordInRegion(y, sourceY, sourceHeight, height, targetHeight);
    final y0 = sy.$1;
    final y1 = sy.$2;
    final wy = sy.$3;
    for (var x = 0; x < targetWidth; x++) {
      final sx =
          _sourceCoordInRegion(x, sourceX, sourceWidth, width, targetWidth);
      final x0 = sx.$1;
      final x1 = sx.$2;
      final wx = sx.$3;
      final v = _bilinearByte(data[y0 * width + x0], data[y0 * width + x1],
          data[y1 * width + x0], data[y1 * width + x1], wx, wy);
      out[di] = out[di + 1] = out[di + 2] = v;
      out[di + 3] = 255;
      di += 4;
    }
  }
  return PdfDecodedPixels(out, targetWidth, targetHeight);
}

PdfDecodedPixels? _scaledIndexed1Region(
  CosDocument cos,
  CosDictionary dict,
  Uint8List data,
  int width,
  int height,
  int sourceX,
  int sourceY,
  int sourceWidth,
  int sourceHeight,
  int targetWidth,
  int targetHeight,
  CosStream? mask,
) {
  final paletteInfo = _indexedPalette(cos, dict);
  if (paletteInfo == null) return null;
  final palette = paletteInfo.$1;
  final paletteCount = paletteInfo.$2;
  final rowBytes = (width + 7) ~/ 8;
  if (data.length < rowBytes * height) return null;

  Uint8List? maskData;
  var maskInverted = false;
  if (mask != null) {
    final filters = pdfImageFilters(cos, mask.dictionary);
    if (filters.length != 1 ||
        (filters.single != 'FlateDecode' && filters.single != 'Fl')) {
      return null;
    }
    final mw = _intOf(cos.resolve(mask.dictionary['Width']));
    final mh = _intOf(cos.resolve(mask.dictionary['Height']));
    final mbits =
        _intOf(cos.resolve(mask.dictionary['BitsPerComponent']), fallback: 1);
    if (mw != width || mh != height || mbits != 1) return null;
    final decode = cos.resolve(mask.dictionary['Decode']);
    maskInverted = decode is CosArray &&
        decode.length > 0 &&
        _numOf(cos.resolve(decode[0])) == 1;
    maskData = cos.decodeStreamData(mask);
    if (maskData.length < rowBytes * height) return null;
  }

  final out = Uint8List(targetWidth * targetHeight * 4);
  var di = 0;
  for (var y = 0; y < targetHeight; y++) {
    final sy = (sourceY + (y + 0.5) * sourceHeight / targetHeight)
        .floor()
        .clamp(0, height - 1);
    final row = sy * rowBytes;
    for (var x = 0; x < targetWidth; x++) {
      final sx = (sourceX + (x + 0.5) * sourceWidth / targetWidth)
          .floor()
          .clamp(0, width - 1);
      final bit = (data[row + (sx >> 3)] >> (7 - (sx & 7))) & 1;
      final index = bit >= paletteCount ? 0 : bit;

      var alpha = 255;
      if (maskData != null) {
        final maskBit = (maskData[row + (sx >> 3)] >> (7 - (sx & 7))) & 1;
        final masked = maskInverted ? maskBit == 0 : maskBit == 1;
        alpha = masked ? 0 : 255;
      }

      final pi = index * 3;
      out[di] = alpha == 0 ? 0 : palette[pi];
      out[di + 1] = alpha == 0 ? 0 : palette[pi + 1];
      out[di + 2] = alpha == 0 ? 0 : palette[pi + 2];
      out[di + 3] = alpha;
      di += 4;
    }
  }
  return PdfDecodedPixels(out, targetWidth, targetHeight);
}

PdfDecodedPixels? _scaledGray1Region(
  CosDocument cos,
  CosDictionary dict,
  Uint8List data,
  int width,
  int height,
  int sourceX,
  int sourceY,
  int sourceWidth,
  int sourceHeight,
  int targetWidth,
  int targetHeight,
) {
  final rowBytes = (width + 7) ~/ 8;
  if (data.length < rowBytes * height) return null;

  final ranges = pdfImageDecodeRanges(cos, dict, 1);
  final (min, max) = ranges?[0] ?? (0.0, 1.0);
  final values = (
    (min * 255).round().clamp(0, 255),
    (max * 255).round().clamp(0, 255),
  );
  final colorKey = pdfImageColorKeyRanges(cos, dict, 1);
  final alpha0 =
      colorKey != null && 0 >= colorKey[0].$1 && 0 <= colorKey[0].$2 ? 0 : 255;
  final alpha1 =
      colorKey != null && 1 >= colorKey[0].$1 && 1 <= colorKey[0].$2 ? 0 : 255;
  final premultiplied0 = alpha0 == 0 ? 0 : values.$1;
  final premultiplied1 = alpha1 == 0 ? 0 : values.$2;

  // Match [downsamplePdfDecodedPixels]' area-average exactly, but count the
  // two possible packed samples instead of first expanding every source pixel
  // to four RGBA bytes. Besides preserving thin scanned linework better than
  // point sampling, this makes the fast result pixel-identical to the old
  // full-decode-then-downsample fallback.
  final out = Uint8List(targetWidth * targetHeight * 4);
  var di = 0;
  for (var ty = 0; ty < targetHeight; ty++) {
    final sy0 = sourceY + ty * sourceHeight ~/ targetHeight;
    var sy1 = sourceY + (ty + 1) * sourceHeight ~/ targetHeight;
    if (sy1 <= sy0) sy1 = sy0 + 1;
    for (var tx = 0; tx < targetWidth; tx++) {
      final sx0 = sourceX + tx * sourceWidth ~/ targetWidth;
      var sx1 = sourceX + (tx + 1) * sourceWidth ~/ targetWidth;
      if (sx1 <= sx0) sx1 = sx0 + 1;

      var ones = 0;
      for (var sy = sy0; sy < sy1; sy++) {
        final row = sy * rowBytes;
        for (var sx = sx0; sx < sx1; sx++) {
          ones += (data[row + (sx >> 3)] >> (7 - (sx & 7))) & 1;
        }
      }
      final count = (sx1 - sx0) * (sy1 - sy0);
      final zeros = count - ones;
      final value = (zeros * premultiplied0 + ones * premultiplied1) ~/ count;
      final alpha = (zeros * alpha0 + ones * alpha1) ~/ count;
      out[di] = out[di + 1] = out[di + 2] = value;
      out[di + 3] = alpha;
      di += 4;
    }
  }
  return PdfDecodedPixels(out, targetWidth, targetHeight);
}

PdfDecodedPixels? _scaledImageMaskRegion(
  CosDocument cos,
  CosDictionary dict,
  Uint8List data,
  int width,
  int height,
  int sourceX,
  int sourceY,
  int sourceWidth,
  int sourceHeight,
  int targetWidth,
  int targetHeight,
) {
  final rowBytes = (width + 7) ~/ 8;
  if (data.length < rowBytes * height) return null;
  final decode = cos.resolve(dict['Decode']);
  final inverted = decode is CosArray &&
      decode.length > 0 &&
      _numOf(cos.resolve(decode[0])) == 1;
  final out = Uint8List(targetWidth * targetHeight * 4);
  var di = 0;
  for (var y = 0; y < targetHeight; y++) {
    final sy = (sourceY + (y + 0.5) * sourceHeight / targetHeight)
        .floor()
        .clamp(0, height - 1);
    for (var x = 0; x < targetWidth; x++) {
      final sx = (sourceX + (x + 0.5) * sourceWidth / targetWidth)
          .floor()
          .clamp(0, width - 1);
      final bit = (data[sy * rowBytes + (sx >> 3)] >> (7 - (sx & 7))) & 1;
      final paint = inverted ? bit == 1 : bit == 0;
      final v = paint ? 255 : 0;
      out[di] = out[di + 1] = out[di + 2] = v;
      out[di + 3] = v;
      di += 4;
    }
  }
  return PdfDecodedPixels(out, targetWidth, targetHeight);
}

(int, int, double) _sourceCoordInRegion(
  int dst,
  int sourceStart,
  int sourceSize,
  int fullSize,
  int dstSize,
) {
  final p = sourceStart + (dst + 0.5) * sourceSize / dstSize - 0.5;
  final i0 = p.floor().clamp(0, fullSize - 1);
  final i1 = (i0 + 1).clamp(0, fullSize - 1);
  return (i0, i1, p - i0);
}

int _bilinearByte(
  int v00,
  int v01,
  int v10,
  int v11,
  double wx,
  double wy,
) {
  final top = v00 * (1 - wx) + v01 * wx;
  final bottom = v10 * (1 - wx) + v11 * wx;
  return (top * (1 - wy) + bottom * wy).round().clamp(0, 255);
}

/// The pixel size an image should be decoded/stored at so it is no sharper than
/// [headroom]× its on-screen footprint - the cap behind `serializeCommands`'s
/// `maxImagePixelRatio` (see render_command_codec.dart), extracted as a pure
/// function so every branch is unit-testable without a giant fixture image.
///
/// [srcWidth]/[srcHeight] are the image's native pixels; [widthPts]/[heightPts]
/// are its drawn size on the page in points (the column lengths of its CTM);
/// [ratio] is screen pixels per point (device pixel ratio included). The target
/// is `headroom × drawnPixels`, never upscaled past the source, and never past
/// the hard ceilings ([maxDimension] per edge, [maxPixels] total) that keep a
/// sheet-sized raster underlay within a GPU texture limit and the decoded-image
/// cache. Returns `(srcWidth, srcHeight)` unchanged when no worthwhile
/// reduction applies (already small enough, a degenerate transform, or a
/// non-positive ratio) - the caller then ships the native pixels as-is.
(int, int) cappedImagePixelSize(int srcWidth, int srcHeight, double widthPts,
    double heightPts, double ratio,
    {double headroom = 2.0,
    int maxPixels = 1 << 24,
    double maxDimension = 8192}) {
  if (srcWidth < 1 || srcHeight < 1) return (srcWidth, srcHeight);
  if (!(ratio > 0) || !(widthPts > 0) || !(heightPts > 0)) {
    return (srcWidth, srcHeight);
  }
  // ceil() of a positive double is >= 1, so tw/th never under-run 1px.
  var tw = (widthPts * ratio * headroom).ceil();
  var th = (heightPts * ratio * headroom).ceil();
  if (tw >= srcWidth && th >= srcHeight) return (srcWidth, srcHeight); // no up
  if (tw > srcWidth) tw = srcWidth;
  if (th > srcHeight) th = srcHeight;

  final maxEdge = math.max(tw, th);
  if (maxEdge > maxDimension) {
    final s = maxDimension / maxEdge;
    tw = (tw * s).floor().clamp(1, srcWidth);
    th = (th * s).floor().clamp(1, srcHeight);
  }
  if (tw * th > maxPixels) {
    final s = math.sqrt(maxPixels / (tw * th));
    tw = (tw * s).floor().clamp(1, srcWidth);
    th = (th * s).floor().clamp(1, srcHeight);
  }

  // Not worth a full-buffer resample for a sliver - keep the native pixels.
  if (tw * th >= srcWidth * srcHeight * 0.9) return (srcWidth, srcHeight);
  return (tw, th);
}

/// Premultiplies straight-alpha RGBA in place. `decodeImageFromPixels` treats
/// rgba8888 as premultiplied, so straight alpha would make transparent-but-
/// colored pixels (a white backdrop under an /SMask cutout) composite
/// additively as solid color.
void pdfPremultiplyRgba(Uint8List rgba) {
  for (var i = 0; i < rgba.length; i += 4) {
    final a = rgba[i + 3];
    if (a == 255) continue;
    rgba[i] = rgba[i] * a ~/ 255;
    rgba[i + 1] = rgba[i + 1] * a ~/ 255;
    rgba[i + 2] = rgba[i + 2] * a ~/ 255;
  }
}

class _DctCmykImage {
  const _DctCmykImage(this.samples, this.width, this.height);

  final Uint8List samples;
  final int width;
  final int height;
}

/// Decodes 4-component JPEG samples in PDF polarity: 0 = no ink,
/// 255 = full ink. Platform codecs convert these directly to RGB as Adobe
/// inverted CMYK and lose the original K, producing very dark images.
_DctCmykImage? _decodeDctCmyk(Uint8List jpegBytes) {
  final jpeg = img.JpegData()..read(jpegBytes);
  if (jpeg.components.length != 4) return null;
  final width = jpeg.width;
  final height = jpeg.height;
  if (width == null || height == null || width <= 0 || height <= 0) {
    return null;
  }

  final out = Uint8List(width * height * 4);
  final component1 = jpeg.components[0];
  final component2 = jpeg.components[1];
  final component3 = jpeg.components[2];
  final component4 = jpeg.components[3];
  final ycck = (jpeg.adobe?.transformCode ?? 0) != 0;

  for (var y = 0; y < height; y++) {
    final y1 = y >> component1.vScaleShift;
    final y2 = y >> component2.vScaleShift;
    final y3 = y >> component3.vScaleShift;
    final y4 = y >> component4.vScaleShift;
    final line1 = component1.lines[y1];
    final line2 = component2.lines[y2];
    final line3 = component3.lines[y3];
    final line4 = component4.lines[y4];
    if (line1 == null || line2 == null || line3 == null || line4 == null) {
      return null;
    }
    for (var x = 0; x < width; x++) {
      final x1 = x >> component1.hScaleShift;
      final x2 = x >> component2.hScaleShift;
      final x3 = x >> component3.hScaleShift;
      final x4 = x >> component4.hScaleShift;
      var c = line1[x1];
      var m = line2[x2];
      var yy = line3[x3];
      var k = line4[x4];

      if (ycck) {
        final cr = yy - 128;
        final cb = m - 128;
        final yScaled = c << 8;
        // YCCK -> CMYK per pdf.js's _convertYcckToCmyk: Adobe stores the
        // chroma/luma of the inverted CMY, so the converted channels are
        // inverted back to PDF ink polarity (0 = no ink). K passes through
        // unchanged - pdf.js leaves it to a /Decode array, and matching the
        // reference renderer matters more than MuPDF's all-four-inverted
        // convention, which disagrees on K.
        c = 255 - _shiftR(yScaled + 359 * cr, 8).clamp(0, 255);
        m = 255 - _shiftR(yScaled - 88 * cb - 183 * cr, 8).clamp(0, 255);
        yy = 255 - _shiftR(yScaled + 454 * cb, 8).clamp(0, 255);
      }

      final i = (y * width + x) * 4;
      out[i] = c;
      out[i + 1] = m;
      out[i + 2] = yy;
      out[i + 3] = k;
    }
  }
  return _DctCmykImage(out, width, height);
}

int _shiftR(int value, int count) => (value >> count).toSigned(32);

/// JPX samples to RGBA by component count (per §7.4.9 the embedded
/// color description governs; gray, RGB, and CMYK cover PDF practice).
Uint8List? _jpxToRgba(JpxImage jpx) {
  final count = jpx.width * jpx.height;
  final out = Uint8List(count * 4);
  final samples = jpx.samples;
  switch (jpx.components) {
    case 1:
      for (var i = 0; i < count; i++) {
        out[i * 4] = out[i * 4 + 1] = out[i * 4 + 2] = samples[i];
        out[i * 4 + 3] = 255;
      }
    case 3:
      for (var i = 0; i < count; i++) {
        out[i * 4] = samples[i * 3];
        out[i * 4 + 1] = samples[i * 3 + 1];
        out[i * 4 + 2] = samples[i * 3 + 2];
        out[i * 4 + 3] = 255;
      }
    case 4:
      for (var i = 0; i < count; i++) {
        final color = PdfColor.cmyk(
            samples[i * 4] / 255,
            samples[i * 4 + 1] / 255,
            samples[i * 4 + 2] / 255,
            samples[i * 4 + 3] / 255);
        out[i * 4] = (color.red * 255).round();
        out[i * 4 + 1] = (color.green * 255).round();
        out[i * 4 + 2] = (color.blue * 255).round();
        out[i * 4 + 3] = 255;
      }
    default:
      return null;
  }
  return out;
}

/// Maps an /Indexed JPX image's index samples through its palette. JPX stores
/// the indices in a single component (§7.4.9 / the /Indexed base governs the
/// colour), so `jpx.samples` are palette indices, not colour. Out-of-range
/// indices clamp to 0, matching [_indexedToRgba]. Returns null when the
/// palette can't be resolved.
Uint8List? _jpxIndexedToRgba(CosDocument cos, CosDictionary dict, JpxImage jpx) {
  if (jpx.components != 1) return null;
  final paletteInfo = _indexedPalette(cos, dict);
  if (paletteInfo == null) return null;
  final palette = paletteInfo.$1;
  final paletteCount = paletteInfo.$2;
  final count = jpx.width * jpx.height;
  final samples = jpx.samples;
  if (samples.length < count) return null;
  final out = Uint8List(count * 4);
  for (var i = 0; i < count; i++) {
    final raw = samples[i];
    final index = raw >= paletteCount ? 0 : raw;
    final o = i * 4;
    out[o] = palette[index * 3];
    out[o + 1] = palette[index * 3 + 1];
    out[o + 2] = palette[index * 3 + 2];
    out[o + 3] = 255;
  }
  return out;
}

/// The /JBIG2Globals stream from /DecodeParms (dict or filter-aligned
/// array form), decoded, or null.
Uint8List? _jbig2Globals(CosDocument cos, CosDictionary dict) {
  final parms = cos.resolve(dict['DecodeParms'] ?? dict['DP']);
  CosObject? globalsRef;
  if (parms is CosDictionary) globalsRef = parms['JBIG2Globals'];
  if (parms is CosArray) {
    for (final entry in parms.items) {
      final resolved = cos.resolve(entry);
      if (resolved is CosDictionary && resolved.containsKey('JBIG2Globals')) {
        globalsRef = resolved['JBIG2Globals'];
        break;
      }
    }
  }
  final globals = cos.resolve(globalsRef);
  if (globals is! CosStream) return null;
  try {
    return cos.decodeStreamData(globals);
  } on Exception {
    return null;
  }
}

/// Whether the image's /SMask is DCTDecode-encoded - that mask needs the
/// platform JPEG codec, so the pure path declines the whole image.
bool _softMaskIsDct(CosDocument cos, CosDictionary dict) {
  final smask = cos.resolve(dict['SMask']);
  if (smask is! CosStream) return false;
  return pdfImageFilters(cos, smask.dictionary).contains('DCTDecode');
}

/// The DCTDecode-encoded /SMask's JPEG bytes (wrapping filters undone), or null
/// when the /SMask is absent or not DCT. The `dart:ui` layer decodes these
/// with the platform codec to recover the alpha plane.
Uint8List? pdfImageDctSoftMaskBytes(CosDocument cos, CosDictionary dict) {
  final smask = cos.resolve(dict['SMask']);
  if (smask is! CosStream) return null;
  if (!pdfImageFilters(cos, smask.dictionary).contains('DCTDecode')) {
    return null;
  }
  try {
    return cos.decodeStreamData(smask, stopBeforeFilter: 'DCTDecode');
  } on Exception {
    return null;
  }
}

/// Decodes a non-DCT /SMask: a grayscale image whose samples become the alpha
/// channel of its parent image (§11.6.5.2). Returns null when there is no
/// /SMask, or it is DCT-encoded (use [pdfImageDctSoftMaskBytes]), or its shape
/// is unsupported.
PdfImageSoftMask? pdfImageSoftMask(CosDocument cos, CosDictionary dict) {
  final smask = cos.resolve(dict['SMask']);
  if (smask is! CosStream) return null;
  try {
    if (pdfImageFilters(cos, smask.dictionary).contains('DCTDecode')) {
      return null; // DCT mask: the caller handles it via the platform codec
    }
    final width = _intOf(cos.resolve(smask.dictionary['Width']));
    final height = _intOf(cos.resolve(smask.dictionary['Height']));
    if (width <= 0 || height <= 0) return null;
    final bits =
        _intOf(cos.resolve(smask.dictionary['BitsPerComponent']), fallback: 8);
    final data = cos.decodeStreamData(smask);

    if (bits == 8 && data.length >= width * height) {
      return PdfImageSoftMask(data, width, height);
    }
    if (bits == 1) {
      final rowBytes = (width + 7) ~/ 8;
      if (data.length < rowBytes * height) return null;
      final alpha = Uint8List(width * height);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final bit = (data[y * rowBytes + (x >> 3)] >> (7 - (x & 7))) & 1;
          alpha[y * width + x] = bit == 1 ? 255 : 0;
        }
      }
      return PdfImageSoftMask(alpha, width, height);
    }
    return null;
  } on Exception {
    return null; // unsupported mask: leave the image opaque
  }
}

/// An explicit /Mask stencil stream (§8.9.6.3): 1-bit samples where 1
/// means "masked out" (transparent); /Decode [1 0] flips the polarity.
PdfImageSoftMask? pdfImageStencilMask(CosDocument cos, CosDictionary dict) {
  final mask = cos.resolve(dict['Mask']);
  if (mask is! CosStream) return null;
  try {
    final width = _intOf(cos.resolve(mask.dictionary['Width']));
    final height = _intOf(cos.resolve(mask.dictionary['Height']));
    if (width <= 0 || height <= 0) return null;
    final bits =
        _intOf(cos.resolve(mask.dictionary['BitsPerComponent']), fallback: 1);
    if (bits != 1) return null;
    final decode = cos.resolve(mask.dictionary['Decode']);
    final inverted = decode is CosArray &&
        decode.length > 0 &&
        _numOf(cos.resolve(decode[0])) == 1;
    final data = cos.decodeStreamData(mask);
    final rowBytes = (width + 7) ~/ 8;
    if (data.length < rowBytes * height) return null;
    final alpha = Uint8List(width * height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final bit = (data[y * rowBytes + (x >> 3)] >> (7 - (x & 7))) & 1;
        final masked = inverted ? bit == 0 : bit == 1;
        alpha[y * width + x] = masked ? 0 : 255;
      }
    }
    return PdfImageSoftMask(alpha, width, height);
  } on Exception {
    return null; // unsupported mask: leave the image opaque
  }
}

/// Per-component (min, max) pairs from /Decode, or null when absent or
/// not matching [components].
List<(double, double)>? pdfImageDecodeRanges(
    CosDocument cos, CosDictionary dict, int components) {
  final raw = cos.resolve(dict['Decode']);
  if (raw is! CosArray || raw.length < components * 2) return null;
  final values = <double>[];
  for (var i = 0; i < components * 2; i++) {
    final n = cos.resolve(raw[i]);
    if (n is CosInteger) {
      values.add(n.value.toDouble());
    } else if (n is CosReal) {
      values.add(n.value);
    } else {
      return null;
    }
  }
  final ranges = [
    for (var c = 0; c < components; c++) (values[c * 2], values[c * 2 + 1]),
  ];
  // identity decode: skip the lookup work
  if (ranges.every((r) => r.$1 == 0 && r.$2 == 1)) return null;
  return ranges;
}

/// A 256-entry lookup table mapping a raw 8-bit sample through a /Decode
/// range back to an 8-bit value.
Uint8List _decodeLut((double, double) range) {
  final (min, max) = range;
  final lut = Uint8List(256);
  for (var s = 0; s < 256; s++) {
    lut[s] = ((min + s / 255 * (max - min)) * 255).round().clamp(0, 255);
  }
  return lut;
}

/// Color-key masking ranges (§8.9.6.4): /Mask as an array of [min max]
/// pairs in *raw sample* space; samples inside every range go transparent.
List<(int, int)>? pdfImageColorKeyRanges(
    CosDocument cos, CosDictionary dict, int components) {
  final raw = cos.resolve(dict['Mask']);
  if (raw is! CosArray || raw.length < components * 2) return null;
  final values = <int>[];
  for (var i = 0; i < components * 2; i++) {
    final n = cos.resolve(raw[i]);
    if (n is! CosInteger) return null;
    values.add(n.value);
  }
  return [
    for (var c = 0; c < components; c++) (values[c * 2], values[c * 2 + 1]),
  ];
}

/// A stencil mask carries no colors: 1-bit samples select where the fill
/// color paints. Decode to white pixels with alpha; the device tints them.
/// Default /Decode [0 1] paints where the sample is 0 (§8.9.6.2).
Uint8List? _stencilToRgba(CosDocument cos, CosDictionary dict, Uint8List data,
    int width, int height) {
  final decode = cos.resolve(dict['Decode']);
  final inverted = decode is CosArray &&
      decode.length > 0 &&
      _numOf(cos.resolve(decode[0])) == 1;
  final rowBytes = (width + 7) ~/ 8;
  if (data.length < rowBytes * height) return null;
  final out = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final bit = (data[y * rowBytes + (x >> 3)] >> (7 - (x & 7))) & 1;
      final paint = inverted ? bit == 1 : bit == 0;
      final i = (y * width + x) * 4;
      out[i] = out[i + 1] = out[i + 2] = 255;
      out[i + 3] = paint ? 255 : 0;
    }
  }
  return out;
}

/// Applies a /Decode lookup and color-key transparency to RGBA pixels in
/// place. Keying compares the pre-/Decode samples (§8.9.6.4), so it runs
/// before the lookup.
void pdfApplyImageDecodeAndColorKey(Uint8List rgba, int components,
    List<(double, double)>? ranges, List<(int, int)>? colorKey) {
  final luts = ranges == null
      ? null
      : [for (var c = 0; c < components; c++) _lutFor(ranges, c)];
  for (var i = 0; i < rgba.length; i += 4) {
    if (colorKey != null) {
      var inside = true;
      for (var c = 0; c < components; c++) {
        final sample = rgba[i + (components == 1 ? 0 : c)];
        if (sample < colorKey[c].$1 || sample > colorKey[c].$2) {
          inside = false;
          break;
        }
      }
      if (inside) rgba[i + 3] = 0;
    }
    if (luts != null) {
      if (components == 1) {
        rgba[i] = rgba[i + 1] = rgba[i + 2] = luts[0][rgba[i]];
      } else {
        rgba[i] = luts[0][rgba[i]];
        rgba[i + 1] = luts[1][rgba[i + 1]];
        rgba[i + 2] = luts[2][rgba[i + 2]];
      }
    }
  }
}

/// Bakes [mask]'s alpha into [rgba], returning the resulting (bytes, width,
/// height). When the mask is HIGHER resolution than the base image - common
/// for /Mask stencils where a tiny colour image carries a large crisp cutout
/// (issue4246: a 50x40 gradient under a 1000x800 letter mask) - the result is
/// built at the mask's resolution with the colour bilinearly upsampled, so the
/// cutout's detail survives instead of being crushed to the base grid (which
/// the device would then upscale into visible blocks). Otherwise the mask is
/// point-sampled onto the base in place.
(Uint8List, int, int) pdfApplyImageAlpha(
    Uint8List rgba, int width, int height, PdfImageSoftMask mask) {
  if (mask.width * mask.height <= width * height) {
    for (var y = 0; y < height; y++) {
      final maskY = y * mask.height ~/ height;
      for (var x = 0; x < width; x++) {
        final maskX = x * mask.width ~/ width;
        rgba[(y * width + x) * 4 + 3] = mask.alpha[maskY * mask.width + maskX];
      }
    }
    return (rgba, width, height);
  }
  final mw = mask.width;
  final mh = mask.height;
  final out = Uint8List(mw * mh * 4);
  for (var my = 0; my < mh; my++) {
    final fy = (my + 0.5) * height / mh - 0.5;
    final y0 = fy.floor();
    final wy = fy - y0;
    final y0c = y0.clamp(0, height - 1);
    final y1c = (y0 + 1).clamp(0, height - 1);
    for (var mx = 0; mx < mw; mx++) {
      final fx = (mx + 0.5) * width / mw - 0.5;
      final x0 = fx.floor();
      final wx = fx - x0;
      final x0c = x0.clamp(0, width - 1);
      final x1c = (x0 + 1).clamp(0, width - 1);
      final i00 = (y0c * width + x0c) * 4;
      final i01 = (y0c * width + x1c) * 4;
      final i10 = (y1c * width + x0c) * 4;
      final i11 = (y1c * width + x1c) * 4;
      final o = (my * mw + mx) * 4;
      for (var c = 0; c < 3; c++) {
        final top = rgba[i00 + c] * (1 - wx) + rgba[i01 + c] * wx;
        final bot = rgba[i10 + c] * (1 - wx) + rgba[i11 + c] * wx;
        out[o + c] = (top * (1 - wy) + bot * wy).round().clamp(0, 255);
      }
      out[o + 3] = mask.alpha[my * mw + mx];
    }
  }
  return (out, mw, mh);
}

/// The parsed ICC profile of an ICCBased image color space, when the
/// engine supports its shape; null falls back to the device family. Gated on
/// the family name so a non-ICCBased image never parses its (potentially
/// expensive) colour space just to discover there is no profile.
/// Parsed ICC profiles, scoped to the document that owns their streams.
///
/// [PdfColorSpace.parse] takes an `iccCache` for exactly this and the
/// interpreter keeps one, but the image path had no way to pass one through
/// its public entry points, so every image re-parsed its profile stream - and
/// a page of tiles shares one profile across all of them. An Expando keeps the
/// cache document-scoped (and collectable with the document) without widening
/// the public signatures.
final Expando<Map<CosStream, IccProfile?>> _iccProfileCache =
    Expando<Map<CosStream, IccProfile?>>('pdfIccProfiles');

IccProfile? _iccProfileFor(CosDocument cos, CosDictionary dict) {
  final space = cos.resolve(dict['ColorSpace']);
  if (space is! CosArray || space.length < 1) return null;
  final family = cos.resolve(space[0]);
  if (family is! CosName || family.value != 'ICCBased') return null;
  final cache = _iccProfileCache[cos] ??= <CosStream, IccProfile?>{};
  return PdfColorSpace.parse(cos, space, iccCache: cache).iccProfile;
}

Uint8List? _toRgba(CosDocument cos, CosDictionary dict, Uint8List data,
    int width, int height, int bits,
    {IccProfile? icc}) {
  final count = width * height;
  final out = Uint8List(count * 4);

  final space = pdfImageColorFamily(cos, dict);
  final alternate = _alternateColorSpaceFor(cos, dict);
  final components = alternate?.channels ??
      switch (space) {
        'DeviceRGB' => 3,
        'DeviceGray' => 1,
        'DeviceCMYK' => 4,
        _ => 0,
      };
  final ranges =
      components > 0 ? pdfImageDecodeRanges(cos, dict, components) : null;
  final colorKey = components > 0
      ? pdfImageColorKeyRanges(cos, dict, components)
      : space == 'Indexed'
          ? pdfImageColorKeyRanges(cos, dict, 1)
          : null;

  if (space == 'DeviceGray' && bits == 1) {
    final (min, max) = ranges?[0] ?? (0.0, 1.0);
    final values = [
      (min * 255).round().clamp(0, 255),
      (max * 255).round().clamp(0, 255),
    ];
    final key = colorKey;
    final rowBytes = (width + 7) ~/ 8;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final byte = data[y * rowBytes + (x >> 3)];
        final on = (byte >> (7 - (x & 7))) & 1;
        final i = (y * width + x) * 4;
        out[i] = out[i + 1] = out[i + 2] = values[on];
        out[i + 3] =
            key != null && on >= key[0].$1 && on <= key[0].$2 ? 0 : 255;
      }
    }
    return out;
  }
  if (space == 'Indexed') {
    return _indexedToRgba(cos, dict, data, width, height, bits, out,
        colorKey: colorKey);
  }
  if (bits != 8) return null;
  if (alternate != null) {
    return _alternateToRgba(
      data,
      width,
      height,
      out,
      alternate,
      ranges,
      colorKey,
    );
  }

  switch (space) {
    case 'DeviceRGB':
      if (data.length < count * 3) return null;
      // An sRGB-equivalent profile is an 8-bit no-op - take the unmanaged
      // path (#531, the single most common ICCBased RGB case).
      final rgbIcc =
          icc != null && icc.channels == 3 && !icc.isSrgb ? icc : null;
      // Fast path: no colour management, identity /Decode, no color key - the
      // RGB samples copy straight through (the LUTs would be identity and the
      // alpha is a constant 255), with no per-pixel list allocation.
      if (rgbIcc == null && ranges == null && colorKey == null) {
        for (var i = 0; i < count; i++) {
          final s = i * 3, o = i * 4;
          out[o] = data[s];
          out[o + 1] = data[s + 1];
          out[o + 2] = data[s + 2];
          out[o + 3] = 255;
        }
        return out;
      }
      final lut0 = _lutFor(ranges, 0),
          lut1 = _lutFor(ranges, 1),
          lut2 = _lutFor(ranges, 2);
      final key = colorKey;
      // Matrix/TRC profiles transform allocation-free straight from bytes
      // (#531); with an identity /Decode the samples pass through untouched.
      final rgb8 = rgbIcc?.rgb8Transform;
      if (rgb8 != null && ranges == null && key == null) {
        for (var i = 0; i < count; i++) {
          final s = i * 3, o = i * 4;
          rgb8(data, s, out, o);
          out[o + 3] = 255;
        }
        return out;
      }
      for (var i = 0; i < count; i++) {
        final s = i * 3, o = i * 4;
        final r = data[s], g = data[s + 1], b = data[s + 2];
        if (rgbIcc != null) {
          final c =
              rgbIcc.toSrgb([lut0[r] / 255, lut1[g] / 255, lut2[b] / 255]);
          out[o] = (c.red * 255).round();
          out[o + 1] = (c.green * 255).round();
          out[o + 2] = (c.blue * 255).round();
        } else {
          out[o] = lut0[r];
          out[o + 1] = lut1[g];
          out[o + 2] = lut2[b];
        }
        out[o + 3] = key != null &&
                r >= key[0].$1 &&
                r <= key[0].$2 &&
                g >= key[1].$1 &&
                g <= key[1].$2 &&
                b >= key[2].$1 &&
                b <= key[2].$2
            ? 0
            : 255;
      }
      return out;
    case 'DeviceGray':
      if (data.length < count) return null;
      final lut = _lutFor(ranges, 0);
      final grayIcc =
          icc != null && icc.channels == 1 && !icc.isSrgb ? icc : null;
      final key = colorKey;
      // Fast path: identity /Decode, no ICC, no color key - replicate the gray
      // sample into RGB with constant 255 alpha, no per-pixel allocation.
      if (grayIcc == null && ranges == null && key == null) {
        for (var i = 0; i < count; i++) {
          final o = i * 4, v = data[i];
          out[o] = out[o + 1] = out[o + 2] = v;
          out[o + 3] = 255;
        }
        return out;
      }
      final grayLut = grayIcc == null
          ? null
          : [
              for (var v = 0; v < 256; v++) grayIcc.toSrgb([lut[v] / 255])
            ];
      for (var i = 0; i < count; i++) {
        final o = i * 4, s = data[i];
        if (grayLut != null) {
          final c = grayLut[s];
          out[o] = (c.red * 255).round();
          out[o + 1] = (c.green * 255).round();
          out[o + 2] = (c.blue * 255).round();
        } else {
          out[o] = out[o + 1] = out[o + 2] = lut[s];
        }
        out[o + 3] = key != null && s >= key[0].$1 && s <= key[0].$2 ? 0 : 255;
      }
      return out;
    case 'DeviceCMYK':
      if (data.length < count * 4) return null;
      final lut0 = _lutFor(ranges, 0),
          lut1 = _lutFor(ranges, 1),
          lut2 = _lutFor(ranges, 2),
          lut3 = _lutFor(ranges, 3);
      final cmykIcc = icc != null && icc.channels == 4 ? icc : null;
      final key = colorKey;
      // CMYK→RGB is the heaviest per-pixel path (a quadratic polynomial, or an
      // ICC LUT). The conversion math is unchanged, but the per-pixel sample
      // and value lists - and the keyed() argument list - are gone, which is
      // most of the old cost.
      for (var i = 0; i < count; i++) {
        final base = i * 4;
        final s0 = data[base],
            s1 = data[base + 1],
            s2 = data[base + 2],
            s3 = data[base + 3];
        final color = cmykIcc != null
            ? cmykIcc.toSrgb([
                lut0[s0] / 255,
                lut1[s1] / 255,
                lut2[s2] / 255,
                lut3[s3] / 255
              ])
            : PdfColor.cmyk(
                lut0[s0] / 255, lut1[s1] / 255, lut2[s2] / 255, lut3[s3] / 255);
        out[base] = (color.red * 255).round();
        out[base + 1] = (color.green * 255).round();
        out[base + 2] = (color.blue * 255).round();
        out[base + 3] = key != null &&
                s0 >= key[0].$1 &&
                s0 <= key[0].$2 &&
                s1 >= key[1].$1 &&
                s1 <= key[1].$2 &&
                s2 >= key[2].$1 &&
                s2 <= key[2].$2 &&
                s3 >= key[3].$1 &&
                s3 <= key[3].$2
            ? 0
            : 255;
      }
      return out;
  }
  return null;
}

/// A packed sample tuple must fit an int key; wider spaces skip the table.
const int _tintMemoMaxComponents = 8;

/// Ceiling on distinct tuples remembered, so a wide space whose tuples never
/// repeat cannot grow the table with the pixel count.
const int _tintMemoMaxEntries = 1 << 16;

/// Separation and DeviceN samples reach the alternate space through a tint
/// transform, which - a type 4 calculator especially - costs orders of
/// magnitude more per pixel than the device spaces' copy. Samples are 8 bits,
/// so one colorant has at most 256 distinct inputs and two at most 65536,
/// against the millions of pixels in a scan: evaluate each distinct tuple
/// once and index the answer afterwards, the way [_indexedToRgba] resolves
/// its palette up front.
Uint8List? _alternateToRgba(
  Uint8List data,
  int width,
  int height,
  Uint8List out,
  PdfColorSpace alternate,
  List<(double, double)>? ranges,
  List<(int, int)>? colorKey,
) {
  final count = width * height;
  final components = alternate.channels;
  if (data.length < count * components) return null;
  final luts = [for (var c = 0; c < components; c++) _lutFor(ranges, c)];
  final memo = components <= _tintMemoMaxComponents ? <int, int>{} : null;
  // Reused across pixels: evaluateAt reads its input and keeps no reference.
  final values = Float64List(components);

  for (var i = 0; i < count; i++) {
    final base = i * components;
    var key = 0;
    if (memo != null) {
      for (var c = 0; c < components; c++) {
        key = (key << 8) | data[base + c];
      }
    }
    // Packed RGB is never negative, so -1 stands in for "not remembered".
    var rgb = memo?[key] ?? -1;
    if (rgb < 0) {
      for (var c = 0; c < components; c++) {
        values[c] = luts[c][data[base + c]] / 255;
      }
      final color = alternate.toSrgb(values);
      rgb = ((color.red * 255).round().clamp(0, 255) << 16) |
          ((color.green * 255).round().clamp(0, 255) << 8) |
          ((color.blue * 255).round().clamp(0, 255));
      if (memo != null && memo.length < _tintMemoMaxEntries) memo[key] = rgb;
    }
    out[i * 4] = (rgb >> 16) & 0xff;
    out[i * 4 + 1] = (rgb >> 8) & 0xff;
    out[i * 4 + 2] = rgb & 0xff;
    var masked = false;
    if (colorKey != null) {
      masked = true;
      for (var c = 0; c < components; c++) {
        final sample = data[base + c];
        if (sample < colorKey[c].$1 || sample > colorKey[c].$2) {
          masked = false;
          break;
        }
      }
    }
    out[i * 4 + 3] = masked ? 0 : 255;
  }
  return out;
}

final Uint8List _identityLut =
    Uint8List.fromList([for (var i = 0; i < 256; i++) i]);

Uint8List _lutFor(List<(double, double)>? ranges, int component) =>
    ranges == null ? _identityLut : _decodeLut(ranges[component]);

/// Indexed images: samples are palette indices at 1/2/4/8 bits per pixel;
/// the palette lives in any base space we can map to RGB (DeviceRGB and
/// -Gray and -CMYK, directly or behind ICCBased/CalRGB/CalGray, the /Lab CIE
/// space, or a Separation/DeviceN tint transform).
Uint8List? _indexedToRgba(CosDocument cos, CosDictionary dict, Uint8List data,
    int width, int height, int bits, Uint8List out,
    {List<(int, int)>? colorKey}) {
  final paletteInfo = _indexedPalette(cos, dict);
  if (paletteInfo == null) return null;
  final palette = paletteInfo.$1;
  final paletteCount = paletteInfo.$2;
  if (bits != 1 && bits != 2 && bits != 4 && bits != 8) return null;

  final rowBytes = (width * bits + 7) ~/ 8;
  if (data.length < rowBytes * height) return null;
  final perByte = 8 ~/ bits;
  final mask = (1 << bits) - 1;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final byte = data[y * rowBytes + x ~/ perByte];
      final shift = 8 - bits * (x % perByte + 1);
      final raw = (byte >> shift) & mask;
      final index = raw >= paletteCount ? 0 : raw;
      final i = (y * width + x) * 4;
      out[i] = palette[index * 3];
      out[i + 1] = palette[index * 3 + 1];
      out[i + 2] = palette[index * 3 + 2];
      // color-key ranges compare the raw index sample (§8.9.6.4)
      out[i + 3] =
          colorKey != null && raw >= colorKey[0].$1 && raw <= colorKey[0].$2
              ? 0
              : 255;
    }
  }
  return out;
}

(Uint8List, int)? _indexedPalette(CosDocument cos, CosDictionary dict) {
  final space = cos.resolve(dict['ColorSpace']);
  if (space is! CosArray || space.length < 4) return null;
  // A Lab base palette is decoded through the CIE machinery - without this it
  // falls through to DeviceGray and the L*/a*/b* triples read as three
  // separate gray samples, banding a smooth gradient into diagonal stripes.
  // (CalRGB/CalGray keep their existing device decode to avoid baseline churn.)
  final baseObj = cos.resolve(space[1]);
  final baseFamily = baseObj is CosArray && baseObj.length > 0
      ? cos.resolve(baseObj[0])
      : null;
  final labBase = baseFamily is CosName && baseFamily.value == 'Lab'
      ? PdfCalibratedColorSpace.parse(cos, baseObj)
      : null;
  // A Separation/DeviceN base reaches its alternate space through a tint
  // transform (§8.6.6.4): each palette entry runs through it exactly as
  // _alternateToRgba does for a non-indexed Separation/DeviceN image. Without
  // this the base fell to the device switch's `_ => 0` and the whole image was
  // dropped - both images on the Ghent DeviceN page are this shape (issue
  // #430). PdfColorSpace already covers the /Lab alternate these files use.
  final tintBase = labBase == null &&
          baseFamily is CosName &&
          (baseFamily.value == 'Separation' || baseFamily.value == 'DeviceN')
      ? PdfColorSpace.parse(cos, baseObj)
      : null;
  final components = labBase?.components ??
      tintBase?.channels ??
      switch (_familyOf(cos, space[1])) {
        'DeviceRGB' => 3,
        'DeviceGray' => 1,
        'DeviceCMYK' => 4,
        _ => 0,
      };
  if (components == 0) return null;

  final lookupObj = cos.resolve(space[3]);
  final Uint8List lookup;
  if (lookupObj is CosString) {
    lookup = lookupObj.bytes;
  } else if (lookupObj is CosStream) {
    lookup = cos.decodeStreamData(lookupObj);
  } else {
    return null;
  }
  // convert the palette to RGB once, indices then just copy triplets
  final paletteCount = lookup.length ~/ components;
  final palette = Uint8List(paletteCount * 3);
  for (var p = 0; p < paletteCount; p++) {
    final src = p * components;
    if (labBase != null) {
      final color = labBase.toSrgbFromSamples(
          [for (var c = 0; c < components; c++) lookup[src + c]]);
      palette[p * 3] = (color.red * 255).round().clamp(0, 255);
      palette[p * 3 + 1] = (color.green * 255).round().clamp(0, 255);
      palette[p * 3 + 2] = (color.blue * 255).round().clamp(0, 255);
      continue;
    }
    if (tintBase != null) {
      final color = tintBase.toSrgbFromSamples(
          [for (var c = 0; c < components; c++) lookup[src + c]]);
      palette[p * 3] = (color.red * 255).round().clamp(0, 255);
      palette[p * 3 + 1] = (color.green * 255).round().clamp(0, 255);
      palette[p * 3 + 2] = (color.blue * 255).round().clamp(0, 255);
      continue;
    }
    switch (components) {
      case 3:
        palette[p * 3] = lookup[src];
        palette[p * 3 + 1] = lookup[src + 1];
        palette[p * 3 + 2] = lookup[src + 2];
      case 1:
        palette[p * 3] = palette[p * 3 + 1] = palette[p * 3 + 2] = lookup[src];
      case 4:
        final color = PdfColor.cmyk(lookup[src] / 255, lookup[src + 1] / 255,
            lookup[src + 2] / 255, lookup[src + 3] / 255);
        palette[p * 3] = (color.red * 255).round();
        palette[p * 3 + 1] = (color.green * 255).round();
        palette[p * 3 + 2] = (color.blue * 255).round();
    }
  }
  return (palette, paletteCount);
}

/// Maps the image's /ColorSpace to the device family used for decoding.
String pdfImageColorFamily(CosDocument cos, CosDictionary dict) =>
    _familyOf(cos, dict['ColorSpace']);

/// Maps any color-space object to the device family used for decoding:
/// names (with their inline-image abbreviations), ICCBased by component
/// count, and the CIE spaces by their device-family shape.
String _familyOf(CosDocument cos, CosObject? raw) {
  final space = cos.resolve(raw);
  if (space is CosName) {
    return switch (space.value) {
      'G' => 'DeviceGray',
      'RGB' => 'DeviceRGB',
      'CMYK' => 'DeviceCMYK',
      'I' => 'Indexed',
      final name => name,
    };
  }
  if (space is CosArray && space.length > 0) {
    final family = cos.resolve(space[0]);
    if (family is CosName) {
      switch (family.value) {
        case 'Indexed' || 'I':
          return 'Indexed';
        case 'CalRGB':
          return 'DeviceRGB';
        case 'CalGray':
          return 'DeviceGray';
        case 'ICCBased':
          if (space.length > 1) {
            final profile = cos.resolve(space[1]);
            if (profile is CosStream) {
              return switch (_intOf(cos.resolve(profile.dictionary['N']))) {
                1 => 'DeviceGray',
                4 => 'DeviceCMYK',
                _ => 'DeviceRGB',
              };
            }
          }
          return 'DeviceRGB';
        case 'DeviceN':
          return 'DeviceN';
        case 'Separation':
          return 'Separation';
      }
    }
  }
  return 'DeviceGray';
}

/// The Separation/DeviceN space of an image whose samples reach an alternate
/// space through a tint transform (§8.6.6.4), or null when the /ColorSpace is
/// not one of those (device, Indexed, and CIE spaces decode directly). The
/// returned space's [PdfColorSpace.channels] is the colorant count of the
/// samples and [PdfColorSpace.toSrgb] runs the tint transform into the
/// alternate space.
PdfColorSpace? _alternateColorSpaceFor(CosDocument cos, CosDictionary dict) {
  // Gate on the family name before the full parse: only Separation/DeviceN
  // need the tint transform decoded here, so device/Indexed/ICCBased images
  // must not pay to parse (and re-parse) their colour space.
  final space = cos.resolve(dict['ColorSpace']);
  if (space is! CosArray || space.length < 1) return null;
  final family = cos.resolve(space[0]);
  if (family is! CosName ||
      (family.value != 'Separation' && family.value != 'DeviceN')) {
    return null;
  }
  return PdfColorSpace.parse(cos, space);
}

/// The image's /Filter names in order (resolving the dict and array forms).
List<String> pdfImageFilters(CosDocument cos, CosDictionary dict) {
  final filter = cos.resolve(dict['Filter']);
  if (filter is CosName) return [filter.value];
  if (filter is CosArray) {
    return [
      for (final f in filter.items)
        if (cos.resolve(f) case CosName(:final value)) value,
    ];
  }
  return const [];
}

double _numOf(CosObject? value) {
  if (value is CosInteger) return value.value.toDouble();
  if (value is CosReal) return value.value;
  return 0;
}

int _intOf(CosObject? value, {int fallback = 0}) =>
    value is CosInteger ? value.value : fallback;
