# OCR accuracy: a benchmark, and what it found

A user's A3 interlocking drawing (/Rotate 90, ~7pt labels sitting on track
dots) came back from OCR with `(FSFCR)` read as `(FSCRC)`, `(Cab T)` as
`(Cab) (FSCR)`, `D27` as `D2Z`. That layer came from the **browser** path: its
boxes all sit on Florence-2's 1000-bin grid over 1024 px tiles (0.512pt steps
at the 2x raster). There was no way to measure either engine, so this session
built one and used it on both.

## The benchmark

- **Fixture:** `buildOcrDrawingSheet` (pdf_test_fixtures,
  `ocr_drawing_sheet.dart`) - a seeded sheet with the real one's geometry:
  portrait A3 + /Rotate 90, 4.9pt dots, 7.2pt labels whose paren bottoms sit
  0.36pt above the dot, IDs 2pt below, a title block. Codes are random
  capitals so no language prior can guess them. Text is an **embedded**
  Liberation Sans (Arial metrics): a base-14 Helvetica goes through Flutter's
  text stack, which `flutter test` paints as **Ahem boxes** - the first run
  "measured" black rectangles (CER 99.9%).
- **Scorer:** `scoreOcrAccuracy` (pdf_test_fixtures, `ocr_accuracy.dart`):
  each span goes to the truth label it overlaps most; a label's reading is its
  spans joined along its long axis (rotation-agnostic). Exact-match rate, CER
  (a missed label costs its length), misses, and extras (spans on no label).
  Merging two labels costs both - one reads too long, the other is missed.
- **PP-OCR harness:** `pdf_ocr_ondevice/test/accuracy/ocr_accuracy_test.dart`,
  opt-in on `PDF_OCR_MODEL_DIR` (the three `ocr-models-v1` release files).
  `onnxruntime` 1.4.1 ships `linux/libonnxruntime.so.1.15.1`, so it runs under
  `flutter test` on Linux with that dir on `LD_LIBRARY_PATH`. Env knobs for a
  sweep: `PDF_OCR_PIXEL_RATIO`, `PDF_OCR_DET_SIDE`, `PDF_OCR_UNCLIP`,
  `PDF_OCR_BOX_THRESH`, `PDF_OCR_DET_THRESH`, `PDF_OCR_RAW=1`,
  `PDF_OCR_ISOLATE=1`; `PDF_OCR_REAL_PDF` + `PDF_OCR_REAL_TRUTH` add a real
  page against a JSON truth list (kept out of the repo).
- **Web harness:** `app/tool/perf/ocr_web_bridge.mjs` hosts the browser OCR
  bridge **lifted verbatim from web/index.html** in headless Chromium (served
  COOP + COEP credentialless like firebase.json, so onnxruntime-web runs
  threaded) and exposes it on localhost; `PDF_OCR_WEB_BRIDGE=<url>` makes the
  PP-OCR harness run the same `PpOcrPipeline` against it. Tensors cross over
  HTTP (the page fetches its input and posts its output back to the script),
  not DevTools - a detection input is ~100 MB and a recognition output ~17 MB
  per batch, so the harness's wall time overstates the app's (measured
  in-page instead, below). In a sandbox whose TLS proxy Chromium doesn't
  trust, `OCR_FETCH_VIA_NODE=1 NODE_USE_ENV_PROXY=1` 307s the page's https
  requests to the script's relay, which fetches from Node (verified against
  `NODE_EXTRA_CA_CERTS`) through a disk cache. Gotcha: a `BytesBuilder`
  `takeBytes()` chunk can be a view into a larger buffer - `.buffer` viewed
  whole read past the tensor (a RangeError in box extraction).
- **Real page truth:** 154 labels transcribed from a 300 dpi render, boxes from
  connected-component clustering of the ink (kept out of the repo).

## PP-OCR (on-device) - what was wrong and what fixed it

| config (A3 sheet)                                  | synthetic exact / CER | real exact / CER |
|----------------------------------------------------|-----------------------|------------------|
| before: 2x, det <= 960, scale-unclip 1.6, rec 512  | 18.1% / 68.8%         | 24.7% / 55.5%    |
| new post-process, det <= 960                       | 20.9% / 67.4%         | 21.4% / 57.1%    |
| new post-process, 2x, det <= 2400                  | 84.8% / 7.0%          | 62.3% / 22.7%    |
| new post-process, 3x, det <= 4000                  | 89.3% / 4.6%          | 77.3% / 15.8%    |
| + `cleanRecognizedText` (shipped default)          | **95.0% / 1.4%**      | **82.5% / 13.2%**|
| 4x, det <= 4000                                    | 90.8% / 3.4%          | 75.3% / 17.2%    |
| 3x, det <= 3200                                    | 81.9% / 7.9%          | 77.3% / 14.4%    |
| 3x, det <= 4000, unclip 2.0                        | 78.8% / 9.7%          | 72.1% / 19.5%    |

1. **Detection was squeezed to 960 px** (`detectionSideLimit`). On an A3 page
   at 2x that is a 0.4 downscale: 5pt capitals at ~4 px, and the 0.36pt gap
   between a label and its dot vanishes, so the probability map fuses label +
   dot + ID into one blob and the recognizer reads a three-line crop
   (`(FSFCR) $27fr}$`). PaddleOCR's own PP-OCRv5 pipeline caps at 4000
   (`max_side_limit`) and otherwise doesn't downscale. Default now 4000.
2. **Raster resolution.** `OnDeviceOcrEngine.pixelRatioFor(page)`: 3 px/pt
   (216 dpi), capped so the longest side fits 4000 px (no point rasterizing
   what detection would shrink; bounds memory - A0 at 3x would be ~290 MB).
   The app's native job uses it. 4x gains nothing on A3 (the cap shrinks it).
3. **Unclip** scaled the box 1.6x about its centre: a long label's ends grew
   30% into its neighbours while its height barely grew. DB's unclip is a
   distance offset `area * ratio / perimeter` (PaddleOCR `DBPostProcess`,
   ratio 1.5). Box-score threshold 0.6 (PaddleOCR's).
4. **Recognition width**: every crop was padded/squashed into 512 px. Now
   aspect-preserving, padded to >= 320 (PaddleOCR `resize_norm_img`); the
   model is fully convolutional along x. Faster too (less padding).
5. **Drawing symbols**: the multilingual dict carries `● ▲ ▼ △`, and on a
   drawing the detector boxes dots/triangles, so lines came back `F12 ●`,
   `▲8`, or just `●`. `cleanRecognizedText` strips U+25A0-25FF and drops
   lines with no letter/digit: extras 158 -> 4 on the synthetic sheet.
6. **Speed**: `OrtValueTensor.value` builds nested `List`s of boxed doubles.
   A rec output is `[1, T, 18385]` - >1M boxed numbers per line - and
   profiling one page showed 113 s of 155 s spent there (`.value` 87 s +
   flatten 26 s; det run 6.8 s, rec run 30 s). `readFloatTensor`
   (`ort_tensor_data.dart`) reads the buffer through the package's generated
   C-API bindings (an implementation import - the package exposes no other
   route), with `.value` as the fallback for non-float outputs. Page time
   134 s -> 36 s at identical accuracy (85 s before this session, at 18%).

What is left: `I`/`1` and `O`/`0` in random IDs (genuinely near-identical in
Arial at 5pt), isolated single digits the detector doesn't box, `(FSFCR)`
reading as `[FSFCR]` on the real sheet, and the relay contact rows (`5 A 6`)
reading as one line - fine for search, but the scorer counts it against the
labels.

## Web: Florence-2 replaced by the same PP-OCR pipeline

Florence-2 (Transformers.js, 1024 px tiles -> its 768 input, q4) read the
synthetic sheet at **21.5% exact, CER 80.3%** - mostly *invented* text
(`X11` -> `X1.1`, `(HZVMP)` -> `(H)ZVMP) (HZVMP)`, `(PSK)` -> a neighbour's
`(UXBRC)`): a generative model fills unclear print with plausible tokens, which
is the user's `(FSCRC)`/`(FSCR)`. (Smaller tiles were being measured when the
decision was made; at ~125 s a tile on CPU it was 1.7x the time per page anyway.)
The web now runs PP-OCR:

- **Shared pipeline.** `PpOcrPipeline` (pdf_ocr_ondevice, plain Dart) does
  everything but the two network calls, behind `PpOcrInference`;
  `OnnxOcrModelRunner` is it over FFI sessions. `package:pdf_ocr_ondevice/
  pp_ocr.dart` is the web-safe library (no `dart:io`/FFI); `OcrRunnerEngine`
  is the backend-agnostic `PdfOcrEngine` (`OnDeviceOcrEngine` extends it).
- **Bridge.** `web/index.html`: `__dartPdfOcrLoad` (sessions + dictionary)
  and `__dartPdfOcrRun(name, Float32Array, dims)`, onnxruntime-web 1.30.0
  from jsDelivr - the WASM-only build unless `requestAdapter()` returns an
  adapter (then the WebGPU build, EPs `['webgpu', 'wasm']`); `numThreads` 4 on
  a cross-origin-isolated page. Keeps #1013's `__dartPdfOcrOnProgress` hook
  (`download` over the two .onnx files, then `preparing`). Models are kept in
  the Cache API (`dart-pdf-ocr-pp-ocrv5-mobile-v1` - bump it with the files).
- **Hosting.** GitHub release downloads send no CORS headers, so the models
  are served from the app's origin: `tool/fetch_ocr_models.sh <build/web>`
  writes `ocr/pp-ocrv5-mobile/{det,rec}.onnx + dict.txt`, SHA-256-checked
  against the pins `PdfOcrModels.ppOcrV5Mobile` uses
  (`test/fetch_ocr_models_test.dart` keeps them identical). Wired into
  `app/tool/build_web.sh`, preview-app-web, deploy-app-web and release-app.
  For `flutter run -d chrome`: `tool/fetch_ocr_models.sh app/web`
  (git-ignored).
- **Batched recognition** (both platforms): lines sorted by aspect ratio,
  6 per call, each batch padded to its own widest line (PaddleOCR's
  `TextRecognizer`). Same readings on both sheets; native page time
  37 s -> 19 s.
- Removed: `ocr_tiling.dart` (Florence tiling/parsing/merge) and its test,
  the Florence harness. `ocrWebPromptBody` reworded in all 22 locales.

Measured through the shipped bridge (`ocr_web_bridge.mjs`, 3x raster,
WASM, 4 threads):

| engine (web)                        | synthetic exact / CER | real exact / CER |
|-------------------------------------|-----------------------|------------------|
| Florence-2 (before)                 | 21.5% / 80.3%         | -                |
| PP-OCR on onnxruntime-web (shipped) | **95.0% / 1.4%**      | **82.5% / 13.2%**|

Identical to native, misread for misread - the same Dart pipeline compiled
both ways. The user's label (`(FSFCR)` above D27) now reads `(FSFCR)`, D27
`D27`. In-page compute on this 4-core container: a full A3 detection
(3584x2528) ~3.1 s with 4 threads (9.9 s single-threaded), recognition
~31 ms a line in batches of 6 (~85 ms single) - so ~15-20 s a page,
against ~37 min a page for Florence on the same CPU. The harness's own wall
time is several times that (tensors cross localhost HTTP).

Gotchas found on the way:
- Headless Chromium defines `navigator.gpu` with no adapter; the old
  `navigator.gpu ? 'webgpu' : 'wasm'` crashed the renderer.
- puppeteer's `setRequestInterception` pauses *every* request, and an
  intercepted multi-MB POST can stall forever (a 36 MB detection output
  posted back to the harness hung; zeros timed out, random data didn't - so it
  looked data-dependent). The harness now pauses only `https://*` via the
  DevTools `Fetch` domain. App code never POSTs tensors.

Memory: the web path holds the detection input twice (Dart `Float32List` +
onnxruntime-web's copy, ~108 MB each for A3 at 3x) - fine on desktop
browsers, heavy for phones. Tiled detection (bounded per-call input) is the
follow-up that would bound it on both platforms.
