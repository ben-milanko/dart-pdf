import 'package:crypto/crypto.dart';
import 'package:pdf_cos/src/filters/ccitt.dart';

import '../test/ccitt_corpus.dart';

/// Re-baselines the digests in `test/ccitt_golden_test.dart`.
///
/// Only run this for an intended behaviour change: the checked-in digests
/// were captured from the decoder as it stood before the hot-loop rewrite,
/// and their whole job is to fail when output moves. Paste the output over
/// the `_goldens` map.
void main() {
  for (final entry in allCorpora().entries) {
    final accumulator = <int>[];
    var totalBytes = 0;
    for (final testCase in entry.value) {
      final out = CcittDecoder(
        data: testCase.data,
        k: testCase.k,
        columns: testCase.columns,
        rows: testCase.rows,
        blackIs1: testCase.blackIs1,
        byteAlign: testCase.byteAlign,
      ).decode();
      accumulator
        ..add(out.length & 0xFF)
        ..add((out.length >> 8) & 0xFF)
        ..addAll(out);
      totalBytes += out.length;
    }
    // ignore: avoid_print
    print("  '${entry.key}': (\n"
        "    cases: ${entry.value.length},\n"
        "    bytes: $totalBytes,\n"
        "    digest: '${sha256.convert(accumulator)}',\n"
        '  ),');
  }
}
