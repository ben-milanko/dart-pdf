// A/B benchmark for incremental content parsing on one-pass recording paths.
//
// Run from packages/pdf_graphics. Page numbers are one-based:
//
//   fvm dart run tool/dense_content_benchmark.dart /path/to/file.pdf \
//     --page 21 --repeat 9 --minimum-speedup 1.05
//
// Compare peak resident memory in separate processes (warmup zero avoids
// carrying the other mode's high-water mark):
//
//   ... --page 21 --mode materialized --warmup 0 --repeat 1
//   ... --page 21 --mode streaming --warmup 0 --repeat 1
//
// For lower-noise release measurements, compile and run the same harness:
//
//   fvm dart compile exe tool/dense_content_benchmark.dart \
//     -o /tmp/dart-pdf-dense-benchmark
//   /tmp/dart-pdf-dense-benchmark /path/to/file.pdf --page 21 --repeat 9
//
// Both modes record into the production RecordingPdfDevice. The materialized
// mode retains every ContentOperation through interpretation; the streaming
// mode keeps only the operation currently being executed.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

class _Args {
  String path = '';
  int page = 21;
  int repeat = 9;
  int warmup = 2;
  double minimumSpeedup = 1;
  String mode = 'both';
}

class _Sample {
  const _Sample(this.totalUs, this.parseUs, this.commandCount,
      {this.operationCount});

  final int totalUs;
  final int parseUs;
  final int commandCount;
  final int? operationCount;
}

_Args _parseArgs(List<String> argv) {
  final args = _Args();
  for (var i = 0; i < argv.length; i++) {
    String next(String flag) {
      if (++i >= argv.length) {
        stderr.writeln('missing value for $flag');
        exit(2);
      }
      return argv[i];
    }

    switch (argv[i]) {
      case '--page':
        args.page = int.parse(next(argv[i]));
      case '--repeat':
        args.repeat = int.parse(next(argv[i]));
      case '--warmup':
        args.warmup = int.parse(next(argv[i]));
      case '--minimum-speedup':
        args.minimumSpeedup = double.parse(next(argv[i]));
      case '--mode':
        args.mode = next(argv[i]);
      default:
        if (argv[i].startsWith('--')) {
          stderr.writeln('unknown flag ${argv[i]}');
          exit(2);
        }
        args.path = argv[i];
    }
  }
  if (args.path.isEmpty ||
      args.page <= 0 ||
      args.repeat <= 0 ||
      !const {'both', 'materialized', 'streaming'}.contains(args.mode)) {
    stderr.writeln('usage: dense_content_benchmark.dart <pdf> '
        '[--page N] [--repeat N] [--warmup N] [--mode MODE] '
        '[--minimum-speedup X]');
    exit(2);
  }
  return args;
}

_Sample _materialized(PdfPage page, Uint8List content) {
  PdfInterpreter.clearFontCache();
  final total = Stopwatch()..start();
  final parse = Stopwatch()..start();
  final operations = ContentStreamParser.parse(content);
  parse.stop();
  final recorder = RecordingPdfDevice();
  PdfInterpreter(cos: page.document.cos, device: recorder)
      .drawPageOperations(page, operations);
  total.stop();
  return _Sample(
    total.elapsedMicroseconds,
    parse.elapsedMicroseconds,
    recorder.commands.length,
    operationCount: operations.length,
  );
}

_Sample _streaming(PdfPage page, Uint8List content) {
  PdfInterpreter.clearFontCache();
  final total = Stopwatch()..start();
  final recorder = RecordingPdfDevice();
  PdfInterpreter(cos: page.document.cos, device: recorder)
      .drawPageContent(page, content);
  total.stop();
  return _Sample(total.elapsedMicroseconds, 0, recorder.commands.length);
}

int _percentile(List<int> values, double fraction) {
  final sorted = [...values]..sort();
  final index = math.max(0, (sorted.length * fraction).ceil() - 1);
  return sorted[index];
}

double _ms(int microseconds) => microseconds / 1000;

Never _singleMode(
  _Args args,
  PdfPage page,
  Uint8List content,
) {
  final materialized = args.mode == 'materialized';
  for (var i = 0; i < args.warmup; i++) {
    materialized ? _materialized(page, content) : _streaming(page, content);
  }
  final samples = <_Sample>[];
  for (var i = 0; i < args.repeat; i++) {
    samples.add(
      materialized ? _materialized(page, content) : _streaming(page, content),
    );
  }
  final totals = samples.map((sample) => sample.totalUs).toList();
  final result = <String, Object?>{
    'file': args.path.split(Platform.pathSeparator).last,
    'page': args.page,
    'mode': args.mode,
    'contentBytes': content.length,
    'operationCount': materialized ? samples.first.operationCount : null,
    'commandCount': samples.first.commandCount,
    'repeat': args.repeat,
    'totalMs': totals.map(_ms).toList(),
    'p50Ms': _ms(_percentile(totals, 0.5)),
    'p90Ms': _ms(_percentile(totals, 0.9)),
    'retainedParsedOperations':
        materialized ? samples.first.operationCount : (content.isEmpty ? 0 : 1),
    'maxRssBytes': ProcessInfo.maxRss,
  };
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));
  exit(0);
}

void main(List<String> argv) {
  final args = _parseArgs(argv);
  final bytes = File(args.path).readAsBytesSync();
  final document = PdfDocument.open(bytes);
  final pageIndex = args.page - 1;
  if (pageIndex >= document.pageCount) {
    stderr.writeln('page ${args.page} is outside 1..${document.pageCount}');
    exit(2);
  }
  final page = document.page(pageIndex);
  final content = page.contentBytes();
  if (args.mode != 'both') _singleMode(args, page, content);

  for (var i = 0; i < args.warmup; i++) {
    _materialized(page, content);
    _streaming(page, content);
  }

  final materialized = <_Sample>[];
  final streaming = <_Sample>[];
  for (var i = 0; i < args.repeat; i++) {
    if (i.isEven) {
      materialized.add(_materialized(page, content));
      streaming.add(_streaming(page, content));
    } else {
      streaming.add(_streaming(page, content));
      materialized.add(_materialized(page, content));
    }
  }

  final operationCount = materialized.first.operationCount!;
  final commandCount = materialized.first.commandCount;
  if (materialized.any((sample) =>
          sample.operationCount != operationCount ||
          sample.commandCount != commandCount) ||
      streaming.any((sample) => sample.commandCount != commandCount)) {
    throw StateError('benchmark modes produced inconsistent output counts');
  }

  final materializedTotal = materialized.map((s) => s.totalUs).toList();
  final materializedParse = materialized.map((s) => s.parseUs).toList();
  final streamingTotal = streaming.map((s) => s.totalUs).toList();
  final materializedP90 = _percentile(materializedTotal, 0.9);
  final streamingP90 = _percentile(streamingTotal, 0.9);
  final speedup = materializedP90 / streamingP90;
  final reduction = 1 - streamingP90 / materializedP90;

  final result = <String, Object>{
    'file': args.path.split(Platform.pathSeparator).last,
    'page': args.page,
    'contentBytes': content.length,
    'operationCount': operationCount,
    'commandCount': commandCount,
    'repeat': args.repeat,
    'materializedTotalMs': materializedTotal.map(_ms).toList(),
    'materializedParseMs': materializedParse.map(_ms).toList(),
    'streamingTotalMs': streamingTotal.map(_ms).toList(),
    'materializedP50Ms': _ms(_percentile(materializedTotal, 0.5)),
    'materializedP90Ms': _ms(materializedP90),
    'parseP90Ms': _ms(_percentile(materializedParse, 0.9)),
    'streamingP50Ms': _ms(_percentile(streamingTotal, 0.5)),
    'streamingP90Ms': _ms(streamingP90),
    'speedup': speedup,
    'latencyReduction': reduction,
    'materializedRetainedOperations': operationCount,
    'streamingRetainedOperations': operationCount == 0 ? 0 : 1,
  };
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));

  if (speedup < args.minimumSpeedup) {
    stderr.writeln('speedup ${speedup.toStringAsFixed(2)}x is below '
        '${args.minimumSpeedup.toStringAsFixed(2)}x');
    exitCode = 1;
  }
}
