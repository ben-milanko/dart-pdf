# 2026-07-11 — Deep-zoom combined jobs, first-present benchmark, record retry

This session closes the first three remaining native strip-performance items:
#219's display-shaped measurement, #214's combined region detail request, and
#215's safe in-flight RECORD preemption.

## Display-shaped settle measurement (#219)

`strip_worker_latency_test.dart` remains the pixel-correctness harness: it
calls `toImage` and then synchronously reads the whole raster back to RGBA.
That last readback is useful for comparisons but is not part of the viewer's
display path and dominated its reported totals.

`strip_display_latency_test.dart` is the companion latency harness. It stops
at the first `RawImage` frame containing the newly rasterized page, registers
an `addTimingsCallback` for backends that expose `FrameTiming`, and never calls
`toByteData`. On the Flutter test backend used here frame timings are not
reported (the frame columns remain zero), so the pump wall time is retained as
the portable first-present boundary. A one-pass Impeller run on
`ly9-far-cad.pdf#4` (98.9k commands) produced:

```
path        binWait    build  toImage  present    first
local           0.0    329.4     13.0      1.5    344.0
worker        328.3     18.7     21.8      1.7    370.4
primed          2.6     12.9     13.4      1.6     30.6
```

This matches the earlier inference: synchronous readback was obscuring the
actual win. With the speculative plan warm, the display-shaped settle is about
31 ms on this run rather than the ~493 ms readback-inclusive number.

## One region-detail worker job (#214)

Dense strip-routed detail patches previously had to choose between two partial
paths: a region `record` supplied sharp image crops but replayed as the slow
nested-picture path, while `binStrips` kept the fast flat strip path but reused
the base scene's lower-resolution images. Issuing both independently would
also serialize two queue waits on the single worker.

The worker API now exposes `recordStripDetail`, returning `PdfStripDetail`:

- `commands`: image pixels decoded/cropped for the visible PDF-space region;
- `plan`: a `StripPlan` binned from those exact round-tripped commands and the
  exact region device geometry.

The native isolate sends the command and plan buffers as two
`TransferableTypedData` payloads in one response. Pool routing uses the same
static page affinity as ordinary strip bins; the full-page record cache passes
the transient result through without retaining it. Unsupported backends
inherit a null implementation and the page view falls back to its existing
base-scene region bin.

The worker's two-entry strip command LRU now keeps two views per page:

- the original document-backed recording, needed to resolve and region-decode
  image COS graphs;
- the wire-round-tripped recording, needed for bit-exact ordinary strip plans.

Keeping both avoids re-interpreting the page on every pan. A regression test
caught why one view cannot serve both jobs: a detached wire command is correct
for geometry replay but is not a safe source for a second COS image
serialization.

`PdfPageView` builds a transient retained scene from the combined commands and
rasterizes the region through the matching plan. It therefore keeps painter
order, strip-plan validation, and region-resolution images with one worker
round trip.

## Safe RECORD preemption (#215)

The interpreter already yields cooperatively, so a higher-priority record can
cancel a lower-priority in-flight walk. The remaining bug was policy:
`PdfCachingRenderWorker` deduplicates concurrent records, so completing the
interrupted backend request with null also completed every shared waiter with
null.

Priority preemption now marks an in-flight RECORD for retry. When its cancelled
response arrives, the main-side worker queue requeues the same request behind
the urgent page without completing its original future. The urgent page cuts
in immediately, then every deduplicated waiter receives the retried record.
The native isolate and Web Worker queues use the same policy.
Explicit stale-page `cancel()` never sets the retry flag and keeps its previous
queued-only semantics; superseded BIN/detail jobs remain disposable and are
not retried.

## Verification

- Full workspace analyzer: clean.
- Focused page-view/worker/preview/strip suite: 101 tests passed, including the
  Ghent strip parity gate.
- New combined-protocol tests verify the worker plan is byte-identical to a
  local bin of the returned commands and that region image pixels ride in the
  same response and rasterize successfully.
- New preemption test uses two pages and two deduplicated low-priority waiters:
  the urgent page completes first and both interrupted waiters later receive a
  non-null record.
- The display benchmark ran successfully against the local dense CAD corpus;
  its missing-corpus path compiles and skips cleanly for normal CI machines.

## #216 first pass: cheaper command-buffer decode

The codec knows all collection lengths from the wire but grew the top-level
command list, every path-segment list, and every glyph-placement list from
empty. Those lists now start at their exact length (while remaining growable
to preserve the public result's behavior), removing capacity reallocations on
large CAD command streams.

Large image payloads also no longer take an unconditional second copy during
UI-isolate deserialization. Decoded RGBA planes and raw image streams of at
least 1 MiB keep a `Uint8List.sublistView` of the transferred buffer. Small COS
strings/streams still copy so a tiny value cannot pin a large buffer. The
retained command list already owns the large payload for its lifetime, making
the view the lower-memory representation as well as the faster one.

`deserializeCommandsMicros` now exposes accumulated UI-side decode time to the
performance probes, parallel to `decodeStripPlanMicros`. The codec suite covers
large-payload zero-copy behavior, growable-list compatibility, and all existing
round trips. The display harness measured 56.2 ms for the initial 98.9k-command
decode on `ly9-far-cad.pdf#4` in the one-pass run above, confirming that this is
still a material first-paint slice even after the allocation cleanup. This is a
bounded first pass on #216; direct decode-to-picture and wire-level interning
remain larger follow-ups that should be benchmarked before changing the format.

## Next priority group

The next native #216 increment is direct decode-to-picture / wire-level
interning, which needs codec-level design and should be judged with the new
first-present harness. Web parity (#217) follows; #218 depends on that web
strip/device proof.
Adaptive policy (#189) and OCR isolation (#93) are valuable but orthogonal to
the now-measured zoom-settle critical path.

## Request-scoped cancellation (#220)

The follow-up is implemented in the same branch. Native cancel-port messages
and Web Worker `{kind:'cancel'}` messages now carry the target request id. Each
worker compares that id with its active request before flipping the cooperative
token, so a late cancel for a completed job cannot abort the urgent job that
followed it.

The native regression uses a private test hook to withhold request A's cancel
until A has answered and request B has been dispatched, then delivers the stale
id while B is walking a dense page. B completes non-null. The ordinary
preemption/requeue tests remain green, and the example web build verifies the
mirrored JS protocol.
