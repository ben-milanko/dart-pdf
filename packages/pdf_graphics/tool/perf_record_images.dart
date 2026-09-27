// The `decodeImagesAtTarget` measure of perf_sweep.dart: the render worker's
// decoding record (serializeCommands with decodeImages), priced the way the
// worker pays it. The timer brackets the whole call, so it includes encoding
// the page's vector commands; image decode dominates it on image-heavy pages.
//
// perf_sweep's `decodeImages` measure decodes every drawn image at native
// size (decodePdfImagePixels). The worker never does: it serializes each
// page's record with the images decoded to their display target, under the
// page-wide raster budget, so the costs that matter on a real sheet - the
// target-aware scaled and masked paths, the stencil coverage kernel, the
// alpha composite and the box downsample - are invisible to a native decode.
// This measure records every page with a RecordingPdfDevice (untimed), then
// times exactly the worker's call:
//
//   serializeCommands(commands, cos:, decodeImages: true,
//       maxImagePixelRatio: R, pageRasterPixels: pdfPageRasterPixels(box, R),
//       imageCache: PdfImageDecodeCache(), compactStateScopes: true)
//
// with a fresh decode cache per page. R is the scenario's "imageRatio"
// (default 0.5). Alongside the best-of-N time it reports the PdfPerf call
// counts of imageDecode / imageDownsample / imageColorConvert / imageAlpha for
// one pass: deterministic, so a path change shows even where the time is
// noise.
//
// Why a separate script: perf_sweep.dart is grafted onto historic commits by
// tool/perf/backfill.sh, so it must keep compiling against APIs as old as the
// harness. The record-path APIs used here are much newer; perf_sweep spawns
// this script as a second child for the one measure that needs them.
//
//   cd packages/pdf_graphics
//   fvm dart run tool/perf_record_images.dart --one <file.pdf> \
//       [--max-pages N] [--repeat N] [--image-ratio R] [--phases]
//
// Prints one JSON object (the fields perf_sweep merges into its result row).
import 'dart:convert';
import 'dart:io';

import 'package:pdf_cos/perf.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

const _countedPhases = {
  'imageDecodeCalls': PdfPerfPhase.imageDecode,
  'imageDownsampleCalls': PdfPerfPhase.imageDownsample,
  'imageColorConvertCalls': PdfPerfPhase.imageColorConvert,
  'imageAlphaCalls': PdfPerfPhase.imageAlpha,
};

void main(List<String> argv) {
  String? path;
  var maxPages = 10;
  var repeat = 3;
  var ratio = 0.5;
  var phases = false;
  for (var i = 0; i < argv.length; i++) {
    String next() => argv[++i];
    switch (argv[i]) {
      case '--one':
        path = next();
      case '--max-pages':
        maxPages = int.parse(next());
      case '--repeat':
        repeat = int.parse(next());
      case '--image-ratio':
        ratio = double.parse(next());
      case '--phases':
        phases = true;
      default:
        stderr.writeln('unknown argument ${argv[i]}');
        exit(2);
    }
  }
  if (path == null || !(ratio > 0)) {
    stderr.writeln('usage: perf_record_images.dart --one <file.pdf> '
        '[--max-pages N] [--repeat N] [--image-ratio R>0] [--phases]');
    exit(2);
  }
  stdout.writeln(jsonEncode(_measure(path, maxPages, repeat, ratio, phases)));
}

Map<String, Object?> _measure(
    String path, int maxPages, int repeat, double ratio, bool phases) {
  final bytes = File(path).readAsBytesSync();
  // The call counts need the facade on; its disabled-path cost is one branch
  // and its enabled cost a clock read per phase - a handful per image, noise
  // against an image decode.
  PdfPerf.enabled = true;
  double? best;
  var pagesRendered = 0;
  var images = 0;
  Map<String, int>? calls;
  String? error;

  for (var r = 0; r < repeat; r++) {
    PdfDocument doc;
    try {
      doc = PdfDocument.open(bytes);
    } catch (e) {
      error ??= 'open: $e';
      break;
    }
    final pages = doc.pageCount;
    final limit = maxPages <= 0 || pages < maxPages ? pages : maxPages;
    final before = PdfPerf.snapshot();
    var us = 0;
    var done = 0;
    var drawn = 0;
    for (var i = 0; i < limit; i++) {
      try {
        final page = doc.page(i);
        final recorder = RecordingPdfDevice();
        PdfInterpreter(cos: doc.cos, device: recorder).drawPage(page);
        drawn += recorder.imageRequests.length;
        final sw = Stopwatch()..start();
        serializeCommands(recorder.commands,
            cos: doc.cos,
            decodeImages: true,
            maxImagePixelRatio: ratio,
            pageRasterPixels: pdfPageRasterPixels(page.cropBox, ratio),
            imageCache: PdfImageDecodeCache(),
            compactStateScopes: true);
        us += sw.elapsedMicroseconds;
        done++;
      } catch (e) {
        error ??= 'record page $i: $e';
      }
    }
    final ms = us / 1000.0;
    if (best == null || ms < best) best = ms;
    if (done > pagesRendered) pagesRendered = done;
    images = drawn;
    if (calls == null) {
      // One pass's calls (the passes are identical). Snapshot deltas, not a
      // reset, so --phases still reports the whole run.
      final after = PdfPerf.snapshot();
      calls = {
        for (final e in _countedPhases.entries)
          e.key: after.phaseCallCount(e.value) - before.phaseCallCount(e.value),
      };
    }
  }

  return {
    'pagesRendered': pagesRendered,
    if (best != null) 'decodeAtTargetMs': double.parse(best.toStringAsFixed(3)),
    if (best != null) 'imagesAtTarget': images,
    ...?calls,
    'peakRssBytes': ProcessInfo.maxRss,
    'error': error,
    if (phases) 'perfAtTarget': PdfPerf.snapshot().toJson(),
  };
}
