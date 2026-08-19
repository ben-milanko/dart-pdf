# Thumbnails and preview LoDs reuse work the viewer already did (#699)

The field trace on #699 (113-page corporate report, scrolled in the web app
after #698's motion-safe lane landed) put the two background surfaces above
the document itself in platform-thread cost over a ~10 s window: 1525 ms of
thumbnail tiles and 523 ms of preview-LoD warms against 584 ms of actual page
interprets, with 49 of 58 janked frames raster-dominated. Both numbers were
spent re-deriving something the viewer already had.

## The preview ladder walked the page once per rung

`PdfPagePreviewCache.renderPreview` produced exactly one raster per call, so
the viewer's prerender loop - which selects one page and one rung at a time -
walked the same content stream for base, then again for 400px, then again for
800px:

```
prerender page=107 lod=base  full warm=108.9ms
prerender page=107 lod=400px full warm=56.6ms
prerender page=107 lod=800px full warm=61.1ms
```

The rungs differ only in raster size. `renderPreview` now takes
`alsoFillLongestSides`: it collects the rungs that are missing, records the
page **once** at the sharpest rung's image resolution, and rasterizes every
rung from that one `ui.Picture`. A rung that rode along on another rung's
record prints a `shared` token in its `prerender` line and a `warm=` that is
its own raster only, so a trace still says what each rung cost.

The viewer decides what rides along (`_ladderRungsFor` in pdf_viewer.dart):
the still-missing intermediate rungs of a page inside
`PdfPagePreviewLodPolicy.intermediateWindow`. Vector-first motion passes stay
base-only - intermediates are image-complete by construction.

**Selection policy is unchanged, arrival order is not.** The loop still picks
the nearest page missing a base preview first; what changed is that a base
render for a page in the tight LoD window now also yields that page's sharper
rungs, since they cost only their own raster once the page is interpreted. A
far page's base preview therefore lands a couple of downscale rasters later
than before. `idle prerender promotes only the nearby LoD working set` in
page_preview_test.dart had to wait on both conditions instead of racing them;
its assertions (page 4 base-covered, page 4 without intermediates) still hold.

## A 128px thumbnail cost a whole page interpret

With no active worker `rasterizeThumbnail` fell through to
`PdfPageRenderer.renderImage`, walking the entire content stream to fill a
128px tile - for a page the viewer had interpreted seconds earlier and still
held a retained scene for:

```
[perf 1005] scene-cache store page=74 commands=739 …
[perf 1337] thumbnail page=74 tile px=128 local interpret+raster=55.4ms (no worker)
```

`rasterizeThumbnail` now takes the viewer's `PdfPagePreviewCache` and tries
its retained scene first - ahead of the worker, which is a strictly more
expensive way to obtain the same commands. A hit is a replay plus the tile's
own (tiny) raster: no content-stream parse, no image codec, and a
`thumbnail … retained replay+raster=` line in place of the
`local interpret+raster=` one.

What the lookup has to get right is that "the same display" is not the same as
"an identical `PdfPageRenderPlan`". Two of the plan's inputs have spellings
that coincide, and `_retainedSceneForTile` tries both:

* **Rotation.** A plan carrying the page's own /Rotate and a plan carrying
  null are the same render, and different producers write different ones - the
  viewer always resolves an explicit angle, a bare `PdfPageView` may not.
* **Annotations.** This is the one that decides whether the optimization fires
  in the app at all. The viewer bakes annotations into the page picture only
  when it is *not* drawing them in a live overlay layer
  (`_pageImagesShowAnnotations`), and an editing session - which is when the
  thumbnail strip exists - always uses the overlay. So its retained scenes are
  annotation-free while the strip asks for annotations, and without this the
  hit rate in `PdfEditorView` would be zero. On a page that carries no
  annotations the two are the same pixels, so only such a page tries the other
  spelling; an annotated page still renders itself.

A view rotation, another paper colour, or annotations on a page that has some
all miss, as they should, and every path below is unchanged.

**Image LoD** is the other guard: a scene whose images were decoded below the
tile's own ratio would draw them softer than a fresh render, so those decline.
A tile ratio is a fraction of any display ratio, so it is a guard, not a
common case.

The warm pass reuses a scene too: `skipIfWorkerDeclines` means "do not start a
heavy UI-thread interpret", not "ignore a page that is already recorded". The
motion gate still applies - a replay is cheap but is still platform-thread
work, so a tile waits for the scroll to settle.

## Measuring

`test/benchmark_background_surfaces_test.dart` prices both halves on the VM
(synthetic text/CAD profiles plus the committed
`test_corpora/dartpdf/letterhead-report-40p.pdf`, the document class the issue
names) and fails if either reuse stops paying:

```
background-surfaces ordinary: pages=4 ladderPerRung=17.3ms/page
  ladderOneRecord=2.8ms/page (-84%) tileLocal=2.2ms/tile tileRetained=1.2ms/tile (-44%)
background-surfaces cad-vector: pages=1 ladderPerRung=886.9ms/page
  ladderOneRecord=317.1ms/page (-64%) tileLocal=173.1ms/tile tileRetained=159.4ms/tile (-8%)
background-surfaces letterhead-report: pages=6 ladderPerRung=37.1ms/page
  ladderOneRecord=17.5ms/page (-53%) tileLocal=9.7ms/tile tileRetained=7.6ms/tile (-22%)
```

Read the tile column knowing what the VM leaves out: there the 128px readback
dominates a tile, so removing the interpret is worth 22% on the letterhead
report; on the web, where the trace measured a whole tile at 55 ms, the
interpret is the bulk of it. The CAD row is the honest floor - a
20k-command transcript costs about the same to replay whoever recorded it, so
reuse buys 8% there.

The web half is the real-Chrome harness. `scroll-text` is the scenario that
actually warms previews - `wheel` and `read` keep moving, and the prerender
loop needs a full second of idle on web, so neither ever starts it.
`tool/perf.sh webdiff e4dafb9 scroll-text --iterations 3`:

```
metric                  baseline    current     Δ         verdict
agentMemoryBytes        112953482   111146987   -1.6%     ·
buildMax                43.89       45.55       +3.8%     ·
buildP50                2.54        2.73        +7.5%     ·
buildP95                6.88        6.50        -5.5%     ·
jankCount               174         167         -4.0%     ·
openBytesMs             234         243         +3.8%     ·
openDocMs               238         247         +3.7%     ·
openPageCountMs         491         526         +7.1%     ·
✓ no metric regressed past 1.1×
```

The scenario has no metric for what a preview rung costs, so read the warm
counts instead: full ladder rungs completed inside the same ~31 s window went
9/9/9 (baseline) to 11/14/13 (current) - the same interpret budget producing
about 40% more rungs - while janked frames fell 4% and agent memory 1.6%. Note
this scenario is worker-backed, so the record was already off the platform
thread; what one rung still costs there is its own CanvasKit readback, which no
amount of reuse can remove. The worker-less session the issue traced is the
larger win, and the thumbnail half has no web coverage at all: the perf harness
has no thumbnail strip.

The `open*` triple drifting ~4% is the harness, not this change:
`openBytesMs` is fetching the file's bytes, which no code here touches, and it
moved with the other two.

Fixing the driver was part of getting these numbers: `prerender warms` had been
reporting 0/0 on every scenario since the ladder added its `lod=` token to the
line the regex matched.

`page_preview_test.dart` and `editing_thumbnail_cache_test.dart` pin the
mechanism rather than the timing, by counting tokenized content operations
(`PdfPerfCount.contentOps`): the ladder tokenizes the page once where three
per-rung calls tokenize it three times, and a tile served from a retained
scene tokenizes nothing at all.

## Still open from the same trace

The issue reports two further findings, deliberately left alone here:

* **The exact page-raster cache is inert on that document** (163
  `page-raster miss … reason=empty` lines, zero stores, against an idle
  256 MB budget). The likely gate is `putFullImage`'s
  `_renderedAtFullImageRatio()` refusing a page that rendered as a prefetch
  neighbour at half image resolution and then never re-rendered because its
  raster was already current.
* **The session had no render worker at all** (`path=recorded(no-worker)`),
  which is why all of this landed on the UI thread. The suspected cause is a
  deploy serving `main.dart.wasm` alongside a dart2js-only worker asset - the
  pairing `render_worker_web.dart`'s own comment names as the hazard.

Neither is worker-specific to this fix: the ladder's repeated walks cost the
same on every platform, and the thumbnail reuse removes the interpret whether
or not a worker exists.
