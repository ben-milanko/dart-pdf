# 2026-09-26: JPX tier-1 neighbour flags and stride-2 DWT

JPEG 2000 decode got about twice as fast (0.42-0.48x decode time on AOT,
0.44-0.53x under dart2js) with no change to the output. The render worker's
decoding record on JPX pages drops to 0.44-0.54x. Two changes in
`packages/pdf_cos/lib/src/filters/jpx.dart`, one commit each.

## Why

Pure-Dart JPX decode runs on Android, Windows, Linux and the web. On Apple
platforms, #860 hands plain JPX to ImageIO, but anything with an SMask,
ICCBased/Indexed colour, `/Decode`, a colour-key mask, or used as a soft
mask still comes to us. Profiles of the render worker's decoding record on
JPX pages put `_BitModel._hasSignificantNeighbor` at 30-43% of self time.
Every coefficient, in every coding pass, rescanned its 3x3 neighbourhood
with bounds checks, and `_zcContext` then did the same eight loads again to
pick the zero-coding context. After those, `int.clamp` came next (~6% self,
~80% of it from `_synthesize1d`'s mirroring closure), then `_zcContext`
itself. #525 (cp_reduce) skips whole resolution levels but left tier-1
alone, and #407 made the DWT in-place. Nothing had touched the per-pass
bookkeeping before this.

## What changed

- **Tier-1 (`_BitModel`)**:
  - A `Uint8List _neighbors` per code block holds one packed byte per
    coefficient: the horizontal count in bits 0-1 (+0x01), vertical in bits
    2-3 (+0x04) and diagonal in bits 4-6 (+0x10). This is the OpenJPEG /
    pdf.js layout.
  - The three sites that make a coefficient significant all go through
    `_markSignificant`, which bumps the eight neighbours.
  - `_hasSignificantNeighbor(index)` becomes `_neighbors[index] != 0`.
  - `_zcContext(index)` becomes `_zc[_neighbors[index]]`. `_zc` is this band
    family's row of `_zcTables`: three 128-entry tables built once from the
    unchanged Table D.1 logic (`_zcContextOf`). The row is hoisted into the
    model so the hot path skips the lazy top-level-final check and the outer
    list index.
  - The callers pass the index they already computed instead of recomputing
    `y * width + x`.
- **DWT (`_synthesize1d`)**: each lifting step walks its own parity with
  stride 2 and reads the interior neighbours directly. Only the two end
  samples still go through the mirroring `at()`. The 9/7 scale loop splits
  into an even pass and an odd pass. Every sample gets the same float
  operations in the same order.
- **Test (`packages/pdf_cos/test/jpx_test.dart`)**:
  `tier-1 and DWT edge shapes decode bit-perfectly` checks ten lossless
  OpenJPEG 2.5.4 codestreams, stored base64 with the raster recomputed from
  `_edgePattern`. They cover:
  - odd image offsets `-d 1,1`, `3,5` and `1,3` (the last in RGB);
  - 4x4 code blocks;
  - 1x9, 9x1, 2x9 / 9x2 at an odd offset (n == 1 odd-parity bands), 3x3 and
    1x1.

## Why the counts stay exact

- Each significance site is guarded by `_significant[index] == 0`. The
  run-length position is taken only when all four coefficients are
  insignificant, so a coefficient is marked at most once.
- That caps the counts at h 2, v 2, d 4, so the packed byte peaks at 0x4A.
  It fits the 128-entry table and never wraps a `Uint8List` slot.
- The counts are updated before any later read, so the refinement pass's
  context 14/15 sees the same live state the 3x3 scan did.
- `_BitModel` is created per code block and dropped after `decode()`.
  `_neighbors` is transient: one byte per coefficient, 4 KB for a 64x64
  block.

## Measured

AOT (`dart compile exe`), Dart 3.13.3, thread-CPU medians, 5 rounds
interleaved base / tier-1 / tier-1+DWT on a loaded 10-core machine. Decoded
samples hash identically in every run.

| workload | base | tier-1 only | tier-1 + DWT |
|---|---:|---:|---:|
| private real-world corpus doc, 43 unique JPX streams (46M samples) | 5634 ms | 0.59x | **0.48x** |
| same doc, reduce 1 | 1917 ms | 0.56x | **0.49x** |
| one 2048x1754x3 CAD JPX tile (cad-images-mixed) | 1713 ms | 0.50x | **0.42x** |
| same tile, reduce 2 | 146 ms | 0.66x | **0.60x** |

dart2js under node, process CPU, 5 rounds:

- the CAD tile: 2394 -> 1062 ms (**0.44x**) at `-O2`, 2356 -> 1059 ms
  (**0.45x**) at `-O3` (the render worker's level since #964)
- the corpus doc's 49 streams: 7865 -> 4141 ms (**0.53x**) at `-O2`,
  8049 -> 4143 ms (**0.51x**) at `-O3`

Render-worker decoding record: `serializeCommands(decodeImages: true,
maxImagePixelRatio: 2, pageRasterPixels, fresh PdfImageDecodeCache,
compactStateScopes: true)`, thread CPU, 5 rounds.

- **Corpus doc, all 20 JPX pages**: 7629 -> 4102 ms (**0.54x**). Per page
  the ratio is 0.40-0.73x. Pages that also decode large Flate/Indexed
  underlays sit at the high end of that range.
- **Heaviest page**: 3991 -> 1849 ms.
- **CAD mixed page (13 JPX tiles)**: 25.5 -> 11.1 s (**0.44x**).
- **Output**: `outBytes` is identical on every page.

The CAD tiles are plain DeviceRGB, so on macOS/iOS they go to ImageIO and
see none of this. The corpus doc's JPX (ICCBased with SMask, plus DeviceGray
soft masks) stays in Dart on every platform.

## Identity

An old-vs-new harness links a HEAD copy of `jpx.dart` next to the patched
one and byte-compares every stream at reduce 0, 1 and 2. 1,761 decodes, 0
mismatches:

- Ghent GWG170, GWG172 and the two V50 suites, plus pdf.js jp2k-resetprob
  (15 decodes);
- the corpus doc's 49 streams (147);
- the 13 CAD tiles (39);
- the ten new KAT codestreams (30);
- 510 synthetic `opj_compress` codestreams (1,530): 30 sizes from 1x1 to
  513x97, gray and RGB, times 17 option sets (lossless, 9/7, layers, 4x4
  and 16x64 blocks, odd image and tile offsets, tiles, RESET, RPCL +
  precincts + SOP/EPH, `-n 1/2`, PSNR layers, mct 0, VSC). The 48 VSC
  streams are null in both, because the vertically-causal style is
  rejected at parse time.

The Ghent render baselines do not change.

## Gotchas

- **Causal contexts**: the neighbour counts assume non-causal contexts.
  Adding the vertically-causal code-block style (0x08, rejected today in
  `_readCodingParameters`) would need `_markSignificant` to hide the next
  stripe's top row from each stripe's bottom row. A comment at
  `_markSignificant` says so.
- **Formatting**: `jpx.dart` and `jpx_test.dart` are not format-clean at
  HEAD under the current formatter (old-style list literals), so running
  `tool/format.dart` on them rewrites unrelated code. The changed hunks were
  checked format-clean against a formatted copy instead.
- **Ghent coverage**: Ghent's JPX is one 236x236 Indexed image per file,
  which exercises this code only lightly. Rely on the KATs and the
  stream-level old/new compare, not the render baselines.
- **Why the new KAT matters**: two DWT boundary mutants (a wrong mirror at
  the odd-parity left end, or at the even right end) pass all eleven older
  jpx tests. The new edge-shape KAT catches both. The 16x16 zero-offset
  fixtures never put a sample of that parity at either end.

## Next (measured in the post-change profile, not done here)

- `_scContext`: its closure, record return and h/v clamp still account for
  most of the remaining `int.clamp` self time. Fold the sign context onto
  the neighbour byte or the sign bits, as pdf.js does.
- `MqDecoder.decode` is now the top self item (~12%).
- `_synthesize1d` (~9% self): a stripe-oriented column DWT would drop the
  per-column gather/scatter. A flat per-band scatter without the closure
  would help too.
- The output clamp in `_JpxParser.decode` could use a manual min/max.
