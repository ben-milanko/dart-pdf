// The exact masked-image region kernel (decodePdfImagePixelsRegionScaled for
// an 8-bit DeviceRGB/DeviceGray Flate base under a same-size stencil /Mask or
// 8-bit /SMask) must reproduce the general path it replaces byte for byte:
// the full decode, cropped and box-filtered.
//
// No dart:io, so the same cases run under dart2js too:
//   dart test test/image_masked_region_test.dart
//   dart test -p node test/image_masked_region_test.dart
import 'dart:math';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/icc_profiles.dart';
import 'package:test/test.dart';

CosStream _flate(Map<String, CosObject> dict, Uint8List data) => CosStream(
    CosDictionary({...dict, 'Filter': const CosName('FlateDecode')}),
    _storedZlib(data));

/// [data] as a zlib stream of stored (uncompressed) deflate blocks: valid
/// FlateDecode input without an encoder dependency.
Uint8List _storedZlib(Uint8List data) {
  final out = BytesBuilder()..add([0x78, 0x01]);
  for (var at = 0; at < data.length || at == 0; at += 0xffff) {
    final end = at + 0xffff < data.length ? at + 0xffff : data.length;
    final length = end - at;
    out
      ..addByte(end == data.length ? 1 : 0) // BFINAL, BTYPE 00
      ..add([length & 0xff, length >> 8, ~length & 0xff, (~length >> 8) & 0xff])
      ..add(Uint8List.sublistView(data, at, end));
    if (end == data.length) break;
  }
  var a = 1, b = 0;
  for (final byte in data) {
    a = (a + byte) % 65521;
    b = (b + a) % 65521;
  }
  return (out..add([b >> 8, b & 0xff, a >> 8, a & 0xff])).takeBytes();
}

/// What the kernel stands in for: decode everything, then crop and filter.
PdfDecodedPixels? _reference(CosDocument cos, CosStream stream, int sx, int sy,
    int sw, int sh, int tw, int th) {
  final full = decodePdfImagePixels(cos, stream);
  return full == null
      ? null
      : cropDownsamplePdfDecodedPixels(full, sx, sy, sw, sh, tw, th);
}

/// An empty document; with [outputIntent] its catalog names a CMYK press
/// profile as its PDF/X output intent, which maps DeviceGray through the
/// output condition.
CosDocument _document({bool outputIntent = false}) {
  final builder = CosDocumentBuilder();
  final pages = builder.add(CosDictionary({
    'Type': const CosName('Pages'),
    'Kids': CosArray(),
    'Count': const CosInteger(0),
  }));
  final catalog = builder.add(CosDictionary({
    'Type': const CosName('Catalog'),
    'Pages': pages,
    if (outputIntent)
      'OutputIntents': CosArray([
        CosDictionary({
          'Type': const CosName('OutputIntent'),
          'S': const CosName('GTS_PDFX'),
          'DestOutputProfile': builder.add(CosStream(
              CosDictionary({'N': const CosInteger(4)}), genericCmykIcc())),
        }),
      ]),
  }));
  return CosDocument.open(builder.build(root: catalog));
}

/// A random masked 8-bit image: odd sizes, both colour spaces, and every mask
/// kind - a stencil in either /Decode polarity (sparse, dense, or blank), or
/// an 8-bit soft mask with runs of 0 and 255 between partial coverage.
({CosStream stream, int width, int height, bool rgb, int kind})
    _randomMaskedImage(Random random, int trial) {
  final width = 17 + 2 * random.nextInt(34);
  final height = 9 + 2 * random.nextInt(27);
  final rgb = trial.isEven;
  final components = rgb ? 3 : 1;
  final kind = trial % 3; // 0 stencil, 1 inverted stencil, 2 soft
  final samples = Uint8List(width * height * components);
  for (var i = 0; i < samples.length; i++) {
    samples[i] = random.nextInt(256);
  }
  final CosStream mask;
  if (kind == 2) {
    final alpha = Uint8List(width * height);
    for (var i = 0; i < alpha.length; i++) {
      alpha[i] = switch (random.nextInt(4)) {
        0 => 0,
        1 => 255,
        _ => random.nextInt(256),
      };
    }
    mask = _flate({
      'Type': const CosName('XObject'),
      'Subtype': const CosName('Image'),
      'Width': CosInteger(width),
      'Height': CosInteger(height),
      'ColorSpace': const CosName('DeviceGray'),
      'BitsPerComponent': const CosInteger(8),
    }, alpha);
  } else {
    final rowBytes = (width + 7) >> 3;
    final inverted = kind == 1;
    final bits = Uint8List(rowBytes * height)
      ..fillRange(0, rowBytes * height, inverted ? 0x00 : 0xff);
    final density = random.nextInt(3);
    for (var i = 0; i < bits.length; i++) {
      if (density == 2 || random.nextInt(8) < density * 2) {
        bits[i] = random.nextInt(256);
      }
    }
    mask = _flate({
      'Type': const CosName('XObject'),
      'Subtype': const CosName('Image'),
      'ImageMask': const CosBoolean(true),
      'Width': CosInteger(width),
      'Height': CosInteger(height),
      'BitsPerComponent': const CosInteger(1),
      if (inverted)
        'Decode': CosArray([const CosInteger(1), const CosInteger(0)]),
    }, bits);
  }
  final stream = _flate({
    'Type': const CosName('XObject'),
    'Subtype': const CosName('Image'),
    'Width': CosInteger(width),
    'Height': CosInteger(height),
    'ColorSpace': CosName(rgb ? 'DeviceRGB' : 'DeviceGray'),
    'BitsPerComponent': const CosInteger(8),
    kind == 2 ? 'SMask' : 'Mask': mask,
  }, samples);
  return (stream: stream, width: width, height: height, rgb: rgb, kind: kind);
}

void main() {
  late CosDocument cos;
  setUp(() => cos = _document());

  test('matches the full decode, cropped and box-filtered (randomized)', () {
    final random = Random(20260927);
    for (var trial = 0; trial < 24; trial++) {
      final (:stream, :width, :height, :rgb, :kind) =
          _randomMaskedImage(random, trial);
      final regions = [
        (0, 0, width, height), // whole image, as a region
        (0, 0, width, height),
        for (var i = 0; i < 3; i++)
          () {
            final sx = random.nextInt(width), sy = random.nextInt(height);
            return (
              sx,
              sy,
              1 + random.nextInt(width - sx),
              1 + random.nextInt(height - sy),
            );
          }(),
      ];
      for (final (i, (sx, sy, sw, sh)) in regions.indexed) {
        // 1:1 crops, downscales, and one oversized target (clamped).
        final tw = i == 1 ? sw : (i == 4 ? sw + 3 : 1 + random.nextInt(sw));
        final th = i == 1 ? sh : (i == 4 ? sh + 2 : 1 + random.nextInt(sh));
        final expected = _reference(cos, stream, sx, sy, sw, sh, tw, th)!;
        final direct = decodePdfImagePixelsRegionScaled(
            cos, stream, sx, sy, sw, sh, tw, th);
        final reason = 'trial $trial ${rgb ? 'rgb' : 'gray'} kind $kind '
            '${width}x$height region ($sx,$sy ${sw}x$sh) -> ${tw}x$th';
        expect(direct, isNotNull, reason: '$reason: kernel declined');
        expect(direct!.width, expected.width, reason: reason);
        expect(direct.height, expected.height, reason: reason);
        expect(direct.rgba, expected.rgba, reason: reason);
        final viaFacade = decodePdfImage(cos, stream,
            region: PdfImageRegion(sx, sy, sw, sh),
            targetWidth: tw,
            targetHeight: th);
        expect(viaFacade!.rgba, expected.rgba, reason: reason);
      }
    }
  });

  test('same-size slices are the full decode, cropped', () {
    // Deep zoom at or past native resolution asks for a region at 1:1 (a
    // larger target clamps to it), which the kernel writes straight out
    // rather than summing: unaligned edges, every mask kind, both spaces.
    final random = Random(20260929);
    for (var trial = 0; trial < 24; trial++) {
      final (:stream, :width, :height, :rgb, :kind) =
          _randomMaskedImage(random, trial);
      for (var i = 0; i < 4; i++) {
        final sx = random.nextInt(width), sy = random.nextInt(height);
        final sw = 1 + random.nextInt(width - sx);
        final sh = 1 + random.nextInt(height - sy);
        final (tw, th) = i.isEven ? (sw, sh) : (sw + 1 + i, sh * 2);
        final expected = _reference(cos, stream, sx, sy, sw, sh, tw, th)!;
        final direct = decodePdfImagePixelsRegionScaled(
            cos, stream, sx, sy, sw, sh, tw, th);
        final reason = 'trial $trial ${rgb ? 'rgb' : 'gray'} kind $kind '
            '${width}x$height region ($sx,$sy ${sw}x$sh) -> ${tw}x$th';
        expect(direct, isNotNull, reason: '$reason: kernel declined');
        expect(direct!.width, sw, reason: reason);
        expect(direct.height, sh, reason: reason);
        expect(direct.rgba, expected.rgba, reason: reason);
      }
    }
  });

  test('whole-image masked downscales are the full decode, box-filtered', () {
    // The render worker's own case: a masked tile drawn smaller than native.
    final random = Random(20260928);
    for (var trial = 0; trial < 24; trial++) {
      final (:stream, :width, :height, :rgb, :kind) =
          _randomMaskedImage(random, trial);
      final tw = 1 + random.nextInt(width - 1);
      final th = 1 + random.nextInt(height);
      final expected = downsamplePdfDecodedPixels(
          decodePdfImagePixels(cos, stream)!, tw, th);
      final pixels =
          decodePdfImage(cos, stream, targetWidth: tw, targetHeight: th)!;
      final reason = 'trial $trial ${rgb ? 'rgb' : 'gray'} kind $kind '
          '${width}x$height -> ${tw}x$th';
      expect(pixels.width, expected.width, reason: reason);
      expect(pixels.height, expected.height, reason: reason);
      expect(pixels.rgba, expected.rgba, reason: reason);
    }
  });

  test('masked DeviceGray under an OutputIntent keeps the mapped reference',
      () {
    // Under a PDF/X OutputIntent, DeviceGray is the output condition's K-only
    // ramp, not the raw byte: the kernel copies bytes, so it must decline.
    final doc = _document(outputIntent: true);
    const width = 12, height = 10;
    final gray = Uint8List(width * height)..fillRange(0, width * height, 128);
    final alpha = Uint8List(width * height);
    for (var i = 0; i < alpha.length; i++) {
      alpha[i] = i.isEven ? 255 : 90;
    }
    final stream = _flate({
      'Width': const CosInteger(width),
      'Height': const CosInteger(height),
      'ColorSpace': const CosName('DeviceGray'),
      'BitsPerComponent': const CosInteger(8),
      'SMask': _flate({
        'Width': const CosInteger(width),
        'Height': const CosInteger(height),
        'ColorSpace': const CosName('DeviceGray'),
        'BitsPerComponent': const CosInteger(8),
      }, alpha),
    }, gray);
    expect(decodePdfImagePixelsRegionScaled(doc, stream, 2, 2, 8, 6, 4, 3),
        isNull);
    final expected = _reference(doc, stream, 2, 2, 8, 6, 4, 3)!;
    final pixels = decodePdfImage(doc, stream,
        region: const PdfImageRegion(2, 2, 8, 6),
        targetWidth: 4,
        targetHeight: 3)!;
    expect(pixels.rgba, expected.rgba);
    // The mapping is real: the identity byte would be 128 at full coverage.
    final full = decodePdfImagePixels(doc, stream)!;
    expect(full.rgba[0], isNot(128));
  });

  test('declines the shapes it does not reproduce exactly', () {
    const width = 16, height = 8;
    final samples = Uint8List(width * height * 3);
    for (var i = 0; i < samples.length; i++) {
      samples[i] = i * 37 & 0xff;
    }
    CosStream withMask(String key, CosStream mask,
            [Map<String, CosObject> extra = const {}]) =>
        _flate({
          'Width': const CosInteger(width),
          'Height': const CosInteger(height),
          'ColorSpace': const CosName('DeviceRGB'),
          'BitsPerComponent': const CosInteger(8),
          key: mask,
          ...extra,
        }, samples);
    CosStream soft(Map<String, CosObject> extra, {int w = width}) => _flate({
          'Width': CosInteger(w),
          'Height': const CosInteger(height),
          'ColorSpace': const CosName('DeviceGray'),
          'BitsPerComponent': const CosInteger(8),
          ...extra,
        }, Uint8List(w * height)..fillRange(0, w * height, 200));
    final shapes = {
      'matte': withMask(
          'SMask',
          soft({
            'Matte': CosArray(
                [const CosInteger(1), const CosInteger(1), const CosInteger(1)])
          })),
      'smaller soft mask': withMask('SMask', soft(const {}, w: 8)),
      'decode on the base': withMask('SMask', soft(const {}), {
        'Decode': CosArray([
          const CosInteger(1),
          const CosInteger(0),
          const CosInteger(1),
          const CosInteger(0),
          const CosInteger(1),
          const CosInteger(0),
        ]),
      }),
    };
    for (final MapEntry(key: name, value: stream) in shapes.entries) {
      expect(decodePdfImagePixelsRegionScaled(cos, stream, 0, 0, 16, 8, 4, 2),
          isNull,
          reason: name);
      final expected = _reference(cos, stream, 0, 0, 16, 8, 4, 2)!;
      final pixels = decodePdfImage(cos, stream,
          region: const PdfImageRegion(0, 0, 16, 8),
          targetWidth: 4,
          targetHeight: 2)!;
      expect(pixels.rgba, expected.rgba, reason: name);
    }
  });

  test('a cell too large for 32-bit sums falls back to the full decode', () {
    // 3000 x 3000 into one pixel: 9M samples of alpha 255 overflow a 32-bit
    // column sum, so the kernel must decline rather than wrap.
    const side = 3000;
    final gray = Uint8List(side * side)..fillRange(0, side * side, 200);
    final alpha = Uint8List(side * side)..fillRange(0, side * side, 255);
    final stream = _flate({
      'Width': const CosInteger(side),
      'Height': const CosInteger(side),
      'ColorSpace': const CosName('DeviceGray'),
      'BitsPerComponent': const CosInteger(8),
      'SMask': _flate({
        'Width': const CosInteger(side),
        'Height': const CosInteger(side),
        'ColorSpace': const CosName('DeviceGray'),
        'BitsPerComponent': const CosInteger(8),
      }, alpha),
    }, gray);
    expect(
        decodePdfImagePixelsRegionScaled(cos, stream, 0, 0, side, side, 1, 1),
        isNull);
    final pixels = decodePdfImage(cos, stream,
        region: const PdfImageRegion(0, 0, side, side),
        targetWidth: 1,
        targetHeight: 1)!;
    expect(pixels.rgba, [200, 200, 200, 255]);
  });
}
