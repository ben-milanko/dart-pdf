# 2026-10-11 - #997 zoom bisect: #748 is the step, and it is readiness, not pixels

#997 reported zoom stable visual p50 28.5 -> 44.1 ms (1.55x) between the
2026-08-23 and 2026-10-02 parity checkpoints, named #748 (`2bf88e15`) the first
bad commit, found that restoring #748's synchronous hold release on `main` did
not recover it, and suspected a second cause in #755. This session bisected it
in the cloud container and found that, here, the regression is entirely in
**when the harness sees the viewer go idle**, not in when the zoomed pixels
land.

## Method

- Each bisect point is built from its *own* harness and `build.sh` in a git
  worktree (`fvm` Flutter 3.47.5 for history, as #997 did; 3.47.7 for `main`
  variants), then served as a prebuilt bundle (`PERF_WEB_DIR`) to today's
  `competitive.mjs`, DartPDF only (`PERF_ENGINES=dart-pdf`, #1076).
- `parity-plan` on `test_corpora/dartpdf/plan-set-16p.pdf`, `PERF_PAGES=2,8`,
  `PERF_ZOOMS=1.72,1,1.72,1,1.72,1` (six zooms per run), 4-5 runs per point,
  builds interleaved round by round with the order alternating.
- Playwright Chromium 141, SwiftShader, 4 cores: absolute times are about 4x
  #997's hardware Chrome 154 numbers. Ratios and steps are what carry over.
- The `1b887e9f` August checkpoint is not on `main`'s history; #748's parent
  `fa4d6b28` stands in as the good end.

## Results (zoom stable visual p50 / first visual p50, ms)

| build | readiness | runs | stable | first | median of per-run p50 |
|---|---|---|---|---|---|
| `fa4d6b28` (#748^) | polled | 5 | 107.5 | 107.3 | 106.6 |
| `2bf88e15` (#748) | polled | 4 | 162.0 | 105.1 | 155.0 |
| `812f8e5d` (#755) | polled | 4 | 165.1 | 106.3 | 163.6 |
| `fadf7760` (10-02) | polled | 5 | 159.6 | 103.0 | 155.5 |
| `fadf7760` @ 3.47.7 | polled | 4 | 155.1 | 106.3 | 148.2 |
| `main` `e34541e` | polled | 4 | 154.0 | 103.0 | 151.3 |
| `main` `e34541e` | tracked (#999) | 4 | 108.6 | 108.6 | 100.1 |

- The whole step is #748: `fa4d6b28` -> `2bf88e15` is +50 ms and every later
  point, #755 included, is within noise of it. No second cause here.
- The first visual change never moved (103-108 ms everywhere). Only "stable"
  did.
- In every polled post-#748 sample, stable equals the ready sample exactly:
  `settle()` reports `max(lastChangedAt, readyAt)`, and the driver's
  `!__perfBusy()` poll is what lands last. Before #748 stable equalled first
  visual and readiness never bound it.
- Same `main` build, tracked readiness (#999's `__perfZoomReadyAt`, the first
  frame/activity instant the predicate holds): ready lands ~17 ms (one frame)
  before stable, and stable is 108.6 ms - the pre-#748 number.

## Reading

What is established: after #748 the page's visible render completes on time
(first visual = stable under tracked readiness), but "scheduler idle and nothing
queued" - what a ~20 ms `evaluate()` poll has to observe - becomes true about
50 ms later, and a polled harness charges that to the zoom.

What is not yet traced is exactly which work keeps it busy. The likely
candidate is the post-frame release itself: it restarts the preview prerender
and raster warm one frame after the settle, so background work queues behind
the visible render and keeps the scheduler (and the main thread the poll needs)
occupied. That would also explain why #997's restore experiment, which kept the
polled harness, did not recover: the background restart still follows the zoom
either way. A `PdfPerfLog` trace of one zoom (scheduler grants after the
visible render) would confirm it.

So in this container #997 is a measurement artifact of polled readiness, which
is exactly the precision problem #999 named. The quick wins it proposed for
#997 (the #755 colour-pipeline gating, re-synchronising the release) would not
change the visible zoom here; the `noquick`/`tiles8`/`syncrel` variants of
`main` measured 104-106 ms under tracked readiness, all within noise of `main`
(108.6 ms).

## Not established here

- Hardware Chrome 154. Re-run `tool/perf.sh competitive parity-plan` with
  `PERF_EXPECT_CHROME=154` on the parity host before closing #997: if the
  tracked zoom-stable p50 there is back near 25-28 ms, the issue is the
  harness; if not, the residual is real and hardware-specific.
- Whether the background warm/prerender restarting right behind a zoom costs
  the *next* interaction (a cadence question, not zoom latency).

## Reproducing

Scripts are in the session scratchpad, not the repo: `build_ref.sh <sha>`
(worktree + own harness + Flutter 3.47.5), `build_variant.sh <name>`
(`origin/main` + an isolated #748 revert), `measure.sh <rounds> <builds...>`
(interleaved, `RUNNER=`/`TAG=` to swap the driver), `summarize.mjs`. The polled
`main` runs used a temporary copy of `competitive.mjs` with the tracked branch
forced off.
