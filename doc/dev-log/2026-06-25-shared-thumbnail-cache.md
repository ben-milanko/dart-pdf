# Shared, viewport-ordered page-thumbnail cache

Reworked the page-thumbnail rendering behind the docked strip
(`PdfThumbnailSidebar`) and the full-area page grid (`PdfThumbnailView`)
in `editing_thumbnails.dart`. Three problems the user reported:

1. The grid built every cell eagerly (a `Wrap` in a `SingleChildScrollView`)
   and each cell enqueued onto a plain FIFO `Future` chain, so pages
   rendered strictly in index order — page 50, on screen, waited behind
   pages 0–49. Scrolling never re-prioritized.
2. The strip and grid each owned their own `_ThumbnailCache`, so switching
   between them (or scrolling a tile out and back past the 96-entry LRU)
   re-rendered pages that had already been rasterized.
3. Nothing warmed the cache ahead of the user.

## What changed

- **`PdfThumbnailCache`** (new `editing/thumbnail_cache.dart`): the old
  per-panel `_ThumbnailCache` LRU plus a viewport-ordered scheduler that
  replaces the FIFO `Future` chain. Tasks carry their page index; the
  queue always grants the pending task nearest `focus` next, serialized
  one at a time. `request(token, page, run, {warm})` / `cancel(token)` /
  `focus` setter. Warm tasks rank below *every* on-screen tile
  (`1 << 30` penalty in `_rank`), so background fill never delays a
  visible page. Kept the `scheduleMicrotask` drain (no `endOfFrame`
  between tasks) so the existing widget tests that drain under
  `runAsync` behave exactly as before.

- **Hosted on the session.** `PdfEditingController.thumbnailCache` owns one
  cache for the whole edit session; both panels draw from it via
  `widget.controller.thumbnailCache`. A page rendered for the strip is
  reused by the grid and survives a tile scrolling out and back. A new
  session = a new controller = a fresh empty cache, so the old
  per-controller-swap `_cache.clear()` is gone (render stamps restart at
  zero per session, so cross-session key collisions can't happen anyway).
  Capacity bumped 96 → 256.

- **Focus from scroll.** Both panels push `cache.focus` from their scroll
  position (`_thumbnailFocusFromScroll`, a coarse fraction→index estimate
  — no per-tile layout math). The strip also biases focus to the viewer's
  current page on follow. So "render what's on screen first," and
  scrolling re-prioritizes toward what just came into view.

- **Idle background warm.** `_ThumbnailWarmer` (one stable token per page)
  registers a lowest-priority warm task for every page, re-synced from
  `build` only when the render signature (pixel-width bucket / page color /
  annotations / page count) changes. Each warm task renders straight into
  the shared cache and is skipped if the key is already present. Withdrawn
  on panel dispose / session swap via `cancelAll`. For a document larger
  than the 256-entry LRU this self-limits (far pages evict near ones);
  the common case (tens of pages) warms fully.

- **Preview placeholder.** While a sharp tile is still rendering it now
  paints the viewer's matching low-res preview as a soft placeholder
  instead of blank paper. `PdfViewerController.pagePreviewCache` exposes
  the attached viewer's `PdfPagePreviewCache` (read-only, one clone per
  tile, disposed when the sharp raster lands). Best-effort — a missed
  preview just leaves blank paper as before.

## Gotchas / notes

- **Dedup across surfaces.** A tile's render task re-checks
  `cache.contains(key)` at the top: when the grid, the strip, or the warm
  pass rendered the same key while the task waited its turn, it adopts the
  existing raster instead of re-rendering. Because the scheduler runs one
  task at a time, this is race-free and keeps `debugRasterizations` at
  exactly one rasterization per (page, stamp, size, color) — the
  `editing_panels_test` exact-count assertions still hold.
- **The cache key** (`thumbnailKey`) is unchanged in shape (page · render
  stamp · ARGB color · pixel-width bucket · `noannots`), just hoisted to a
  shared helper so the tile, the grid cell, and the warm pass all derive
  the same key and reuse one another's rasters.
- `rasterizeThumbnail` is the extracted render path (worker priority 2 →
  replay, else local `renderImage`), shared by the tiles and the warm
  pass. No rotation argument — page `/Rotate` rides the page object and
  bumps the render stamp, so it flows through the key.
- The grid cell's thumbnail lays out at `tileWidth - 21` (the cell pads
  ~21px); the warm pass must use the same width or it would render a
  second, differently-keyed raster. Both panels compute the warm
  pixel-width from their own tile width.

Kept thumbnails at sharp tile resolution (the user's call over unifying
on the ~200px preview cache); the preview cache is only the placeholder
source, not the thumbnail store.

## Follow-up: the warm pass was slowing visible thumbnails

First cut registered the whole-document warm as lowest-priority tasks in
the *same* serialized queue as the on-screen tiles. Two problems on a heavy
CAD document (~3–4 s/page to interpret):

1. Visible tiles and warm renders both hit the render worker at **priority
   2**, so the worker couldn't tell "the thumb you're looking at" from a
   background page — an in-flight warm render wasn't preempted.
2. The scheduler serializes through one slot (`_drain` awaits each task).
   A warm render holding that slot blocked a tile requested mid-warm for
   the *whole* render, and because the tile's worker request was never even
   sent while the slot was held, worker priority alone couldn't rescue it.

Fix — warm is now a **separate paced loop** in `PdfThumbnailCache`
(`setWarm`/`clearWarm`/`_warmLoop`), not a scheduler task:

- It renders one off-screen page at a time, nearest `focus` first, and
  **steps aside (returns) whenever a tile is queued or rendering**
  (`_foregroundBusy`); the foreground `_drain`'s `finally` re-kicks it when
  the queue empties. `focus`/`setWarm` also re-kick.
- `rasterizeThumbnail` gained `priority` + `skipIfWorkerDeclines`. Warm
  renders at worker **priority 3** (below tiles' 2) and **declines the
  UI-thread fallback** — so a tile arriving mid-warm preempts the warm
  render at the worker (returns null → warm skips, no heavy local interpret),
  and the tile renders immediately.
- The old scheduler lost its `warm` flag/rank — it's foreground-only now.

**Gotcha that bit once:** the first version of `_warmLoop` *busy-waited* on
`SchedulerBinding.instance.endOfFrame` while `_foregroundBusy`. In widget
tests the foreground render parks forever on a never-completing
`toImage` (rasterization needs `tester.runAsync`), so `_draining` stays
true and the loop spun, scheduling a frame every iteration → `pumpAndSettle`
never settled and 22 tests failed. Stepping aside (return + re-kick) instead
of busy-waiting fixes it; the only `endOfFrame` left is the bounded
between-pages breathe, reached just once per page per pass.

## Instrumentation for grid perf traces

Added timeline/console instrumentation on the thumbnail render path to
diagnose a "grid still feels slow" report:

- `rasterizeThumbnail` opens a `dart:developer` `TimelineTask` (`thumbnail`,
  args page/pixelWidth/priority/reason) with instant markers splitting the
  render into `worker.record` → `rasterize` (worker path) or
  `local interpret+raster` / `worker declined → skip`. These are free when no
  trace is recording and appear in a DevTools Performance capture or
  `flutter run --profile`. Matching gated `PdfPerfLog` lines print the same
  per-phase ms under `--dart-define=PDF_PERF_LOG=true` (or `?perf=1` on the
  web demo).
- `PdfThumbnailCache` logs scheduler grants (`thumbnail grant page= focus=
  pending=`, also a `Timeline.instantSync`), warm activity
  (`thumbnail warm page=`), warm-yields-to-foreground, and the armed warm
  signature (`thumbnail warm armed pages= key=`, which carries the
  pixel-width bucket so a too-high grid resolution is visible at a glance).
- `reason` distinguishes on-screen tiles (`tile`) from the background warm
  (`warm`); only one thumbnail surface is mounted at a time, so grid vs strip
  is unambiguous from context.

All timeline events are unconditional (no-op when not recording); the
`PdfPerfLog` lines stay off unless the dart-define / `?perf=1` is set, so
tests and normal runs are unaffected.

## Follow-up 2: the page grid was starved by the viewer's preview prerender

A web perf trace of a ~50-page CAD document (`?perf=1`) showed the grid
taking ~1 min for the first 30 pages, every tile logging
`worker result page=N declined (null) → local` →
`thumbnail page=N tile px=320 local interpret+raster=140–965ms`. The same
page that *declined* for the thumbnail had just been interpreted fine by the
worker for a `prerender` — so the decline was **preemption**, not page
content: the full-area page grid (`PdfThumbnailView`) overlays the still-
mounted viewer, and the viewer's preview prerender (worker priority 1) kept
preempting every grid tile's worker request (priority 2). Net effect: each
visible grid page was interpreted **twice** — once off-thread for a preview
the user couldn't see (the grid covers the viewer), once on the **UI thread**
for the thumbnail (the local fallback) — and the prerender was warming pages
around the *viewer's* scroll position (25–47), not the grid's visible pages
(0–29).

Fix: pause the viewer's preview prerender while the grid overlays it —
`PdfEditorView` passes `PdfViewer(pagePreviews: !gridActive)`, and the viewer
resumes the prerender when the flag flips back (a new `didUpdateWidget`
branch, since previews were never togglable before). With the worker no
longer hogged, grid tiles are served off-thread (replay at tile resolution,
no second interpret, no UI-thread jank) nearest the grid's focus first.

Deliberately did **not** also raise the thumbnail tile's worker priority
above the prerender's: with priority 1 a tile would preempt an in-flight
prerender, and `renderPreview` falls back to a *local* (UI-thread) render on
a null/preempted result — that just moves the jank onto the viewer in the
docked-strip case. Pausing under the grid is the targeted fix; the absolute
fill time is still bounded by the per-page CAD interpret cost (1–11 s/page in
this document), which the worker can only do once each.

## Follow-up 3: pause the whole viewer under the grid, not just its previews

A second trace (worker now serving the tiles — follow-up 2 worked) showed the
grid's first tile still waiting `worker record=11882ms`: on a fresh 41 MB doc
the viewer was restored to page 31 and rendered its *on-screen* pages
(`interpret page=31/30/32`, 5–11 s each) at worker priority 0 before any grid
tile, even though the grid fully covers it. Pausing only the prerender didn't
stop these.

`PdfViewer` gained an `active` flag (default true); `PdfEditorView` passes
`active: !gridActive`. When false the viewer forces the render-scheduler hold
(its pages don't interpret) and bails the preview prerender, but stays laid
out — so the grid's tap-to-open still `jumpToPage`s it before the grid closes.
Held from the first frame (initState) for the persisted-grid-on-open case,
released + prerender-resumed when `active` flips back (didUpdateWidget); the
velocity tracker and settle timers OR their hold with `!active` so a paused
viewer never releases.

What this does NOT fix (and can't, cheaply): the raw per-page interpret is
~650–1600 ms each on a **single** web worker, serialized — so a 133-page CAD
document still takes ~100 s to fully warm on first open. The real levers are a
worker *pool* (parallel interprets) or persisting thumbnails to the on-disk
raster cache (instant re-open) — both larger, noted for a future session.

## Follow-up 4: parallel worker pool + on-disk thumbnail persistence

Ben opted into both levers above.

**Worker pool** (`PdfRenderWorkerPool`, render_worker.dart): itself a
`PdfRenderWorker`, holds N child workers and routes each `record` to the
least-busy one (tracked via a per-worker in-flight count), so up to N pages
interpret concurrently instead of queueing behind one. The reader and editor
build one via `startPdfRenderWorker(bytes, pageCount:)` —
`pdfRenderWorkerPoolSize` workers (default 3) for documents ≥
`pdfRenderWorkerPoolMinPages` (12), a single worker below that (the
parallelism has nothing to spread, and extra workers cost startup + memory).
Each worker opens its own copy of the document, so it's memory-for-throughput;
the size is a launch-time global like `pdfRenderWorkerScriptUrl`. On the
profiled 133-page doc this is the big first-open win — 3× fewer seconds to
fill, bounded now by 3 parallel interprets rather than one serial.

**Disk persistence**: `PdfRasterCache` gained `loadThumbnail`/`storeThumbnail`
under a resolution-tagged key (`$doc/t$pixelWidth/$page`), distinct from the
preview namespace. `PdfThumbnailCache` carries an optional `disk` the panels
set each build (bound to the document via `rasterCache.forDocument(key)`,
threaded from `PdfEditorView.rasterCache`). `rasterizeThumbnail` reads it
first (returns the stored PNG decoded, no interpret) and writes through after
rendering. **Gated to unedited pages only** (`pageRenderStamp == 0`): the disk
key is content-derived and render stamps reset per session, so persisting an
edited page would serve stale pixels on reopen — edited pages always render
fresh and skip disk. So a re-opened grid (or a later session of the same file)
paints already-rendered thumbnails immediately; only the *first* open pays the
interpret. Needs the host to supply a `rasterCache` (same one the viewer uses
for preview persistence); without it, session-only as before.
