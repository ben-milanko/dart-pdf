# 2026-10-03 - Vector snapshots include un-flattened annotations

The Snapshot tool's raster capture already rendered annotations
(`captureSnapshot(annotations:)`), but the vector copy behind "paste as
vector" / PDF clipboard export (`captureVectorSnapshot`) copied only the
page content stream + resources, so live markup over the region vanished
from what got pasted.

- `PdfVectorSnapshotEditing.captureVectorSnapshot(..., annotations: true)`
  now appends each qualifying annotation's normal appearance after the page
  content (bracketed `q`...`Q`, as flattening does), fitted onto its /Rect
  per §12.5.5 (`fitFormToRect` + `_formMatrix`, same as
  `_flattenAnnotations`). The forms are deep-copied through the same
  `_SnapshotCopier` into the snapshot's /XObject dict as `SnapAnnotN`.
- Which annotations: the renderer's on-screen rule (`drawAnnotations`) -
  skip Hidden, NoView, Popup, replies and review-state annotations - plus
  only those with an /AP (the renderer's no-AP fallback drawing has no
  content-stream form) and whose /Rect overlaps the region (the form BBox
  would clip the rest anyway; skipping keeps the payload small).
- The editor passes the viewer's `showAnnotations` through
  `copyVectorSnapshot(annotations:)`, matching the raster capture.
- Recolouring a pasted snapshot recurses into nested forms, so captured
  annotations recolour with the rest.
