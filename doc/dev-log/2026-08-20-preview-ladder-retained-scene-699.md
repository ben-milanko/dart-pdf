# The preview ladder reuses the page the viewer is holding (#699)

[#700](https://github.com/ben-milanko/dart-pdf/pull/700) took the first half of
#699's proposed fix: build the page once. The preview ladder stopped walking
the content stream once per rung, and `rasterizeThumbnail` learned to replay
the viewer's retained scene instead of interpreting a whole page to fill a
128 px tile.

The other half of that same sentence was left undone. The issue asked for the
picture to be built "**preferring the page's retained scene when
`PdfPagePreviewCache` already has one**, else one local walk" - and the ladder
only got the "one local walk" part. It still interpreted, once per page, a page
the viewer had interpreted seconds earlier and was still holding.

This session closes that, and resolves the issue's two side findings: one of
them turned out to have a different cause than the issue guessed, and it is the
same cause that made the ladder's interpret matter at all.

## The ladder now tries the retained scene first

`renderPreview` had three ways to obtain a picture and reached for them in the
wrong order of cost:

1. `worker.record(...)` - interpret off-thread, transfer the command buffer,
   rebuild the picture on the platform thread;
2. `renderPictureRecordedWithPlan(...)` - interpret *on* the platform thread;
3. nothing else.

A retained scene is strictly cheaper than either. It already holds the exact
commands a worker record would ship back, with the images already decoded, so
serving a rung from it costs a flat replay plus that rung's own raster: no
content-stream walk, no wire transfer, no reconstruction. `renderPreview` now
asks `_retainedSceneForPreview` before it asks the worker, and rasterizes every
rung of the ladder from that one picture (or, when the cache entry kept the
page picture beside its scene, from the picture itself - not even a replay).

A rung served this way prints a `retained` token in its `prerender` line, so a
trace still says where each rung came from.

Two guards, and the second is the one the correctness rests on:

* **Image LoD.** A scene whose images were decoded below the sharpest rung's
  ratio would draw them softer than a fresh record, so it declines and the
  ordinary paths run. Rungs sit at or below 1x while a display scene is decoded
  at the page's own display ratio, so this is a guard rather than a common
  case.
* **Vector-first warms keep their worker-only contract.** Those exist to put
  *some* pixels up during a fast scroll with no main-thread render at all. A
  replay is cheap but is not nothing, so `decodeImages: false` never takes this
  route; it serves the full warms, which is what the #699 trace measured
  (`prerender ... full warm=`).

Plan matching is shared with the thumbnail half rather than duplicated:
`_retainedSceneForTile` had grown the rule that "the same display" is not "an
identical `PdfPageRenderPlan`", and that rule now lives on the cache as
`PdfPagePreviewCache.retainedSceneForDisplay` with both callers on it. Moving
it also tightened it: rotation's two spellings are interchangeable only when
the caller asks for null or for the page's own /Rotate. A *view* rotation is a
different render and now tries nothing but itself, where a literal copy of the
tile helper would have handed it the unrotated scene.

## Why the exact page-raster cache is inert - one cause found, one still open

The issue's second finding was 163 `page-raster miss ... reason=empty
retained=0 entries=0` lines with zero stores and zero hits against an idle
256 MB budget, and it reached for `putFullImage`'s `_renderedAtFullImageRatio`
gate refusing a prefetch neighbour that never re-rendered.

On the document that trace came from, that is not the cause.
`_baseRasterIsCurrent` mirrors that comparison deliberately, so a neighbour
whose images are soft does re-render when it comes into focus. The cause there
is one level up: **those pages never produce a base raster at all**.
`PdfPageView.directPicturePresentation` (on by default, and the route any page
under 5 000 commands takes - the trace's page 74 has 739) presents the
completed display list instead of flattening it through `Picture.toImage`, and
returns before the branch that calls `putFullImage`. No readback, so no raster,
so nothing can ever reach the tier and every lookup necessarily misses.

Reproduced directly, and now pinned by `a page presented directly never seeds
the exact raster tier` in `pdf_page_view_test.dart` - a test that has to turn
`directPicturePresentation` back on, because `flutter_test_config.dart` pins it
off for the whole suite, which is why nothing caught this.

That is working as designed: skipping the readback is the entire point of the
route, and within a session the retained scene is the tier doing the
"revisits are free" job instead. The budget is not stolen either - the
process-wide `PdfCacheRegistry` ceiling is enforced against live occupancy, and
the app's Auto memory mode only reserves a page-cache floor while a warm policy
is active.

**It does not explain every session, and the original hypothesis is not dead.**
A later field trace of a different document shows pages that *do* take the
raster route - `raster kind=base-full page=121 n=2 full ratio=1.1 img=895x633`
- with the tier still reading `retained=0 entries=0` fourteen seconds and two
`page-raster mode=auto` reconfigurations later, both reporting
`trimmedEntries=0` (so nothing was admitted and then evicted; nothing was ever
admitted). On that session `_renderedAtFullImageRatio` is back in play as a
candidate: it wants `_pictureImageRatio >= _effectiveRatio() *
focusedImageDecodeHeadroom`, i.e. roughly 2.2 where that raster was produced at
1.1, and the same trace shows the codebase carrying sub-1 image ratios on this
document (`scene-cache reject page=121 reason=image-lod have=0.63 need=1.00`).
That is a consistent story, not a proven one - it needs a test that drives a
page down the raster route and asserts a store - so this section claims only
what the first trace proves, and leaves the second open.

**But it is directly connected to the first half of this issue.** `putFullImage`
is also what fills the preview ladder for free
(`_putIntermediateLadderFromImage` blits every configured rung out of the
raster that just landed). A document whose pages present directly never gets
that, so on exactly these documents the ladder has to warm itself from scratch
- which is the `prerender ... full warm=` cost the trace measured. The change
above gives that back from the scene instead of the raster.

## Measuring

`test/benchmark_background_surfaces_test.dart` gained a third ladder column,
priced the same way as the tile: the record is outside the clock because the
viewer paid for it when the page was on screen.

```
background-surfaces ordinary: pages=4 ladderPerRung=22.0ms/page
  ladderOneRecord=2.9ms/page (-87%) ladderRetained=2.8ms/page (-87%)
  tileLocal=2.0ms/tile tileRetained=0.6ms/tile (-72%)
background-surfaces cad-vector: pages=1 ladderPerRung=1358.8ms/page
  ladderOneRecord=400.1ms/page (-71%) ladderRetained=330.3ms/page (-76%)
  tileLocal=226.8ms/tile tileRetained=168.5ms/tile (-26%)
background-surfaces letterhead-report: pages=6 ladderPerRung=58.8ms/page
  ladderOneRecord=30.2ms/page (-49%) ladderRetained=27.4ms/page (-53%)
  tileLocal=11.8ms/tile tileRetained=10.1ms/tile (-15%)
```

Read the letterhead column knowing what makes it small on the VM: that page is
792 pt tall against an 800 px rung, so `buildRatio` is 1.0 and the record this
removes was decoding images at that same ratio anyway. What is left is three
rasters, which no reuse can remove, and across repeated runs the two ladder
columns there land within noise of each other. The CAD sheet, where the
interpret dominates, gains 17% over one record; ordinary text pages are already
down at 3 ms.

Which is why the retained columns are **gated on the interpret, not the
clock**: `PdfPerfCount.contentOps == 0`. That is the thing the reuse actually
removes, it is the same number on every machine, and the wall-time column on a
fast host is close enough to buy a flake rather than a signal. Rung-per-call
against one record keeps its wall-time gate - that saving is an interpret per
rung and is large on every profile.

Getting those numbers honest took one correction worth recording. The first
version timed the retained runs with `PdfPerf.enabled`, which turns every phase
in the render/raster stack into a live `Stopwatch`, and compared them against
uninstrumented ones - reporting the reuse as a *regression* on the letterhead
report. Both retained helpers now run twice: the clock in an uninstrumented
pass, the operation count in an instrumented one.

### The web half

The VM benchmark prices the mechanism; the browser is where the issue's cost
was measured, so the change was A/B'd in the real-Chrome harness too.

`scroll-text` - the scenario #700 used - moved nothing either way. It is
worker-backed, so the record the reuse removes was already off the platform
thread, and two identical `webdiff origin/main scroll-text --iterations 3` runs
disagreed on the *sign* of every small delta (the `open*` triple, which is
fetching the file's bytes and which no code here touches, drifted ±8-12% on its
own). That scenario cannot answer this question.

So this adds **`scroll-letterhead-noworker`**: the corporate-report shape
scrolled with `worker=0`, which is the condition the field trace was actually
captured in - every interpret and every ladder warm on the platform thread. A
scroll rather than a wheel because the idle prerender needs a full second of
quiet on web, which a continuous wheel never gives it.

```
══ scroll-letterhead-noworker: origin/main (71ae240) → working tree, 3 interleaved runs
agentMemoryBytes  101625550  101591420  -0.0%     buildP95   11.65  11.22  -3.6%
buildMax               64.59      65.81  +1.9%     jankCount    170    168  -1.2%
✓ no metric regressed past 1.1×
```

No scenario metric moves, and none should: the harness has no metric for what
a preview rung costs, and the ladder runs in idle time that the frame stats do
not price. What the trace lines say, across three runs of that scenario, is the
thing the change is about - the **base** rung is the one that pays the
interpret, and the rungs riding along on it print `shared`:

```
  path        n   median    range
  interpret   9   199.2ms   180.7 - 241.3
  retained    6   131.2ms   118.2 - 152.6      -34%
```

Non-overlapping, in headless Chrome where the CanvasKit raster - which no
amount of reuse can remove - is the rest of the number. The `retained` token in
the `prerender` line is what makes this readable; `driver.mjs`'s warm-counting
regex accepts it, as it already does `lod=` and `shared`.

## The third finding: no render worker at all

The issue's last finding - `path=recorded(no-worker)` on every page for the
whole session - is a deploy question, and it is the one this session could not
settle: confirming it needs the `webworker …` lines a `?perf=1` trace emits at
document open, which we do not have. Two things did come out of looking:

* **No workflow builds the app with `--wasm`, and a JS build emits no
  `main.dart.wasm`.** `deploy-app-web.yml`, `preview-app-web.yml`,
  `release-app.yml` and both demo workflows build the default JS/CanvasKit
  renderer, and `deploy-demo-web.yml` says why. `flutter build web` does run a
  dart2wasm *dry run* (on by default), but the build directory it produces
  holds `main.dart.js` and no `main.dart.wasm` - checked on this machine. So
  the wasm/JS pairing the report describes is not what these workflows deploy.
  The claim in `doc/render_worker_web.md` that the live deploys "ship the
  `--wasm` renderer" was stale, and is corrected - it is plausibly where the
  belief came from.
* **If one ever did, the worker would silently rot.** `tool/web_cache_bust.sh`
  gives the worker URL a `?v=<content hash>` by rewriting the string literal in
  the compiled output, which is what lets hosting serve `assets/**.js` with a
  year of `max-age`. dart2wasm does not store string literals as plain UTF-8 or
  UTF-16 in the module - a `dart compile wasm` of a program holding this very
  URL contains no byte sequence matching it in either encoding - so under
  `--wasm` the reference can be neither rewritten *nor detected by the
  assertion that exists to catch exactly this*. The deploy would ship the bare,
  stable URL under an immutable year-long cache, and a browser that once
  fetched the committed placeholder (which throws on load) would render every
  page, image decode and thumbnail on the main thread from then on - visible
  only in a trace.

  The script now refuses a build directory containing `main.dart.wasm`, naming
  the two remedies (build without `--wasm`, or serve the worker with
  revalidation and re-run with `WORKER_URL_REVALIDATED=1`).

That closes the invisible-failure hole. Whether the traced session hit it, or
something else stopped its worker, still needs the trace.
