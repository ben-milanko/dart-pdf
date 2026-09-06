// Benchmarks parse + interpret + sparse-strip generation (lib/raster.dart),
// the pure-Dart CPU half of the shader-driven strip renderer (M1 gate of
// the strip experiment; no GPU upload/draw - that needs Flutter). Runs on
// the Dart VM:
//
//   cd packages/pdf_graphics
//   fvm dart run tool/benchmark_strips.dart ../../corpus \
//       --max-pages 10 --out ../../benchmark/out/dart-strips.json
//
// Emits the JSON schema shared with the other harnesses so
// benchmark/compare.py can line the tools up file-by-file: `renderMs` is
// interpret+strip-generate wall time per file; `openMs` is parse/load.
// Extra per-file `strips` and top-level `stripStats` fields carry strip
// counts, alpha atlas bytes, and solid-strip fractions (ignored by
// compare.py).
//
// The headless device routes solid fills, strokes, and outline-glyph text
// into a StripGenerator at the requested scale (device = page size x
// scale); images, gradients, meshes, groups, and soft masks are counted
// and skipped (Track B delegates those to the canvas fallback).
import 'dart:convert';
import 'dart:io';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_graphics/raster.dart';
// (GlyphStripCache comes from raster.dart)

/// Per-run strip + delegation statistics.
class StripStats {
  int strips = 0;
  int solidStrips = 0;
  int alphaBytes = 0;
  int fills = 0;
  int strokes = 0;
  int glyphs = 0;
  int substitutedRuns = 0;
  int images = 0;
  int gradients = 0;
  int meshes = 0;
  int groups = 0;
  int softMasks = 0;
  int clips = 0;

  void addBuffer(StripBuffer b) {
    strips += b.length;
    alphaBytes += b.alphaColumns * 4;
    for (var i = 0; i < b.length; i++) {
      if (b.widthFlags[i] & stripFlagSolid != 0) solidStrips++;
    }
  }

  Map<String, Object?> toJson() => {
        'strips': strips,
        'solidStrips': solidStrips,
        'alphaBytes': alphaBytes,
        'fills': fills,
        'strokes': strokes,
        'glyphs': glyphs,
        'substitutedRuns': substitutedRuns,
        'images': images,
        'gradients': gradients,
        'meshes': meshes,
        'groups': groups,
        'softMasks': softMasks,
        'clips': clips,
      };
}

/// Headless [PdfDevice] that strip-generates every solid paint primitive
/// and counts everything the strip path would delegate.
class StripBenchDevice implements PdfDevice {
  StripBenchDevice(this.gen, this.pageToDevice, this.stats);

  final StripGenerator gen;
  final PdfMatrix pageToDevice;
  final StripStats stats;

  @override
  void save() {}

  @override
  void restore() {}

  @override
  void fillPath(PdfPath path, PdfColor color, PdfFillRule rule, double alpha) {
    stats.fills++;
    gen.fillPath(path, pageToDevice, rule, premulRgba8(color, alpha));
  }

  @override
  void fillPathGradient(
      PdfPath path, PdfFillRule rule, PdfGradient gradient, double alpha) {
    stats.gradients++;
  }

  @override
  void fillMesh(PdfMesh mesh, double alpha) {
    stats.meshes++;
  }

  @override
  void strokePath(
      PdfPath path, PdfColor color, PdfStroke stroke, double alpha) {
    stats.strokes++;
    gen.strokePath(path, pageToDevice, stroke, premulRgba8(color, alpha));
  }

  @override
  void clipPath(PdfPath path, PdfFillRule rule) {
    stats.clips++; // Track B clips GPU-side (canvas.clipPath), not here
  }

  @override
  void drawText(PdfTextRun run) {
    if (run.invisible) return;
    final glyphs = run.glyphs;
    if (glyphs == null) {
      stats.substitutedRuns++; // no embedded outlines: canvas fallback
      return;
    }
    if (run.gradient != null) stats.gradients++;
    final color =
        premulRgba8(run.fill ? run.color : (run.strokeColor ?? run.color), 1);
    for (final glyph in glyphs) {
      final outline = glyph.outline;
      if (outline == null) continue;
      stats.glyphs++;
      final emToDevice = PdfMatrix.translation(glyph.offset, glyph.offsetY)
          .concat(run.transform)
          .concat(pageToDevice);
      gen.fillOutline(FlattenedOutline.of(outline), emToDevice, color);
    }
  }

  @override
  void drawImage(PdfImageRequest request) {
    stats.images++;
  }

  @override
  void setBlendMode(PdfBlendMode mode) {}

  @override
  void setOverprint(
      {required bool fill, required bool stroke, required int mode}) {}

  @override
  void beginGroup(double alpha, {bool knockout = false}) {
    stats.groups++;
  }

  @override
  void endGroup() {}

  @override
  void beginSoftMasked() {
    stats.softMasks++;
  }

  @override
  void endSoftMasked({
    required bool luminosity,
    required PdfRect backdrop,
    required void Function() drawMask,
    double backdropLuminance = 0,
    double transferScale = 1,
    double transferOffset = 0,
  }) {
    // masked content already arrived through the normal callbacks; the mask
    // group itself is delegated work - skip drawMask.
  }
}

class _Args {
  String corpus = '';
  double scale = 2;
  int maxPages = 10;
  int repeat = 1;
  bool glyphCache = true;
  bool shapeCache = true;
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
      case '--no-glyph-cache':
        a.glyphCache = false;
      case '--no-shape-cache':
        a.shapeCache = false;
      default:
        if (arg.startsWith('--')) {
          stderr.writeln('unknown flag $arg');
          exit(2);
        }
        a.corpus = arg;
    }
  }
  if (a.corpus.isEmpty) {
    stderr.writeln('usage: benchmark_strips.dart <corpus> [--max-pages N] '
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

/// (pages, pagesRendered, openMs, renderMs, error, stats)
(int, int, double, double, String?, StripStats) _benchFile(
    File file, int maxPages, double scale, StripGenerator gen) {
  final stats = StripStats();
  final bytes = file.readAsBytesSync();
  final sw = Stopwatch()..start();
  PdfDocument doc;
  int pages;
  try {
    doc = PdfDocument.open(bytes);
    pages = doc.pageCount;
  } catch (e) {
    return (0, 0, sw.elapsedMicroseconds / 1000, 0, e.toString(), stats);
  }
  final openMs = sw.elapsedMicroseconds / 1000;

  final limit = maxPages <= 0 ? pages : (pages < maxPages ? pages : maxPages);
  var rendered = 0;
  String? error;
  final walk = Stopwatch()..start();
  for (var i = 0; i < limit; i++) {
    try {
      final page = doc.page(i);
      final box = page.cropBox;
      final w = (box.width * scale).ceil();
      final h = (box.height * scale).ceil();
      if (w <= 0 || h <= 0) continue;
      final pageToDevice = PdfMatrix(
          scale, 0, 0, -scale, -box.left * scale, box.top * scale);
      gen.begin(w, h);
      final device = StripBenchDevice(gen, pageToDevice, stats);
      PdfInterpreter(cos: doc.cos, device: device).drawPage(page);
      stats.addBuffer(gen.strips);
      rendered++;
    } catch (e) {
      error ??= 'page $i: $e';
    }
  }
  walk.stop();
  return (
    pages,
    rendered,
    openMs,
    walk.elapsedMicroseconds / 1000,
    error,
    stats
  );
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

  // reused across pages and files
  final gen = StripGenerator()
    ..glyphCache = args.glyphCache ? GlyphStripCache.shared : null
    ..shapeCache = args.shapeCache ? ShapeStripCache.shared : null;
  final best = <String, Map<String, Object?>>{};
  for (var r = 0; r < args.repeat; r++) {
    for (final file in files) {
      final (pages, did, openMs, renderMs, error, stats) =
          _benchFile(file, args.maxPages, args.scale, gen);
      final name = corpusIsDir
          ? file.path.substring(args.corpus.length).replaceAll(RegExp(r'^/'), '')
          : file.uri.pathSegments.last;
      final prev = best[file.path];
      final better = prev == null ||
          (error == null &&
              (prev['error'] != null ||
                  renderMs < (prev['renderMs'] as double)));
      if (better) {
        best[file.path] = {
          'file': name,
          'pages': pages,
          'pagesRendered': did,
          'openMs': double.parse(openMs.toStringAsFixed(3)),
          'renderMs': double.parse(renderMs.toStringAsFixed(3)),
          'error': error,
          'strips': stats.toJson(),
        };
      }
    }
    stderr.writeln('  dart-strips pass ${r + 1}/${args.repeat} done '
        '(${files.length} files)');
  }

  // Aggregate: per-page means over successfully rendered pages.
  var totalPages = 0;
  var totalMs = 0.0;
  var totalStrips = 0;
  var totalSolid = 0;
  var totalAlphaBytes = 0;
  for (final f in files) {
    final r = best[f.path]!;
    if (r['error'] != null) continue;
    final did = r['pagesRendered'] as int;
    if (did == 0) continue;
    totalPages += did;
    totalMs += r['renderMs'] as double;
    final s = r['strips'] as Map<String, Object?>;
    totalStrips += s['strips'] as int;
    totalSolid += s['solidStrips'] as int;
    totalAlphaBytes += s['alphaBytes'] as int;
  }
  final gc = GlyphStripCache.shared;
  final sc = ShapeStripCache.shared;
  final summary = {
    'pages': totalPages,
    'glyphCache': args.glyphCache
        ? {
            'hits': gc.hits,
            'misses': gc.misses,
            'firstSights': gc.firstSights,
            'bypasses': gc.bypasses,
            'entries': gc.entryCount,
            'alphaBytes': gc.alphaBytes,
            'hitRate': (gc.hits + gc.misses) == 0
                ? null
                : double.parse(
                    (gc.hits / (gc.hits + gc.misses)).toStringAsFixed(3)),
          }
        : null,
    'shapeCache': args.shapeCache
        ? {
            'hits': sc.hits,
            'misses': sc.misses,
            'firstSights': sc.firstSights,
            'bypasses': sc.bypasses,
            'collisions': sc.collisions,
            'entries': sc.entryCount,
            'dataBytes': sc.dataBytes,
            'hitRate': (sc.hits + sc.misses) == 0
                ? null
                : double.parse(
                    (sc.hits / (sc.hits + sc.misses)).toStringAsFixed(3)),
          }
        : null,
    'renderMsPerPage':
        totalPages == 0 ? null : double.parse((totalMs / totalPages).toStringAsFixed(2)),
    'stripsPerPage': totalPages == 0 ? null : totalStrips ~/ totalPages,
    'alphaBytesPerPage':
        totalPages == 0 ? null : totalAlphaBytes ~/ totalPages,
    'solidStripFraction': totalStrips == 0
        ? null
        : double.parse((totalSolid / totalStrips).toStringAsFixed(3)),
  };
  stderr.writeln('  summary: $summary');

  final payload = {
    'tool': 'dart-pdf-strips',
    'scale': args.scale,
    'maxPages': args.maxPages,
    'engine': 'dart-pdf (pdf_graphics interpreter -> StripGenerator)',
    'stripStats': summary,
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
