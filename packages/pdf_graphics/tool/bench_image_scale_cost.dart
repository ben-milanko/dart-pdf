// #451: does asking for a SMALLER decode actually cost less?
//
// The device trace showed a 128px-wide thumbnail tile paying serialize=1148ms
// on one page, all of it inside the pure-Dart decode of images the browser
// codec declined. #603 already budgets the thumbnail record to its tile, so the
// target size the codec asks for is small - the open question is whether the
// decoder honours that cheaply or fully decodes and then downsamples.
//
// For every image each page draws, this decodes it three ways and reports the
// wall time of each:
//
//   full    - native resolution (no cap)
//   page    - the capped display size at a full-page ratio (2.0)
//   tile    - the capped display size for a 128px thumbnail tile
//
// If `tile` tracks `full`, the cap is saving bytes but not time, and a scaled
// decode path is needed for that shape (the JPX path `_decodeJpxScaled` already
// does exactly this for JPEG 2000 via reduced resolution levels).
//
//   fvm dart tool/bench_image_scale_cost.dart <file.pdf> [--pages=2,3,29]
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

/// Decode time is noisy; report the best of this many runs.
const _runs = 3;

/// The full-page record ratio, and the tile a 128px thumbnail rasterizes into.
const _pageRatio = 2.0;
const _tilePx = 128.0;

void main(List<String> args) {
  final paths = args.where((a) => !a.startsWith('--')).toList();
  if (paths.isEmpty) {
    stderr.writeln('usage: bench_image_scale_cost.dart <file.pdf> '
        '[--pages=2,3,29]');
    exit(1);
  }
  final pagesArg = args.firstWhere((a) => a.startsWith('--pages='),
      orElse: () => '');
  final only = pagesArg.isEmpty
      ? null
      : pagesArg
          .replaceFirst('--pages=', '')
          .split(',')
          .map(int.parse)
          .toSet();

  final bytes = File(paths.first).readAsBytesSync();
  final cos = CosDocument.open(bytes);
  final doc = PdfDocument.open(bytes);

  stdout.writeln('\n${paths.first}  (best of $_runs)\n');
  stdout.writeln('  fullMs   pageMs   tileMs  tile/full  '
      'native        page        tile          shape');

  for (var i = 0; i < doc.pageCount; i++) {
    if (only != null && !only.contains(i)) continue;
    final page = doc.page(i);
    final recorder = RecordingPdfDevice();
    try {
      PdfInterpreter(cos: cos, device: recorder)
        ..drawPage(page)
        ..drawAnnotations(page);
    } catch (_) {
      continue;
    }
    final box = page.cropBox;
    // What a 128px-wide tile of this page rasterizes at, in ratio terms.
    final tileRatio = box.width > 0 ? _tilePx / box.width : _pageRatio;

    for (final request in recorder.imageRequests) {
      final dict = request.stream.dictionary;
      final w = _intOf(cos.resolve(dict['Width']));
      final h = _intOf(cos.resolve(dict['Height']));
      if (w < 1 || h < 1) continue;

      final t = request.transform;
      final widthPts = math.sqrt(t.a * t.a + t.b * t.b);
      final heightPts = math.sqrt(t.c * t.c + t.d * t.d);
      final pageSize =
          cappedImagePixelSize(w, h, widthPts, heightPts, _pageRatio);
      final tileSize =
          cappedImagePixelSize(w, h, widthPts, heightPts, tileRatio);

      final full = _time(() => decodePdfImage(cos, request.stream));
      final atPage = _time(() => decodePdfImage(cos, request.stream,
          targetWidth: pageSize.$1, targetHeight: pageSize.$2));
      final atTile = _time(() => decodePdfImage(cos, request.stream,
          targetWidth: tileSize.$1, targetHeight: tileSize.$2));
      if (full == null || atPage == null || atTile == null) continue;

      // Only the expensive ones are interesting; sub-millisecond images are
      // noise and there are hundreds of them.
      if (full < 5) continue;

      // Split the cost: how much is the JPEG entropy decode + IDCT inside
      // package:image, and how much is our own CMYK/ICC -> RGBA pass on top?
      // A scaled (reduced-IDCT) decode can only ever attack the former.
      var jpegMs = -1.0;
      final filters0 = pdfImageFilters(cos, dict);
      if (filters0.contains('DCTDecode')) {
        final raw = cos.decodeStreamData(request.stream,
            stopBeforeFilter: 'DCTDecode');
        jpegMs = _time(() {
          final d = img.JpegData()..read(raw);
          return d.components.isEmpty ? null : d;
        }) ??
            -1;
      }

      final filters = pdfImageFilters(cos, dict).join('+');
      final space = pdfImageColorFamily(cos, dict);
      final mask = dict.containsKey('SMask')
          ? 'SMask'
          : dict.containsKey('Mask')
              ? 'Mask'
              : '-';
      stdout.writeln('  ${_ms(full)} ${_ms(atPage)} ${_ms(atTile)}  '
          '${(atTile / full).toStringAsFixed(2).padLeft(9)}  '
          '${'${w}x$h'.padRight(12)}'
          '${_size(pageSize).padRight(12)}'
          '${_size(tileSize).padRight(12)}  '
          'p$i $space $mask $filters'
          '${jpegMs < 0 ? '' : '  [jpeg=${jpegMs.toStringAsFixed(1)}ms '
              '${(jpegMs / full * 100).round()}%]'}');
    }
  }
}

String _size((int, int) s) => '${s.$1}x${s.$2}';

String _ms(double v) => v.toStringAsFixed(1).padLeft(8);

/// Best-of-[_runs] wall time in ms, or null when the decode declines.
double? _time(Object? Function() decode) {
  var best = double.infinity;
  for (var i = 0; i < _runs; i++) {
    final sw = Stopwatch()..start();
    final result = decode();
    sw.stop();
    if (result == null) return null;
    best = math.min(best, sw.elapsedMicroseconds / 1000);
  }
  return best;
}

int _intOf(CosObject? o, {int fallback = 0}) =>
    o is CosInteger ? o.value : o is CosReal ? o.value.round() : fallback;
