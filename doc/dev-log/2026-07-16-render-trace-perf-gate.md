# One PdfRenderTrace spanning both isolates + a CI perf gate

Issue #306. The measurement enabler for the perf-architecture batch: before
this there was no single interface that yielded an end-to-end per-phase
breakdown of one page render, and nothing gated a PR against regressions.

## What landed

- **`PdfRenderTrace`** (`lib/src/render_trace.dart`) - one value type both
  isolates fill. It carries the worker/off-thread phases (parse, stream,
  interpret, decode, serialize, bin, plus `workerUs` and `transcriptHit`) and
  the main-isolate phases (queue, transfer, deserialize, replay, rasterize),
  with `workerPhasesUs`/`mainPhasesUs`/`endToEndUs` rollups and a `format()`
  for logging. Phase fields are mutable microsecond accumulators (a progressive
  page is recorded in several passes; `+=`), with `copy()` for a snapshot and
  `min()` for best-of-N.
- The old worker-only `PdfWorkerPhaseTimings` (was in
  `render_worker_transcript_cache.dart`) is now `typedef
  PdfWorkerPhaseTimings = PdfRenderTrace;` - the worker fills its half of the
  unified record with no code change. The transcript-cache file re-exports both
  names so existing importers keep compiling.
- **`PdfRenderTrace.captureOffThread(document, pageIndex)`** - the single call
  that produces the VM-measurable per-phase breakdown of one page: it mirrors
  exactly what the worker does off-thread (tokenize -> interpret content +
  annotations -> serialize) then the main-isolate finish (deserialize ->
  replay). Rasterization needs `dart:ui`, so it stays 0 here; the Flutter
  `benchmark_phases_test.dart` still covers paint/raster.
- **`PdfRenderWorker.lastRenderTrace`** - a getter surfacing the most recent
  job's unified trace. The web backend populates it from `_WebRequestTrace`
  (which already collected every field but only string-logged them); the
  caching wrapper forwards to its inner worker, the pool returns whichever
  worker last reported. Only populated while `PdfPerfLog` is enabled, so
  ordinary rendering pays nothing. Base default is null.
- **`PdfRenderPhaseBudget`** + **`test/render_trace_gate_test.dart`** - the CI
  gate. A tiny programmatic micro-corpus (classic text, multipage, annotations,
  AcroForm, embedded font) is captured best-of-N and asserted against coarse
  per-phase budgets. It runs by default under `flutter test` (the nine
  `benchmark_*_test.dart` probes are all skip-unless-env, so they never gate).

## Gotchas

- `PdfDocument` has no `dispose()` - don't add tearDowns for it.
- On tiny fixtures the cheap phases (parse, replay) can measure 0us of
  Stopwatch resolution, so the gate's liveness asserts only `serializeUs > 0`
  and `endToEndUs > 0`; the rest are `>= 0`. Budgets are order-of-magnitude
  tripwires (~50x observed) taken best-of-N, so shared-runner jitter never
  trips them - re-baseline the numbers in that one file if real cost shifts,
  don't mute the gate.
- The bundled web worker asset (`assets/web/pdf_render_worker.dart.js`) had to
  be rebuilt (`dart run dart_pdf_editor:build_web_worker`) because the worker's
  transitive source changed; CI's "Verify bundled web render worker" step
  compares it against a fresh build.
