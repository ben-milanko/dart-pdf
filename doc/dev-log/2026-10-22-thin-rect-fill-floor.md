# Thin rectangle fills get the stroke's one-pixel floor

Report: box and table edges vanish when zoomed out (a fault-response flow
chart exported from Word). Strokes were already floored at one device pixel
(#426/#912, `CanvasPdfDevice.strokeWidthFor`, the strip device's stroke
floor), but Word draws table borders as **filled** 0.5 pt rectangles
(`re f`), and fills had no floor. At 0.6 px/pt a 0.5 pt fill is 0.3 px of
coverage, split across two pixel rows wherever it lands; measured peak ink
before the fix was 0.30 at 60% and 0.10-0.16 at 33% zoom - invisible -
against 0.58-0.92 after.

## What changed

- `pdfPathAxisAlignedRects` (pdf_graphics `path.dart`): the rectangles a
  path is made of (`l, b, r, t` quadruples, page space), or null when any
  subpath is anything else. Bails on the first curve / fifth corner, so a
  dense CAD path costs a few segments.
- `CanvasPdfDevice.fillPath` → `_floorThinRectFill`: the fill stays exact
  and a Skia **hairline** (`strokeWidth = 0`) is drawn down the centre line
  of each thin rectangle. A hairline is one device pixel at any replay
  scale, and where the fill is wider than a pixel it lies inside it and
  changes nothing - so unlike widening at record time it is right for every
  ratio a recorded picture is replayed at (pixelRatio is 1 in the main
  recording paths). Threshold `pdfThinRectFillMaxThickness` = 2 recorded
  px; generous is free because the hairline only adds ink.
- `StripBinningDevice.fillPath` widens rectangles thinner than one device
  pixel to exactly one about their centre (it knows its real
  `pageToDevice`, like its stroke floor).

## Guards (both devices, `pdfThinRectFill` + `pdfRectIsRule`)

- **Every** rectangle in the path must be thin, else nothing is floored: a
  thick rectangle may be the outside of a nonzero/even-odd frame whose thin
  "rectangle" is a hole (test: 0.5 pt slot in a 20 pt `f*` box stays open).
  The strip rebuild also drops windings, which is only safe when all are thin.
- Only **rules** are floored: long side >= 3x the short side. Ghent
  GWG080/081 draw their checkmarks as a traced bitmap - one `re f` per
  0.66 x 0.67 pt cell - and the first cut (`w == h` as the speck test)
  floored every cell and emboldened them past the baseline gate.
- Parallel rules touching across their short sides in one path are an area
  (a traced bitmap's rows), not rules: the whole path stays exact. Rules
  meeting at right angles (table corners) are still rules. Over 64
  rectangles in one path: exact (the check is pairwise).
- Canvas only: opaque paint with srcOver/src/darken, where painting the same
  colour twice is idempotent. Translucent or blended thin fills stay exact.

Tests: `dart_pdf_editor/test/thin_rect_fill_floor_test.dart` (canvas at
several scales/grid offsets, vertical, multi-rect, zoom-in thickness, thick
fill untouched, even-odd hole, translucent, strip vs a true 1 px reference),
`pdf_graphics/test/path_rects_test.dart`. The strip test compares against a
reference rule because the headless strip shader reports coverage at 2x.
