// Benchmarks dart-pdf's parse + content-stream interpretation, the pure-Dart
// half of rendering (no rasterization — that needs Flutter; see
// dart_pdf_editor/test/benchmark_render_test.dart). Runs on the Dart VM:
//
//   cd packages/pdf_graphics
//   fvm dart run tool/benchmark_interpret.dart ../../test_corpora/pdfjs \
//       --max-pages 10 --out ../../benchmark/out/dart-interpret.json
//
// Emits the JSON schema shared with the PDFium harness
// (benchmark/pdfium_benchmark.py) so benchmark/compare.py can line the tools
// up file-by-file. `renderMs` here is interpret-only wall time (the
// interpreter walks the page to a NullDevice); `openMs` is parse/load.
import 'dart:convert';
import 'dart:io';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

/// Swallows every device call — the interpreter still does all the parsing,
/// font shaping, and geometry work; only the paint sink is a no-op.
class NullDevice implements PdfDevice {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Args {
  String corpus = '';
  double scale = 1; // recorded for schema parity; interpret is scale-free
  int maxPages = 10;
  int repeat = 1;
  String? out;
}

_Args _parse(List<String> argv) {
  final a = _Args();
  for (var i = 0; i < argv.length; i++) {
    final arg = argv[i];
    String next() => argv[++i];
    switch (arg) {
      case '--scale':
        a.scale = double.parse(next());
      case '--max-pages':
        a.maxPages = int.parse(next());
      case '--repeat':
        a.repeat = int.parse(next());
      case '--out':
        a.out = next();
      default:
        if (arg.startsWith('--')) {
          stderr.writeln('unknown flag $arg');
          exit(2);
        }
        a.corpus = arg;
    }
  }
  if (a.corpus.isEmpty) {
    stderr.writeln('usage: benchmark_interpret.dart <corpus> [--max-pages N] '
        '[--repeat N] [--scale S] [--out file.json]');
    exit(2);
  }
  return a;
}

List<File> _findPdfs(String root) {
  final entity = FileSystemEntity.typeSync(root);
  if (entity == FileSystemEntityType.file) return [File(root)];
  final files = Directory(root)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.pdf'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return files;
}

/// (pages, pagesInterpreted, openMs, interpretMs, error)
(int, int, double, double, String?) _benchFile(File file, int maxPages) {
  final bytes = file.readAsBytesSync();
  final sw = Stopwatch()..start();
  PdfDocument doc;
  int pages;
  try {
    doc = PdfDocument.open(bytes);
    pages = doc.pageCount;
  } catch (e) {
    return (0, 0, sw.elapsedMicroseconds / 1000, 0, e.toString());
  }
  final openMs = sw.elapsedMicroseconds / 1000;

  final limit = maxPages <= 0 ? pages : (pages < maxPages ? pages : maxPages);
  var interpreted = 0;
  String? error;
  final walk = Stopwatch()..start();
  for (var i = 0; i < limit; i++) {
    try {
      PdfInterpreter(cos: doc.cos, device: NullDevice()).drawPage(doc.page(i));
      interpreted++;
    } catch (e) {
      error ??= 'page $i: $e';
    }
  }
  walk.stop();
  return (pages, interpreted, openMs, walk.elapsedMicroseconds / 1000, error);
}

void main(List<String> argv) {
  final args = _parse(argv);
  final files = _findPdfs(args.corpus);
  if (files.isEmpty) {
    stderr.writeln('no PDFs under ${args.corpus}');
    exit(1);
  }
  final corpusIsDir =
      FileSystemEntity.typeSync(args.corpus) == FileSystemEntityType.directory;

  final best = <String, Map<String, Object?>>{};
  for (var r = 0; r < args.repeat; r++) {
    for (final file in files) {
      final (pages, did, openMs, interpMs, error) =
          _benchFile(file, args.maxPages);
      final name = corpusIsDir
          ? file.path.substring(args.corpus.length).replaceAll(RegExp(r'^/'), '')
          : file.uri.pathSegments.last;
      final prev = best[file.path];
      final better = prev == null ||
          (error == null &&
              (prev['error'] != null ||
                  interpMs < (prev['renderMs'] as double)));
      if (better) {
        best[file.path] = {
          'file': name,
          'pages': pages,
          'pagesRendered': did,
          'openMs': double.parse(openMs.toStringAsFixed(3)),
          'renderMs': double.parse(interpMs.toStringAsFixed(3)),
          'error': error,
        };
      }
    }
    stderr.writeln('  dart-interpret pass ${r + 1}/${args.repeat} done '
        '(${files.length} files)');
  }

  final payload = {
    'tool': 'dart-pdf-interpret',
    'scale': args.scale,
    'maxPages': args.maxPages,
    'engine': 'dart-pdf (pdf_graphics interpreter, NullDevice)',
    'results': [for (final f in files) best[f.path]],
  };
  final text = const JsonEncoder.withIndent('  ').convert(payload);
  final outPath = args.out;
  if (outPath != null) {
    final outFile = File(outPath)..parent.createSync(recursive: true);
    outFile.writeAsStringSync(text);
    stderr.writeln('wrote $outPath');
  } else {
    stdout.writeln(text);
  }
}
