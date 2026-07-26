# A default render worker for a bare PdfViewer (#396 part 1)

Page interpretation runs on the UI thread unless a `PdfRenderWorker` is attached.
The shipping app attaches one through `PdfShellSessionLifecycle`, so it is fine -
but a host embedding a bare `PdfViewer` (and the comparison view, which mounts two)
got on-thread interpretation and the frame-freezing that comes with it. Part 1
makes the viewer stand up its own worker by default.

## Extraction first (behavior-preserving)

The worker lifecycle - incremental `updateRevision` for a byte-prefix append vs a
full restart otherwise (#308), generation counting, dispose - lived inside
`PdfShellSessionLifecycle._syncWorker`. Pulled it into `PdfRenderWorkerHost`
(`render_worker_host.dart`), a widget/editing-free state machine:
`sync({document, bytes, pageCount, revision})` + `dispose()`, with a `workerCount`
provider and an `onGeneration` hook (the shell's diagnostics log). The shell now
delegates; all shell/session/revision tests pass unchanged. This is what lets the
viewer reuse the *identical* logic instead of a second copy that drifts.

## The viewer wiring

`_PdfViewerState` owns a `PdfRenderWorkerHost` when `renderWorker == null` and
`autoRenderWorker` (new, default true). `_syncDefaultWorker()`:

- **Editing/form session** - drives the host from the revision controller's
  revision-aware `bytes` + `lastRevisionDelta`, so each edit streams in
  incrementally and the worker never renders a stale page. Called from
  `_onRevisionControllerChanged` (per revision), `didUpdateWidget`, and
  `initState`.
- **Read-only document** - drives it from `document.cos.bytes`, no revisions.

A single `_effectiveRenderWorker` getter (`widget.renderWorker ?? host.worker`)
replaces every `widget.renderWorker` read in the state, so the default fills in
transparently; children receive it through the existing `renderWorker:`
pass-downs. Disposed in `dispose()`.

### Deliberate choices

- **Single worker, not a pool.** `workerCount: () => 1`, so a bare viewer - or
  several on one screen (the comparison panes) - costs at most one isolate each.
  A pooled multi-worker backend for a long document still needs an explicit
  `renderWorker` via the shell.
- **Opt-out** via `autoRenderWorker: false` (force on-thread) - documented for a
  host that mounts many viewers or manages its own workers. An explicit
  `renderWorker` always wins; the shell paths (`pdf_reader`, `pdf_editor_view`)
  pass `_shell.worker`, so no redundant worker under the shell.
- **Web is safe by default.** With no worker script, `startRenderWorker` returns
  an inactive worker and the viewer already falls back to on-thread - unchanged.
- **Async activation.** Like the shell's non-prewarmed path, the worker's
  `isActive` flips true after the isolate handshake; the first frame may render
  on-thread and later pages use the worker. No activation-rebuild machinery.

## Tests

- `render_worker_host_test.dart` - the state machine with a fake worker via a new
  `PdfRenderWorkerHost.debugSpawnOverride` seam: first sync starts one generation,
  same document is a no-op, a byte-prefix append updates in place (no new
  generation), a length-mismatch restarts (old worker disposed), dispose is
  idempotent, `onGeneration` fires per fresh generation only.
- `default_worker_test.dart` - the viewer wiring: a bare viewer spawns one single
  worker, `autoRenderWorker: false` spawns none, an explicit `renderWorker`
  suppresses the default (and isn't disposed by the viewer), the default is
  disposed with the viewer, and an editing session gets one too.

### Suite-wide: default worker off in tests

Auto-spawning a real isolate per viewer turned synchronous render assertions
async - three editing render-timing tests (eraser/interaction/stamps) saw
`committed` instead of `rasterReady` because the worker record hadn't landed in
the pump budget. So `flutter_test_config.dart` sets
`PdfViewer.debugAutoRenderWorkerEnabled = false` for the whole suite (deterministic
on-thread, no isolates, no test slowdown); `default_worker_test.dart` re-enables
it. Worker-specific suites already spin up their own real workers explicitly and
are unaffected.

The remaining ghent CMYK/overprint baseline failures are pre-existing (#550 -
they fail on clean main and `ghent_render_test` never touches `PdfViewer`), not a
regression here.

## Not done here

Part 2 (an off-thread `extractText` worker job for search/hover) still routes
extraction on the UI thread; its web half needs the #422/#571
`WORKER_REGEN_TOKEN`. Part 3 (search yields per page) shipped separately (#575).

Files: `render_worker_host.dart` (new), `shell_session.dart`, `pdf_viewer.dart`,
`test/render_worker_host_test.dart` (new), `test/default_worker_test.dart` (new),
`test/flutter_test_config.dart`.
