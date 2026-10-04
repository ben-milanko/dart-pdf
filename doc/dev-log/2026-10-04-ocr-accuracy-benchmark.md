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
- **Florence harness:** three steps, so it measures what ships:
  `app/test/ocr_web_accuracy_test.dart` exports the page's tiles with the
  app's own `ocrTiles` (`PDF_OCR_FLORENCE_DIR`, `PDF_OCR_TILE`);
  `app/tool/perf/ocr_florence_run.mjs` (puppeteer-core, already this dir's
  dependency) runs them through the `__dartPdfOcrRecognize` bridge **lifted
  verbatim from web/index.html** in headless Chromium; `PDF_OCR_PHASE=score`
  feeds the raw output through `parseFlorenceSpans` + `mergeOcrSpans` +
  `userSpaceRect`. In a sandbox whose TLS proxy Chromium doesn't trust,
  `OCR_FETCH_VIA_NODE=1 NODE_USE_ENV_PROXY=1` has the page's https requests
  307'd to the script's localhost relay, which fetches from Node (verified
  against `NODE_EXTRA_CA_CERTS`) through a disk cache - model files are too
  big to hand back through a DevTools interception response.
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

## Florence-2 (web)

- Bridge bug: the device was `navigator.gpu ? 'webgpu' : 'wasm'`. Headless
  Chromium (and Linux Chrome without GPU access) defines `navigator.gpu` with
  no adapter behind it, so the bridge asked for WebGPU and crashed the
  renderer. Now picks by whether `requestAdapter()` returns one.
- Baseline on the synthetic sheet (2x, 1024 px tiles -> Florence's 768 input,
  q4 encoder/decoder): **21.5% exact, CER 80.3%**. CER above the miss rate is
  insertion: `X11` -> `X1.1`, `(HZVMP)` -> `(H)ZVMP) (HZVMP)`, `(PSK)` ->
  `(UXBRC)` (a neighbour's code). That is the user's `(FSCRC)`.
- Smaller tiles (512 px at 2x, 30 tiles, so the model upsamples rather than
  downsamples the text): measurement in progress; the tile default is
  unchanged until it is in.
