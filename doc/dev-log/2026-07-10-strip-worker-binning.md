# 2026-07-10 — Worker-isolate strip binning, the Impeller gate, and default-on

Branch `perf/strip-worker-binning`, stacked on `feat/strip-rendering`
(PR #210). #210 left the strip zoom router opt-in for two reasons: no
runtime backend detection, and the ~270 ms strip re-bin ran on the UI
thread every settle. This session removes both — and, along the way,
found and fixed a silent total-blackout bug in #210's Impeller path.

## 1. Shared binning core (`StripBinningDevice`, pdf_graphics/raster)

`StripPdfDevice`'s routing/state/flush logic moved to an abstract,
dart:ui-free base in `pdf_graphics/lib/src/raster/strip_binning_device.dart`:
blend/knockout/clip stacks, the generator feeds (hairline-stroke width
adjustment, the glyph-outline loop), `stripFlattenTolerance`, and **every
flush-point decision**, including `endSoftMasked`'s composite split (the
base runs `drawMask()` between the halves so mask strips bin identically
everywhere). Subclasses get `emitBatch(ordinal, StripBatchData?)` plus
per-op delegate hooks.

**The flush-ordinal parity invariant**: flush points are counted in the
base — empty ones included — and batches are tagged with the ordinal of
the flush point that emitted them. Because routing and flushing live
*only* in the base, a headless replay of the same command list on another
isolate produces batches that interleave at exactly the same ordinals as
the live device. That is the entire correctness story of precomputed
plans. Corollary: the debug-delegate flags change routing, so any of them
being set forces local binning (worker isolates have their own statics).

`StripBatchData`/`StripChunkData` (also pdf_graphics) carry the exact
`drawVertices` upload arrays; the editor's `StripBatch` is now nothing
but `ui.Vertices.raw` + `decodeImageFromPixels` around them.

## 2. StripPlan + codec + StripPlanBinner

`StripPlan` = { totalFlushPoints, deviceWidth/Height, pageToDevice (6
doubles, bit-exact round-trip), tolerance, ordinal-tagged batches }.
`encodeStripPlan`/`decodeStripPlan` write one compact Uint8List (bulk
arrays as raw host-order bytes — producer and consumer are the same
build), shipped as a single `TransferableTypedData`.
`StripPlanBinner` is the headless subclass (delegates are no-ops);
`replayCommandsCancellable` (render_command.dart) chunks the replay every
1024 commands, yielding so a worker's cancel port can preempt mid-walk.

## 3. Worker protocol: `binStrips` / `cancelBinStrips`

`PdfRenderWorker.binStrips(page, {annotations, pageToDevice, deviceWidth,
deviceHeight, pixelRatio, priority: 0})` — priority 0 because a zoom
settle IS the visible page. Bins ride the native isolate's existing
priority queue with their own cancel kind (a settle cancel can't drop the
page's record and vice versa). The abstract base supplies a declining
default (null → local bin) which the stub and web backends inherit; the
web worker entry answers the `bin` message kind with null defensively.
`PdfPooledRenderWorker` routes bins by the **static** page index — a zoom
session hammers one page, so stable affinity keeps the worker-side caches
warm, where least-loaded routing would re-record the page on every
worker. `PdfCachingRenderWorker` passes bins straight through: a plan is
only valid for the matrix it was binned for and every settle's is fresh.

Worker side: on command-cache miss the isolate re-records the page
(deterministic interpretation ⇒ matches the buffer the UI's scene came
from), **round-trips it through the wire codec** so geometry carries the
same float32 truncation as the UI's scene — making worker plans
bit-identical to a local re-bin (asserted end-to-end in
`render_worker_strips_test.dart` by comparing encoded plans, and in
`strip_plan_device_test.dart` by byte-comparing rasters). The list is
kept in a 2-entry (page, annotations) LRU; stable command identity across
settles is what lets the process-global glyph/shape strip caches hit on
repeat settles (measured below). Pages that can't round-trip (inline
images) decline — the same pages `record` declines, so their scenes are
locally recorded and never ask for plans anyway.

## 4. Precomputed mode + verification/fallback semantics

`StripPdfDevice(precomputed: plan)`: generator never feeds (no
flatten/stroke/coverage cost); each flush point consumes the plan batch
tagged with its ordinal. Guards, in order:

- `usablePlan` (constructor): geometry must match exactly (dims, matrix
  coefficient-for-coefficient, tolerance) and no debug-delegate flag may
  be set — else the plan is dropped up front (stale geometry counts in
  `totalPlanMismatches`) and the device bins locally.
- `finish()`: verifies flush-point count and full batch consumption
  **before painting anything**; a desync throws `StripPlanMismatchError`,
  which `PdfRetainedScene`'s strip replays catch — recording discarded,
  transparent re-run with local binning. `totalPlanPictures` counts
  plan-fed pictures for tests/telemetry.
- `debugVerifyPrecomputed` (test-only): bins locally too and
  byte-compares every batch (ordinal presence, strip count, alphaBase,
  vertex arrays, atlas bytes) against the plan.

`PdfRetainedScene` grew `stripGeometry`/`stripRegionGeometry` — the page
view sends those exact six coefficients to the worker, so the equality
guard is exact, not epsilon-y — and `stripPlan:` params on the strip
replay/rasterize entry points.

## 5. PdfPageView: backend gate + plan wiring

- **Impeller gate**: strip routing (both `_retainScene` at scene-adoption
  time and `_stripReplayScene` at settle time — they must agree, or a
  page retained for strips wouldn't strip) additionally requires
  `ui.ImageFilter.isShaderFilterSupported`, public API that is true iff
  Impeller is enabled (verified in 3.44.4 sky_engine painting.dart:4506).
  `PdfPageView.debugStripZoomReplayBackendOverride` forces the decision
  in tests (`flutter test` = software Skia).
- Scenes track their origin (`_setScene(fromWorker:)`): only scenes built
  from a worker-recorded buffer may consume worker plans. Locally
  recorded scenes (worker declined, editing's `skipAnnotation`) keep
  local binning — a worker re-record would ignore skipAnnotation and
  carry f64 geometry, desyncing either content or bytes.
- Zoom settle and deep-zoom region detail request a plan via
  `_workerStripPlan` (cancels the page's still-queued bin first, so a
  newer settle/pan supersedes an older one; the superseded caller's null
  dies under its generation guard without a wasteful local re-bin), then
  `rasterizeStrips/RegionStrips(stripPlan:)`; null plan = local bin,
  exactly #210's behavior.
- Strip-routed pages now skip `_detailPictureFromWorker` for the detail
  patch: replaying its picture is a nested-picture re-raster — the slow
  path strips exist to avoid. The region-resolution image re-decode that
  path offers is orthogonal (stays for canvas-routed pages); combining it
  with strip plans is a follow-up.
- Queued bins are cancelled alongside record cancels on dispose and
  page-recycle.

## 6. The Impeller blackout bug (separate fix commit)

While benchmarking, Impeller validation errors appeared: `Requested
texture size (495503, 8) exceeds maximum supported size of (16384,
16384)` … `Missing texture for VerticesSimpleBlendContents`. Impeller
does not pass drawVertices texcoords to the fragment shader as varyings
(Skia does): it renders the paint's runtime shader into a **snapshot
texture covering the texcoord bounds** and samples that. Our u texcoords
were *global alpha-texel indices* — ~500k on a dense CAD batch — so the
snapshot failed validation and the batch drew **nothing**. ly9-far-cad
p4 through #210's router rendered a blank page on Impeller (only the
delegated logo painted); #210's Impeller settle numbers (380 ms) were
timing an empty raster. The M0 probes and Ghent-sized parity pages never
tripped it because their atlases are small.

Fix: `StripBatchData` chunks by alpha-texel span too
(`stripMaxAlphaColumnsPerDraw` = 8192, chosen under the 8192 max-texture
floor of older Metal GPUs), texcoords are rebased per chunk, and a new
`uBase` shader uniform (one `fragmentShader()` instance per chunk)
restores the global origin. Solid strips now carry constant u = 0 — their
sample is ignored and texel 0 always exists — so they never widen a
chunk's bounds. After the fix ly9 renders the full sheet on Impeller with
zero validation errors; software output is unchanged (parity 53/57
relaxed, as documented).

**Known environment deviation**: `strip_parity_test` under
`--enable-impeller` sits at 22/57 relaxed on this machine — *at the base
commit too*, identical numbers, so it predates this branch (the dev-log
of #210 recorded 57/57 on some other setup). The diffs are edge-share
~100% canvas-vs-strips AA character differences of Impeller's canvas;
the strip side is CPU-binned and backend-independent. Left as is.

## 7. Benchmarks (Impeller/Metal, M4, `strip_worker_latency_test.dart` + `zoom_latency_test.dart`, mean ms/settle over 3 passes × 5 zoom steps, 2382×1684 fit)

ly9-far-cad p4 (98 936 commands — the only default file that strip-routes;
WAT_L0001_S p0 records 12 741 commands, under the 20 000 ceiling, and
keeps the flat retained replay, 585 ms/settle unchanged):

| path | binWait | build | toImage | readback | **UI-block** | total |
|---|---|---|---|---|---|---|
| a-current (cached picture, pre-#210) | — | 3 | 81 | 1389 | ~3 | **1473** |
| b-retained (flat replay) | — | 70 | 63 | 1319 | ~70 | 1453 |
| L local-bin strips (#210 + blackout fix) | — | 343 | 31 | 394 | **341** | 768 |
| W worker-plan strips (this branch) | 338 | 24 | 31 | 373 | **35** | 767 |

- UI-block = the synchronous main-isolate sections (route/bin + tape
  replay + plan decode; `totalRouteMicros`/`totalReplayMicros`/
  `decodeStripPlanMicros`). The worker wait and GPU raster are awaited.
- Strips reach sharp pixels ~2× sooner than the shipping path
  (a-current 1473 → ~770 ms; #210's headline 380 ms was the blank-raster
  artifact — the honest post-fix number is 622–768 ms depending on
  harness, still the fastest path by far).
- **Worker plans cut the settle's UI-thread blocking 341 → 35 ms**
  (−90%), under the ≤80 ms flip criterion. The residual is plan decode
  (~10 ms), `ui.Vertices.raw` creation, and the routing walk of the 99k
  commands.
- Worker-side steady state: bin wait per settle 449 (cold) → 385 → 339 →
  291 ms across passes — the command-cache-stable glyph/shape strip
  caches carry over, mirroring the local −42% effect at reduced scale
  (each settle still has a fresh matrix, so only the cached-shape replay
  cost drops, not the whole bin).
- Office control (INVOICE, 545 commands): 91 ms/settle via b-retained,
  untouched code path, no regression.

## 8. Default flip

`PdfPageView.stripZoomReplay` now defaults **true**: the Impeller gate
makes it inert on software/web, worker binning keeps the UI thread
under ~35 ms per settle on the worst corpus page, and the no-worker
fallback (local bin, 341 ms blocked but sharp ~2× sooner) is the honest
cost of the fastest available settle. Kill switch unchanged (set false).

## 9. Web status

Protocol stubbed only: the web client's `binStrips` inherits the
declining default (null → local bin — itself unreachable today because
`isShaderFilterSupported` is false on web), and the worker entry answers
the `bin` message kind with null so a future client can't hang a slot.
`dart run dart_pdf_editor:build_web_worker` (ci.yml's gate) compiles
green. Wiring real web strip binning (and web strip routing generally)
stays out of scope until strips are proven on a web backend.

## 10. Follow-ups

- Region detail: combine worker strip plans with region-cropped image
  re-decode (today strip-routed pages reuse the scene's base-resolution
  images at deep zoom).
- The Impeller-canvas parity deviation (22/57 relaxed on this machine,
  pre-existing) deserves its own investigation — likely MSAA/AA character
  of Impeller's path rendering, not a strips defect.
- `zoom_latency_test`'s (d) path now reflects real Impeller drawing;
  #210's dev-log table numbers for (d) should be read with this session's
  correction in mind.
- Consider making `stripMaxAlphaColumnsPerDraw` adaptive if a device
  reports a smaller max texture size than 8192 (none known under
  Impeller's Metal/Vulkan floors).

## Files

- pdf_graphics: `src/raster/strip_binning_device.dart`,
  `strip_batch_data.dart`, `strip_plan.dart` (+ `raster.dart` exports),
  `src/render_command.dart` (range + cancellable replay),
  `test/raster/strip_plan_test.dart`.
- dart_pdf_editor: `src/strips/strip_device.dart` (subclass + precomputed
  mode), `strip_batch.dart` (engine wrapper), `shaders/pdf_strips.frag`
  (uBase), `src/render_worker*.dart` (protocol), `src/retained_scene.dart`
  (geometry helpers + stripPlan), `src/pdf_page_view.dart` (gate, scene
  origin, plan wiring, default), tests: `strip_plan_device_test.dart`,
  `render_worker_strips_test.dart`, `strip_worker_latency_test.dart`,
  updated `strip_zoom_router_test.dart`.
