# 2026-07-25 — Streaming record partials, PR3 of #564 (cost-bounding + a host-paint finding)

PR1 (native transport) and PR2 (caching shared-stream dedup) landed the streaming
*transport* for progressive record partials, both merged. This PR does the
**cost-bounding** both adversarial reviews flagged as a must-fix before any
consumer ships, and records a design finding that reshapes the remaining work.

## Cost-bounding

Two independent bounds, both previously O(n) or worse in the page's command
count, now flat or logarithmic:

1. **Doubling emit schedule** (`render_worker_isolate.dart`, `_recordResumable-
   Page`). Each partial re-serializes the *whole accumulated* prefix, so emitting
   one per chunk is O(commands²) across a page. Now partials fire only after
   chunks 1, 2, 4, 8, … — O(log chunks) emits whose serialize work is a geometric
   series dominated by the last (full-page) prefix, i.e. **O(commands) total**,
   ~2× a single full serialize. It also fronts the reveals (dense early, sparse
   late), which is where a top-down reveal matters. The schedule counters live on
   `_SuspendedRecord`, so they persist across a preempt/resume instead of
   restarting the cadence on requeue.

2. **O(1) replay buffer** (`render_worker.dart`, `_InflightRecord`). PR2 buffered
   every emitted partial for late-joiner replay — O(chunks) retention. But every
   partial is a cumulative **superset** of its predecessors, so a late joiner only
   needs the *latest* to be fully caught up. `_InflightRecord` now keeps a single
   `_latest` instead of a list; present subscribers still get every partial live.

Together these mean a consumer can stream a heavy page's reveal without the
streaming path scaling worse than one extra full serialize plus one small
retained buffer.

## The host-paint finding (why the consumer is NOT in this PR)

I wired a host consumer (`PdfPageView`, behind a default-off flag) onto the heavy
`decodeImages: true` record — the multi-second image-decode pass — and painted
each streamed linework prefix into the preview slot. A widget test with an
image-bearing dense CAD fixture showed the mechanism works, but the perf log
revealed it adds **no visible value where I hooked it**:

```
vector-first detail page=0 ... commands=12001
raster kind=vector-first-full page=0 ... img=600x60   <- full linework already on screen
```

By the time the heavy `decodeImages: true` record runs, the **vector-first pass
has already rastered the whole page's linework** into the preview. The streamed
partials are linework prefixes with images excluded — i.e. a *subset* of what is
already painted. The reveal only adds information if it lands **before** the
vector-first full raster, which means hooking the stream into the first paint
(replacing #527's single bounded early-prefix with a growing sequence) or
reordering the vector-first raster — a real paint-ordering change whose value and
smoothness can only be judged **visually, in a preview**. Nailing that blind
would ship a flag that does redundant work, so I reverted the host consumer and
left the placement to a follow-up done with a preview in the loop.

This is the honest boundary the whole #564 rollout has respected: land the safe,
testable, inert infrastructure; do the visually-judged UI integration with a
human watching. The transport and its cost bounds are now all in; the consumer
placement is the open design question.

## Measurement

Still no production streaming path (the consumer was reverted), so nothing to A/B
— the first-frame win waits on the (visually-validated) consumer. `tool/perf.sh
gate` → 12 inputs, 13 counters within 3%. The cost-bounding is proven by unit
test, not the harness.

## Tests

`partial_record_test.dart`: a large page (~15 worker chunks) emits a handful of
partials, not fifteen (the doubling bound), each a strictly larger prefix.
`caching_partial_dedup_test.dart` and the rest of the partial suite stay green
with keep-latest replay (a late joiner replays the latest prefix, which is a
superset of all prior).

## Follow-up (#564)

The host progressive paint: decide where the reveal hooks so it lands *before*
the vector-first full raster (a growing early-prefix sequence, or a vector-first
reorder), validated on a deploy preview / native run; then the web transport twin
(`render_worker_web` + entry) so the web preview shows it and `tool/perf.sh web`
measures the first-frame win. The bundle-rebuild is no longer a blocker (#582
removed `WORKER_REGEN_TOKEN`; the preview builds the real worker).
