# Changelog

## Unreleased

- Windows: Snapshots now copy to the system clipboard instead of failing with
  "Could not copy snapshot to clipboard". The desktop clipboard channel had no
  Windows handler, so the image never reached the OS clipboard.
- Mobile: Recent files and the last session now reopen without a fresh pick.
  Opened PDFs are snapshotted into the app's private store, so tapping a Recent
  entry (or relaunching) reopens the document directly instead of showing "Pick
  again to reopen".

## 1.4.0

- Add color processing for replacing document colors across selected pages or
  the full document, including multi-source selection, document color swatches,
  custom picker colors, transparent replacement, and background processing for
  larger files.
- Add full bookmark management, cloud polygon markups, freehand highlighting,
  stamp hover previews, stamp import/export, annotation apply-to-pages, and
  image export from selected PDF content.
- Improve desktop workflows with Open Recent, visible shortcut labels,
  feedback links, multi-file picker selection, and more reliable macOS
  open-with and OneDrive/security-scoped file access.
- Polish page and annotation navigation: hover-only desktop controls,
  arrow-key page navigation, page-grid click-to-select/double-click-to-open,
  and fixes for thumbnail/search layout overflow.
- Fix eraser misses across separate ink annotations, highlighter style leakage,
  color-lock handling, and several popup/menu layout issues.

## 1.3.2

- Editing polish from the 1.3.2 package suite: no-flicker annotation
  appearance updates, zoom-stable chrome, improved gesture rendering, right-click
  form-field editing, and more direct highlight styling.
- Custom stamps can now be built from vector templates with dynamic fields,
  saved signatures, image components, metadata, and configurable date/time
  placeholders.
- macOS release builds more reliably re-sign embedded native libraries.

## 1.3.1

- Text boxes can use installed platform fonts through the editor font menu;
  selected fonts are embedded so documents render and print consistently.
- Includes the 1.3.1 package-suite updates for custom editor toolbar chrome,
  OCR rasterization, rendering, annotation editing robustness, and interpreter
  color handling.

## 1.2.3

- Print the open document through the OS print dialog on every platform
  (browser print on the web), from ⌘P / Ctrl+P or the DartPDF menu.

## 1.2.2

- View rotation, deeper zoom, and smoother touch scrolling in the viewer.
- Free-text editing improvements: any embedded TrueType/OpenType font,
  paste-to-text-box, autosize, right-to-left text, and fixes for non-Latin
  glyphs and rotated pages.
- Background render worker preempts superseded jobs and recovers from a slow
  or silent worker, so large CAD drawings no longer hang while scrolling.
- Save As (Ctrl/Cmd+Shift+S), "Set up as default application", and "Open
  containing folder" in the tab context menu.
- Windows on-device OCR model path staging fix.
- Android: support 16 KB memory page sizes.
