// #451, one level down from bench_image_serialize: per *image*, what does the
// record path pay to decode it, and what shape is it?
//
// The record path asks `decodePdfImage` for the capped display size
// (`cappedImagePixelSize` at ratio 2.0). This reproduces that call for every
// image every corpus page draws and prints the cost next to the image's
// shape - colour space, filters, bits, mask, source vs target pixels - so the
// expensive shapes are identifiable rather than guessed at.
//
//   fvm dart tool/bench_image_decode.dart [dir-or-file ...]
import 'dart:io';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'dart:math' as math;

const _ratio = 2.0;

/// Decode time is noisy; report the best of this many runs per image.
const _runs = 5;

void main(List<String> args) {
  final paths = args.where((a) => !a.startsWith('--')).toList();
  final files = _collect(paths.isEmpty
      ? const ['../../test_corpora/ghent', '../../test_corpora/pdfjs']
      : paths);

  final rows = <_Row>[];
  for (final file in files) {
    final PdfDocument doc;
    final int pageCount;
    try {
      doc = PdfDocument.open(file.readAsBytesSync());
      pageCount = doc.pageCount;
    } catch (_) {
      continue;
    }
    for (var i = 0; i < pageCount; i++) {
      try {
        rows.addAll(_measurePage(file.path, doc, i));
      } catch (_) {
        // Uninterpretable pages are not this benchmark's concern.
      }
    }
  }

  rows.sort((a, b) => b.ms.compareTo(a.ms));
  stdout.writeln('Per-image decode at the record path\'s capped size '
      '(ratio $_ratio, ${rows.length} images)\n');
  stdout.writeln('      ms   src px    dst px  scale  bits  space        '
      'mask  filters               page');
  for (final r in rows.take(30)) {
    stdout.writeln(r);
  }
  final total = rows.fold<double>(0, (s, r) => s + r.ms);
  stdout.writeln('\ntotal ${total.toStringAsFixed(0)}ms across '
      '${rows.length} images');

  // Group the cost by shape, which is what a fix has to target.
  final byShape = <String, (double, int)>{};
  for (final r in rows) {
    final key = '${r.space}/${r.bits}b'
        '${r.mask.isEmpty ? '' : '+${r.mask}'}';
    final prev = byShape[key] ?? (0.0, 0);
    byShape[key] = (prev.$1 + r.ms, prev.$2 + 1);
  }
  final shapes = byShape.entries.toList()
    ..sort((a, b) => b.value.$1.compareTo(a.value.$1));
  stdout.writeln('\nCost by image shape:');
  for (final e in shapes.take(15)) {
    stdout.writeln('  ${e.value.$1.toStringAsFixed(1).padLeft(8)}ms  '
        '${e.value.$2.toString().padLeft(4)} images  ${e.key}');
  }

  // How much of the cost is on images that are downscaled at all? That is the
  // ceiling on any "downsample before converting" fix.
  var downscaled = 0.0, native = 0.0;
  for (final r in rows) {
    if (r.dstPixels < r.srcPixels) {
      downscaled += r.ms;
    } else {
      native += r.ms;
    }
  }
  stdout.writeln('\ndownscaled images: ${downscaled.toStringAsFixed(0)}ms   '
      'drawn at/above native: ${native.toStringAsFixed(0)}ms');
}

List<_Row> _measurePage(String path, PdfDocument doc, int index) {
  final page = doc.page(index);
  final cos = doc.cos;
  final recorder = RecordingPdfDevice();
  PdfInterpreter(cos: cos, device: recorder)
    ..drawPage(page)
    ..drawAnnotations(page);

  final rows = <_Row>[];
  final seen = <CosStream>{};
  for (final request in recorder.imageRequests) {
    if (!seen.add(request.stream)) continue;
    final dict = request.stream.dictionary;
    final w = _intOf(cos.resolve(dict['Width']));
    final h = _intOf(cos.resolve(dict['Height']));
    if (w <= 0 || h <= 0) continue;

    final t = request.transform;
    final widthPts = math.sqrt(t.a * t.a + t.b * t.b);
    final heightPts = math.sqrt(t.c * t.c + t.d * t.d);
    final capped = cappedImagePixelSize(w, h, widthPts, heightPts, _ratio);

    // Warm the stream/ICC caches, then take the best of a few runs: decode
    // time is noisy enough between runs that a single sample cannot tell a
    // real change from scheduler jitter.
    decodePdfImage(cos, request.stream,
        targetWidth: capped.$1, targetHeight: capped.$2);
    var bestUs = -1;
    for (var run = 0; run < _runs; run++) {
      final sw = Stopwatch()..start();
      final decoded = decodePdfImage(cos, request.stream,
          targetWidth: capped.$1, targetHeight: capped.$2);
      sw.stop();
      if (decoded == null) break;
      if (bestUs < 0 || sw.elapsedMicroseconds < bestUs) {
        bestUs = sw.elapsedMicroseconds;
      }
    }
    if (bestUs < 0) continue;

    rows.add(_Row(
      ms: bestUs / 1000,
      srcWidth: w,
      srcHeight: h,
      dstWidth: capped.$1,
      dstHeight: capped.$2,
      bits: _intOf(cos.resolve(dict['BitsPerComponent']), fallback: 8),
      space: pdfImageColorFamily(cos, dict),
      mask: [
        if (dict.containsKey('SMask')) 'SMask',
        if (cos.resolve(dict['Mask']) is CosArray) 'ColorKey',
        if (cos.resolve(dict['Mask']) is CosStream) 'Stencil',
        if (cos.resolve(dict['ImageMask']) == const CosBoolean(true))
          'ImageMask',
      ].join('+'),
      filters: pdfImageFilters(cos, dict).join(','),
      page: '${path.split('/').last} p$index',
    ));
  }
  return rows;
}

class _Row {
  _Row({
    required this.ms,
    required this.srcWidth,
    required this.srcHeight,
    required this.dstWidth,
    required this.dstHeight,
    required this.bits,
    required this.space,
    required this.mask,
    required this.filters,
    required this.page,
  });

  final double ms;
  final int srcWidth, srcHeight, dstWidth, dstHeight, bits;
  final String space, mask, filters, page;

  int get srcPixels => srcWidth * srcHeight;
  int get dstPixels => dstWidth * dstHeight;

  @override
  String toString() {
    final scale = srcPixels == 0 ? 0.0 : dstPixels / srcPixels;
    return '  ${ms.toStringAsFixed(1).padLeft(6)}  '
        '${'${srcWidth}x$srcHeight'.padLeft(9)} '
        '${'${dstWidth}x$dstHeight'.padLeft(9)}  '
        '${scale.toStringAsFixed(2).padLeft(5)}  '
        '${bits.toString().padLeft(4)}  ${space.padRight(12)} '
        '${mask.padRight(5)} ${filters.padRight(21)} $page';
  }
}

int _intOf(CosObject? o, {int fallback = 0}) =>
    o is CosInteger ? o.value : o is CosReal ? o.value.round() : fallback;

List<File> _collect(List<String> paths) {
  final out = <File>[];
  for (final p in paths) {
    final dir = Directory(p);
    if (dir.existsSync()) {
      out.addAll(dir.listSync(recursive: true).whereType<File>().where((f) =>
          f.path.toLowerCase().endsWith('.pdf') && !f.path.contains('/_')));
      continue;
    }
    final file = File(p);
    if (file.existsSync()) out.add(file);
  }
  out.sort((a, b) => a.path.compareTo(b.path));
  return out;
}
