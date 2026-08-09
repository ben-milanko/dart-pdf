# Changelog

## 3.4.0

- Copy and paste annotations between open documents, save placed stamps back
  to the stamp collection, and show the selected annotation colour in the
  toolbar.
- Drop a PDF between page thumbnails to insert its pages at that exact
  position, and optionally show document chapters on the scrollbar.
- Improve proportional-font selection and substituted-font placement, keep
  touch selection menus aligned while zoomed, and hide page-colour editing in
  view mode.
- Improve tab-grid scrolling, trackpad pinch-out scrolling, progressive file
  access, and print-preview reliability.

## 3.3.1

- Changing annotation properties no longer creates a duplicate in PDFs that
  store annotation lists indirectly.
- Text colour changes now preserve embedded fonts, and cloud/polygon live
  previews retain the configured pattern scale.
- Multi-page reordering has clearer group feedback and moves the selected page
  set reliably.

## 3.3.0

- Pages you revisit can open immediately from full-resolution memory and disk
  caches, while optional idle warming prepares more pages before you navigate
  to them.
- Deep zoom is sharper on scanned and image-backed PDFs because visible tiles
  re-decode the source image at the requested detail.
- Touch panning responds sooner and works reliably from the canvas around a
  page. Rectangle corner radius is available in the properties panel, newly
  inserted PDF pages stay in view, and the floating toolbar no longer obscures
  the end of a document.
- Linux users can install from the preferred GPG-signed Flatpak repository or
  the secondary Snap package, with AppImage and portable archives retained as
  fallbacks.

## 3.2.0

- Page caching now adapts to device memory and system pressure, and the render
  pipeline avoids redundant full-page and detail work. Large and dense
  documents stay responsive while using a larger cache where the device can
  afford it.
- Third-party FreeText boxes and callouts render more faithfully, including
  wrapping, alignment, fills, borders, and leader lines. Multi-line text
  markups select only where their visible quads are painted.
- Fix loading pauses on macOS, keep remote session restoration responsive, and
  preserve Ctrl/Cmd-wheel zoom after drawing a Shift-constrained line.
- Add opt-in nightly Windows updates for users who want the newest fixes
  between stable releases.

## 3.1.1

- Smoother scrolling on large and visually dense PDFs, with the page renderer
  staying responsive through rapid mouse-wheel gestures.
- Page previews remain visible during fast scrolling and settle cleanly into
  full-detail renders, with fewer dropped frames.

## 3.1.0

- Scan documents straight into a PDF: scan to a new document or insert a scan
  into the open one, and take a photo with the camera on mobile.
- Never lose work to a crash: unsaved changes are mirrored in the background
  and restored when the document is reopened.
- New editing tools: hyperlinks (web and in-document), cropping for placed
  images, annotation lock/unlock, and keyboard shortcuts for every tool.
- Faithful overprint rendering — print-oriented PDFs that rely on overprint
  (knockouts, spot inks) now display the way they print.
- Pages reveal progressively as they render, and rendering is much faster on
  large or image-heavy files; search text is extracted in the background.
- Recent files can show as a grid of page thumbnails.
- Shrink a PDF's file size losslessly from the save flow.
- The app updates itself in place on desktop — "Update now" downloads and
  applies the new version without a browser visit.

## 3.0.0

- The app is now available in 10 languages, with full right-to-left layout
  for Arabic.
- More accurate overprint, blend-mode and soft-mask rendering.
- Hold Shift to draw straight lines, and set a default style for annotations.
- Redesigned, smoother document tabs.
- Faster rendering and lower memory use on large files.

## 2.1.0

- Reflow reading view: read a document as flowing text instead of fixed
  pages, with lazy scrolling, quick navigation, a remembered reading
  position, and a figure viewer for images and diagrams.
- Faster opening and rendering, especially on large or image-heavy files;
  saving an edit is proportional to the size of the change, and very wide
  drawings use less memory.
- Crisper hairlines, so fine linework stays legible when zoomed out.
- Better colour on gradients and indexed images; Symbol and ZapfDingbats
  characters render instead of empty boxes.

## 2.0.0

- Deep zoom now shows crisp detail on every platform: zoom past the normal
  limit and the visible area re-renders at full resolution instead of looking
  blurry.
- Large files and cloud documents open much faster — the first page appears
  while the rest of the file is still loading, instead of waiting for the whole
  download or read to finish.
- Digitally sign a document with one tap: create a signing identity in the app
  (self-signed, or keyless via Sigstore) and sign without setting up
  certificates by hand.
- Rearrange the workspace: side panels can be dragged and docked to any edge,
  placed side by side or grouped into tabs, and the layout is remembered.
  Press F12 for a developer-tools overlay.
- The font menu lists the document's own fonts and your recent picks, and the
  toolbar shows the actual embedded typeface.
- The annotation list supports multi-select (ctrl/shift) and a hover menu.
- Better colour accuracy for certain CMYK photos, and assorted mobile polish.

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
