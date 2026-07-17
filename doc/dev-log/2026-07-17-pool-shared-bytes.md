# Render worker pool: share one source-byte snapshot across workers (#309)

`PdfPooledRenderWorker` (`dart_pdf_editor/lib/src/render_worker.dart`) used to
make a private `Uint8List.fromList(bytes)` copy for **every** worker plus one
more for the urgent one-off lane - `N+1` copies of the source bytes on the main
isolate before any decode working set. For a pool of 3 over a 24 MB file that
is ~96 MB of source bytes just sitting there (the class doc acknowledged it).

The per-worker copy was defensive: the doc claimed "a platform worker may
transfer (and so detach) the buffer it is handed", so sharing one buffer would
leave later workers with an empty document. That is **not true of either
backend** as written:

- Native (`render_worker_isolate.dart`): the isolate is seeded with
  `TransferableTypedData.fromList([bytes])`. `fromList` copies the bytes into an
  external buffer at construction and does **not** neuter/detach its input - the
  same `Uint8List` can be wrapped by `fromList` any number of times and each
  materializes to the full data. (Verified empirically; the zero-copy transfer
  is the later `materialize()`, which each isolate does on its own copy.)
- Web (`render_worker_web.dart`): the worker either copies into a
  `SharedArrayBuffer` (`setAll`, a read) or does `Uint8List.fromList(bytes)`
  before transferring the copy's `ArrayBuffer`. The input `bytes` is never
  transferred/detached directly.

So both backends already copy internally, and the pool's own copy just
duplicated that. The fix: the pool makes **one** read-only snapshot and seeds
every worker - and the lazy urgent worker - from that single instance. Pool
source-byte footprint drops from `N+1` copies to exactly one; each isolate's
materialized copy inside its own isolate is unavoidable and unchanged.

## Shape of the change

- `PdfPooledRenderWorker(bytes, size)` is now a `factory` that snapshots the
  caller's bytes once and redirects to a private `_shared(snapshot, size,
  spawn)` generative ctor, which seeds all workers from `snapshot` and stores it
  as `_urgentBytes`.
- New `_spawnWorker` field (the worker factory, `startRenderWorker` in
  production) is reused by `_urgentWorkerFor`, which no longer re-copies with
  `Uint8List.fromList` - it hands the shared snapshot straight to the backend.
- Test seam `PdfPooledRenderWorker.withSpawner(bytes, size, spawn)` injects a
  fake spawner so a test can capture the byte view each worker (and the urgent
  lane) is handed and assert they are the **same instance**
  (`render_worker_test.dart`, two new cases in the `PdfPooledRenderWorker`
  group). The existing real-isolate `PdfRenderWorker.start` tests already cover
  the pooled path over live isolates and still replay pixel-identically.

## Deferred: the transfer half

The issue's second half - passing command graphs by `SendPort`/`Isolate.exit`
transfer on native instead of the `serializeCommands`/`deserializeCommands`
round-trip - is intentionally **not** done here. It is speculative (the codec
also normalizes geometry to float32 that the UI consumes, so a raw transfer is
not a pure win) and riskier; the shared-byte-view half is the safe first step
the issue called out. Left for a follow-up.
