import 'dart:math';
import 'dart:typed_data';

/// Deterministic CCITT input corpora shared by the golden test and the
/// baseline generator (`tool/gen_ccitt_goldens.dart`). Everything here is
/// seeded, so the same corpus is produced on every run and on every
/// platform - which is what makes the checked-in digests meaningful.

/// One decode job: the encoded bytes plus the parameters to decode with.
class CcittCase {
  const CcittCase(this.data, this.k, this.columns, this.rows,
      {this.blackIs1 = false, this.byteAlign = false});

  final Uint8List data;
  final int k;
  final int columns;
  final int rows;
  final bool blackIs1;
  final bool byteAlign;
}

// T.4 terminating and make-up codes, enough to spell 64*k + t for k <= 4
// and t in [_terms].
const _whiteCodes = {
  0: '00110101', 1: '000111', 2: '0111', 3: '1000', 4: '1011',
  5: '1100', 6: '1110', 7: '1111', 8: '10011', 9: '10100',
  10: '00111', 16: '101010', 32: '00011011', 64: '11011',
  128: '10010', 192: '010111', 256: '0110111',
};
const _blackCodes = {
  0: '0000110111', 1: '010', 2: '11', 3: '10', 4: '011', 5: '0011',
  6: '0010', 7: '00011', 8: '000101', 9: '000100', 10: '0000100',
  16: '0000010111', 32: '000001101010', 64: '0000001111',
  128: '000011001000', 192: '000011001001', 256: '000001011011',
};
const _terms = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 16, 32];

/// Run lengths the tables above can spell, ascending.
final List<int> encodableRuns = <int>{
  for (var k = 0; k <= 4; k++)
    for (final t in _terms) 64 * k + t
}.toList()
  ..sort();

/// Encodes rows of alternating run lengths (white first, summing to
/// [columns]) as G4 horizontal-mode pairs off an all-white reference.
Uint8List encodeG4Horizontal(List<List<int>> rows, int columns) {
  final bits = <int>[];
  void put(String code) {
    for (final c in code.codeUnits) {
      bits.add(c - 0x30);
    }
  }

  void putRun(int run, {required bool isWhite}) {
    final table = isWhite ? _whiteCodes : _blackCodes;
    var remaining = run;
    while (remaining >= 64) {
      final makeup = [256, 192, 128, 64]
          .firstWhere((m) => m <= remaining && table.containsKey(m));
      put(table[makeup]!);
      remaining -= makeup;
    }
    final code = table[remaining];
    if (code == null) {
      throw ArgumentError('run $run is not encodable by this test encoder');
    }
    put(code);
  }

  for (final row in rows) {
    // horizontal mode codes a *pair* of runs and leaves the colour at
    // white, so consume the row two entries at a time
    for (var i = 0; i < row.length; i += 2) {
      put('001'); // horizontal mode
      putRun(row[i], isWhite: true);
      putRun(i + 1 < row.length ? row[i + 1] : 0, isWhite: false);
    }
  }
  final out = Uint8List((bits.length + 7) >> 3);
  for (var i = 0; i < bits.length; i++) {
    if (bits[i] != 0) out[i >> 3] |= 0x80 >> (i & 7);
  }
  return out;
}

/// A row of alternating white/black runs summing to exactly [columns],
/// every run encodable. Even length, so it ends on a black run.
List<int> _randomRow(Random random, int columns) {
  final runs = <int>[];
  var remaining = columns;
  while (remaining > 0) {
    final choices =
        encodableRuns.where((v) => v >= 1 && v <= remaining).toList();
    final run = choices[random.nextInt(choices.length)];
    runs.add(run);
    remaining -= run;
  }
  if (runs.length.isOdd) runs.add(0);
  return runs;
}

/// Well-formed multi-row G4 streams over a spread of widths.
List<CcittCase> wellFormedCorpus() {
  final random = Random(20260720);
  final cases = <CcittCase>[];
  for (var trial = 0; trial < 200; trial++) {
    final columns = 8 + random.nextInt(300);
    final rowCount = 1 + random.nextInt(12);
    final rows = [
      for (var r = 0; r < rowCount; r++) _randomRow(random, columns)
    ];
    final data = encodeG4Horizontal(rows, columns);
    for (final blackIs1 in [false, true]) {
      cases.add(CcittCase(data, -1, columns, rowCount, blackIs1: blackIs1));
    }
  }
  return cases;
}

/// Random bytes across every parameter combination - the leniency contract
/// says these must decode to *something* deterministic, never throw.
List<CcittCase> malformedCorpus() {
  final random = Random(987654321);
  final cases = <CcittCase>[];
  for (var trial = 0; trial < 4000; trial++) {
    final data = Uint8List.fromList(
        List.generate(1 + random.nextInt(64), (_) => random.nextInt(256)));
    cases.add(CcittCase(
      data,
      [-1, 0, 4][random.nextInt(3)],
      [8, 17, 64, 1728][random.nextInt(4)],
      random.nextInt(4),
      blackIs1: random.nextBool(),
      byteAlign: random.nextBool(),
    ));
  }
  return cases;
}

/// Well-formed streams cut off mid-code, exercising the end-of-data paths
/// that the peek-once tables had to keep exact (a code the zero padding
/// completed is not really present).
List<CcittCase> truncatedCorpus() {
  final random = Random(555);
  final cases = <CcittCase>[];
  for (var trial = 0; trial < 400; trial++) {
    const columns = 64;
    final rows = [for (var r = 0; r < 6; r++) _randomRow(random, columns)];
    final full = encodeG4Horizontal(rows, columns);
    if (full.length < 2) continue;
    final cut = 1 + random.nextInt(full.length - 1);
    cases.add(CcittCase(Uint8List.sublistView(full, 0, cut), -1, columns, 6));
  }
  return cases;
}

/// A single black span swept across every start/end bit alignment - the
/// byte-run span fill has to agree with the old per-pixel fill on partial
/// head bytes, partial tail bytes, and whole interior bytes.
List<CcittCase> spanAlignmentCorpus() {
  final cases = <CcittCase>[];
  for (var columns = 2; columns <= 40; columns++) {
    for (final lead in encodableRuns.where((v) => v < columns)) {
      for (final black
          in encodableRuns.where((v) => v >= 1 && v <= columns - lead)) {
        final tail = columns - lead - black;
        if (!encodableRuns.contains(tail)) continue;
        final data = encodeG4Horizontal([
          [lead, black, if (tail > 0) tail, if (tail > 0) 0]
        ], columns);
        for (final blackIs1 in [false, true]) {
          cases.add(CcittCase(data, -1, columns, 1, blackIs1: blackIs1));
        }
      }
    }
  }
  return cases;
}

/// Random *structurally valid* 2-D mode-code streams: every code decodes,
/// but the sequence is arbitrary, so rows go places a real encoder never
/// would. This is the corpus that reaches the awkward corners - notably a
/// VL2/VL3 that drives `a1` back below the previous transition, leaving the
/// reference row unsorted, which is the case the b1 cursor must not assume
/// away. Purely random *bytes* almost never get there, because they hit an
/// unknown code and bail out within a few bits.
List<CcittCase> modeCodeCorpus() {
  const modes = [
    '1', // V0
    '011', '000011', '0000011', // VR1..VR3
    '010', '000010', '0000010', // VL1..VL3
    '0001', // pass
  ];
  final random = Random(31337);
  final cases = <CcittCase>[];
  for (var trial = 0; trial < 1500; trial++) {
    final columns = [8, 24, 64, 200][random.nextInt(4)];
    final bits = <int>[];
    void put(String code) {
      for (final c in code.codeUnits) {
        bits.add(c - 0x30);
      }
    }

    final codeCount = 4 + random.nextInt(120);
    for (var i = 0; i < codeCount; i++) {
      if (random.nextInt(8) == 0) {
        // horizontal mode, with two encodable runs
        put('001');
        final white = encodableRuns[random.nextInt(encodableRuns.length)];
        final black = encodableRuns[random.nextInt(encodableRuns.length)];
        for (final (run, isWhite) in [(white, true), (black, false)]) {
          final table = isWhite ? _whiteCodes : _blackCodes;
          var remaining = run;
          while (remaining >= 64) {
            final makeup = [256, 192, 128, 64]
                .firstWhere((m) => m <= remaining && table.containsKey(m));
            put(table[makeup]!);
            remaining -= makeup;
          }
          put(table[remaining]!);
        }
      } else {
        put(modes[random.nextInt(modes.length)]);
      }
    }
    final data = Uint8List((bits.length + 7) >> 3);
    for (var i = 0; i < bits.length; i++) {
      if (bits[i] != 0) data[i >> 3] |= 0x80 >> (i & 7);
    }
    cases.add(CcittCase(data, -1, columns, 1 + random.nextInt(8),
        blackIs1: random.nextBool()));
  }
  return cases;
}

/// The named corpora, in the order the goldens record them.
Map<String, List<CcittCase>> allCorpora() => {
      'well-formed': wellFormedCorpus(),
      'malformed': malformedCorpus(),
      'truncated': truncatedCorpus(),
      'span-alignment': spanAlignmentCorpus(),
      'mode-codes': modeCodeCorpus(),
    };
