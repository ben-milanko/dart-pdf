# Tile store: batched slab rasters + GPU-side slicing (issue #314 follow-up)

The #342 benchmark said a naive 1-`toImage`-per-512²-tile cold sweep loses
badly to the legacy single-patch path and named the fix: batch several tiles
per readback. This session lands that batching, plus a measurement correction
that changes the original benchmark's story.

## What landed

**`PdfTileStore.batchRasters` (default true).** One `viewFor` pass already
knows every missing tile before it returns, so that is the batching point:
`_schedule` defers keys into the pass's pending list and the pass dispatches
raster *batches* instead of per-tile rasters.

- **Grouping (`_groupBatches`):** the whole missing set rasters as one slab
  when it fills ≥50% of its tile bounding box (the cold-settle shape) and fits
  `maxBatchTilesPerAxis` (8 → a 4096² slab at 512² tiles, under the 2^14
  texture limit); a sparse set (revisit holes) falls back to contiguous
  per-row runs so cached tiles between holes are never re-rastered
  (asserted in `tile_store_test.dart`).
- **Slicing (`_sliceTile`):** the slab lands as one `rasterizeRegion` readback
  (the exact shape that makes the legacy patch fast); each tile is then cut
  out with a 1:1 `drawImageRect` blit converted by `toImageSync` — GPU-resident
  output, no scene replay, no extra pixel readback. Slices are exact because
  the whole batch shares one raster at the bucket ratio (a quadrant-color KAT
  in the tests pins the pixel offsets).
- Staleness, invalidation epochs, MRU, budget: unchanged — a batch checks one
  epoch for its page and discards the whole slab if stale. Per-tile mode
  (`batchRasters: false`) is intact and still covered by the original tests
  (the center-out scheduling test pins it explicitly).

**Benchmark now drives three strategies** (`benchmark_tile_store_test.dart`):
legacy patch, per-tile store, batched store — and adds `settleMs`, a
settle-to-sharp wall clock that *drains in-flight rasters inside the timing
window* (`while (store.inFlightCount > 0)`).

## The measurement correction

The original harness's `rasterMs` sums per-raster stopwatches, and per-tile
mode runs dozens of rasters concurrently — each stopwatch spans awaits that
include the *other* rasters' work, so the sum overcounts wall time severely.
The dev-log's "tiles ~8× slower wall-time" (1924 ms vs 235 ms pan) was this
artifact. The drained settle clock is the honest number.

## Results (7 pdfjs pages, ratio 8, best-of-2, headless software raster)

Pan (cold) per strategy — readbacks / raster-meter ms / settle-to-sharp ms:

| strategy | readbacks | rasterMs | settleMs |
|---|---|---|---|
| patch | 70 | 80 | ≈80 |
| per-tile 512² | 224 | 542 (overcounted) | **79** |
| batched 512² | **35** | 75 | 331 |
| batched 1024² | **16** | 55 | 278 |

Revisit stays 100% reuse for both tile modes (settle ≈7–30 ms vs patch
≈100 ms). Pinch: per-tile settle 125 ms, batch 511 ms, patch 44 ms.

Reading it honestly:

- **Batching does what it promised on readbacks**: 35 (or 16 at 1024²) slab
  readbacks vs 224 per-tile — and at 1024² the batch *raster* cost beats even
  the patch (55 vs 97 ms) while touching 1.6× fewer pixels.
- **This harness cannot pick the winner.** The software renderer makes
  `toImage` per-call overhead tiny (so per-tile looks fine at wall clock —
  which the GPU/web case, one full GPU sync + readback per call, will not
  reproduce) and makes `toImageSync` slicing a real CPU raster pass
  (~0.5 ms/slice, dominating batch settleMs — which on GPU is a near-free
  blit). It under-costs exactly what batching saves and over-costs exactly
  what batching adds.
- So the flag-flip decision still needs the #306 on-device/web render-trace
  numbers; what's no longer in question is the batch path's correctness and
  that it removes the readback-count explosion (the web killer: each readback
  is an uncancellable main-thread stall).

## Default rollout (same day, after interactive validation)

`PdfPageView.tileStoreDetail` now defaults per platform
(`pdfDefaultTileStoreDetail()`): **on for desktop**, off for web/mobile.
Desktop evidence: interactive testing on dense CAD sheets (with the
vector-only per-tile veto) and a 198-page scan book - 4,490 tiles over 862
slab readbacks, zero discards, pyramid pinned at its 96 MB budget, RSS
healthy under the coordinated ceiling, and the scan handoff
(vector-only → full record → tiles) confirmed working. Web stays off until
its own pass (Slug-layer coexistence, CanvasKit `toImageSync`, readback
stalls - the wins are biggest there, so measure, don't assume); mobile is
untested and jetsam-tight. Widget tests run as TargetPlatform.android, so
the existing detail-patch tests keep pinning the patch path unchanged.

## Gotchas

- Never compare summed per-operation stopwatches across strategies with
  different concurrency — drain to a quiescent state inside the clock window.
- `_sliceTile` must skip `drawImageRect` when the clamped src is empty (an
  edge tile of a clamped slab), else the engine asserts.
- Fake rasterizers feeding a batching store must size images from the
  requested region (`_Rasterizer(sizeFromRegion: true)`), or slices read
  blank pixels.
