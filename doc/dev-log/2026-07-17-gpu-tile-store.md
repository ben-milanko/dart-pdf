# PdfTileStore: a budgeted zoom-bucket tile pyramid for deep-zoom detail

Issue #314 (perf). The structural gap against native viewers (Bluebeam-class):
they composite GPU-resident tiles and never re-rasterize on pan; the page view
re-reads pixels back from the GPU on every settle. Today three raster
mechanisms coexist per `_PdfPageViewState`, each with its own staleness rule -
the full-page `_image` (capped by `_maxPixels`/`_maxDimension`, so page size
bounds fidelity), **exactly one** unbudgeted detail patch (`_detailImage`, which
dies on every settle/scene change/edit, so a pan past it blurs until a fresh
whole-region `toImage` lands), and the `_preview` upscale. This lands the module
the issue proposed, plus a flag-gated integration, without touching the shipping
default path.

## What landed

**`lib/src/tile_store.dart` - `PdfTileStore`** (a `ChangeNotifier`), a quantized
zoom-bucket pyramid of fixed-size (512² physical px ≈ 1 MB RGBA) GPU-resident
tiles. The interface the issue specified, small and synchronous:

- **`PdfTileView viewFor({id, pageSize, desiredRatio, visiblePageRect,
  rasterize})`** - returns the best-available tiles *now*. It snaps
  `desiredRatio` to a bucket, walks the visible tile range **center-out**, and
  for each tile: composites the exact-bucket tile if cached (touched to
  most-recently-used), else schedules its raster and falls back **per-tile to
  the nearest coarser cached bucket, upscaled** (clipped to the overlap; any
  still-uncovered gap leaves the base raster showing through, which is why the
  layer is purely additive). It also schedules a one-tile **prefetch ring** so a
  pan reveals ready tiles. Every placed tile is promoted to MRU, so a concurrent
  completion's eviction can only drop tiles outside the current view (the byte
  budget floor keeps a viewport's worth well above the eviction line).
- **`invalidate({Set<int>? pages})`** - `null` clears all; a page set evicts via
  `PdfBudgetedCache.evictWhere` and stamps a per-page epoch so an in-flight
  raster dispatched before the edit is discarded on completion (the exact model
  `PdfCachingRenderWorker.updateRevision`'s `changedPages` uses, #308).
- **Listenable** - ticks (coalesced to one `notifyListeners` per microtask) as
  sharper tiles land.

Storage is one `PdfBudgetedCache<PdfTileKey, PdfTile>` (#307) weighed by tile
bytes, default 96 MB, `disposer` disposing the `ui.Image`, registered with
`PdfCacheRegistry` so memory pressure clears it. The tile key -
`(PdfTilePageIdentity{pageIndex, pageEpoch, contentStamp, destructiveStamp,
plan}, rung, tx, ty)` - is built entirely from identities already on
`PdfPageRenderIntent`/`PdfPageRenderPlan`, so a content edit, rotation, or
paper-color change is a distinct key and stale pixels can never surface even
before `invalidate` frees them. The `PdfTileZoomLadder` snaps a desired ratio to
a ×√2 rung (rung 0 = ratio 1), clamped, so a small pan/pinch keeps hitting the
same rung's tiles.

The raster primitive is the existing `PdfRetainedScene.rasterizeRegion` - a tile
is just a region raster of the tile bounds at the bucket ratio. Added
`PdfRetainedScene.supportsRegionRaster` (a non-debug alias over the region
index's `supported` flag) so the caller can leave soft-mask/group pages, whose
regions can't be culled, on the legacy path.

**`lib/src/tile_layer.dart` - `PdfTileLayer`**, the presentation seam: a
`CustomPaint` whose painter (`super(repaint: store)`) calls `viewFor` each paint
and issues `canvas.drawImageRect` per placement, repainting when the store
ticks. Kept in its own file so `tile_store.dart` stays a pure model (no widget
import).

**Integration behind `PdfPageView.tileStoreDetail` (default false).** When on
and the page retains a region-cullable scene, `_updateDetail` short-circuits:
instead of producing the single `_detailImage`, `_refreshTileGeometry` stores
the visible fraction + desired ratio (computed post-render, never during
layout - `_detailGeometryAt` reads the render tree), and `build` slots a
`Positioned.fill(PdfTileLayer(...))` **above** the base `_image`, replacing the
detail-patch branch. `_dropDetail` also calls the store's per-page `invalidate`.
Soft-mask/group pages and the vector-first progressive scene keep the legacy
patch - the fallback adapter the issue calls for.

## Why flag-gated + additive, not the wholesale replacement

The issue's "what it deletes" list (`_detailImage`/`_detailGeometryAt`, the
`_rasteredRatio` staleness gate, the `_maxPixels`/`_maxDimension` caps, the
preview cache's full-raster tier) touches load-bearing machinery interwoven with
the Slug web layer, the strip router, speculative worker binning, and the
vector-first progressive scene. Ripping those out in one PR would be reckless.
The tile layer sits *above* the untouched base raster, so with the flag off the
default path is byte-identical, and with it on a not-yet-tiled gap simply shows
the (capped) base image - no regression surface. The deletions and making it
default are deferred follow-ups, pending the #306 render-trace measurements the
issue sequences this after (settle-to-sharp latency, per-readback main-thread
stall on web, retained MB on the #283 62-page scroll).

## Tests

- `tile_store_test.dart` (13): ladder snapping/round-trip; center-out
  scheduling at the bucket ratio; prefetch ring; coarser-bucket upscaled
  fallback (and no-cache → empty base-only view); per-page `invalidate` +
  in-flight discard; `null` clears all; byte-budget bound; coalesced tick;
  memory pressure; dispose inert + late-tile drop.
- `tile_layer_test.dart` (2): the layer schedules on first paint then
  composites + repaints as tiles land; an empty store paints nothing.
- `tile_store_page_view_test.dart` (2): with the flag on, a deep-zoom classic
  page composites real tiles from its retained scene (`pdf-page-tile-layer`
  present, `pdf-page-detail-image` gone, base RawImage intact); a classic scene
  reports region-cullable.

## Gotchas

- **Never call `findRenderObject` during layout.** The first cut computed the
  visible fraction inside the `LayoutBuilder` builder; that runs during the
  layout phase where reading `RenderBox.size`/`localToGlobal` asserts. Moved to
  a post-render `_refreshTileGeometry` that stores the fraction for `build`.
- **MRU protection is budget-relative.** `viewFor` promotes placed tiles, but a
  batch of completions larger than `budget − viewport` could still age a view
  tile past the eviction line. The 96 MB default (8 MB floor) sits far above a
  deep-zoom viewport (a dozen tiles ≈ 12 MB) plus a completion batch, so in
  practice eviction only ever targets off-view/prefetch tiles.
- **Tick coalescing is per-microtask, not per-batch-across-turns.** The
  test's `flush` completes every rasterizer synchronously in one burst so the
  N completions drain in a single microtask and coalesce to one tick; spread
  across event-loop turns they'd tick per turn (still correct, just chattier).
