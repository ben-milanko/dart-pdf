// Writes the image-heavy wide-CAD perf fixture: one ~8504 x 842 pt sheet with
// a grid of large raster tiles under vector linework. Three profiles:
//
//   faithful  the #419 profile of the real 62 MB cathodic-protection drawing -
//             FlateDecode only, ~2:1 ImageMask stencils to DeviceRGB tiles
//             plus a few Indexed ones. That profile counted the sheet's /Mask
//             stencil streams as drawn ImageMasks, and its hatch paints 94% of
//             each stencil, so this is NOT the shape the sheet draws; it stays
//             byte-stable because cad-images-1p-sweep measures it.
//
//   faithful2 the sheet as it is drawn: 462 ImageMask stencils (/Decode [1 0],
//             sparse linework), 445 DeviceRGB and 17 Indexed tiles each under
//             a same-size 1-bit /Mask stencil, and one tiny unmasked Indexed
//             image; ~983 pt tiles stacked ~100 deep. A few percent of the
//             stencils (and every Indexed tile's mask) are fully transparent,
//             as on the sheet. [tiles] counts the large tiles (default 924;
//             231 is the quarter-size nightly variant).
//
//   mixed     the same sheet re-encoded with DCTDecode and JPXDecode tiles, to
//             exercise the JPEG and JPEG 2000 decoders under a realistic
//             page. Needs `cjpeg` (mozjpeg/libjpeg-turbo) and `opj_compress`
//             (OpenJPEG) on PATH; both are generated once and the resulting
//             PDF is pre-seeded into tool/perf/cache, so CI never needs them.
//
//   fvm dart run packages/pdf_test_fixtures/tool/gen_cad_image_pdf.dart \
//       <out.pdf> [faithful|faithful2|mixed] [tiles] [tileW] [tileH] [ops]
//       [seed]
//
// Defaults: 1386 tiles of 2048x1754 and 500k vector ops - the profiled counts
// (the real sheet is heavy in BOTH raster and vector: ~57.7 MB of image
// streams *and* ~24.75 MB of decoded content across 8 /Contents streams).
// The real file is ~62 MB and would decode to ~20 GB of RGBA if every tile
// were resident at once; that ratio is the point of the fixture.
//
// JPX note: the codestream must stay inside what `JpxDecoder` supports - no
// component subsampling and no code-block style options - so opj_compress is
// invoked without -s and without -M.
import 'dart:io';
import 'dart:typed_data';

import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main(List<String> args) {
  final outPath = args.isNotEmpty ? args[0] : 'perf_cad_images.pdf';
  final profile = args.length > 1 ? args[1] : 'faithful';
  final tileCount = args.length > 2
      ? int.parse(args[2])
      : (profile == 'faithful2' ? 924 : 1386);
  final tileW = args.length > 3 ? int.parse(args[3]) : 2048;
  final tileH = args.length > 4 ? int.parse(args[4]) : 1754;
  final ops = args.length > 5 ? int.parse(args[5]) : 500000;
  final seed = args.length > 6 ? int.parse(args[6]) : 20260720;

  if (profile != 'faithful' && profile != 'faithful2' && profile != 'mixed') {
    stderr.writeln('profile must be "faithful", "faithful2" or "mixed"');
    exitCode = 2;
    return;
  }

  if (profile == 'faithful2') {
    _writeFaithful2(outPath, tileCount, tileW, tileH, ops, seed);
    return;
  }

  final tiles = <PdfTileSpec>[];
  Uint8List? jpegPayload;
  Uint8List? jpxPayload;

  if (profile == 'mixed') {
    // Encode one tile with each external codec and reuse the payload. Reuse is
    // deliberate: the decoders do the same work per tile either way, and one
    // encode keeps generation quick and byte-reproducible.
    jpegPayload = _encodeJpeg(tileW, tileH);
    jpxPayload = _encodeJpx(tileW, tileH);
  }

  for (var i = 0; i < tileCount; i++) {
    // Profiled mix: 923 ImageMask : 445 DeviceRGB : 18 Indexed out of 1386,
    // i.e. roughly 2 stencils per RGB tile with a sprinkle of Indexed.
    final slot = i % 77;
    final PdfTileCodec codec;
    if (slot == 76) {
      codec = PdfTileCodec.indexed;
    } else if (slot % 3 == 2) {
      codec = profile == 'mixed'
          ? (i % 6 == 2 ? PdfTileCodec.jpeg2000 : PdfTileCodec.jpeg)
          : PdfTileCodec.flateRgb;
    } else {
      codec = PdfTileCodec.imageMask;
    }
    tiles.add(PdfTileSpec(
      codec: codec,
      width: tileW,
      height: tileH,
      payload: switch (codec) {
        PdfTileCodec.jpeg => jpegPayload,
        PdfTileCodec.jpeg2000 => jpxPayload,
        _ => null,
      },
    ));
  }

  final bytes = buildSyntheticCadImageStrip(tiles: tiles, ops: ops, seed: seed);
  File(outPath)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(bytes);

  final counts = <PdfTileCodec, int>{};
  for (final t in tiles) {
    counts[t.codec] = (counts[t.codec] ?? 0) + 1;
  }
  final megapixels = tileCount * tileW * tileH / 1e6;
  stderr.writeln('wrote $outPath: 1 page 8504x842pt, $profile profile, '
      '$tileCount tiles of ${tileW}x$tileH, $ops vector ops, '
      '${(bytes.length / (1 << 20)).toStringAsFixed(1)} MB, seed $seed');
  stderr.writeln('  tiles: ${counts.entries.map((e) => '${e.key.name}=${e.value}').join(' ')}');
  stderr.writeln('  ${megapixels.toStringAsFixed(0)} Mpx total -> '
      '~${(megapixels * 4 / 1000).toStringAsFixed(1)} GB if all decoded to RGBA');
}

/// The sheet as drawn (see the file comment): per 54 draws, 27 ImageMask
/// stencils alternating with 26 masked DeviceRGB tiles, then one masked
/// Indexed tile - 462:445:17 over 924 - plus the 3x1 unmasked Indexed image
/// the sheet also draws. Transparent planes: every 16th ImageMask (29 of 462;
/// the sheet has 28), every 40th RGB mask (11 of 445; the sheet has 11), and
/// every Indexed mask (all 17 on the sheet).
void _writeFaithful2(
    String outPath, int tileCount, int tileW, int tileH, int ops, int seed) {
  final tiles = <PdfTileSpec>[];
  var stencils = 0, rgb = 0;
  for (var i = 0; i < tileCount; i++) {
    final slot = i % 54;
    if (slot == 53) {
      tiles.add(PdfTileSpec(
          codec: PdfTileCodec.indexed,
          width: tileW,
          height: tileH,
          masked: true,
          maskBlank: true));
    } else if (slot.isOdd) {
      tiles.add(PdfTileSpec(
          codec: PdfTileCodec.flateRgb,
          width: tileW,
          height: tileH,
          masked: true,
          maskBlank: rgb++ % 40 == 19));
    } else {
      tiles.add(PdfTileSpec(
          codec: PdfTileCodec.imageMask,
          width: tileW,
          height: tileH,
          masked: true,
          maskBlank: stencils++ % 16 == 7));
    }
  }
  tiles
      .add(const PdfTileSpec(codec: PdfTileCodec.indexed, width: 3, height: 1));

  final bytes = buildSyntheticCadImageStrip(
      tiles: tiles, ops: ops, seed: seed, tileWidthPt: 983);
  File(outPath)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(bytes);

  final counts = <String, int>{};
  for (final t in tiles) {
    final key =
        '${t.codec.name}${t.masked && t.codec != PdfTileCodec.imageMask ? '+mask' : ''}'
        '${t.maskBlank ? '(blank)' : ''}';
    counts[key] = (counts[key] ?? 0) + 1;
  }
  stderr.writeln('wrote $outPath: 1 page 8504x842pt, faithful2 profile, '
      '${tiles.length} draws (${tileW}x$tileH tiles, 983 pt wide), $ops vector '
      'ops, ${(bytes.length / (1 << 20)).toStringAsFixed(1)} MB, seed $seed');
  stderr.writeln(
      '  draws: ${counts.entries.map((e) => '${e.key}=${e.value}').join(' ')}');
}

/// A deterministic RGB source image, written as binary PPM for the encoders.
Uint8List _ppm(int w, int h) {
  final header = Uint8List.fromList('P6\n$w $h\n255\n'.codeUnits);
  final body = Uint8List(w * h * 3);
  for (var y = 0; y < h; y++) {
    final row = y * w * 3;
    for (var x = 0; x < w; x++) {
      final i = row + x * 3;
      body[i] = x * 255 ~/ w;
      body[i + 1] = y * 255 ~/ h;
      body[i + 2] = (x ^ y) & 0xFF;
    }
  }
  return Uint8List.fromList([...header, ...body]);
}

Uint8List _runCodec(
    String exe, List<String> Function(String src, String dst) argv,
    String srcExt, String dstExt, int w, int h) {
  final dir = Directory.systemTemp.createTempSync('cadgen');
  try {
    final src = File('${dir.path}/src.$srcExt')..writeAsBytesSync(_ppm(w, h));
    final dst = '${dir.path}/out.$dstExt';
    final result = Process.runSync(exe, argv(src.path, dst));
    if (result.exitCode != 0 || !File(dst).existsSync()) {
      throw StateError('$exe failed (${result.exitCode}): ${result.stderr}');
    }
    return File(dst).readAsBytesSync();
  } on ProcessException catch (e) {
    throw StateError('$exe not found on PATH - needed for the "mixed" '
        'profile. Install it (brew install mozjpeg openjpeg) or use the '
        '"faithful" profile, which needs no external codecs. ($e)');
  } finally {
    dir.deleteSync(recursive: true);
  }
}

Uint8List _encodeJpeg(int w, int h) => _runCodec(
      'cjpeg',
      (src, dst) => ['-quality', '80', '-outfile', dst, src],
      'ppm',
      'jpg',
      w,
      h,
    );

/// Raw JPEG 2000 codestream (`-o out.j2k`), inside what `JpxDecoder` supports:
/// no `-s` (component subsampling is rejected) and no `-M` (code-block style
/// options are rejected).
Uint8List _encodeJpx(int w, int h) => _runCodec(
      'opj_compress',
      (src, dst) => ['-i', src, '-o', dst, '-r', '20'],
      'ppm',
      'j2k',
      w,
      h,
    );
