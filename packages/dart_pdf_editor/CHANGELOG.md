# Changelog

## Unreleased

- Add X-strip transcript banding to bound retained memory on extreme-aspect
  pages (`PdfBandedTranscript`): partition a page's `PdfRenderCommand`
  transcript into N vertical strips along the horizontal pan axis, retain only
  the strips overlapping the viewport, and re-materialize an evicted strip on
  demand. `PdfRetainedScene` gains `bandTranscript`/`bands`/`reband`,
  `dropRegionIndex`, and `debugUnitBandHistogram`; the viewer's memory-pressure
  path now sheds retained-scene spatial metadata via
  `PdfRetainedScene.handleMemoryPressure` (dropped indices rebuild identically,
  evicted strips re-materialize, so there is no visual regression) (#385).

## 2.0.0

- **Breaking:** remove the pure style forwarders from `PdfEditingController`.
  The ~19 tool-style properties that only mirrored `preferences`
  (`strokeWidth`, `cornerRadius`, `eraserRadius`, `fontSize`, `textAlign`,
  `opacity`, `lineStyle`, `lineScale`, `lineStartEnding`, `lineEndEnding`,
  `textFillColor`, `textBorderColor`, `shapeFillColor`, `author`,
  `stampDateFormat`, `stampTimeFormat`, `fingerDrawsInk`, `measurementScale`,
  `signature`) are gone; read and write them through
  `controller.preferences.<name>` instead. The setters that carried editing
  side effects stay on the controller (`color` still recolours the active
  stamp and honours the colour lock; `fontFamily` still clears the embedded
  `activeFont`), as do the computed helpers (`dashedStroke`,
  `hasMeasurementScale`) and every signature/measurement behaviour method
  (`placeSignature`, `calibrateScale`, `measuredDistance`, …) (#317).
- Expose a customizable viewer scroll indicator / page-scrubber API: a
  read-only `PdfScrollMetrics` snapshot (page count, current page,
  normalized position/extent, pixel offsets, zoom) via
  `PdfViewerController.scrollMetrics`, page-aware commands
  `jumpToNormalized` and `animateToPage` alongside the existing
  `jumpToPage`, and a `PdfViewer.scrollIndicatorBuilder` that replaces the
  built-in vertical scrollbar with a host widget (#326).
- Add configurable page layouts to `PdfViewer`: the new `pageLayout`
  parameter takes a `PdfPageLayout` - `verticalContinuous()` (the default,
  top-to-bottom) or `horizontalContinuous()` (left-to-right, book-like
  reading and wide documents). The horizontal layout keeps every viewer
  behaviour along the new axis - virtualization, zoom/pan, current-page
  tracking, search and destination navigation, text selection, overlays,
  links, forms/annotation hit-testing, keyboard navigation, and mixed page
  sizes (pages fit the viewport height and centre on the cross axis).
  `PdfPageLayout` is a value type with named constructors so further layouts
  (facing/two-page) can be added without changing the viewer's API.
  `PdfReader` and `PdfEditorView` forward the option (#324).
- Deep-zoom detail via a budgeted zoom-bucket tile pyramid (`PdfTileStore`),
  now enabled by default on every platform: past the raster caps the viewer
  renders and caches the visible slice at native resolution instead of
  upscaling, with a budget-vs-demand guard against eviction thrash (#314).
- Open local and remote files through the ranged `PdfByteSource` so the first
  page paints before the whole file is read/downloaded (#359, #328).
- Wire Sigstore/Fulcio keyless and one-tap self-signed signing into the editor,
  including the "Create signing identity" UI and secure key storage (#322).
- Introduce `PdfEditToolBehavior` as the single source of tool identity, and
  collapse `PdfViewer`'s separate `document` + editing inputs into one revision
  source (#311, #319).
- Draggable, dockable side panels (any edge, side-by-side or tab groups, with a
  saved layout) and an F12 developer-tools overlay (#362, #360).
- Annotation list gains a hover more-menu and ctrl/shift multi-select (#350),
  and the toolbar font chip shows the real embedded face (#348).

## 1.4.7

- Print through each platform's native print system: the Dart engine
  renders every page itself and streams it to the OS (Windows, macOS,
  iOS, Android, Linux) or the browser, replacing the `printing` plugin
  and its bundled PDFium so broken-but-renderable documents no longer
  crash on print. `rasterizePdfForPrinting` and `printPdfBytes` back the
  path (#291).
- Add page copy/cut/paste to the thumbnail strip and grid, shared across
  document tabs via a process-wide `PdfPageClipboard`: controller gains
  `copyPages`/`cutPages`/`pastePages` (and the `*SelectedPages` variants),
  wired into the context menu, bulk-selection bar, header menu, and
  Cmd/Ctrl+C/X/V (#299).
- Round the corners of rectangle (/Square) shapes: a rectangle-only
  "Corner radius" slider in the tune popup, applied at creation and
  restylable on a selected rectangle (`restyleSelected(cornerRadius:)`,
  `canRoundSelectedCorners`, `selectedCornerRadius`) (#297).
- Separate line thickness from pattern scale: a "Pattern scale" slider
  (0.5x–4x) sizes dash lengths and cloud scallops independently of the
  pen width (`restyleSelected(scale:)`, `selectedLineScale`), so a thin
  outline can carry big puffs or a heavy line tight dashes (#300).
- Add and remove /PolyLine and /Polygon vertices from the context menu
  (Add node / Remove node), splicing into the nearest edge or dropping
  the nearest vertex — `addSelectedVertexAt`, `removeSelectedVertexNear`,
  `canAddSelectedVertex`, `canRemoveSelectedVertex` (#288).
- Recolour pasted vector snapshots from the annotation context menu
  ("Recolour…"): retints the captured Form XObject to a single ink
  without touching geometry — `recolorSnapshotSelected`,
  `canRecolorSnapshotSelected` (#301).
- Add a swatch grid to the annotation colour picker below the value row:
  a fixed palette plus recently-chosen colours (persisted, capped at 18)
  and the colours already used in the open document
  (`documentAnnotationColors`), via `pickEditingColor` (#292).
- Shapes and revision clouds: add an "Outline" colour row to the tune popup,
  next to "Fill", so a cloud's stroke colour can be picked from the tune menu
  (not just the toolbar swatches) — armed or with the shape selected.
- Curl revision-cloud scallops inward with a trailing-foot lean so each
  puff rolls one way into the hand-drawn Bluebeam/Acrobat look, matched in
  the live editor preview (#295).
- Fill cloudy /Polygon annotations to the scalloped cloud edges instead
  of only to the straight vertex polygon, mirrored in the live preview so
  no unfilled crescent shows under each row of puffs (#287).
- Preview a 'TEXT' placeholder while hovering the text-stamp tool so the
  click target is visible even when no custom stamp is active (#293).
- Make the custom-stamp template composer use the on-page overlay's
  touch interaction: a GestureDetector with touch slop and eight
  corner/edge handles, so tap-to-select no longer nudges the component
  and resizing grabs a forgiving target (#304).
- Let the style sliders' numeric readouts accept a wider typed range than
  the slider scale can reach (`PdfSliderValueField` fieldMin/fieldMax;
  point/size values up to `kPdfTypedSizeMax` = 1000, opacity a true
  0–100%, line spacing 0.1–100x) (#302).
- Fix Ctrl/⌘+S doing nothing on a brand-new untitled document with no
  edits yet: `PdfEditorView.alwaysAllowSave` keeps Save enabled so the
  first save routes to Save As (#294).
- Nudge the selected annotation(s) with the arrow keys — 1 pt per press,
  10 pt with Shift — translating the move through the page's /Rotate so a
  key always slides the annotation the way it points on screen. A bare
  arrow still scrolls the page when nothing is selected.
- Bound the render worker's page-record cache by entry count, not only by
  decoded-image bytes: image-free and vector-first records weigh zero, so on a
  long scroll they used to accumulate one (or more) per page for the life of
  the worker with no limit (issue #283). The cache now caps retained records
  (`pdfRenderWorkerCacheMaxEntries`, default 64), so a long document's memory
  no longer grows unbounded in the page count.
- Bound the viewer's four per-page maps (text, annotations, visible
  annotations, form-field rects) by entry count via the new LRU
  `PdfPageObjectCache` (`pdfViewerPageObjectCacheMaxEntries`, default
  128), so revisiting pages still hits but retention no longer grows one
  entry per page visited for the life of the viewer (issue #283).
- Size the decoded-image cache budget per platform (`PdfImageCache`
  default 256 MB desktop, 128 MB mobile/web, 64 MB on a ≤2 GB browser
  device), measured against the corpus, and clear the image + preview
  caches on `didHaveMemoryPressure` (#284, issue #281).
- Unify per-page render timings into one `PdfRenderTrace` value type that
  both isolates fill (worker parse/interpret/serialize; main isolate
  transfer/deserialize/replay/rasterize), surfaced via
  `PdfRenderTrace.captureOffThread` and `PdfRenderWorker.lastRenderTrace`
  (free unless `PdfPerfLog` is on). Adds `PdfRenderPhaseBudget` and a
  default-on render-trace gate test guarding against per-phase
  regressions; `PdfWorkerPhaseTimings` is now an alias of the new type
  (#321).
- Free-text boxes: add line spacing, character spacing, font width
  (horizontal scaling), and underline controls (tune popup + properties
  panel), with an inline underline toggle and Cmd/Ctrl+U shortcut.
- Fix backspacing in an inline free-text editor sliding a bold (or otherwise
  styled) run onto the following characters — style runs now follow their
  own text across edits.
- Resize an embedded/bundled-font free-text box by re-wrapping it (as with
  base-14 boxes) instead of stretching the glyphs, and keep rich per-run
  styling across the resize.
- Keep a free-text box's alignment in the resize preview and post-commit
  afterimage so it no longer appears to snap to the left while dragging.
- Show a free-text box's actual (embedded/bundled) font name in the font
  picker instead of collapsing it to "Sans".
- Stop the inline editor's line spacing shifting when a run's font changes
  in the tune popup (font-independent leading, matching the appearance).
- Fix tapping a free-text style-chip button (underline, size, …) on touch
  devices committing and deselecting the box out from under the tap.

## 1.4.6

- Expose edit-and-style and markup actions when text is selected in an
  editor-backed viewer, on both touch and desktop context menus.
- Treat each `applyRemoteChange` as an undo checkpoint: local edits made after
  a remote apply stay undoable, but undo can no longer remove remote state or
  cross into older local history.
- Fall back to the bundled DejaVu Sans and platform Arabic faces when
  substituting fonts, so Arabic (including the presentation forms copied out
  of shaped PDFs), Hebrew, Greek, and Cyrillic render on hosts whose Helvetica
  substitute has no suitable fallback.
- Regenerate the bundled web render worker so browser builds pick up the
  scaled CCITT decode path and the right-to-left text fixes.

## 1.4.5

## 1.4.5

- Correct selection and copy ordering for multi-word Arabic and other
  right-to-left page text.

## 1.4.4

- Regenerate the bundled web render worker from the current sources so web
  consumers receive the 1.4.3 form and fragmented-strip rendering fixes.

## 1.4.3

- Bake page rotation into regenerated form appearances so existing and newly
  authored fields remain upright after rotating the document.
- Add certificate-backed PAdES B-B digital signing to editing sessions via
  `PdfDigitalSignatureIdentity` and `addDigitalSignature`, including key/cert
  matching, validation before commit, and undo/redo support.
- Allow a selected form field to be converted between text, check-box, and
  image-button types from the contextual toolbar or properties panel while
  keeping the rebuilt field selected.
- Make form-field right-click select the field instead of opening an oversized
  context menu, with value, rename, type, delete, flatten, and style actions in
  the contextual toolbar.
- Keep the floating stroke-width, opacity, and measurement readouts at a
  constant screen size and cursor offset while the document is zoomed.
- Show common and mixed (`Varies`) values for multi-selected annotations in
  the properties panel, with bulk edits for compatible appearance, line,
  contents, and author properties.
- Restyle annotation-thread Reply and Resolve controls as compact, muted text
  actions that emphasize only on hover, focus, or press.
- Keep clip-heavy Visio and CAD pages responsive by detecting fragmented
  sparse-strip plans before worker binning and using cached canvas replay.

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
