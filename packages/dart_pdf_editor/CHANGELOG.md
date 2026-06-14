# Changelog

## Unreleased

- Reflow reading view: images and diagrams now appear inline with the
  text, decoded and laid out at their on-page aspect ratio in reading
  order; bullet/numbered lists read as separate, indented items.
  `PdfReflowView.showImages` (default true) toggles back to text-only.
  The view now scrolls through a single non-lazy list so the scrollbar
  no longer jumps as pages of differing heights (text vs. images) come
  into view.

## 1.0.0

First stable release. Highlights since 0.1.0:

- Redaction tool: mark regions and burn the content irreversibly.
- Document comparison: pixel + text diff with a synchronized compare view.
- Text reflow: a paragraph-aware reading view of extracted text.
- More annotation tools: line/polyline/polygon with the full line-ending
  picker, an insert-image tool, customizable dash line styles, and
  polygon fills.
- Text boxes: bold/italic across the standard fonts, with font, outline,
  and fill controls in the style popup.
- Forms: fill fields directly in reading mode, and use the form tool to
  select, move, resize, and rename fields.
- Per-tool style memory: each annotation tool remembers its own color,
  stroke, opacity, font, and line style across sessions.
- Responsive UI: a floating toolbar, side panels and the thumbnail strip
  become bottom sheets on small screens, and tap-to-place for text,
  stamps, and signatures.
- Input & performance: reduced Apple Pencil latency (forward-extrapolated
  prediction), single-finger scroll in pencil mode, Shift+drag marquee
  selection, aspect-lock and past-zero invert on resize, an eraser-size
  control, render pacing for smooth fast-scrolling, compact auto-dismissing
  snackbars, and a ⌘S / Ctrl+S save shortcut.
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
- Keyboard shortcuts for the common editing tools: single, unmodified keys
  arm a tool from the viewer (V select, P pen/ink, E eraser, R rectangle,
  O ellipse, L line, A arrow, T text box, N note, S stamp, I image,
  G signature, M measure, F form, C content, K redact); pressing a tool's
  key again drops back to Select. Active only during an editing session and
  suppressed while an in-place text editor (free text or form field) is
  open. The bindings are exposed as `pdfEditToolShortcuts` and surfaced in
  the toolbar tooltips (e.g. "Rectangle (R)").

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
