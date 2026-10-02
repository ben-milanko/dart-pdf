# Deep zoom no longer loses its scene to a superseded image refine

The web Patrol perf journey "deep-zooms an image-heavy CAD sheet through
worker-backed tiles" failed intermittently in the Preview Demo Web job. Over
three days, at least one performance repetition failed in 3 of about 20
runs, each time with `deep zoom should adopt image detail and land CAD
tiles`. It was not slow timing. It was a product race, and anyone who zoomed a
cold, image-heavy dense page at the wrong moment could hit it: that page never
got tiles or region image detail, and every pan re-rendered a full-viewport
picture instead.

## The race

The document's first cold visible page decodes its images at 1x when the
worker is active and the performance controller has no observations yet
(`_imageRatioTarget`). That keeps first content cheap. Once that raster is on
screen, `_scheduleFocusedImageRefinement` drops the picture and the retained
scene (`_dropPicture`; the raster stays up as backing) and asks for a second
record at the 2x focused decode (`image-refine page=0 have=0.31 need=0.61`).

In the failing repetitions, the zoom landed while that refine was still
recording:

1. The scale change invalidates the full-render generation
   (`PdfPageRenderSession.update`). The refine pass threw its finished record
   away at its next `_superseded` check.
2. The zoom's own request had been deferred behind the in-flight refine
   (`scheduler defer page=0 (render in flight)`). When the scheduler re-granted
   it, `_renderNow` asked `_baseRasterIsCurrent()`. Past the full-page raster
   caps (`needsDetail`), that check deliberately stops comparing the raster's
   image ratio, because the detail path supplies the sharp pixels. So the stale
   1x-image raster read as current: `render skip reason=base-current`.
3. Nothing rebuilt the picture or the scene after that. Every detail request
   logged `scene=false tiles=no-scene`, the tile path never ran, and no region
   image detail was adopted.

In the passing repetitions the page's first record had already decoded at 2x,
so there was no refine to race.

## What changed (`pdf_page_view.dart`)

- **`_imageRefinePending`.** Set when the refine drops the picture. Cleared by
  `_dropPicture` and when a full pass installs its interpreted picture. While
  it is set, the page has no picture, and the page is on screen and
  quality-visible, `_baseRasterIsCurrent()` answers false. The re-grant then
  records the page again instead of skipping, which is the record the refine
  already asked for. Any other path that puts a picture back (a retained-scene
  cache hit) makes the `_picture == null` clause false, so the flag cannot turn
  later re-grants into repeat re-rasters. The guard uses the refine's own
  preconditions (on screen, quality-visible). A page that has left the quality
  foreground keeps the old answer and does not re-record at a reduced ratio;
  the debt comes due when it comes back.
- **`_renderNow` decides both exits before claiming a generation.** The paused
  re-queue and the base-current skip (which still calls `_updateDetail`) now
  run before `beginFull()`. Only a pass that will actually render may
  supersede in-flight work. Three things moved below the exits: `beginFull`,
  the first-interpret `_lastInterpret*` resets (read only at the end of the
  proceeding path), and the pass Stopwatch. `_motionSafePass` is still set at
  the top, so the paused decision and the skip's detail refresh see exactly
  what they did before.

  Under the scheduler, one page's passes never overlap, and the zoom's scale
  change supersedes the refine by itself. So this reorder is not what closed
  the race; the ablation below shows the guard alone does. It removes a second
  way to lose finished work: a no-op pass killing an overlapping pass on a
  bare-hold host (no scheduler), or a persistent-tier disk restore that holds
  `fullGeneration` unclaimed.

Kept as is: the cold 1x-then-refine policy, `needsDetail`'s meaning everywhere
outside the refine window, and every pixel a pass produces. The only
behavioural change is a skip turning into the re-record the page already owed.

## Regression test

`test/image_refine_supersede_test.dart` reproduces the race
deterministically in flutter_tester:

- A real worker (`PdfRenderWorker.startUncached`) is wrapped so the refine's
  record is held. The refine is the first full-page record that asks for more
  than 1.5x the cold image ratio.
- The page is a wide synthetic CAD strip: 18 image tiles and 6000 operators in
  4 streams, 2600 px wide at 1x, with `baseRasterScale: 1`.
- A fresh `PdfPerformanceController` (0 observations) makes it the document's
  first cold page.
- The test asserts the cold record was at the exact footprint and the refine
  at 2x. It zooms to 4 under a `PdfPageRenderScheduler` while the refine is
  held, asserts the zoom was deferred behind it, then releases the hold.
- It then expects a re-issued full record, a `detail request ... scene=true
  tiles=active` line, tile image-detail adoptions > 0, tiles landed, the tile
  layer present, and no `tiles=no-scene` after the refine.

Before/after (5 runs each):

- origin/main: 5/5 fail with the CI trace, `image-refine have=0.31
  need=0.61`, then `scheduler defer`, then `render skip reason=base-current
  ratio=0.31`, then `scene=false tiles=no-scene`.
- This branch: 5/5 pass, with no base-current skip in that window.

Ablation on origin/main (3 runs each):

- The generation reorder alone still fails, 3/3.
- The guard alone passes, 3/3.

`render_hold_test`'s deferred re-grant case still gets exactly one base-full
raster and a visible base-current skip.

## E2E diagnostics (`example/patrol_test/perf_e2e_test.dart`)

- The combined wait is now three cumulative waits: tile layer present, then
  image detail adopted, then tiles landed. A failure names the step that never
  happened.
- Each failure reason carries the observed counters and the page's last
  `detail request` line (captured through an additive `PdfPerfLog.sink`), so
  `tiles=<status>` is in the log.
- `attempts: 360` is replaced by a 60 s wall-clock budget. Once a
  multi-megapixel detail picture is on screen, each 100 ms pump costs about
  300 ms in CI, so 360 attempts had quietly become about 125 s. In the passing
  CI repetitions, zoom to `phase=validated` took about 9-11 s, and that
  includes the three window visits.
- The convergence time is printed on success.
- The assertion is unchanged and there are no whole-test retries.

## Not verified locally

The Patrol web run needs a browser harness and a web build, so it was not run
here. The PR's Preview Demo Web job is the end-to-end check: its performance
repetitions should never show `tiles=no-scene` after an `image-refine` line.
The VM counter gate (`tool/perf.sh gate`) is unchanged.
