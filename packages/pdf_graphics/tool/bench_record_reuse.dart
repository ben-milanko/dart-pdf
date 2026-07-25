// #451: what does the SECOND record of a page cost?
//
// A render worker records the same page several times in one scroll - the
// vector-first pass, the full pass, a prerender warm, a thumbnail tile. The
// device trace showed one page paying ~900ms of pure-Dart CMYK decode three
// times, and ~6.9s of such decodes across seven records.
//
// The records use DIFFERENT image pixel ratios, because that is what
// production does: the repeat records of a page are a full-page pass and a
// 128px thumbnail tile. An earlier version of this tool re-recorded at the
// SAME ratio, which made an exact-match cache look like a 93% win and the
// device trace then showed no win at all - the two records never asked for the
// same target size.
//
// It reports the time and whether the bytes are identical to the uncached
// record - reuse that changed a single byte would be a rendering change, not a
// speed-up.
//
//   fvm dart tool/bench_record_reuse.dart <file.pdf> [--pages=2,3,29]
import 'dart:io';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

/// The full-page record ratio, and the ratio a 128px thumbnail tile records
/// at - the two a page actually gets recorded at within one scroll.
const _pageRatio = 2.0;
const _tilePx = 128.0;

void main(List<String> args) {
  final paths = args.where((a) => !a.startsWith('--')).toList();
  if (paths.isEmpty) {
    stderr.writeln('usage: bench_record_reuse.dart <file.pdf> [--pages=1,2]');
    exit(1);
  }
  final pagesArg =
      args.firstWhere((a) => a.startsWith('--pages='), orElse: () => '');
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

  stdout.writeln('\n${paths.first}\n');
  stdout.writeln('    pageMs    tileMs  tileCachedMs   saved  identical  page');

  var totalFirst = 0.0, totalSecond = 0.0, totalReuse = 0.0;
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
    final commands = recorder.commands;
    if (recorder.imageRequests.isEmpty) continue;

    final box = page.cropBox;
    final tileRatio = box.width > 0 ? _tilePx / box.width : _pageRatio;

    Uint8ListOrNull run(
        double ratio, PdfImageDecodeCache? cache, void Function(double) sink) {
      final sw = Stopwatch()..start();
      final out = serializeCommands(commands,
          cos: cos,
          decodeImages: true,
          maxImagePixelRatio: ratio,
          pageRasterPixels: pdfPageRasterPixels(box, ratio),
          imageCache: cache);
      sw.stop();
      sink(sw.elapsedMicroseconds / 1000);
      return out;
    }

    // Uncached, the production sequence: a full-page record, then the
    // thumbnail tile record that follows it.
    var pageMs = 0.0, tileMs = 0.0, cachedMs = 0.0;
    run(_pageRatio, null, (ms) => pageMs = ms);
    final tile = run(tileRatio, null, (ms) => tileMs = ms);
    // Same sequence sharing one cache: the page record fills it, and the tile
    // record - at a DIFFERENT ratio - is the one that has to reuse.
    final cache = PdfImageDecodeCache();
    run(_pageRatio, cache, (_) {});
    final tileCached = run(tileRatio, cache, (ms) => cachedMs = ms);
    if (tile == null || tileCached == null) continue;

    final identical = _sameBytes(tile, tileCached);
    totalFirst += pageMs;
    totalSecond += tileMs;
    totalReuse += cachedMs;
    stdout.writeln('  ${_ms(pageMs)} ${_ms(tileMs)} ${_ms(cachedMs)}  '
        '${'${(100 - cachedMs / tileMs * 100).round()}%'.padLeft(6)}  '
        '${(identical ? 'yes' : 'NO').padLeft(9)}  p$i '
        '(${recorder.imageRequests.length} images, '
        'cache ${cache.hits}h/${cache.misses}m)');
  }

  stdout.writeln('\n  thumbnail record after a full-page record: '
      '${_round(totalSecond)}ms uncached -> ${_round(totalReuse)}ms cached '
      '(${(100 - totalReuse / totalSecond * 100).round()}% less). '
      'The full-page record itself is ${_round(totalFirst)}ms either way.');
}

typedef Uint8ListOrNull = List<int>?;

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

String _ms(double v) => v.toStringAsFixed(1).padLeft(9);

double _round(double v) => (v * 10).round() / 10;
