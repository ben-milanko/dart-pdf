# Convert page-content text to a free-text annotation

The content tool's element strip gained **Convert to text box**
(`pdf-convert-element-text-to-free-text`, `tbConvertToFreeText`), backed by
`PdfEditingController.convertSelectedElementTextToFreeText()`.

- One `apply`: `deleteElements` drops every run of the
  `selectedElementWord` (the same span a text edit covers, so a word drawn
  one glyph per `Tj` converts whole) and `addFreeText` places a box with the
  joined text. One undo step restores the content and drops the annotation.
- Style is inferred, best-effort:
  - size = `Tf` x the vertical axis of `Tm x CTM` (`_apparentFontSize`), so a
    `1 Tf` + `24 0 0 24 Tm` run converts at 24pt;
  - colour = the non-stroking device colour in effect at the run's first
    operation (`_fillColorBefore`: forward scan honouring `q`/`Q`, `g`/`rg`/
    `k` and numeric `sc`/`scn`; black otherwise - no ICC/pattern/Separation);
  - face = `PdfStandardFont.tryFromName` on the /BaseFont behind the run's
    /Font resource, falling back to Helvetica with bold/italic recovered.
- The box (`_freeTextRectOver`) is laid out in *view* space through
  `PdfPageGeometry`, so on a rotated page it widens to the visual right: the
  run's bounds plus the appearance's 3pt inset, widened when the base-14 face
  measures wider than the original (no surprise wrap), vertically centred
  (`PdfTextVerticalAlign.center`) because element bounds' vertical extent is
  an estimate. Transparent, borderless.
- After converting, the tool switches to select and the new annotation is
  selected, so it can be dragged/restyled/retyped straight away.
- Mobile dock: it was ~9px from overflowing at 364px wide, so Reflow
  paragraph and Convert now share a `more_vert` menu
  (`pdf-mobile-element-text-more`); the item keys are unchanged.

Not done: rotated/skewed text converts axis-aligned; embedded document fonts
are not reused (base-14 substitute only).

Tests: `test/editing_convert_text_to_free_text_test.dart`.
