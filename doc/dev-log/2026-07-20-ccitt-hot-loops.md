# CCITT decode hot loops (#398)

First item off the July 2026 performance-architecture review (#408). The
CCITT G3/G4 decoder is the dominant filter in scanned monochrome PDFs and
is reused wholesale by the JBIG2 MMR path, so its inner loops are the
hottest code in `pdf_cos` on scanned documents. Four defects, all in
`packages/pdf_cos/lib/src/filters/ccitt.dart`.

## What was wrong

1. **`b1Index` rescanned the reference row from index 0 for every mode
   code** - O(transitions) per code, O(transitions²) per row. On a dense
   300 dpi row (~350 transitions measured on the synthetic page below)
   that is ~60k iterations per row, ×2200 rows.
2. **Run-code decoding re-peeked per candidate length.** `_readRunCode`
   tried lengths 4..13 (white) / 2..13 (black), and `_Bits.peek` was
   itself a bit-at-a-time loop, so a single white run cost up to ~85 bit
   extractions plus a dozen synthesized-key map lookups. `_readMode` had
   the same shape, scanning `_modeCodes` linearly.
3. **`_renderRow` filled spans one pixel at a time** - a solid 1728-column
   row cost 1728 read-modify-writes instead of ~216 byte writes.
4. **The JBIG2 MMR path re-expanded the packed output pixel by pixel**
   (`jbig2.dart` `_decodeMmr`), stacking a second per-pixel loop on top of
   `_renderRow`'s.

## What changed

- **Monotonic b1 cursor.** `a0` is non-decreasing within a well-formed
  row and `reference` is sorted, so the scan resumes where the last one
  stopped. Both premises can be violated by broken input, which the
  decoder is contractually lenient about, so the cursor is used *only*
  when the row is actually sorted (checked once per row, O(n)) and it
  rewinds if `a0` moves backwards. **A VL2/VL3 code really can drive `a1`
  below the previous transition and leave the row unsorted** - this is not
  theoretical, it is reachable and covered by the `mode-codes` corpus.
- **Peek-once prefix tables.** `_runCodeMaxBits` (13) and
  `_modeCodeMaxBits` (7) bits are peeked once and resolved with a single
  `Int32List` lookup holding `(payload << 4) | codeLength`. Tables are
  built from the existing `_whiteCodes`/`_blackCodes` maps, shortest code
  laid down first and never overwritten, preserving the old
  "first match wins" order. The tables are prefix-free (verified), so the
  fill order is in fact immaterial - the ordering is kept for exactness,
  not correctness.
- **Zero-padding guard.** Near the end of the data fewer than 13 bits
  remain, so the peek is zero-padded; a code the padding *completed* is
  rejected (`length > available`), which is what keeps truncated streams
  decoding to the same bytes as before.
- **Byte-run span fill.** `_fillSpan` masks the two partial edge bytes and
  `fillRange`s the interior.
- **`_Bits.peek` accumulates whole bytes** (at most three for a 13-bit
  read) instead of looping per bit. This speeds up `_skipEolAndFill` and
  `_readMode` as a side effect.
- **JBIG2 `_decodeMmr` unpacks a byte at a time** and skips all-white
  bytes outright, since the target bitmap starts zeroed.

## Validation

Output is **byte-identical** to the previous decoder. That is the whole
risk of this change - the decoder is lenient by contract, so "correct on
valid input" is not enough; malformed and truncated input has to keep
decoding to the *same wrong answer* it did before.

`test/ccitt_golden_test.dart` locks the output of five seeded corpora
(`test/ccitt_corpus.dart`) against digests **captured from the
pre-optimization decoder**:

| corpus | cases | what it covers |
|---|---|---|
| `well-formed` | 400 | multi-row G4 across a spread of widths, both polarities |
| `malformed` | 4000 | random bytes across every K/columns/rows/flag combination |
| `truncated` | 400 | well-formed streams cut mid-code (the zero-padding paths) |
| `span-alignment` | 3386 | a black span at every start/end bit alignment |
| `mode-codes` | 1500 | random *structurally valid* mode-code streams |

Case counts and total decoded bytes are part of each golden, so a corpus
that stops generating cases - or starts decoding everything to nothing -
fails loudly instead of matching a digest vacuously.

The suite was **mutation-tested**: dropping the cursor rewind, breaking
the tail mask by one bit, removing either zero-padding guard, and dropping
the `peek` mask are each caught. Notably, *ignoring the `sorted` check* was
**not** caught until the `mode-codes` corpus was added - random bytes bail
out on an unknown code within a few bits and essentially never build an
unsorted reference row. That corpus is the reason the guard is known to be
load-bearing rather than assumed to be.

Re-baseline deliberately with `dart run tool/gen_ccitt_goldens.dart`.

## Measured

Synthetic 1728×2200 G4 page (US Letter at 200 dpi), text-like content at
~343 transitions/row, encoded by a proper T.6 encoder so the mode mix is
the pass/vertical/horizontal blend a real scanner emits:

| | old | new |
|---|---|---|
| decode | 168.9 ms | **42.7 ms** |

**3.96×**, output byte-identical. A horizontal-mode-only variant of the
same page measures 3.01×; the vertical-mode number is the representative
one, because that is what real G4 is made of and because `b1Index` is a
larger share of the work there.

`tool/perf.sh gate` passes unchanged (12 inputs, 13 counters within 3%),
which is expected - this is pure constant-factor work behind identical
output, so no counter should move.

## Notes

- The full `dart_pdf_editor` suite is green except the pre-existing
  `ghent GWG030` baseline failure, which is unrelated and predates this
  branch.
- No real CCITT PDF exists in `corpus/` or `test_corpora/`, which is why
  the benchmark is synthetic. Worth adding one if a suitable scanned
  document turns up - the checked-in 64×24 libtiff fixture in
  `ccitt_test.dart` is real but far too small to time.
