# Rendering through the scroll, and keeping what we rendered (#long-doc)

The report: on a long text document, scrolling through it and watching the
pages arrive feels slow next to PDFium, which shows content essentially as
fast as you can scroll. "Be greedier with the render and with what details
are saved."

## What the trace actually said

Added a `read` scenario to the web harness
(`app/tool/perf/scenarios.json` → `read-text`/`read-booklet`/`read-plan`,
harness `_driveRead`) because none of the existing ones measure the thing
being complained about: it arrives on each page in turn, waits for that
page's **sharp** raster (`PdfViewerController.isPageRasterReady`), then
reads back through the pages it just visited. Forward latency is
scheduling; backward latency is retention. It reports both, plus the share
of arrivals that needed no render at all (`readBackInstantPct`) and - added
after the first round - the part of the wait that comes *after* the
navigation animation lands (`read*SettleP50Ms`), which is the number a
render that runs during the scroll drives to zero.

Baseline on `text-report-40p.pdf`, 24 pages out and back:

```
readFirstP50Ms 609   readFirstInstantPct 0.0
readBackP50Ms  476   readBackInstantPct  4.3
```

A verbose trace of one page arrival explains all of it:

```
2950  renderHold ON (jump begins)
3309  scroll ... v=354px/s hold=ON        <- 360 ms of held rendering
3313  jump-focus settle / renderHold off (pending=1)
3342  scheduler grant page=3
3374  webworker result page=3 (record total=31ms, of which transfer=30ms)
3386  interpret page=3 path=worker FIRST interpret=43ms
3414  page-ready page=3
```

The page itself costs ~70 ms. The other ~360 ms is the render hold: nothing
starts until the scroll settles. And the pages behind it were no cheaper -
`scene-cache` showed 9 stores and 1 hit over a six-page journey, because the
retained-scene LRU was capped at **4 entries for the whole document**.

## Why the hold was over-priced

The hold exists because a dense sheet's interpret walk is 100-400 ms of UI
thread inside a fling. Two facts make it far too broad:

- With a render worker attached the walk does not run on the UI thread at
  all. *Starting* a page during a scroll costs the frame nothing.
- What does run here is the replay of the returned command buffer - and by
  then its size is known. No guessing needed.

So `PdfPageRenderScheduler` gained a **motion-safe lane**. A request may
declare itself `motionSafe`, and the caller re-declares it at `paceUiWork`
once the record has landed. Motion-safe work is granted during a hold, one
per frame (`motionSafeGrantsWhileHolding`), and several may start per frame
once settled (`motionSafeGrantsPerFrame`, 3 - their walks are in the
worker). Everything else keeps the old behaviour exactly: held, then one per
frame, and a *held-class* focus render still parks its neighbours.

`PdfPageView` answers the question in two halves, at the two moments they
can be answered honestly (`motionSafeRenders`, default on):

1. **At request time** - a live worker, and no page-level `/XObject`. A
   three-operator content stream can hide megabytes of image behind an
   XObject, and that cost is unknowable before the record lands.
2. **When the record lands** - at most `motionSafeMaxCommands` (4000) and
   no image draws.

Two holes had to be closed, both found by the tests rather than by
inspection:

- A pass that **falls through to a local interpret** (the worker declined,
  or `forceLocal`) revokes the verdict on the spot - that walk is on the UI
  thread and belongs behind the hold. Without this an inline-image page
  rendered mid-fling, because the record path never ran.
- A page rendered during a scroll routinely finishes **before it is on
  screen**, and `canPresentPictureDirectly` requires `onScreen` - so it fell
  to the raster branch and paid a full-page GPU readback plus a retained
  multi-megabyte image, for pixels the direct presentation would replace
  moments later. That was worth **+200 MB** on its own. It now hands itself
  to the existing `_deferredOffscreenRasterRefresh` hook and presents its
  display list when it genuinely arrives.

## The retention half, and a byte budget that was lying

Raising the retained-scene cap from 4 to 32 made scroll-back instant and
took the tab from 79 MB to 282 MB. Setting the cap back to 4 with everything
else in place returned it to 76 MB, which named the culprit exactly: the
LRU's byte estimate. A 38-command text page priced at ~0.5 MB
(`commands*260 + Picture.approximateBytesUsed`) and measured at ~9 MB of
browser heap - the engine does not count the shaped text and path objects a
retained picture holds. The budget was not generous, it was meaningless, and
it fed the same fiction to the process-wide `PdfCacheRegistry` the host's
memory governor drives.

`PdfPagePreviewCache.priceRetainedScene` now floors an entry at the raster
it stands in for (the page's own WxHx4 at display resolution). That is what
keeping the page's pixels would cost, it scales with page size and zoom by
itself, and it lands within ~20% of measured agent memory. With honest
prices the budget governs again, so the entry cap goes back to being a
backstop (32) and the budget becomes platform-aware like its neighbours in
`performance_policy.dart` (`pdfDefaultRetainedSceneBytes`: desktop 128 MB,
mobile/web 64 MB ≈ eight ordinary pages).

## Result

`tool/perf.sh webdiff e574c87 read-text`, three interleaved runs, same
harness both sides (40-page text report, 24 pages out and back):

| metric | baseline | now |
|---|---|---|
| readFirstSettleP50Ms (wait after the page stops moving) | 207 | **0.05** |
| readBackSettleP50Ms | 196 | **0.03** |
| readFirstP50Ms (whole arrival, incl. the 250 ms animation) | 614 | 477 |
| readBackP50Ms | 482 | 334 |
| readBackInstantPct (already sharp on arrival) | 4.3 | **100** |
| readFirstInstantPct | 0.0 | **69.6** |
| buildP50 / buildP95 | 2.22 / 6.04 ms | 2.83 / 5.67 ms |
| tab memory | 79.9 MB | 113.5 MB |

The settle numbers are the honest statement: the wait after the page stops
moving is gone, and what is left in the totals is the navigation animation
itself. `read-plan` - the 16-sheet CAD arm, the pages the pacing exists for -
moves the same way: readFirstP50 586 → 385 ms, readBackP50 609 → 375 ms, 91%
of revisits sharp on arrival, for +5.6% tab memory.

What it costs, stated plainly:

- **~34 MB on a text document** (`scroll-text` and `read-text` both +42%),
  which is the retained-scene budget actually being spent. It is bounded by
  `pdfDefaultRetainedSceneBytes`, priced honestly for the first time, and
  registered with `PdfCacheRegistry`, so a host under pressure reclaims it.
- **A busier median frame**: buildP50 +12% to +27% across the arms, from
  2.2-3.2 ms to 2.8-3.7 ms against a 16 ms budget. p95 is flat or better and
  `scroll-plan`'s jank count fell 22%, because the work moved off the
  post-scroll cliff and into frames that had room.
- `scroll-plan` renders **16 sheets where it used to render 9** over the same
  sweep. That is not overhead, it is the point.

The one place greed had to be walked back is the fling. An unbounded lane
recorded *every* sheet a fast scroll flew past: on `scroll-plan` that was
+34% tab memory and +21% median build for latency nobody waited on, since the
reader was navigating somewhere else. `motionSafeHoldRadius` (1) grants only
around the destination while a scroll is in flight - and a jump sets `focus`
to its target before the animation starts, so that is the destination and not
wherever the scroll is passing. With it, `scroll-plan` memory lands at +7.5%.

## Gotchas for next time

- `PdfPageRenderScheduler.holding` is not only a gate at the start of a
  pass: `_renderPaused` is checked repeatedly *inside* `_renderNow`, so a
  render that starts during motion also has to be allowed to finish. That is
  why the verdict lives on the pass (`_motionSafePass`) and not on the
  request.
- The command buffer at the pace point is not the buffer you counted from
  the content stream - a classic three-operator page reaches it as one
  command. Ceilings in tests must be set against what the trace shows, not
  what the fixture reads.
- A pass that starts during a hold and then learns its record is held-class
  does not abandon the record: it parks in `paceUiWork` and replays the
  moment the scroll settles. That is one worker round trip where the old
  path took two (`render_worker_test.dart`'s hold-resume test now pins the
  single record), and `_recordKnownHeld` stops the page speculating again on
  the next hold.
- `bench.mjs` copies today's `tool/perf` into the baseline worktree but not
  `app/tool/perf_harness`, so a *new* scenario silently falls back to
  `scroll` on the baseline side and the A/B compares two different
  workloads. Fixed here; watch for it if an A/B's baseline column shows
  metrics your scenario does not emit.
