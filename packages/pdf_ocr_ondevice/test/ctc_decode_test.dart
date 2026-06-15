import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_ocr_ondevice/pdf_ocr_ondevice.dart';

/// Builds a [timesteps] x [vocab] logit matrix that is argmax-`indices[t]` at
/// each step (the winning class gets 0.9, the rest 0.1/(vocab-1)).
Float32List _logitsFrom(List<int> indices, int vocab) {
  final out = Float32List(indices.length * vocab);
  for (var t = 0; t < indices.length; t++) {
    for (var v = 0; v < vocab; v++) {
      out[t * vocab + v] = v == indices[t] ? 0.9 : 0.1 / (vocab - 1);
    }
  }
  return out;
}

void main() {
  // dictionary index 0 -> 'a', 1 -> 'b', 2 -> 'c'; vocab index 0 is blank, so
  // vocab 1 -> 'a', 2 -> 'b', 3 -> 'c', 4 -> ' ' (the appended space).
  final decoder = CtcDecoder(['a', 'b', 'c', ' ']);
  const vocab = 5;

  test('collapses repeats and drops blanks', () {
    // a a <blank> b -> "ab"
    final logits = _logitsFrom([1, 1, 0, 2], vocab);
    final result = decoder.decode(logits, 4, vocab);
    expect(result.text, 'ab');
    expect(result.confidence, closeTo(0.9, 1e-6));
  });

  test('a blank between identical chars keeps both', () {
    // a <blank> a -> "aa"
    final logits = _logitsFrom([1, 0, 1], vocab);
    expect(decoder.decode(logits, 3, vocab).text, 'aa');
  });

  test('an all-blank sequence decodes to empty with full confidence', () {
    final logits = _logitsFrom([0, 0, 0], vocab);
    final r = decoder.decode(logits, 3, vocab);
    expect(r.text, isEmpty);
    expect(r.confidence, 1.0);
  });

  test('raw logits without softmax overstate confidence (clamp to 1.0)', () {
    // A confident-looking logit row [.., 8.0, ..] taken as a probability is
    // clamped to 1.0 — the bug applySoftmax fixes.
    final raw = CtcDecoder(['a', 'b', 'c', ' ']);
    final logits = Float32List(vocab)..[1] = 8.0; // argmax 'a', logit 8
    expect(raw.decode(logits, 1, vocab).confidence, 1.0);
  });

  test('applySoftmax turns logits into a real probability', () {
    final soft = CtcDecoder(['a', 'b', 'c', ' '], applySoftmax: true);
    // 'a' wins with logit 2.0 over four 0.0s: softmax = e^2/(e^2+4) ≈ 0.649.
    final logits = Float32List(vocab)..[1] = 2.0;
    final r = soft.decode(logits, 1, vocab);
    expect(r.text, 'a');
    expect(r.confidence, closeTo(0.649, 0.005));
    expect(r.confidence, lessThan(1.0)); // minConfidence is now meaningful
  });

  test('softmax of an unambiguous row approaches 1', () {
    final soft = CtcDecoder(['a', 'b', 'c', ' '], applySoftmax: true);
    final logits = Float32List(vocab)..[2] = 20.0; // 'b' dominates
    expect(soft.decode(logits, 1, vocab).confidence, closeTo(1.0, 1e-3));
  });

  test('parseDictionary keeps order and appends a space token', () {
    final dict = parseDictionary('a\nb\nc\n');
    expect(dict, ['a', 'b', 'c', ' ']);
  });

  test('parseDictionary strips a trailing carriage return', () {
    final dict = parseDictionary('x\r\ny\r\n', addSpace: false);
    expect(dict, ['x', 'y']);
  });
}
