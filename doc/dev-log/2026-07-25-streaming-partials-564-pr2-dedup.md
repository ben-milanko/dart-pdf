# 2026-07-25 — Streaming record partials, PR2 of #564 (caching shared-stream dedup)

PR1 gave the native isolate backend an opt-in `onPartial` sink and had the
production caching wrapper deliberately **drop** it — the shared-future dedup
could not fan a progressive stream to concurrent callers, and that redesign was
called out on the issue as "the hard part / main source of subtle bugs." This
session lands it.

Note the original three-PR plan bundled the dedup redesign **with** the web twin
+ worker-bundle rebuild. I split them: the web twin still needs browser
validation, so it stays ahead. The dedup redesign is **pure Dart in the
platform-agnostic caching wrapper, VM-unit-testable, needs no bundle rebuild** —
so it lands now, CI-safe, still inert in production.

(An earlier draft of this note claimed the web twin was blocked on a
`WORKER_REGEN_TOKEN` secret. That is stale: #582 — closed the same day — stopped
committing the generated web-worker bundle and deleted the whole regen-and-push
machinery, including that token. A web-worker PR is no longer gated on it; the
`worker-compiles` CI job just proves the worker still compiles and keeps the
committed asset a placeholder. The web twin is gated only on browser validation.)

## What changed (all in `render_worker.dart`)

`PdfCachingRenderWorker`'s in-flight map changed from
`Map<key, Future<…>>` to `Map<key, _InflightRecord>`. An `_InflightRecord` holds:

- a `Completer` for the one shared final result (unchanged dedup guarantee);
- a **buffer of the partials emitted so far** and a **list of subscriber sinks**.

`record`:
- **Fresh dispatch** registers the `_InflightRecord` in the map *before* starting
  the decode (so a synchronously-emitted partial has a live sink target and a
  concurrent joiner on a later turn finds it), subscribes the dispatcher's sink,
  then wires the backend's partials into `record.emit` via `_recordAndStore`.
  The dispatch future routes to `record.complete` / `record.completeError`.
- **Join** (`_inflight[key]` present): shares `record.future` and, if this caller
  passed a sink, `subscribe`s — which **replays the buffered prefixes
  synchronously** so a late joiner is caught up, then receives the rest live.

`emit` fans to a *copy* of the sink list (a sink that re-enters `record()` on the
same key can't mutate it mid-iteration) and is a **no-op once `_done`** (a stray
partial from a backend racing its own final can't reach a caller after its
future). `complete`/`completeError` set `_done` and clear the buffers.

## The opt-in gate — why production stays byte-identical

Streaming is enabled **only when the caller that dispatches the decode opts in**:
`_recordAndStore` is passed `onPartial: onPartial == null ? null : record.emit`.
If the dispatcher passes no sink, the backend is never asked for partials
(`wantsPartials` false on the isolate wire), so an all-null production workload
never enters the streaming path — the common visible-page record *is* the
dispatcher and will carry the sink in PR3. A later joiner that wants partials
**cannot retroactively enable a stream the dispatcher declined** (the walk
already started without it); it only awaits the shared final. This is the
property that keeps PR2 inert until PR3 wires a host consumer.

## Correctness corners checked (the issue's flagged risks)

- **Revision invalidation mid-stream:** `updateRevision` drops the record from
  the map, but the decode's `.then` closure keeps it alive; subscribers still get
  their final, `_recordAndStore`'s epoch guard skips the now-stale store, and the
  `whenComplete` cleanup no-ops on the already-removed key. Matches prior "the
  future continues" behavior.
- **Join in the completion window** (after `complete`, before map removal):
  `subscribe`'s `_done` guard returns without adding; the caller gets the already-
  resolved shared final. No partials for a finished record.
- **Two dispatchers on one key:** single-turn registration (no await before
  `_inflight[key] = record`) means a second caller in a later turn always finds
  the record — they can't both see a null slot.

## Cost / PR3 tuning surface

Combined with PR1's O(commands²) prefix re-serialize, `_partials` also **retains
every emitted prefix until the decode completes**, even when no joiner ever
arrives. Inert today (empty unless a consumer opts in), but PR3 — which enables
the consumer — must bound both: throttle emission / ship suffix-only deltas, and
cap or drop the replay buffer once the dispatcher is the only subscriber.

## Measurement

Still no production streaming path (opt-in, no consumer), so nothing to A/B — the
3–7× first-frame win is PR3's, measured on `tool/perf.sh web` once a host paints
partials. The only production delta is one `_InflightRecord` (a `Completer` + two
empty lists) per in-flight decode instead of a bare future — negligible against a
multi-second decode, and covered by the render-scheduler / worker regression
suites. `tool/perf.sh gate` → 12 inputs, 13 counters within 3%.

## Tests

`test/caching_partial_dedup_test.dart` (deterministic fake backend, gate-
controlled so "a joiner arrives after partial 1 but before partial 2" is race-
free): a single opted-in caller gets all partials then the final; a concurrent
late joiner replays the buffered prefix then shares the rest, both deduped onto
one decode and one shared result instance; a dispatcher that opts out never asks
the backend to stream and a later joiner can't enable it; a post-completion
partial is dropped. `test/partial_record_test.dart` updated: the cached wrapper
now streams (and stays inert with no sink). Full worker suite green (105 tests).
