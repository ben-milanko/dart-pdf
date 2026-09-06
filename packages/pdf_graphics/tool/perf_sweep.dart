// Corpus timing sweep - the VM half of the perf suite (tool/perf.sh sweep).
// Measures, per PDF, best-of-N wall times for the whole document lifecycle
// short of rasterization (which needs a Flutter engine - see
// dart_pdf_editor/test/benchmark_render_test.dart):
//
//   openMs        parse + xref + first catalog resolve (PdfDocument.open)
//   firstPageMs   interpret page 0 to a NullDevice (open-to-first-page proxy)
//   interpretMs   interpret all pages (up to --max-pages) to a NullDevice
//   extractMs     text extraction over the same pages
//   saveMs        incremental-save round trip (catalog rewrite)
//   decodeMs      pure-Dart decode of every image the pages draw (opt-in, see
//                 the "measures" scenario key) - the codec half of a render,
//                 which the NullDevice interpret pass never reaches
//   peakRssBytes  the child process's ProcessInfo.maxRss
//
// Each file is measured in its own killable child process (parent re-spawns
// this script with --one), so a malformed or adversarial PDF that hangs or
// OOMs costs one timeout, not the sweep - and peak RSS is per-file clean.
//
//   cd packages/pdf_graphics
//   fvm dart run tool/perf_sweep.dart ../../test_corpora/ghent --repeat 3
//   fvm dart run tool/perf_sweep.dart --scenario ghent-suite-open
//
// Emits one envelope (tool/perf/SCHEMA.md, suite "vm-sweep"): --out for
// pretty JSON, --append-history to add an NDJSON line. --phases additionally
// enables the PdfPerf facade in the child and attaches per-file phase/counter
// snapshots under results[].perf.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_cos/perf.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

import 'perf_run_context.dart';

/// Swallows every device call; the interpreter still parses, shapes fonts,
/// and computes geometry.
class NullDevice implements PdfDevice {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// A [NullDevice] that keeps the image draws, so the `decodeImages` measure can
/// run the decode a real device would - without a Flutter engine.
class _ImageCollectingDevice implements PdfDevice {
  final requests = <PdfImageRequest>[];

  @override
  void drawImage(PdfImageRequest request) => requests.add(request);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

const _defaultMeasures = {'open', 'firstPage', 'interpret', 'extract', 'save'};

/// `decodeImages` is opt-in: it is the only measure that costs real time on
/// image-heavy corpora, and most scenarios exist to track the parse/interpret
/// path. Scenarios ask for it with the "measures" key.
const _allMeasures = {..._defaultMeasures, 'decodeImages'};

class _Args {
  String? corpus;
  String? scenario;
  String? one;
  String? out;
  String? appendHistory;
  int maxPages = 10;
  int repeat = 3;
  int timeoutS = 120;
  bool phases = false;
  Set<String> measures = _defaultMeasures;
}

_Args _parse(List<String> argv) {
  final a = _Args();
  for (var i = 0; i < argv.length; i++) {
    final arg = argv[i];
    String next() => argv[++i];
    switch (arg) {
      case '--scenario':
        a.scenario = next();
      case '--one':
        a.one = next();
      case '--out':
        a.out = next();
      case '--append-history':
        a.appendHistory = next();
      case '--max-pages':
        a.maxPages = int.parse(next());
      case '--repeat':
        a.repeat = int.parse(next());
      case '--timeout':
        a.timeoutS = int.parse(next());
      case '--phases':
        a.phases = true;
      case '--measures':
        a.measures = next().split(',').toSet();
        final unknown = a.measures.difference(_allMeasures);
        if (unknown.isNotEmpty) {
          stderr.writeln('unknown measures: ${unknown.join(',')}');
          exit(2);
        }
      default:
        if (arg.startsWith('--')) {
          stderr.writeln('unknown flag $arg');
          exit(2);
        }
        a.corpus = arg;
    }
  }
  if (a.one == null && a.corpus == null && a.scenario == null) {
    stderr.writeln(
        'usage: perf_sweep.dart <corpus-dir-or-file> | --scenario <name>\n'
        '  [--max-pages N] [--repeat N] [--timeout S] [--phases]\n'
        '  [--measures open,firstPage,interpret,extract,save,decodeImages]\n'
        '  [--out envelope.json] [--append-history history.ndjson]');
    exit(2);
  }
  return a;
}

// ---------------------------------------------------------------- child mode

double _ms(int us) => us / 1000.0;

/// Best-of-N measurement of one file; runs inside the killable child.
Map<String, Object?> _measureOne(_Args args) {
  final path = args.one!;
  final bytes = File(path).readAsBytesSync();
  if (args.phases) PdfPerf.enabled = true;

  var pages = 0;
  var pagesRendered = 0;
  var images = 0;
  String? error;
  final best = <String, double>{};
  void record(String key, int us) {
    final ms = _ms(us);
    final prev = best[key];
    if (prev == null || ms < prev) best[key] = ms;
  }

  for (var r = 0; r < args.repeat; r++) {
    final sw = Stopwatch()..start();
    PdfDocument doc;
    try {
      doc = PdfDocument.open(bytes);
      pages = doc.pageCount;
    } catch (e) {
      error ??= 'open: $e';
      break;
    }
    if (args.measures.contains('open')) record('openMs', sw.elapsedMicroseconds);

    final limit = pages < args.maxPages || args.maxPages <= 0
        ? pages
        : args.maxPages;

    if (args.measures.contains('firstPage') && pages > 0) {
      sw.reset();
      try {
        PdfInterpreter(cos: doc.cos, device: NullDevice()).drawPage(doc.page(0));
        record('firstPageMs', sw.elapsedMicroseconds);
      } catch (e) {
        error ??= 'firstPage: $e';
      }
    }

    if (args.measures.contains('interpret')) {
      sw.reset();
      var done = 0;
      for (var i = 0; i < limit; i++) {
        try {
          PdfInterpreter(cos: doc.cos, device: NullDevice())
              .drawPage(doc.page(i));
          done++;
        } catch (e) {
          error ??= 'interpret page $i: $e';
        }
      }
      record('interpretMs', sw.elapsedMicroseconds);
      if (done > pagesRendered) pagesRendered = done;
    }

    if (args.measures.contains('extract')) {
      sw.reset();
      for (var i = 0; i < limit; i++) {
        try {
          PdfTextExtractor.extract(doc, i);
        } catch (e) {
          error ??= 'extract page $i: $e';
        }
      }
      record('extractMs', sw.elapsedMicroseconds);
    }

    if (args.measures.contains('decodeImages')) {
      // Collect the image draws first (interpretation is already measured
      // above), then time only the decode - the pure-Dart path the render
      // worker runs, so the number is engine-free but real.
      final collector = _ImageCollectingDevice();
      var done = 0;
      for (var i = 0; i < limit; i++) {
        try {
          PdfInterpreter(cos: doc.cos, device: collector).drawPage(doc.page(i));
          done++;
        } catch (e) {
          error ??= 'collect images page $i: $e';
        }
      }
      if (done > pagesRendered) pagesRendered = done;
      sw.reset();
      for (final request in collector.requests) {
        try {
          decodePdfImagePixels(doc.cos, request.stream);
        } catch (e) {
          error ??= 'decode image: $e';
        }
      }
      record('decodeMs', sw.elapsedMicroseconds);
      images = collector.requests.length;
    }

    if (args.measures.contains('save')) {
      sw.reset();
      try {
        final rootRef = doc.cos.trailer['Root'];
        if (rootRef is CosReference) {
          // Rewrite the (unchanged) catalog: exercises the serializer, the
          // xref appender, and - on encrypted files - encrypt-on-write,
          // without depending on any document contents.
          final updater = CosIncrementalUpdater(doc.cos)
            ..replaceObject(rootRef.objectNumber, doc.cos.catalog);
          updater.save();
          record('saveMs', sw.elapsedMicroseconds);
        }
      } catch (e) {
        error ??= 'save: $e';
      }
    }
  }

  return {
    'file': path,
    'pages': pages,
    'pagesRendered': pagesRendered,
    if (best.containsKey('openMs')) 'openMs': best['openMs'],
    if (best.containsKey('firstPageMs')) 'firstPageMs': best['firstPageMs'],
    if (best.containsKey('interpretMs')) 'interpretMs': best['interpretMs'],
    if (best.containsKey('extractMs')) 'extractMs': best['extractMs'],
    if (best.containsKey('saveMs')) 'saveMs': best['saveMs'],
    if (best.containsKey('decodeMs')) 'decodeMs': best['decodeMs'],
    if (best.containsKey('decodeMs')) 'imagesDecoded': images,
    'peakRssBytes': ProcessInfo.maxRss,
    'error': error,
    if (args.phases) 'perf': PdfPerf.snapshot().toJson(),
  };
}

// --------------------------------------------------------------- parent mode

List<File> _findPdfs(String root) {
  final type = FileSystemEntity.typeSync(root);
  if (type == FileSystemEntityType.file) return [File(root)];
  if (type == FileSystemEntityType.notFound) return [];
  return Directory(root)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.pdf'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

/// Resolves --scenario against tool/perf/scenarios.json; mutates [args] with
/// the scenario's parameters and returns the corpus path (generating a
/// cached synthetic corpus when the scenario asks for one). Returns null when
/// a local-only scenario's assets are absent (caller exits 0 with a notice).
Future<String?> _resolveScenario(_Args args, String repoRoot) async {
  final file = File('$repoRoot/tool/perf/scenarios.json');
  final scenarios = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  final s = scenarios[args.scenario];
  if (s is! Map) {
    stderr.writeln('unknown scenario "${args.scenario}" '
        '(known: ${scenarios.keys.join(', ')})');
    exit(2);
  }
  if (s['suite'] != null && s['suite'] != 'vm-sweep') {
    stderr.writeln('scenario "${args.scenario}" is suite ${s['suite']}, '
        'not vm-sweep - use the matching tool/perf.sh subcommand');
    exit(2);
  }
  if (s['maxPages'] is int) args.maxPages = s['maxPages'] as int;
  if (s['repeat'] is int) args.repeat = s['repeat'] as int;
  if (s['timeoutS'] is int) args.timeoutS = s['timeoutS'] as int;
  if (s['measures'] is List) {
    args.measures = (s['measures'] as List).cast<String>().toSet();
  }
  if (s['phases'] == true) args.phases = true;

  final generate = s['generate'];
  if (generate is Map) {
    final seed = generate['seed'] as int? ?? 20260718;
    // "wide" shape: one ultra-wide single-page strip drawing (the janky-CAD
    // shape) instead of the multi-page A1 set - a different generator and a
    // different cache name, so the two never collide.
    if (generate['shape'] == 'wide') {
      final ops = generate['ops'] as int? ?? 850000;
      final streams = generate['streams'] as int? ?? 8;
      final cache =
          File('$repoRoot/tool/perf/cache/cad-wide-$ops-$streams-$seed.pdf');
      if (!cache.existsSync()) {
        stderr.writeln('generating ${cache.path}...');
        final r = await Process.run(Platform.resolvedExecutable, [
          '$repoRoot/packages/pdf_test_fixtures/tool/gen_cad_wide_pdf.dart',
          cache.path,
          '$ops',
          '$streams',
          '$seed',
        ], workingDirectory: repoRoot);
        if (r.exitCode != 0) {
          stderr.writeln('generator failed: ${r.stderr}');
          exit(1);
        }
      }
      return cache.path;
    }
    final pagesN = generate['pages'] as int? ?? 138;
    final ops = generate['opsPerPage'] as int? ?? 6000;
    final cache =
        File('$repoRoot/tool/perf/cache/cad-$pagesN-$ops-$seed.pdf');
    if (!cache.existsSync()) {
      stderr.writeln('generating ${cache.path}...');
      final r = await Process.run(Platform.resolvedExecutable, [
        '$repoRoot/packages/pdf_cos/tool/gen_cad_pdf.dart',
        cache.path,
        '$pagesN',
        '$ops',
        '$seed',
      ], workingDirectory: repoRoot);
      if (r.exitCode != 0) {
        stderr.writeln('generator failed: ${r.stderr}');
        exit(1);
      }
    }
    return cache.path;
  }

  final corpus = s['corpus'] as String?;
  if (corpus == null) {
    stderr.writeln('scenario "${args.scenario}" has neither corpus nor '
        'generate');
    exit(2);
  }
  final path = '$repoRoot/$corpus';
  if (_findPdfs(path).isEmpty) {
    if (s['ciSafe'] == false) {
      stderr.writeln('scenario "${args.scenario}" skipped: $corpus has no '
          'PDFs here (local-only corpus)');
      return null;
    }
    stderr.writeln('scenario "${args.scenario}": no PDFs under $path');
    exit(1);
  }
  return path;
}

Future<Map<String, Object?>> _runChild(
    _Args args, String scriptPath, File file) async {
  final process = await Process.start(Platform.resolvedExecutable, [
    scriptPath,
    '--one',
    file.path,
    '--max-pages',
    '${args.maxPages}',
    '--repeat',
    '${args.repeat}',
    '--measures',
    args.measures.join(','),
    if (args.phases) '--phases',
  ]);
  final stdoutF = process.stdout.transform(utf8.decoder).join();
  final stderrF = process.stderr.transform(utf8.decoder).join();
  var timedOut = false;
  final timer = Timer(Duration(seconds: args.timeoutS), () {
    timedOut = true;
    process.kill(ProcessSignal.sigkill);
  });
  final code = await process.exitCode;
  timer.cancel();
  final out = await stdoutF;
  final err = await stderrF;
  if (timedOut) {
    return {
      'file': file.path,
      'pages': 0,
      'pagesRendered': 0,
      'error': 'timeout after ${args.timeoutS}s',
    };
  }
  if (code != 0) {
    final detail = err.trim().replaceAll('\n', ' | ');
    return {
      'file': file.path,
      'pages': 0,
      'pagesRendered': 0,
      'error': 'child exited $code: '
          '${detail.length > 400 ? detail.substring(0, 400) : detail}',
    };
  }
  try {
    return jsonDecode(out) as Map<String, Object?>;
  } catch (e) {
    return {
      'file': file.path,
      'pages': 0,
      'pagesRendered': 0,
      'error': 'child emitted unparseable output: $e',
    };
  }
}

Map<String, Object?> _aggregate(List<Map<String, Object?>> results) {
  List<double> values(String key, {bool perPage = false}) => [
        for (final r in results)
          if (r[key] is num && (!perPage || (r['pagesRendered'] as int? ?? 0) > 0))
            perPage
                ? (r[key] as num) / (r['pagesRendered'] as int)
                : (r[key] as num).toDouble(),
      ];
  double round(double v) => double.parse(v.toStringAsFixed(3));
  Map<String, Object?> dist(String key, {bool perPage = false}) {
    final v = values(key, perPage: perPage);
    if (v.isEmpty) return {};
    var name = perPage ? '${key.replaceAll('Ms', '')}MsPerPage' : key;
    name = name[0].toUpperCase() + name.substring(1);
    return {
      'p50$name': round(percentile(v, 50)),
      'p95$name': round(percentile(v, 95)),
      'max$name': round(percentile(v, 100)),
    };
  }

  final errors = results.where((r) => r['error'] != null).length;
  final rss = values('peakRssBytes');
  return {
    'files': results.length,
    'errors': errors,
    ...dist('openMs'),
    ...dist('firstPageMs'),
    ...dist('interpretMs', perPage: true),
    ...dist('extractMs', perPage: true),
    ...dist('saveMs'),
    ...dist('decodeMs', perPage: true),
    if (rss.isNotEmpty) 'maxPeakRssBytes': percentile(rss, 100).round(),
  };
}

Future<void> main(List<String> argv) async {
  final args = _parse(argv);

  if (args.one != null) {
    stdout.writeln(jsonEncode(_measureOne(args)));
    return;
  }

  final repoRoot = findRepoRoot();
  final scriptPath = File.fromUri(Platform.script).path;

  String? corpus = args.corpus;
  if (args.scenario != null) {
    corpus = await _resolveScenario(args, repoRoot);
    if (corpus == null) return; // local-only scenario, assets absent
  }

  final files = _findPdfs(corpus!);
  if (files.isEmpty) {
    stderr.writeln('no PDFs under $corpus');
    exit(1);
  }

  final results = <Map<String, Object?>>[];
  final corpusIsDir =
      FileSystemEntity.typeSync(corpus) == FileSystemEntityType.directory;
  for (final (i, file) in files.indexed) {
    final r = await _runChild(args, scriptPath, file);
    // Relativize for stable cross-machine file keys.
    r['file'] = corpusIsDir
        ? file.path.substring(corpus.length).replaceAll(RegExp(r'^/'), '')
        : file.uri.pathSegments.last;
    results.add(r);
    stderr.writeln('  [${i + 1}/${files.length}] ${r['file']} '
        '${r['error'] == null ? 'ok' : 'ERROR: ${r['error']}'}');
  }

  final envelope = {
    'schema': 1,
    'suite': 'vm-sweep',
    'scenario': args.scenario,
    'tool': 'dart-pdf-sweep',
    'engine': 'dart-pdf (VM, NullDevice interpret)',
    'maxPages': args.maxPages,
    'params': {
      'repeat': args.repeat,
      'timeoutS': args.timeoutS,
      'measures': args.measures.toList()..sort(),
      'phases': args.phases,
      'corpus': corpus.startsWith(repoRoot)
          ? corpus.substring(repoRoot.length + 1)
          : corpus,
    },
    'rev': revInfo(repoRoot),
    'env': envInfo(),
    'ts': isoNow(),
    'metrics': _aggregate(results),
    'results': results,
  };

  final pretty = const JsonEncoder.withIndent('  ').convert(envelope);
  if (args.out != null) {
    File(args.out!)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(pretty);
    stderr.writeln('wrote ${args.out}');
  } else {
    stdout.writeln(pretty);
  }
  if (args.appendHistory != null) {
    File(args.appendHistory!)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('${jsonEncode(envelope)}\n', mode: FileMode.append);
    stderr.writeln('appended to ${args.appendHistory}');
  }
}
