# 2026-07-24 — a resumable page-content walk (#566)

Third piece of the #520 deep-tier session (after `2026-07-24-jpx-cp-reduce-525.md`
and `2026-07-24-progressive-reveal-and-base-cull-526-527.md`). Landed the
**shared resumable-cursor primitive** that both remaining tickets need — #530
(resume a cancelled record) and #564 (spatial streaming partials).

## Why land it on its own

Both tickets independently need "record N ops, stop, then continue *appending*
from N+1". Building them separately would have produced two incompatible
mechanisms on the hottest path in the viewer. This lands the primitive once,
measured, with neither consumer wired up — so the follow-ups are each a small,
reviewable change against a proven base.

## What it is

`PdfInterpreter.beginPageContent(page, content)` returns a
`PdfPageContentWalk`:

- `advance({operations, yieldInterval})` records up to `operations` more
  operations (null runs to completion) and returns true once the page is done.
- `abandon()` ends the walk early — the cancelled-render path.
- `isComplete` / `isFinished`.

Resumption needs no serialization: the `ContentOperationCursor` already holds
the parse position and the interpreter instance already holds the graphics
state, so continuing is simply "call `advance` again". The pieces that had to
move were the ones `drawPageContentAsync` did *per call* — resetting
`_state`/stacks, creating the cursor, and the `device.save()`/`restore()` pair.
Those now live in `beginPageContent` / `_endPageContent`, which runs exactly
once per walk.

Chunk boundaries land only between **top-level** operations — a form XObject
runs to completion inside one `_execOp` — so the state is always at page level
between chunks. That is what makes emitting a partial at a boundary safe (the
property #564 depends on).

## The trick that makes it trustworthy

`drawPageContentAsync` is now **implemented on top of the walk** (begin +
unbounded advance). Every async page record in the codebase therefore exercises
the new code, so the whole corpus — 909 pdf_graphics tests, the ghent and
PDF.js suites, the perf sweeps — is regression coverage for it. The alternative
(adding the walk beside the existing path) would have left the chunked form a
parallel, lightly-tested branch. The two cursor helpers it replaced
(`_runCursorAsync`, `_runCursorOpsAsync`) became dead and were removed.

That choice is also why the hot-path A/B below was mandatory rather than
optional: the refactor touches every page record, so a regression there would
have hit everything.

## Measured

**Chunking overhead** (cad-wide, 850k ops, median of 5, warmed):

| | time | vs single |
|---|---|---|
| single walk | 855.1 ms | — |
| chunked (50000) | 854.4 ms | 0.999x |
| chunked (20000, the default) | 851.4 ms | **0.996x** |
| chunked (5000) | 899.1 ms | 1.051x |
| single (re-check) | 854.7 ms | 0.999x |

**Hot path** — `tool/perf.sh diff main dartpdf-corpus`, 4 interleaved runs, 16
files: **VERDICT OK**. interpret 0.985x, firstPage 1.002x, extract 0.999x, open
0.990x, save 0.987x, peakRss 0.999x.

### Benchmark gotcha worth remembering
The first run of the chunking benchmark reported chunked as **3× faster** than
single — pure JIT-ordering artifact, because `timeSingle` ran first (cold) and
`timeChunked` after (warm). Warming both shapes first, and re-measuring `single`
at the end as a stability check (0.999x of the first `single`), is what turned a
nonsense number into a trustworthy one. Any A/B inside one VM process needs both
the warmup and the re-check; a same-shape re-measure at the end is the cheapest
way to catch drift.

## Test-contract gotcha

The obvious assertion for `abandon()` — "saves == restores" — **fails**, 7 vs 6.
Stopping mid-page can leave the *content's own* `q` unmatched by its `Q`, which
is inherent to not finishing and is exactly what a cancelled
`drawPageContentAsync` has always done. The meaningful invariant is narrower:
abandon emits the **one** restore balancing `beginPageContent`'s save, and is
idempotent. The test counts restores before and after instead.

## What remains

- **#530** — hold the walk across cancellation in `render_scheduler.dart` /
  `page_render_session.dart` so a resumed render appends into the same
  `RecordingDevice` rather than starting a new one.
- **#564** — the interpreter side is done; what is left is entirely transport:
  breaking the strictly 1:1 worker request/response contract (`_inFlight`, the
  `Completer`, and `PdfCachingRenderWorker`'s shared-future dedup) across 6
  files, twin-implemented native + web, plus the bundle rebuild.

## Study status

10 landed + this primitive · 3 closed after measuring (#521, #523, #526) · 2
report-only (#528, #529) · 2 open (#530, #564).
