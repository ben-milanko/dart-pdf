# 2026-10-10 - wheel cadence (#998): budget motion previews, decode replies inside their UI turn

#998 traced the wheel rAF p95 regression (43.7 -> 83.3 ms on `parity-plan`)
to two kinds of UI-thread work landing inside wheel frames. This session takes
both out of the gesture. Quick win Q1 of #1001.

## 1. One motion preview per scroll burst, only for a blank page

`_prerenderPreviews` warms a command-limited vector preview for the pages
next to the viewport while a fast scroll is in flight (`_vectorFirstPrefetch`).
The worker records it off-thread, but `renderPreview`'s replay and the
CanvasKit `toImage` readback run on the UI thread: the trace's 67-175 ms
prerender gaps line up with the 83/67/167 ms rAF intervals. The gate
`_previewUiMustDefer` deliberately let these through for list motion, because
before motion-safe renders (2026-08-19) these previews were the only thing
keeping fast-scrolled pages from arriving blank. Now a page entering the
viewport renders through the scroll on its own, so the preview is only worth a
frame for a page that has *nothing* to paint.

- `_motionPreviewSpent` (pdf_viewer.dart): a burst rasterizes at most one
  motion preview. Reset at burst start (`_trackScrollVelocity`'s first sample)
  and at `_settleScrollChange`.
- `_nextPreviewIndex(blankOnly:)`: while a list scroll is live the candidate
  must have no preview at all (`_previews.has`, any revision - a stale preview
  still paints).
- The `deferUiWork` closure re-checks both when the worker reply lands, and
  spends the budget at the first undeferred check (the replay start). A
  per-preview `motionGranted` flag lets that preview's later checks through,
  so the budget never abandons a preview half-way.
- The loop returns instead of spinning when the budget is spent or no blank
  candidate exists: each scroll event re-enters it, and the settle restarts it.

`test/motion_preview_budget_test.dart`: a 24-frame wheel burst over a 40-page
document asked for 10 motion previews before, at most 1 now.

## 2. Worker replies decode inside their UI turn (`PdfRecordDecodeGate`)

`deserializeCommands` ran in the record future's continuation, before
`_paceWorkerUiWork` could weigh the buffer. A plan sheet (~70k ops) was
decoded inside the gesture only for `_recordAllowsMotionReplay` to then send
its replay to the settle.

- `serializedCommandCount(bytes)` (pdf_graphics codec): the top-level count
  from the header (version byte + u32), no decode. Null for a foreign version.
- `PdfRenderWorker.record(decodeGate:)`: the web and isolate workers call the
  gate with that count after the reply arrives and decode only when it
  completes; `false` drops the reply (record returns null).
- `PdfCachingRenderWorker`: the dispatching caller's gate rides the backend
  call. Every caller of a key shares the one reply, so a caller gate only
  *delays*; the cache adds the veto it is sure of - a dispatch superseded while
  parked (priority promotion, revision update) is not decoded at all. The 90 s
  watchdog returns the pending future instead of disposing the worker once the
  reply has arrived: a long scroll is not a wedge.
- `PdfPooledRenderWorker`: the lease is handed back when the gate is reached,
  so a parked decode is not counted as load and does not push other pages off
  their sticky worker.
- `PdfPageView._motionDecodeGate`: a reply over `motionSafeMaxCommands` marks
  the pass held (`_markRecordMotionHeld`) and takes its paced UI turn *before*
  the decode; `_paceWorkerUiWork(turn:)` then spends that grant for the replay
  instead of queueing a second one a frame later. Small replies decode at once
  (image pixels still decide them, and their decode is cheap). Wired into the
  direct worker record, the fused progressive and bounded-final records, and
  the vector-first record. Detail/tile records (zoom-time, unpaced) and the
  bounded early prefix (<=20k ops by construction) are unchanged.

`test/motion_safe_render_test.dart` ("a large worker reply is not even decoded
during live input") fails without the gate: the reply decoded once mid-gesture.
`render_worker_test.dart` covers the cache (delay + share, watchdog, superseded
drop) and pool (lease) halves.

## Numbers

`tool/perf.sh webdiff b0b7489 wheel-plan` (real headless Chromium 1194 -
Playwright's build, not Chrome 154 - in a 4-core container), interleaved,
medians:

| metric | base | branch | 5 runs Δ | 10 runs: base | branch | Δ |
|---|---|---|---|---|---|---|
| buildP95 | 15.03 ms | 12.66 ms | -15.8% | 13.07 ms | 12.99 ms | -0.6% |
| buildP50 | 2.83 ms | 2.65 ms | -6.7% | 2.81 ms | 2.58 ms | -8.0% |
| wheelSoftP95Ms | 750 | 835 | +11.3% | 813 | 741 | -8.8% |
| wheelSoftMeanMs | 538 | 546 | +1.6% | 551 | 538 | -2.5% |
| wheelSharpWhileScrollingPct | 81.6 | 81.6 | 0 | 81.6 | 80.6 | -1.2% |
| wheelSettleMs | 0.26 | 0.23 | - | 0.24 | 0.22 | - |

Read honestly: **neutral on this harness.** The 5-run pass flagged
`wheelSoftP95Ms` (+11%) and showed a -16% build p95; the 10-run pass flips the
first (-8.8%) and erases the second. `wheelSoftP95Ms` is effectively the max of
~7 pages per run (682-1055 ms spread on one side), so it is noise at this
sample size; nothing regressed past 1.1x at 10 runs, and no page went
never-sharp. The scenario's 50 wheel steps over a 16-page plan set do not
reproduce the parity-plan trace's 83 ms rAF p95 here, so this is a no-harm
check, not the #998 acceptance - that still needs `tool/perf.sh competitive
parity-plan` on Chrome 154 with the improved harness (#999).

CI's Patrol web performance report on the PR head (3 samples/side) was
favourable across the board (jank total p95 478 -> 431 ms, web-worker scenario
p50 2410 -> 2064 ms), but at 3 samples that is directional only.

## Not done here

- #998 item 3 (keep -O3) needs nothing: it is still the default.
- The acceptance numbers (rAF p95 <= ~35 ms, journey p50 ≈ 350 ms) are on
  `parity-plan` against PDFium on Chrome 154; this container has Playwright's
  Chromium, no Chrome PDF viewer, so only the DartPDF side was measured.
- #997 (zoom), #999 (harness) and #1000 (raster architecture) are untouched:
  each needs the interleaved parity A/B against PDFium.

## Files

- `packages/pdf_graphics/lib/src/render_command_codec.dart`
  (`serializedCommandCount`)
- `packages/dart_pdf_editor/lib/src/render_worker.dart` (`PdfRecordDecodeGate`,
  pool + cache plumbing), `render_worker_web.dart`,
  `render_worker_isolate.dart`, `render_worker_stub.dart`
- `packages/dart_pdf_editor/lib/src/pdf_page_view.dart` (`_DecodeTurn`,
  `_motionDecodeGate`, `_markRecordMotionHeld`, `_requestUiTurn`)
- `packages/dart_pdf_editor/lib/src/pdf_viewer.dart` (`_motionPreviewSpent`,
  `_nextPreviewIndex(blankOnly:)`)
- Every `PdfRenderWorker` test fake gained the `decodeGate` parameter.
