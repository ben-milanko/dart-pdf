# Web Worker render backend

On native platforms `dart_pdf_editor` runs page interpretation on a background
**isolate** (`Isolate.spawn`), so the heavy content-stream parse and interpreter
walk don't block frames while scrolling. The web has no isolates, so the same
work runs on a **Web Worker** instead. Unlike the isolate, a Web Worker is a
*separately compiled script*. `dart_pdf_editor` ships one as a Flutter package
asset and uses it by default; this document shows how that works and how to
override it.

When no worker script is configured, or the script fails to load, the web build
falls back to local rendering on the main thread.

## How it fits together

```
main app  ──postMessage(init: ArrayBuffer)──▶  Web Worker (pdf_render_worker.dart.js)
          ──postMessage(record: page,id)───▶     opens the PdfDocument once,
          ──postMessage(bin: geometry,id)──▶     records/caches strip commands,
          ──postMessage(surface: canvas)───▶     optionally owns a page canvas,
          ◀─postMessage(ready)──────────────     serializeCommands(page) off-thread,
          ◀─postMessage(result: ArrayBuffer)─     transfers commands/plans back

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

Dense-page strip plans use the same worker queue and transferable result shape.
The worker keeps a two-entry LRU of wire-round-tripped command recordings, so
repeat zoom settles re-bin stable command objects without re-interpreting the
page and preserve the glyph/shape strip caches. `cancelBinStrips` drops queued
plans and cooperatively stops an in-flight stale geometry. The main-side pool
keeps the native static-page affinity, so one zoom session repeatedly reaches
the same worker cache.

### Experimental worker-owned page surfaces

The PDFium parity work also has a default-off web experiment that transfers a
page's `OffscreenCanvas` to one worker for its lifetime. A `surface` request
then interprets and paints directly with Canvas2D; only a one-byte
success/decline reply returns to the main thread. This removes the normal
SkWasm `ui.Image` raster, readback, pixel transfer, and main-surface upload from
the interaction's critical path. Pooled workers bind a page's full canvas and
deep-zoom region canvas to the same capable lane, because a transferred canvas
cannot migrate later and the region should reuse the base surface's transcript
and decoded-image samples.

The current Canvas2D device is intentionally a correctness-gated profile, not
a second general renderer. It accepts ordinary paths, strokes, substituted
fill text, and supported decoded images, and checks the complete transcript
before touching the canvas. Simple 8-bit DeviceGray Flate scans can stay in
browser-native luma frames; other admitted images use the shared decoder.
Embedded glyph outlines, gradients, groups, masks, and every other unsupported
command decline to the established Flutter renderer. At deep zoom a retained
full-page backing is capped at 2× and a viewport-sized worker canvas supplies
the visible 3× slice, avoiding a multi-megapixel full-page DOM commit. Focused
full-page surfaces otherwise paint directly at the requested size in both zoom
directions; scaling down a larger Canvas2D backing made thin vector strokes
visibly lighter. Each live surface retains an exact-size `ImageBitmap` LRU
bounded to 8 MP / 32 MiB total. This keeps repeated smaller zoom levels without
replaying dense command streams or re-decoding scans, while oversized entries
repaint and consume no cache space. The worker-surface scroll settle is 120 ms;
the established Flutter renderer keeps its 500 ms debounce.

The app and performance harness enable this only with `?domSurface=1`;
`PdfPageView` leaves `webDomRasterPresentation` false by default, so package
users are unaffected.
`tool/perf.sh surface-check` compares the profile with the established renderer
across real plan, scan, text, and diagram samples before performance results are
accepted.

## Do I have to do anything?

**One line.** The worker script ships in the optional `dart_pdf_editor_assets`
package (it used to be a `dart_pdf_editor` asset, but was split out so
viewer-only apps don't bundle its ~0.48 MB). Depend on that package and call
`registerBundledEditorAssets()` once at startup - it sets
`pdfRenderWorkerScriptUrl` to Flutter's package asset path:

```text
assets/packages/dart_pdf_editor_assets/assets/web/pdf_render_worker.dart.js
```

Without that call, `pdfRenderWorkerScriptUrl` is null and web rendering runs on
the main thread. If a worker URL is set but the script cannot load, the viewer
degrades to main-thread rendering too. Set `pdfRenderWorkerScriptUrl = null`
before opening a viewer to force that fallback explicitly.

## Self-host the worker (optional)

Most apps should use the bundled package asset. Self-host only when you want the
worker at an app-owned URL, need custom cache headers, or want to regenerate the
worker in the app build pipeline.

1. **Build the custom worker** from your app root. One command generates the
   entry. Run it after `flutter pub get`, from the same directory that has your
   app's `pubspec.yaml` and `web/` folder:

   ```sh
   dart run dart_pdf_editor:build_web_worker
   ```

   This generates the worker entry under `.dart_tool/`, so it never clutters
   your sources, and compiles it to `web/pdf_render_worker.dart.js`, which
   `flutter build web` and `flutter run` serve next to `index.html`.

2. **Point the app at that custom URL** once, before opening a viewer:

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

Without this override, `PdfReader` / `PdfEditorView` use the bundled package
asset automatically (the shells call `PdfRenderWorker.start`, which routes to
the Web Worker backend when the URL is non-null).

### Does it run every build?

**It doesn't have to.** A self-hosted `web/pdf_render_worker.dart.js` is a static
file. You can either:

- **Commit it** and re-run `dart run dart_pdf_editor:build_web_worker` only when
  you upgrade `dart_pdf_editor` (the bundle embeds the library, so a stale one
  would replay an old renderer). That keeps build time unchanged; or
- **Gitignore it** and run the command before each `flutter build web` (e.g. a
  `tool/build_web.sh` wrapper that runs the tool, then `flutter build web`).

Either way, if the custom file is missing or stale-by-absence the app just
renders locally. A forgotten rebuild degrades gracefully; it never breaks.

## Working on this repository

The real bundled worker asset
(`packages/dart_pdf_editor_assets/assets/web/pdf_render_worker.dart.js`) is a
~1 MB `dart compile js` output that is **not committed** (issue #582) - two
`dart2js` outputs can't be merged textually, so committing a bundle that almost
every source change regenerates was a constant source of unmergeable diffs, and
its `.js.deps` sibling leaked absolute local pub-cache paths.

Because that path is a *declared Flutter asset* (it has to be, so it ships in
the pub.dev package and loads at the `assets/packages/...` URL), it can't simply
be absent: `dart analyze` and **every** `flutter build` - web *and native*,
since Flutter bundles a package's declared assets on every target - fail on a
missing declared asset. So a small, stable **placeholder** is committed in its
place, and the real bundle is generated over it at the points that actually
serve it to the web:

- **Publishing:** `tool/release.sh` runs `build_web_worker` before
  `pub publish` (and restores the placeholder afterward), so the pub.dev archive
  ships the real worker.
- **Deploying / previewing / releasing the web app:** the deploy, preview, and
  release workflows already run `build_web_worker --out .../pdf_render_worker.dart.js`
  before `flutter build web`.
- **Local web builds:** `app/tool/build_web.sh` regenerates it first.

The placeholder throws on load, so if it is ever the file actually served on the
web (e.g. a bare `flutter run -d chrome` straight from a clone, without
`build_web.sh`), the client's worker `onerror` handler falls back to main-thread
rendering - the same graceful degradation as an unset worker URL. To get real
off-thread rendering in that inner loop, generate the bundle once (only needed
again when you change worker-linked source):

```sh
dart run dart_pdf_editor:build_web_worker \
  --out packages/dart_pdf_editor_assets/assets/web/pdf_render_worker.dart.js
```

or just route local web work through `app/tool/build_web.sh`, which does this
for you. That leaves the ~1 MB bundle in your working tree as an uncommitted
modification of the placeholder; `git checkout` the path to restore it (CI's
`worker-compiles` job guards that the committed file stays the small
placeholder, and also compiles the worker to catch `dart2js`/`.toJS` errors
`dart analyze` misses).

## Status

The backend is wired end to end. `render_worker_web.dart` (main-side worker) and
`render_worker_web_entry.dart` (worker-side entry) mirror the isolate backend's
priority queue and protocol, and the app is wired up:

- The package ships a prebuilt worker asset and uses it by default. The helper
  `dart run dart_pdf_editor:build_web_worker` still builds a self-hosted worker
  for apps that want to override `pdfRenderWorkerScriptUrl`. The live web
  deploys (the demo at `dart-pdf-demo.web.app` and the app at
  `dartpdf-app.web.app`) ship the `--wasm` renderer with COOP/COEP headers. See
  `deploy-demo-web.yml` and the firebase configs.
- `dart compile js` of the worker entry **succeeds** (~857 KB bundle), so the
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

- **In-flight preemption** (issue #73 item 3): when a higher-priority request
  (e.g. the on-screen page at priority 0) arrives while a lower-priority job
  (e.g. a prefetch at priority 1) is executing, the worker cancels the
  in-flight job cooperatively via `PdfCancellationToken` and serves the urgent
  request next. The interpreter checks the token every 64 operators and yields
  to the event loop every 512 operators (via `drawPageOperationsAsync`), so a
  cancel message (sent over the isolate's cancel port or the Web Worker's
  `{kind:'cancel'}` message) fires within a few hundred operators. The
  cancelled job resolves to null (local render); the preempting request gets
  the worker's next slot immediately.

- **Strip binning and routing** (issue #217): `binStrips` is a real Web Worker
  request instead of the old null fallback. Encoded plans transfer as
  `ArrayBuffer`s, decode on the main side, and feed the same sparse-strip
  device used by native Impeller. A production-shaped browser probe verified
  an 11-batch worker plan byte-for-byte against local binning and successfully
  rasterized its plan-fed output at 612×792. Web therefore participates in
  the dense-page strip route; native software Skia remains gated out because
  its shader interpreter loses to the canvas path.

Still open:

- v1 ships decoded pixels on every record; a re-record of a page already
  cached on the main side re-decodes in the worker (off-thread, so it never
  janks, but it is redundant work). A `knownKeys` skip is the next refinement.

## Caveats

- Cross-origin isolation is optional, but useful. On an isolated page with
  `SharedArrayBuffer` available, each render worker receives a shared view of
  the document bytes instead of its own cloned `ArrayBuffer`. Hosts without
  COOP/COEP, Safari, or apps that set `pdfRenderWorkerUseSharedArrayBuffer =
  false` fall back to the older transferable `ArrayBuffer` startup path. Result
  buffers are still transferred `ArrayBuffer`s either way.
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
- The boundary carries raw bytes, not Dart objects, so neither side depends on
  the other's compilation. On cross-origin isolated pages the document bytes use
  `SharedArrayBuffer`; otherwise the host pays one buffer copy from Wasm linear
  memory into a JS `ArrayBuffer` per worker at startup. Results remain
  transferred `ArrayBuffer`s.

The worker itself stays JS (`dart compile js`) even under a Wasm host. Compiling
*the worker* to Wasm (`dart compile wasm`) is possible but needs a different
in-worker bootstrap (its `.mjs` loader instantiating the module) and buys little
because the worker is already off the main thread. A skwasm host that sets
COOP/COEP for its own raster threads now also lets the render worker share the
opened document bytes across the worker pool.
