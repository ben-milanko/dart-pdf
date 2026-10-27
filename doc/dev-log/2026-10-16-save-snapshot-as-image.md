# Right-click a pasted vector snapshot → Save as image…

A vector snapshot pasted back onto a page (the Snapshot tool's capture, a
/Stamp whose appearance carries the detached page content) can now be saved
out as a PNG from the annotation context menu, next to Recolor….

- **Controller**: `PdfEditingController.canExportSelectedSnapshotImage`
  (exactly one selected annotation, and `isVectorSnapshotStamp`) and
  `exportSelectedSnapshotImage({dpi = 300})`. It renders the annotation's
  own appearance alone (`PdfPageRenderer.renderAnnotationPicture`, so crop,
  recolour and rotation all come along) on a transparent background and
  rasterizes the annotation's /Rect in page raster space via
  `rasterizeRegion`. The rect is *not* intersected with the page: a snapshot
  hanging past the edge (geometry isn't confined to the crop box) saves
  whole. Longest side capped at 8192 px, like the content-image export. A
  revision landing mid-render returns null.
- **Menu**: `showPdfAnnotationMenu(onSaveImage:)` adds the
  `pdf-annot-menu-save-snapshot-image` row in the recolour group, only when
  a saver is supplied. `PdfViewer.onSaveAnnotationImage` feeds it on every
  path that opens the stock menu (right-click and the selection chip /
  touch long-press "More").
- **Wiring**: reuses the existing `PdfSelectedContentImageHandler` and
  `PdfSelectedContentImage`; `PdfEditorView` passes its
  `onExportSelectedContentImage` to the viewer, so the app's existing
  save-dialog / download / share path saves it with no app change.
- New l10n key `menuSaveAsImage`, translated in every locale.

Tests: `editing_snapshot_test.dart` (PNG + IHDR size at 144 dpi, single-
selection gate) and `editing_menu_test.dart` (shown only for a snapshot with
a saver; picking it hands a PNG to the host without a new revision).
