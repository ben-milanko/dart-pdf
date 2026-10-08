# Thumbnails snap back after a page reorder (#1025)

**Symptom.** Dragging page 3 to position 2 in the thumbnail strip/grid moved
the page in the viewer, but the thumbnails went back to the old order on
release.

**Cause.** A pure reorder reports `PdfEditImpact.pageOrderOnly` with empty
visual/content page sets: no page renders differently, so no render stamp is
bumped. The thumbnail cache key was `pageIndex|pageRenderStamp|...`, so slot 1
(now page 3, stamp 0) hit the cached raster of the page that used to sit there
(old page 2, also stamp 0). Stamps are already keyed by page *identity*
(`_pageStampKey`, the indirect ref) - only the cache key used the index.

The disk thumbnail tier had the same hole: it is keyed by document + page
index and was gated on `pageRenderStamp(i) == 0`, which a reorder leaves true.

**Fix.**
- `PdfEditingController.pageRenderIdentity(i)` exposes the stamp key;
  `thumbnailKey` now leads with it instead of the index. A moved page keeps
  its raster (no re-render), and undo restores the original keys.
- `PdfEditingController.pageMatchesOpenedFile(i)` gates the disk tier: stamp
  0 **and** no revision (commit/undo/redo) has changed page structure
  (`_pageStructureEpoch`, bumped from the shared `_bumpStampsFor(impact)`).
  Conservative: once pages move, the disk tier stays off for the session.

Tests: `editing_thumbnail_cache_test.dart` group `page reorder (#1025)`.
