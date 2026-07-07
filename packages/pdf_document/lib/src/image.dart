import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:pdf_cos/pdf_cos.dart';

import 'png.dart';

/// A raster image parsed and ready to embed as a PDF image XObject.
///
/// JPEGs pass through untouched (DCTDecode); PNGs are decoded and
/// re-compressed as FlateDecode samples, with any alpha channel split
/// into a /SMask. Use [PdfEmbeddableImage.decode] to sniff the format.
class PdfEmbeddableImage {
  PdfEmbeddableImage._(this.width, this.height, this._dict, this._data,
      this._smask);

  /// Pixel dimensions, for aspect-ratio math.
  final int width;
  final int height;

  final CosDictionary _dict;
  final Uint8List _data;
  final CosStream? _smask;

  /// Sniffs JPEG vs PNG from the magic bytes.
  factory PdfEmbeddableImage.decode(Uint8List bytes) {
    if (PngImage.isPng(bytes)) return PdfEmbeddableImage.png(bytes);
    if (bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
      return PdfEmbeddableImage.jpeg(bytes);
    }
    throw ArgumentError('unrecognized image format (expected JPEG or PNG)');
  }

  /// A baseline or progressive JPEG, embedded verbatim under DCTDecode.
  /// Gray and RGB only - CMYK JPEGs are rejected.
  factory PdfEmbeddableImage.jpeg(Uint8List bytes) {
    final info = readJpegInfo(bytes);
    return PdfEmbeddableImage._(
      info.width,
      info.height,
      CosDictionary({
        'ColorSpace':
            CosName(info.components == 1 ? 'DeviceGray' : 'DeviceRGB'),
        'BitsPerComponent': const CosInteger(8),
        'Filter': const CosName('DCTDecode'),
      }),
      bytes,
      null,
    );
  }

  /// A PNG, decoded and re-compressed as Flate samples. Transparency
  /// (alpha channels, palette tRNS, color keys) becomes a /SMask.
  factory PdfEmbeddableImage.png(Uint8List bytes) {
    final png = PngImage.decode(bytes);
    final data = _deflate(png.samples);
    CosStream? smask;
    final alpha = png.alpha;
    if (alpha != null) {
      final alphaData = _deflate(alpha);
      smask = CosStream(
        CosDictionary({
          'Type': const CosName('XObject'),
          'Subtype': const CosName('Image'),
          'Width': CosInteger(png.width),
          'Height': CosInteger(png.height),
          'ColorSpace': const CosName('DeviceGray'),
          'BitsPerComponent': const CosInteger(8),
          'Filter': const CosName('FlateDecode'),
          'Length': CosInteger(alphaData.length),
        }),
        alphaData,
      );
    }
    return PdfEmbeddableImage._(
      png.width,
      png.height,
      CosDictionary({
        'ColorSpace':
            CosName(png.components == 1 ? 'DeviceGray' : 'DeviceRGB'),
        'BitsPerComponent': const CosInteger(8),
        'Filter': const CosName('FlateDecode'),
      }),
      data,
      smask,
    );
  }

  /// Builds the image XObject. When the image carries transparency,
  /// [addObject] registers the soft-mask stream so /SMask can reference
  /// it indirectly (a requirement of the spec - /SMask is a stream).
  CosStream toXObject(CosReference Function(CosStream) addObject) {
    final dict = CosDictionary({
      'Type': const CosName('XObject'),
      'Subtype': const CosName('Image'),
      'Width': CosInteger(width),
      'Height': CosInteger(height),
      ..._dict.entries,
      'Length': CosInteger(_data.length),
    });
    final smask = _smask;
    if (smask != null) dict['SMask'] = addObject(smask);
    return CosStream(dict, _data);
  }

  static Uint8List _deflate(Uint8List data) =>
      Uint8List.fromList(const ZLibEncoder().encode(data));
}

class JpegInfo {
  JpegInfo(this.width, this.height, this.components);
  final int width;
  final int height;
  final int components;
}

/// Reads dimensions from a JPEG's start-of-frame marker.
JpegInfo readJpegInfo(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
    throw ArgumentError('not a JPEG (missing SOI marker)');
  }
  var p = 2;
  while (p + 9 < bytes.length) {
    if (bytes[p] != 0xFF) {
      p++;
      continue;
    }
    final marker = bytes[p + 1];
    // standalone markers without a length
    if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
      p += 2;
      continue;
    }
    final length = (bytes[p + 2] << 8) | bytes[p + 3];
    final isSof = marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC;
    if (isSof) {
      final components = bytes[p + 9];
      if (components == 4) {
        throw ArgumentError('CMYK JPEGs are not supported for embedding');
      }
      return JpegInfo(
        (bytes[p + 7] << 8) | bytes[p + 8],
        (bytes[p + 5] << 8) | bytes[p + 6],
        components,
      );
    }
    p += 2 + length;
  }
  throw ArgumentError('no JPEG start-of-frame marker found');
}
