# Build the region-replay grid index on the render-worker isolate (#384)

Follow-up to #383 (grid-cull region replay). With the grid index a dense CAD
page's deep-zoom tiles are cheap, but the remaining first-zoom UI-isolate stall
was the **grid build itself** — walking the ~850k-command transcript to bin
~282k paint units, ~210 ms on the UI isolate. That build is pure data
(command-bounds arithmetic, no `dart:ui`), so it moves to the render-worker
isolate, which already produces the transcript via `worker.record`.

## What changed

- **`region_replay_index.dart` is now Flutter-free.** `replay` routed save/
  restore through `Canvas`; it now routes them through `PdfDevice` (whose
  `CanvasPdfDevice` forwards to the canvas — byte-identical), dropping the
  `package:flutter/painting.dart` import. That lets both worker backends (the
  native isolate and the `dart compile js` web worker) import the file and call
  `PdfRegionReplayIndex.build`. Verified the web worker still compiles to JS.

- **Serialization** (`serializeRegionReplayIndex` / `deserializeRegionReplay
  Index`, same file). The grid arrays (`_cellStart`, `_cellUnits`, `_broad`) and
  the per-unit `commandIndex`/bounds/`blendMode` are trivially sendable typed
  data. The only live graph is the clip-state tree: each `PdfRegionClipState`
  holds a `PdfClipPathCommand` (a `PdfPath` + rule) plus a parent pointer. The
  tree is flattened parent-before-child to index references, and the clip PATH
  commands ride the existing `serializeCommands`/`deserializeCommands` codec —
  the same float32 path truncation the scene transcript already carries, so the
  round trip is pixel-lossless (the codec truncation is idempotent). An
  unsupported index (a group/soft-mask spanned the page) serializes to a tiny
  marker so the consumer learns the page was examined and isn't region-cullable.

- **`PdfRenderWorker.buildRegionIndex(page, {annotations, maxCommands,
  buildGrid, priority})`** — base declines (null); native isolate and web worker
  override; pool routes by stable page affinity like `binStrips` (both
  re-record, so the second request hits the worker's warm `_BinCommandCache`);
  caching wrapper is a pure passthrough (the scene memoizes the index for its
  life, so a second identical build never reaches the worker). Both backends
  build the index from the **same round-tripped, compacted wire transcript** the
  strip bins replay — byte-for-byte what a worker-recorded scene holds — so the
  index's unit indices line up with that scene's `commands`.

- **`PdfRetainedScene`**: `warmRegionIndex(worker, {pageIndex})` builds the
  index off-isolate when the worker is active and the scene came from it, else
  falls back to an in-isolate build; idempotent (concurrent calls share one
  build). `dropRegionIndex()` is the memory-pressure primitive (the next region
  raster or warm rebuilds it). `regionIndexBuildIsHeavy` is the grid-escalation
  gate — only the ~O(commands) build is worth a worker round trip; a small
  page's linear index still builds in-isolate in microseconds. `_ensure
  RegionIndex` and the worker request now share `_regionIndexBuildParams` so
  both bin the transcript with identical `(maxCommands, buildGrid)`.

- **`pdf_page_view.dart`**: `_refreshTileGeometry` calls
  `_warmRegionIndexIfNeeded`, which kicks the build onto the worker for a dense
  page (only a worker-recorded scene takes a worker-built index — its transcript
  must match the re-record). `_useTilePath` no longer forces the heavy build
  synchronously: for a dense page it defers the tile path until the warmed index
  is resident (the base raster / single patch covers the view meanwhile), then
  re-runs `_refreshTileGeometry` when it lands. **Pages below the grid ceiling
  are unchanged** — they keep the cheap synchronous linear build.

## Why byte-identical holds

The worker re-records the page through `_BinCommandCache.commandsFor`
(native) / `PdfWorkerTranscriptCache.transcriptFor` (web), which produce
`serialize(compactStateScopes:true, decodeImages:false)` → `deserialize`. A
worker-recorded scene's `commands` come from `serialize(compactStateScopes:true,
decodeImages:true)` → `deserialize`. `compactStateScopes` removes save/restore
pairs purely on clip structure (image-independent), and `decodeImages` only
changes image payloads, never the command count/order — so the two transcripts
are structurally identical and the index's `commandIndex` positions align. The
grid build is deterministic, so the same parameters produce the same units in
painter order.

## Tests

`region_replay_index_worker_test.dart`:
- serialized index → byte-identical region rasters vs the in-isolate build
  across a diverse pdfjs corpus (clips/images/gradients/patterns/text/blend);
- a **real background-isolate** `buildRegionIndex` → byte-identical region
  raster (the full seam: record → worker build → serialize → deserialize →
  replay);
- unsupported (grouped) index round-trips its `supported:false` verdict;
- `dropRegionIndex` releases the index and the next raster rebuilds it.

The #383 suites (`region_replay_grid_test`, `retained_scene_test`,
`spatial_region_corpus_test`) and the worker/tile suites stay green — the
`replay` signature change (dropping the `Canvas` arg) is internal.

## Notes / follow-ups

- The synchronous grid build can occupy the worker queue for ~210 ms (it can't
  yield mid-build), so a concurrent higher-priority record waits. Acceptable:
  the visible page's record already completed (the scene exists) before its
  index is warmed, so only background prefetch / a later settle's bin waits.
- This branch is stacked on #383 (`perf/cad-region-grid-and-hover`); it needs
  that grid to land first.
