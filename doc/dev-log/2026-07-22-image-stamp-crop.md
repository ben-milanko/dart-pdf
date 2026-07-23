# Cropping placed images / raster snapshots

Adds an interactive crop tool for image stamps - the `/Stamp` annotations
that `PdfEditor.addImageStamp` produces for placed images and pasted raster
pictures. You select a placed image, hit **Crop**, drag a rectangle over it,
and confirm; the annotation's box shrinks to the cropped region and only that
part of the source picture shows.

## Model: the crop rides the appearance, not the image

An image stamp draws a unit image mapped onto its rect
(`_imageStampContent`, `annotation_editor.dart`). Cropping is baked into that
one method: given a normalized crop rect `[cl cb cr ct]` in `[0,1]` (origin
bottom-left, the source picture's own space), it clips the visual box and
scales the picture so the crop's sub-rect fills the box -

```
box  W n                       % clip to the visual rect
sx 0 0 sy tx ty cm             % sx = W/(cr-cl), tx = box.left - cl*sx, …
/Img0 Do
```

A full crop `[0 0 1 1]` degrades to the old identity map (`W 0 0 H L B cm`),
so uncropped stamps are byte-for-byte unchanged.

Design decisions:

- **The crop is a private marker, not inferred from the appearance.**
  `addImageStamp(..., crop:)` writes `/DartPdfImageCrop [cl cb cr ct]` on the
  annotation dict (same `DartPdf*` convention as `/DartPdfImageStamp`), and
  `PdfAnnotation.imageStampCrop` reads it back (null for absent/full). This
  matters because the appearance is regenerated on an **opacity restyle**
  (`_regenerateStyledAppearance` → `_imageStampContent`): that path now reads
  the crop off the dict, so changing transparency preserves the crop. A
  full-image crop drops the marker, so an uncropped picture carries none.
- **Resize needs no crop-awareness.** An image stamp resizes by the §12.5.5
  BBox→Rect stretch (`resizeBehavior == stretch`), which scales the whole
  baked appearance - clip and all - so a cropped stamp stretches
  proportionally with zero extra code. Only opacity restyle and creation
  regenerate the content, and both go through `_imageStampContent`.
- **`cropImageStamp(pageIndex, annotation, {crop, rect})`** is the editor
  entry: it re-references the same image XObject (`_stampImageRef`), rewrites
  the appearance at the new crop, and optionally sets a new `/Rect`. The crop
  composes against the *source* picture, so `crop: [0 0 1 1]` restores the
  whole image regardless of an earlier crop. A rotated image stamp (folded
  `/Matrix`) crops in place through the `_restyleRegenerate` local-frame path
  (re-rotates after regenerating); the `rect` shrink is upright-only, since an
  axis-aligned page rect can't describe a rotated frame.

Tests: `image_stamp_test.dart` - crop clips + scales, full crop is identity,
crop in place vs. box-shrink, opacity restyle preserves the crop, two crops
compose, reset clears the marker, and a no-op on non-image stamps.

## Controller: compose + shrink

`PdfEditingController.cropSelectedImage(visibleRect)` takes a page-space
rectangle inside the current box, converts it to fractions of the box,
composes those into the source-normalized crop (so re-cropping keeps
narrowing toward the source), and shrinks `/Rect` to `visibleRect` so the
retained pixels keep their on-page scale instead of stretching to refill the
old box. `resetSelectedImageCrop()` grows the box back to the full picture.
`canCropSelected` gates on a single, upright image stamp (rotated ones are
excluded - see above).

Interactive crop is a transient mode on the controller
(`isCroppingImage`/`imageCropDraft`, `beginImageCrop`/`updateImageCropDraft`/
`commitImageCrop`/`cancelImageCrop`), auto-cancelled by the tool setter so a
stray tool switch can't strand it.

## UI: a self-contained overlay, driven through the working gesture path

`PdfImageCropOverlay` (`editing_image_crop.dart`) is the on-page crop
rectangle: a dim scrim over the image outside the crop, a rule-of-thirds
grid, eight `HandleLayout` handles, and floating confirm/cancel chips. It is
rendered as the topmost child of the editing overlay's Stack while
`isCroppingImage`, and the editing overlay drops its own pan/tap recognizers
(`cropping ? null : _panStart`, etc.) so the crop overlay owns every pointer
on the page.

Two gotchas cost time and are worth recording:

- **`dragStartBehavior: DragStartBehavior.down`** on the crop overlay's
  `GestureDetector` is mandatory. The default (`start`) reports the pan-start
  position *after* the recognizer wins the arena (post-slop), so a handle grab
  hit-tests against a point ~18px off the handle and silently becomes a
  body-move. The editing overlay already uses `down` for the same reason.
- **The confirm/cancel chips fire from `Listener.onPointerUp`, not just
  `InkWell.onTap`.** The chips sit over the viewer's `SelectableRegion` and
  the editing overlay's gesture stack, which win a plain tap's arena, so
  `onTap` never fired in the viewer (it works fine in isolation). A raw
  pointer-up listener fires regardless of the arena; `commit`/`cancel` are
  idempotent, so the InkWell's `onTap` staying on for ripple feedback is
  harmless. Tooltips were also dropped for `Semantics` labels - a `Tooltip`
  schedules a timer that leaks past widget-tree disposal in tests.

Toolbar: a `crop` icon in the selection strip (`canCropSelected`) arms the
mode; while cropping the strip swaps to a crop bar (reset / cancel / apply).
Escape cancels the crop before it clears the selection (`_onEscape`,
`pdf_viewer.dart`). New l10n keys `tbCropImage`/`tbCroppingImage`/
`tbCropApply`/`tbCropCancel`/`tbCropReset`.

Tests: `editing_image_crop_test.dart` - the overlay widget (handle drag,
interior move+clamp, chip callbacks), the viewer wiring (arm shows the
overlay, drag-a-handle-then-confirm crops the annotation, cancel discards),
and the toolbar (Crop button arms + swaps in the crop strip). Controller
composition/lifecycle in `editing_image_test.dart`.

## Not covered

Vector snapshots (`PdfVectorSnapshot`, a form XObject replaying page
operators) aren't croppable through this tool - only raster image stamps.
Cropping a rotated image stamp works in place but can't shrink its box.
