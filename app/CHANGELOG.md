# Changelog

## 1.4.7

- Printing now goes through each platform's own print system, so
  documents that open here but trip up other engines print reliably —
  and printing no longer crashes the app on Windows.
- Scanned and image-heavy pages, especially large print exports, render
  much faster and use less memory; the app also frees cached images when
  the system is low on memory.
- Rectangle shapes can now have rounded corners, and dash and cloud
  patterns can be scaled independently of line thickness.
- Copy, cut, and paste whole pages in the page thumbnail view — including
  between open document tabs — with the usual keyboard shortcuts.
- The colour picker now shows a swatch grid with the colours you recently
  used and the colours already in the open document.
- Nudge a selected annotation with the arrow keys, add or remove points on
  polyline and polygon shapes, and recolour a pasted vector snapshot.
- Add a visible signature box when signing, showing the signer's name and
  details (and an optional handwritten-signature or logo graphic).
- Free-text boxes gain line spacing, letter spacing, width, and underline
  controls, and Save now works on a brand-new untitled document.

## 1.4.6

- Hover a document tab on desktop to preview the page before switching to it,
  and open a grid of all open documents to jump between them.
- Edit, style, and markup actions are now offered directly when you select text
  in a document.
- Tightened the desktop menus so more fits on screen without scrolling.
- Arabic search now matches text copied out of a page, marks and vowel signs
  stay attached to their letters when selecting or copying, and pasted Arabic
  renders with a bundled font.
- Large scanned pages open faster and use less memory.

## 1.4.5

- Correct Arabic and other right-to-left page-text extraction, selection, and
  copy ordering, including multi-word lines.

## 1.4.4

- Ship the regenerated editor web worker so browser builds include the current
  form and fragmented-strip rendering fixes.

## 1.4.3

- Enlarge the DartPDF corner badge on PDF document thumbnails so it remains
  recognizable at smaller Finder and Explorer icon sizes.
- Keep drag-time thickness, opacity, and measurement indicators aligned and
  consistently sized when the document is zoomed.
- Make form-field right-click select the field and move its edit, rename,
  conversion, delete, flatten, and style actions into the toolbar.
- Remove the redundant selected-text copy button from the desktop app header;
  keyboard and context-menu copy remain available.
- Add proper certificate-backed PAdES digital signatures from the app menu,
  using an RSA private key and X.509 certificate chain entirely in memory.
- Create new blank PDFs from page-size and orientation presets, including
  Ctrl/Cmd+N and correct unsaved-document handling.
- Make Save As adopt the selected filename and writable origin for subsequent
  saves while preserving the active editing and viewer sessions.

## 1.4.1

- Windows: Snapshots now copy to the system clipboard instead of failing with
  "Could not copy snapshot to clipboard". The desktop clipboard channel had no
  Windows handler, so the image never reached the OS clipboard.
- Mobile: Recent files and the last session now reopen without a fresh pick.
  Opened PDFs are snapshotted into the app's private store, so tapping a Recent
  entry (or relaunching) reopens the document directly instead of showing "Pick
  again to reopen".
- Add callout annotations and rich-text styling for in-place document text
  edits.
- Capture a local diagnostic log and attach it to feedback, making rendering
  and workflow issues easier to investigate without collecting user data.
- Greatly improve large CAD and illustration documents with adaptive retained
  rendering, visible-region prioritization, exact raster reuse, and off-thread
  strip planning on native and web.
- Keep page edges reachable after pinch gestures on Android and improve glyph
  and image sharpness while zooming and panning.
- Improve macOS document opening, branded PDF file icons, store/web marketing
  assets, and production web startup reliability.

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
