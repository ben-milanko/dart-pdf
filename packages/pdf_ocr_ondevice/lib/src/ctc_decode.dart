import 'dart:typed_data';

/// The text decoded from a recognizer's per-timestep logits.
class CtcResult {
  const CtcResult({required this.text, required this.confidence});

  final String text;

  /// Mean probability of the kept (non-blank, non-repeat) characters, or 1.0
  /// when nothing was decoded.
  final double confidence;
}

/// Greedy CTC decoder over a fixed character [dictionary].
///
/// PP-OCR recognizers output, per timestep, a probability over a vocabulary
/// whose index 0 is the CTC blank and whose remaining indices map to
/// [dictionary] (so logits index `i` is `dictionary[i - 1]`); the final index
/// is conventionally a space. Greedy decoding takes the argmax per timestep,
/// then collapses runs of the same index and drops blanks (§ CTC).
class CtcDecoder {
  CtcDecoder(this.dictionary, {this.blankIndex = 0});

  /// Characters for vocabulary indices `1..dictionary.length` (index 0 is the
  /// blank). Build it from a PP-OCR dict file with [parseDictionary].
  final List<String> dictionary;

  /// The vocabulary index reserved for the CTC blank.
  final int blankIndex;

  /// Decodes [logits], a `timesteps` x `vocab` row-major matrix.
  CtcResult decode(Float32List logits, int timesteps, int vocab) {
    final buffer = StringBuffer();
    var prev = -1;
    var probSum = 0.0;
    var kept = 0;
    for (var t = 0; t < timesteps; t++) {
      final base = t * vocab;
      var best = 0;
      var bestVal = logits[base];
      for (var v = 1; v < vocab; v++) {
        final val = logits[base + v];
        if (val > bestVal) {
          bestVal = val;
          best = v;
        }
      }
      if (best != blankIndex && best != prev) {
        final ch = _charFor(best);
        if (ch != null) {
          buffer.write(ch);
          probSum += bestVal;
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
