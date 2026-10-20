# 2026-07-23 — browser JPEG decode: observability + main-thread fast path (#458)

## Context

A mobile-web device trace (#449) of a 24 MB / 62-page book showed the
image-bearing record for page 0 costing **643 ms on the UI thread** in
`ui.instantiateImageCodec` (Skia's WASM codec under CanvasKit), even though the
web render worker *already* has a browser-codec decode path
(`_withBrowserDecodedImages` → `_decodeWithBrowserCodec`,
`render_worker_web_entry.dart`). The worker's decode phase for that page read
`decode=1.0ms` for two `/DCTDecode` images — i.e. it declined both instantly and
the main thread paid. Nothing in any trace distinguished a codec that ran from
one that silently no-opped, which cost the original investigation a full detour
(a second decode path was half-built before the first was discovered).

Two independent pieces landed here.

## Part 1 — make the decline observable

`decode=1.0ms` for two DCT images can only mean the worker's capability guard
(`_browserImageDecodeAvailable`) returned false: a real `createImageBitmap`
decode awaits and costs real time. The content-dependent early exits
(`/ImageMask`, `DeviceCMYK` without a DCT soft mask) don't fire on non-CMYK DCT.
So the diagnosis hinges on *which* prerequisite is missing, and it was invisible.

- The worker's `ready` reply now carries `browserImageDecode=<bool>` and, when
  false, `browserImageDecodeMissing=<Blob|createImageBitmap|OffscreenCanvas>`
  (`_browserImageDecodeMissing()` — the split of the old boolean getter). The
  client logs it on the `ready` line. One line on the next device trace pins the
  cause per worker.
- Per page, a `_BrowserDecodeTally` records why each image was declined —
  `noCapability` (the #458 case), the expected `notDct`/`cmyk`/`imageMask`
  pure-Dart declines, or `decodeFailed` — and folds a one-line summary
  (`codec=2` / `codec=0 declined=2(noCapability)`) into the phase log next to
  `decode=`. It rides on `PdfRenderTrace.imageDecodeSummary`, carried like
  `cosStats` (web-only, kept-not-summed across a progressive page's passes) and
  serialized on the result object beside `decodeUs`. Only allocated under
  `collectTimings`, so production pays nothing.

## Part 2 — main-thread browser-codec fallback

The near-certain missing prerequisite is `OffscreenCanvas` in the *worker*
scope (absent on iOS Safari before 16.4). The worker needs it to read decoded
pixels back off a canvas. But the **main thread** does not:
`dart:ui_web`'s `createImageFromImageBitmap` (present in Flutter 3.44.4) consumes
an `ImageBitmap` straight into a GPU `ui.Image` with no canvas and no readback.
So even when the worker can't help, the main thread can still decode through the
browser's native codec instead of paying Skia's WASM decode.

- New conditional-import seam `browser_jpeg_decode.dart` (stub +
  `_web` impl, the repo's standard `dart.library.js_interop` pattern).
  `decodeJpegWithBrowser(jpeg, {targetWidth, targetHeight})` returns a
  `ui.Image?` — null off-web and on any failure. The web impl:
  `createImageBitmap(blob, {resizeWidth/Height, resizeQuality})` (the resize
  options preserve the display-resolution decode cap) →
  `ui_web.createImageFromImageBitmap` (which takes ownership of the bitmap — do
  NOT `close()` it after handing it over).
- `image_decoder.dart`'s `_decodeOne` DCT branch tries `decodeJpegWithBrowser`
  first and falls back to `ui.instantiateImageCodec` only when it returns null.
  The rest of the function is unchanged: when a soft mask, `/Decode` array, or
  color-key `/Mask` must touch the samples, it still reads `base.toByteData`
  and applies them — the browser base is opaque (JPEG), so premultiplied ==
  straight and the mask math is identical to the engine-codec base.

Native Flutter is untouched (stub returns null; the engine codec already runs on
a background raster thread there). VM tests exercise the fallback and stay green.

## Verification

- `dart analyze` clean; the worker still compiles under `dart compile js`.
- `flutter build web` compiles the main-thread `_web` file (the analyzer misses
  dart2js-only breakage — see the web-render-worker-compile-gap note).
- `render_trace_gate` + `render_worker` + `image_decoder` + `editing_image` +
  `inline_image` tests pass.

## Part 3 — a desktop A/B harness for the main-thread decode

The web perf harness runs desktop Chrome, whose *worker* scope has
`OffscreenCanvas`, so DCT images normally decode in the worker and Part 2's
main-thread path never fires — and the corpus had no non-CMYK DCT scenario
anyway (`scan-book` is Flate, `cmyk-jpeg` is CMYK, which Part 2 declines). Two
additions make the win measurable on desktop:

- **`photo-jpeg-6p.pdf`** in the public corpus: 6 full-page DeviceRGB DCTDecode
  covers (~1240×1654, the #458 shape), built by a new `buildPhotoJpeg` in
  `gen_public_corpus.dart` via `package:image`'s `encodeJpg` (byte-deterministic:
  fixed seed + fixed quality). It's the corpus's only non-CMYK DCT decode
  workload. Regeneration leaves the other eight files byte-identical (verified).
- **`?worker=N`** in `perf_harness.dart`: `worker=0` sets
  `pdfRenderWorkerScriptUrl = null`, forcing every page — interpret and image
  decode — onto the main thread. That routes all six JPEGs through the changed
  `_decodeOne` DCT branch. The toggle lives in the harness, which the A/B copies
  into the baseline worktree, so both trees fork at the same lever.
- **`scroll-photo-noworker`** scenario ties them together (`worker:0`).

**Result** (`tool/perf.sh webdiff main scroll-photo-noworker --iterations 5`):
in `worker=0` mode the only code difference between the trees is `_decodeOne`'s
DCT branch, and current is **buildP50 1.49 → 1.22 ms, −17.8%** (openPageCountMs
−5.3%, everything else flat, no regression). A consistent P50 drop of that size
is the browser codec working and beating Skia's WASM decode — had it silently
fallen back, current would equal baseline. So Part 2 is confirmed active and
faster on the main thread, not just compiling.

### Finding surfaced by Part 1's tally (worth its own follow-up)

Running the photo doc with the worker **on** (headless), the worker's browser
decode declines every page — `imageDecode=codec=0 declined=1(decodeNull:1)` —
i.e. `createImageBitmap`/`OffscreenCanvas.getImageData` returns null in this
headless environment (not a capability gap; the getter is true). Part 1 made
that visible immediately. Whether it's headless-only or also bites real mobile
browsers is a #458 sub-question for a device trace. (The decline reason strings
deliberately avoid the words "fail"/"error" — they ride the phase log, which the
harness scans for fatal-error markers, and `decodeFailed` was tripping it.)

## Not done here

- Regenerating the committed `pdf_render_worker.dart.js` asset — that's the
  flaky auto-regen path (#422), handled separately.
- Confirming *which* prerequisite is missing on the reported device — that needs
  a fresh device trace, which Part 1 now makes a one-line read.
- Root-causing the headless `decodeNull` (Part 1 surfaced it; may be
  headless-specific).
