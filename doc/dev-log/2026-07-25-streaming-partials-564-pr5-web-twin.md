# 2026-07-25 — Streaming record partials, PR5 of #564 (web transport twin)

PR1–4 landed the streaming reveal on the **native** isolate backend (transport,
dedup, cost bounds, host paint). PR4's flag, validated on a real 143k-command CAD
sheet, streamed nine growing linework frames (266 → 143 882 commands, the doubling
schedule) ~3.5 s before the full raster. But it was native-only: the web worker
didn't stream, so on web a dense page lost the #527 bounded prefix without gaining
the reveal. This PR is the **web transport twin**, so the reveal works on web too
(and shows in the deploy-preview).

## The twin

Mirrors PR1's native transport into the Web Worker protocol:

- **`render_worker_transcript_cache.dart`** — `transcriptFor` (the web worker's
  resumable record walk, shared with strip binning) gains an `onPartial` sink and
  emits interim linework prefixes on the same **doubling chunk schedule** as the
  isolate. Counters live on `_SuspendedTranscriptWalk`, so the cadence survives a
  preempt/resume. A cache hit does no walk and streams nothing. This is
  platform-agnostic pure Dart, so it is **VM-unit-tested directly** (the one piece
  of the web path that can be) — a dense page emits a logarithmic number of
  growing prefix buffers.
- **`render_worker_web_entry.dart`** (runs in the worker) — reads `wantsPartials`
  from the record message, builds an `emitPartial` that `postMessage`s
  `{kind:'partial', id, buffer}` (buffer transferred zero-copy) while the record
  owns the slot and isn't cancelled, and threads it through `_recordPageAsync` →
  `transcriptFor`. New `_postPartial` helper.
- **`render_worker_web.dart`** (main-thread client) — sends `wantsPartials` on the
  record message; `_onMessage` handles `kind:'partial'` by forwarding the buffer
  to the request's sink **without** clearing `_inFlight` or completing the
  completer (the `result` still lands normally); a partial whose id no longer
  matches the in-flight request is dropped. `_WebPending` gained `onPartialBytes`
  (deserialize + forward), mirroring the isolate's `_PendingRequest`.

The `onPartial` param on the web `record` (a no-op since PR1) is now wired.

## Validation — the dart2js gap

The web worker only *truly* compiles via `dart compile js`; `.toJS`/async errors
slip past `dart analyze` (the gap that hung the demo once, #133). Ran the actual
worker build locally — `dart run dart_pdf_editor:build_web_worker` — which
produced a real ~1.06 MB bundle with no errors. The committed asset stays the
~2 KB placeholder (#582), so CI's `worker-compiles` size guard is satisfied; the
real bundle is regenerated at deploy/preview.

`WORKER_REGEN_TOKEN` is **not** a blocker — #582 deleted that machinery; the
deploy-preview builds the real worker, so this reveal will show there.

## Inertness

The web twin only streams when the client sends `wantsPartials`, which it does
only when the caller passed an `onPartial` sink — i.e. only the host's
progressive vector-first record when `PdfPageView.progressiveStreamingPaint` is
on (still default-off). Every other web record is byte-identical.

## Measurement

The first-frame A/B (`tool/perf.sh web`) against the shipped #527 bounded prefix
is the last step, run with the flag on in a browser now that both backends
stream. The mechanism is proven: native logs show the reveal; the transcript-walk
streaming (the web core) is unit-tested; the worker compiles.

## Tests

`render_worker_transcript_cache_test.dart`: `transcriptFor` streams a logarithmic
number of growing prefix buffers on a dense page, and a cache hit streams
nothing. The native `partial_record_test.dart` / dedup / host paint suites are
unchanged and green.

## Follow-up (#564)

With both backends streaming, flip `progressiveStreamingPaint` on once the
`tool/perf.sh web` first-frame number and the preview look hold. That closes
#564.
