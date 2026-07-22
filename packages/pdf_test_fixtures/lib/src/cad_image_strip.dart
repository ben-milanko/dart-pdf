import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:pdf_cos/pdf_cos.dart';

/// How a tile's pixels are encoded into the PDF.
enum PdfTileCodec {
  /// `FlateDecode` 8-bit RGB - what the real drawing uses.
  flateRgb,

  /// `FlateDecode` 1-bit `/ImageMask` stencil - the linework layer.
  imageMask,

  /// `FlateDecode` 8-bit `/Indexed` palette.
  indexed,

  /// `DCTDecode` - payload supplied by the caller.
  jpeg,

  /// `JPXDecode` - payload supplied by the caller.
  jpeg2000,
}

/// One image tile placed on the sheet.
class PdfTileSpec {
  const PdfTileSpec({
    required this.codec,
    required this.width,
    required this.height,
    this.payload,
  });

  final PdfTileCodec codec;
  final int width;
  final int height;

  /// Pre-encoded bytes for [PdfTileCodec.jpeg] / [PdfTileCodec.jpeg2000].
  ///
  /// Those two are produced by external encoders (`cjpeg`, `opj_compress`)
  /// because this library has no `dart:io` and ships no codecs - the tool that
  /// writes the fixture supplies them. The Flate variants are generated here,
  /// so the common case needs nothing external.
  final Uint8List? payload;
}

/// Builds the **image-heavy** variant of the wide CAD strip
/// (`buildSyntheticCadStrip`): the same ~8504 x 842 pt single-sheet drawing,
/// with a grid of large raster tiles composited under the linework.
///
/// The shape is taken from a real 62 MB cathodic-protection sheet, profiled
/// rather than guessed:
///
/// ```
/// images: 1386  (93% of file bytes)
/// dimensions: 2048x1754 x1385
/// colorspaces: 923 ImageMask (1-bit), 445 DeviceRGB (8-bit), 18 Indexed
/// smasks: 0        filters: FlateDecode only
/// content: 8 streams, 3.93 MB raw -> 24.75 MB decoded
/// total pixels: 4975 Mpx  ->  ~19.9 GB if every tile were decoded to RGBA
/// ```
///
/// That last line is the point of the fixture: a 62 MB file that can ask for
/// ~20 GB of decoded RGBA is what stresses the decoded-image cache budget, and
/// the 1-bit `/ImageMask` stencil path is not covered by any other perf
/// document. Tiles are drawn in a row across the strip so a horizontal pan
/// crosses many of them, which is how the real sheet is read.
///
/// [tiles] describes each tile in draw order. [ops] vector primitives are drawn
/// over the top so the page still carries CAD linework, split across [streams]
/// `/Contents` streams like a real multi-pass export. Output is deterministic:
/// seeded PRNG, no timestamps.
Uint8List buildSyntheticCadImageStrip({
  required List<PdfTileSpec> tiles,
  int ops = 500000,
  int streams = 8,
  int seed = 20260720,
  double pageW = 8503.939,
  double pageH = 841.89,
}) {
  assert(streams > 0);
  const zlib = ZLibEncoder();
  final builder = CosDocumentBuilder();
  final random = _Lcg(seed);

  // Registration order: 1 = catalog, 2 = pages tree, then one object per tile
  // (plus one palette object per indexed tile), then the content streams, then
  // the page.
  const catalogNum = 1;
  const treeNum = 2;
  final treeRef = const CosReference(treeNum, 0);

  var next = 3;
  final tileRefs = <CosReference>[];
  final tileObjects = <CosObject>[];
  final paletteObjects = <(int, CosObject)>[];
  for (final tile in tiles) {
    final paletteNum = tile.codec == PdfTileCodec.indexed ? next++ : null;
    final tileNum = next++;
    tileRefs.add(CosReference(tileNum, 0));
    if (paletteNum != null) {
      paletteObjects.add((paletteNum, _palette(zlib)));
    }
    tileObjects.add(_tileStream(tile, paletteNum, zlib, random));
  }
  final contentStart = next;
  final contentRefs = [
    for (var i = 0; i < streams; i++) CosReference(contentStart + i, 0)
  ];
  final pageRef = CosReference(contentStart + streams, 0);

  builder.add(CosDictionary({
    'Type': const CosName('Catalog'),
    'Pages': treeRef,
  }));
  builder.add(CosDictionary({
    'Type': const CosName('Pages'),
    'Kids': CosArray([pageRef]),
    'Count': const CosInteger(1),
  }));

  // Interleave palettes with their tiles so object numbers match the order
  // reserved above.
  var paletteIndex = 0;
  for (var i = 0; i < tiles.length; i++) {
    if (tiles[i].codec == PdfTileCodec.indexed) {
      builder.add(paletteObjects[paletteIndex++].$2);
    }
    builder.add(tileObjects[i]);
  }

  // Lay the tiles out left to right across the strip, so a horizontal pan -
  // how this drawing is actually read - crosses tile after tile.
  final perStream = (tiles.length / streams).ceil();
  final tileW = pageW / tiles.length * 1.6; // overlap, like a stitched scan
  final buffers = <StringBuffer>[];
  for (var s = 0; s < streams; s++) {
    final buf = StringBuffer();
    final from = s * perStream;
    final to = (from + perStream).clamp(0, tiles.length);
    for (var i = from; i < to; i++) {
      final x = pageW * i / tiles.length;
      buf.writeln('q ${_f(tileW)} 0 0 ${_f(pageH)} ${_f(x)} 0 cm '
          '/Im$i Do Q');
    }
    // vector linework over the tiles, this stream's share
    final opsHere = ops ~/ streams;
    for (var i = 0; i < opsHere; i++) {
      final x = random.range(0, pageW);
      final y = random.range(0, pageH);
      buf.writeln('${_f(random.range(0, 1))} G ${_f(random.range(0.2, 1.4))} w '
          '${_f(x)} ${_f(y)} m ${_f(x + random.range(-40, 40))} '
          '${_f(y + random.range(-30, 30))} l S');
    }
    buffers.add(buf);
  }

  for (final buf in buffers) {
    final raw = Uint8List.fromList(buf.toString().codeUnits);
    final deflated = Uint8List.fromList(zlib.encode(raw));
    builder.add(CosStream(
      CosDictionary({
        'Filter': const CosName('FlateDecode'),
        'Length': CosInteger(deflated.length),
      }),
      deflated,
    ));
  }

  builder.add(CosDictionary({
    'Type': const CosName('Page'),
    'Parent': treeRef,
    'MediaBox': CosArray([
      const CosInteger(0),
      const CosInteger(0),
      CosReal(pageW),
      CosReal(pageH),
    ]),
    'Resources': CosDictionary({
      'XObject': CosDictionary({
        for (var i = 0; i < tileRefs.length; i++) 'Im$i': tileRefs[i],
      }),
    }),
    'Contents': CosArray(contentRefs),
  }));

  return builder.build(root: const CosReference(catalogNum, 0));
}

String _f(double v) => v.toStringAsFixed(2);

/// A 256-entry ramp palette for the indexed tiles.
CosStream _palette(ZLibEncoder zlib) {
  final table = Uint8List(256 * 3);
  for (var i = 0; i < 256; i++) {
    table[i * 3] = i;
    table[i * 3 + 1] = 255 - i;
    table[i * 3 + 2] = (i * 7) & 0xFF;
  }
  final deflated = Uint8List.fromList(zlib.encode(table));
  return CosStream(
    CosDictionary({
      'Filter': const CosName('FlateDecode'),
      'Length': CosInteger(deflated.length),
    }),
    deflated,
  );
}

CosStream _tileStream(
    PdfTileSpec tile, int? paletteNum, ZLibEncoder zlib, _Lcg random) {
  final w = tile.width;
  final h = tile.height;

  switch (tile.codec) {
    case PdfTileCodec.jpeg:
    case PdfTileCodec.jpeg2000:
      final payload = tile.payload;
      if (payload == null) {
        throw ArgumentError('${tile.codec} tiles need a pre-encoded payload');
      }
      return CosStream(
        CosDictionary({
          'Type': const CosName('XObject'),
          'Subtype': const CosName('Image'),
          'Width': CosInteger(w),
          'Height': CosInteger(h),
          'ColorSpace': const CosName('DeviceRGB'),
          'BitsPerComponent': const CosInteger(8),
          'Filter': CosName(
              tile.codec == PdfTileCodec.jpeg ? 'DCTDecode' : 'JPXDecode'),
          'Length': CosInteger(payload.length),
        }),
        payload,
      );

    case PdfTileCodec.imageMask:
      // 1 bit per pixel, rows padded to byte boundaries - the stencil layer.
      final rowBytes = (w + 7) >> 3;
      final bits = Uint8List(rowBytes * h);
      for (var y = 0; y < h; y++) {
        // sparse diagonal hatching: cheap to generate, compresses like linework
        for (var x = (y * 3) % 17; x < w; x += 17) {
          bits[y * rowBytes + (x >> 3)] |= 0x80 >> (x & 7);
        }
      }
      final deflated = Uint8List.fromList(zlib.encode(bits));
      return CosStream(
        CosDictionary({
          'Type': const CosName('XObject'),
          'Subtype': const CosName('Image'),
          'Width': CosInteger(w),
          'Height': CosInteger(h),
          'ImageMask': const CosBoolean(true),
          'BitsPerComponent': const CosInteger(1),
          'Decode': CosArray([const CosInteger(0), const CosInteger(1)]),
          'Filter': const CosName('FlateDecode'),
          'Length': CosInteger(deflated.length),
        }),
        deflated,
      );

    case PdfTileCodec.indexed:
      final pixels = Uint8List(w * h);
      for (var i = 0; i < pixels.length; i++) {
        pixels[i] = (i * 31 + random.intBelow(3)) & 0xFF;
      }
      final deflated = Uint8List.fromList(zlib.encode(pixels));
      return CosStream(
        CosDictionary({
          'Type': const CosName('XObject'),
          'Subtype': const CosName('Image'),
          'Width': CosInteger(w),
          'Height': CosInteger(h),
          'ColorSpace': CosArray([
            const CosName('Indexed'),
            const CosName('DeviceRGB'),
            const CosInteger(255),
            CosReference(paletteNum!, 0),
          ]),
          'BitsPerComponent': const CosInteger(8),
          'Filter': const CosName('FlateDecode'),
          'Length': CosInteger(deflated.length),
        }),
        deflated,
      );

    case PdfTileCodec.flateRgb:
      // A scanned drawing tile: near-white paper with sparse dark linework.
      //
      // This is load-bearing for the fixture's realism. An earlier version
      // filled the tile with an `x ^ y` gradient, which is high-entropy noise:
      // it deflated to ~6 MB per tile against the real file's ~42 KB average,
      // making the fixture ~12x too large and turning a Flate-decode benchmark
      // into a memory-bandwidth benchmark. Long runs of identical pixels are
      // what a real scan compresses down to.
      final rgb = Uint8List(w * h * 3)..fillRange(0, w * h * 3, 0xF8);
      void mark(int x, int y) {
        if (x < 0 || x >= w || y < 0 || y >= h) return;
        final i = (y * w + x) * 3;
        rgb[i] = 0x20;
        rgb[i + 1] = 0x24;
        rgb[i + 2] = 0x30;
      }

      // horizontal + vertical rules, the dominant feature of a CAD scan
      for (var y = 0; y < h; y += 97) {
        for (var x = 0; x < w; x++) {
          mark(x, y);
          mark(x, y + 1);
        }
      }
      for (var x = 0; x < w; x += 131) {
        for (var y = 0; y < h; y++) {
          mark(x, y);
        }
      }
      // a scattering of small filled blocks standing in for symbols and text
      for (var i = 0; i < 240; i++) {
        final bx = random.intBelow(w - 24);
        final by = random.intBelow(h - 12);
        for (var y = 0; y < 9; y++) {
          for (var x = 0; x < 18; x++) {
            if (((x * 7 + y * 3) & 3) != 0) mark(bx + x, by + y);
          }
        }
      }
      final deflated = Uint8List.fromList(zlib.encode(rgb));
      return CosStream(
        CosDictionary({
          'Type': const CosName('XObject'),
          'Subtype': const CosName('Image'),
          'Width': CosInteger(w),
          'Height': CosInteger(h),
          'ColorSpace': const CosName('DeviceRGB'),
          'BitsPerComponent': const CosInteger(8),
          'Filter': const CosName('FlateDecode'),
          'Length': CosInteger(deflated.length),
        }),
        deflated,
      );
  }
}

/// Deterministic 64-bit LCG (VM-only; see `cad_strip.dart`).
class _Lcg {
  _Lcg(this._state);
  int _state;

  int _next() =>
      _state = (_state * 6364136223846793005 + 1442695040888963407) &
          0x7FFFFFFFFFFFFFFF;

  double unit() => (_next() >> 11) * (1.0 / (1 << 52));

  double range(double lo, double hi) => lo + unit() * (hi - lo);

  int intBelow(int n) => (unit() * n).floor();
}
