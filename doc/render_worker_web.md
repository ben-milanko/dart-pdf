# Web Worker render backend

On native platforms `dart_pdf_editor` runs page interpretation on a background
**isolate** (`Isolate.spawn`), so the heavy content-stream parse and interpreter
walk don't block frames while scrolling. The web has no isolates, so the same
work runs on a **Web Worker** instead. Unlike the isolate, a Web Worker is a
*separately compiled script* the host app must build and serve. This document
shows the wiring.

When no worker script is configured, the web build falls back to local
rendering on the main thread. This is purely an opt-in performance upgrade.

## How it fits together

```
main app  ──postMessage(init: ArrayBuffer)──▶  Web Worker (pdf_render_worker.dart.js)
          ──postMessage(record: page,id)───▶     opens the PdfDocument once,
          ◀─postMessage(ready)──────────────     serializeCommands(page) off-thread,
          ◀─postMessage(result: ArrayBuffer)─     transfers the buffer back

main app: deserializeCommands + PdfPageRenderer.pictureFromCommands (cheap replay
          + a final engine codec upload) on the main thread, like the isolate.
```

The wire format is identical to the native backend. `serializeCommands` and
`deserializeCommands` produce a plain `Uint8List`, and image XObjects travel as
self-contained inline-resolved stream subgraphs, so the replay path
(`pictureFromCommands`) is shared. The worker also runs the pure-Dart **image
decode** (`serializeCommands(decodeImages: true)`): premultiplied RGBA rides
beside each image command, so the main thread only runs `decodeImageFromPixels`,
never the Flate inflate / colour-convert. That matters on the web because there
is no separate raster thread; an on-main-thread decode would block frames. Images
that need the platform JPEG codec (a non-CMYK DCTDecode base) ship un-decoded
and decode on the main thread as before.

## Do I have to do anything?

**No, not to use the library.** With no worker configured, web rendering runs
on the main thread exactly as before, and if a configured worker script is
missing it degrades to that automatically. The Web Worker is a pure opt-in
performance upgrade. Skip this whole document and everything still works.

## Opt in (host web app)

1. **Build the worker** from your app root. One command generates the entry.
   Run it after `flutter pub get`, from the same directory that has your
   app's `pubspec.yaml` and `web/` folder:

   ```sh
   dart run dart_pdf_editor:build_web_worker
   ```

   This generates the worker entry under `.dart_tool/`, so it never clutters
   your sources, and compiles it to `web/pdf_render_worker.dart.js`, which
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

That's it. `PdfReader` / `PdfEditorView` pick up the worker automatically (the
shells call `PdfRenderWorker.start`, which routes to the Web Worker backend when
the URL is set).

### Does it run every build?

**It doesn't have to.** `web/pdf_render_worker.dart.js` is a static file. You can
either:

- **Commit it** and re-run `dart run dart_pdf_editor:build_web_worker` only when
  you upgrade `dart_pdf_editor` (the bundle embeds the library, so a stale one
  would replay an old renderer). That keeps build time unchanged; or
- **Gitignore it** and run the command before each `flutter build web` (e.g. a
  `tool/build_web.sh` wrapper that runs the tool, then `flutter build web`).

Either way, if the file is missing or stale-by-absence the app just renders
locally. A forgotten rebuild degrades gracefully; it never breaks.

## Status

The backend is wired end to end. `render_worker_web.dart` (main-side worker) and
`render_worker_web_entry.dart` (worker-side entry) mirror the isolate backend's
priority queue and protocol, and the app is wired up:

- `dart run dart_pdf_editor:build_web_worker` builds the worker; both
  `app/lib/app.dart` and the example app set `pdfRenderWorkerScriptUrl` on
  web. The live web deploys (the demo at `dart-pdf-demo.web.app` and the app at
  `dartpdf-app.web.app`) build the worker and ship the `--wasm` renderer with
  COOP/COEP headers. See `deploy-demo-web.yml` and the firebase configs.
- `dart compile js` of the worker entry **succeeds** (~720 KB bundle), so the
  `dart:js_interop` / `package:web` usage is valid on the web toolchain.
- **Verified live** under `flutter run -d chrome` against the 41 MB / 133-page
  CAD test doc: every page round-tripped through the worker (`path=worker`),
  the transferred `ArrayBuffer`s replay correctly, and the main-thread interpret
  time roughly halved. This surfaced a real bug: the command codec used
  `ByteData.setInt64`/`getInt64`, which throw on the web (no JS 64-bit int);
  now float64-encoded (exact ≤ 2^53).
- **Image decode is offloaded too** (issue #73 item 1): the pure-Dart decode
  moved into `pdf_graphics` (`decodePdfImagePixels`), and the worker runs it
  during recording, shipping premultiplied RGBA. The main thread now only runs
  the engine codec. Verify a raster-heavy CAD sheet with `PDF_PERF_LOG=true`:
  the page goes crisp without a large synchronous decode in the trace.

- **Superseded prefetches are cancelled** (issue #73 item 2): scrolling past a
  page drops its still-queued render request (`PdfRenderWorker.cancel`) instead
  of letting the worker grind through stale work, so the visible page's job is
  reached sooner.

Still open; see issue #73:

- The in-flight worker/isolate job still can't be *preempted* (item 3): a
  request already executing in the worker runs to completion even if you land
  on another page mid-prefetch. Only *queued* requests are cancelled (above);
  the fast-scroll page preview covers the remaining gap visually.
- v1 ships decoded pixels on every record; a re-record of a page already
  cached on the main side re-decodes in the worker (off-thread, so it never
  janks, but it is redundant work). A `knownKeys` skip is the next refinement.

## Caveats

- **Not** cross-origin isolation / `SharedArrayBuffer`. This uses an ordinary
  dedicated worker with transferable `ArrayBuffer`s, so it needs no COOP/COEP
  headers. (skwasm's multithreading, which *does* need those headers,
  parallelizes raster, not interpretation, and is unrelated.)
- The worker holds a fixed snapshot of the document bytes, like the isolate; an
  editing session must restart the worker when the bytes change (the shells
  already do this on every revision).

## WebAssembly (dart2wasm) hosts

No special handling is needed when the main app is compiled to Wasm
(`flutter build web --wasm`):

- The worker is a **separately compiled JS bundle** loaded by URL, independent
  of how the host is compiled. A dart2wasm app constructs and drives it just
  like a dart2js app.
- The client half (constructing the `web.Worker`, `postMessage`, reading
  results) uses only `dart:js_interop` / `package:web`, which compile under
  **both** dart2js and dart2wasm. The backend is selected on
  `dart.library.js_interop` (provided on Wasm), deliberately **not**
  `dart.library.html`, which is unavailable on Wasm and would break the build.
- The boundary carries **transferred `ArrayBuffer`s** (raw bytes), not Dart
  objects, so neither side depends on the other's compilation. The host pays one
  buffer copy from Wasm linear memory into a JS `ArrayBuffer` per document and
  per result (via `.toJS`), which is negligible.

The worker itself stays JS (`dart compile js`) even under a Wasm host. Compiling
*the worker* to Wasm (`dart compile wasm`) is possible but needs a different
in-worker bootstrap (its `.mjs` loader instantiating the module) and buys little
because the worker is already off the main thread. A skwasm host that sets COOP/COEP
for its own raster threads keeps working unchanged: this is an ordinary
same-origin dedicated worker with no `SharedArrayBuffer`, so those headers
neither help nor hinder it.
