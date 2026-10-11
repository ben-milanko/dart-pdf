# 2026-10-11 - parity harness precision (#999): zoom readiness, LoAF, per-process RSS, Chrome pin

#999 asked for the real-Chrome parity harness (`app/tool/perf/competitive.mjs`)
to measure the #997 zoom and #998 cadence fixes precisely enough to accept
them, with every change applied to both engines. This session lands the four
harness changes; the attribution passes it lists come next, on top of this.

## What changed

- **Zoom readiness is a historical timestamp.** The driver polled "zoom
  applied, page visible, not busy" about every 20 ms, so every
  `zoomReadySamplesMs` sample carried up to a poll interval of noise.
  - DartPDF: the harness (`app/tool/perf_harness/lib/harness.dart`) gains
    `__perfSetZoomTracked(scale, page)` / `__perfZoomReadyAt()`. It records the
    first frame end or `pageRenderActivity` change after the zoom at which the
    zoom has landed, the page is visible and `isPageRenderBusy` is false. Never
    before the first post-zoom frame: that frame's build is what asks the pages
    for the new geometry, so until then the scheduler is idle only because
    nothing has asked yet. (`debugRenderHold` is not needed: a request made
    under the hold is pending, so busy already reads true.)
  - PDFium: a rAF watcher in the viewer frame stamps the first animation frame
    whose `viewport.getZoom()` matches. PDFium exposes no render-idle signal,
    so its readiness stays "zoom applied", now frame-accurate.
  - Both timestamps also go to `settle()` as the ready time. A bundle without
    the hook falls back to the old poll.
- **Long Animation Frame attribution.** `installRafProbe` also observes
  `long-animation-frame` (page for DartPDF, viewer frame for PDFium); entries
  are read once each navigation, zoom and wheel action has visually settled
  (they reach the observer after their frame). `summarizeLongAnimationFrames`
  (competitive_common.mjs) gives count, total/blocking duration,
  script/render/style-and-layout time and the top scripts keyed on invoker,
  function and source URL, per journey in
  `runs[].diagnostics.longAnimationFrames`, each with `supported`.
- **Per-process RSS.** `processTypeRss` reads the renderer and GPU process
  types out of the existing `rssStages`; runs carry
  `renderer{Peak,Settled}RssBytes` / `gpu{Peak,Settled}RssBytes`, aggregated
  and ratioed like the browser total, printed but not budgeted.
- **Chrome build recorded and pinned.** `env.chrome` is now in the `chrome-*`
  `driver.mjs` envelopes too; `PERF_EXPECT_CHROME` (`154`, or a fuller prefix
  on a component boundary) makes both runners refuse any other build.

## First run (this container)

`tool/perf.sh competitive parity-plan --iterations 1`, Playwright's Chromium
141.0.7390.37, SwiftShader (software GL), 4 cores. The PDFium side *does* run
here - Chromium ships the PDF viewer - so the absolute numbers are only
container numbers (DartPDF raster is software, hence the 4-5x page/scroll
ratios), but every new field came out sane:

| zoom | DartPDF ready | DartPDF stable | PDFium ready | PDFium stable |
|---|---|---|---|---|
| 2 | 207.3 | 223.5 | 2.9 | 103.2 |
| 1 | 114.7 | 132.9 | 8.0 | 110.6 |
| 3 | 54.8 | 71.4 | 16.2 | 127.8 |
| 1 | 86.7 | 104.5 | 17.1 | 108.5 |

DartPDF's readiness lands one frame (~16 ms) before its visually stable
sample every time - the order it should have.

LoAF on DartPDF: navigation 24 long frames / 3.3 s blocking, of which
`FrameRequestCallback` 3.2 s and `Worker.onmessage` 1.3 s script time (the
worker-reply path #998 targets); zoom 7 / 0.26 s; scroll 26 / 1.9 s.
PDFium: `supported: true`, zero long frames on every journey - its raster runs
in the plugin process, outside the observed frame, and the viewer's own JS is
light. So LoAF attributes main-thread work, which is exactly DartPDF's cost.

Per-process (MiB, peak): renderer 938 vs 654 (1.43x), GPU 343 vs 117 (2.93x),
browser total 1720 vs 1235 (1.39x).

## Gotchas

- **Flutter's work is one rAF callback.** LoAF names `FrameRequestCallback`
  in `main.dart.js` with an empty function name (minified dart2js), so it splits
  frame work from worker-message handling and input listeners, not frame work
  from itself. `flutterFramesByAction` (build/raster per action) remains the
  finer split; `sourceCharPosition` is kept in the raw entries for a source-map
  lookup.
- **`supported` distinguishes zero from unknown.** A frame without LoAF
  support reports `supported: false`; a journey with no actions leaves it
  `null`.
- **`renderer` sums every renderer process in the tree** - DartPDF's tab, and
  for PDFium the tab plus the viewer frame's process. It cannot isolate one tab,
  but it takes the browser, utility and GPU processes out of the comparison.

## Next (#999's attribution passes)

Per-zoom timeline (console + FrameTiming + screencast), page-stable phase split
on the book scenario, a refreshed offline phase split, and SkWasm on
`parity-plan` in screenshot mode for #1000 - all on Chrome 154 with
`PERF_EXPECT_CHROME=154`.

## Files

- `app/tool/perf/competitive.mjs`, `competitive_common.mjs` (+ tests),
  `driver.mjs`, `README.md`
- `app/tool/perf_harness/lib/harness.dart`
- `tool/perf/SCHEMA.md`
