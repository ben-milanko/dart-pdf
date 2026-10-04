import 'dart:math' as math;

import 'ocr_drawing_sheet.dart';

/// One recognized span to score, in the same user space as the truth.
typedef OcrScoredSpan = ({
  String text,
  double left,
  double bottom,
  double right,
  double top,
});

/// The score of one OCR run against a truth set.
class OcrAccuracy {
  OcrAccuracy._(this.labels, this.exact, this.missed, this.edits, this.chars,
      this.extras, this.misreads);

  /// Truth labels scored.
  final int labels;

  /// Labels read exactly (after whitespace normalisation).
  final int exact;

  /// Labels no span overlapped at all.
  final int missed;

  /// Summed edit distance over every label (a missed label costs its length).
  final int edits;

  /// Summed truth length.
  final int chars;

  /// Spans that overlapped no truth label (hallucinations or unlabelled ink).
  final int extras;

  /// `(truth, read)` for every label not read exactly, for eyeballing.
  final List<(String, String)> misreads;

  /// Character error rate over every label.
  double get cer => chars == 0 ? 0 : edits / chars;

  double get exactRate => labels == 0 ? 0 : exact / labels;

  @override
  String toString() => 'labels $labels  exact '
      '${(exactRate * 100).toStringAsFixed(1)}%  '
      'CER ${(cer * 100).toStringAsFixed(1)}%  missed $missed  extras $extras';
}

String _norm(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');

double _overlap(OcrScoredSpan s, OcrTruthLabel t) {
  final w = math.min(s.right, t.right) - math.max(s.left, t.left);
  final h = math.min(s.top, t.top) - math.max(s.bottom, t.bottom);
  return w > 0 && h > 0 ? w * h : 0;
}

/// Levenshtein distance between [a] and [b] (UTF-16 code units).
int ocrEditDistance(String a, String b) {
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final sub =
          prev[j - 1] + (a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1);
      cur[j] = math.min(sub, math.min(prev[j] + 1, cur[j - 1] + 1));
    }
    prev = cur;
  }
  return prev[b.length];
}

/// Scores [spans] against [truth]. Each span goes to the truth label it
/// overlaps most; a label's reading is its spans joined in reading order along
/// the label's long axis (so a /Rotate 90 page, whose lines run along user y,
/// scores the same as an upright one). A span that merges two labels lands on
/// one of them and leaves the other missed, so merging is penalised twice -
/// as it should be, since both labels come out wrong.
OcrAccuracy scoreOcrAccuracy(
    List<OcrTruthLabel> truth, Iterable<OcrScoredSpan> spans) {
  final assigned = List.generate(truth.length, (_) => <OcrScoredSpan>[]);
  var extras = 0;
  for (final span in spans) {
    var best = -1;
    var bestArea = 0.0;
    for (var i = 0; i < truth.length; i++) {
      final a = _overlap(span, truth[i]);
      if (a > bestArea) {
        bestArea = a;
        best = i;
      }
    }
    if (best < 0) {
      extras++;
    } else {
      assigned[best].add(span);
    }
  }
  var exact = 0, missed = 0, edits = 0, chars = 0;
  final misreads = <(String, String)>[];
  for (var i = 0; i < truth.length; i++) {
    final t = truth[i];
    final horizontal = t.right - t.left >= t.top - t.bottom;
    final parts = assigned[i]
      ..sort((a, b) =>
          horizontal ? a.left.compareTo(b.left) : a.bottom.compareTo(b.bottom));
    final read = _norm(parts.map((s) => s.text).join(' '));
    final want = _norm(t.text);
    if (parts.isEmpty) missed++;
    final d = ocrEditDistance(want, read);
    edits += d;
    chars += want.length;
    if (d == 0) {
      exact++;
    } else {
      misreads.add((want, read));
    }
  }
  return OcrAccuracy._(
      truth.length, exact, missed, edits, chars, extras, misreads);
}
