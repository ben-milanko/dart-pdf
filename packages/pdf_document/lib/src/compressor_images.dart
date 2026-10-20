import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as image;
import 'package:pdf_cos/pdf_cos.dart';

import 'document.dart';

/// Changes made by the optional, lossy image optimization pass.
class PdfImageOptimizationStats {
  PdfImageOptimizationStats({
    required this.imagesRecompressed,
    required this.bytesSaved,
    required List<String> warnings,
  }) : warnings = List.unmodifiable(warnings);

  final int imagesRecompressed;

  /// Encoded image payload bytes saved, before document serialization.
  final int bytesSaved;
  final List<String> warnings;
}

/// Downsamples eligible image XObjects to their largest placed size at
/// [targetDpi], and optionally re-encodes RGB samples as JPEG.
///
/// This is a **lossy** pass: callers must explicitly opt in. It updates the
/// document's loaded COS graph; a subsequent full rewrite is required to
/// persist the changes. Call it on an independently opened working document.
///
/// Eligible images are 8-bit DeviceRGB/DeviceGray with a single DCTDecode or
/// FlateDecode filter and no decode parameters, masks, or Decode array. Gray
/// output remains DeviceGray/Flate (the JPEG encoder emits three components).
/// Inline images and images used in annotation appearances, patterns, Type 3
/// fonts, soft masks, or contexts whose placement cannot be established are
/// preserved. Device color-space overrides, oriented EXIF JPEGs, and images
/// above 16 million pixels are also preserved. Nothing is upsampled, and an
/// encoded replacement is installed only when its payload is smaller.
PdfImageOptimizationStats optimizePdfImages(
  PdfDocument document, {
  required double targetDpi,
  required int jpegQuality,
}) {
  if (!targetDpi.isFinite || targetDpi <= 0) {
    throw ArgumentError.value(targetDpi, 'targetDpi', 'must be finite and > 0');
  }
  if (jpegQuality < 1 || jpegQuality > 100) {
    throw RangeError.range(jpegQuality, 1, 100, 'jpegQuality');
  }
  final scan = _ImagePlacementScan(document);
  try {
    scan.scan();
  } on Object {
    // No mutation occurs until the complete placement survey succeeds.
    return PdfImageOptimizationStats(
      imagesRecompressed: 0,
      bytesSaved: 0,
      warnings: const [
        'Images were preserved because their placements could not be fully '
            'inspected within the optimization limits.',
      ],
    );
  }

  final skipped = <String, int>{};
  void skip(String reason) =>
      skipped.update(reason, (n) => n + 1, ifAbsent: () => 1);
  var changed = 0;
  var saved = 0;
  for (final entry in scan.placements.entries) {
    final stream = entry.key;
    final placement = entry.value;
    final ref = document.cos.referenceTo(stream);
    if (ref == null || scan.unsafe.contains(stream)) {
      skip('unsupported or uncertain placement');
      continue;
    }
    try {
      final replacement = _optimizeImage(
          document.cos, stream, placement, targetDpi, jpegQuality, skip);
      if (replacement != null) {
        document.cos.adoptObject(ref, replacement);
        changed++;
        saved += stream.rawBytes.length - replacement.rawBytes.length;
      }
    } on Object {
      skip('image could not be decoded safely');
    }
  }
  return PdfImageOptimizationStats(
    imagesRecompressed: changed,
    bytesSaved: saved,
    warnings: [
      for (final entry in skipped.entries)
        '${entry.value} image(s) preserved: ${entry.key}.',
      if (scan.sawInlineImages) 'Inline images were preserved.',
    ],
  );
}

CosStream? _optimizeImage(
  CosDocument cos,
  CosStream stream,
  _ImagePlacement placement,
  double dpi,
  int quality,
  void Function(String) skip,
) {
  final dict = stream.dictionary;
  final width = _integer(cos.resolve(dict['Width']));
  final height = _integer(cos.resolve(dict['Height']));
  final color = cos.resolve(dict['ColorSpace']);
  var filter = cos.resolve(dict['Filter']);
  if (filter is CosArray && filter.length == 1) {
    filter = cos.resolve(filter[0]);
  }
  if (width == null ||
      height == null ||
      width <= 0 ||
      height <= 0 ||
      width * height > 16000000) {
    skip('invalid dimensions or more than 16 million pixels');
    return null;
  }
  if (_integer(cos.resolve(dict['BitsPerComponent'])) != 8 ||
      color is! CosName ||
      (color.value != 'DeviceRGB' && color.value != 'DeviceGray') ||
      filter is! CosName ||
      (filter.value != 'DCTDecode' && filter.value != 'FlateDecode') ||
      const [
        'Decode',
        'DecodeParms',
        'DP',
        'Mask',
        'SMask',
        'SMaskInData',
        'Alternates',
        'F',
        'FFilter',
        'FDecodeParms',
        'OPI'
      ].any(dict.containsKey) ||
      cos.resolve(dict['ImageMask']) == const CosBoolean(true)) {
    skip('color space, bit depth, filter, decode parameters, or masking');
    return null;
  }

  // Preserve the raster's aspect ratio. The most demanding axis of every
  // placement wins, including shears and rotations (basis-vector lengths).
  final neededWidth = placement.width * dpi / 72;
  final neededHeight = placement.height * dpi / 72;
  final ratio =
      math.min(1.0, math.max(neededWidth / width, neededHeight / height));
  final outWidth = (width * ratio).ceil().clamp(1, width);
  final outHeight = (height * ratio).ceil().clamp(1, height);
  final channels = color.value == 'DeviceGray' ? 1 : 3;
  image.Image decoded;
  if (filter.value == 'DCTDecode') {
    final bytes = cos.decodeStreamData(stream, stopBeforeFilter: 'DCTDecode');
    final decoder = image.JpegDecoder();
    final info = decoder.startDecode(bytes);
    if (info == null ||
        info.width != width ||
        info.height != height ||
        decoder.info!.numComponents != channels) {
      skip('JPEG dimensions or components disagree with its PDF dictionary');
      return null;
    }
    // package:image bakes EXIF orientation during JPEG decode; PDF does not.
    // Reject before decoding, including mirrors that retain width/height.
    final orientation = image.decodeJpgExif(bytes)?.imageIfd.orientation;
    if (orientation != null && orientation != 1) {
      skip('JPEG EXIF orientation');
      return null;
    }
    final pixels = decoder.decodeFrame(0);
    if (pixels == null) throw StateError('JPEG decoder returned no image');
    if (pixels.iccProfile != null) {
      skip('JPEG embedded ICC profile');
      return null;
    }
    decoded = pixels;
  } else {
    final bytes = cos.decodeStreamData(stream);
    if (bytes.length != width * height * channels) {
      skip('decoded sample count disagrees with image dimensions');
      return null;
    }
    decoded = image.Image.fromBytes(
      width: width,
      height: height,
      bytes: bytes.buffer,
      bytesOffset: bytes.offsetInBytes,
      numChannels: channels,
    );
  }
  if (outWidth != width || outHeight != height) {
    decoded = image.copyResize(decoded,
        width: outWidth,
        height: outHeight,
        interpolation: image.Interpolation.average);
  }

  // Strip container EXIF from the encoded raster; it is not PDF image state.
  decoded.exif = image.ExifData();
  final Uint8List payload;
  final String outputFilter;
  if (channels == 1) {
    payload = Uint8List.fromList(const ZLibEncoder().encodeBytes(
        decoded.getBytes(order: image.ChannelOrder.red),
        level: 9));
    outputFilter = 'FlateDecode';
  } else {
    payload = image.encodeJpg(decoded, quality: quality);
    outputFilter = 'DCTDecode';
  }
  if (payload.length >= stream.rawBytes.length) return null;
  final output = CosDictionary(Map.of(dict.entries))
    ..['Width'] = CosInteger(outWidth)
    ..['Height'] = CosInteger(outHeight)
    ..['Filter'] = CosName(outputFilter)
    ..['Length'] = CosInteger(payload.length);
  return CosStream(output, payload);
}

int? _integer(CosObject? value) => value is CosInteger ? value.value : null;

double? _number(CosObject? value) => switch (value) {
      CosInteger(:final value) => value.toDouble(),
      CosReal(:final value) when value.isFinite => value,
      _ => null,
    };

class _ImagePlacement {
  double width = 0;
  double height = 0;
  void include(PdfMatrix matrix) {
    width =
        math.max(width, math.sqrt(matrix.a * matrix.a + matrix.b * matrix.b));
    height =
        math.max(height, math.sqrt(matrix.c * matrix.c + matrix.d * matrix.d));
  }
}

class _ImagePlacementScan {
  _ImagePlacementScan(this.document);

  final PdfDocument document;
  CosDocument get cos => document.cos;
  final placements = <CosStream, _ImagePlacement>{};
  final unsafe = <CosStream>{};
  final _blockedVisited = <CosObject>{};
  var _operations = 0;
  var _graphNodes = 0;
  var sawInlineImages = false;

  void scan() {
    // AcroForm, appearance state dictionaries, tiling patterns, Type 3
    // CharProcs, and soft-mask groups can paint at additional unknown scales.
    for (final entry in document.catalog.entries.entries) {
      if (entry.key != 'Pages') _blockGraph(entry.value);
    }
    for (final page in document.pages) {
      for (final entry in page.dict.entries.entries) {
        if (!const {'Parent', 'Resources', 'Contents'}.contains(entry.key)) {
          _blockGraph(entry.value);
        }
      }
      final resources = page.resources;
      final rawUnit = cos.resolve(page.dict['UserUnit']);
      final unit = rawUnit is CosNull ? 1.0 : _number(rawUnit);
      if (unit == null || !unit.isFinite || unit <= 0) {
        _blockGraph(resources);
        continue;
      }
      try {
        _content(_pageBytes(page.dict['Contents']), resources,
            PdfMatrix.scaled(unit, unit), <CosStream>{});
      } on Object {
        _blockGraph(resources);
      }
    }
  }

  Uint8List _pageBytes(CosObject? raw) {
    final contents = cos.resolve(raw);
    if (contents is CosNull) return Uint8List(0);
    if (contents is CosStream) return cos.decodeStreamData(contents);
    if (contents is! CosArray) throw StateError('Invalid page contents');
    final out = BytesBuilder(copy: false);
    for (final item in contents.items) {
      final stream = cos.resolve(item);
      if (stream is! CosStream) throw StateError('Invalid content stream');
      out
        ..add(cos.decodeStreamData(stream))
        ..addByte(10);
    }
    return out.takeBytes();
  }

  void _content(Uint8List bytes, CosDictionary resources, PdfMatrix initial,
      Set<CosStream> active) {
    if (active.length > 64) throw StateError('Form nesting limit');
    for (final entry in resources.entries.entries) {
      if (entry.key != 'XObject') _blockGraph(entry.value);
    }
    final xObjects = cos.resolve(resources['XObject']);
    final colors = cos.resolve(resources['ColorSpace']);
    var ctm = initial;
    final stack = <PdfMatrix>[];
    final cursor = ContentStreamParser.cursor(bytes);
    ContentOperation? op;
    while ((op = cursor.nextOperation()) != null) {
      if (++_operations > 1000000) throw StateError('Operation limit');
      switch (op!.operator) {
        case 'q':
          if (stack.length >= 1024) throw StateError('Graphics-state limit');
          stack.add(ctm);
        case 'Q':
          if (stack.isEmpty) throw StateError('Unbalanced graphics state');
          ctm = stack.removeLast();
        case 'cm':
          ctm = _matrix(op.operands).concat(ctm);
          if (!ctm.toList().every((v) => v.isFinite)) {
            throw StateError('Invalid transformation');
          }
        case 'BI':
          sawInlineImages = true;
        case 'Do':
          if (op.operands.length != 1 ||
              op.operands.single is! CosName ||
              xObjects is! CosDictionary) {
            throw StateError('Invalid XObject invocation');
          }
          final name = (op.operands.single as CosName).value;
          final target = cos.resolve(xObjects[name]);
          if (target is! CosStream) throw StateError('Missing XObject');
          final dict = target.dictionary;
          final subtype = cos.resolve(dict['Subtype']);
          if (subtype == const CosName('Image')) {
            placements.putIfAbsent(target, _ImagePlacement.new).include(ctm);
            _blockGraph(dict); // Image masks and alternate renditions.
            final color = cos.resolve(dict['ColorSpace']);
            if (colors is CosDictionary &&
                ((color == const CosName('DeviceRGB') &&
                        colors.containsKey('DefaultRGB')) ||
                    (color == const CosName('DeviceGray') &&
                        colors.containsKey('DefaultGray')))) {
              unsafe.add(target);
            }
          } else if (subtype == const CosName('Form')) {
            if (!active.add(target)) throw StateError('Recursive Form');
            try {
              final ownResources = cos.resolve(dict['Resources']);
              if (ownResources is! CosNull && ownResources is! CosDictionary) {
                throw StateError('Invalid Form resources');
              }
              final formResources =
                  ownResources is CosDictionary ? ownResources : resources;
              for (final entry in dict.entries.entries) {
                if (entry.key != 'Resources') _blockGraph(entry.value);
              }
              final rawMatrix = cos.resolve(dict['Matrix']);
              final matrix = rawMatrix is CosNull
                  ? PdfMatrix.identity
                  : rawMatrix is CosArray
                      ? _matrix(rawMatrix.items)
                      : throw StateError('Invalid Form matrix');
              _content(cos.decodeStreamData(target), formResources,
                  matrix.concat(ctm), active);
            } finally {
              active.remove(target);
            }
          } else {
            throw StateError('Unsupported XObject');
          }
      }
    }
    if (stack.isNotEmpty) throw StateError('Unbalanced graphics state');
  }

  PdfMatrix _matrix(List<CosObject> row) {
    if (row.length != 6) throw StateError('Invalid matrix');
    final values = row.map((v) => _number(cos.resolve(v))).toList();
    if (values.any((v) => v == null)) throw StateError('Invalid matrix');
    return PdfMatrix.row(values.cast<double>());
  }

  void _blockGraph(CosObject? raw, [int depth = 0]) {
    final object = cos.resolve(raw);
    if (!_blockedVisited.add(object)) return;
    if (++_graphNodes > 100000 || depth > 128) {
      throw StateError('Resource graph limit');
    }
    switch (object) {
      case CosStream():
        if (cos.resolve(object.dictionary['Subtype']) ==
            const CosName('Image')) {
          unsafe.add(object);
        }
        _blockGraph(object.dictionary, depth + 1);
      case CosDictionary():
        // Resource/annotation backreferences must not sweep the page tree.
        if (object.typeName == 'Page' || object.typeName == 'Pages') return;
        for (final entry in object.entries.entries) {
          _blockGraph(entry.value, depth + 1);
        }
      case CosArray():
        for (final item in object.items) {
          _blockGraph(item, depth + 1);
        }
      default:
        break;
    }
  }
}
