# OCR text layer on /Rotate pages

- Bug: `PdfOcrEditing.injectTextLayer` (`pdf_document/lib/src/ocr_editor.dart`)
  always wrote a horizontal user-space run - font size = box height, `Tz` to
  box width, `Td` at (left, bottom + size/4). The span bounds come from
  `PdfOcrPageImage.userSpaceRect`, which undoes /Rotate correctly, so on a
  /Rotate 90/270 page a word that reads left to right on screen has its
  length along user-space **y**. The run came out perpendicular to the word:
  font size = the word's on-screen width, `Tz` squashing it to the on-screen
  height. Seen on an A3 drawing (/Rotate 90): `/OcrF1 25.088 Tf 8.441 Tz`
  for a label ~23pt wide and ~7pt tall, which `pdftotext -bbox` split into
  stacked fragments. On /Rotate 180 the run read upside down.
- Fix: per page rotation, the run gets a `Tm` that inverts the clockwise
  display turn, so its baseline follows the visual reading direction and
  glyphs stand upright on screen:
  - 90: `[0 1 -1 0  right-d  bottom]`, reading +y
  - 180: `[-1 0 0 -1  right  top-d]`, reading -x
  - 270: `[0 -1 1 0  left+d  top]`, reading -y

  with d = size/4 (the em box's descent, so the em box spans the box
  exactly). Font size is the box's extent across the reading direction
  (width on a quarter turn) and `Tz` fits the extent along it. /Rotate 0
  still writes the old `Td` form byte for byte. `PdfOcrSpan` bounds stay
  axis-aligned in user space; only the writer changed.
- `ocrSpansNotIn` needed nothing: it compares axis-aligned user-space boxes,
  and the rotated run's extracted bounds now match the span, so a re-run
  dedupes.
- Tests: `pdf_graphics/test/ocr_layer_test.dart` "injectTextLayer on a
  /Rotate page" - for 90/180/270, `PdfTextExtractor.extract` gives a single
  run whose bounds and search highlight match the span, whose baseline maps
  to screen +x and whose glyph-up maps to screen +y; plus a re-run dedupe
  per rotation. The direction tests fail against the old writer.
