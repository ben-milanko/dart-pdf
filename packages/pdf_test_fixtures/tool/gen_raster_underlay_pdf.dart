// Writes the raster-underlay CAD sheet perf/corpus fixture: one large page
// carrying a handful of enormous DeviceRGB image underlays, each with its own
// full-size grayscale soft mask, plus a stack of optional-content layers. The
// drawing lives in `buildSyntheticRasterUnderlaySheet` (package:
// pdf_test_fixtures), shared with the tests so the fixture and the test doc are
// the same bytes.
//
// Two profiles, mirroring gen_cad_image_pdf.dart:
//
//   faithful  FlateDecode DeviceRGB bases under FlateDecode gray soft masks.
//             Hermetic - no external codecs - so it is the committed corpus
//             variant. Reproduces the giant-single-image + soft-mask + OCG
//             *structure* (and the >8192-px GPU-max-texture case).
//
//   mixed     the same sheet with DCTDecode (JPEG) bases under the same Flate
//             soft masks - the shape profiled from the real ~8 MB survey
//             drawing. A non-CMYK JPEG base needs the platform codec, so this
//             is the variant that reproduces the un-capped full-resolution
//             decode + per-pixel alpha-multiply pathology. Needs `cjpeg`
//             (mozjpeg/libjpeg-turbo) on PATH; generated once and pre-seeded
//             into tool/perf/cache, so CI never needs it.
//
//   fvm dart run packages/pdf_test_fixtures/tool/gen_raster_underlay_pdf.dart \
//       <out.pdf> [faithful|mixed] [underlays] [imageW] [imageH] [layers] [ops] [seed]
//
// Defaults: 2 underlays of 9460x2918 (the profiled dimensions), 71 layers,
// 6000 vector ops. At native resolution the two bases + two masks decode to
// ~220 MB of RGBA - the number that overruns the web image-cache budget.
import 'dart:io';
import 'dart:typed_data';

import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main(List<String> args) {
  final outPath = args.isNotEmpty ? args[0] : 'perf_raster_underlay.pdf';
  final profile = args.length > 1 ? args[1] : 'faithful';
  final underlayCount = args.length > 2 ? int.parse(args[2]) : 2;
  final imageW = args.length > 3 ? int.parse(args[3]) : 9460;
  final imageH = args.length > 4 ? int.parse(args[4]) : 2918;
  final layers = args.length > 5 ? int.parse(args[5]) : 71;
  final ops = args.length > 6 ? int.parse(args[6]) : 6000;
  final seed = args.length > 7 ? int.parse(args[7]) : 20260722;

  if (profile != 'faithful' && profile != 'mixed') {
    stderr.writeln('profile must be "faithful" or "mixed"');
    exitCode = 2;
    return;
  }

  // One JPEG encode reused for every base: the decoder does the same per-image
  // work either way, and one encode keeps generation quick and byte-reproducible.
  final jpegPayload = profile == 'mixed' ? _encodeJpeg(imageW, imageH) : null;

  final underlays = [
    for (var i = 0; i < underlayCount; i++)
      PdfUnderlaySpec(width: imageW, height: imageH, payload: jpegPayload),
  ];

  final bytes = buildSyntheticRasterUnderlaySheet(
    underlays: underlays,
    layers: layers,
    ops: ops,
    seed: seed,
  );
  File(outPath)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(bytes);

  final decodedMb = underlayCount * imageW * imageH * (3 + 1) / 1e6;
  stderr.writeln('wrote $outPath: 1 page, $profile profile, '
      '$underlayCount underlays of ${imageW}x$imageH + soft masks, '
      '$layers layers, $ops vector ops, '
      '${(bytes.length / (1 << 20)).toStringAsFixed(1)} MB, seed $seed');
  stderr.writeln('  ~${decodedMb.toStringAsFixed(0)} MB RGBA resident if every '
      'base + mask is decoded at native resolution');
}

/// A deterministic RGB source image, written as binary PPM for `cjpeg`.
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

Uint8List _encodeJpeg(int w, int h) {
  final dir = Directory.systemTemp.createTempSync('underlaygen');
  try {
    final src = File('${dir.path}/src.ppm')..writeAsBytesSync(_ppm(w, h));
    final dst = '${dir.path}/out.jpg';
    final result = Process.runSync(
        'cjpeg', ['-quality', '80', '-outfile', dst, src.path]);
    if (result.exitCode != 0 || !File(dst).existsSync()) {
      throw StateError('cjpeg failed (${result.exitCode}): ${result.stderr}');
    }
    return File(dst).readAsBytesSync();
  } on ProcessException catch (e) {
    throw StateError('cjpeg not found on PATH - needed for the "mixed" '
        'profile. Install it (brew install mozjpeg) or use the "faithful" '
        'profile, which needs no external codecs. ($e)');
  } finally {
    dir.deleteSync(recursive: true);
  }
}
