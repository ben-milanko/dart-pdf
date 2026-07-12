# Changelog

## 1.4.2

- Keep touch scrolling responsive on zoomed mixed-width documents when a
  gesture starts on the canvas or in an inter-page gap, and keep the current
  page and render focus synchronized with the transformed viewport.
- Prevent dense pages from rendering as solid magenta on iPad by routing iOS
  deep-zoom replay through the stable canvas path instead of shader-backed
  sparse strips.

## 1.4.1

- Add callout annotations and rich-text styling for in-place document text
  edits, including the editor controls and annotation presentation support.
- Make dense CAD and illustration pages substantially more responsive with
  retained-scene replay, adaptive render policy, sparse strip rendering,
  speculative visible-region detail, and exact raster reuse on revisits.
- Run strip planning and dense recording off the UI thread on native and web;
  reuse compact Web Worker transcripts and prioritize visible detail to reduce
  cold-start, zoom, and pan latency.
- Bundle the default web render worker as a package asset and repair production
  web loading, while retaining the public override for custom worker hosting.
- Keep page edges reachable after Android pinch gestures and keep Slug glyphs
  and image content sharp while zooming and panning.
- Consolidate annotation policy, editing interactions, shell lifecycle, page
  rendering, sidebar framing, and edit transactions without removing exported
  APIs.

## 1.4.0

- Color processing: add a Bluebeam-style tool that can list document colors,
  replace one or more selected colors across selected pages or the whole
  document, replace colors with transparency, and run large-document
  processing in the background to avoid UI hangs.
- Bookmarks: add a PDF outline/bookmarks panel with create, edit, delete, and
  navigation support in the reader and editor shells.
- Editing tools: add freehand highlighting, cloudy polygon annotations,
  annotation apply-to-pages, selected-image export, color locking, and stronger
  style isolation when switching tools.
- Stamps: support hover placement previews, custom template dimensions, and
  import/export for custom stamp libraries.
- Page and annotation chrome: add hover-only controls on mouse platforms,
  arrow-key navigation for thumbnail/page views, page-grid click-to-select
  with double-click navigation, and layout fixes for thumbnail/search chrome.
- Web rendering: ship the render worker as a package asset and use it by
  default, so Flutter web apps no longer need to set
  `pdfRenderWorkerScriptUrl` unless they want to self-host the worker.
- App integrations: improve macOS open-with/file access handling, multi-file
  picking, recent-file menus, menu shortcut labels, and the built-in feedback
  link.

## 1.3.2

- Viewer rendering: annotation appearances now paint in a separate overlay
  from the base page raster, so annotation-only edits no longer invalidate the
  expensive page image or flicker while a refreshed appearance is rendering.
- Viewer interaction: motion-based render hold defers expensive UI work during
  active gestures, chrome stays visually constant while zoomed, and annotation
  hit handling exposes a new `PdfAnnotationTapHandler` callback.
- Editing UI: the draw toolbar includes a freehand highlight tool, active text
  selections can be styled as markup, count-tool cursor previews are more
  accurate, and the takeoff panel has improved accessibility labels.
- Forms: right-click form-field editing and form-style controls are available
  from the viewer, including font and visual style updates.
- Stamps: custom stamps can be vector templates with dynamic fields, images,
  saved signatures, metadata tags/types, host-provided stamp lists, and
  configurable date/time placeholder formats.
- Fix rendering artifacts from stale detail patches after visual content
  changes and keep the current annotation layer visible while updated
  appearances load.

## 1.3.1

- Font menu: offer the host platform's installed fonts as embeddable choices
  alongside the base-14 families and bundled fonts. A host fills the new
  `pdfPlatformFonts` registry once at startup (the example/app scan the OS
  font directories on native; web stays empty), and every font menu picks
  them up by default. Picking one embeds its outlines into the document so
  the text renders and prints everywhere. New `PdfPlatformFont` type and an
  optional `platformFonts` argument on `PdfFontMenuButton`/`showPdfFontMenu`.
- `PdfEditorView` can now replace the stock bottom editing toolbar via
  `toolbarBuilder`, in addition to the existing leading/trailing toolbar
  extension points.
- OCR: `PdfEditor.applyOcr` now accepts a `PdfOcrRasterizer`, so hosts and
  tests can provide their own rasterization backend while still using the
  built-in text-layer injection flow.
- Rendering: `PdfPageRenderPlan` carries page color, annotation visibility,
  and view rotation through the renderer paths, keeping viewer rasters,
  color sampling, and worker replay in sync.
- Shells: shared panel layout keeps the viewer element stable while docking
  side panels, bottom sheets, and floating or docked toolbars.

## 1.2.3

- Free text: align a text box left, center, or right. The alignment buttons
  sit in the text style popup and the annotation properties panel - they
  apply to the selected box and set the default for new boxes (remembered
  per the text tool). New boxes still follow the text direction until you
  pick an alignment.

## 1.2.2

- View rotation: rotate the displayed page in 90° steps without changing the
  document's page orientation; selection, overlays, and hit-testing follow
  the rotated view.
- Background render worker: in-flight jobs are now preempted when superseded
  (fast scrolls drop stale work instead of queueing), the web worker compiles
  reliably, and the viewer recovers from a slow or silent worker instead of
  hanging.
- Touch: horizontal scrolling rubber-bands at the edges and pans in reader
  mode; deeper zoom is allowed for long plots and large CAD drawings.
- Free text: author text in any embedded TrueType/OpenType font via the font
  menu, paste clipboard text as a free-text annotation, an autosize shortcut,
  right-to-left text direction, corrected inline editing baseline, and
  double-click-to-edit. Non-Latin glyphs and text on rotated pages render
  correctly.
- Ink: the cursor stays at the stroke end, switching to the eraser defers the
  pending commit, and Escape commits the in-progress stroke instead of
  discarding it.
- Save As (Ctrl/Cmd+Shift+S) writes the document to a new file.
- Snapshot/stamp paste shows a preview before the raster refresh.
- Android: support 16 KB memory page sizes.

## 1.2.1

- Shorten the package description so pub.dev awards the full pubspec score.

## 1.2.0

- Responsive shell and mobile editing chrome improvements, including compact
  tab switching, mobile header controls, bottom-sheet shell options, and
  cleaner menu layout.
- Standalone-app integration polish: browser-local OCR wiring, loading state
  while opening PDFs, trackpad momentum when edit tools are active, Apple
  Pencil double-tap eraser toggle, and clearer markup text-selection labels.
- Web startup and branded splash/icon updates for the app and example.

## 1.1.0

- Full font selection for text boxes: a font menu (in the style popup and
  the properties panel) offers the standard families, a set of bundled
  full-Unicode fonts (DejaVu Sans/Serif/Mono), and "Load font…" - a
  host-provided `PdfFontPicker` for any `.ttf`/`.otf` file. The chosen
  font embeds into the document so the text renders and prints
  identically everywhere. `PdfEditingController.activeFont`/`setCustomFont`
  drive new text; editing an embedded-font box keeps its font.
- Rotate pages from the thumbnail strip: a per-tile rotate-right button,
  plus rotate-left/right actions in the multi-select bar.
  `PdfEditingController.rotatePages`/`rotateSelectedPages` turn pages
  clockwise (or counterclockwise) without shifting page indices, so the
  page selection survives the edit.
- Snapshot tool (`PdfEditTool.snapshot`, in the Edit toolbar): drag a
  region to capture it, Bluebeam-style. The captured region is rendered to
  a PNG handed to `PdfViewer.onSnapshot` (copy/save/share) AND kept on the
  controller as detached **vector** graphics. Paste it back into the PDF
  with ⌘V/Ctrl+V or the right-click Paste (`PdfEditingController.
  pasteSnapshot`) and it stays vector, crisp at any zoom.
- Background rendering: heavy pages now interpret off the UI thread, so
  scrolling and drawing stay smooth on large/CAD documents.
  `PdfRenderWorker` runs page interpretation and image decode in a
  background isolate (native) or a dedicated Web Worker (web); set
  `pdfRenderWorkerScriptUrl` and build the worker bundle with
  `dart run dart_pdf_editor:build_web_worker` to enable it on the web. The
  viewer also paints a low-res preview of pages still rendering during a
  fast scroll, and cancels superseded prefetches.
- Reflow reading view: images and diagrams now appear inline with the
  text, decoded and laid out at their on-page aspect ratio in reading
  order; bullet/numbered lists read as separate, indented items.
  `PdfReflowView.showImages` (default true) toggles back to text-only.
  The view now scrolls through a single non-lazy list so the scrollbar
  no longer jumps as pages of differing heights (text vs. images) come
  into view.
- Toolbar tool types can be disabled individually: the new
  `PdfEditingToolbar.groups` (and `PdfEditorFeatures.toolGroups`) takes a
  set of `PdfEditToolGroup` values (Select, Markup, Draw, Shapes, Insert,
  Measure, Edit). Pass a subset to hide whole tool types at once,
  without enumerating each tool in `tools`.
- Count tool: place Bluebeam-style check-marks and watch a running
  on-page tally. This is the editor surface for `PdfEditor.addCheckMark`.
- Right-click text context menu on mouse platforms (copy, select all).
- Thumbnail strip: Shift-click to multi-select a range of pages.
- Single-key keyboard shortcuts for the common editing tools.
- Performance: decoded image XObjects and substituted-text glyph layouts
  are cached across renders; per-pixel image decode is inlined; the
  preview prerender is bounded to a window around the viewport.
- Fixes: page content no longer flashes under a moved annotation's old
  spot; mobile toolbar colors show only when relevant to the current
  tool; thumbnail-sheet scrolling and header layout overflow.

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
- Pluggable OCR: `PdfOcrEngine` (a host-supplied recognizer such as ML Kit,
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
  position automatically. Pass `documentId` for a stable key, or let it
  derive one from the bytes (`pdfDocumentKey`).
- Keyboard shortcuts for the common editing tools: single, unmodified keys
  arm a tool from the viewer (V select, P pen/ink, E eraser, R rectangle,
  O ellipse, L line, A arrow, T text box, N note, S stamp, I image,
  G snapshot, H signature, M measure, F form, C content, K redact); pressing a tool's
  key again drops back to Select. Active only during an editing session and
  suppressed while an in-place text editor (free text or form field) is
  open. The bindings are exposed as `pdfEditToolShortcuts` and surfaced in
  the toolbar tooltips (e.g. "Rectangle (R)").

## 0.1.0

Initial release.

- Drop-in widgets: `PdfEditorView` (the full editor: header bar with
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
