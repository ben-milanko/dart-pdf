# 2026-07-22 - Warn once when web rendering falls back to the main thread

Follow-up to #465 (the `dart_pdf_editor_assets` split). Making the web render
worker an opt-in asset introduced a *silent* perf cliff: an existing app that
upgrades and doesn't add the assets package + `registerBundledEditorAssets()`
keeps working, but `pdfRenderWorkerScriptUrl` is now null by default, so every
page decodes on the main thread and long documents jank - with nothing in the
logs to explain why.

The fonts degrading quietly is fine (a menu group disappears, obvious enough);
the worker doing it is not. Ben's call (over bundling the worker by default or
leaving it fully silent) was to keep the full ~1.7 MB size win for viewer apps
but make the regression **discoverable in development**.

## Shape

`startRenderWorker` in `render_worker_web.dart` already returns
`_WebRenderWorker.disabled()` when the URL is null. Added a one-time advisory on
that branch:

- **Web-only by construction.** The helper lives in `render_worker_web.dart`,
  which is only selected by the `if (dart.library.js_interop)` conditional
  import. On native a null URL is the normal state (the isolate backend needs no
  script), and that code path never runs, so there is no false positive there.
- **Debug-only.** The whole body runs inside an `assert(() { ... }())`, so
  release and profile builds strip it and stay silent. This is the Flutter-free
  way to get debug-only behaviour - the library must keep compiling via
  `dart compile js` for the worker, so no `kDebugMode`/`foundation.dart` import.
- **Once per session.** A top-level `_warnedMainThreadRendering` bool guards it,
  so a 3-worker pool opening several documents logs it once, not per
  `startRenderWorker` call.
- **`developer.log(..., name: 'dart_pdf_editor.render_worker', level: 900)`** -
  the same channel the isolate backend already uses, at WARNING level, rather
  than `print` (banned by `flutter_lints`' `avoid_print`) or the perf-gated
  `_wlog`, which only surfaces when `PdfPerfLog` is enabled.

The message names the one-line fix (`registerBundledEditorAssets()` or a custom
`pdfRenderWorkerScriptUrl`) and notes it can be ignored if main-thread rendering
is intentional - the one case we can't distinguish from a forgotten opt-in.

## Not tested in VM `flutter test`

`render_worker_web.dart` is web-only; the package's `flutter test` runs on the
VM, where the conditional import picks the isolate/stub backend, so this branch
isn't reachable there (same as the rest of the file - validated through the
real-Chrome harness and web builds, not VM unit tests). `dart analyze` covers it
statically.
