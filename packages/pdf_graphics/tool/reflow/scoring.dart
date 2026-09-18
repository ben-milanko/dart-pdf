// Scoring for the reading-view reflow evaluation.
//
// Deliberately engine-agnostic: it takes plain [ReflowPredictedBlock]s, not
// `PdfReflowPage`, so the metrics unit-test against hand-written inputs and
// so a future structure-tree or layout-model path scores on exactly the same
// ruler as today's geometric one.
//
// Six text metrics plus figure recall, each in [0, 1] and each answering one
// question a reader would ask:
//
//   textAccuracy      did the words survive?            (1 - word error rate)
//   readingOrder      are they in the right order?      (1 - inversion rate)
//   segmentationF1    are the paragraph edges right?    (block match F1)
//   artifactRejection did running heads stay out?       (1 - leak rate)
//   listF1            were lists recognised as lists?
//   headingF1         were headings recognised as headings?
//   figureRecall      did figures survive, in place?
//
// They are reported separately because they fail separately: a pipeline can
// score 1.0 on words and 0.4 on order (a column-detection bug), and a single
// blended number would hide exactly the thing worth knowing.
library;

import 'dart:math' as math;

import 'package:pdf_document/pdf_document.dart';

import 'truth.dart';

/// One block a reflow engine produced, reduced to what scoring needs.
class ReflowPredictedBlock {
  const ReflowPredictedBlock({
    required this.pageIndex,
    required this.text,
    required this.bounds,
    this.isListItem = false,
    this.isHeading = false,
    this.isFigure = false,
  });

  final int pageIndex;
  final String text;
  final PdfRect bounds;
  final bool isListItem;

  /// Whether the engine (or the view rendering it) treats this as a heading.
  /// Today that decision lives in the *view* - a font-size ratio - so the
  /// caller reproduces the shipped rule and passes the verdict in. That the
  /// model itself has no heading concept is a finding, not an oversight.
  final bool isHeading;

  final bool isFigure;
}

/// Per-document metric bundle. Every field is in [0, 1], higher is better.
class ReflowScore {
  const ReflowScore({
    required this.name,
    required this.textAccuracy,
    required this.readingOrder,
    required this.segmentationF1,
    required this.artifactRejection,
    required this.listF1,
    required this.headingF1,
    required this.figureRecall,
    required this.splitRate,
    required this.mergeRate,
    required this.truthBlocks,
    required this.predictedBlocks,
  });

  final String name;

  /// 1 - word error rate of the reading-order text stream, per page.
  final double textAccuracy;

  /// 1 - normalized inversion count over blocks matched to truth.
  final double readingOrder;

  /// F1 of predicted blocks against truth blocks, matched at Jaccard >= 0.5.
  final double segmentationF1;

  /// 1 - the share of running-head/foot/page-number words that leaked into
  /// the reading stream.
  final double artifactRejection;

  final double listF1;
  final double headingF1;

  /// Share of truth figures that surfaced as a figure near the right place.
  final double figureRecall;

  /// Diagnostics (lower is better, not part of [overall]): truth blocks torn
  /// across several predictions, and predictions that swallowed several truth
  /// blocks.
  final double splitRate;
  final double mergeRate;

  final int truthBlocks;
  final int predictedBlocks;

  /// Unweighted mean of the seven headline metrics - a single number for
  /// trend lines and the regression gate. Read the components, not this.
  double get overall =>
      (textAccuracy +
          readingOrder +
          segmentationF1 +
          artifactRejection +
          listF1 +
          headingF1 +
          figureRecall) /
      7;

  Map<String, Object?> toJson() => {
        'name': name,
        'textAccuracy': _round(textAccuracy),
        'readingOrder': _round(readingOrder),
        'segmentationF1': _round(segmentationF1),
        'artifactRejection': _round(artifactRejection),
        'listF1': _round(listF1),
        'headingF1': _round(headingF1),
        'figureRecall': _round(figureRecall),
        'splitRate': _round(splitRate),
        'mergeRate': _round(mergeRate),
        'overall': _round(overall),
        'truthBlocks': truthBlocks,
        'predictedBlocks': predictedBlocks,
      };

  static double _round(double v) => roundReflowMetric(v);
}

/// The metric names that make up [ReflowScore.overall], in report order.
const reflowMetrics = <String>[
  'textAccuracy',
  'readingOrder',
  'segmentationF1',
  'artifactRejection',
  'listF1',
  'headingF1',
  'figureRecall',
];

/// Splits [text] into comparison tokens: lowercase alphanumeric runs, with
/// the punctuation, quote style, and whitespace that no reader cares about
/// thrown away. Soft hyphens and the hyphen of a line-broken word are
/// stripped so a pipeline is not punished for repairing (or not repairing)
/// hyphenation in a way this scorer has an opinion about - that is what
/// [ReflowTruthBlock.text] settles instead.
List<String> reflowTokens(String text) {
  final cleaned = text
      .replaceAll('­', '')
      .replaceAll(RegExp(r'[‘’‚‛]'), "'")
      .replaceAll(RegExp(r'[“”„]'), '"')
      .replaceAll(RegExp(r'[‐-―]'), '-')
      .toLowerCase();
  return [
    for (final match in RegExp(r"[a-z0-9]+(?:'[a-z]+)?").allMatches(cleaned))
      match.group(0)!
  ];
}

/// Scores one document's [predictions] against its [truth].
ReflowScore scoreReflow(
    ReflowTruth truth, List<ReflowPredictedBlock> predictions) {
  final truthBlocks = truth.readableBlocks;
  final textPredictions = [
    for (final p in predictions)
      if (!p.isFigure) p
  ];

  final truthTokens = [for (final b in truthBlocks) reflowTokens(b.text)];
  final predTokens = [for (final p in textPredictions) reflowTokens(p.text)];

  final matches = _match(truthTokens, predTokens);

  return ReflowScore(
    name: truth.name,
    textAccuracy: _textAccuracy(truth, truthBlocks, textPredictions),
    readingOrder: _readingOrder(truthBlocks, textPredictions, matches),
    segmentationF1: _segmentationF1(truthBlocks, textPredictions, matches),
    artifactRejection: _artifactRejection(truth, textPredictions),
    listF1: _flagF1(truthBlocks, textPredictions, matches,
        truthHas: (b) => b.role == ReflowRole.listItem,
        predHas: (p) => p.isListItem),
    headingF1: _flagF1(truthBlocks, textPredictions, matches,
        truthHas: (b) => b.role == ReflowRole.heading,
        predHas: (p) => p.isHeading),
    figureRecall: _figureRecall(truth, predictions),
    splitRate: _splitRate(truthTokens, predTokens),
    mergeRate: _mergeRate(truthTokens, predTokens),
    truthBlocks: truthBlocks.length,
    predictedBlocks: textPredictions.length,
  );
}

/// A one-to-one assignment between truth block indices and prediction
/// indices, plus the loose best-truth-for-each-prediction map that reading
/// order needs (order is judged on every prediction that clearly belongs
/// somewhere, not only on the ones whose edges are also right).
class _Matching {
  _Matching(this.pairs, this.bestTruthForPrediction);

  /// Mutually exclusive (truthIndex, predIndex) pairs at Jaccard >= 0.5.
  final List<(int, int)> pairs;

  /// predIndex -> truthIndex, for any prediction sharing at least half of the
  /// smaller token bag with some truth block. Not one-to-one.
  final Map<int, int> bestTruthForPrediction;
}

_Matching _match(List<List<String>> truth, List<List<String>> pred) {
  final candidates = <(double score, int t, int p)>[];
  final best = <int, int>{};
  final bestScore = <int, double>{};

  for (var p = 0; p < pred.length; p++) {
    for (var t = 0; t < truth.length; t++) {
      final shared = _intersectionSize(truth[t], pred[p]);
      if (shared == 0) continue;
      final union = truth[t].length + pred[p].length - shared;
      final jaccard = union == 0 ? 0.0 : shared / union;
      if (jaccard >= 0.5) candidates.add((jaccard, t, p));
      // Containment, not Jaccard: a prediction that merged three paragraphs
      // still *belongs* to the first of them for ordering purposes.
      final smaller = math.min(truth[t].length, pred[p].length);
      final containment = smaller == 0 ? 0.0 : shared / smaller;
      if (containment >= 0.5 && containment > (bestScore[p] ?? 0)) {
        bestScore[p] = containment;
        best[p] = t;
      }
    }
  }

  candidates.sort((a, b) => b.$1.compareTo(a.$1));
  final usedTruth = <int>{};
  final usedPred = <int>{};
  final pairs = <(int, int)>[];
  for (final (_, t, p) in candidates) {
    if (usedTruth.contains(t) || usedPred.contains(p)) continue;
    usedTruth.add(t);
    usedPred.add(p);
    pairs.add((t, p));
  }
  return _Matching(pairs, best);
}

int _intersectionSize(List<String> a, List<String> b) {
  final counts = <String, int>{};
  for (final token in a) {
    counts[token] = (counts[token] ?? 0) + 1;
  }
  var shared = 0;
  for (final token in b) {
    final left = counts[token] ?? 0;
    if (left > 0) {
      counts[token] = left - 1;
      shared++;
    }
  }
  return shared;
}

/// Word error rate of the reading stream, computed per page and pooled by
/// truth length. Per page because a Levenshtein over a whole 40-page document
/// is quadratic for no extra signal - cross-page order is [_readingOrder]'s
/// job, not this one's.
double _textAccuracy(ReflowTruth truth, List<ReflowTruthBlock> truthBlocks,
    List<ReflowPredictedBlock> predictions) {
  var totalRef = 0, totalErrors = 0;
  for (var page = 0; page < truth.pageCount; page++) {
    final reference = <String>[
      for (final b in truthBlocks)
        if (b.pageIndex == page) ...reflowTokens(b.text)
    ];
    final hypothesis = <String>[
      for (final p in predictions)
        if (p.pageIndex == page) ...reflowTokens(p.text)
    ];
    if (reference.isEmpty && hypothesis.isEmpty) continue;
    totalRef += reference.length;
    totalErrors += _levenshtein(reference, hypothesis);
  }
  if (totalRef == 0) return 1;
  return (1 - totalErrors / totalRef).clamp(0.0, 1.0);
}

int _levenshtein(List<String> a, List<String> b) {
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var previous = List<int>.generate(b.length + 1, (i) => i);
  final current = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    current[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      current[j] = math.min(
        math.min(current[j - 1] + 1, previous[j] + 1),
        previous[j - 1] + cost,
      );
    }
    previous = List<int>.from(current);
  }
  return previous[b.length];
}

/// 1 - the share of block pairs the engine put in the wrong relative order.
double _readingOrder(List<ReflowTruthBlock> truthBlocks,
    List<ReflowPredictedBlock> predictions, _Matching matching) {
  final sequence = <int>[];
  for (var p = 0; p < predictions.length; p++) {
    final t = matching.bestTruthForPrediction[p];
    if (t != null) sequence.add(truthBlocks[t].readingIndex);
  }
  if (sequence.length < 2) return 1;
  final inversions = _countInversions(sequence);
  final worst = sequence.length * (sequence.length - 1) / 2;
  return (1 - inversions / worst).clamp(0.0, 1.0);
}

/// Merge-sort inversion count: pairs (i < j) whose values run backwards.
int _countInversions(List<int> values) {
  final buffer = List<int>.filled(values.length, 0);
  final work = List<int>.from(values);

  int sort(int lo, int hi) {
    if (hi - lo < 2) return 0;
    final mid = (lo + hi) ~/ 2;
    var count = sort(lo, mid) + sort(mid, hi);
    var i = lo, j = mid, k = lo;
    while (i < mid && j < hi) {
      if (work[i] <= work[j]) {
        buffer[k++] = work[i++];
      } else {
        count += mid - i;
        buffer[k++] = work[j++];
      }
    }
    while (i < mid) {
      buffer[k++] = work[i++];
    }
    while (j < hi) {
      buffer[k++] = work[j++];
    }
    for (var x = lo; x < hi; x++) {
      work[x] = buffer[x];
    }
    return count;
  }

  return sort(0, values.length);
}

double _segmentationF1(List<ReflowTruthBlock> truthBlocks,
    List<ReflowPredictedBlock> predictions, _Matching matching) {
  if (truthBlocks.isEmpty && predictions.isEmpty) return 1;
  if (truthBlocks.isEmpty || predictions.isEmpty) return 0;
  final hits = matching.pairs.length;
  final precision = hits / predictions.length;
  final recall = hits / truthBlocks.length;
  if (precision + recall == 0) return 0;
  return 2 * precision * recall / (precision + recall);
}

/// How well running heads, running feet, and page numbers were kept out of
/// the reading stream. Scored per page, because a page number that leaks is
/// only a leak on the page it was drawn on.
double _artifactRejection(
    ReflowTruth truth, List<ReflowPredictedBlock> predictions) {
  final artifacts = truth.artifacts;
  if (artifacts.isEmpty) return 1;
  var total = 0, leaked = 0;
  for (var page = 0; page < truth.pageCount; page++) {
    final artifactTokens = <String>[
      for (final a in artifacts)
        if (a.pageIndex == page) ...reflowTokens(a.text)
    ];
    if (artifactTokens.isEmpty) continue;
    final predTokens = <String>[
      for (final p in predictions)
        if (p.pageIndex == page) ...reflowTokens(p.text)
    ];
    total += artifactTokens.length;
    leaked += _intersectionSize(artifactTokens, predTokens);
  }
  if (total == 0) return 1;
  return (1 - leaked / total).clamp(0.0, 1.0);
}

double _flagF1(
  List<ReflowTruthBlock> truthBlocks,
  List<ReflowPredictedBlock> predictions,
  _Matching matching, {
  required bool Function(ReflowTruthBlock) truthHas,
  required bool Function(ReflowPredictedBlock) predHas,
}) {
  final expected = truthBlocks.where(truthHas).length;
  final claimed = predictions.where(predHas).length;
  if (expected == 0 && claimed == 0) return 1;
  var correct = 0;
  for (final (t, p) in matching.pairs) {
    if (truthHas(truthBlocks[t]) && predHas(predictions[p])) correct++;
  }
  if (expected == 0 || claimed == 0) return 0;
  final precision = correct / claimed;
  final recall = correct / expected;
  if (precision + recall == 0) return 0;
  return 2 * precision * recall / (precision + recall);
}

/// A truth figure counts as recalled when some predicted figure overlaps it
/// by at least half of the smaller box - the reading view places figures by
/// their page geometry, so this is the honest test of "it is still there, and
/// still where it belongs".
double _figureRecall(
    ReflowTruth truth, List<ReflowPredictedBlock> predictions) {
  final figures = truth.figures;
  if (figures.isEmpty) return 1;
  final predicted = [
    for (final p in predictions)
      if (p.isFigure) p
  ];
  var found = 0;
  final used = <int>{};
  for (final figure in figures) {
    for (var i = 0; i < predicted.length; i++) {
      if (used.contains(i)) continue;
      final p = predicted[i];
      if (p.pageIndex != figure.pageIndex) continue;
      if (_overlapRatio(figure.bounds, p.bounds) < 0.5) continue;
      used.add(i);
      found++;
      break;
    }
  }
  return found / figures.length;
}

double _overlapRatio(PdfRect a, PdfRect b) {
  final w = math.min(a.right, b.right) - math.max(a.left, b.left);
  final h = math.min(a.top, b.top) - math.max(a.bottom, b.bottom);
  if (w <= 0 || h <= 0) return 0;
  final smaller = math.min(a.width * a.height, b.width * b.height);
  if (smaller <= 0) return 0;
  return w * h / smaller;
}

/// Share of truth blocks whose words landed in two or more predictions, each
/// carrying a real piece (>= 25%) of it - a paragraph torn in half.
double _splitRate(List<List<String>> truth, List<List<String>> pred) {
  if (truth.isEmpty) return 0;
  var split = 0;
  for (final tokens in truth) {
    if (tokens.isEmpty) continue;
    var carriers = 0;
    for (final p in pred) {
      if (_intersectionSize(tokens, p) >= tokens.length * 0.25) carriers++;
    }
    if (carriers > 1) split++;
  }
  return split / truth.length;
}

/// Share of predictions that swallowed a real piece of two or more truth
/// blocks - two paragraphs run together.
double _mergeRate(List<List<String>> truth, List<List<String>> pred) {
  if (pred.isEmpty) return 0;
  var merged = 0;
  for (final tokens in pred) {
    if (tokens.isEmpty) continue;
    var sources = 0;
    for (final t in truth) {
      if (t.isEmpty) continue;
      if (_intersectionSize(t, tokens) >= t.length * 0.25) sources++;
    }
    if (sources > 1) merged++;
  }
  return merged / pred.length;
}

/// Pools per-document scores into a corpus-level bundle (plain means - every
/// document counts once, so a 40-page report cannot drown out the one-page
/// table case it was cheap to get right).
Map<String, double> poolReflowScores(List<ReflowScore> scores) {
  if (scores.isEmpty) return {for (final m in reflowMetrics) m: 0.0};
  double mean(double Function(ReflowScore) pick) =>
      scores.map(pick).reduce((a, b) => a + b) / scores.length;
  return {
    'textAccuracy': mean((s) => s.textAccuracy),
    'readingOrder': mean((s) => s.readingOrder),
    'segmentationF1': mean((s) => s.segmentationF1),
    'artifactRejection': mean((s) => s.artifactRejection),
    'listF1': mean((s) => s.listF1),
    'headingF1': mean((s) => s.headingF1),
    'figureRecall': mean((s) => s.figureRecall),
    'splitRate': mean((s) => s.splitRate),
    'mergeRate': mean((s) => s.mergeRate),
    'overall': mean((s) => s.overall),
  };
}

/// Rounds a metric for reporting: four decimals is finer than any real
/// pipeline change and coarse enough that a committed baseline diff stays
/// readable.
double roundReflowMetric(double v) => (v * 10000).round() / 10000;
