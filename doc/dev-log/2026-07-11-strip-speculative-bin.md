# 2026-07-11 — Speculative strip binning during zoom quiescence

Branch `perf/strip-settle-pipeline`, on top of #211 (worker-isolate strip
binning). #211 moved the dense-page strip re-bin onto the render worker,
but a production settle on ly9-far-cad.pdf p4 (98.9k commands) was still
dominated by *waiting* for that bin. This session makes the wait overlap
the viewer's own settle debounce.

## The binWait decomposition

Instrumenting the worker round-trip on ly9 p4 showed the warm bin wait
(185–430 ms across zoom steps, ~290 ms typical, 355–380 ms on the
benchmark machine below) is essentially the bin itself:

- record ≈ 0 — the worker's `_BinCommandCache` hits on every settle after
  the first (a zoom session hammers one page);
- encode 4–38 ms; transfer ~free via `TransferableTypedData` even at the
  9–21 MB a CAD-sheet plan weighs;
- everything else is `StripPlanBinner.bin` walking 98.9k commands.

Meanwhile the UI-side settle work is small: plan decode + engine-object
build ≈ 20–35 ms, `toImage` ≈ 22–56 ms. So the perceived settle latency
was ~binWait + ~60 ms.

## The overlap: the viewer already waits 200 ms

`_PdfViewerState._onTransformChanged` restarts a 200 ms `_settleTimer` on
every matrix change and only then bumps `_renderScale`/`_settleGeneration`
(pdf_viewer.dart). For that entire debounce the final geometry is already
known and the worker sits idle. New flow:

- `PdfPageView` gains `transformScale` (a `ValueListenable<double>`; the
  viewer feeds it the live InteractiveViewer scale, null keeps the feature
  inert for standalone uses / existing tests).
- `_PdfPageViewState` listens; each change restarts a private 50 ms
  one-shot (`_speculateDebounce`). **Why 50 ms, not every tick**: during
  active motion matrix events arrive every frame, so the timer keeps
  resetting and nothing fires; once motion pauses 50 ms we bin
  speculatively — 150 ms of the viewer's 200 ms debounce then overlaps the
  bin. Firing per tick would cancel-churn the worker continuously for no
  benefit.
- `_speculateStripPlan` (pdf_page_view.dart) re-checks the same
  eligibility as the settle path via the shared `_workerBinningEligible`
  (worker-recorded scene, live worker, no debug-delegate flags) plus
  `retainedZoomReplay`/`_stripReplayScene`, computes the settle's scale,
  and issues `worker.binStrips(...)` with exactly the settle's argument
  construction at the SAME priority. The `(geometry, pixelRatio, future)`
  triple is held in `_speculativeStripPlan`.
- `_workerStripPlan`, on a full-page call, consumes the stored future when
  the geometry matches EXACTLY (all six matrix doubles, width, height,
  pixelRatio — they round-trip the wire codec bit-exactly, so `==` is
  correct). Non-null → return it (`debugSpeculativePlanHits`). Null (the
  speculative bin was cancelled/declined) → fall through to today's
  cancel+request path. Geometry mismatch or a region call → drop it
  (`debugSpeculativePlanMisses`), and the normal `cancelBinStrips` reaps
  the stale worker job. `_setScene` clears the field — a speculative
  geometry is meaningless against a new scene.

## The scale-quantization mirroring contract

The anticipated scale must be the one the settle will pass, so
`_speculateStripPlan` mirrors the viewer's `_renderScale` rule EXACTLY:

```dart
final live = math.max(1.0, transformScale.value);
final anticipated =
    (live - widget.scale).abs() > 0.1 * widget.scale ? live : widget.scale;
```

Both sites carry cross-referencing comments (pdf_viewer.dart's settle,
pdf_page_view.dart's speculation) — if the rule drifts, every speculation
becomes a geometry miss and silently re-pays the full bin wait. The
speculation also mirrors `_renderNow`'s staleness gate (skip when the
effective ratio is within 1% of `_rasteredRatio`): the settle wouldn't
re-raster the full page, and at deep zoom the pixel-capped ratio stops
moving, so speculation never competes with the detail patch's region bins.
`_desiredRatio`/`_effectiveRatio` grew `...At(double scale)` variants for
this; the zero-arg forms delegate.

## In-flight preemption, bin kind only

`_IsolateRenderWorker._cancelKind` (render_worker_isolate.dart) used to
drop only QUEUED requests. For the BIN kind it now also sends the
cancel-port signal when `_inFlight` matches (kind, page, priority), so a
superseded settle — or a speculative bin overtaken by a newer geometry —
frees the worker mid-walk instead of running a stale ~300 ms bin to
completion first (this also improves pan-at-deep-zoom, where a superseded
region bin used to finish before the fresh one started). **Record cancels
stay queued-only**: `PdfCachingRenderWorker` dedups in-flight records
across callers, so preempting one would null a waiter shared with a caller
that still wants it; strip plans are never shared (the caching wrapper
passes bins straight through), so bins are safe to preempt. The signal
keeps the benign pre-existing race the priority-preemption path already
accepts: it can land after the job completed and cancel the NEXT job
instead, whose caller then falls back to a local render/bin.

## Benchmark (strip_worker_latency_test, Impeller/Metal, M-series)

New (P) primed path: issue `binStrips`, wait out the 200 ms settle
debounce the viewer gives for free, then measure the residual await + the
identical build/toImage/readback — production speculation, modelled
honestly.

```
strip settle latency (backend=impeller, mean ms/step over 3 passes x 5 steps, target 2382x1684 fit)
page                         path          binWait    build  toImage  readback  uiBlock    total
WAT_L0001_S.pdf#0            b-retained          -     50.0        -     568.2        -    618.2
ly9-far-cad.pdf#4            L-local-bin       0.0    342.6     56.2     530.6    340.7    929.4
ly9-far-cad.pdf#4            W-worker        371.1     32.8     23.7     441.8     40.8    869.4
ly9-far-cad.pdf#4            P-primed         24.6     21.9     21.8     424.7     35.4    492.9
INVOICE-1000664832.pdf#0     b-retained          -     10.0        -      96.2        -    106.2

worker bin wait per settle by pass (worker-side caches warming):
ly9-far-cad.pdf#4            binWait/settle by pass: 489.8  380.6  377.7  354.9  (pass 0 = cold)
```

The perceived settle wait (binWait + build + toImage) drops 448 → 68 ms.
One honesty caveat: in the harness each P bin runs the SAME geometry the
W bin just binned, so the process-global glyph/shape strip caches are
maximally warm and the primed bin itself takes ~225 ms (fully covered by
the 200 ms sleep bar 25 ms). In production the speculative bin is the
*first* at its geometry (~355–380 ms warm here), so the expected residual
is ~155–180 ms on this machine — still less than half of W, and the
readback (which dwarfs everything and is unaffected) overlaps other work
in the real viewer rather than being serially timed.

## Tests

- strip_plan_device_test: speculative hit (settle consumes the plan,
  `debugSpeculativePlanHits == 1`, no mismatches) and miss (different
  settle scale → miss counted, fresh plan still feeds the device).
- render_worker_strips_test: `cancelBinStrips` preempts a matching
  in-flight bin — needs the new `buildDenseVectorPdf` (4000 rects) so the
  bin reliably spans the interpreter's every-512-ops yield points and the
  cancel deterministically lands mid-walk; a tiny page can finish before
  ever yielding and would return a plan instead of null.
- Web worker compile gate re-run (`dart run dart_pdf_editor:build_web_worker`)
  — the touched render_worker.dart stays Flutter-free.

## Follow-ups

- Region/detail-patch speculation: pans at deep zoom settle through
  `stripRegionGeometry` bins that could be speculated from the live
  translation the same way (the in-flight preemption half is already in).
- The region image re-decode (`_detailPictureFromWorker`) and the region
  strip bin are two separate worker round-trips for one settle; combining
  them into one request would halve the deep-zoom patch latency.
- The primed path's readback still dominates the harness total; the real
  viewer never reads the full page back synchronously, so a
  display-pipeline-shaped benchmark would show the win even larger.
