// The per-PR perf gate that never flakes: DETERMINISTIC counters, zero wall
// time. Runs open + interpret + extract + save over a fixed input set (the
// programmatic test fixtures, a stable slice of the checked-in Ghent corpus,
// and the seeded synthetic CAD sheet) and records PdfPerf's structural
// counters - objects loaded, streams decoded, decoded bytes, content ops,
// fonts parsed, saved bytes. The numbers are identical on every machine and
// every run, so the committed baseline (tool/perf/baselines/counters.json)
// can be compared with a tight tolerance on a noisy shared runner.
//
// A counter drift means real work changed: more objects parsed per page,
// a filter decoding more bytes, an interpreter walking more ops. That is
// either a bug (this gate fails the PR) or a deliberate change - rerun with
// --update-baseline and the new numbers review as a normal diff.
//
//   cd packages/pdf_graphics
//   fvm dart run tool/perf_count_gate.dart                  # check (CI mode)
//   fvm dart run tool/perf_count_gate.dart --update-baseline
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_cos/perf.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

import 'perf_run_context.dart';

class NullDevice implements PdfDevice {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Relative drift allowed per counter before the gate fails. Most counters
/// are exactly reproducible; the band absorbs benign cross-version noise
/// (e.g. a Dart SDK bump changing an internal buffer growth pattern is NOT
/// expected to move these, but a zlib swap changing nothing but timing must
/// never fail the gate on a 0-byte diff rounding artifact).
const tolerance = 0.03;

/// The Ghent slice: stable, checked-in, exercise CMYK/transparency/fonts.
const ghentFiles = [
  '1-CMYK/GWG010_CMYK_OP_x3.pdf',
  '1-CMYK/GWG050_Font_Substitution_x3.pdf',
  '1-CMYK/GWG060_Shading_x1a.pdf',
  '2-SPOT/GWG020_CMYKSpot_OP_x1a.pdf',
  '3-ICC-CMS/GWG206_ICC_V4-RGB-Image_x4.pdf',
  '3-ICC-CMS/GWG230_Four_different Grays_x1a.pdf',
];

const trackedCounts = [
  PdfPerfCount.objectsLoaded,
  PdfPerfCount.objectStreamsLoaded,
  PdfPerfCount.streamsDecoded,
  PdfPerfCount.bytesDecodedFlate,
  PdfPerfCount.bytesDecodedOther,
  PdfPerfCount.contentOps,
  PdfPerfCount.contentBytes,
  PdfPerfCount.fontsParsed,
  PdfPerfCount.fontParseFailed,
  PdfPerfCount.savedBytes,
  PdfPerfCount.savedObjects,
  PdfPerfCount.xrefRecovered,
  PdfPerfCount.xrefOffsetRescue,
];

/// Deterministic workload over one document: open, interpret + extract every
/// page (bounded), save. Returns the PdfPerf counter snapshot.
Map<String, int> measure(Uint8List bytes, {int maxPages = 10}) {
  PdfPerf.reset();
  final doc = PdfDocument.open(bytes);
  final limit =
      doc.pageCount < maxPages ? doc.pageCount : maxPages;
  for (var i = 0; i < limit; i++) {
    PdfInterpreter(cos: doc.cos, device: NullDevice()).drawPage(doc.page(i));
    PdfTextExtractor.extract(doc, i);
  }
  final rootRef = doc.cos.trailer['Root'];
  if (rootRef is CosReference) {
    (CosIncrementalUpdater(doc.cos)
          ..replaceObject(rootRef.objectNumber, doc.cos.catalog))
        .save();
  }
  final stats = PdfPerf.snapshot();
  return {for (final c in trackedCounts) c.name: stats.count(c)};
}

void main(List<String> argv) {
  final update = argv.contains('--update-baseline');
  final repoRoot = findRepoRoot();
  final baselineFile = File('$repoRoot/tool/perf/baselines/counters.json');

  PdfPerf.enabled = true;

  final inputs = <String, Uint8List>{
    'fixture:classic': buildClassicPdf(),
    'fixture:xref-stream': buildXrefStreamPdf(),
    'fixture:multi-page-40': buildMultiPagePdf(40),
    'fixture:nested-tree': buildNestedPageTreePdf(),
    'fixture:embedded-font': buildEmbeddedFontPdf(),
  };
  for (final rel in ghentFiles) {
    final f = File('$repoRoot/test_corpora/ghent/$rel');
    if (f.existsSync()) inputs['ghent:$rel'] = f.readAsBytesSync();
  }
  // The seeded CAD sheet, 12 pages: enough content to make interpreter-side
  // drift visible without slowing the PR gate.
  final cad = File('$repoRoot/tool/perf/cache/gate-cad-12.pdf');
  if (!cad.existsSync()) {
    final r = Process.runSync(Platform.resolvedExecutable, [
      '$repoRoot/packages/pdf_cos/tool/gen_cad_pdf.dart',
      cad.path,
      '12',
      '6000',
      '20260718',
    ]);
    if (r.exitCode != 0) {
      stderr.writeln('CAD generator failed: ${r.stderr}');
      exit(1);
    }
  }
  inputs['synthetic:cad-12'] = cad.readAsBytesSync();

  final current = <String, Map<String, int>>{
    for (final e in inputs.entries) e.key: measure(e.value),
  };

  if (update) {
    baselineFile
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(current));
    stdout.writeln('baseline updated: ${baselineFile.path} '
        '(${current.length} inputs) - commit and review the diff');
    return;
  }

  if (!baselineFile.existsSync()) {
    stderr.writeln('no baseline at ${baselineFile.path}; run with '
        '--update-baseline first');
    exit(2);
  }
  final baseline = (jsonDecode(baselineFile.readAsStringSync()) as Map)
      .cast<String, Object?>();

  final failures = <String>[];
  current.forEach((input, counters) {
    final base = (baseline[input] as Map?)?.cast<String, Object?>();
    if (base == null) {
      failures.add('$input: not in baseline (run --update-baseline)');
      return;
    }
    counters.forEach((name, value) {
      final expected = base[name];
      if (expected is! int) return; // new counter: tolerated until re-baselined
      final band = (expected.abs() * tolerance).ceil();
      if ((value - expected).abs() > band) {
        final pct = expected == 0
            ? 'inf'
            : ((value - expected) * 100 / expected).toStringAsFixed(1);
        failures.add('$input  $name: $expected -> $value ($pct%)');
      }
    });
  });

  if (failures.isNotEmpty) {
    stderr.writeln('COUNTER GATE FAILED - deterministic work counters moved '
        'beyond ${(tolerance * 100).toStringAsFixed(0)}%:');
    stderr.writeln('  input                        counter: baseline -> now');
    for (final f in failures) {
      stderr.writeln('  $f');
    }
    stderr.writeln('If intentional: tool/perf.sh gate --update-baseline, '
        'commit, and explain the shift in the PR.');
    exit(1);
  }
  stdout.writeln('counter gate OK: ${current.length} inputs, '
      '${trackedCounts.length} counters within '
      '${(tolerance * 100).toStringAsFixed(0)}%');
}
