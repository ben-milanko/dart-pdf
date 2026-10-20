# In-app devtools panel + proactive coordinated cache ceiling

Two app-facing pieces from the 8 GB macOS debug investigation (same day as
the tile-batch session, separate workstream).

## The memory audit, corrected

A retention sweep across the viewer/editor/app found **no single leak** - the
#283-era caches are genuinely budgeted. The 8 GB debug RSS is a *sum*:
the main-isolate budgeted caches (decoded-image 256 MB + render-record 96 MB +
previews + thumbnails + tiles-when-active can pass 600 MB), the per-live-page
retained rasters (`_image` ≤64 MB + `_detailImage` ≤64 MB + the unbudgeted
`PdfRetainedScene` decoded images, × the build window), the grow-only edit
session buffer (`_bytes`, plus the worker's parallel copy - the one truly
unbounded path), and per-open-tab baselines. Crucially, on desktop the only
trim trigger was the platform memory-pressure callback, which macOS delivers
too late (or never) before pausing the process.

**Correction:** the audit's claim that each render-worker isolate carries its
own 256 MB `PdfImageCache` is wrong - worker isolates never materialize
`ui.Image`s; the decoded-byte record cache (96 MB, budgeted) lives on the
main isolate in `PdfCachingRenderWorker`, and per-worker transcript caches are
command-slot-weighted and small. So there was no "divide the worker budget by
pool size" fix to make; the real fix is the ceiling below.

## Proactive coordinated cache ceiling

`PdfCacheRegistry.maxTotalWeight` (budgeted_cache.dart): a process-level
ceiling across every registered cache, enforced **as caches grow** - each
weight-bearing `put` on a registered cache calls `enforceBudget()` - instead
of only on `didHaveMemoryPressure`. Enforcement trims每 cache
**proportionally** (`trimToWeight(weight * ceiling ~/ total)`, a new public
LRU-trim that protects the MRU entry and skips weight-0 entries), so a hot
big cache isn't wiped to protect idle small ones and no cross-cache LRU clock
is needed. Residue above the ceiling is bounded by one MRU entry per cache.
Default **0 = disabled** - no SDK behavior change; the app opts in
(`app.dart`: 384 MB desktop / 192 MB mobile - heuristic split pending a
re-run of `benchmark_image_cache_budget_test.dart`). Tests in
`budgeted_cache_test.dart` ('coordinated ceiling' group).

## Devtools panel (F12 / Settings → Developer tools)

`app/lib/devtools.dart` (model) + `devtools_panel.dart` (UI), debug/profile
only (`!kReleaseMode` gates the F12 handler, the Settings tile, and
`AppDevTools.install()`). The panel uses the editor's own sidebar chrome
(`PdfSidebarPanelFrame`, docked right, resizable, session-local width) so it
looks like Annotations/Pages - just with no toolbar button - and it docks
**beside** the body in a Row (the viewer relays out narrower), never overlaying
the page, so zoom/scroll gestures keep their space. F12 is a
`HardwareKeyboard.instance.addHandler` global hook, not a CallbackShortcuts
binding: a shortcuts binding goes deaf whenever focus leaves its subtree,
e.g. right after the panel itself opens. Every metric row carries a hover
tooltip and a tap-to-open dialog with the same explanation (`_kv(help:)` /
`_helpSwitch`).

Sections: frame stats (fps/build/raster/jank over a 120-frame window, plus
performance-overlay switch and debug-only repaint rainbow), memory (process
RSS via conditional `dart:io`, per-cache table from the new
`PdfCacheRegistry.snapshot()`, the ceiling, clear-all), render-worker pool
stepper (`pdfRenderWorkerPoolSize`, applies to the next spawned pool),
deep-zoom detail mode switch (#314: patch / tiles per-tile / tiles batched,
via `PdfPageView.debugTileStoreOverride` + live tile counters), PdfPerf
(enable toggle, nonzero phases/counters, reset - main isolate only), session
diagnostics (`revisionCount` / `sessionBufferBytes`, new on
`PdfEditingController`), and a captured log (debugPrint + FlutterError,
filterable, copy/clear). A header button exports the whole snapshot -
frames, memory, caches, tile counters, PdfPerf, session, log - as one JSON
document (`saveJsonAs`, generalized from the stamps exporter) for offline
analysis. Neither the performance overlay nor repaint rainbow exists in
release: the panel is compiled out, rainbow is debug-engine-only, and the
overlay is meaningful in profile.

## Debug overlays + why a CAD page shows 0 tiles

Testing the tile modes on `OGW-30-06_Diagram.pdf` (31k-command 3370×2384 pt
CAD sheet) showed **0 tiles scheduled at 590% zoom**. Diagnosis: the page
never reaches a tile-eligible scene. `_useTilePath` (pdf_page_view.dart)
requires a retained, region-cullable, NON-vector-only scene - and a dense
vector page at deep zoom takes the **vector-first progressive path**, which
adopts a `vectorOnly` placeholder scene (image pixels deliberately absent)
and sharpens via the legacy patch. All three OGW pages are region-cullable
(probed headless), but they do carry image draws, so the "vector-only is
complete when the page has no images" relaxation does not apply. Whether the
full record ever replaces the vector-only scene during a deep-zoom dwell (it
appeared not to within ~90 s) is the open question - the new PdfPerfLog
devtools switch exists to answer exactly that from a live session. Fixing
tiles-under-vector-first is follow-up work (options: let the full record land
under tile mode, or raster tiles from the vector-only scene and stamp them
image-invalid).

New SDK debug flags (`src/debug_overlays.dart`, exported): 
- `pdfDebugPaintDetailBounds` - `PdfTileLayer` strokes every placement
  (green exact, orange upscaled fallback via the new
  `PdfTilePlacement.isFallback`) and the legacy detail patch draws a purple
  border. ValueNotifier, merged into the painter's `repaint`, so toggling
  repaints without rebuilding pages.
- `PdfLivePageRegistry` + `pdfDebugShowRenderWindow` - page views register
  their `previewIndex` on init/dispose/slot-reuse; the thumbnail tile
  (shared by strip + grid) outlines live pages in teal: the lazy-list
  render window where per-page memory lives.

Devtools panel additions: switches for both overlays, a PdfPerfLog
verbose-log toggle (its debugPrint lines land in the captured log), and
app-level catches now emit to the devtools log - `_toast`/`_openError` are
mirrored (history + export), and the silent best-effort catches (platform
fonts, session store, recents, update check, signature-appearance/OIDC/
keyless caches, deferred opens, page inserts) log errors instead of
vanishing.

## Gotchas

- `debugPrint` must NOT be wrapped under `flutter test` - the binding asserts
  foundation globals are untouched after every test. `install()` is a no-op
  when `FLUTTER_TEST` is set (conditional-import probe; web stub says false).
- No pending `Timer`s on a process-wide singleton: flutter_test fails any test
  that ends with one. The log/frame notifier throttles by timestamp
  (leading-edge) instead of a trailing timer; the panel's own 1 s poll picks
  up dropped trailing updates.
- The panel body is an eager Column in a `SingleChildScrollView`, not a lazy
  list - sections must stay live (and findable in tests) while scrolled out.
- Switching tile stores at runtime: `invalidate()` the old store but do not
  `dispose()` it - a mounted `PdfTileLayer` may still be listening until the
  next rebuild.
