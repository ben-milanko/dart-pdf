# 2026-11-05 - selection manipulation: one geometry for preview and commit (#1203)

The selection's drags (move, resize, rotate, node reshape, content-element
move, marquee) were computed on both sides of the overlay/controller seam.
The overlay kept about 20 nullable fields in exclusive groups and predicted
the geometry; `_finishPan` snapshotted them and ran an ordered if/else. The
controller then decided the result, and the overlay re-read it to paint
the afterimage. Callout handles were an index-parity protocol: an even
index was a terminus, an odd one a base, and `_commitVertexDrag` decoded
it.

## Shape

`editing/selection_manipulation.dart` (exported, pure):

- **Frame**: `pdfSelectionFrame(bounds, quad:, rotation:, group:)` is the
  chrome box and resting angle, moved out of the overlay's
  `_selectionChrome`. Resize and rotate drags start from it, and tests
  judge a commit by the frame it leaves.
- **Handles**: `pdfReshapeHandlesOf(annotation)` returns sealed
  `PdfReshapeHandle`s: `PdfLineVertexHandle(index)`,
  `PdfCalloutTerminusHandle(leader)`, `PdfCalloutBaseHandle(leader)`,
  `PdfCloudRegionHandle(vertex)`. `pdfCalloutLeaderPairs` pairs a terminus
  with its base by leader, not by position. The painter takes the handle
  kinds (`vertexHandleKinds`) in place of the `calloutLeaderHandles` bool
  and the `i.isEven` check.
- **Drags**: sealed `PdfSelectionDrag`: `PdfMarqueeDrag`, `PdfMoveDrag`,
  `PdfElementMoveDrag`, `PdfResizeDrag`, `PdfRotateDrag`,
  `PdfReshapeDrag`. Each is mutable and fed snapped view-space pointers.
  Its fields are the preview, and its `commit(geometry)` returns a sealed
  `PdfSelectionEdit` (`PdfMoveEdit`, `PdfRehomeEdit`, `PdfElementMoveEdit`,
  `PdfElementRehomeEdit`, `PdfResizeEdit`, `PdfRotateEdit`,
  `PdfReshapeEdit`). `PdfEditingController.applySelectionEdit` is the one
  dispatch from an edit to the existing commands.
- **Page-space rules**: `pdfTetherShift` / `pdfTetheredDelta` (the
  controller's `_tetherShift` now delegates to them), and
  `pdfViewDeltaToPage` (`nudgeSelected` used to carry its own copy of the
  /Rotate mapping).

The overlay holds a single `PdfSelectionDrag? _drag`. The old field names
are now read-only getters over it, for the painting code, and `_finishPan`
hands the drag to `_commitSelectionDrag`.

## Drift fixes

- **Resizing a rotated annotation on a /Rotate 90/270 page.** The frame
  measures the local box along the annotation's own edges in view space.
  The commit's `toPageRect` swapped width and height on a sideways page,
  so the committed box came out transposed against the preview (up to
  55 px off in the new tests). Only groups had a patch for this, in the
  overlay. `PdfResizeDrag.commit` now keeps the local width and height for
  every rotated selection.
- **Content-element drag preview.** The commit tethers a same-page drop so
  a strip stays on the paper, but the live preview (and the cross-page
  floating preview) drew the raw pointer delta. `previewDelta` now
  tethers the same way. It follows the pointer untethered only while the
  pointer is over another page the drop would re-home onto
  (`PdfElementMoveDrag.drop`, resolved on every update).
- **Cancelled node drag.** A bailed gesture (`_bailActiveGesture`) now also
  drops an in-flight node reshape. It used to leave the vertex drag state
  behind.

## Tests

`test/selection_manipulation_test.dart` has plain tests of the form "grab
handle k at p, move to q, preview == committed". They cover resize
(page /Rotate × annotation 0°/30° × three handles), move, rotate, and the
callout terminus and line endpoint reshapes on every /Rotate, the element
tether, and the view-to-page delta.
