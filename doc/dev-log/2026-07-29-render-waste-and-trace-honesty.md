# Re-raster waste, the memory feedback loop, and two lying trace fields

Driven by a device trace (`perf.logs`-style, 2026-07-29, ~3.5 minutes on a
3-4 page 1191x824pt document). The headline number: **~30 seconds of
rasterize wall-clock inside ~40 seconds of active session**, 31 full-page
rasters for 4 distinct pages. Page 1 alone rasterized 14 times, page 0 nine
times. The viewer was rasterize-bound essentially the whole time it was
awake, and almost all of it was repeat work.

Six changes, in the order they matter.

## 1. A settle no longer supersedes the base raster (`page_render_session.dart`)

`PdfPageRenderSession.update` bumped the **full** render generation on any
`viewportChanged`, which includes a `settleGeneration` bump at unchanged
scale. A full raster that completed a few milliseconds after such a bump
failed `_superseded` in `_renderNow`, was disposed unpainted, and the page
rasterized from scratch again.

That is the trace's clearest waste: page 0 produced an identical
`base-full ratio=1.4 1715x1213` at n=59, n=61 and n=63 inside one second -
~8MB and a full GPU readback each - with only the last one surviving to
paint. Page 1 did the same at n=60/62.

The full raster depends on content, display settings and resolution. A
settle touches none of them; it moves the *detail patch*. So `update` now
invalidates the detail on every settle (unchanged) and the full generation
only on `blanked || visualChanged || scaleChanged || pageSlotChanged`. It
still *schedules* a render - the patch needs one - it just stops cancelling
work that was about to land.

Unit-tested deterministically in `page_render_session_test.dart` ('a settle
at unchanged scale supersedes the detail, not the base'); that test fails if
the `invalidateFull()` guard is removed. The end-to-end widget test in
`render_hold_test.dart` guards the observable outcome only - the timing that
actually discards a raster is not reproducible there, because a local render
lands too fast to be interrupted.

## 2. Memory pressure no longer punishes caches that hold nothing

`AdaptiveMemoryBudgetController._applyPressure` halved the registry ceiling
and the page-raster budget on every pressure event, and held both for
`pressureCooldown`. In the trace that fired against a registry holding
**7MB of a 1350MB process**: it reclaimed 22MB (1.6%), halved the ceiling
140MB -> 70MB, and the pages whose rasters the ceiling had been retaining
promptly re-rasterized four more times - raising RSS, arming the next
sample, halving the ceiling again. A closed loop, and the cache was never
the problem: the memory is in live rasters, worker buffers and GPU
textures.

Reclaiming is unchanged (pressure is a hard signal). What is now gated is
the **lasting** half - the `_pressureRegistryCap` and the halved page budget
- on the registry holding at least `registryMaterialityPercent` (5%) of
process RSS. Below that the caches are not the thing to cut, and
`PdfLiveRasterBudget` (still halved unconditionally) is the lever that
corresponds to the signal. With no RSS reading available the old behaviour
is kept.

Note this also explains why `page-raster mode=fixed total=2147483648` in the
trace was cosmetic: `PdfCacheRegistry.enforceBudget` trims proportionally and
may evict the final MRU master, so the ~70MB ceiling was the real bound, not
the 2GB devtools setting.

## 3. No second raster when the vector replay already finished the region

`_updateDetail` painted a vector-only region replay, then unconditionally
awaited a worker region record and rasterized *that* over it. On a region no
image reaches, the two produce identical pixels. The trace paid it on a page
whose single image decoded to 0.0 megapixels: `detail-vector ... 1715x999
ms=401.9` followed 320ms later by `detail-worker-picture ... 1715x999
ms=322.5`.

`vectorCoversRegion` (the existing `_imagesIntersectRegion` predicate, hoisted
above the worker launch) now skips the worker request entirely and returns the
vector patch as final. The predicate is the codebase's own definition of "the
vector replay is visually complete for this region" - `_tileCanRasterize` already
bets *retained, reused* tiles on it, which is a longer-lived commitment than this
one.

`web_slug_mixed_page_test.dart` covers both sides: the image-free region now
asks for no region record, and a new test asserts that a region the image
*does* reach still waits for the complete record and paints no vector patch
in the meantime.

## 4. The raster cache no longer keeps entries that can only miss

`fullImageFor` returned null on a geometry mismatch and left the entry in
place. In the trace a page-0 raster stored at ratio 0.4 (429x304) produced
`miss reason=dimensions` three times over 1.4s while the viewer, long since
at ratio 1.4, re-rasterized the page each time. Six lookups across the
session: one hit. A mismatched entry is dropped now - the caller's next act
is to store its replacement anyway, and under the coordinated ceiling the
cache holds single-digit entries.

## 5. `interpret=` was not measuring interpreting

The `_renderNow` stopwatch starts above `_paintVectorFirst`, so
`interpretMs` included a full-page vector raster and an `endOfFrame` wait.
`interpret page=2 ... interpret=1224.2ms wait=109.0ms build=132.8ms` left
~980ms unattributed, and that time was the `vector-first-full ... ms=793.0`
logged two lines earlier. Every such line under-attributed by 60-80% -
exactly the shape that sends someone optimizing the interpreter when the
cost is in the raster.

`PdfPerfLog.interpret` now takes `progressiveMs`, so
`progressive + wait + build` accounts for `interpret`. Printed even at zero:
"ran no progressive phase" and "this build predates the split" must not read
the same.

## 6. `ms=` on raster lines is queue-inclusive - `conc=` says by how much

`toImage` awaits the raster thread and the scheduler starts page renders
without awaiting them, so concurrent rasters absorb each other's queue time.
Three 0.1MP rasters that started together reported 4692ms, 3461ms and
2731ms; one page at one ratio measured 138.8ms uncontended against 2299.4ms
contended - 16x over identical pixels.

New `PdfRasterProbe.measure(kind, page:, ratio:, region:, rasterize:)`
replaces the hand-rolled `Stopwatch` + `PdfPerfLog.raster` pairs at all five
call sites and adds `conc=N`: peak rasters in flight during this one's
lifetime (peak, not depth-at-start - a raster that begins alone and is then
joined waits just as long as one that started fourth). At `conc=1` the
duration is the work; above it, mostly queue. The probe retires in a
`finally`, so a throwing rasterize cannot leak the count and quietly turn
the diagnostic into a liar - asserted directly via `debugInFlight`.

## 7. The thumbnail warm logged ~90 times and warmed nothing

`_kickWarm` scheduled a microtask that immediately re-checked the gate and
stood down. The scheduler pings its activity `Listenable` on every grant,
settle, request and hold transition - mostly while still busy - so each ping
cost a microtask and a log line. The trace has ~90 `thumbnail warm yields`
lines and not one `thumbnail warm page=`.

The gate is now checked *before* scheduling, and the yield is logged once per
transition into yielding rather than once per ping. `renderHold` lines also
now carry `inFlight=`, because `busy` is pending + inFlight + hold: a trace
showing `renderHold off (pending=0)` followed by silence previously gave no
way to tell an idle viewer from one whose in-flight set never drained.

## Not fixed / open

- The ~1.4GB RSS itself. The page-raster cache held 7-16MB of it throughout,
  so it is elsewhere - retained scenes, worker command buffers, or GPU
  textures. The trace shows 250MB swings inside 200ms windows with no
  eviction logged (13:45:19.643 -> 19.840, 1474 -> 1225MB), which points at
  scene/worker-buffer churn. Change 2 stops the controller making it worse;
  it does not find it.
- Seven `FIRST` interprets on a 3-4 page document, including pages
  re-interpreted after the pressure eviction dropped their pictures.
  Change 2 should reduce these; not yet measured on device.
- `_baseRasterIsCurrent` / `_imageState` (`pdf_page_view.dart`) hoists the
  resolution-unchanged decision above the vector-first and picture-await
  work, and adds content-intent and image-ratio checks the old
  `_rasteredRatio` guard lacked. Every path traced was already covered by the
  old guard, so this is an early-out and a `render skip ... reason=base-current`
  trace line, **not** a behaviour fix - the duplicate rasters are change 1.
