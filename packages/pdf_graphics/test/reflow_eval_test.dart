// The reading-view reflow evaluation gate.
//
// Three jobs, in order of what they protect:
//
//  1. The corpus is honest. For every generated document the ground truth
//     must describe the bytes exactly - same page count, same words, nothing
//     drawn off the page, no two runs of text on top of each other. If this
//     fails, every score below it is measuring a broken fixture instead of
//     the pipeline.
//  2. The scorer is right. The metrics are checked against hand-built inputs
//     with known answers, so a metric can't quietly start flattering us.
//  3. The pipeline has not regressed. Scores are compared with the committed
//     baseline (tool/reflow/baseline.json); a drop fails, a rise does not.
//     Re-baseline deliberately:
//       cd packages/pdf_graphics
//       fvm dart run tool/reflow_eval.dart --update-baseline
//     and review the diff the way a perf baseline update is reviewed.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:test/test.dart';

import '../tool/reflow/scoring.dart';
import '../tool/reflow/truth.dart';
import '../tool/reflow_eval.dart';

const _corpusPath = '../../test_corpora/reflow';

List<ReflowTruth> _loadTruth() {
  final directory = Directory(_corpusPath);
  if (!directory.existsSync()) return const [];
  final files = directory
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.truth.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return [
    for (final file in files)
      ReflowTruth.fromJson(
          (json.decode(file.readAsStringSync()) as Map).cast<String, Object?>())
  ];
}

PdfRect _rect(double left, double bottom, double right, double top) =>
    PdfRect(left, bottom, right, top);

ReflowTruthBlock _truthBlock(
  String text, {
  int page = 0,
  int reading = 0,
  ReflowRole role = ReflowRole.paragraph,
}) =>
    ReflowTruthBlock(
      pageIndex: page,
      role: role,
      text: text,
      bounds: _rect(0, 0, 100, 10),
      readingIndex: role == ReflowRole.artifact ? -1 : reading,
    );

ReflowTruth _truth(List<ReflowTruthBlock> blocks, {int pages = 1}) =>
    ReflowTruth(
        name: 'unit', description: 'unit', pageCount: pages, blocks: blocks);

ReflowPredictedBlock _pred(
  String text, {
  int page = 0,
  bool list = false,
  bool heading = false,
}) =>
    ReflowPredictedBlock(
      pageIndex: page,
      text: text,
      bounds: _rect(0, 0, 100, 10),
      isListItem: list,
      isHeading: heading,
    );

void main() {
  group('the corpus truth describes the bytes', () {
    final truths = _loadTruth();

    test('the corpus exists', () {
      expect(truths, isNotEmpty,
          reason: 'run: fvm dart run tool/gen_reflow_corpus.dart');
    });

    for (final truth in truths) {
      test(truth.name, () {
        final file = File('$_corpusPath/${truth.name}.pdf');
        expect(file.existsSync(), isTrue);
        final document = PdfDocument.open(file.readAsBytesSync());
        expect(document.pageCount, truth.pageCount,
            reason: 'truth claims a different page count than the file has');

        for (var page = 0; page < document.pageCount; page++) {
          final extracted = PdfTextExtractor.extract(document, page);

          // Every word the truth claims is drawn, and no word is drawn that
          // the truth does not claim - as multisets, so a duplicated line
          // cannot hide behind a set comparison.
          final claimed = _counts([
            for (final block in truth.blocks)
              if (block.pageIndex == page) ...reflowTokens(block.text)
          ]);
          final drawn = _counts(reflowTokens(extracted.text));
          expect(drawn, claimed,
              reason: 'page $page: the truth and the content stream disagree '
                  'about what words are on the page');

          // Nothing spills outside the page box.
          final box = document.page(page).cropBox;
          for (final run in extracted.runs) {
            expect(run.bounds.left, greaterThanOrEqualTo(box.left - 1),
                reason: 'page $page: "${run.text}" runs off the left edge');
            expect(run.bounds.right, lessThanOrEqualTo(box.right + 1),
                reason: 'page $page: "${run.text}" runs off the right edge');
            expect(run.bounds.bottom, greaterThanOrEqualTo(box.bottom - 1),
                reason: 'page $page: "${run.text}" runs off the bottom');
            expect(run.bounds.top, lessThanOrEqualTo(box.top + 1),
                reason: 'page $page: "${run.text}" runs off the top');
          }

          // No two pieces of text are drawn on top of each other - a layout
          // bug in the generator would show up here and nowhere else.
          final runs = [
            for (final run in extracted.runs)
              if (run.text.trim().isNotEmpty) run
          ];
          for (var i = 0; i < runs.length; i++) {
            for (var j = i + 1; j < runs.length; j++) {
              final a = runs[i].bounds, b = runs[j].bounds;
              final overlapWidth = (a.right < b.right ? a.right : b.right) -
                  (a.left > b.left ? a.left : b.left);
              final overlapHeight = (a.top < b.top ? a.top : b.top) -
                  (a.bottom > b.bottom ? a.bottom : b.bottom);
              expect(overlapWidth > 1 && overlapHeight > 3, isFalse,
                  reason: 'page $page: "${runs[i].text}" and "${runs[j].text}" '
                      'are drawn on top of each other');
            }
          }
        }
      });
    }
  });

  group('scoring', () {
    test('a perfect prediction scores 1 across the board', () {
      final truth = _truth([
        _truthBlock('Alpha beta gamma', reading: 0, role: ReflowRole.heading),
        _truthBlock('Delta epsilon zeta eta', reading: 1),
        _truthBlock('- theta iota', reading: 2, role: ReflowRole.listItem),
        _truthBlock('Page 7', role: ReflowRole.artifact),
      ]);
      final score = scoreReflow(truth, [
        _pred('Alpha beta gamma', heading: true),
        _pred('Delta epsilon zeta eta'),
        _pred('- theta iota', list: true),
      ]);
      expect(score.textAccuracy, 1);
      expect(score.readingOrder, 1);
      expect(score.segmentationF1, 1);
      expect(score.artifactRejection, 1);
      expect(score.listF1, 1);
      expect(score.headingF1, 1);
      expect(score.figureRecall, 1);
      expect(score.overall, 1);
    });

    test('a leaked running head costs artifactRejection, nothing else', () {
      final truth = _truth([
        _truthBlock('Alpha beta gamma', reading: 0),
        _truthBlock('Quarterly report', role: ReflowRole.artifact),
      ]);
      final score = scoreReflow(truth, [
        _pred('Quarterly report'),
        _pred('Alpha beta gamma'),
      ]);
      expect(score.artifactRejection, 0);
      expect(score.textAccuracy, lessThan(1),
          reason: 'the leaked words are extra words in the stream');
      expect(score.segmentationF1, closeTo(2 / 3, 1e-9),
          reason: 'one of two predictions matched one of one truth blocks');
    });

    test('swapped blocks cost readingOrder but not text', () {
      final truth = _truth([
        _truthBlock('alpha alpha alpha', reading: 0),
        _truthBlock('beta beta beta', reading: 1),
        _truthBlock('gamma gamma gamma', reading: 2),
      ]);
      final reversed = scoreReflow(truth, [
        _pred('gamma gamma gamma'),
        _pred('beta beta beta'),
        _pred('alpha alpha alpha'),
      ]);
      expect(reversed.readingOrder, 0, reason: 'every pair is inverted');
      expect(reversed.segmentationF1, 1,
          reason: 'the blocks themselves are right');

      final oneSwap = scoreReflow(truth, [
        _pred('beta beta beta'),
        _pred('alpha alpha alpha'),
        _pred('gamma gamma gamma'),
      ]);
      expect(oneSwap.readingOrder, closeTo(1 - 1 / 3, 1e-9));
    });

    test('merging two paragraphs shows up as merge rate and segmentation', () {
      final truth = _truth([
        _truthBlock('alpha alpha alpha', reading: 0),
        _truthBlock('beta beta beta', reading: 1),
      ]);
      final score =
          scoreReflow(truth, [_pred('alpha alpha alpha beta beta beta')]);
      expect(score.textAccuracy, 1, reason: 'no word was lost');
      expect(score.mergeRate, 1);
      expect(score.segmentationF1, lessThan(1));
    });

    test('dropped words cost textAccuracy in proportion', () {
      final truth = _truth([_truthBlock('one two three four', reading: 0)]);
      final score = scoreReflow(truth, [_pred('one two')]);
      expect(score.textAccuracy, closeTo(0.5, 1e-9));
    });

    test('a figure counts as recalled only where it belongs', () {
      final truth = ReflowTruth(
        name: 'unit',
        description: 'unit',
        pageCount: 1,
        blocks: [
          ReflowTruthBlock(
            pageIndex: 0,
            role: ReflowRole.figure,
            text: '',
            bounds: _rect(100, 100, 200, 200),
            readingIndex: 0,
          ),
        ],
      );
      const onSpot = ReflowPredictedBlock(
          pageIndex: 0,
          text: '',
          bounds: PdfRect(105, 105, 195, 195),
          isFigure: true);
      const elsewhere = ReflowPredictedBlock(
          pageIndex: 0,
          text: '',
          bounds: PdfRect(400, 400, 500, 500),
          isFigure: true);
      expect(scoreReflow(truth, [onSpot]).figureRecall, 1);
      expect(scoreReflow(truth, [elsewhere]).figureRecall, 0);
      expect(scoreReflow(truth, const []).figureRecall, 0);
    });

    test('tokens ignore punctuation, case, and hyphenation repair', () {
      expect(reflowTokens('Hello, World!'), ['hello', 'world']);
      expect(reflowTokens('co­operate'), ['cooperate']);
      expect(reflowTokens('“quoted”'), ['quoted']);
    });
  });

  group('no regression against the committed baseline', () {
    test('every metric holds', () {
      final baselineFile = File('tool/reflow/baseline.json');
      expect(baselineFile.existsSync(), isTrue,
          reason: 'run: fvm dart run tool/reflow_eval.dart --update-baseline');
      final scores = runReflowEval(_corpusPath);
      expect(scores, isNotEmpty);
      final failures = compareToBaseline(
          scores,
          (json.decode(baselineFile.readAsStringSync()) as Map)
              .cast<String, Object?>());
      expect(failures, isEmpty,
          reason: 'reading-view reflow regressed:\n  ${failures.join('\n  ')}');
    });
  });
}

Map<String, int> _counts(Iterable<String> tokens) {
  final out = <String, int>{};
  for (final token in tokens) {
    out[token] = (out[token] ?? 0) + 1;
  }
  return out;
}
