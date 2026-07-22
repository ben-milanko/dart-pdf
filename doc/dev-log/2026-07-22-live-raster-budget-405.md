# 2026-07-22 — global live-raster memory budget (#405)

Per-page raster caps were additive with no cross-page accounting: each live page
in the scroll cacheExtent could simultaneously hold a base raster (up to
`_maxPixels` = 16.7 Mpx ≈ 64 MB RGBA), a deep-zoom detail patch, and a retained
scene's decoded images. With 3–5 pages live that is several hundred MB of GPU
memory with nothing bounding the sum — the memory-pressure / jetsam shape #405
(and the 2 GB RSS traces) describe on large-format documents.

## Change

A process-wide `PdfLiveRasterBudget` (`live_raster_budget.dart`) that every live
page registers with, and that reclaims the farthest-from-viewport pages' rasters
whenever the total exceeds `maxBytes`:

- `PdfLiveRasterHolder` is a plain (`dart:ui`-free) interface — `liveRasterBytes`,
  `liveRasterDistance` (0 = viewport), `evictLiveRaster()` — so the accounting and
  eviction order are unit-tested against fakes with no Flutter binding.
- `_PdfPageViewState implements PdfLiveRasterHolder`: bytes = base `_image` +
  detail `_detailImage` + the retained scene's decoded images (new
  `PdfRetainedScene.decodedImageBytes`, part 3 of the ticket); distance =
  `widget.focusDistance` (the signal added for #451); evict drops the base
  raster, detail patch, and scene (keeping the soft preview up) so the page
  re-rasterises when scrolled back near the viewport.
- `rebalance()` runs post-frame after a base raster lands (`_scheduleBudgetRebalance`,
  debounced once per frame). It evicts farthest-first, **never the focused page**,
  and **stops the moment the total fits** — so it is a reclaim budget, not a
  reservation, and the near-viewport working set is never touched.
- Memory pressure: `didHaveMemoryPressure` now calls `evictReclaimable()`, which
  surrenders every off-viewport page's rasters. Live-page rasters used to be
  exempt from the pressure signal that already trims the byte-budgeted caches —
  the ticket's specific gap.
- Platform default `pdfDefaultLiveRasterBudgetBytes()` (desktop 384 MB, mobile
  192 MB, low-RAM web 128 MB), set at app boot next to the cache-registry ceiling.

## Testing

- `live_raster_budget_test.dart` — 9 unit tests over the eviction contract:
  farthest-first, stops-when-it-fits, never-the-focused-page, keeps-evicting-outward,
  distance-tie-breaks-by-size, disabled at `maxBytes <= 0`, and the pressure path.
- Full `dart_pdf_editor` Flutter suite green (the eviction runs setState on
  off-viewport page states; the render lifecycle re-rasterises them on scroll-back
  exactly like a cache miss). `dart analyze` clean (package + app).

## Not done (deliberately)

- Part 2 (lower `_maxPixels` toward viewport² × maxUsefulZoom): a separate
  per-page-cap tweak with detail-patch-engagement trade-offs of its own; left out
  to keep this change to the cross-page budget, which is the headline fix. The
  budget already bounds the sum regardless of the per-page cap.
