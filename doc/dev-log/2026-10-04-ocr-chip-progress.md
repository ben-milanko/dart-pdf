# OCR chip: honest progress, live motion, web download %

The app-bar OCR chip (`OcrStatusChip`, now in `app/lib/ocr_status_chip.dart`
with widget tests in `app/test/ocr_status_chip_test.dart`) had
three problems:

- **"OCR 1/1" while working.** `OcrJobStatus.fraction` was `page / pageCount`
  with `page` the 1-based page *in progress*, so a one-page document read as
  finished (full ring, "1/1") the moment it started. The fraction now counts
  only finished pages plus an optional `pageFraction` for the current one, and
  the label is "OCR page 3 of 12" (multi-page) or "Reading text…" (one page).
- **Nothing moving.** A determinate ring sits still between page updates.
  The ring is now always indeterminate (always turning) and completion moved
  to a 3px bar along the chip's bottom edge - determinate when known, eased
  between updates, sweeping otherwise.
- **No download % on web.** The Transformers.js bridge in `app/web/index.html`
  never passed a `progress_callback`, so web sat on "Downloading OCR model…".
  The bridge now sums per-file `loaded`/`total` across the processor,
  tokenizer and model loads and calls a Dart listener registered through
  `window.__dartPdfOcrOnProgress(stage, loaded, total)`. Totals grow as each
  file's request opens, so `ocr_web.dart` holds the shown fraction monotonic.
  The hook is optional (an older cached `index.html` simply reports nothing).

New `OcrPhase.preparing` ("Loading OCR model…") covers the gap after the
bytes are in: the web warm-up generate and native engine construction.
Web also reports within-page progress per recognized tile
(`_BrowserOcrEngine.onPageProgress`); native has no sub-page signal.

Note: the chip now always contains an indeterminate spinner, so a widget test
must `pump(duration)` rather than `pumpAndSettle()` while it is up.

Gotcha: `TweenAnimationBuilder` asserts a non-null `tween.end`, so the bar only
eases when the fraction is known and swaps to a plain indeterminate
`LinearProgressIndicator` otherwise (a nullable tween crashes debug builds in
the preparing/finishing phases).

## Follow-up: the minute at "Downloading model 100%"

Reading the Transformers.js 4.2.0 source (`transformers.web.js`) explains it:

- The first bridge version summed *every* file, so the processor's tiny JSON
  files reached 100% before the ONNX weights had even started, and the
  monotonic hold then kept the chip at 100% through the real download. The
  bridge now counts only `onnx/...` files and waits until every started
  weight file has reported a size (`initiate` fires for all session files up
  front, but a size only arrives with the first chunk).
- After the last weight byte, `from_pretrained` still writes each file into
  the browser Cache API (`storeCachedResource`, before `done`), fetches the
  ONNX Runtime WASM binary (`ensureWasmLoaded`), and builds the four
  inference sessions **serially** (`webInitChain`). None of that reports
  progress, and the old code only switched to "Loading OCR model…" after
  `from_pretrained` returned. The bridge now flips to `preparing` the moment
  the weight bytes are complete, so that stretch shows the sweeping bar and
  the right label. There is no honest percentage for session creation;
  ONNX Runtime exposes no hook.
