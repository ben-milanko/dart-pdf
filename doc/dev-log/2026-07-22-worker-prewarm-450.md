# 2026-07-22 — prewarm the web render worker at app boot (#450)

Opening a document on mobile web blocked ~1.5 s on the render worker: `web.Worker(scriptUrl)`
fetches, compiles, and boots the ~1 MB dart2js worker script, and every page
record queues behind it (the trace showed `startup=1511ms`, `queue=1437ms` on
page 0). None of that depends on the document — `startRenderWorker(bytes)` only
paid it because it constructed the worker *after* a file was picked and read.

## Change (option 2 from the ticket: warm at boot)

Split construction (fetch + compile + boot) from the document hand-off (`init`),
without touching the pool/caching abstraction:

- `render_worker_web.dart`: a module-level queue of pre-booted `web.Worker`s.
  `prewarmRenderWorkers(count)` constructs them now; `_WebRenderWorker` adopts one
  (`removeAt(0)`) instead of constructing, then reinstalls its real handlers and
  posts `init`. The worker is silent until it receives `init` (verified in the
  entry: it only posts `ready` after opening the document), so nothing is lost
  between prewarm and adoption. `disposePrewarmedRenderWorkers()` drops unadopted
  ones. `startRenderWorker(bytes)` is otherwise unchanged — the pool and caching
  wrapper need no API change.
- `render_worker_isolate.dart` / `render_worker_stub.dart`: no-op prewarm (native
  isolate spawn carries no fetch/compile cost; #450 is dart2js-on-web specific).
- `render_worker.dart`: `PdfRenderWorker.prewarm({count})` /
  `disposePrewarm()` statics over the conditional-import platform functions.
- `app/lib/app.dart`: calls `PdfRenderWorker.prewarm(count: pdfRenderWorkerPoolSize)`
  in `initState`, right after the pool size is set — so the compile overlaps the
  user choosing a file. (Not in `main.dart`: that runs before the deferred
  `app.dart` unit and importing the package there would drag the editor stack
  into the initial download the deferred split exists to keep small.)
- `perf_harness.dart`: prewarms at the top of `_start()`, gated on `?prewarm`
  (default on) so one bundle A/Bs both arms.

## Measured (real Chrome, CPU-throttled to approximate a phone's slow compile)

`open` scenario, `_ab_prewarm.mjs` (COOP/COEP server + `Emulation.setCPUThrottlingRate`),
worker-startup and first-content timings off the perf log:

```
                worker startup   worker ready   first full pixels (base-full)
  6x  baseline     459 ms           1424 ms          3477 ms
  6x  prewarm      221 ms  (-52%)   1082 ms (-24%)   2928 ms  (-549 ms)
 12x  baseline    1629 ms           4997 ms          8325 ms
 12x  prewarm      974 ms  (-40%)   4068 ms (-19%)   6766 ms  (-1559 ms)
```

The win scales with CPU slowness — exactly as expected, since prewarm overlaps
the compile with the document load/parse. At 12× (phone-class, ~1.6 s baseline
startup, matching the ticket's 1.5 s) it shaves **~1.5 s off first content**. On
a real phone with a real network the absolute win is at least this, plus the
fetch overlap.

## Notes / not done

- The two telemetry "notes" on #450 (`workers=1` vs `renderWorkers: 2`;
  `vectorFirst=false` while vector-first runs) are separate reporting-accuracy
  items — left for a follow-up; they need the intended-semantics context, not a
  mechanical fix.
- Option 1 (an `index.html` script preload) composes with this and would add
  the cold-network fetch overlap; not included here (its benefit is
  network-proportional and not visible on the local harness).
