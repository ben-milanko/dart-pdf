# Web Worker render backend

On native platforms `dart_pdf_editor` runs page interpretation on a background
**isolate** (`Isolate.spawn`), so the heavy content-stream parse and interpreter
walk don't block frames while scrolling. The web has no isolates, so the same
work runs on a **Web Worker** instead — but unlike the isolate, a Web Worker is
a *separately compiled script* the host app must build and serve. This document
is the wiring.

When no worker script is configured, the web build falls back to local
rendering on the main thread (the historical behavior) — so this is purely an
opt-in performance upgrade.

## How it fits together

```
main app  ──postMessage(init: ArrayBuffer)──▶  Web Worker (pdf_render_worker.dart.js)
          ──postMessage(record: page,id)───▶     opens the PdfDocument once,
          ◀─postMessage(ready)──────────────     serializeCommands(page) off-thread,
          ◀─postMessage(result: ArrayBuffer)─     transfers the buffer back

main app: deserializeCommands + PdfPageRenderer.pictureFromCommands (cheap replay
          + image decode) on the main thread, exactly like the isolate path.
```

The wire format is identical to the native backend — `serializeCommands` /
`deserializeCommands` produce a plain `Uint8List`, and image XObjects travel as
self-contained inline-resolved stream subgraphs — so the replay and image-decode
path (`pictureFromCommands`) is shared.

## Do I have to do anything?

**No — not to use the library.** With no worker configured, web rendering runs
on the main thread exactly as before, and if a configured worker script is
missing it degrades to that automatically. The Web Worker is a pure opt-in
performance upgrade. Skip this whole document and everything still works.

## Opt in (host web app)

1. **Build the worker** from your app root — one command, no hand-written entry:

   ```sh
   dart run dart_pdf_editor:build_web_worker
   ```

   This generates the worker entry (under `.dart_tool/`, so it never clutters
   your sources) and compiles it to `web/pdf_render_worker.dart.js`, which
   `flutter build web` and `flutter run` serve next to `index.html`.

2. **Point the app at it** once, in `main()` (web only):

   ```dart
   import 'package:dart_pdf_editor/dart_pdf_editor.dart';
   import 'package:flutter/foundation.dart';

   void main() {
     if (kIsWeb) {
       pdfRenderWorkerScriptUrl = 'pdf_render_worker.dart.js';
     }
     runApp(...);
   }
   ```

That's it — `PdfReader` / `PdfEditorView` pick up the worker automatically (the
shells call `PdfRenderWorker.start`, which routes to the Web Worker backend when
the URL is set).

### Does it run every build?

**It doesn't have to.** `web/pdf_render_worker.dart.js` is a static file. You can
either:

- **Commit it** and re-run `dart run dart_pdf_editor:build_web_worker` only when
  you upgrade `dart_pdf_editor` (the bundle embeds the library, so a stale one
  would replay an old renderer) — zero per-build cost; or
- **Gitignore it** and run the command before each `flutter build web` (e.g. a
  `tool/build_web.sh` wrapper that runs the tool, then `flutter build web`).

Either way, if the file is missing or stale-by-absence the app just renders
locally — a forgotten rebuild degrades gracefully, it never breaks.

## Status

The backend is wired end to end. `render_worker_web.dart` (main-side worker) and
`render_worker_web_entry.dart` (worker-side entry) mirror the isolate backend's
priority queue and protocol, and the app is wired up:

- `dart run dart_pdf_editor:build_web_worker` builds the worker;
  `app/lib/main.dart` sets `pdfRenderWorkerScriptUrl` on web.
- `dart compile js` of the worker entry **succeeds** (~720 KB bundle), so the
  `dart:js_interop` / `package:web` usage is valid on the web toolchain.
- **Verified live** under `flutter run -d chrome` against the 41 MB / 133-page
  CAD test doc: every page round-tripped through the worker (`path=worker`),
  the transferred `ArrayBuffer`s replay correctly, and the main-thread interpret
  time roughly halved (the residual is replay + image decode). This surfaced a
  real bug — the command codec used `ByteData.setInt64`/`getInt64`, which throw
  on the web (no JS 64-bit int); now float64-encoded (exact ≤ 2^53).

Still open — see issue #73:

- Offload the image *decode* too (issue #73 item 1); on web that is even more
  valuable since there is no separate raster thread, and it is the bulk of the
  remaining per-page time.

## Caveats

- **Not** cross-origin isolation / `SharedArrayBuffer`. This uses an ordinary
  dedicated worker with transferable `ArrayBuffer`s, so it needs no COOP/COEP
  headers. (skwasm's multithreading, which *does* need those headers,
  parallelizes raster — not interpretation — and is unrelated.)
- The worker holds a fixed snapshot of the document bytes, like the isolate; an
  editing session must restart the worker when the bytes change (the shells
  already do this on every revision).

## WebAssembly (dart2wasm) hosts

No special handling is needed when the main app is compiled to Wasm
(`flutter build web --wasm`):

- The worker is a **separately compiled JS bundle** loaded by URL, independent
  of how the host is compiled — a dart2wasm app constructs and drives it just
  like a dart2js app.
- The client half (constructing the `web.Worker`, `postMessage`, reading
  results) uses only `dart:js_interop` / `package:web`, which compile under
  **both** dart2js and dart2wasm. The backend is selected on
  `dart.library.js_interop` (provided on Wasm) — deliberately **not**
  `dart.library.html`, which is unavailable on Wasm and would break the build.
- The boundary carries **transferred `ArrayBuffer`s** (raw bytes), not Dart
  objects, so neither side depends on the other's compilation. The host pays one
  buffer copy from Wasm linear memory into a JS `ArrayBuffer` per document and
  per result (via `.toJS`) — negligible.

The worker itself stays JS (`dart compile js`) even under a Wasm host. Compiling
*the worker* to Wasm (`dart compile wasm`) is possible but needs a different
in-worker bootstrap (its `.mjs` loader instantiating the module) and buys little
— the worker is already off the main thread. A skwasm host that sets COOP/COEP
for its own raster threads keeps working unchanged: this is an ordinary
same-origin dedicated worker with no `SharedArrayBuffer`, so those headers
neither help nor hinder it.
