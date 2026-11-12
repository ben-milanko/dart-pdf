# 2026-11-12 - Deep-zoom tiles draw from their slab (#1276)

`PdfTileStore` batches a settle's missing tiles into one region raster (the
"slab") and used to slice it into per-tile textures: one `drawImageRect` +
`toImageSync` per tile (`_sliceTile`). Each tile now keeps a
`ui.Image.clone()` handle on the slab plus its cell (`PdfTile.source`), and
`viewFor` hands that cell to the painter as the placement's `src`
(`_landShared`). The fallback path offsets its crop into the cell.

## Accounting

A slab stays resident until its last tile is evicted. Pixels no landed tile
covers (cells already cached when the batch rastered, edge clamping) are
spread across the landed tiles as `PdfTile.sharedBytes`, so the budget still
sees the whole slab while every tile holding it is alive. Partial eviction
can leave a slab alive under-priced until its last clone goes; bounded by one
slab (≤ `maxBatchTilesPerAxis`² tiles).

A cell outside an undersized slab still lands with an empty source, matching
the copy path (which left it transparent).

## Kept as-is

- `shareSlabs: false` restores per-tile copies.
- With a `PdfTilePersistence` attached the copy path stays: the disk tier
  stores each tile's own pixels.
- The `drawRawAtlas` half of the ticket is not done: `RSTransform` only
  carries a uniform scale, and placements scale x/y independently after
  rounding (dest fraction × size vs src pixels), so one atlas draw would
  risk hairline seams for little gain once the copies are gone.

## Measured

`test/benchmark_tile_store_test.dart` over `test_corpora/dartpdf` (8 files,
best of 3, Linux flutter_tester), batched strategy, main → slab:

| sequence | settle ms | change |
| --- | ---: | ---: |
| pinch | 3656 → 2328 | -36% |
| pan | 1470 → 736 | -50% |
| revisit | 403 → 191 | -53% |

Retained tile bytes identical (475,865 KB / 367,872 KB). Every file improved
(e.g. `cad-sheet-8p` pinch 479 → 146 ms). The web `zoom-scan` A/B
(dart2js, 5 iterations) was neutral: that scenario's 3x zoom never leaves the
base raster, so it does not reach the pyramid.
