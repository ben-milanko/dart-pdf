# Changelog

## Unreleased

- Page management: `PdfEditingController.addBlankPage` (sized to its
  neighbour by default), `insertPagesFrom`/`insertPagesFromBytes` (merge
  pages from another PDF), and `exportPages`/`exportPageRange` (split off a
  standalone PDF). The thumbnail strip gained an "Add page" footer button
  (shown when `allowPageEditing`), so `PdfEditorView` gets it out of the box.
  `PdfEditorView` also exposes the other two in its header via
  `onPickPdfToInsert` (host returns a PDF to merge after the current page)
  and `onExportPages` (host saves the exported range); the range is chosen
  with the new exported `showPdfPageRangeDialog`.
- Pluggable OCR: `PdfOcrEngine` (a host-supplied recognizer — ML Kit,
  Tesseract WASM, a cloud API; none ships in-tree) plus
  `PdfEditor.applyOcr(pageIndex, engine)`, which rasterizes the page, runs
  the engine, and injects an invisible selectable/searchable text layer.
  `PdfOcrPageImage.userSpaceRect` maps the engine's pixel boxes back to PDF
  user space (crop box and /Rotate aware).
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
- Measurement tools: distance/perimeter/area annotations with scale
  calibration (`PdfMeasurementScale`, `showPdfScaleDialog`, persisted in
  preferences) and a live readout chip that rides the cursor for mouse
  and floats above the finger for touch/stylus.
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
