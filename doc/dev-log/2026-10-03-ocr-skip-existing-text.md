# OCR no longer duplicates text the page already has

The OCR engines read the page **raster**, so they recognize born-digital text
exactly as readily as scanned text. `PdfEditor.applyOcr` used to inject every
span it got back, so running OCR over a mixed page (a scan with a typed header,
a form with printed labels) - or over a page that was already OCR'd - wrote a
second, invisible copy of words the page could already select. Extraction,
search hit counts, and copy/paste all came out doubled.

## Fix

- `ocrSpansNotIn(existing, spans)` (pdf_graphics `ocr_coverage.dart`, pure
  Dart): drops a span when >= 50% (`defaultOcrDuplicateCoverage`) of its box
  lies under the bounds of the page's existing non-blank text runs. Coverage is
  the exact **union** area (coordinate compression over the few runs touching
  the span), so text drawn twice - fake bold, a stale layer under a visible
  one - doesn't count double and push a half-covered word over the line.
- `applyOcr(skipExistingText: true)` (dart_pdf_editor `ocr.dart`) extracts the
  page with `PdfTextExtractor.extract` after recognition and filters through
  it before `injectTextLayer`. Invisible (Tr 3) text is extracted too, so a
  re-run only fills in what is still missing. `skipExistingText: false` is the
  opt-out.
- `injectTextLayer` itself is unchanged: it writes whatever spans it is given.

The app's native and web OCR jobs both go through `applyOcr`, so they pick
this up with no change. Cost is one extraction walk per page, negligible next
to model inference.

Tests: `pdf_graphics/test/ocr_layer_test.dart` (`ocrSpansNotIn` group) and
`dart_pdf_editor/test/ocr_test.dart` (end to end, including OCR run twice).
The existing applyOcr test's canned word sat on top of the fixture's
"Hello, world!", so it moved to an empty part of the page.
