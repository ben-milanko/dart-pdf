# 2026-11-12 - Deep-zoom tiles draw from their slab (#1276)

`PdfTileStore` batches a settle's missing tiles into one region raster (the
"slab") and used to slice it into per-tile textures: one `drawImageRect` +
`toImageSync` per tile (`_sliceTile`). Each tile now keeps a
`ui.Image.clone()` handle on the slab plus its cell (`PdfTile.source`), and
`viewFor` hands that cell to the painter as the placement's `src`
(`_landShared`). The fallback path offsets its crop into the cell.

## Accounting: share only fully used slabs

A slab is shared only when the cells landing from it cover all of its
pixels, so every shared tile costs exactly its own pixels and a slab lives
until its last tile is evicted. A batch whose box spans already-cached cells
slices per tile as before. Two CI failures forced this:

- An earlier cut charged a slab's unused pixels to its landed tiles. The
  Android gate (`native_perf_e2e_test`, a 64 MB budget expected to hold 64
  one-MB tiles) filled at 60: a 1024x2048 prefetch slab spanned 4 cached
  cells and charged their pixels to its 4 new tiles.
- Any overshoot at all loops: `viewFor` plans the visible + ring working set
  with *nominal* tile bytes, so tiles priced even ~11% above nominal pushed
  the set over budget, the LRU evicted ring tiles, and the next paint
  re-requested them forever (15 deep-zoom widget tests timed out in
  `pumpAndSettle`; the same 65 tiles were dispatched 72 times each).

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
best of 3, Linux flutter_tester, quiet machine), batched strategy,
main -> shared slabs:

| sequence | settle ms | change |
| --- | ---: | ---: |
| pinch | 3656 -> 2353 | -36% |
| pan | 1470 -> 710 | -52% |
| revisit | 403 -> 197 | -51% |

Retained tile bytes identical (475,865 KB / 367,872 KB). The web `zoom-scan`
A/B (dart2js, 5 iterations) was neutral: that scenario's 3x zoom never leaves
the base raster, so it does not reach the pyramid. Full `dart_pdf_editor`
suite: 3837 passed.
