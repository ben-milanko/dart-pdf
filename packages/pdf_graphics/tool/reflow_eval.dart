// Scores the reading-view reflow pipeline against the generated corpus.
//
// This is the ruler for reading-view work: it turns "the reflow looks better"
// into seven numbers per document that move, or do not, when the pipeline
// changes. The corpus and its ground truth come from
// tool/gen_reflow_corpus.dart; the metrics live in tool/reflow/scoring.dart.
//
//   cd packages/pdf_graphics
//   fvm dart run tool/reflow_eval.dart                    # check vs baseline
//   fvm dart run tool/reflow_eval.dart --update-baseline  # re-baseline
//   fvm dart run tool/reflow_eval.dart --json             # machine readable
//   fvm dart run tool/reflow_eval.dart --only two-column  # one document
//
// The baseline (tool/reflow/baseline.json) is committed. A metric falling
// more than [tolerance] below it fails the run, which is what the gate test
// (test/reflow_eval_test.dart) asserts in CI. A metric that RISES never
// fails - it just shows up in the diff when you re-baseline.
import 'dart:convert';
import 'dart:io';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

import 'reflow/scoring.dart';
import 'reflow/truth.dart';

/// How far a metric may fall below baseline before the run fails. The
/// pipeline is deterministic, so this absorbs nothing but rounding - any real
/// drop is a real regression.
const tolerance = 0.005;

void main(List<String> argv) {
  final update = argv.contains('--update-baseline');
  final asJson = argv.contains('--json');
  String? only;
  for (var i = 0; i < argv.length; i++) {
    if (argv[i] == '--only' && i + 1 < argv.length) only = argv[i + 1];
  }

  final corpus = Directory('../../test_corpora/reflow');
  if (!corpus.existsSync()) {
    stderr.writeln('no corpus at ${corpus.path} - run '
        'tool/gen_reflow_corpus.dart first');
    exit(2);
  }

  final scores = runReflowEval(corpus.path, only: only);
  if (scores.isEmpty) {
    stderr.writeln('no documents scored${only == null ? '' : ' for "$only"'}');
    exit(2);
  }

  final pooled = poolReflowScores(scores);
  final baselineFile = File('tool/reflow/baseline.json');

  if (update) {
    const encoder = JsonEncoder.withIndent('  ');
    baselineFile.writeAsStringSync('${encoder.convert({
          'documents': {for (final s in scores) s.name: s.toJson()},
          'pooled': {
            for (final e in pooled.entries) e.key: roundReflowMetric(e.value)
          },
        })}\n');
    stdout.writeln(_table(scores, pooled));
    stdout.writeln('\nbaseline updated: ${baselineFile.path}');
    return;
  }

  if (asJson) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert({
      'documents': [for (final s in scores) s.toJson()],
      'pooled': pooled,
    }));
    return;
  }

  stdout.writeln(_table(scores, pooled));

  if (!baselineFile.existsSync()) {
    stderr.writeln('\nno baseline yet - run with --update-baseline');
    exit(1);
  }
  final failures = compareToBaseline(
      scores,
      (json.decode(baselineFile.readAsStringSync()) as Map)
          .cast<String, Object?>());
  if (failures.isEmpty) {
    stdout.writeln('\nno regression against ${baselineFile.path}');
    return;
  }
  stderr.writeln('\nREGRESSION vs ${baselineFile.path}:');
  for (final failure in failures) {
    stderr.writeln('  $failure');
  }
  exit(1);
}

/// Scores every document in [corpusPath] (optionally just [only]).
List<ReflowScore> runReflowEval(String corpusPath, {String? only}) {
  final directory = Directory(corpusPath);
  final truthFiles = directory
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.truth.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final scores = <ReflowScore>[];
  for (final file in truthFiles) {
    final truth = ReflowTruth.fromJson(
        (json.decode(file.readAsStringSync()) as Map).cast<String, Object?>());
    if (only != null && truth.name != only) continue;
    final pdf = File('$corpusPath/${truth.name}.pdf');
    if (!pdf.existsSync()) {
      stderr.writeln('missing ${pdf.path} - regenerate the corpus');
      continue;
    }
    final document = PdfDocument.open(pdf.readAsBytesSync());
    scores.add(scoreReflow(truth, predictReflow(document, truth.pageCount)));
  }
  return scores;
}

/// Runs the shipping reading-view pipeline over [document] and flattens it to
/// the neutral blocks the scorer takes.
///
/// The heading verdict is reproduced here from the *view's* rule
/// (`_styleFor` in pdf_reflow_view.dart: a block whose font size is at least
/// 1.3x the page median renders as a title). That rule lives in the widget,
/// not in [PdfReflowBlock], so scoring it means restating it - which is
/// itself the finding that the model carries no role at all.
List<ReflowPredictedBlock> predictReflow(PdfDocument document, int pageCount) {
  final out = <ReflowPredictedBlock>[];
  for (var page = 0; page < pageCount; page++) {
    final reflowed = PdfTextExtractor.reflowPage(document, page);
    final median = _median([for (final b in reflowed.blocks) b.fontSize]);
    for (final item in reflowed.items) {
      switch (item) {
        case final PdfReflowBlock block:
          out.add(ReflowPredictedBlock(
            pageIndex: page,
            text: block.text,
            bounds: block.bounds,
            isListItem: block.isListItem,
            isHeading: median > 0 && block.fontSize >= median * 1.3,
          ));
        case final PdfReflowImage image:
          out.add(ReflowPredictedBlock(
            pageIndex: page,
            text: '',
            bounds: image.bounds,
            isFigure: true,
          ));
      }
    }
  }
  return out;
}

/// Per-metric regressions of [scores] against a committed baseline.
List<String> compareToBaseline(
    List<ReflowScore> scores, Map<String, Object?> baseline) {
  final documents =
      (baseline['documents'] as Map?)?.cast<String, Object?>() ?? const {};
  final failures = <String>[];
  for (final score in scores) {
    final previous = (documents[score.name] as Map?)?.cast<String, Object?>();
    if (previous == null) {
      failures.add('${score.name}: not in baseline (re-baseline to adopt it)');
      continue;
    }
    final current = score.toJson();
    for (final metric in [...reflowMetrics, 'overall']) {
      final was = (previous[metric] as num?)?.toDouble();
      final now = (current[metric] as num?)?.toDouble();
      if (was == null || now == null) continue;
      if (now < was - tolerance) {
        failures.add('${score.name}.$metric '
            '${was.toStringAsFixed(4)} -> ${now.toStringAsFixed(4)} '
            '(-${(was - now).toStringAsFixed(4)})');
      }
    }
  }
  return failures;
}

String _table(List<ReflowScore> scores, Map<String, double> pooled) {
  const headers = [
    ('text', 'textAccuracy'),
    ('order', 'readingOrder'),
    ('segF1', 'segmentationF1'),
    ('artif', 'artifactRejection'),
    ('list', 'listF1'),
    ('head', 'headingF1'),
    ('figs', 'figureRecall'),
    ('OVERALL', 'overall'),
  ];
  final buffer = StringBuffer()
    ..write('document'.padRight(22))
    ..writeln(headers.map((h) => h.$1.padLeft(8)).join());
  buffer.writeln('-' * (22 + headers.length * 8));
  for (final score in scores) {
    final row = score.toJson();
    buffer
      ..write(score.name.padRight(22))
      ..writeln(headers
          .map((h) => (row[h.$2]! as num).toStringAsFixed(3).padLeft(8))
          .join());
  }
  buffer
    ..writeln('-' * (22 + headers.length * 8))
    ..write('pooled mean'.padRight(22))
    ..writeln(
        headers.map((h) => pooled[h.$2]!.toStringAsFixed(3).padLeft(8)).join())
    ..writeln()
    ..writeln('split rate ${pooled['splitRate']!.toStringAsFixed(3)}  '
        'merge rate ${pooled['mergeRate']!.toStringAsFixed(3)}  '
        '(diagnostics, not scored)');
  return buffer.toString();
}

double _median(List<double> values) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}
