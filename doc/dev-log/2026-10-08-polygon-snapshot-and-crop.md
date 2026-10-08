# Polygon snapshots and cropping a pasted snapshot

Two Snapshot-tool additions.

## Traced (polygon) snapshots

The Snapshot tool is now a hybrid like the cloud and content-delete tools
(`_hybridPolyTool` in `editing_overlay.dart`): **drag** still rubber-bands a
box, **tap** drops a vertex and **double-tap** finishes the polygon. Once a
vertex is down, a drag no longer restarts the shape as a box
(`_regionPolyInProgress`). The in-progress path paints with the same marquee
style as the box (`_paintPathPreview`'s snapshot branch).

`_finishPolyPath` hands the polygon to `_commitSnapshot` (shared with the
box path in `_commitRect`). The capture region is the polygon's bounds, and
both halves are cut to the polygon:

- **Vector**: `captureVectorSnapshot(..., clip:)` (pdf_document
  `vector_snapshot.dart`) wraps the captured content in a
  `q <polygon> W n ... Q` clip in page user space. The clip is baked into
  `_content`, so paste, `toPdfBytes`, and re-import all carry it with no
  further changes.
- **Raster**: `PdfEditingController.captureSnapshot(..., clip:)` replays the
  page picture under `clipPath` before `rasterizeRegion`, so the PNG is
  transparent outside the polygon.

`PdfSnapshot.pagePolygon` tells the host which shape was traced. It is null
for a box.

## Cropping a pasted vector snapshot

`canCropSelected` now accepts pasted vector snapshots
(`isVectorSnapshotStamp`) as well as image stamps, under the same "upright
only" rule. The crop UI (`PdfImageCropOverlay`, toolbar crop strip) is
unchanged. `cropSelectedImage` / `resetSelectedImageCrop` dispatch through
`_applyCrop` to `cropImageStamp` or the new
`PdfVectorSnapshotEditing.cropVectorSnapshot`.

`cropVectorSnapshot` mirrors `cropImageStamp`. The crop is normalized
against the captured `/Cap` form's BBox and recorded as
`/DartPdfSnapshotCrop` (read back by `vectorSnapshotCrop`). The appearance
is regenerated as `[/GS0 gs] q <rect> re W n <scale+shift> cm /Cap Do Q`,
so the graphics stay vector. Opacity (GS0) and a recolour (a re-pointed
`/Cap`) carry over because the appearance resources are kept. A crop of
`[0 0 1 1]` drops the marker and the clip. The toolbar's reset button keys
off `PdfEditingController.selectedHasCrop` instead of `imageStampCrop`.

Tests: `pdf_document/test/vector_snapshot_test.dart` (polygon clip, crop)
and `dart_pdf_editor/test/editing_snapshot_test.dart` (tap-traced capture
including PNG alpha, and crop/compose/reset through the controller).
