# Deselecting an edited annotation no longer hides it

Report (Windows, a civil as-built markup PDF): a callout that had been
moved and reshaped several times disappeared when it was deselected. It
was intermittent, and switching away from the window and back brought it
back.

## Why

While editing, the page raster never includes annotations. They come from
`_AnnotationAppearanceLayer` (pdf_viewer.dart). A revision drops a moved or
restyled mark's stale picture straight away (`_dropStalePictures`) and
re-renders it in a paced, quiet-class pass (`paceUiWork`). Until that pass
lands, only the editing overlay paints the mark: either the drag's
afterimage (`_afterGhost`) or the selection's resting ghost (`restGhost`,
which needs a selection).

Deselecting removed both stand-ins:

- The resting ghost is tied to the selection. `_ensureGhost` disposed it as
  soon as the slot went away.
- In the default mode (a mouse click selects, no tool armed), the viewer
  unmounts the whole overlay when nothing is selected. That threw away a
  drag afterimage too. Only committed ink kept it mounted.

So the mark stayed invisible until the layer pass landed. When the pass was
held back, that could be a long time. Quiet work waits for
`PdfPageRenderScheduler.activeGesture` to go false. In this report a window
focus change appears to have released it, but which state stayed set was
not confirmed. A trackpad pan-zoom with no `PointerPanZoomEnd` would
explain it, because `_trackpadGestureActive` only clears on that event.

## Fix

- `_holdRestingGhost` (editing_overlay.dart): when the selection moves off
  an annotation whose page is not current yet, the resting ghost becomes an
  ordinary afterimage. It keeps the same picture and view rect, under the
  current `_afterRevisionId`. It retires like every other afterimage: once
  the page is current, or when the document moves past that revision. It
  only applies while the ghost belongs to the current document, so a delete
  (a new revision) never leaves a ghost behind.
- `_editingOverlayHeld` (`_PdfViewerPageState`): once the overlay is
  mounted, it stays mounted until the page is current (`rasterCurrent`),
  even after its own reason to be there (tool, selection, ...) has gone.
  The overlay is passive then (`acceptsEditingGestures` is false without a
  tool or selection), so this changes no gestures.

## Tests

`editing_polish_test.dart` "a moved annotation stays painted when
deselected before the page catches up": it holds the layer pass behind
`debugAnnotationAppearancePicturesRendererOverride`, moves a selected
rectangle, deselects, and checks the pixels at the new position. It then
releases the gate and checks that the layer draws the rectangle and that
nothing is left at the old spot. There are two variants: the select tool
(needs `_holdRestingGhost`) and a no-tool click selection (also needs the
viewer hold). Each variant fails with its half of the fix removed.
