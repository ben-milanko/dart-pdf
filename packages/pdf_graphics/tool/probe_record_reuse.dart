// #451: does the shared image cache actually get HITS when a page is recorded
// the way a worker records it - a fresh interpret per record, at the ratios
// production uses?
//
// bench_record_reuse.dart measures the byte-identity of a reused record, but it
// interprets ONCE and serializes twice, so it can never catch a problem in how
// records differ from each other - stream identity, or a decode that is never
// stored. This one re-interprets every record and reports the cache's own
// hit/miss/entry counters, which is what distinguishes the two ways reuse can
// fail:
//
//   entries stays 0  -> nothing is being STORED (every decode declined, or each
//                       one is larger than the whole budget)
//   entries grow but
//   hits stay 0      -> stored fine, but the KEY never matches (identity)
//
// `sameStreams` pins the identity half directly: N/N means every image request
// in this record points at the same CosStream object as the first record's.
//
//   fvm dart tool/probe_record_reuse.dart <file.pdf> [21,25,28]
import 'dart:io';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

const _fullRatio = 1.1; // the trace's `full ratio=1.1`
const _tilePx = 128.0; // the thumbnail tile

void main(List<String> args) {
  final bytes = File(args.first).readAsBytesSync();
  final cos = CosDocument.open(bytes);
  final doc = PdfDocument.open(bytes);
  final cache = PdfImageDecodeCache();

  final pages = args.length > 1
      ? args[1].split(',').map(int.parse).toList()
      : [21, 25, 28];

  stdout.writeln('\n${args.first}');
  stdout.writeln('  page  record          ms   hits  misses  entries  '
      'sameStreams');

  for (final i in pages) {
    if (i >= doc.pageCount) continue;
    final page = doc.page(i);
    List<CosStream>? firstStreams;

    for (final label in ['full#1', 'tile#1', 'full#2', 'tile#2']) {
      // A fresh interpret per record, exactly like the worker.
      final recorder = RecordingPdfDevice();
      try {
        PdfInterpreter(cos: cos, device: recorder)
          ..drawPage(page)
          ..drawAnnotations(page);
      } catch (_) {
        break;
      }
      final streams = recorder.imageRequests.map((e) => e.stream).toList();
      String same;
      if (firstStreams == null) {
        firstStreams = streams;
        same = '-';
      } else {
        var n = 0;
        for (var k = 0; k < streams.length && k < firstStreams.length; k++) {
          if (identical(streams[k], firstStreams[k])) n++;
        }
        same = '$n/${streams.length}';
      }

      final ratio =
          label.startsWith('tile') ? _tilePx / page.cropBox.width : _fullRatio;
      final h0 = cache.hits, m0 = cache.misses;
      final sw = Stopwatch()..start();
      serializeCommands(
        recorder.commands,
        cos: cos,
        decodeImages: true,
        maxImagePixelRatio: ratio,
        pageRasterPixels: pdfPageRasterPixels(page.cropBox, ratio),
        imageCache: cache,
      );
      sw.stop();
      stdout.writeln('  p$i'.padRight(6) +
          label.padRight(8) +
          '${(sw.elapsedMicroseconds / 1000).toStringAsFixed(1)}ms'
              .padLeft(10) +
          '${cache.hits - h0}'.padLeft(7) +
          '${cache.misses - m0}'.padLeft(8) +
          '${cache.length}'.padLeft(9) +
          same.padLeft(13));
    }
    stdout.writeln('');
  }
  stdout.writeln('  cache total: ${cache.hits} hits, ${cache.misses} misses, '
      '${(cache.bytes / (1 << 20)).toStringAsFixed(1)} MB');
}
