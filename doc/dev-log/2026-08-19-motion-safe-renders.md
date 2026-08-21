# Rendering through the scroll, and keeping what we rendered (#long-doc)

The report: on a long text document, scrolling through it and watching the
pages arrive feels slow next to PDFium, which shows content essentially as
fast as you can scroll. "Be greedier with the render and with what details
are saved." Follow-up, after the first round: *"I can scroll as fast as I
want in PDFium and the content is there instantly; on DartPDF I scroll two
pages then wait ~0.5 s."*

That follow-up is the important one, and it exposed a measurement mistake
worth recording before anything else: the first round was measured with the
`read` scenario, which navigates page to page with `jumpToPage`. A reader
does not navigate, they **drag the document past the viewport**, and the two
journeys turned out to be gated by completely different things. The
`jumpToPage` numbers improved a lot while the actual complaint barely moved.
The `wheel` scenario below is the workload the report describes; when in
doubt, measure the gesture the user made, not the API that resembles it.

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

## What actually gated a continuous scroll

`wheel-text` (pointer scroll signals at frame cadence, sampling every frame
which pages are visible and which of those are sharp) reproduced the report
exactly on the pre-change tree:

```
wheelSettleMs               716    <- the wait after the reader stops
wheelSharpWhileScrollingPct  15    <- what was readable while it moved
wheelSoftP50Ms             1322    <- how long a page sits on screen, soft
wheelPagesNeverSharp        3/5
```

The trace named the gate, and it was not the scheduler at all:

```
5457  scheduler grant page=5 cost=motion-safe hold=ON   <- the lane works
5681  page-ready page=5
5977  renderHold off                                    <- 500ms quiet window
6020  scheduler grant page=4 focus=4 hold=off           <- the page you LANDED on
6093  page-ready page=4
```

Page 4 - the one filling the viewport - was never queued until the scroll
settled. Nothing in a page's render intent changes as it scrolls into view
(`onScreen` is deliberately not part of it), and the image-ratio promotion
that would otherwise fire cannot: `_renderedAtDisplayImageRatio()` answers
"yes" for a page that has never rendered at all. So the only thing that
queued a mounted cache-window neighbour was the settle generation bump at the
*end* of the scroll, a 500 ms quiet window away.

**The motion-safe lane cannot grant what was never queued.** `PdfPageView`
now asks on every rebuild while it is on screen with nothing of its own to
paint, guarded by `PdfPageRenderScheduler.isQueued` so the ask cannot pile a
second pass behind a render already running. Deliberately a level check, not
an edge one: the on-screen span can flip before the page is geometrically
visible, so "the frame it entered" is not a reliable moment to hang this on.

The same round removed an off-screen raster deferral added earlier in this
session for the jump case - it was firing for pages scrolling *into* view and
costing them a whole extra round trip (`defer-raster reason=off-screen-motion`
in the trace).

## Result

`tool/perf.sh webdiff e574c87 wheel-text`, three interleaved runs, same
harness both sides - the reader's own journey:

| metric | baseline | now |
|---|---|---|
| wheelSettleMs (wait after you stop scrolling) | 716 | **0.23** |
| wheelSharpWhileScrollingPct | 15.0 | **96.0** |
| wheelSharpPct | 10.6 | **96.0** |
| wheelSoftP50Ms (page on screen but soft) | 1322 | **0.0** |
| wheelSoftP95Ms | 1322 | 358 |
| wheelPagesNeverSharp | 3 | **0** |
| buildP50 / buildP95 | 1.93 / 5.58 ms | 1.99 / 4.60 ms |

`wheel-plan`, the dense-vector arm the pacing exists for, moves the same way:
settle 864 → 0.23 ms, sharp-while-scrolling 8% → 67%, pages never sharp 5 →
1, and tab memory *down* 32%. Its buildP95 rises 8.8 → 11.6 ms.

Page-to-page navigation (`read-text`) keeps the first round's win:
readFirstSettleP50 212 → 0.04 ms, readBackSettleP50 220 → 0.03 ms, 100% of
revisits already sharp on arrival.

### What it costs

Attributed by turning each half off and re-measuring:

- **The scrolling fix is free.** With the retained-scene tier disabled
  entirely, `wheel-text` still reports settle 0.2 ms and 88% sharp while
  scrolling, at 68 MB - *below* the 75 MB baseline.
- **The retention is what costs memory**: ~+97 MB on a 40-page text document
  at a 64 MB budget, and it buys the last 8 points of sharp-while-scrolling
  plus free scroll-back (readBack 4% → 100% instant).
- Frame cost is small and mixed: median build +3% on the wheel journey with
  p95 *better*; on the CAD arms p95 is 1-3 ms worse, and jank counts fall
  9-12% because the work moved off the post-scroll cliff.

Halving the web budget to 32 MB was measured too: tab memory +25 MB instead
of +97 MB, scroll-back still free, but forward arrivals lose their warm
(readFirstSettleP50 back to ~180 ms) because the tier can no longer hold the
speculative warm window. That is the reasoning recorded in
`pdfDefaultRetainedSceneBytes`: the floor is the warm window, not a round
number.

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
- Every non-`warm` harness scenario was running with the warm scenarios'
  **1 GB** page-raster budget, so every page ever rendered kept a ~8 MB
  raster. That flattered revisit latency and inflated `agentMemoryBytes` past
  anything an app would show. Non-warm scenarios now use the package default
  (32 MB), which is what a real viewer has.
- Two widget tests written for this looked like they passed on the old code
  as well - in a widget-test layout the page mounts already on screen, and a
  page that mounts on screen has always queued itself. Check that a new test
  fails without the change before believing it; the queuing fix's real
  evidence is the `wheel-text` A/B.

## Round three: the field trace

A trace from the desktop app on a 50-page document said the work above had
barely moved it, and named two things the browser harness could not have.

**The thumbnail strip owned the wait.** At every settle:

```
57.757  renderHold off (pending=0 …)
57.758  thumbnail grant page=28 … local interpret+raster=111.8ms (no worker)
        … four more tiles …                    ≈ 400 ms of platform thread
58.171  scheduler grant page=30 focus=30       <- the page the reader landed on
58.183  interpret page=30 FIRST interpret=12.0ms
58.189  page-ready page=30
```

400-530 ms of thumbnails, three times over, ahead of a page whose own walk is
12 ms. The thumbnail queue *does* stand down while the viewer is busy - but
`busy` was false at that instant, because no page had queued a render yet
(the very bug the previous round fixed), and once the drain starts it runs
tiles back to back on the strength of that one reading. The frame that would
have queued the page could not run. `PdfThumbnailCache._drain` now yields a
whole frame between tiles and re-reads the gate after it.

**There was no render worker at all.** `path=recorded`, `(no worker)`: every
interpret on the UI thread, which also made the whole motion-safe lane inert,
since it required an off-thread walk. So the lane grew a third class.

## Motion classes

The boolean was wrong in a way worth recording: a request made mid-fling is
granted after the reader's hand has stopped, and the answer differs between
those two moments. So `PdfRenderMotionClass` is declared by the caller and
*evaluated at grant time*:

- `free` - worker-backed and small: runs whenever, motion or not.
- `quiet` - no worker, small page: runs in the scroll-quiet window but never
  inside a live gesture. A 12 ms UI-thread walk should not sit out a 500 ms
  window whose purpose is insurance against the scroll resuming.
- `held` - everything else, exactly as before.

"Live gesture" needed its own signal: `_motionRenderHoldActive` includes that
500 ms window, so using it here would have gated the lane on the very thing it
exists to bypass. `PdfPageRenderScheduler.activeGesture` is driven by a 120 ms
quiet timer restarted on every scroll event - two frames, so a wheel stream's
gaps never read as "stopped".

A local walk that overruns `motionSafeLocalBudgetMs` marks its page held for
good (`_recordKnownHeld`): encoded size is a weak proxy for walk cost, so the
pre-walk gate is pessimistic and the measurement is what actually decides.

## Where this leaves the no-worker path

`wheel-text-noworker` (the same scroll with `?worker=0`) goes 612 -> ~410 ms
to settle, and that residue is *work*, not waiting: three UI-thread walks at
25-110 ms each, one per frame. Sharp-while-scrolling stays at 15%, and it
should - at 12,000 px/s a reader passes ten pages a second and no amount of
scheduling walks ten pages a second on the UI thread. That is what the worker
is for, which makes "why was there no worker?" the important question, not
"how do we schedule around it". The interpret line now says
`recorded(no-worker)` vs `recorded(declined)` so the next field trace answers
it in one word instead of a round trip.

### The silent cliff

Chasing "why was there no worker?" turned up something worth more than the
answer: `_IsolateRenderWorker._spawn` caught a failed spawn with `catch (_)`
and set `_spawnFailed`, after which every `record()` resolves to null and
every page interprets on the UI thread - permanently, for that document, with
**nothing in any log**. A trace of that session is indistinguishable from one
where the worker merely declined a page. It is the single most consequential
thing that can quietly go wrong with rendering, and it was invisible.

It now logs to `PdfPerfLog` and, in debug, prints a plain-language warning
naming the cause. Paired with the `recorded(no-worker)` / `recorded(declined)`
split on the interpret line, a field trace now answers "did this session have
a worker, and if not why" without a round trip.
