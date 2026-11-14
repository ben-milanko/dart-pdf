import 'dart:io';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:test/test.dart';

/// Holds `RunLengthFilter` to the formally verified model of RunLengthDecode
/// in `tool/lean/runlength/`.
///
/// The model's decoder is proved in Lean to equal the §7.4.5 specification
/// (including this codebase's leniency on truncated input) for every input.
/// That proof is about the model, not about the Dart; this test is the
/// bridge. `test/data/run_length_lean_vectors.txt` is the model's output on a
/// fixed set of edge cases plus generated inputs - `input output`, hex, `-`
/// for no bytes - regenerated and compared by `tool/lean/runlength/check.sh`.
void main() {
  Uint8List bytes(String hex) {
    if (hex == '-') return Uint8List(0);
    return Uint8List.fromList([
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);
  }

  final lines = File('test/data/run_length_lean_vectors.txt')
      .readAsLinesSync()
      .where((line) => line.isNotEmpty)
      .toList();

  test('RunLengthDecode matches the verified model on every vector', () {
    expect(lines.length, greaterThan(500));
    const filter = RunLengthFilter();
    for (final line in lines) {
      final [input, output] = line.split(' ');
      expect(filter.decode(bytes(input), null), bytes(output),
          reason: 'input $input');
    }
  });

  test('the vectors respect the proven 128x output bound', () {
    for (final line in lines) {
      final [input, output] = line.split(' ');
      expect(bytes(output).length, lessThanOrEqualTo(128 * bytes(input).length),
          reason: 'input $input');
    }
  });
}
