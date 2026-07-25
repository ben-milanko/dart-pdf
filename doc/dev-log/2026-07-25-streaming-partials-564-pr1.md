# 2026-07-25 — Streaming record partials, PR1 of #564 (native transport, inert)

#564 wants a PDFium-style top-down progressive reveal: the top band of a heavy
page paints first and fills downward, instead of the whole page appearing at
once when the record completes. The interpreter side has been ready since #530/
#566 — `PdfInterpreter.beginPageContent` → `PdfPageContentWalk.advance()` records
a bounded op chunk and resumes without re-walking, and chunk boundaries land only
between top-level operators, so the graphics state is always at page level in
between (which is what makes emitting a partial there safe). What remained was
entirely the **worker transport**: the request/response contract is strictly 1:1
(one request → one payload-bearing response, single in-flight slot), so a job
cannot emit partials as it walks.

This session lands **PR1 of the three-PR plan** on the issue: the native isolate
backend can now stream progressive linework prefixes, opt-in, default-off, with
**no host consumer and no web change** — so it is inert in production and fully
VM-testable. PR2 (caching shared-stream dedup + web twin + bundle rebuild) and
PR3 (`transcriptFor` chunk yield + host progressive paint behind a flag, measured
on the web harness) stay ahead.

## What changed

- **`PdfRenderWorker.record` gains `onPartial` (`PdfPartialRecordSink?`)**
  (`render_worker.dart`). A new typedef documents the contract: each call delivers
  a spatially-growing *linework* prefix (image draws left as placeholders) before
  the future resolves with the final decoded buffer. A page recorded in a single
  chunk emits none.

- **Isolate backend streams it** (`render_worker_isolate.dart`). The record wire
  message carries a trailing `wantsPartials` bool. On the resumable
  (`decodeImages: true`) path, `_recordResumablePage` serializes
  `recorder.commands` after each *incomplete* chunk with `decodeImages: false,
  imagePlaceholders: true` and ships it as `['partial', id, TransferableTypedData]`.
  The main-side listener forwards a partial to the request's sink **without**
  clearing `_inFlight` or completing the `Completer` — the final buffer still
  arrives on the ordinary response path. A partial whose id no longer matches the
  in-flight request (disposed, or requeued under a new id after preemption) is
  dropped; the worker also stops emitting the moment its request loses the slot or
  is cancelled.

- **Pool forwards; the caching wrapper deliberately does not.** `PdfPooledRender-
  Worker.record` threads `onPartial` to the routed/urgent worker.
  `PdfCachingRenderWorker.record` accepts it but **drops it**: the cache collapses
  concurrent callers onto one shared future, and a stream shared with late joiners
  (who must replay already-emitted partials) is exactly the dedup redesign PR2
  owns. Because `PdfRenderWorker.start()` returns the caching wrapper, production
  is byte-identical to before — the feature is reachable only through
  `startUncached`/the pool (tests today, the PR3 host path later). The stub and web
  backends accept the param for interface parity and never call it.

## Why this shape

The subtle edges the issue flags all live in the parts PR1 *doesn't* touch:
requeue-after-preemption across a shared future, explicit cancel mid-stream, and
late-joiner replay are the caching wrapper's problem, and the caching wrapper
does not stream in PR1. Keeping the caching path provably unchanged is what makes
PR1 safe to land unsupervised — the class of regression that has bitten this
subsystem before is web-only dart2js/`.toJS` hangs, and PR1 makes no web change.

## Cost / correctness

- The partial serialize is `decodeImages: false` (no image decode) — the cheap
  linework pass, not a re-decode — and runs only when a sink is attached (off by
  default).
- **Caveat (found in adversarial review):** each incomplete chunk re-serializes
  the *whole accumulated* `recorder.commands`, not just the new suffix, so the
  streaming path is **O(commands²)** in serialize work across a page (and the
  main side re-`deserializeCommands` each partial). That is genuinely inert today
  — nothing reaches it in production — but it is the exact heavy page the feature
  targets, so **PR3 must throttle emission or ship suffix-only deltas** rather
  than the full prefix per chunk. Flagged in a code comment at the emit site.
- A chunk boundary is page-level graphics state, so a prefix of
  `recorder.commands` is a valid replayable buffer (same call the final uses,
  earlier and without decode). Each partial is a superset of the last.

## Adversarial review

A reviewer scrutinized the diff for misrouting, preemption/requeue, and the
inertness claim and found **no shipping bug**: the listener's type-check ordering
means a `['partial', …]` message can never reach the `response[0] as int` cast;
monotonic ids + the single in-flight slot make stale-partial misrouting
impossible; production is byte-identical (the caching wrapper never references
`onPartial`, so `wantsPartials` is always false on the wire); and the ordering
test genuinely proves partials arrive *during* the record (per-port FIFO). The
only finding was the O(commands²) cost above, addressed as a documented PR3
follow-up.

## Measurement

PR1 adds no production code path (guarded behind `onPartial != null`; the caching
wrapper drops it), so there is nothing to A/B yet — the 3–7× first-frame win is
PR3's, measured on the web harness once a host consumer paints the partials.
Ran the deterministic counter gate as the regression check: **`tool/perf.sh gate`
→ 12 inputs, 13 counters within 3%**, and `render_trace_gate_test` green. The
normal record path is unshifted.

## Tests

`test/partial_record_test.dart`: a multi-chunk page streams ≥1 partial, all
before the final; each partial is a non-empty prefix (≤ final command count) and
monotonically grows; requesting partials does not change the final buffer; a
one-chunk page emits none; and the cached production wrapper streams none (the
PR1 inert boundary). Existing worker suites (record/host/revision/strips/resume/
early-prefix) stay green after adding the interface param to their fakes.
