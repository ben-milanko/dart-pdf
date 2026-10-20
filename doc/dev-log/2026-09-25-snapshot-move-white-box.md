# Moving a snapshot left a white box behind

Moving a vector snapshot (a `/Stamp` whose appearance replays a whole captured
page) on a dense CAD drawing left a paper-coloured rectangle over the old spot.
The rectangle covered the real page content until the moved stamp's appearance
finished re-rendering, and for a snapshot of a busy page that took seconds.

## Cause

`EditingPageOverlay._commitWithGhost` covered a moved annotation's old spot so
the stale mark would not show next to the committed afterimage. It did that in
one of two ways:

- a *clean page* render (the whole page without the annotation), clipped to
  the old rect. This was skipped for Stamps because the full-page render
  stalled drags on CAD pages;
- otherwise, a **paper-colour wash** of the old rect (`sourceWash`).

The wash was based on a wrong assumption. Under the editing overlay the page
raster **never includes annotations**
(`_pageImagesShowAnnotationsFor` is false whenever `editing != null`), because
annotations are painted by `_AnnotationAppearanceLayer`. So the wash covered
page content, not a stale annotation. The actual stale mark was the layer's
old picture, which the layer kept (`keepCurrent`) until the re-render
published. The wash stayed up until then because `rasterCurrent` waits on
`_annotationLayerCurrent`.

## Fix

- `_AnnotationAppearanceLayer` now tracks one appearance key per painted
  picture (`_pictureKeys`, parallel to `_pictures`). On a same-geometry
  revision within one COS graph, `_dropStalePictures` immediately stops
  painting every picture whose `(appearance stream, /Rect)` key is no longer
  live on the new page. This covers moved, restyled and deleted marks.
  Untouched marks keep painting because an incremental revision preserves
  stream identity. This runs in `didUpdateWidget`, in the same frame the
  overlay switches to its afterimage, so nothing flashes.
- The overlay no longer covers the old spot at all. Removed:
  `sourceWash`/`sourceClean`/`source` from `_AfterGhost`, `washSource`,
  `_ensureSourceClean`, `_renderAfterGhostSourceClean` and the FreeText rest
  ghost wash. As a side benefit, selecting a non-stamp annotation no longer
  starts a full-page "clean" render.

Other "clean page" paths are unchanged: the resize lift, the text-edit
afterimage, and content-element moves still need them. During a drag the
layer is still painting the original, and page *content* lives in the raster.

## Tests

- `annotation_appearance_cache_test.dart`: "a move drops the stale picture
  before its re-render lands". The re-render is held pending, and only the
  untouched picture is painted in the frame after the move. It fails without
  the layer change.
- `editing_chrome_test.dart` / `editing_drag_preview_test.dart`: removed the
  expectations that pinned the wash.
