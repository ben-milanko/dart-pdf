# OCR chip: honest progress, live motion, web download %

The app-bar OCR chip (`_OcrStatusChip` in `app/lib/editor_screen.dart`) had
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
