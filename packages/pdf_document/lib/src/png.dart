import 'dart:typed_data';

import 'package:archive/archive.dart';

/// A decoded PNG, normalized for PDF embedding: 8-bit samples, gray or
/// RGB, with the alpha channel (if any) split off for a /SMask.
///
/// Supports the full baseline format: bit depths 1/2/4/8/16, color types
/// 0 (gray), 2 (RGB), 3 (palette), 4 (gray+alpha), 6 (RGBA), tRNS
/// transparency (palette and color-key), and Adam7 interlacing. 16-bit
/// samples are reduced to their high byte.
class PngImage {
  PngImage._(this.width, this.height, this.components, this.samples,
      this.alpha);

  final int width;
  final int height;

  /// 1 (DeviceGray) or 3 (DeviceRGB).
  final int components;

  /// Row-major samples, [components] bytes per pixel.
  final Uint8List samples;

  /// One byte per pixel when the PNG carries transparency, else null.
  final Uint8List? alpha;

  static bool isPng(Uint8List bytes) =>
      bytes.length > 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47;

  static PngImage decode(Uint8List bytes) {
    if (!isPng(bytes)) {
      throw ArgumentError('not a PNG (missing signature)');
    }
    var width = 0, height = 0, bitDepth = 8, colorType = 0, interlace = 0;
    Uint8List? palette;
    Uint8List? transparency;
    final idat = BytesBuilder(copy: false);
    var p = 8;
    while (p + 8 <= bytes.length) {
      final length = _be32(bytes, p);
      final type = String.fromCharCodes(bytes, p + 4, p + 8);
      final data = Uint8List.sublistView(
          bytes, p + 8, (p + 8 + length).clamp(0, bytes.length));
      switch (type) {
        case 'IHDR':
          if (data.length < 13) throw ArgumentError('truncated IHDR');
          width = _be32(data, 0);
          height = _be32(data, 4);
          bitDepth = data[8];
          colorType = data[9];
          interlace = data[12];
        case 'PLTE':
          palette = data;
        case 'tRNS':
          transparency = data;
        case 'IDAT':
          idat.add(data);
        case 'IEND':
          p = bytes.length;
          continue;
      }
      p += 12 + length; // length + type + data + CRC
    }
    if (width <= 0 || height <= 0) {
      throw ArgumentError('invalid PNG dimensions');
    }
    const channelCounts = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4};
    final channels = channelCounts[colorType];
    if (channels == null) {
      throw ArgumentError('unsupported PNG color type $colorType');
    }
    if (![1, 2, 4, 8, 16].contains(bitDepth)) {
      throw ArgumentError('unsupported PNG bit depth $bitDepth');
    }

    // decodeBytes already returns a freshly allocated Uint8List (#533).
    final raw = const ZLibDecoder().decodeBytes(idat.takeBytes());

    // raw channel data, 8 bits per channel, full image. Palette indices
    // must stay verbatim - only real samples scale to 0–255.
    final scale = colorType != 3;
    final pixels = interlace == 1
        ? _deinterlace(raw, width, height, channels, bitDepth, scale)
        : _unfilterImage(raw, 0, width, height, channels, bitDepth,
            Uint8List(width * height * channels),
            scaleSubByte: scale)
            .$1;

    return _normalize(
        width, height, colorType, pixels, channels, palette, transparency,
        bitDepth);
  }

  /// Converts unfiltered channel data into gray/RGB samples + alpha.
  static PngImage _normalize(int width, int height, int colorType,
      Uint8List pixels, int channels, Uint8List? palette,
      Uint8List? transparency, int bitDepth) {
    final count = width * height;
    switch (colorType) {
      case 0: // grayscale (+ optional color-key tRNS)
        Uint8List? alpha;
        if (transparency != null && transparency.length >= 2) {
          final key = _keyByte(transparency, 0, bitDepth);
          alpha = Uint8List(count);
          for (var i = 0; i < count; i++) {
            alpha[i] = pixels[i] == key ? 0 : 255;
          }
        }
        return PngImage._(width, height, 1, pixels, alpha);
      case 2: // RGB (+ optional color-key tRNS)
        Uint8List? alpha;
        if (transparency != null && transparency.length >= 6) {
          final r = _keyByte(transparency, 0, bitDepth);
          final g = _keyByte(transparency, 2, bitDepth);
          final b = _keyByte(transparency, 4, bitDepth);
          alpha = Uint8List(count);
          for (var i = 0; i < count; i++) {
            alpha[i] = pixels[i * 3] == r &&
                    pixels[i * 3 + 1] == g &&
                    pixels[i * 3 + 2] == b
                ? 0
                : 255;
          }
        }
        return PngImage._(width, height, 3, pixels, alpha);
      case 3: // palette
        final plte = palette ?? Uint8List(0);
        final rgb = Uint8List(count * 3);
        Uint8List? alpha;
        if (transparency != null) alpha = Uint8List(count);
        var anyTransparent = false;
        for (var i = 0; i < count; i++) {
          // indexed samples were expanded to 8 bits without scaling
          final index = pixels[i];
          final base = index * 3;
          if (base + 2 < plte.length) {
            rgb[i * 3] = plte[base];
            rgb[i * 3 + 1] = plte[base + 1];
            rgb[i * 3 + 2] = plte[base + 2];
          }
          if (alpha != null) {
            final a = index < transparency!.length ? transparency[index] : 255;
            alpha[i] = a;
            if (a != 255) anyTransparent = true;
          }
        }
        return PngImage._(
            width, height, 3, rgb, anyTransparent ? alpha : null);
      case 4: // gray + alpha
        final gray = Uint8List(count);
        final alpha = Uint8List(count);
        for (var i = 0; i < count; i++) {
          gray[i] = pixels[i * 2];
          alpha[i] = pixels[i * 2 + 1];
        }
        return PngImage._(width, height, 1, gray, alpha);
      default: // 6: RGBA
        final rgb = Uint8List(count * 3);
        final alpha = Uint8List(count);
        for (var i = 0; i < count; i++) {
          rgb[i * 3] = pixels[i * 4];
          rgb[i * 3 + 1] = pixels[i * 4 + 1];
          rgb[i * 3 + 2] = pixels[i * 4 + 2];
          alpha[i] = pixels[i * 4 + 3];
        }
        return PngImage._(width, height, 3, rgb, alpha);
    }
  }

  /// A tRNS color key reduced the same way samples are: 16-bit values by
  /// their high byte, sub-byte depths scaled to 8 bits.
  static int _keyByte(Uint8List trns, int offset, int bitDepth) {
    final value = (trns[offset] << 8) | trns[offset + 1];
    return switch (bitDepth) {
      16 => value >> 8,
      8 => value & 0xFF,
      _ => ((value & ((1 << bitDepth) - 1)) * 255) ~/ ((1 << bitDepth) - 1),
    };
  }

  /// Unfilters [height] rows of a (sub)image starting at [offset] in the
  /// inflated stream, writing 8-bit channel values into [out]. Returns
  /// (out, bytes consumed). Sub-byte depths are expanded per pixel -
  /// scaled to 0–255 except for palette indices, which stay raw (the
  /// caller distinguishes via the palette path reading them verbatim;
  /// scaling is suppressed there by [scaleSubByte]).
  static (Uint8List, int) _unfilterImage(Uint8List raw, int offset, int width,
      int height, int channels, int bitDepth, Uint8List out,
      {bool scaleSubByte = true}) {
    final bitsPerPixel = channels * bitDepth;
    final rowBytes = (width * bitsPerPixel + 7) >> 3;
    final bpp = (bitsPerPixel + 7) >> 3;
    final prior = Uint8List(rowBytes);
    final row = Uint8List(rowBytes);
    var p = offset;
    final stride = width * channels;
    for (var y = 0; y < height; y++) {
      if (p >= raw.length) break; // truncated data: keep what decoded
      final filter = raw[p++];
      final available = (raw.length - p).clamp(0, rowBytes);
      row.fillRange(0, rowBytes, 0);
      row.setRange(0, available, Uint8List.sublistView(raw, p, p + available));
      p += available;
      switch (filter) {
        case 1: // Sub
          for (var i = bpp; i < rowBytes; i++) {
            row[i] = (row[i] + row[i - bpp]) & 0xFF;
          }
        case 2: // Up
          for (var i = 0; i < rowBytes; i++) {
            row[i] = (row[i] + prior[i]) & 0xFF;
          }
        case 3: // Average
          for (var i = 0; i < rowBytes; i++) {
            final left = i >= bpp ? row[i - bpp] : 0;
            row[i] = (row[i] + ((left + prior[i]) >> 1)) & 0xFF;
          }
        case 4: // Paeth
          for (var i = 0; i < rowBytes; i++) {
            final left = i >= bpp ? row[i - bpp] : 0;
            final upLeft = i >= bpp ? prior[i - bpp] : 0;
            row[i] = (row[i] + _paeth(left, prior[i], upLeft)) & 0xFF;
          }
      }
      prior.setAll(0, row);
      _emitRow(row, width, channels, bitDepth, scaleSubByte, out,
          y * stride, channels);
    }
    return (out, p - offset);
  }

  /// Expands one unfiltered row to 8-bit channel values at [outBase],
  /// advancing [outStep] bytes per pixel (for interlace placement).
  static void _emitRow(Uint8List row, int width, int channels, int bitDepth,
      bool scale, Uint8List out, int outBase, int outStep) {
    var o = outBase;
    if (bitDepth == 8) {
      for (var x = 0; x < width; x++) {
        for (var c = 0; c < channels; c++) {
          out[o + c] = row[x * channels + c];
        }
        o += outStep;
      }
    } else if (bitDepth == 16) {
      for (var x = 0; x < width; x++) {
        for (var c = 0; c < channels; c++) {
          out[o + c] = row[(x * channels + c) * 2];
        }
        o += outStep;
      }
    } else {
      final max = (1 << bitDepth) - 1;
      for (var x = 0; x < width; x++) {
        final bit = x * bitDepth;
        final value = (row[bit >> 3] >> (8 - bitDepth - (bit & 7))) & max;
        out[o] = scale ? (value * 255) ~/ max : value;
        o += outStep;
      }
    }
  }

  static int _paeth(int a, int b, int c) {
    final p = a + b - c;
    final pa = (p - a).abs(), pb = (p - b).abs(), pc = (p - c).abs();
    if (pa <= pb && pa <= pc) return a;
    return pb <= pc ? b : c;
  }

  /// Adam7: seven sub-images, each filtered independently.
  static Uint8List _deinterlace(Uint8List raw, int width, int height,
      int channels, int bitDepth, bool scaleSubByte) {
    const xStart = [0, 4, 0, 2, 0, 1, 0];
    const yStart = [0, 0, 4, 0, 2, 0, 1];
    const xStep = [8, 8, 4, 4, 2, 2, 1];
    const yStep = [8, 8, 8, 4, 4, 2, 2];
    final out = Uint8List(width * height * channels);
    var offset = 0;
    for (var pass = 0; pass < 7; pass++) {
      final passWidth = (width - xStart[pass] + xStep[pass] - 1) ~/ xStep[pass];
      final passHeight =
          (height - yStart[pass] + yStep[pass] - 1) ~/ yStep[pass];
      if (passWidth <= 0 || passHeight <= 0) continue;
      final pixels = Uint8List(passWidth * passHeight * channels);
      final (_, consumed) = _unfilterImage(
          raw, offset, passWidth, passHeight, channels, bitDepth, pixels,
          scaleSubByte: false);
      offset += consumed;
      // place: pass pixels keep raw sub-byte values; scale once here
      final max = (1 << bitDepth) - 1;
      for (var y = 0; y < passHeight; y++) {
        final destY = yStart[pass] + y * yStep[pass];
        if (destY >= height) break;
        for (var x = 0; x < passWidth; x++) {
          final destX = xStart[pass] + x * xStep[pass];
          if (destX >= width) break;
          final src = (y * passWidth + x) * channels;
          final dest = (destY * width + destX) * channels;
          for (var c = 0; c < channels; c++) {
            var value = pixels[src + c];
            if (bitDepth < 8 && scaleSubByte) value = (value * 255) ~/ max;
            out[dest + c] = value;
          }
        }
      }
    }
    return out;
  }

  static int _be32(Uint8List bytes, int offset) =>
      (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
}
