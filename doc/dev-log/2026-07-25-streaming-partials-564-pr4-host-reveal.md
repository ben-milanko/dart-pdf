# 2026-07-25 — Streaming record partials, PR4 of #564 (the host reveal)

PR1–3 landed the streaming *transport* (native emit, caching dedup, cost bounds).
PR3 also recorded the finding that killed my first host-consumer attempt: hooking
the reveal onto the heavy `decodeImages: true` record was **redundant** — the
vector-first pass has already rastered the whole page's linework by then, so the
streamed linework prefixes were a subset of what's on screen.

Per the chosen direction ("grow the early-prefix"), PR4 moves the reveal to
**before** the vector-first full raster: the vector-first record itself streams
the growing linework prefix, and each prefix paints into the preview slot. Behind
a **default-off** flag (`PdfPageView.progressiveStreamingPaint`).

## Worker: stream the vector-first record

The vector-first record is `decodeImages: false` (linework, no image decode), and
PR1 kept that on the one-shot path — only the decoding record streamed. PR4 routes
a *full* non-decoding record (no `commandLimit`) through the resumable path when
it wants partials, so it emits linework prefixes as it walks
(`_recordPageAsync`'s routing gains `|| (onPartial != null && commandLimit ==
null)`). `_recordResumablePage` gained a `decodeImages` parameter: its final
serialize now honours the record's own flag (`decodeImages: decodeImages,
imagePlaceholders: !decodeImages`), so a streamed non-decoding record's final is
**byte-equivalent** to the one-shot non-decoding record it replaces — the walk is
decodeImages-agnostic (it only affects serialization), so resuming one is safe.
A bounded prefix (`commandLimit` set) stays on the cheap one-shot path.

## Host: paint the reveal before the vector-first raster

In `_paintVectorFirst`, when the flag is on and the page clears the same density
proxy as the bounded early prefix, the single bounded prefix is skipped and the
vector-first `worker.record(decodeImages: false, ...)` is given an `onPartial`
sink. Each partial goes to `_paintProgressivePartial`, which rasterizes the
linework prefix into `_preview`. Ordering/lifetime guards: a monotonic `seq`
(reset per record) so a slow rasterize of an earlier partial can't clobber a
later one; `_abandoned` / `_renderPaused` / `_image != null` so a landed full
raster or a recycled page wins. Because this runs *during* the vector-first
record — before its full raster — `_image` is still null, so the partials
actually paint (the mistake PR3 diagnosed). Each partial is a superset, so
replacing the preview outright is correct.

## Why it's still safe / inert by default

`progressiveStreamingPaint` defaults **off**, so production is unchanged. Even on,
a backend that doesn't stream (the web worker until its twin lands, or the null
worker) simply returns the final with no partials, and the page renders exactly
as before. The worker routing change only affects a record that both wants
partials and has no command limit — i.e. only a streaming vector-first record;
every other record keeps its existing path and output.

## Measurement

The reveal's value is a first-frame / perceived-latency win that is a **visual**
judgement, so it is validated on a preview / native run, not a counter. The
widget test confirms the mechanism end-to-end: on a dense page the vector-first
record streams four growing prefixes (928 → 1855 → 3705 → 7369 commands, the
doubling schedule) that paint *before* the `base-full` raster. `tool/perf.sh gate`
stays within 3% (the streaming path is off by default). The first-frame A/B
against the shipped #527 bounded early-prefix, and the web-preview reveal, come
with the web transport twin (the remaining follow-up) once a browser is in the
loop.

## Tests

`progressive_streaming_paint_test.dart`: the vector-first record gets a sink only
when the flag is on and the page is dense (and never with the flag off or on an
ordinary page); and — with the record's final held behind a gate — a streamed
partial paints into the preview (`progressive-partial` logged) before the full
raster. `partial_record_test.dart` adds the byte-equivalence guard: a streaming
`decodeImages: false` record's final matches the one-shot's. The page-view /
worker / dedup suites stay green (96 tests in the batch).

## Follow-up (#564)

Web transport twin (`render_worker_web` + `render_worker_web_entry`) so the web
deploy-preview shows the reveal and `tool/perf.sh web` measures the first-frame
win; then flip the flag on once the number and the look hold. The bundle rebuild
is not a blocker (#582 removed `WORKER_REGEN_TOKEN`; the preview builds the real
worker).
