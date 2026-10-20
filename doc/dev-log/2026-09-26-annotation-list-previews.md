# Rendered annotation previews in the list and library

The annotation sidebar (`PdfAnnotationSidebar`) and the annotation library
(`PdfAnnotationLibraryPanel`, plus the legacy dialog) used to lead each row
with a subtype icon. They now show the annotation's own normal appearance.

- `PdfAnnotationAppearancePreview` (`editing/annotation_preview.dart`,
  exported) renders through `PdfPageRenderer.renderAnnotationPicture` - the
  same page-space picture the move ghost uses - and fits the annotation's
  view rect (`PdfPageGeometry.toViewRect`) into the card, upscaling at most
  `maxScale` (4x) so a tiny mark doesn't balloon.
- The card is **always white**, in every theme: appearances are authored
  against paper, and a Multiply highlight or black ink vanishes on a dark
  panel. The fallback icon is a fixed grey for the same reason.
- The icon stays for annotations with no /AP (links, bare widgets) and while
  the picture renders. A new `page`/`annotation` object re-renders, but the
  old picture stays up until the new one lands, so an edit never flashes the
  rows. `PdfPage.annotations` and `controller.pageAt` are cached per
  revision, so rebuilds within a revision don't re-render.
- The library's snapshot is detached; `PdfSavedAnnotationPreview` (now
  stateful, new optional `page`/`pageIndex`) materializes it once via
  `annotationForPreview` against page 0 of the open document and holds it
  until the saved item changes. Without a `page` it shows the old icon tile.
- Each card sits in a `RepaintBoundary`; only the lazily built visible rows
  render.

Tests: `test/annotation_preview_test.dart` (pixel checks on the sidebar and
library cards, white paper under a dark theme, icon fallback without /AP).
