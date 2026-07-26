// Colorant readings for decoded rasters - image overprint (issue #604).
//
// The colorant buffer (issue #502, `overprint_compositor.dart`) made *vector*
// overprint faithful by recording the device colorants every draw leaves
// behind. An image draw had no such reading: decoded pixels are sRGB, and sRGB
// has no colorant decomposition, so an image neither overprinted what was
// under it nor accepted overprint from ink drawn over it.
//
// This supplies the missing reading, at the only place it exists - the image's
// own *samples*, in its own colour space, before they become sRGB:
//
//  * [pdfImageColorants] answers "what colorants does this raster carry",
//    which is what lets the buffer record an image as a backdrop.
//  * [pdfImageOverprintStream] answers "what does this raster look like
//    overprinted onto that backdrop", by compositing every sample in ink space
//    ([PdfInkColorants.over]) and handing back a **substitute image stream**
//    whose colours are already the composite.
//
// A substitute stream rather than a new device call, a flag on the request, or
// a per-pixel hook: the substitute is an ordinary image XObject, so every path
// that draws an image - the canvas device, the strip device, the recorded
// command buffer, the render worker, the decoded-image cache - carries it with
// no change at all. The interpreter simply draws a different stream. That is
// also why the results are memoised on the source stream ([Expando]): the
// decoded-image cache keys XObject images by stream *identity*, so the same
// (image, backdrop) pair must produce the same object on every interpretation
// pass, including the collect walk that decodes ahead of the paint walk.
//
// Pure Dart with no `dart:ui` dependency, like the rest of the overprint
// machinery, so the VM, the render worker and the web agree by construction.
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';

import 'color.dart';
import 'color_space.dart';
import 'colorants.dart';
import 'image_pixels.dart';

/// The device colorants an image XObject's samples carry.
///
/// [uniformInk] is non-null only when every sample carries the *same*
/// colorants, which is what the buffer can record as a backdrop: it stores one
/// colorant vector per cell, and a device paints one colour per call, so an
/// image whose colorants vary reads as "unknown" exactly as it did before.
class PdfImageColorants {
  const PdfImageColorants({
    required this.uniformInk,
    required this.uniformColor,
    required this.coversQuad,
  });

  /// The ink every sample of the image carries, or null when they differ.
  final PdfInkColorants? uniformInk;

  /// The sRGB [uniformInk] renders as; meaningless when [uniformInk] is null.
  final PdfColor uniformColor;

  /// Whether painting the image lays ink down over its whole unit square - no
  /// /SMask, no stencil /Mask, no colour-key /Mask. A masked raster still
  /// *has* a colorant reading (it can be composited onto a backdrop), but the
  /// buffer must not record it as a backdrop of its own: the backdrop survives
  /// wherever the mask is transparent.
  final bool coversQuad;

  /// The ink the buffer may record over the image's whole quad - [uniformInk]
  /// only when it also [coversQuad].
  PdfInkColorants? get backdropInk => coversQuad ? uniformInk : null;
}

/// The colorant reading of image XObject [stream], or null when it has none.
///
/// Null means "this raster has no colorant decomposition", which is what sends
/// an overprint over it back to the painting device's approximation. That is
/// the answer for a DeviceRGB / ICCBased / Lab / CalRGB image (inventing
/// colorants for those would knock backdrops out that a real separations
/// device leaves alone - the same rule [PdfColorSpace.inkColorants] applies to
/// vector colour), for an encoding whose samples this cannot read (DCT, JPX,
/// JBIG2), for a stencil (/ImageMask carries no colour of its own), and for a
/// raster past [_maxReadPixels].
///
/// Memoised per stream: a page draws the same XObject repeatedly and
/// re-interprets on every render, and the answer depends only on the stream.
PdfImageColorants? pdfImageColorants(CosDocument cos, CosStream stream,
    {CosDictionary? resources}) {
  final cached = _readings[stream];
  if (cached != null) {
    return identical(cached, _noReading) ? null : cached as PdfImageColorants;
  }
  final reading = _readColorants(cos, stream, resources);
  _readings[stream] = reading ?? _noReading;
  return reading;
}

/// A substitute for image XObject [stream] whose samples are already
/// composited over [backdrop] under overprint mode [mode] (§8.6.7), or null
/// when no substitute can be built.
///
/// The substitute is a plain, unfiltered `/DeviceRGB` 8-bit image of the same
/// dimensions, carrying the source's /SMask, stencil /Mask, /Interpolate and
/// /Intent through unchanged - only the colour changes. Its /Decode is baked
/// into the samples, so the substitute needs none.
///
/// Returns null (draw the original) when:
///  * the backdrop is bare paper - overprinting onto no colorant leaves every
///    sample exactly as it was, so the source stream *is* the answer, and this
///    is the case that keeps pages which set `/op` defensively over white free;
///  * the source has a colour-key /Mask - its ranges are stated in source
///    sample space and cannot survive the conversion to DeviceRGB;
///  * the samples cannot be read, or the raster is past [_maxReadPixels].
///
/// Memoised per (stream, backdrop, mode); see the library comment for why the
/// identity has to be stable.
CosStream? pdfImageOverprintStream(
  CosDocument cos,
  CosStream stream, {
  CosDictionary? resources,
  required PdfColorants backdrop,
  required PdfColor backdropColor,
  required int mode,
  required Map<String, List<double>> spotEquivalents,
}) {
  if (backdrop == PdfColorants.none) return null;
  final key = _SubstituteKey(backdrop, mode);
  final memo = _substitutes[stream] ??= <_SubstituteKey, CosStream?>{};
  if (memo.containsKey(key)) return memo[key];
  // Cap the memo rather than let a page that overprints one image onto many
  // different backdrops pin a raster per backdrop for the document's lifetime.
  // Past the cap nothing is stored, so the buffer keeps declining rather than
  // silently serving a substitute built for a different backdrop.
  if (memo.length >= _maxSubstitutesPerImage) return null;
  final built = _buildSubstitute(
      cos, stream, resources, backdrop, backdropColor, mode, spotEquivalents);
  memo[key] = built;
  return built;
}

/// Rasters larger than this are not read: the uniformity scan and the
/// per-sample composite are both O(pixels), and the substitute holds three
/// bytes per pixel for as long as its source stream lives. 4 Mpx caps a
/// substitute at 12 MB. Past it an image reads as colorant-less, which is
/// exactly where image overprint stood before this existed.
const int _maxReadPixels = 4 << 20;

/// Distinct backdrops one image will build a substitute for.
const int _maxSubstitutesPerImage = 4;

/// Distinct sample tuples a substitute build will memoise the composite for.
const int _maxTupleMemo = 1 << 16;

final Expando<Object> _readings = Expando('pdfImageColorants');
final Object _noReading = Object();
final Expando<Map<_SubstituteKey, CosStream?>> _substitutes =
    Expando('pdfImageOverprintStream');

class _SubstituteKey {
  const _SubstituteKey(this.backdrop, this.mode);

  final PdfColorants backdrop;
  final int mode;

  @override
  bool operator ==(Object other) =>
      other is _SubstituteKey &&
      other.mode == mode &&
      other.backdrop == backdrop;

  @override
  int get hashCode => Object.hash(backdrop, mode);
}

PdfImageColorants? _readColorants(
    CosDocument cos, CosStream stream, CosDictionary? resources) {
  final samples = _ImageSamples.read(cos, stream, resources);
  if (samples == null) return null;
  final first = samples.inkAt(0, 0);
  if (first == null) return null; // the space has no colorant reading
  final dict = stream.dictionary;
  // An /SMask is a stream; a /Mask is a stencil stream or colour-key ranges.
  // Anything else there (typically /None) leaves the raster opaque.
  final smask = cos.resolve(dict['SMask']);
  final mask = cos.resolve(dict['Mask']);
  final covers = smask is! CosStream && mask is! CosStream && mask is! CosArray;
  if (!samples.isUniform) {
    return PdfImageColorants(
        uniformInk: null, uniformColor: PdfColor.black, coversQuad: covers);
  }
  return PdfImageColorants(
      uniformInk: first,
      uniformColor: samples.space.toSrgb(samples.valuesAt(0, 0)),
      coversQuad: covers);
}

CosStream? _buildSubstitute(
  CosDocument cos,
  CosStream stream,
  CosDictionary? resources,
  PdfColorants backdrop,
  PdfColor backdropColor,
  int mode,
  Map<String, List<double>> spotEquivalents,
) {
  final dict = stream.dictionary;
  // A colour-key /Mask selects transparent pixels by their *source* sample
  // ranges (§8.9.6.4); those ranges mean nothing against DeviceRGB samples,
  // and dropping the mask would paint pixels that must not appear.
  if (cos.resolve(dict['Mask']) is CosArray) return null;
  final samples = _ImageSamples.read(cos, stream, resources);
  if (samples == null) return null;
  if (samples.inkAt(0, 0) == null) return null;

  final width = samples.width, height = samples.height;
  final rgb = Uint8List(width * height * 3);
  // Spot equivalents seen on the page so far, plus whatever this image's own
  // space contributes - a composite naming a spot only the image carries still
  // has to convert back to sRGB.
  final spots = <String, List<double>>{...spotEquivalents};
  final memo = samples.canPackTuple ? <int, int>{} : null;
  var out = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final packed = memo == null ? 0 : samples.packedTuple(x, y);
      var value = memo == null ? null : memo[packed];
      if (value == null) {
        final ink = samples.inkAt(x, y);
        if (ink == null) return null;
        for (var i = 0; i < ink.colorants.spots.length; i++) {
          if (i < ink.spotEquivalents.length) {
            spots.putIfAbsent(
                ink.colorants.spots[i], () => ink.spotEquivalents[i]);
          }
        }
        final composite = ink.over(backdrop, mode);
        // The same exact-answer rule the vector compositor applies
        // (PdfOverprintCompositor._srgbFor): an overprint that changed nothing
        // must reuse the backdrop's own rendered pixels, and one that knocked
        // the backdrop out must reuse the ink's, so neither picks up a shade of
        // round-trip drift. Only a genuinely new combination converts through
        // the separations model.
        final PdfColor color;
        if (composite == backdrop) {
          color = backdropColor;
        } else if (composite == ink.colorants) {
          color = samples.space.toSrgb(samples.valuesAt(x, y));
        } else {
          color = colorantsToSrgb(composite, spots);
        }
        value = ((color.red * 255).round().clamp(0, 255) << 16) |
            ((color.green * 255).round().clamp(0, 255) << 8) |
            (color.blue * 255).round().clamp(0, 255);
        // Capped: press artwork reuses a handful of inks, but a noisy CMYK
        // photograph has no such working set, and an uncapped map would grow
        // an entry per distinct tuple. Past the cap it stops learning and
        // simply recomputes, which is what it did before the first hit.
        if (memo != null && memo.length < _maxTupleMemo) memo[packed] = value;
      }
      rgb[out++] = (value >> 16) & 0xff;
      rgb[out++] = (value >> 8) & 0xff;
      rgb[out++] = value & 0xff;
    }
  }

  final substitute = CosDictionary()
    ..['Type'] = const CosName('XObject')
    ..['Subtype'] = const CosName('Image')
    ..['Width'] = CosInteger(width)
    ..['Height'] = CosInteger(height)
    ..['ColorSpace'] = const CosName('DeviceRGB')
    ..['BitsPerComponent'] = const CosInteger(8);
  // Alpha and sampling are colour-independent: carry them through verbatim.
  for (final key in const ['SMask', 'Mask', 'Interpolate', 'Intent']) {
    final value = dict[key];
    if (value != null) substitute[key] = value;
  }
  return CosStream(substitute, rgb);
}

/// A readable view of an image XObject's samples in its own colour space.
///
/// Deliberately independent of `image_pixels.dart`'s RGBA decoders: those
/// answer "what pixels does this paint", and by the time they are done the
/// colorants are gone. This answers "what component values does each sample
/// hold", which is the only form overprint is defined over.
class _ImageSamples {
  _ImageSamples._({
    required this.data,
    required this.space,
    required this.width,
    required this.height,
    required this.bits,
    required this.components,
    required this.decode,
  })  : _rowBytes = (width * components * bits + 7) ~/ 8,
        _maxValue = ((1 << bits) - 1).toDouble(),
        _values = Float64List(components);

  /// Reads [stream]'s sample geometry, or null when its samples cannot be read
  /// in their own space.
  static _ImageSamples? read(
      CosDocument cos, CosStream stream, CosDictionary? resources) {
    final dict = stream.dictionary;
    // A stencil has no colour of its own - it paints the fill colour through
    // its alpha, and that colour is vector ink the buffer already handles.
    if (cos.resolve(dict['ImageMask']) == const CosBoolean(true)) return null;
    for (final filter in pdfImageFilters(cos, dict)) {
      // These decode straight to pixels (or, for JBIG2, through a decoder this
      // does not run); their samples are not in the stream's own bytes.
      if (filter == 'DCTDecode' ||
          filter == 'DCT' ||
          filter == 'JPXDecode' ||
          filter == 'JBIG2Decode') {
        return null;
      }
    }
    final width = _intOf(cos.resolve(dict['Width']));
    final height = _intOf(cos.resolve(dict['Height']));
    if (width <= 0 || height <= 0 || width * height > _maxReadPixels) {
      return null;
    }
    final bits = _intOf(cos.resolve(dict['BitsPerComponent']), fallback: 8);
    if (bits != 1 && bits != 2 && bits != 4 && bits != 8 && bits != 16) {
      return null;
    }
    final space =
        PdfColorSpace.parse(cos, dict['ColorSpace'], resources: resources);
    final components = space.channels;
    if (components <= 0) return null;
    // Decide "does this space have a colorant reading at all" before touching
    // the samples: a DeviceRGB / ICCBased / Lab raster - most photographic
    // content, and most of what a page draws - answers no, and must not pay to
    // decompress and scan a raster to find that out.
    if (space.inkColorants(Float64List(components)) == null) return null;
    final Uint8List data;
    try {
      data = cos.decodeStreamData(stream);
    } on Exception {
      return null;
    }
    if (data.length < ((width * components * bits + 7) ~/ 8) * height) {
      return null;
    }
    return _ImageSamples._(
      data: data,
      space: space,
      width: width,
      height: height,
      bits: bits,
      components: components,
      decode: _decodeRanges(cos, dict, space, components, bits),
    );
  }

  final Uint8List data;
  final PdfColorSpace space;
  final int width;
  final int height;
  final int bits;
  final int components;

  /// `[min0, max0, min1, max1, …]`, already defaulted for the space (§8.9.5.2:
  /// `[0 1]` per component, but `[0 2^bits-1]` for Indexed, whose samples are
  /// palette indices rather than tints).
  final Float64List decode;

  final int _rowBytes;
  final double _maxValue;
  final Float64List _values;

  /// True when [packedTuple] is usable - the memo key must stay inside the 32
  /// bits web integers handle exactly.
  bool get canPackTuple => bits == 8 && components <= 4;

  int packedTuple(int x, int y) {
    final base = y * _rowBytes + x * components;
    var packed = 0;
    for (var c = 0; c < components; c++) {
      packed |= data[base + c] << (c * 8);
    }
    return packed;
  }

  int rawAt(int x, int y, int c) {
    final index = x * components + c;
    if (bits == 8) return data[y * _rowBytes + index];
    if (bits == 16) {
      final offset = y * _rowBytes + index * 2;
      return (data[offset] << 8) | data[offset + 1];
    }
    final bit = index * bits;
    final byte = data[y * _rowBytes + (bit >> 3)];
    return (byte >> (8 - bits - (bit & 7))) & ((1 << bits) - 1);
  }

  /// The component values of the sample at ([x], [y]), in the space's own
  /// ranges. The returned list is reused across calls.
  Float64List valuesAt(int x, int y) {
    for (var c = 0; c < components; c++) {
      final min = decode[c * 2], max = decode[c * 2 + 1];
      _values[c] = min + rawAt(x, y, c) * (max - min) / _maxValue;
    }
    return _values;
  }

  PdfInkColorants? inkAt(int x, int y) => space.inkColorants(valuesAt(x, y));

  /// Whether every sample holds the same raw component tuple.
  ///
  /// Compared raw rather than as colorants: two different tuples *could* map to
  /// one colorant vector, so this is conservative, and being conservative here
  /// only means the image records as "colorants unknown" - the answer it gave
  /// before any of this. Early-exits, so the overwhelmingly common non-uniform
  /// raster costs a handful of samples.
  bool get isUniform {
    if (bits == 8 && _rowBytes == width * components) {
      // No row padding: the tuple repeats every [components] bytes, so this is
      // a tight typed-array walk rather than a per-sample unpack.
      final end = width * height * components;
      for (var i = components; i < end; i++) {
        if (data[i] != data[i - components]) return false;
      }
      return true;
    }
    final first = [for (var c = 0; c < components; c++) rawAt(0, 0, c)];
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        for (var c = 0; c < components; c++) {
          if (rawAt(x, y, c) != first[c]) return false;
        }
      }
    }
    return true;
  }
}

/// The /Decode array (§8.9.5.2) as `[min0, max0, min1, max1, …]`, defaulted per
/// space: `[0 1]` per component, but `[0 2^bits-1]` for Indexed, whose samples
/// are palette indices rather than tints.
Float64List _decodeRanges(CosDocument cos, CosDictionary dict,
    PdfColorSpace space, int components, int bits) {
  final top = space.family == 'Indexed' ? ((1 << bits) - 1).toDouble() : 1.0;
  Float64List defaults() {
    final ranges = Float64List(components * 2);
    for (var c = 0; c < components; c++) {
      ranges[c * 2 + 1] = top;
    }
    return ranges;
  }

  final raw = cos.resolve(dict['Decode']);
  if (raw is! CosArray || raw.length < components * 2) return defaults();
  final ranges = Float64List(components * 2);
  for (var i = 0; i < components * 2; i++) {
    final n = cos.resolve(raw[i]);
    if (n is CosInteger) {
      ranges[i] = n.value.toDouble();
    } else if (n is CosReal) {
      ranges[i] = n.value;
    } else {
      return defaults(); // malformed entry invalidates the whole array
    }
  }
  return ranges;
}

int _intOf(CosObject? value, {int fallback = 0}) => switch (value) {
      CosInteger(:final value) => value,
      CosReal(:final value) => value.round(),
      _ => fallback,
    };
