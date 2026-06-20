/// The pure-Dart half of image-XObject decoding: everything that turns an
/// image stream into RGBA pixels without touching `dart:ui`.
///
/// This is `dart:ui`-free on purpose, so it runs on a bare worker — a native
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

import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf_cos/pdf_cos.dart';

import 'calibrated_color.dart';
import 'color.dart';
import 'function.dart';
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
    final rgba = _jpxToRgba(jpx);
    if (rgba == null) return null;
    // _jpxToRgba writes alpha 255 throughout (JPX carries no color key).
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
/// needed — a non-CMYK DCTDecode base, or any image paired with a DCTDecode-
/// encoded /SMask — or the image can't be decoded. On null the caller falls
/// back to the `dart:ui` decode path ([decodePdfImageBase] + the codec).
PdfDecodedPixels? decodePdfImagePixels(CosDocument cos, CosStream stream) {
  final base = decodePdfImageBase(cos, stream);
  if (base == null) return null;

  final dict = stream.dictionary;
  if (cos.resolve(dict['ImageMask']) == const CosBoolean(true)) {
    // A stencil's alpha is already in base.rgba; no soft mask applies.
    return _finish(base.rgba, base.width, base.height, hasAlpha: true);
  }
  if (_softMaskIsDct(cos, dict)) return null; // mask needs the platform codec
  final mask = pdfImageSoftMask(cos, dict) ?? pdfImageStencilMask(cos, dict);
  if (mask == null) {
    return _finish(base.rgba, base.width, base.height, hasAlpha: !base.opaque);
  }
  final m = pdfApplyImageAlpha(base.rgba, base.width, base.height, mask);
  return _finish(m.$1, m.$2, m.$3, hasAlpha: true);
}

/// Wraps decoded straight-alpha [rgba] as a codec-ready result: premultiplies
/// when the pixels can carry transparency, skips the scan when they're opaque
/// (premultiplying by alpha 255 is the identity).
PdfDecodedPixels _finish(Uint8List rgba, int width, int height,
    {required bool hasAlpha}) {
  if (hasAlpha) pdfPremultiplyRgba(rgba);
  return PdfDecodedPixels(rgba, width, height);
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
        c = _shiftR(yScaled + 359 * cr, 8).clamp(0, 255);
        m = _shiftR(yScaled - 88 * cb - 183 * cr, 8).clamp(0, 255);
        yy = _shiftR(yScaled + 454 * cb, 8).clamp(0, 255);
        k = 255 - k;
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

/// Whether the image's /SMask is DCTDecode-encoded — that mask needs the
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
  if (!pdfImageFilters(cos, smask.dictionary).contains('DCTDecode')) return null;
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
/// height). When the mask is HIGHER resolution than the base image — common
/// for /Mask stencils where a tiny colour image carries a large crisp cutout
/// (issue4246: a 50x40 gradient under a 1000x800 letter mask) — the result is
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
/// engine supports its shape; null falls back to the device family.
IccProfile? _iccProfileFor(CosDocument cos, CosDictionary dict) {
  final space = cos.resolve(dict['ColorSpace']);
  if (space is! CosArray || space.length < 2) return null;
  final family = cos.resolve(space[0]);
  if (family is! CosName || family.value != 'ICCBased') return null;
  final stream = cos.resolve(space[1]);
  if (stream is! CosStream) return null;
  try {
    return IccProfile.parse(cos.decodeStreamData(stream));
  } on Exception {
    return null;
  }
}

Uint8List? _toRgba(CosDocument cos, CosDictionary dict, Uint8List data,
    int width, int height, int bits,
    {IccProfile? icc}) {
  final count = width * height;
  final out = Uint8List(count * 4);

  final space = pdfImageColorFamily(cos, dict);
  final alternate = _alternateColorSpaceFor(cos, dict);
  final components = alternate?.components ??
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
        out[i + 3] = key != null && on >= key[0].$1 && on <= key[0].$2 ? 0 : 255;
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
      final rgbIcc = icc != null && icc.channels == 3 ? icc : null;
      // Fast path: no colour management, identity /Decode, no color key — the
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
      final grayIcc = icc != null && icc.channels == 1 ? icc : null;
      final key = colorKey;
      // Fast path: identity /Decode, no ICC, no color key — replicate the gray
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
      // and value lists — and the keyed() argument list — are gone, which is
      // most of the old cost.
      for (var i = 0; i < count; i++) {
        final base = i * 4;
        final s0 = data[base],
            s1 = data[base + 1],
            s2 = data[base + 2],
            s3 = data[base + 3];
        final color = cmykIcc != null
            ? cmykIcc.toSrgb(
                [lut0[s0] / 255, lut1[s1] / 255, lut2[s2] / 255, lut3[s3] / 255])
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

Uint8List? _alternateToRgba(
  Uint8List data,
  int width,
  int height,
  Uint8List out,
  _AlternateColorSpace alternate,
  List<(double, double)>? ranges,
  List<(int, int)>? colorKey,
) {
  final count = width * height;
  final components = alternate.components;
  if (data.length < count * components) return null;
  final luts = [for (var c = 0; c < components; c++) _lutFor(ranges, c)];
  for (var i = 0; i < count; i++) {
    final samples = [
      for (var c = 0; c < components; c++) data[i * components + c]
    ];
    final values = [
      for (var c = 0; c < components; c++) luts[c][samples[c]] / 255
    ];
    final color = alternate.colorFor(values);
    out[i * 4] = (color.red * 255).round().clamp(0, 255);
    out[i * 4 + 1] = (color.green * 255).round().clamp(0, 255);
    out[i * 4 + 2] = (color.blue * 255).round().clamp(0, 255);
    var masked = false;
    if (colorKey != null) {
      masked = true;
      for (var c = 0; c < components; c++) {
        if (samples[c] < colorKey[c].$1 || samples[c] > colorKey[c].$2) {
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
/// -Gray and -CMYK, directly or behind ICCBased/CalRGB/CalGray).
Uint8List? _indexedToRgba(CosDocument cos, CosDictionary dict, Uint8List data,
    int width, int height, int bits, Uint8List out,
    {List<(int, int)>? colorKey}) {
  final space = cos.resolve(dict['ColorSpace']);
  if (space is! CosArray || space.length < 4) return null;
  // A Lab base palette is decoded through the CIE machinery — without this it
  // falls through to DeviceGray and the L*/a*/b* triples read as three
  // separate gray samples, banding a smooth gradient into diagonal stripes.
  // (CalRGB/CalGray keep their existing device decode to avoid baseline churn.)
  final baseObj = cos.resolve(space[1]);
  final baseFamily =
      baseObj is CosArray && baseObj.length > 0 ? cos.resolve(baseObj[0]) : null;
  final labBase = baseFamily is CosName && baseFamily.value == 'Lab'
      ? PdfCalibratedColorSpace.parse(cos, baseObj)
      : null;
  final components = labBase?.components ??
      switch (_familyOf(cos, space[1])) {
        'DeviceRGB' => 3,
        'DeviceGray' => 1,
        'DeviceCMYK' => 4,
        _ => 0,
      };
  if (components == 0) return null;
  if (bits != 1 && bits != 2 && bits != 4 && bits != 8) return null;

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

class _AlternateColorSpace {
  const _AlternateColorSpace({
    required this.components,
    required this.baseComponents,
    required this.function,
    this.calibrated,
  });

  final int components;
  final int baseComponents;
  final PdfFunction function;
  final PdfCalibratedColorSpace? calibrated;

  PdfColor colorFor(List<double> values) {
    final transformed = function.evaluateAt(values);
    return calibrated?.toSrgb(transformed) ??
        colorFromComponents(transformed, baseComponents);
  }
}

_AlternateColorSpace? _alternateColorSpaceFor(
    CosDocument cos, CosDictionary dict) {
  final space = cos.resolve(dict['ColorSpace']);
  if (space is! CosArray || space.length < 4) return null;
  final family = cos.resolve(space[0]);
  if (family is! CosName) return null;

  final int components;
  final CosObject alternateSpace;
  final CosObject functionObject;
  switch (family.value) {
    case 'Separation':
      components = 1;
      alternateSpace = space[2];
      functionObject = space[3];
    case 'DeviceN':
      final names = cos.resolve(space[1]);
      if (names is! CosArray || names.length == 0) return null;
      components = names.length;
      alternateSpace = space[2];
      functionObject = space[3];
    default:
      return null;
  }

  final function = PdfFunction.parse(cos, functionObject);
  if (function == null) return null;
  final baseComponents = _alternateComponents(cos, alternateSpace);
  if (baseComponents == 0) return null;
  return _AlternateColorSpace(
    components: components,
    baseComponents: baseComponents,
    function: function,
    calibrated: PdfCalibratedColorSpace.parse(cos, alternateSpace),
  );
}

int _alternateComponents(CosDocument cos, CosObject object) {
  final space = cos.resolve(object);
  if (space is CosName) {
    return switch (space.value) {
      'DeviceGray' || 'CalGray' || 'G' => 1,
      'DeviceRGB' || 'CalRGB' || 'Lab' || 'RGB' => 3,
      'DeviceCMYK' || 'CMYK' => 4,
      _ => 0,
    };
  }
  if (space is CosArray && space.length > 0) {
    final family = cos.resolve(space[0]);
    if (family is CosName) {
      switch (family.value) {
        case 'CalGray':
          return 1;
        case 'CalRGB':
        case 'Lab':
          return 3;
        case 'ICCBased':
          if (space.length > 1) {
            final profile = cos.resolve(space[1]);
            if (profile is CosStream) {
              return switch (_intOf(cos.resolve(profile.dictionary['N']))) {
                1 => 1,
                4 => 4,
                _ => 3,
              };
            }
          }
          return 3;
      }
    }
  }
  return 0;
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
