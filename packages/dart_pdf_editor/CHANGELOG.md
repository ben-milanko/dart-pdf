# Changelog

## Unreleased

- Reopen documents where the user left them: `PdfViewport` (a
  resolution-independent scroll-position + zoom snapshot),
  `PdfViewerController.captureViewport`/`restoreViewport`,
  `PdfViewer.initialViewport`, and per-document persistence in
  `PdfEditingPreferences` (`viewportFor`/`setViewport`). The `PdfReader`
  and `PdfEditorView` shells remember and restore each document's
  position automatically — pass `documentId` for a stable key, or let it
  derive one from the bytes (`pdfDocumentKey`).

## 0.1.0

Initial release.

- Drop-in widgets: `PdfEditorView` (the full editor — header bar with
  search and panel toggles, all panels, the editing toolbar, save) and
  `PdfReader` (view-only with search, page navigation, and a read-only
  thumbnail strip), both theme-following and configurable via
  `PdfEditorFeatures`/`PdfReaderFeatures` (features and tools toggle
  off; styling via the Material theme and `PdfViewerTheme`).
- `PdfViewer`: zooming/panning viewer with text selection, search,
  link navigation, page-fit modes, deep-zoom detail rendering,
  low-res page previews under fast scrolling (`PdfPagePreviewCache` +
  background prerender), theming (`PdfViewerTheme`), dark mode, and
  custom page colors.
- `PdfEditingController` + tool overlays: highlight/ink (pressure +
  Catmull-Rom smoothing)/shapes/free text/notes/stamps/signatures,
  select/move/resize/rotate with live previews, slicing eraser,
  clipboard, undo/redo as incremental saves.
- Form filling UI: text, checkbox, radio, choice, button images, plus
  field administration, flattening, and a form-field highlight wash
  (`PdfViewer.highlightFormFields`, on by default).
- Panels: thumbnail sidebar with drag reorder, annotation sidebar with
  search and multi-select, properties panel, search results panel.
- Permissions: per-annotation read-only (`/F` flags +
  `canEditAnnotation` predicate) and a hide-all-annotations toggle.
- Sync surface: `annotationChanges` feed + `applyRemoteChange` for
  collaborative annotation stores.
- Touch/stylus support: pinch zoom, scroll fling momentum, palm
  rejection, Apple Pencil pressure, long-press text selection with
  handles, and a long-press context menu (copy/cut/paste and z-order
  without a right click).
