// #451: what does the SECOND record of a page cost?
//
// A render worker records the same page several times in one scroll - the
// vector-first pass, the full pass, a prerender warm, a thumbnail tile. The
// device trace showed one page paying ~900ms of pure-Dart CMYK decode three
// times, and ~6.9s of such decodes across seven records.
//
// This serializes each page twice with a shared PdfImageDecodeCache and once
// without, and reports both the time and whether the bytes are identical -
// reuse that changed a single byte would be a rendering change, not a
// speed-up.
//
//   fvm dart tool/bench_record_reuse.dart <file.pdf> [--pages=2,3,29]
import 'dart:io';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

const _ratio = 2.0;

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
  stdout.writeln('   firstMs  secondMs  reuseMs   saved  identical  page');

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

    Uint8ListOrNull run(PdfImageDecodeCache? cache, void Function(double) sink) {
      final sw = Stopwatch()..start();
      final out = serializeCommands(commands,
          cos: cos,
          decodeImages: true,
          maxImagePixelRatio: _ratio,
          imageCache: cache);
      sw.stop();
      sink(sw.elapsedMicroseconds / 1000);
      return out;
    }

    // Uncached: the cost every record pays today.
    var firstMs = 0.0, secondMs = 0.0, reuseMs = 0.0;
    final a = run(null, (ms) => firstMs = ms);
    final b = run(null, (ms) => secondMs = ms);
    // Cached: the first record fills it, the second reuses.
    final cache = PdfImageDecodeCache();
    run(cache, (_) {});
    final c = run(cache, (ms) => reuseMs = ms);
    if (a == null || b == null || c == null) continue;

    final identical = _sameBytes(b, c);
    totalFirst += firstMs;
    totalSecond += secondMs;
    totalReuse += reuseMs;
    stdout.writeln('  ${_ms(firstMs)} ${_ms(secondMs)} ${_ms(reuseMs)}  '
        '${'${(100 - reuseMs / secondMs * 100).round()}%'.padLeft(6)}  '
        '${(identical ? 'yes' : 'NO').padLeft(9)}  p$i '
        '(${recorder.imageRequests.length} images, '
        'cache ${cache.hits}h/${cache.misses}m)');
  }

  stdout.writeln('\n  re-record uncached ${_round(totalSecond)}ms '
      '-> cached ${_round(totalReuse)}ms '
      '(${(100 - totalReuse / totalSecond * 100).round()}% less), '
      'first record ${_round(totalFirst)}ms either way.');
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
