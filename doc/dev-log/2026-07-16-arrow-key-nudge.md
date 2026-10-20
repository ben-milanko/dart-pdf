# Arrow-key nudge for selected annotations

Added keyboard nudging so a selected annotation can be moved a hair at a
time without dragging.

## What

- Plain arrow → 1 pt, Shift+arrow → 10 pt (the coarse step). Constants
  `_annotationNudgeStep` / `_annotationNudgeStepCoarse` in `pdf_viewer.dart`.
- Bound in the same `CallbackShortcuts` map as undo/redo/delete
  (`pdf_viewer.dart`, in the `editing != null` block). The arrow bindings
  are wrapped in `if (editing.hasAnnotationSelection)` so a bare arrow with
  nothing selected falls through to page scrolling instead of being
  swallowed. The map is re-evaluated on every controller notify because the
  host rebuilds the viewer (the existing editing-UI contract), and selection
  changes call `notifyListeners`.
- The whole map is already empty while an in-place text editor is open
  (`editing.isEditingText`), so arrows reach the field's own caret movement.

## Rotation

`PdfEditingController.nudgeSelected(screenDx, screenDy)` takes a view-space
delta (y **down**, as the reader sees the page) and translates it to page
space through the primary selected page's `/Rotate`, mirroring
`PdfPageGeometry.toPagePoint`:

| rotation | (dx, dy) |
| -------- | -------- |
| 0        | (sx, -sy) |
| 90       | (sy, sx)  |
| 180      | (-sx, sy) |
| 270      | (-sy, -sx) |

so "right" always slides the annotation the way the key points on screen,
whatever the page rotation. It then defers to the existing
`moveSelected`, so a nudge is one revision and the selection survives. A
multi-page selection uses the primary page's rotation for the whole move
(same simplification `moveSelected` already makes by applying one page
delta everywhere).

## Tests

`test/editing_arrow_nudge_test.dart` — direction/rotation mapping at the
controller level (rotation 0 via `buildMultiPagePdf`, rotation 90 via
`buildNestedPageTreePdf`'s inherited `/Rotate 90`), plus viewer widget
tests that an arrow and Shift+arrow move the selection and that a bare
arrow with nothing selected leaves annotations alone.
