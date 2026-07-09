# 2026-07-10 - Track A session 3: glyph strip cache merged, re-measured

Follow-up to [2026-07-10-gpu-strips-wiring.md](2026-07-10-gpu-strips-wiring.md).
Merged `experiment/strip-core` d0b78f5 (glyph strip cache -
cache-on-second-sight + FIFO, on by default via `GlyphStripCache.shared`,
so `GpuPdfDevice`'s `fillOutline` path gets it with no device change; also
brings `curve_quads.dart` Slug foundations and a fine-raster accumulator
crash fix). Merge clean; raster tests 63 green, `fvm dart analyze` clean,
GPU strip-probe + smoke green.

## Matched A2 pairs (scale 2, max 10, pipelined, back-to-back)

| config          | corpus | pdfjs | combined |
|-----------------|-------:|------:|---------:|
| strips A2 + GC  |  64.4  | 13.4  |  41.1    |
| aliased         |  60.7  | 10.6  |  37.9    |

Strips-vs-aliased gap: **+6.1% corpus / +8.6% combined** (yesterday's
pairs: +8.6%..+12%). Still well under the A2 gate (41.1 vs 52.8) and far
under MSAA (+41% over aliased).

## Profile pages (best-of-3, warm cache - where the cache shows)

- **CTC p0 (text-dense, 2596 runs): paint 29.2 -> 12.4 ms (-58%), total
  30.3 vs aliased 31.5 - the text-dense gap is CLOSED warm** (strips now
  at parity with the aliased glyph-triangle cache, with AA).
- WAT_L0001_S p1 (CAD linework): paint 88.3 -> 60.6 ms (-31%; its 319
  text runs/page are cached, the 1595 stroke expansions are not), GPU
  exec ~15ms. Aliased paint 21ms. **Strokes are now the remaining gap.**
- NPR text+vector: paint 9.2 -> 8.5; ly9/AO-PR/TRAX unchanged (not
  glyph-bound).

Benchmark (cold, single pass over 10 pages/file) moves less than the
warm profile because cache-on-second-sight pays full price for each
glyph+transform's first sighting: WAT 141 -> 130 ms/page; CTC is a single
noisy page (115 -> 124 while its aliased twin swung 107 -> 85, both
within the observed ±15% single-page noise).

## Verdict

The glyph cache closed the text-dense strips-vs-aliased gap as predicted
(warm parity on CTC), and took a third off stroke-heavy CAD paint. The
corpus mean only moved ~3 points because the remaining gap is stroke
expansion + binning (WAT-class pages) - a stroke/symbol strip cache (same
quantized-transform idea applied to `strokePath`/repeated CAD symbols)
is the next lever, again in the shared core.
