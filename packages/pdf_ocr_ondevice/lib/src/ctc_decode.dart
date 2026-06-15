import 'dart:math' as math;
import 'dart:typed_data';

/// The text decoded from a recognizer's per-timestep scores.
class CtcResult {
  const CtcResult({required this.text, required this.confidence});

  final String text;

  /// Mean probability in `[0, 1]` of the kept (non-blank, non-repeat)
  /// characters, or 1.0 when nothing was decoded.
  final double confidence;
}

/// Greedy CTC decoder over a fixed character [dictionary].
///
/// PP-OCR recognizers output, per timestep, a score over a vocabulary whose
/// index 0 is the CTC blank and whose remaining indices map to [dictionary]
/// (so score index `i` is `dictionary[i - 1]`); the final index is
/// conventionally a space. Greedy decoding takes the argmax per timestep, then
/// collapses runs of the same index and drops blanks (§ CTC).
///
/// **Confidence depends on what the model emits.** PaddleOCR's recognition
/// *inference* model ends in a softmax, so its per-step scores are already
/// probabilities and the kept character's value is its probability directly
/// (this mirrors PaddleOCR's own `CTCLabelDecode`, which reads the per-step
/// max as the confidence) — that is [applySoftmax] `false`, the default. If a
/// model emits raw **logits** instead, set [applySoftmax] true so each step is
/// softmaxed before its probability is read; otherwise an unbounded logit
/// would clamp the reported confidence to 1.0 and defeat any min-confidence
/// filter. The decoded text is identical either way (argmax is invariant under
/// softmax) — only the confidence differs.
class CtcDecoder {
  CtcDecoder(this.dictionary, {this.blankIndex = 0, this.applySoftmax = false});

  /// Characters for vocabulary indices `1..dictionary.length` (index 0 is the
  /// blank). Build it from a PP-OCR dict file with [parseDictionary].
  final List<String> dictionary;

  /// The vocabulary index reserved for the CTC blank.
  final int blankIndex;

  /// Whether to softmax each timestep before reading the winning class's
  /// probability — set this when the model emits raw logits rather than
  /// softmax probabilities.
  final bool applySoftmax;

  /// Decodes [predictions], a `timesteps` x `vocab` row-major matrix of the
  /// recognizer's per-step scores (probabilities, or logits when
  /// [applySoftmax]).
  CtcResult decode(Float32List predictions, int timesteps, int vocab) {
    final buffer = StringBuffer();
    var prev = -1;
    var probSum = 0.0;
    var kept = 0;
    for (var t = 0; t < timesteps; t++) {
      final base = t * vocab;
      var best = 0;
      var bestVal = predictions[base];
      for (var v = 1; v < vocab; v++) {
        final val = predictions[base + v];
        if (val > bestVal) {
          bestVal = val;
          best = v;
        }
      }
      if (best != blankIndex && best != prev) {
        final ch = _charFor(best);
        if (ch != null) {
          buffer.write(ch);
          probSum += _probability(predictions, base, vocab, bestVal);
          kept++;
        }
      }
      prev = best;
    }
    return CtcResult(
      text: buffer.toString(),
      confidence: kept > 0 ? (probSum / kept).clamp(0.0, 1.0) : 1.0,
    );
  }

  /// The probability of the winning class at timestep row [base] whose score
  /// is [bestVal]: the raw score when the model already emits probabilities,
  /// or the softmax of the row (numerically stable) when [applySoftmax].
  double _probability(Float32List predictions, int base, int vocab,
      double bestVal) {
    if (!applySoftmax) return bestVal;
    var sum = 0.0;
    for (var v = 0; v < vocab; v++) {
      sum += math.exp(predictions[base + v] - bestVal);
    }
    // exp(bestVal - bestVal) / sum == 1 / sum.
    return sum > 0 ? 1.0 / sum : 0.0;
  }

  String? _charFor(int index) {
    // Vocab index `i` (i >= 1) maps to dictionary[i - 1].
    final di = index - 1;
    if (di < 0 || di >= dictionary.length) return null;
    return dictionary[di];
  }
}

/// Parses a PP-OCR character dictionary file: one token per line, blank lines
/// preserved as a single space (some dicts encode the space as an empty
/// line). A trailing space token is appended when the file does not already
/// end with one, matching PP-OCR's `use_space_char` default.
List<String> parseDictionary(String contents, {bool addSpace = true}) {
  final lines = contents.split('\n');
  // Drop a single trailing empty line from the final newline.
  if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
  final out = [
    for (final line in lines) line.endsWith('\r') ? line.substring(0, line.length - 1) : line,
  ];
  if (addSpace && (out.isEmpty || out.last != ' ')) out.add(' ');
  return out;
}
