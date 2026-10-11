# Automatic OCR of scanned documents

A scanned PDF now becomes searchable and selectable on its own. The first time
an editable tab is shown, the app checks whether the document looks scanned
and, if it does, runs the on-device OCR in the background (same engine,
progress chip and cancel as the menu item). Settings → Text recognition →
"Automatically OCR scans" turns it off. It is on by default and stored by
`AutoOcrSetting` (`app/lib/ocr_auto.dart`, key `dart_pdf_editor_app.ocr.auto`,
one app-wide `instance` so every window follows a change).

## Detection (pdf_graphics `ocr_scan_detection.dart`)

`pdfPageLooksScanned` holds when all of these are true:

- images cover >= 50% of the crop box;
- the page has <= 64 non-whitespace characters of text, so a Bates number or a
  digitally stamped header still counts as a scan;
- the content has no `3 Tr`, meaning nobody (us or another tool) already laid
  an invisible OCR layer. Without this check a document would be re-OCR'd on
  every open.

A page whose resources declare no image XObject and whose content has no `BI`
is rejected before any interpretation, so born-digital pages cost one
dictionary walk. Otherwise one `PdfTextExtractor.reflowPage` pass supplies the
image bounds and the text. `pdfDocumentLooksScanned` samples the first 3 pages
(any match is enough). It runs on the UI isolate post-frame, so it stays
bounded. Images only reachable through a form XObject are not looked for,
which can miss a scan but never misfires.

## Result lands in the same tab

The menu item still opens the OCR'd copy in a new tab. The automatic run
doesn't, because popping a second tab for a document you just opened is
noise. Instead:

- `PdfEditor.recognizeOcr` (dart_pdf_editor `ocr.dart`) is the recognition
  half of `applyOcr` (rasterize, recognize, `ocrSpansNotIn` filter) and leaves
  the document untouched. `recognizeAllPages` (`app/lib/ocr_pages.dart`) loops
  it and returns spans by page. Automatic runs pass
  `includePage: pdfPageLooksScanned`, so born-digital pages of a mixed
  document never reach the model.
- The job reads a **copy** of the session bytes. After an undo, the next edit
  overwrites the session buffer past that revision, and `PdfDocument.open`
  reads lazily.
- `OcrSessionSnapshot` records each page's `pageRenderIdentity` +
  `pageContentRenderStamp` and the destructive stamp when the job starts.
  `applyOcrToSession` writes the spans with one `controller.apply`, which is a
  single undo step, only if all of those still match. Annotation edits made
  meanwhile leave content stamps alone and don't block it. A reorder, removal,
  content edit or redaction burn refuses it with a toast. The redaction case
  matters most: spans recognized before a burn would otherwise put the
  redacted words back as invisible text.
- Applying makes the tab dirty. The text layer is a real change the user
  needs to save to keep.

## Quiet by design

`OnDeviceOcr.start(automatic: true)` doesn't toast "already running", "not
available" or a missing bridge. When a tab is passed over because another job
is running, its check is retried after that job ends. If the user declines the
model download (native) or the browser prompt (web), there are no more
automatic prompts this session. On the web, the prompt is skipped once the
user has started browser OCR this session. Read-only mode is skipped, since it
makes no edits.

## Tests

- `pdf_graphics/test/ocr_scan_detection_test.dart`: the fixture is
  `buildScannedPdf` (pdf_test_fixtures).
- `app/test/ocr_auto_test.dart`: the setting, the session guard, and
  `EditorScreen` end to end with a fake `OnDeviceOcr`. `EditorScreen` gained
  the `ocr:` and `autoOcr:` seams for this.
- `app/test/ocr_pages_test.dart`: `recognizeAllPages`.

`pdf_graphics` moved from the app's dev_dependencies to its dependencies.
