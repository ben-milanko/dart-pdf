# Idle full-resolution page-raster warming (#614)

`PdfPageRasterCachePolicy` let a host raise the exact-raster budget, but the
cache was only ever *filled* by pages that rendered on screen. A reader with
several GB to spare still paid the full interpret + GPU readback the first time
they arrived on any page. This session spends genuine viewer idle time filling
that cache ahead of navigation.

## What landed

**`PdfPageRasterWarmPolicy`** (`raster_warm.dart`, new) — `disabled` (the
default), `nearby(window:)`, `document()`, plus `idleDelay`. Threaded through
`PdfViewer`, `PdfReader`, `PdfEditorView`, and `PdfComparisonView` alongside the
existing cache policy. **`PdfPageRasterWarmStats`** in the same file is the
diagnostic snapshot (attempts / completions / skipped / rejected / preempted /
warmed bytes / hits / misses / evictions / retained bytes / entries), exposed as
`PdfViewerController.pageRasterWarmStats`.

**`PdfPageRasterGeometry`** (`renderer.dart`) is the load-bearing piece. The
warm has to bake a raster at *exactly* the geometry the page widget will later
ask the cache for; one pixel of drift and every warmed page is silently a miss.
So the ratio/dimension arithmetic moved out of `_PdfPageViewState`
(`_desiredRatioAt`, `_effectiveRatioAt`, `_rasterDimensions`, `_maxPixels`,
`_maxDimension`) into one place both sides call. The viewer's `_pageWidth(index)`
is provably the page view's `constraints.maxWidth` — `FractionallySizedBox`
gives the child `crossView * crossPointOf/maxCrossPoint * layoutZoom`, and
`_pageCross` is `crossPointOf * _fitScale * layoutZoom` with
`_fitScale = _crossView / _maxCrossPoint` — so warming from the viewer's layout
model lands on the widget's number. The web run below confirms it empirically:
`raster-warm page=N 2400x3106` followed by `full-raster cache hit page=N
2400x3106`.

**The exact-raster cache is now keyed by `(page, raster signature)`**, not by
page index. `PdfPageRasterSignature` = index + physical width/height + paper
colour + annotation visibility + rotation; revision is still compared by
`PdfPage` identity on the entry, because a rebind must not invalidate a raster
whose pixels did not change.

This reverses one specific decision from the 2026-07-29 render-waste session. In
that trace a stale ratio-0.4 raster produced `miss reason=dimensions` three
times while the viewer re-rasterized at ratio 1.4, so `fullImageFor` was made to
evict on any mismatch. Under index keying that was right; under signature keying
it is not, because a fit-size raster and the current zoom's raster are both
useful and neither should destroy the other — the whole point of warming a page
is defeated if zooming it throws the warm away. The waste it was guarding
against is bounded two ways instead: **`_maxVariantsPerPage = 2`** (a third
resolution evicts this page's least-recently-used variant), and
`_dropStaleVariants` on every lookup miss, which drops every raster of that page
belonging to an older revision. `page_preview_test.dart`'s "a lookup at another
geometry drops the entry it cannot use" is replaced by "geometry variants
coexist; a stale revision does not", which pins all three behaviours.

**`PdfPagePreviewCache.warmFullRaster`** is the unit of work. Guard order is the
design: already-cached is skipped with a pure peek (no LRU touch, no counter
distortion); an inadmissible size is declined *before* any interpretation and
counted as `rejected`; `shouldStop` is polled around every await. Worker-first,
local `renderPictureRecordedWithPlan` fallback — unlike the thumbnail warm, the
local walk is worth paying here, because that walk *is* the cost being moved
into idle time. The picture also feeds `putFromPicture`, so the low-resolution
navigation preview comes free.

**The viewer loop** (`_warmFullRasters`, `_nextRasterWarmIndex`,
`_rasterWarmIdle`, `_scheduleRasterWarm`) mirrors the thumbnail warm's shape.
`_rasterWarmIdle` is false while `_renderScheduler.busy` (hold, queued, or a
granted render still replaying), while any motion/scroll/zoom settle timer is
live, while zoomed (deep zoom is the detail patch's job), while a tool is armed,
and while the viewer is parked. `_renderScheduler.activity` restarts the idle
countdown on every ping, so the warm can only run after the viewer has genuinely
stopped — and resumes without needing a scroll settle that may never come.
A page abandoned mid-warm is *removed* from `_rasterWarmAttempts` so the next
settle retries it rather than writing it off.

Invalidation re-arms the pass wherever the signature moves: document/revision
swap, paper colour, annotation visibility, view rotation, and a raised cache
budget (which may admit pages previously declined).

Two subtleties worth remembering:

- The admissibility check deliberately lives in `warmFullRaster`, not in the
  viewer's candidate filter. Filtering silently in the viewer left `rejected` at
  zero and gave a host no way to see why nothing warmed.
- Widget tests must pump *with a duration*. The idle countdown is a `Timer` in
  the fake-async zone, so `await tester.pump()` alone never lets it fire — the
  first version of `raster_warm_test.dart` measured a warm that had not run.

## Measurements

VM, this machine (`test/benchmark_raster_warm_test.dart`, runs by default;
`PDF_WARM_BENCHMARK_PDF=` points it at a real file):

| profile | cold interpret+raster | warmed cache hit | retained |
|---|---|---|---|
| ordinary text (8p) | 17.7 ms/page | 0.081 ms | 12.6 MB/page |
| dense vector (CAD) | 642.6 ms/page | 0.076 ms | 3.9 MB/page |
| raster underlay (scan) | 241.1 ms/page | 0.030 ms | 27.6 MB/page |

Real headless Chrome, dart2js (new `warm` workload kind in
`app/tool/perf/perf_harness.dart`; the arms differ only in `?warm=`). Idle 9 s,
then navigate to a mid-document page:

| scenario | arrive | warmed | retained | tab agent |
|---|---|---|---|---|
| `warm-plan-off` (16p vector plan set) | 2121 ms | – | – | 266 MB |
| `warm-plan-document` | **107 ms** | 14 pages | 84.5 MB | 396 MB |
| `warm-scan-off` (12p A3 grayscale) | 1718 ms | – | – | 270 MB |
| `warm-scan-document` | **49 ms** | 10 pages | 58.2 MB | 538 MB |

~20× and ~35× faster arrival, for 60–85 MB of retained rasters (plus, on the
scan document, the decoded images behind them — tab agent memory roughly
doubles). That is the trade, and it is why the default is `disabled` and the
app exposes it as an explicit Developer-tools selector rather than turning it on
for everyone.

The counter gate (`tool/perf.sh gate`) is unchanged: 12 inputs, 13 counters
within 3%.

## Files

- `packages/dart_pdf_editor/lib/src/raster_warm.dart` (new) — policy + stats
- `packages/dart_pdf_editor/lib/src/preview_cache.dart` — signature key,
  variant cap, `warmFullRaster`, `admitsFullRaster`, `hasFullRaster`, counters
- `packages/dart_pdf_editor/lib/src/renderer.dart` — `PdfPageRasterGeometry`
- `packages/dart_pdf_editor/lib/src/pdf_page_view.dart` — delegates the ratio
  math to the shared helper
- `packages/dart_pdf_editor/lib/src/pdf_viewer.dart` — the warm loop, the idle
  gate, `pageRasterWarmStats`
- `app/lib/devtools.dart` / `devtools_panel.dart` / `editor_screen.dart` — the
  "Idle raster warm" selector (Off / Nearby ±2 / Nearby ±5 / Whole document),
  persisted with the other devtools options
- `app/tool/perf/perf_harness.dart` + `scenarios.json` — the `warm` workload
- tests: `raster_warm_test.dart`, `benchmark_raster_warm_test.dart`,
  `page_preview_test.dart` (variant semantics), app devtools tests
