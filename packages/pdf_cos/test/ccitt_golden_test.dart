import 'package:crypto/crypto.dart';
import 'package:pdf_cos/src/filters/ccitt.dart';
import 'package:test/test.dart';

import 'ccitt_corpus.dart';

/// Byte-for-byte lock on the CCITT decoder's output across four seeded
/// corpora (`ccitt_corpus.dart`).
///
/// The digests below were captured from the decoder as it stood *before*
/// the hot-loop rewrite (monotonic b1 cursor, peek-once prefix tables,
/// byte-run span fills), so they pin the optimizations to exactly the
/// output the old bit-at-a-time implementation produced - on well-formed
/// input and, just as importantly, on malformed and truncated input, where
/// the decoder's contract is to be lenient and return whatever it managed
/// to decode rather than to be "correct".
///
/// Regenerate deliberately, and only for an intended behaviour change:
///   dart run tool/gen_ccitt_goldens.dart
const _goldens = {
  'well-formed': (
    cases: 400,
    bytes: 53348,
    digest: 'd958dde1ac90d2fe7423b656694a007f137915e72f18921181ffb954f64ad6a3',
  ),
  'malformed': (
    cases: 4000,
    bytes: 656930,
    digest: '5f28673265736e6d2e6775cdcef485f762886f33fac093c13fe146b8b5d296a5',
  ),
  'truncated': (
    cases: 400,
    bytes: 19200,
    digest: '3b6de81d656f2b125f9ed6b49b7b0932f140b232d6689ec15eabb23b865f565f',
  ),
  'span-alignment': (
    cases: 3386,
    bytes: 9726,
    digest: '961c6971ffd6259bdcd1ff4835e2bb3c432924c6da5fa26cc18acbd0d2d7d06a',
  ),
  'mode-codes': (
    cases: 1500,
    bytes: 64150,
    digest: 'e06d4522412b107a57bf1e4dd63a5ce4601e360f0c43df27d3766a9489e3ecc8',
  ),
};

void main() {
  final corpora = allCorpora();

  test('every corpus is accounted for', () {
    expect(corpora.keys, unorderedEquals(_goldens.keys));
  });

  for (final entry in corpora.entries) {
    final golden = _goldens[entry.key]!;

    test('${entry.key} corpus decodes to the pre-optimization bytes', () {
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

      // The counts are part of the golden so a corpus that silently stops
      // generating cases - or starts decoding everything to nothing - fails
      // loudly instead of passing vacuously against a matching digest.
      expect(entry.value.length, golden.cases, reason: 'corpus size drifted');
      expect(totalBytes, golden.bytes, reason: 'decoded output size drifted');
      expect('${sha256.convert(accumulator)}', golden.digest);
    });
  }
}
