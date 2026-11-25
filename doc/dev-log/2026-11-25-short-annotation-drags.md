# Short annotation drags no longer snap back

Report: dragging an annotation a small distance snapped it back to where it
started, and the reporter asked for drag precision to follow zoom. There
were two causes, both in the select-mode move path
(`editing_overlay.dart` → `selection_manipulation.dart`).

## 1. The click threshold was in view pixels, not screen pixels

`PdfMoveDrag.isClick` / `PdfElementMoveDrag.isClick` read
`delta.distance < 2` and `PdfMarqueeDrag.isClick` read `< 4`. Those are
**overlay (view) pixels**. The whole viewer zoom is a transform over a
fit-width layout (`EditingPageOverlay.zoom` = `_transformScale`), so one view
pixel is `zoom` screen pixels. At 5x a 9-screen-pixel drag read as a click,
`commit` returned null, and the move preview went away: the annotation
"snapped back". Zooming in, which should make a move more precise, made the
dead zone bigger instead.

Fix: the drags take a `clickSlop` (view px). The overlay passes
`_dragClickSlop` = `pdfDragClickSlop` (2 screen px) x `_chromeScale`, the
same screen-constant conversion the chrome and `_alignmentTolerance` already
use. The marquee keeps twice that, as before. The constructors' defaults keep
the old values, so direct callers (tests) are unchanged.

Everything else in the move already scales with zoom: the view-to-page
mapping is exact (`toPagePoint` on both endpoints), smart-guide tolerance is
in screen px, and grid snapping is in page points on purpose. With the
threshold fixed, a move is as fine as the zoom makes it.

## 2. Smart guides pulled a short drag back to its starting alignment

A selection already on a guide (a neighbour's edge, the page centre or an
edge) sits inside that guide's 6px magnetic range for its first few pixels
of travel. `_snapMovePosition` snapped the box straight back onto it, the
net delta came out ~0, and the drop committed as a click. That happened at
any zoom.

Fix: if the alignment snap would cancel a drag the pointer really made (raw
travel >= click slop, snapped travel < click slop), drop the alignment for
that sample and keep the grid fallback. Holding one axis on a guide while
the other axis travels still works, because the net move is not cancelled
there. The guide catches again once the drag leaves the magnetic range.

## Not changed

- On touch, a drag still has to clear the platform pan slop before the
  `PanGestureRecognizer` starts. Below that it is a tap, so nothing moves.
  (`DragStartBehavior.down` anchors the drag at the press point, so the box
  does not jump once the drag starts.)
- Other view-pixel thresholds that grow with zoom are left as they are:
  the region tools' `_isClick` (4 view px) in `editing_tool_behavior.dart`,
  `PdfResizeDrag.minSize` (12 view px) and `_elementGrabSlop`.

Tests: `editing_guides_grid_test.dart` (one test for the short drag off an
alignment, one for a 4-screen-px move at 5x) and
`selection_manipulation_test.dart` (click slop). Both widget tests fail on
the old code.
