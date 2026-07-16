// Measures retained worker-transcript construction and memory in one process.
// Run the two modes as separate AOT processes so maxRss is comparable:
//
//   fvm dart compile exe tool/transcript_cache_benchmark.dart \
//     -o /tmp/dart-pdf-transcript-cache-benchmark
//   /tmp/dart-pdf-transcript-cache-benchmark /path/to/file.pdf \
//     --page 5 --deduplicate false
//   /tmp/dart-pdf-transcript-cache-benchmark /path/to/file.pdf \
//     --page 5 --deduplicate true
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dart_pdf_editor/src/render_worker_transcript_cache.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

class _Args {
  String path = '';
  int page = 5;
  int repeat = 7;
  bool deduplicate = true;
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
      case '--deduplicate':
        args.deduplicate = switch (next(argv[i])) {
          'true' => true,
          'false' => false,
          final value => throw FormatException('invalid boolean $value'),
        };
      default:
        if (argv[i].startsWith('--')) {
          stderr.writeln('unknown flag ${argv[i]}');
          exit(2);
        }
        args.path = argv[i];
    }
  }
  if (args.path.isEmpty || args.page <= 0 || args.repeat <= 0) {
    stderr.writeln('usage: transcript_cache_benchmark.dart <pdf> '
        '[--page N] [--repeat N] [--deduplicate true|false]');
    exit(2);
  }
  return args;
}

int _percentile(List<int> values, double fraction) {
  final sorted = [...values]..sort();
  return sorted[math.max(0, (sorted.length * fraction).ceil() - 1)];
}

int _hash(List<int> bytes) {
  var hash = 0x811c9dc5;
  for (final byte in bytes) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash;
}

void main(List<String> argv) async {
  final args = _parseArgs(argv);
  final document = PdfDocument.open(File(args.path).readAsBytesSync());
  final pageIndex = args.page - 1;
  if (pageIndex >= document.pageCount) {
    stderr.writeln('page ${args.page} is outside 1..${document.pageCount}');
    exit(2);
  }
  final cache = PdfWorkerTranscriptCache(
    capacity: 4,
    maxRetainedCommands: 1 << 30,
    deduplicateCommands: args.deduplicate,
  );
  final build = Stopwatch()..start();
  final transcript = await cache.transcriptFor(
    document,
    pageIndex,
    false,
    PdfCancellationToken(),
    yieldInterval: 1 << 30,
  );
  build.stop();
  if (transcript == null) throw StateError('page did not serialize');

  final serializeMicros = <int>[];
  var serializedBytes = 0;
  var serializedHash = 0;
  for (var i = 0; i < args.repeat; i++) {
    final stopwatch = Stopwatch()..start();
    final buffer = serializeCommands(
      transcript.sourceCommands,
      cos: document.cos,
      decodeImages: false,
      imagePlaceholders: true,
      compactStateScopes: true,
    );
    stopwatch.stop();
    if (buffer == null) throw StateError('cached transcript did not serialize');
    serializedBytes = buffer.length;
    serializedHash = _hash(buffer);
    serializeMicros.add(stopwatch.elapsedMicroseconds);
  }

  final result = <String, Object>{
    'file': args.path.split(Platform.pathSeparator).last,
    'page': args.page,
    'deduplicate': args.deduplicate,
    'buildMs': build.elapsedMicroseconds / 1000,
    'sourceCommands': transcript.sourceCommands.length,
    'wireCommands': transcript.wireCommands.length,
    'commandGraphsAliased':
        identical(transcript.sourceCommands, transcript.wireCommands),
    'retainedCommandWeight': transcript.retainedCommandWeight,
    'serializedBytes': serializedBytes,
    'serializedHash': serializedHash,
    'warmSerializeP50Ms': _percentile(serializeMicros, 0.5) / 1000,
    'warmSerializeP90Ms': _percentile(serializeMicros, 0.9) / 1000,
    'currentRssBytes': ProcessInfo.currentRss,
    'maxRssBytes': ProcessInfo.maxRss,
  };
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));
}
