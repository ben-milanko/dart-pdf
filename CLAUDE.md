# dart-pdf — pure-Dart PDF renderer & editor

Monorepo using **pub workspaces** (root `pubspec.yaml` lists members under
`packages/`). Flutter is managed with **fvm** (see `.fvmrc`); use
`fvm flutter` / `fvm dart`, or the binaries in `~/fvm/versions/3.44.2/bin/`.

## Commands

- `fvm flutter pub get` (at repo root — resolves every workspace package)
- `fvm dart analyze` (at root)
- `cd packages/<pkg> && fvm dart test` (pure-Dart packages)
- `cd packages/dart_pdf_editor && fvm flutter test`

## Layering rules (strict)

`pdf_cos` ← `pdf_document` ← `pdf_graphics` ← `dart_pdf_editor`

- `dart:ui` and Flutter imports are **only** allowed in `dart_pdf_editor`.
  Everything else must run on the Dart VM (server/CLI/tests) and on the web.
- `dart:io` is not allowed anywhere in `lib/` (web support); use
  `package:archive` for compression.
- `pdf_cos` knows nothing about pages or rendering — only the COS object
  model, syntax, filters, xref, and (de)serialization.

## Design conventions

- Parsers are lenient on input (real-world PDFs are broken: wrong /Length,
  missing endobj, junk before header) and strict on output.
- Streams stay as raw byte views (`Uint8List.sublistView`) until decoded;
  objects load lazily through the xref.
- `CosDictionary` is keyed by `String` (name without the slash).
- Test fixtures are built programmatically in `test/fixtures.dart` so byte
  offsets are always correct — don't hand-edit offsets.

## Test corpus

`corpus/` (git-ignored) holds ~50 real-world PDFs copied from Ben's local
folders and OneDrive — CAD drawings, scanned docs, reports, forms. Use them
to validate changes:

- Parse check: `cd packages/pdf_document && fvm dart tool/inspect.dart ../../corpus/*.pdf`
- Render check: `cd packages/dart_pdf_editor && PDF_PATH=../../corpus/<file>.pdf PDF_PAGE=0 fvm flutter test test/render_smoke_test.dart` (writes /tmp/dart_pdf_render.png)
- Full render sweep: `cd packages/dart_pdf_editor && CORPUS_DIR=../../corpus RENDER_OUT=../../corpus/renders fvm flutter test test/corpus_render_test.dart`

`test_corpora/ghent/` (checked in) is the Ghent PDF Output Suite V5.0 —
54 print-conformance PDFs (overprint, DeviceN, spot, ICC v2/v4, 16-bit,
transparency blend modes, softmasks, optional content, font formats,
JBIG2/JPX) incl. 3 composite test pages. Two test layers:

- `packages/pdf_graphics/test/ghent_corpus_test.dart` — pure-Dart: every
  page must interpret without throwing and paint > 0 ops.
- `packages/dart_pdf_editor/test/ghent_render_test.dart` — rasterizes every
  page and diffs against checked-in baselines in
  `test_corpora/ghent/_baselines` (fail when >0.05% of pixels differ by
  >8/channel). Missing baselines seed on first run; accept intentional
  rendering changes with `GHENT_UPDATE=1 fvm flutter test
  test/ghent_render_test.dart`. Mismatches dump actual+diff PNGs to
  `test_corpora/ghent/_failures/` (git-ignored). The baselines pin
  current behavior, not GWG conformance — many patches print their own
  pass criterion on the page (overprint simulation isn't implemented;
  GWG173's faint "X" is a known JBIG2 deviation).

Run the checked-in corpora from their package directories so the relative
`../../test_corpora/...` paths line up:

- Ghent pure-Dart pass: `cd packages/pdf_graphics && fvm dart test test/ghent_corpus_test.dart`
- Ghent render/baseline pass: `cd packages/dart_pdf_editor && fvm flutter test test/ghent_render_test.dart`
- Accept intentional Ghent baseline changes: `cd packages/dart_pdf_editor && GHENT_UPDATE=1 fvm flutter test test/ghent_render_test.dart`
- Ghent visual review gallery: `cd packages/dart_pdf_editor && GHENT_RENDER_OUT=../../test_corpora/ghent/_renders fvm flutter test test/ghent_render_test.dart`, then open `test_corpora/ghent/_renders/index.html`
- PDF.js pure-Dart pass: `cd packages/pdf_graphics && fvm dart test test/pdfjs_corpus_test.dart`
- PDF.js render smoke pass: `cd packages/dart_pdf_editor && fvm flutter test test/pdfjs_render_test.dart`
- PDF.js visual review gallery: `cd packages/dart_pdf_editor && PDFJS_RENDER_OUT=../../test_corpora/pdfjs/_renders fvm flutter test test/pdfjs_render_test.dart`, then open `test_corpora/pdfjs/_renders/index.html`
- Generate PDF.js reference baselines: `cd packages/dart_pdf_editor/tool/pdfjs_baseline && npm install && npm run render`
- PDF.js pixel compare + side-by-side results: `cd packages/dart_pdf_editor && PDFJS_BASELINE_DIR=../../test_corpora/pdfjs/_baselines fvm flutter test test/pdfjs_render_test.dart`, then open `test_corpora/pdfjs/_renders/index.html`
- All checked-in corpus tests: run the four non-update test commands above
  (excluding the visual galleries); they are intentionally split because
  `pdf_graphics` is VM-only and `dart_pdf_editor` needs Flutter rasterization.

The Ghent gallery writes the same 2x rasters used for baseline comparison.
The PDF.js gallery writes the same pages as the smoke pass by default (up to
five per file at 1x); override it with `PDFJS_RENDER_MAX_PAGES` and
`PDFJS_RENDER_PIXEL_RATIO` when you need deeper or sharper review. When
`PDFJS_BASELINE_DIR` is set, the Flutter test compares Dart rasters against
the PDF.js baselines using `PDFJS_COMPARE_CHANNEL_TOLERANCE` (default 8) and
`PDFJS_COMPARE_MAX_DIFF_FRACTION` (default 0.0005), and writes
`test_corpora/pdfjs/_renders/index.html` unless `PDFJS_RENDER_OUT` overrides
the output directory. The results page shows each page as one row with the
PDF.js baseline, Dart render, and diff side by side.

## Roadmap context

See README.md. The pipeline through the viewer is done: interpreter, font
engine, Flutter rendering, text selection/search, annotation appearance
rendering, and encryption both ways (RC4/AES-128/AES-256 decryption;
encrypt-on-write re-encrypts changed objects on save — `_encryptedCopy`
in updater.dart; signing encrypted files stays refused). Annotation authoring is in:
`PdfEditor` creates highlights/ink/shapes/free text/notes/stamps with
generated appearance streams (`annotation_editor.dart`) and can flatten
them into page content. AcroForm support is in: `PdfAcroForm`/`PdfFormField`
model (`form.dart`) plus filling with regenerated appearances
(`form_editor.dart` — text/checkbox/radio/choice, auto-size, quadding).
Page manipulation is in (`page_editor.dart`): reorder/move/remove flatten
the page tree (materializing inherited attributes), `appendPagesFrom`
deep-copies pages across documents, `extractPages` splits into a fresh
file via `CosDocumentBuilder` (pdf_cos's from-scratch writer).
Digital signatures are in: `PdfSignature.of(doc)` + `validate()`
(`signature.dart`; CMS/X.509/RSA/ECDSA primitives live in
`pdf_cos/src/crypto/` — asn1, rsa, ecdsa, cms) and `PdfEditor.saveSigned`
(`signature_editor.dart`, adbe.pkcs7.detached with ByteRange patching).
Test signer identity in
`pdf_test_fixtures/src/signer_identity.dart`.
Content editing is in: `PdfEditor.stampPage` (text/shapes/JPEG via
`PdfStamp`), `PdfPageElements.of` + `PdfEditor.deleteElements` (element
enumeration with approximate bounds, stream rewriting), and
`PdfEditor.replaceText` (simple fonts only) — all in
`content_editor.dart`/`content_elements.dart`; the content-stream
tokenizer (`ContentStreamParser`) now lives in pdf_cos.
The roadmap is complete. Polish landed since: LZW/RunLength filters, xref recovery
(`CosDocument.open` falls back to scanning for `N G obj` when the xref
chain is broken), type 4 PostScript calculator functions, /Count-based
page lookup with full-walk fallback, gradient /Extend semantics, JPEG
/Decode + color-key masks, and /Rotate folded into `PdfPageGeometry`
(selection, highlights, overlays, and hit-testing are rotation-aware;
the geometry mirrors the renderer's canvas transform).
The big-gap batch landed next, all KAT-validated against reference
codecs: encrypt-on-write (updater `_encryptedCopy`; signing encrypted
files still refused), trust-store chain validation
(`verifyCertificateChain` in pdf_cos cms.dart, `PdfTrustStore` +
`validate(trustStore:)` in pdf_document), mesh shadings 4-7
(`PdfMeshParser`/`PdfMesh`, device `fillMesh`, drawVertices in
dart_pdf_editor), CCITT G3/G4 (`CcittDecoder`, KAT vs libtiff), JBIG2
embedded profile (`Jbig2Decoder` + shared `MqDecoder` in
filters/mq.dart, KAT vs jbig2enc/jbig2dec), JPEG 2000 (`JpxDecoder`,
lossless bit-perfect vs OpenJPEG, lossy ±1), deep-zoom detail patch
(`PdfPageView` renders the visible slice past the raster caps;
`rasterizeRegion`), and real ICC (`IccProfile` in pdf_graphics —
gray TRC, matrix/TRC, mft1/mft2/mAB LUTs, validated vs littleCMS;
wired into sc/scn and image decoding). Remaining gaps:
RSASSA-PSS, JPX subsampling + PCRL/CPRL, rendering intents/BPC in ICC.
The editing UI is in (dart_pdf_editor `src/editing/`): `PdfEditingController`
owns the edit session — every edit is an incremental save, so revisions
are byte prefixes of one buffer and undo/redo is a stack of lengths;
`PdfViewer(editing:)` injects per-page tool overlays (markup/ink/shapes/
free text/note/stamp; select + move + resize via
`PdfEditor.resizeAnnotation`, which rewrites /Rect and scales the point
arrays — appearances regenerate for shapes/free text, stretch per
§12.5.5 otherwise; see the batch-3 session-1 block), binds undo/redo/delete/escape
shortcuts, and preserves the viewport across same-geometry document
swaps. `PdfEditingToolbar` is the stock chrome. The host must rebuild
the viewer with `editing.document` whenever the controller notifies
(asserted in debug builds); the example app shows the wiring.
On top of that: style controls (controller carries strokeWidth/opacity/
fontSize; the toolbar's tune button opens a slider popup), an
annotation sidebar (`PdfAnnotationSidebar` — lists by page, tap selects
via `selectAnnotation(page, slot)`, trailing delete), and a content
tool (`PdfEditTool.content`: taps hit-test `PdfPageElements` — cached
per revision in the controller — orange selection chrome; delete via
`deleteElements`, text rewrite via `replaceText`; element ids die with
every revision, so any edit clears the element selection).
Page management UI: `PdfThumbnailSidebar` (editing_thumbnails.dart) —
display-list thumbnails (`renderPicture` replayed scaled, no
rasterization), tap to jump, long-press drag to reorder
(ReorderableListView `onReorderItem` — already index-adjusted), footer
delete; `controller.movePage`/`removePage` clear the slot-based
annotation selection first because page indices shift under it, and
`removePage` is a no-op on the last page. Reorder drag: immediate for
mouse pointers, long-press for touch (custom listener picking the
recognizer per pointer kind). The strip shows a viewport indicator fed
by `PdfViewerController.visiblePageRegion(page)` (fractions 0–1) and
repainted via `viewportChanges` (a separate Listenable so scrolling
doesn't spam controller listeners). `PdfViewer.initialFit` defaults to
`PdfViewerFit.page` (whole first page visible, Chrome-style) — widget
tests that do view-coordinate math pin `initialFit: PdfViewerFit.width`.
Color + stylus round: `PdfColorPicker`/`showPdfColorPicker`
(editing_color_picker.dart — HSV area, hue slider, hex field; opaque
colors only, opacity stays a controller property) and an eyedropper:
`controller.startColorPick()` arms it, the page overlay's next tap
samples via `PdfPageRenderer.sampleColor` (3×3-point patch through
`rasterizeRegion`+`toByteData`; view→raster is position/geometry.scale)
and calls `finishColorPick` (forced opaque). The overlay is injected
when `tool != null || isPickingColor`, so `_tool` is nullable there;
Escape cancels picking first. Apple Pencil: ink strokes carry per-point
normalized pressure (raw `Listener` feeds `_pointerPressure`, since pan
callbacks drop it; null when pressureMax == pressureMin, i.e. finger/
mouse — uniform width). `addInk(pressures:)` writes one stroked segment
per point pair at `pdfInkStrokeWidth(base, p)` = base×(0.4+1.2p) (round
caps hide seams; InkList stays the centerline; rect pads by the widest
point). Palm rejection: first stylus down with ink armed flips
`controller.fingerDrawsInk` false → GestureDetector `supportedDevices`
excludes touch, so fingers scroll under the overlay (toolbar touch_app
button toggles back). Test gotchas: TestGesture can't set pressure —
dispatch raw PointerDown/Move/Up via tester.binding.handlePointerEvent
(supply delta); the eyedropper's toImage needs `tester.runAsync` after
the tap (poll isPickingColor with real delays).
Eyedropper preview (from Ben's feedback): `PdfPageColorSampler`
(renderer.dart) rasterizes a page once (1px/pt) and answers `colorAt`
lookups from the cached ByteData — per-event re-rendering would be far
too slow; `sampleColor` is now the one-shot wrapper. The overlay keys
the sampler on document identity, previews on hover (mouse) and
down/move (touch/pencil) via a floating swatch+hex chip
(`_EyedropperChip`, cleared on MouseRegion exit), and commits from the
raw pointer-up (so tap and press-drag-release both pick; the tap
handler no-ops while picking). dart:typed_data must be imported
explicitly for ByteData (flutter/painting doesn't re-export it).
Persisted UI preferences (Ben: save them locally, default behavior):
`PdfEditingPreferences` (editing_preferences.dart, backed by
shared_preferences, keys `dart_pdf_editor.editing.*`) — color/strokeWidth/
fontSize/opacity/fingerDrawsInk plus host-chrome flags
showThumbnailSidebar/showAnnotationSidebar. The controller's style
state proxies to it (no duplicate fields; `preferences.addListener(
notifyListeners)` in the ctor, removed in dispose); each controller
creates its own instance by default, the example app shares one
(`preferences:` param) so panels persist too. Loading is async
(`ready`); when storage is missing (widget tests) getInstance throws,
it's swallowed, defaults stand, writes no-op — so plain tests stay
deterministic with zero mocking. A setter call during the in-flight
load wins over stored data (`_modified` guard). Persistence tests use
`SharedPreferences.setMockInitialValues` + `pumpEventQueue()` before
reading back (writes are unawaited).
Signature tool (editing_signature.dart): `PdfInkSignature` stores
strokes normalized 0–1 (y-down) + aspect + RGB color + optional
pressures, JSON-encoded into preferences (`signature` slot).
`PdfEditTool.signature` is tap-driven: `placeSignature(page, x, y,
width: 160)` maps normalized→page space (y-flip), clamps center so the
whole thing stays in the crop box, strokeWidth = w/75, commits via
addInk (so pressure-variable width and select/move/resize come free).
Toolbar history_edu button opens `showPdfSignatureDialog` first when
no signature is saved, then arms; restart_alt redraws while armed. Pad
key: ValueKey('pdf-signature-pad'). Test gotcha: scrollUntilVisible
needs `scrollable:` scoped to the toolbar once a viewer is in the tree
(two Scrollables otherwise). Example app: ⌘F/Ctrl+F focuses search via
CallbackShortcuts wrapping the Scaffold (shortcuts bubble up the focus
tree from the viewer's focus node).
Custom stamps (editing_stamps.dart, Ben's ask): `PdfCustomStamp`
(caption + RGB color, JSON) — saved list persists via preferences
`customStamps` (a string-list key, one JSON blob per stamp).
`controller.activeStamp` is transient (each session starts in the
classic type-the-caption flow); with one set, a stamp-tool tap calls
`placeStamp(page, x, y, height: 40)` — width mirrors addStamp's
appearance math (measureHelvetica bold + 24pt padding) so the caption
isn't shrunk, center-clamped to the crop box like placeSignature.
Drag-out still works and uses the active stamp's text/color; with no
active stamp it prompts as before. Toolbar: a `style` icon button
('Custom stamps…') appears while the stamp tool is armed →
`showPdfStampPicker` (tap to select, trailing delete, 'New stamp…' →
`showPdfStampEditor`, text field key 'pdf-stamp-text'; the 'Type the
text for each stamp' tile clears activeStamp). Deleting the active
stamp also clears it.
Live drag preview (Ben's ask): moving/resizing a selected annotation
shows its real appearance at the dragged rect, Acrobat-style — the
original stays rendered, a ~75% ghost rides the drag.
`PdfInterpreter.drawAnnotation(page, annotation)` (single-annotation
slice of drawAnnotations) + `PdfPageRenderer.renderAnnotationPicture`
(appearance alone, page raster space, transparent bg, null without an
/AP). The overlay caches the picture per (document, page, slot) —
`_ensureGhost()` from build, so it's ready before the drag — and the
painter calls `paintAnnotationDragPreview` (public in
editing_overlay.dart, @visibleForTesting): saveLayer 0xBF alpha,
translate/scale from the resting view rect onto the preview rect (the
same §12.5.5 stretch resizeAnnotation commits). Tests in
editing_drag_preview_test.dart; the mid-drag pixel check captures a
RepaintBoundary via tester.runAsync(toImage) while the gesture is held.
Annotation rotation: `PdfEditor.rotateAnnotation(page, annot, degrees)`
(annotation_editor.dart) — degrees CCW about the rect center; bakes the
current BBox→Rect fit into the appearance /Matrix (no shear when BBox
aspect ≠ Rect), concats the rotation, then sets /Rect to the BBox
corners' bounds under the *new* matrix (the matrix carries the whole
rotation history, so 45°+45° lands exactly where 90° does — never
compute the rect from the old rect's dims). Point arrays
(QuadPoints/InkList/L/Vertices/CL) rotate jointly via _mapPointPairs.
UI: rotate knob 22px above the selection's top-center
(editing_overlay.dart; resize handles win the overlap), drag sweeps
about the center with 45°-multiple snap (±3°), ghost + chrome spin live
(paintAnnotationDragPreview takes `rotation`), commit flips sign —
view clockwise = page −CCW: `rotateSelected(-delta*180/pi)`.
`canRotateSelected` = resizable subtype + has /AP. Tests:
annotation_editor_test.dart (matrix/rect/ink math, 45+45≡90),
editing_rotate_test.dart (pixels + handle-drag sign chain).
Annotation list round (zoom-to, multi-select delete, authors):
`PdfViewerController.showRect(page, rect)` frames a page rect —
`_showRect` centers it and zooms to ~40% viewport fill, clamped
[1, maxZoom] (never zooms out); the transform translation is solved
against the clamped scroll offset, and both clamp at document edges,
so near-margin rects sit off-center (tests frame mid-page rects).
Sidebar (now stateful): tap zooms + selects; long-press enters
multi-select (checkboxes, header 'N selected' + delete) committed via
`controller.deleteAnnotations(slots)` — annotations are all resolved
before the first removal (slots shift), one apply = one undo, clears
the annotation selection; checked state dies with every revision
(document-identity check in build). `PdfAnnotation.author` reads /T
(ignored for Widgets, where /T is the field name);
`controller.author` (persisted preference `author`) stamps /T on all
ten creation paths and is preserved across setSelectedText's
remove+re-add. Tile subtitle is 'author — contents'. Example app:
person_outline AppBar button prompts for the name. Tests:
editing_sidebar_test.dart.
Ink smoothing (Ben: "curves looked chunked"): points are sampled once
per frame, so fast strokes left long straight `l` segments.
`pdfInkCurveControls(points)` (annotation_editor.dart, exported beside
pdfInkStrokeWidth) converts a polyline to Catmull-Rom cubic controls —
c1 = pᵢ + (pᵢ₊₁−pᵢ₋₁)/6, c2 = pᵢ₊₁ − (pᵢ₊₂−pᵢ)/6, neighbors clamped at
the ends; two points degenerate to a straight chord. `addInk` writes
`c` ops (per-pair moveTo+curveTo for pressured strokes), and the rect
bounds include the control points (a spline can overshoot its samples;
the Bézier hull makes the pad rigorous — covered by the "spline
overshoot" test). The same helper drives the live previews so drawn ==
committed: overlay `_EditingPreviewPainter` (cubicTo; controls computed
in page space then mapped — affine, order irrelevant) and the signature
pad painter. /InkList still stores the raw samples per spec.
Scrollbars (Ben: "very hard to see"): the implicit desktop bar lived
inside the InteractiveViewer (thin, scaled away when zoomed) — now
suppressed via ScrollConfiguration(scrollbars: false). `_PdfScrollbar`
(pdf_viewer.dart, axis-generic) paints outside the transform in the
canvas Stack: light thumb + dark outline (reads on dark canvas and
white pages), faint track scrim, hover/drag widens 8→10px, min thumb
36px, DragStartBehavior.down, track tap/track-grab jumps then drags.
Vertical position = scroll.pixels − t_y/s (the transform unprojection);
motion goes through `_scrollbarScrollBy`, which spills what the scroll
extents can't absorb into the zoom window (trackpad-style) so the ends
stay reachable zoomed. Hidden while range ≤ pageSpacing (the list's
bottom padding is nominal slack). Horizontal bar appears only zoomed
(sideways overflow lives in the transform; `_scrollbarPanBy` pans
m[12]), inset right by hitExtent(14) so corners don't collide; needs
`viewExtent: _viewWidth` since its own track is inset. Thumb keys:
'pdf-scrollbar-thumb' / 'pdf-hscrollbar-thumb'. Test gotchas
(pdf_scrollbar_test.dart): lazy-ListView maxScrollExtent is an
estimate that drifts as items build (tolerances, not exact math);
tester.drag eats touch slop (use startGesture+moveBy); touch taps on
the bar resolve only after the viewer's double-tap timeout (pump
400ms); end drag tests with a 300ms pump for the scroll-settle timer.
Dark mode: all chrome follows the ambient Material theme. The viewer
canvas is theme-aware — `PdfViewer.backgroundColor` overrides; default
is 0xFF404347 (light themes, the historical slate) or 0xFF202124
(dark), resolved in build before the LayoutBuilder. Swatch/preview
borders that were Colors.black26 (toolbar palette, signature pad +
inks, stamp inks, color-picker preview, eyedropper chip) now use
colorScheme.outline so they read on dark surfaces; pads/pages stay
paper-white on purpose. `PdfEditingPreferences.themeMode` (ThemeMode,
key `themeMode`, stored by name) is a persisted host-chrome pref; the
example app's MaterialApp listens to the prefs for themeMode (ViewerApp
is now stateful and owns the prefs instance, passing it to
ViewerScreen) with an AppBar button cycling system→light→dark. Test
gotcha (dark_mode_test.dart): re-pumping MaterialApp with a new theme
animates via AnimatedTheme — a single pump still reads the old
brightness, so assert light and dark in separate tests.
Page color (Ben: "instead of a white page it must be blue or green or
another arbitrary colour"): the paper is just the fill renderPicture
paints under the content, so `PdfPageRenderer.renderPicture/renderImage/
sampleColor/PdfPageColorSampler.of` take `pageColor` (default white) and
`PdfViewer.pageColor` threads it through _PdfViewerPage → PdfPageView
(placeholder ColoredBox matches; didUpdateWidget drops the cached
picture on color change) and into EditingPageOverlay so the eyedropper
raster matches what's on screen (sampler keyed on document AND color).
`PdfThumbnailSidebar.pageColor` does the same for thumbnails. Display
setting only — the document is untouched. Persisted as
`PdfEditingPreferences.pageColor` (int key `pageColor`); the example app
has a format_color_fill AppBar button → showPdfColorPicker, wiring the
pref into both the viewer and the thumbnail strip. Test gotcha
(page_color_test.dart): page renders complete without runAsync in
widget tests — placeholders are already replaced after a pump, so
assert on the RawImage/RepaintBoundary pixels (poll with runAsync
delays), not on placeholder ColoredBoxes.
In-place text (Ben: write in place, edit after creation, font + size):
`PdfStandardFont` (pdf_cos-free, content_writer.dart) — Helv/TiRo/Cour
resource names, BaseFont, per-font ascent, AFM widths (new
`timesRomanWidths`; Courier is flat 600), `measureStandardText`, and a
lenient `fromName` (Times*/serif→times, Cour*/mono→courier, else
helvetica). `addFreeText(font:)` threads it through wrap, baseline,
/DA, and the resource dict (`_standardFont`/`_fontResource` generalize
the old `_helvetica`, which stays for bold stamps). Controller:
`fontFamily` (persisted pref key `fontFamily`, stored by enum name),
`selectedTextStyle` (/DA parse `/(\S+) (\d+) Tf`),
`restyleSelectedText(font:,size:)`; it and `setSelectedText` share
`_rewriteSelected` (remove+re-add, re-selects the last /Annots slot so
consecutive restyles stay anchored). `isEditingText`/`setEditingText`
gate the viewer: CallbackShortcuts binds {} and the pointer-down
focus-steal is skipped while typing — otherwise backspace deletes the
selected annotation and any click closes the editor. Overlay: a
free-text drag-out or a tap on the already-selected FreeText opens an
inline TextField (key 'pdf-freetext-editor') over the view rect,
styled fontSize×scale, height 1.2, family mapped like canvas_device's
substitution (Helvetica/Times New Roman/Courier); outside tap, drag,
or tool switch commits, Escape cancels via the editor's own
CallbackShortcuts (nearer to the focus, so it wins); editing existing
text washes pageColor at 0.92 alpha over the old rendering. Toolbar
`_StyleMenu` (now stateful): Sans/Serif/Mono SegmentedButton + the
size slider show the selected free text's style and restyle it on
change end (one revision per slider gesture, `_draggingFontSize`
carries the thumb meanwhile); tooltip renamed 'Stroke, opacity,
font'. Test gotchas (editing_text_edit_test.dart): tap targets must
stay inside the 800×600 test viewport — view(500,300) is y≈643px, the
tap silently misses; the SharedPreferences mock store is
process-global, so widget tests call setMockInitialValues({}) before
creating controllers or a prior test's stored fontFamily leaks in
through the async preference load.
Gesture/navigation fixes (session 3 of batch 2): trackpad gestures
latch an intent per gesture (`_TrackpadIntent` in pdf_viewer.dart) —
macOS reports finger drift as pan deltas during a magnify gesture, so
the first signal past its threshold (|scale−1| > 0.01 → zoom, 8px
accumulated pan → scroll) claims the whole gesture; pre-latch motion
is paid back in one piece when scroll latches, and pinch lift-offs
never fling. Horizontal momentum: `_panFlinger` (unbounded
AnimationController + FrictionSimulation 0.0000135, InteractiveViewer's
drag) continues the zoom window's x-translation after lift-off,
clamped at the edges; stopped on pointer down, wheel, and new trackpad
gestures (State is now TickerProviderStateMixin — two tickers). Jump
accuracy: the ListView gets `itemExtentBuilder` (exact per-page
extents, so scroll extents/offsets never drift from estimates on long
mixed-size docs — `buildVariedHeightPdf` in pdf_test_fixtures cycles
792/396/1008pt pages to defeat uniform estimates), and `_jumpToPage` /
`_scrollToDestination` / `_showMatch` add `_zoomWindowDy` (= t_y/s):
zoomed in, the screen sees list space through (p − t)/s, so targets
shift by t_y/s — _showMatch also scales its viewport-third to
viewH/(3s). Test gotchas (pdf_viewer_test.dart): panZoomUpdate's `pan`
is cumulative, not a delta; widget tests can't reproduce the lazy-list
estimate drift (animateTo lays pages out continuously, so the
zoomed-search test is the regression gate for jump accuracy — it
fails by t_y/s ≈ 240px un-fixed).
Multi-platform example (Ben: "make sure the example runs on all
platforms"): the example app has shells for all six platforms (ios/
android/web/windows/linux generated with --org dev.milanko alongside
the original macos). main.dart is dart:io-free: open uses XFile
(readAsBytes + file.name), the type filter carries extensions +
mimeTypes + uniformTypeIdentifiers (each platform throws without its
field), and _saveAs branches — desktop getSaveLocation+saveTo, web
XFile.fromData(...).saveTo (browser download), mobile share_plus
(ShareParams files+fileNameOverrides+sharePositionOrigin; the origin
rect is required on iPad). Demo overlays pin to slots via _slot
(FittedBox + SizedBox at PDF-point design size) so they scale with the
page — the counter Row overflowed its slot at fit-page scale. Verified
builds: web, macOS, debug APK, iOS simulator. Example test gotchas:
the example's tests derive the page rect from the viewer's fit-page
math (viewer rect → zoom = h/(w·aspect), centered) instead of assuming
fit-width; toolbar taps need scrollUntilVisible scoped to the
toolbar's Scrollable (the row overflows 800px); dialog-dismiss asserts
need two pumps (one starts the route pop, one finishes it); tests seed
SharedPreferences.setMockInitialValues({}) since the mock store is
process-global.
Selection model overhaul (session 1 of batch 2): the controller's
selection is an ordered slot list (`_selected`, last = primary;
`selectedAnnotationSlots` / `hasAnnotationSelection` /
`isAnnotationSelected` / `annotationAt(page, slot)`); pages are cached
per revision (`_page()` / `_pageCache`, cleared in
`_invalidateElements`) because `PdfDocument.page()` re-walks the tree
and re-parses /Annots on every call and selection hit tests run per
pointer event. `selectAnnotationAt(toggle:)` is shift/⌘/ctrl-click
(toggle miss leaves the selection alone), `selectAnnotationsIn` is the
marquee (rect-intersect), `selectAllAnnotationsOn` is ⌘A;
`moveSelected`/`deleteSelected` act on the whole selection in one
apply (single undo); resize/rotate/text-edit/restyle gates demand
exactly one selected; `deleteAnnotation` remaps surviving same-page
slots past the removed index (slot−1) so the selection follows the
annotation. Overlay: `_selectMode` = select tool armed OR a tool-null
selection — the viewer mounts the overlay for `hasAnnotationSelection`
too, which is how default-mode mouse selection gets move/resize/
marquee; empty-area drags marquee for mouse-like kinds
(DragStartDetails.kind, null treated as mouse) and pan the viewer for
touch via `onPanViewport` (viewer `_grabPanBy` = negated
`_scrollbarScrollBy`/`_scrollbarPanBy`, list-space deltas); dragging
an unselected annotation selects it and moves it in the same gesture;
the ghost rides only single selections (multi moves as chrome boxes —
painter `extraSelectionRects` + `marqueeRect`). Viewer: a default-mode
mouse tap selects annotations (`_lastPointerKind` from the raw
pointer-down — tap details carry no device kind; touch taps stay
reader gestures), mouse drags from empty/textless space grab-pan
(`_grabPanning` in the selection pan handlers, grab/grabbing cursors;
hover shows `click` over selectable annotations and links, `text`
over text), ⌘A/Ctrl+A → `_onSelectAll` (all annotations on the
current page when the select tool or a selection is live, else the
page's whole text). Test gotchas (editing_multiselect_test.dart,
pdf_viewer_test.dart): MouseRegion.onHover doesn't fire for
addPointer — moveTo somewhere first or the cursor assert reads the
initial value; tapAt(kind: PointerDeviceKind.mouse) resolves without
the 350ms double-tap wait (that recognizer is touch/stylus-only); the
hover-test "empty area" points must sit inside the 800×600 viewport.
Annotation interaction polish (session 2 of batch 2): four features.
(1) Rotated selection chrome: `PdfAnnotation.appearanceQuad`
(annotation.dart) — BBox corners through the form /Matrix then the
§12.5.5 fit onto /Rect, page space, BBox order (ll lr ur ul); equals
the rect corners for unrotated appearances. The overlay derives
`_selectionChrome` = (base rect from quad edge lengths about the quad
center, resting angle = view direction of the ll→lr edge,
canvas.rotate convention) and the painter's `rotation` is now
resting + drag delta (the ghost gets `ghostRotation` = delta only —
its appearance already carries the resting rotation; `ghostTo` split
from `selectionRect` for the same reason). Rotate-drag snap is on the
TOTAL angle (`_rotateResting` captured at drag start), so rotated
annotations snap back to square; the knob hit-test rotates its
position (`_rotatePoint`). Resize handles are suppressed when resting
≠ 0 (a /Rect resize would shear rotated artwork).
(2) Post-edit flash fix: `PdfPageView.onRasterReady` fires when a
full-page raster for the current page object lands; `_PdfViewerPage`
(now stateful) tracks `_rastered` (false from every page-identity
swap) and hands the overlay `rasterCurrent`. On commit the overlay
captures an afterimage — `_commitWithGhost` (move/resize/rotate: takes
ownership of the ghost picture, paints it at the committed rect via
paintAnnotationDragPreview at opacity 1), `_afterShape` (rect/ellipse
drag preview), `_afterText` (a Positioned Text mirroring the inline
editor, pageColor-washed for existing-text edits), `_afterSignature`,
and controller-side `committedInkOn(page)` (finishInk runs on a timer,
so the controller keeps the strokes + the committing revision) — and
keeps painting it until rasterCurrent goes true or the document moves
past `_afterDocument`. Painter: `extraInk` (List of stroke sets with
own color/width — committed ink + signature previews), `afterGhost`,
`afterShape`; `_paintInk` is the factored stroke painter.
(3) Ink auto-commit: `inkCommitDelay` (default 800ms, null = manual)
— addInkStroke (re)arms a Timer firing finishInk; `beginInkStroke()`
(called from the overlay's ink pan-start) holds it mid-stroke so slow
drawings don't split. Toolbar check/discard buttons only show in
manual mode (`inkAutoCommits`). finishInk/discardInk/dispose cancel.
(4) Signature preview: `signaturePlacement(page, x, y)` exposes
placeSignature's layout (page-space strokes, pressures, color, width);
the overlay previews it at 0.55 alpha riding hover (mouse) or a
press-drag (`_signatureDrag`, release places at the last position —
taps still place as before). Test gotchas (editing_polish_test.dart):
don't pixel-sample a selection edge midpoint (the white resize handle
sits there); after undo the OLD raster legitimately still shows the
undone edit (PdfPageView keeps the previous image until re-render) so
assert the afterimage source (committedInkOn == null), not pixels; any
touch gesture on the viewer leaves the double-tap recognizer's 40ms
timer — end such tests with pump(400ms); an Ink annotation's rect hugs
the strokes (pen-width padded), not the placement box.
Sidebar round (session 4 of batch 2): four features. (1) Thumbnail
performance: `controller.apply` takes `pages:` (the page indices an
edit changes visually; null = unknown = all) — every internal call
site names its pages, structural ops (movePage/removePage/flatten)
and host edits leave null. `pageRenderStamp(page)` =
`_renderStampEpoch + _renderStamps[page]` (per-revision page sets in
`_revisionPages`, bumped on apply/undo/redo of exactly the touched
pages). `pageAt(index)` is the public per-revision page cache (use it
anywhere UI reads pages per frame — sidebars now do). The strip
rasterizes tiles via `PdfPageRenderer.renderImage` into a per-sidebar
LRU (`_ThumbnailCache`, 96 entries, hands out `ui.Image.clone()`s so
eviction can't pull pixels from a painting tile; key =
page|stamp|color|pxWidth with 64px width buckets), renders serialized
through a future chain on the cache (one page at a time, PER PANEL —
a static chain strands continuations in a dead async zone once an
earlier zone, e.g. a previous widget test's FakeAsync, completed the
tail; every task try/catches everything so one failing page can't
poison the chain), and only per-tile ListenableBuilders watch
viewer/viewport changes — the outer list rebuilds on controller
notifies alone. Stamps restart at 0 per controller, so a session swap
(opening another document) must drop cached state: the sidebar clears
the cache and each tile resets its imageKey in didUpdateWidget on
controller identity change — without that the new document shows the
old one's thumbnails (keys collide).
`PdfThumbnailSidebar.debugRasterizations` counts real renders for
tests. (2) Resizable panels: both sidebars take `side` (which side of
the viewer they're docked on, `PdfSidebarSide` in editing_panel.dart),
`resizable`, `minWidth`/`maxWidth`; `PdfSidebarResizeGrip` (8px hit
strip, hairline that thickens on hover/drag) reports deltas already
signed toward growth; widths persist as preferences
`thumbnailSidebarWidth`/`annotationSidebarWidth` (null until first
dragged — the widget's `width` param is just the default). Grip keys:
'pdf-thumbnail-resize-grip'/'pdf-annotation-resize-grip'. (3) Follow
the viewer: the strip keeps per-slot GlobalKeys; on currentPage change
it `Scrollable.ensureVisible`s a built tile (keepVisibleAtEnd then
keepVisibleAtStart = minimal scroll), or jumps to an estimated offset
(aspect math mirroring tile layout: 12px side pad, 1px border, 4px
vert pad, 28px footer) and fine-tunes post-frame once built.
(4) Zoom-to flash: `controller.flashAnnotation(page, slot)` →
`pendingFlash` (`(page, slot, sequence)`; dies with any revision via
document-identity check); the sidebar tap calls it after
showRect+select; the overlay (now SingleTickerProviderStateMixin)
runs a 1100ms pulse — amber (0xFFFFB300) ring closing onto the rect
while fading — and calls `expireFlash(sequence)` on completion
(cancels the 1600ms `flashLifetime` backstop Timer, which only
matters when no overlay ever runs the pulse); the viewer mounts the
overlay for `pendingFlash != null` too (links/widgets flash without a
selection). Test gotchas (editing_panels_test.dart): thumbnails are
RawImages now (page_color's wait condition polls RawImage, not
CustomPaint); resize-grip drags eat pointer slop even for mouse kind —
assert greaterThan + prefs equals rendered width, not exact pixels;
tile-tap tests must pump the pulse out (pumpAndSettle, or pump ~2s) or
the backstop timer trips `!timersPending` — that invariant check runs
BEFORE addTearDown(dispose); never `await viewer.jumpToPage` in a
widget test (fake-async deadlock — fire it unawaited and pump); a
queue yield via Future.delayed(zero) leaves stray fake timers, so the
thumbnail render queue serializes on the rasterize awaits alone; never
chain async work through a STATIC Future in widget-tested code — each
test's FakeAsync zone dies with the test and the chain dies with it.
Viewport indicator contrast (Ben: "I still don't see the viewport
preview"): the strip's viewport mark painted in colorScheme.primary —
in a dark M3 theme that's light lavender over the (white) thumbnail,
~1.7:1, invisible; the feature predates dark mode and was only ever
seen against light-theme primary. The mark paints over the PAPER, not
the app surface, so _PageTile now picks whichever of primary/
inversePrimary has the higher WCAG contrast against pageColor (works
for recolored paper too). Contrast tests live in
editing_panels_test.dart (read the private painter's color via a
dynamic cast; light and dark asserted in separate tests per the
AnimatedTheme gotcha).
Viewer-state clobber (the REAL cause of Ben's invisible indicator —
contrast was secondary): PdfViewerController delegates through a
`_state` pointer set in the viewer's initState and cleared in dispose.
When a host recreates the viewer ELEMENT — the example's keyless Row
gained panels on BOTH sides when the async preference load completed,
so updateChildren mismatches at both ends and re-inflates the keyless
middle — the new state attaches in initState, then the OLD state's
deferred dispose (tree finalization) nulled `_state` again. Every
controller round-trip (visiblePageRegion, jumpToPage, showRect,
search) silently no-ops from then on; values the state PUSHES into
the controller (currentPage, pageCount) keep working, which masks it.
Fix: dispose only detaches `if (identical(_controller._state, this))`;
the example also keys the Row children (panel toggles now preserve the
viewer element and the reading position). Regression test: "controller
survives the host recreating the viewer element" (pdf_viewer_test).
Widget tests can't catch this class of bug when they mount the final
layout in one pump — the live-app tells were tile taps not navigating
and dragging the viewer's scrollbar (cliclick + screencapture against
the running macOS app made it falsifiable). Related cosmetic fix found
the same way: _PageTile's border was DecoratedBox, whose child is NOT
inset, so the full-bleed RawImage covered the 1-2px ring (current-page
outline included) — it's a Container now (decoration padding insets
the child; the strip's width math already assumed width-26).
Theming round (session 5 of batch 2): `PdfViewerTheme`/
`PdfViewerThemeData` (theme.dart, exported) — an InheritedWidget; every
field nullable, null = stock look, widget params (backgroundColor) win
over the theme. Fields: canvasColor, selectionColor, searchMatchColor,
currentSearchMatchColor, annotationChromeColor (selection boxes/
handles/marquee + the inline text editor's border), elementChromeColor,
flashColor, and scrollbar (`PdfScrollbarThemeData`: thumb/thumbActive/
outline/track/trackActive). _HighlightPainter and
_EditingPreviewPainter take `theme` (chrome statics became getters with
fallbacks; translucent fills derive via withAlpha(0x1A)/(0x14) so a
custom chrome recolors them too) — both compare it in shouldRepaint.
The viewer's `_PdfScrollbar` moved to scrollbar.dart as a public
`PdfScrollbar`: transform now optional (plain mode = scale 1, offset =
scroll.pixels), onScrollBy optional (null drives the ScrollController
directly, clamped), `thumbKey` for tests. Both sidebars suppress the
implicit desktop bar (ScrollConfiguration scrollbars:false) and mount
it over their lists — thumb keys 'pdf-thumbnail-scrollbar-thumb' /
'pdf-annotation-scrollbar-thumb', inset by PdfSidebarResizeGrip.width
when the grip rides the same right edge. The annotation list gained a
ScrollController, which surfaced a crash class: toggling multi-select
used to swap `list` ↔ `Column(header, Expanded(list))`, re-inflating
the ListView — old + new positions both attached for a frame and
`controller.position` asserts. Fix shape is the session-4 lesson again:
one tree shape always (Column with the header conditional and the
Expanded keyed) AND the scrollbar treats `positions.length != 1` as
"no metrics" instead of touching `.position`. Tests:
pdf_theme_test.dart (theme plumbing via dynamic painter casts, thumb
decoration colors, sidebar bar presence/drag — mouse-kind
startGesture+moveBy, since tester.drag eats slop).
Color formats (session 6 of batch 2): `PdfColorFormat` {hex, rgb, hsl,
cmyk} (carries its display `label`), exported from
editing_color_picker.dart. The picker's value row switches via a
compact PopupMenuButton (key 'pdf-color-format'); hex stays the
default and its field is unchanged — the legacy picker test finds
exactly one TextField and taps 260-wide-layout offsets, so neither
the default nor the picker width may change. Channel modes show dense
centered fields (keys 'pdf-color-channel-N', labels below, maxLength
from the channel max, ZERO horizontal contentPadding — four CMYK
fields share ~130px and a centered '100' clips with any side padding;
found in the real app, not in tests). One model (`_hsv`): SV/hue
drags and format switches rewrite the visible fields (`_syncFields`);
a channel edit parses the entire visible row (the other fields
already hold their values) and never rewrites it, so typing isn't
clobbered — unparsable/emptied input no-ops, values clamp to
[0, max]. HSL via HSLColor; CMYK is the naive device conversion
(k = 1−max(r,g,b), no color management — entry/display only, stated
in the dartdoc). Format persistence: the picker is preferences-free
(`initialFormat` + `onFormatChanged` params on it and
showPdfColorPicker); `PdfEditingPreferences.colorPickerFormat` (key
`colorPickerFormat`, stored by name) is wired by the toolbar's 'More
colors…' and the example's page-color button — preferences imports
the enum from the picker, never the reverse. Tests: editing_test.dart
(per-format round-trips incl. CMYK 100/0/0/0→cyan, drag rewrites the
fields, empty-field no-op) and the preferences round-trip; verified
live on macOS incl. format persistence across an app restart.
Session 7 (saving + showcase): macOS saving was ALREADY fixed —
a913df0 flipped user-selected.read-only → read-write in both
entitlement profiles; this session verified the whole flow live
(save panel → /tmp write, Replace-overwrite, toast, output parses).
The demo (example/lib/demo_document.dart) is now a 6-page feature
showcase: pages 1-2 unchanged (demo_test.dart taps page-1 buttons at
fixed PDF coords and the GoTo lands on page 2 — don't move them);
page 1 gained a TOC of /Fit GoTo links (placeholders @PGn@ patched
after object numbering). Page 3 graphics (dash/join rows, even-odd
star, Bézier heart, /ShAx stitched type-3-function axial + /ShRad
radial via `sh`, Multiply circles, ca alpha row, CMYK `k` + gray `g`
swatches), page 4 typography (7 standard fonts, Tr 0/1/2 — Tr 7 text
clip is NOT implemented, don't demo it; Tc/Tw/Tz/Ts each reset inline
since text state persists across BT/ET), page 5 images (hue-wheel RGB
XObject as ASCIIHex, color-key /Mask over stripes, 1-bit /ImageMask
smiley ×2, 4×4 inline image), page 6 annotations & forms: the base
file hand-writes field skeletons (text/checkbox with /MK but no /AP —
appearances generate on fill; radio kids NEED hand-written /AP /N
state forms or onStates is empty and setRadioValue throws; combo
needs /Opt + comboFlag 131072) plus /AcroForm /DR /Helv, then
_authorShowcase reopens the bytes and authors 10 annotations + fills
all 4 fields through PdfEditor — the demo is a build-time smoke test
of the authoring pipeline (asserted in demo_document_test.dart).
Inline-image bug found by the showcase: BI..ID..EI synthesizes a
fresh CosStream every interpretation pass, but renderPicture decodes
in a collector pass and paints in a second pass — the identity-keyed
image map never hit, so inline images NEVER rendered. Fix:
PdfImageRequest.isInline (set by _drawInlineImage), pdfImageKey()
in image_decoder.dart returns a value key (PdfInlineImageKey: dict
toString + data bytes) for inline requests, stream identity for
XObjects (the xref cache makes those stable); ImageCollector now
collects requests, decodeImages takes requests and keys by
pdfImageKey, CanvasPdfDevice.images is Map<Object, ui.Image>.
Regression test: dart_pdf_editor/test/inline_image_test.dart. Two Ghent
baselines moved because GWG090's Type 3 bitmap-font row (CharProcs
painting inline images) now renders — re-baselined as an improvement.
Batch 3, session 1 (resize correctness): three fixes sharing one root —
resizeAnnotation's blind §12.5.5 stretch. (1) Shapes + free text now
REGENERATE on resize (`_regenerateResizedAppearance` in
annotation_editor.dart): Square/Circle rebuild from /C (stroke) +
/IC (fill) + /BS /W + opacity, FreeText re-wraps at the /DA font size —
constant stroke width / font size, like desktop editors. Guards fall
back to stretch: /BE (cloudy), /BS /D (dashed), free text whose /DA
font `PdfStandardFont.tryFromName` can't place (embedded fonts — never
silently substitute Helvetica). Opacity reads the appearance's own GS0
/ca (`_appearanceOpacity`), NOT a dict /CA — writing /CA alongside a
baked-in ca would double-apply in conforming viewers.
`_replaceAppearance` swaps the /AP /N stream keeping its object number
and must ALSO `adoptObject` — `replaceObject` only stages, the resolve
cache still returns the old stream within the same apply.
(2) Free-text style now round-trips through the dict
(`PdfAnnotation.freeTextStyle` → `PdfFreeTextStyle`): /C = background
(spec §12.5.6.6; legacy files where /C mirrors the /DA text color parse
as no-background), /DA carries `rg` text + optional `RG` border color,
/BS /W the border width (absent → 0, NOT the spec default 1 — don't
conjure borders). `_rewriteSelected` passes fill/border through (text
edits used to drop the demo's yellow box), `_openTextEditor` reads the
text color from freeTextStyle (annotation.color may now be the
background). New: `interiorColor`/`borderWidth` getters,
`PdfStandardFont.tryFromName`.
(3) Rotated resize: `resizeAnnotationLocal(page, annot, localTo)` —
localTo is the annotation's own unrotated frame; regen types regenerate
at localTo then re-rotate by the quad angle (must rotate a
`PdfAnnotation.fromDict` RE-WRAP: rect is parsed once at construction,
so the freshly-written /Rect is invisible through the stale instance);
stretch types compose T(−c)·R(−θ)·S·R(θ)·T(c′) into the §12.5.5-baked
matrix (`_bakedFormMatrix`/`_bboxBounds`, extracted from
rotateAnnotation) and map point arrays through the same affine. Overlay:
handles show on rotated selections (hit-test + pointer delta unrotate
about the chrome center, `_resizeFrom`/`_resizeAngle`), commit goes
through `controller.resizeSelectedLocal`, and the ghost gets a
`localAngle` path in paintAnnotationDragPreview —
T(toC)·R(λ)·S·R(−λ)·T(−fromC), scaling along the rotated axes (a
page-axis from→to stretch would shear the preview). Test gotchas:
exact-valued mapped coordinates serialize as CosInteger, so resolve
point arrays as num, never cast CosReal; the local-frame drag test
derives handle positions by spinning chrome corners by the resting
angle (view angle = −page angle).
Batch 3, session 2 (selection chrome & text box UX): four features.
(1) Zoom-invariant chrome: the overlay paints inside the
InteractiveViewer transform, so chrome used to scale with zoom. The
viewer owns `_transformScale` (ValueNotifier, set in
_onTransformChanged = matrix getMaxScaleOnAxis — a separate notifier so
overlays don't rebuild on zoomed pan ticks), threaded through
_PdfViewerPage → ValueListenableBuilder → `EditingPageOverlay.zoom`.
The state's `_chromeScale` (= 1/zoom) multiplies hit radii, the knob
distance, `_minSizeView`, and the inline editor's border; the painter's
`chromeScale` multiplies every chrome metric (selection inflate/stroke,
handle size, knob distance/radius, marquee, element box, flash ring).
Layout zoom (≤1) shrinks the page layout, transform identity — chrome
is constant there for free. (2) Rotate-knob connector z-order: the
painter draws the line first, resize handles next, knob circle last
(`rotateKnob` hoisted; box.top − (distance−2)·s keeps the state/painter
positions consistent at any scale). (3) Text-box auto-focus: TextField
autofocus only fires into an unfocused scope, and the creating drag's
pointer-down put primary focus on the viewer's node — _openTextEditor
explicitly requestFocus()es the editor's node post-frame. (4) Text-box
fill/border UI: preferences `textFillColor`/`textBorderColor` (Color?,
remove-key = none), controller proxies + addFreeText passes them with
borderWidth = strokeWidth; `restyleSelectedText` gained record-sentinel
params `(int?,)? fill/border` — `(null,)` clears, omitted keeps the
parsed style (same convention in _rewriteSelected); _StyleMenu (takes
the toolbar `palette` now) shows 'Text fill'/'Text border' swatch rows
(none slash + palette + custom picker; keys 'pdf-text-fill-none',
'pdf-text-fill-N', same for -border) that set defaults and restyle a
selected box (border restyle passes borderWidth: strokeWidth); the
inline editor + _afterText preview the fill (`_textEditFill` replaces
the pageColor wash when set). Tests: editing_chrome_test.dart (painter
chromeScale via dynamic cast, knob drag at the scaled distance, stale
distance no longer hits — compare document identity, NOT isModified
(the setup's addRectangle already set it); pinch then expect
chromeScale ≈ 1/viewer.zoom; knob-line pixel test scans a ±2px column
patch — the 1.5px line lands between pixel columns) and
editing_text_edit_test.dart additions. Gotchas: the style menu is
300px wide with 16px side padding — 86 label + 6 swatches + compact
IconButton needs 1px swatch padding (2px overflowed by 2); a bare
EditingPageOverlay mounts fine in a SizedBox for unit-style overlay
tests (geometry built by hand, textPrompt: showPdfTextPrompt).
Batch 3, session 3 (context menu & z-order): right-click on an
annotation opens a context menu; z-order ops reorder /Annots (later
entries paint on top, §12.5.2). Editor:
`bringAnnotationsToFront`/`sendAnnotationsToBack(pageIndex, annots)`
(annotation_editor.dart) partition the array items by dict identity
(Set.identity — CosDictionary has no value ==) into moved/rest and
reassemble; identical-order result stages nothing. Controller:
`bringSelectedToFront`/`sendSelectedToBack` + `canBring…`/`canSend…`
gates — `_reorderRemap` simulates the same partition on slot indices
(parsed-annotations order == /Annots order restricted to parseable
entries, so the simulation matches the editor exactly); the remap is
applied to `_selected` BEFORE `apply()` because apply's post-save
validation reads the slots against the new document. Whole selection
moves in one apply (one undo), grouped per page, `pages:` named.
Menu API (editing_menu.dart, exported): `showPdfAnnotationMenu`
builds stock entries (front/back/delete, keys
'pdf-annot-menu-front'/'-back'/'-delete'; z-order entries disable via
the can-gates) + host extras from `PdfViewer.annotationMenuBuilder`
(`PdfAnnotationMenuBuilder` → `List<PdfAnnotationMenuItem>`, shown
below a PopupMenuDivider). `PdfAnnotationMenuRequest` snapshots the
selection at open (slots/annotations/primary/controller) and is handed
to every item's `onSelected` — custom items are self-contained.
Viewer: `onSecondaryTapUp` on the main GestureDetector (the overlay's
recognizers only claim primary, so right-click works in every mode
incl. armed tools); the handler selects the hit annotation unless it's
already in the selection (multi-selection survives), tool untouched.
The example adds a conditional 'Copy text' action. Tests:
editing_menu_test.dart (controller remap/undo/gates + widget
right-clicks via `tapAt(kind: mouse, buttons: kSecondaryMouseButton)`)
and annotation_editor_test.dart reorder tests. Gotcha: with every
annotation on a page selected, ANY reorder is the identity — both
menu entries disable; multi-select menu tests need a third,
unselected annotation for the action to do anything.
Batch 3, session 4 (scrolling & panels): three features. (1) Fast-scroll
render hold — the scrollbar "jumping" on big/CAD docs was UI-thread
stalls: renderPicture walks the content stream TWICE synchronously
(collector + paint; worst corpus pages 100–420ms per walk — probe:
pdf_graphics/tool/interp_timing.dart), and every page entering the
cacheExtent kicked it mid-fling. `PdfPageView.renderHold`
(ValueListenable<bool>): while true, a page with no `_picture` yet
skips `_render` (sets `_holdPending`, re-fires on release); pages with
a picture re-raster freely (toImage is raster-thread). The viewer owns
`_renderHold` + `_trackScrollVelocity` (in `_onScrollForDetail`):
per-frame samples (timestamp = `currentSystemFrameTimeStamp`, NOT wall
clock — one wheel tick fires several listener calls in one frame and
an instant 100px jump must not read as infinite velocity; same-frame
samples collapse), ~200ms window, hold = |v| > max(800, 2·viewport)/s;
the 250ms scroll-settle timer clears samples + hold. jumpToPage's
250ms animateTo trips it too (long jumps render only on arrival).
First-frame gap: the first scroll event of a gesture has span 0 → no
verdict → that frame may still interpret one page; inherent to any
estimator. (2) Sidebar scrollbar clearance: both panels pad their list
on the right by the bar zone — hitExtent(14) + grip(8) when the grip
rides the same right edge (thumbnails: minus the tiles' own 12px,
`_extraRightPadding`; tileWidth/_estimateOffset now share `_tileWidth`
= width−26−extra). (3) Annotation-list detail:
`PdfWidgetAnnotation.fieldValue` (inherited /V up /Parent: string,
name, or first array string) + sidebar `_detail` — Widget tiles titled
by /FT (`_fieldLabel`) with "name — value", Link tiles "text — target"
via `PdfPageText.textIn(rect)` (new in pdf_graphics: runs whose bounds
CENTER lies in the rect, document order — whole runs, no partial text)
and `_actionLabel` (URI → uri, GoTo → 'Page N', Named → name, JS →
'JavaScript'); per-page PdfPageText cached in `_pageTexts`, cleared
with `_builtFor` (extraction interprets the page — once per revision
per page that lists a link). Tests: render_hold_test.dart (the
fling test interleaves runAsync delays into the animation pumps so an
un-held render WOULD complete — without that, findsNothing passes
vacuously; both tests verified to fail with the hold disabled),
annotation_test.dart field values, text_extraction_test textIn,
editing_sidebar_test detail tiles (sidebar mounts fine without a
viewer), editing_panels_test clearance (assert the list widgets'
`padding`). buildAcroFormPdf/buildAnnotatedPdf already cover fields
and link actions; link-over-text needed an inline fixture.
Scrollbar jumping, the SECOND cause (Ben, AMT-SP-101.pdf, 291 pages =
232 portrait + 59 landscape A4): debug-logged scroll state while he
scrolled — maxScrollExtent oscillated 93k↔162k px between FRAMES.
itemExtentBuilder gives every child an exact layout offset, but the
sliver's TOTAL scrollExtent comes from
childManager.estimateMaxScrollOffset (average built-child extent
extrapolated over the rest), which the builder never feeds — uniform
docs hide it because the average is constant. Fix:
`ExactExtentListView` (exact_extent_list.dart, package-private) —
ListView subclass overriding buildChildLayout to mount a
SliverVariedExtentList whose render object overrides
estimateMaxScrollOffset → computeMaxScrollOffset (sums the extent
builder over all children; O(n) per layout, trivial). Diagnosis
pattern worth repeating: buffered scrollDbg logging (250ms-batched
print) of px/max/vp/ty/s/velocity/hold per scroll event + FrameTiming
+ per-render ms — the log cleared render stalls (hold worked; frames
fine) and convicted the metrics in one pass. Regression:
exact_extent_test.dart (buildVariedHeightPdf, asserts maxScrollExtent
== the exact sum AND constant across jumps; fails on stock ListView
~2k px off). Reminder: any temp logger that re-arms a Timer trips
widget tests' !timersPending — strip instrumentation before running
suites. The thumbnail strip's ReorderableListView still estimates
(no itemExtentBuilder support); its bar could wobble on mixed docs —
known, unfixed.
Batch 3, session 5 (forms API): a native forms-mutation API.
Metadata (form.dart):
`PdfAcroForm.describeFields()` → `PdfFormFieldInfo` (name, type,
pageIndex, rect) and `PdfFormField.widgetPageIndex` — widget /P first,
then a per-page /Annots identity scan (fixture widgets carry no /P);
−1 for orphans, null rect for junk /Rect, index range-guarded.
Mutations (form_admin.dart, new part of editor.dart):
`addTextField`/`addCheckBoxField`/`addPushButtonField` (merged
field+widget dict, /P + /F 4; creates /AcroForm with /DA "/Helv 0 Tf
0 g" + /DR when absent; push buttons get a blank /AP so they're
drawable), `renameField` (rewrites the terminal /T; prefix-aware
collision check), `removeField`, `changeFieldType` (snapshot first
widget page+rect → remove → re-add same name; pdf-lib semantics:
multi-widget fields collapse to one), `flattenForm` (per-page
`_flattenAnnotations(pageIndex, select)` — flattenAnnotations grew the
predicate — widgets only, then removeField per field, every step
try/caught: junk /Rect or dangling /AP refs must never derail the
rest). ARRAY RULE learned here: /Annots, /Fields, /Kids may be
indirect — never mutate a resolved CosArray in place and stage the
holder (the write won't carry); rebuild and REASSIGN the array into
the holder dict, like deleteAnnotation always did. Fill upgrades
(form_editor.dart): `setTextValue(multiline:)` toggles /Ff bit 13
before regenerating; `sanitizeFieldText` swaps code units > 0xFF for
spaces in APPEARANCES only (/V stays verbatim — appearance fonts are
byte-encoded simple fonts, so those glyphs can't reach the page);
`setButtonImage(field, image)` = aspect-fit centered image over the
/MK decorations, /AP /N per widget (for signatures/logos).
pdf_cos: `CosString.fromText` USED TO THROW on non-Latin-1
(latin1.encode) — now UTF-16BE with BOM per §7.9.2.2, so filling
"naïve ✓" works and /V round-trips.
Images: `PngImage` (pdf_document png.dart) — full baseline PNG: bit
depths 1/2/4/8/16, color types gray/RGB/palette/gray+alpha/RGBA,
tRNS (palette + color key), Adam7; 16-bit reduces to the high byte
(libpng strip-16 — ImageIO rescales with rounding, the one documented
divergence in the KATs); palette indices must NOT be bit-scaled
(scaleSubByte flag). `PdfEmbeddableImage` (image.dart) wraps JPEG
(DCTDecode passthrough, readJpegInfo moved out of content_editor) and
PNG (re-deflated samples, alpha → /SMask, which must be an INDIRECT
stream — toXObject takes an addObject callback); `PdfStamp.image()`
is the generic entry, jpegImage delegates. pdf_document now depends
on package:archive. PNG KATs: fixtures generated by an independent
python implementation (filters + Adam7), opaque ones pixel-verified
against macOS ImageIO (sips → BMP → compare) before check-in.
Base-14 metrics fix (pdf_graphics font_info.dart), found by the form
smoke render clipping a line AFM said fit: simple fonts with no
/Widths fell back to flat 0.5 em, so /DR-style Helvetica (legal per
§9.6.2.2) measured ~15% wide — `_fillStandardWidths` now fills
32–126 from the AFM tables imported from pdf_document
(Helvetica/Arial → helvetica[Bold]Widths, Times* → timesRomanWidths,
Courier* → flat 600; italic ≈ upright). Ripples: interpreter_test /
text_extraction_test had flat-500 baked into expectations (now use
measureHelvetica); pdf_viewer selection tests moved the drag start
154→158 ('Page 1' @24pt is now 76.06pt wide, and the 20px slop move
must still leave the anchor nearest the run END boundary). Test
gotchas: flattened field values live in FlatAnnot XObject streams,
not page contentBytes; a sanitized trailing '✓' leaves trailing
spaces in the appearance string — count them when asserting.
Batch 3, session 6 (forms in the editing UI): the session-5 forms API
surfaced as direct manipulation. `PdfEditTool.form` +
`PdfFormFieldKind` {text, checkBox, pushButton} (editing_controller).
Controller: `acroForm` cached per revision (reset in
_invalidateElements — field enumeration walks the tree and hit tests
run per pointer event); `formFieldAt(page, x, y)` → (field,
widgetIndex) by identity-matching the hit Widget annotation's dict
against field.widgets (topmost /Annots entry wins); fill ops re-resolve
the field BY NAME inside apply() (PdfFormField dies with every
revision — names are the stable handle) and turn editor
ArgumentError/StateError into a false return: `setFormFieldText`
(unchanged-value guard), `toggleFormCheckBox`, `setFormRadioValue`,
`setFormChoiceValue`, `setFormButtonImage(name, bytes)`
(PdfEmbeddableImage.decode, junk → false); admin: `addFormField`
(auto-names 'Field N', returns the name), `renameFormField`,
`removeFormField`, `changeFormFieldKind`, `flattenFormFields`,
transient `newFormFieldKind`. `pages:` for fills = every widget's
widgetPageIndex (null when any is -1); rename passes const [] (no
visual change). pdf_document: `PdfFormField.widgetOnState(index)` —
first non-Off /AP /N key of THAT widget (which state a radio kid tap
selects). Overlay: form-tool taps route by field.type — text opens
the existing inline editor in a form mode (`_textEditFieldName` +
`_textEditMultiline`; key becomes 'pdf-form-text-editor'; /DA-parsed
font/size, 0 Tf edits at 12; single-line fields get maxLines 1 +
onSubmitted commit; commit → setFormFieldText + the _afterText
afterimage with washed: true), checkbox/radio toggle instantly,
choice shows showMenu (item keys 'pdf-form-option-<export>'),
push button runs `PdfViewer.formImagePicker` (typedef
PdfFormImagePicker lives in text_prompt.dart — the overlay file is
unexported, so public typedefs can't live there); read-only fields
ignore taps; drag-out on empty area adds newFormFieldKind (drags
starting ON a widget are not creation gestures); hover: text cursor
over text fields, click over buttons/choices, precise elsewhere.
Menu: `showPdfFormFieldMenu` (editing_menu.dart, keys
'pdf-form-menu-rename/-text/-checkbox/-button/-delete/-flatten');
viewer _onSecondaryTapUp branches to it when the form tool is armed
(field hit-test first — widgets stay out of selectableAnnotationAt).
_menuRow's label is now Flexible+ellipsis: long labels overflowed the
popup's 280px cap under the Ahem test font. Toolbar: ballot_outlined
form button; while armed a PopupMenuButton ('pdf-form-field-type',
entries 'pdf-form-type-text/-checkbox/-button') picks the drag-out
kind and layers_clear flattens. Example: `_pickFormImage` via
file_selector (png/jpg type group needs all three platform fields).
Tests (editing_form_test.dart, 18): controller round-trips + viewer
widget tests on buildAcroFormPdf (612×792 → view() helper like
editing_text_edit_test). Gotchas: a showMenu opened from a TOUCH tap
has burned ~300ms of the usual 400ms double-tap pump on tap
resolution — pumpAndSettle before tapping a menu item or the item's
paint position and hit region disagree mid-animation (tap lands on
the barrier, menu dismisses, value never set); commit-tap targets
must stay inside the 800×600 viewport (view(450, 300) is y≈643 —
silently misses, editor never closes).
Batch 3, session 7 (iPad input, from Ben's on-device testing): five
fixes/features. (1) Touch pinch zoom: InteractiveViewer's scale
recognizer always lost the arena (list drag at 18px, overlay pan at
36px with a tool armed) — `_EagerPinchRecognizer` (pdf_viewer.dart,
touch-only ScaleGestureRecognizer subclass) stays passive for single
pointers and `resolve(accepted)` the moment a 2nd touch joins;
_onPinchUpdate rides `_zoomTo` (focal zoom) + `_grabPanBy`
(focalPointDelta is LOCAL = list-space — verified in SDK scale.dart);
gesture end settles via `_settleZoomGesture()` (extracted from
onInteractionEnd, shared). Limitation: the 2nd finger must land
before the 1st finger's arena closes — mid-scroll add-finger won't
zoom. (2) Raw-driven drawing: with ink/eraser armed, stylus (always)
and touch (iff fingerDrawsInk) draw from the overlay's raw Listener —
`_rawDrives(kind)`, `_rawPointer` claims the gesture in
_onPointerDown, moves append, up commits; pan recognizers still claim
the arena (blocking IV pan/list scroll) but _panStart/_panUpdate/
_panEnd early-return for raw-driven kinds. Zero start latency; a
down+up dot commits as a 2-point stroke [p, p] (round cap renders the
dot, §8.5.3.2). Viewer guards: `_kindDrawsInk` early-returns
_onSelectionStart (no grab-pan under a stroke) and _onDoubleTap (two
quick pen dots must not zoom). Mouse/trackpad keep the arena path.
(3) Multi-touch bail: `_touchPointers` tracked on the raw listener; a
2nd concurrent touch calls `_bailActiveGesture()` (discards stroke/
erase/drag state without committing, `cancelInkStroke()` re-arms the
auto-commit for earlier buffered strokes, `_gestureBailed` deadens
the rest until all touches lift) — EXCEPT when `_rawPointer` is a
stylus (not in _touchPointers): that's a palm, the pen stroke
survives. (4) Selection action chip: `_buildSelectionChip` — floating
Material row (keys 'pdf-selection-chip', '-delete', '-edit' (only
canEditSelectedText), '-menu') above the selection (below when near
the page top), shown only when `_lastPointerKind` ∈ {touch, stylus}
(set on every overlay pointer-down), select mode, not dragging;
Transform.scale(_chromeScale) keeps it screen-constant; '-menu' calls
`EditingPageOverlay.onShowAnnotationMenu(globalPos)` → viewer
`_showSelectionMenu` → showPdfAnnotationMenu with the host's
annotationMenuBuilder (threaded through _PdfViewerPage). (5) Eraser:
`PdfEditTool.eraser` — whole-annotation; `inkAnnotationAt(page, x, y,
tolerance:)` (editing_controller) demands proximity to the /InkList
polyline (segment distance ≤ tolerance + borderWidth/2; rect-only
fallback), `PdfAnnotation.inkList` (pdf_document) parses the point
arrays; swipe collects slots (`_eraseSlots`) → ONE deleteAnnotations
apply on lift (one undo); live fade + afterimage = painter
`fadeRects` washed in pageColor@0.72 (`_afterEraseRects` until
rasterCurrent); invertedStylus erases while INK is armed; mouse uses
the arena (_panErasing, click via _onTapUp); toolbar button
Icons.auto_fix_normal (no real eraser glyph in the icon font), shown
for all input — Ben suggested maybe hiding it from mouse users, but
click-to-erase is genuinely useful on desktop; the touch_app
finger-toggle now also shows with the eraser armed. Tests:
editing_ipad_test.dart (17 — pinch via two TestGestures, raw stroke
under-slop + dots, bail + palm + buffered-stroke release, eraser
precision/undo/inverted, chip visibility per kind + menu). Gotchas:
finishInk aggregates the whole buffer into ONE annotation — tests
needing two annotations must finishInk between strokes; a touch tap
on overlay chrome resolves only after the viewer's 400ms double-tap
timeout, and pumpAndSettle does NOT advance that timer (no frames
scheduled) — pump(400ms) explicitly.
Batch 3, session 8 (touch text selection, from Ben's iPad testing —
"scroll gets caught in text selection"): the viewer's selection pan
recognizer accepted touch, so any swipe with a horizontal component
crossed pan slop before the list's vertical drag could claim it and
became a selection. Now: the pan recognizer (pdf_viewer.dart, the
inner detector — now GestureDetector(taps) wrapping a
RawGestureDetector) is mouse+trackpad only; touch/stylus selection is
`_SelectionLongPressRecognizer` (long press, touch+stylus, gated by
`isEnabled` checked in addAllowedPointer: stands down entirely while
an editing tool is armed or the eyedropper is live, so it never claims
under a tool gesture). Long-press start selects the word
(`_wordRangeAt` + HapticFeedback.selectionClick), move extends by
whole words (`_extendWordSelection`, factored out of
_onSelectionUpdate's word path), lift shows the chrome. Chrome =
`_PageTextSelection` config computed per page in `_textSelectionOn`
(boundary pages only; null mid-long-press — the wash is the live
feedback), rendered by `_TextSelectionChrome` in the page Stack
(topmost; only mounts in reader mode) under a
ValueListenableBuilder(transformScale): `_SelectionHandle` lollipops
(start ball above rect.topLeft, end ball below rect.bottomRight; color
= new `PdfViewerThemeData.selectionHandleColor`, default 0xFF2196F3;
counter-scaled by 1/zoom) whose drags use `_EagerPanRecognizer`
(claims on pointer down — beats list scroll; handle drag start
normalizes anchor/focus so the dragged end is the focus, updates via
`_textPositionAt(globalToLocal through _listSpaceKey's RenderBox)` —
the render tree applies the zoom transform for free), and a
Copy/Select-all chip (keys 'pdf-text-selection-chip', '-copy',
'-select-all'; Copy = copySelection + clear, Select all =
`_selectAllTextOn(page)`, factored out of _onSelectAll). Handle keys:
'pdf-text-handle-start'/'-end'. Chrome shows when `_selRange != null`
&& last pointer kind ∈ {touch, stylus} && !_touchSelecting; chip also
hides while `_handleDragging`. Tests
(pdf_touch_selection_test.dart, 14): on a one-word selection the two
handle hit boxes overlap across the stem zone and the end handle
(later in the Stack) wins hits there — grab the start handle's BALL
(above the text line) in tests; touch chip taps need the usual
pump(400ms); existing selection tests were already mouse-kind so the
recognizer restriction broke none.
Batch 3, session 9 (circle eraser, Ben: "PSPDFKit style circle eraser
which slices annotations"): the eraser now slices ink instead of
deleting whole annotations. pdf_document: `pdfSliceInkStrokes(strokes,
pressures, from, to, radius)` (annotation_editor.dart, exported) —
one capsule stamp; per stroke segment the erased t-interval is found
by ternary search (distance to a convex capsule along a segment is
convex) + bisection refinement, pressures interpolate at cut points,
sub-0.05pt remnants drop, returns null when untouched (the unchanged
signal). `PdfEditor.sliceInk(page, annot, path, radius)` applies the
path capsule-by-capsule and rewrites /InkList + /Rect + the /AP IN
PLACE (`_inkAppearance` factored out of addInk; `_replaceAppearance`
keeps object numbers, so author/contents/identity survive); empty
result → removeAnnotation. Pressures are RECOVERED from our own
appearances (`_recoverInkPressures`): pressured strokes carry one `w`
per segment, so parse ops (ContentStreamParser on decodeStreamData),
reject any op outside the stroked-path set, invert pdfInkStrokeWidth
per segment, average back onto points — any mismatch → uniform
fallback, never guess on foreign appearances. Controller:
`eraserRadius` (persisted pref `eraserRadius`, default 8pt),
`sliceErase(page, path)` — resolves all ink annots up front (editor
works by dict identity, slot shifts don't matter), slices each in ONE
apply, inkless Ink annots fall back to whole-delete when the path
reaches their rect, `_selected` cleared inside the apply callback
only when something changed. Overlay: `_erasePath` accumulates page
points; each move slices the tracked remainders INCREMENTALLY by just
the newest capsule (slicing by capsule A then B == slicing by A∪B —
removal is pointwise), so the live preview is exact: fade wash over
the touched annots' rects + `_eraseSliced` remainders riding extraInk
(painter now paints fadeRects BEFORE ink so remainders read at full
strength). Ring cursor: painter `eraserCursor`/`eraserRadius` (view
px = radius × geometry.scale — page-space size, NOT chrome-scaled;
the line weights are), shown while dragging any pointer and on mouse
hover (`SystemMouseCursors.none` — the ring is the cursor; onExit
clears it unless mid-swipe). Commit on lift → `sliceErase`, afterimage
= `_afterEraseRects` + `_afterEraseInk` until rasterCurrent. Toolbar:
'Eraser size' slider (key 'pdf-eraser-size', 2–40pt) joins the style
menu only while the eraser is armed — the legacy 3-slider count test
still holds. Tests: pdf_document/test/ink_slice_test.dart (geometry
KATs — the vertical-spine cut of a horizontal line lands exactly at
|x−cx| = r; pressure recovery round-trip 3.28/4.72 w), dart_pdf_editor
editing_eraser_test.dart (live preview via the dynamic painter cast —
record fields ARE dynamically accessible; afterimage; hover ring;
slider; pref round-trip) and editing_ipad_test.dart eraser group
updated to slicing semantics (annotations survive, inkList splits,
cut bounds ±0.5pt through the full pointer→commit chain). Gotcha: an
eraser tap is a single-point path — sliceInk/pdfSliceInkStrokes treat
path.length == 1 as a degenerate capsule (a circle stamp), don't skip
it.
Batch 4, session 1 (resize & text-box correctness, from Ben's comment
batch): three fixes. (1) Rotated-resize anchoring: the committed
annotation re-rotates about the NEW local box's center
(resizeAnnotationLocal places localTo rotated about localTo's center),
so any handle drag that moved the center translated the whole
annotation by Δ − R(Δ) — and the dragged handle didn't track the
pointer. Fix is one overlay-side shift (`_anchorResized` in
editing_overlay.dart): shift the dragged local box by R(Δ) − Δ
(Δ = center delta, R = resting view angle); that cancels the drift for
EVERY fixed local point, so the geometry opposite the drag stays
planted and the handle rides the pointer exactly — both provable from
the same identity, and the correction survives the view→page y-flip
(M R_λ M⁻¹ = R_θ). Compute Δ from the UNSHIFTED resized rect. The
ghost preview needed no change (its toC shift composes identically).
editing_rotate_test's local-frame test now asserts the anchored rect
AND the fixed quad ll corner — the old expectations encoded the bug.
(2) Free-text resize previews wrapping: a FreeText resize commit
re-wraps at constant font size, but the drag ghost stretched the
glyphs. `_textResizeStyle` (overlay) mirrors the editor's regenerate
gate exactly (subtype FreeText + normalAppearance + freeTextStyle
parses + PdfStandardFont.tryFromName succeeds); while a resize drag is
live it suppresses the ghost and mounts `_wrappedTextBox` (key
'pdf-text-resize-preview', shared with the _afterText afterimage) at
_resizeRect — text at committed size over fill-or-pageColor@0.92 wash,
Transform.rotate for rotated boxes (_afterText record gained
`rotation`). The commit path freezes the same wrapped preview as the
afterimage instead of _commitWithGhost. Non-regen free text (embedded
fonts) falls back to the stretch ghost — preview must always match
the commit. (3) Text-edit layout shift: the inline editor sat at
rect.inflate(2) and its border was a regular BoxDecoration — Container
folds decoration.padding (= border width) into the child inset, so the
TextField content sat off the box by 2 − 1.5·chromeScale px and the
text jumped on open/commit. Fix: padding EdgeInsets.all(2) (the
inflate gutter) + the border moved to foregroundDecoration (paints
over, contributes NO padding) + fill via Container.color — content now
sits exactly on the annotation rect. Test gotchas: asserting editor
position uses tester.getTopLeft(editorKey) == view(rect tl) — fails by
(1.5,1.5) if the border ever moves back into `decoration:`; the fill
preview test reads Container.color now, NOT decoration.color (a
color-only Container has no decoration). Batch-4 comments remaining:
copy/cut/paste of annotations, properties panel, annotation-panel
search, page-number jump field, slimmer search bar + results panel,
PDF.js corpus, restyle-any-selected-annotation; crypto comment
answered (package:crypto is digest-only — AES/RC4/RSA/ECDSA aren't in
it, no duplication).
Batch 4, session 2 (clipboard & restyle): two features.
(1) Copy/cut/paste: `PdfAnnotationSnapshot` (annotation_clipboard.dart,
new part of editor.dart) — `capture(doc, annotation)` deep-copies the
dict fully INLINE (references resolve and duplicate, streams keep raw
bytes with /Filter intact; encrypted sources decrypt-only via
stopBeforeFilter like _PageImporter), drops P/Popup/Parent/IRT/RT/NM/
StructParent/OC, refuses Popup/Link/Widget (null). Detached → survives
undo, revisions, and crosses documents. `PdfEditor.pasteAnnotation(
page, snapshot, dx:, dy:)` re-materializes per paste (copies never
share structure), shifts Rect + QuadPoints/L/Vertices/CL/InkList, then
`_hoistStreams` (children-first: every inline CosStream → addObject
reference, §7.3.8) and appends to /Annots. Controller: `_clipboard`
(in-app; PDF annots don't round-trip the OS clipboard),
copySelectedAnnotations/cutSelectedAnnotations (cut = copy +
deleteSelected, one undo) / `pasteAnnotations(page, at:)` — at: centers
the group on the point (menu paste at right-click), else cascade
12pt·n down-right (n+1 on the source page so paste #1 doesn't cover
the original; counter resets per copy), `_clampShift` keeps the group
in the crop box (oversize pins low edge); paste arms select +
selects the appended slots (last N). Viewer: ⌘C routes annotation
selection → clipboard, else text copy; ⌘X/⌘V new (bound only when
editing != null; all disabled while isEditingText). Menu keys
'pdf-annot-menu-copy'/'-cut'/'-paste' (paste disabled w/o clipboard);
empty-area right-click now shows the menu IFF clipboard non-empty
(hasSelection false → paste-only menu; showPdfAnnotationMenu gained
`pagePoint`). Re-copy after paste copies the PASTED annots (selection
moved) — test gotcha.
(2) Restyle any selected annotation (#11): `PdfEditor.restyleAnnotation
(page, annot, {color, fillColor: (int?,)?, strokeWidth, opacity})` —
IN PLACE (object numbers + slots survive, vs _rewriteSelected's
remove+re-add): Ink rewrites /C /BS /Rect + appearance via
_inkAppearance with `_recoverInkPressures` (pressures survive but
SMOOTH through the segment→point→segment round trip — [2.6,1.4]@2 →
×2 base gives [4.6,3.4], not [5.2,2.8]; rect re-pads from the widest
RECOVERED pressure); markups regenerate from `_axisAlignedQuads`
(rotated/malformed quads gate to false) via `_markupContent` (factored
from the four creators — Highlight keeps Multiply+GS0 always);
Square/Circle update /C /IC /BS then `_restyleRegenerate` →
`_regenerateStyledAppearance` (= _regenerateResizedAppearance grown an
`opacity:` override, + Stamp `_stampContent` and Text `_noteContent`
factored out of their creators); FreeText rebuilds /DA (rg + kept RG)
and /C = fill ?? textColor (the no-fill mirror convention — leaving
old /C would conjure a background). Rotated annots: regen at the
quad-derived local box then rotateAnnotation (resizeAnnotationLocal's
shape). Gate: top-level `pdfCanRestyleAnnotation(annotation)`
(exported; no editor needed — PdfAnnotation carries its document).
`PdfAnnotation.appearanceOpacity` getter (first /ca in /AP /N
ExtGState, 1.0 default). Controller: `canRestyleSelected` (every
selected passes the gate), `restyleSelected({color, fill: (Color?,)?,
strokeWidth, opacity})` (whole selection, one apply, slots/selection
survive), `selectedAnnotationStyle` (color — freeTextStyle.color for
FreeText — borderWidth, appearanceOpacity) for the style menu.
Toolbar: palette tap + 'More colors…' → `_applyColor` (sets default
AND restyles selection when canRestyleSelected); stroke/opacity
sliders show the selection's values and restyle on release
(_draggingStroke/_draggingOpacity mirror the font-size pattern).
Tests: pdf_document annotation_clipboard_test (7) +
annotation_restyle_test (8), dart_pdf_editor editing_clipboard_test (16).
Remaining batch-4: properties panel, annotation-panel search,
page-number jump field, slimmer search bar + results panel, PDF.js
corpus.
Batch 4, session 3 (panels: properties + sidebar search): two
features. (1) `PdfAnnotationPropertiesPanel` (editing_properties.dart,
exported) — a third resizable side panel (same shape as the sidebars:
side/resizable/min/max, width persisted as preference
`propertiesPanelWidth`, grip key 'pdf-properties-resize-grip',
PdfScrollbar thumb 'pdf-properties-scrollbar-thumb', bar-clearance
list padding). Reads the controller's selection: no selection → hint;
one → type/page header + sections; several → 'N annotations' +
shared style controls (restyleSelected acts on all). Controls and
gates: color swatch (canRestyleSelected → showPdfColorPicker →
restyleSelected(color:)), fill swatch + no-fill button (all selected
∈ {Square, Circle, FreeText}; FreeText fill reads
freeTextStyle.fillColor, shapes interiorColor), stroke slider (all ∈
{Square, Circle, Ink}), opacity slider (all ∈ shapes/ink/markups/
Stamp), font dropdown + size slider (canRestyleSelectedText →
restyleSelectedText), Contents/Author text fields, X/Y/W/H geometry
fields in page points (X/Y → moveSelected; W/H → resizeSelected
anchored bottom-left, enabled iff canResizeSelected; unparsable input
snaps the fields back). Field keys 'pdf-prop-color/-fill/-stroke/
-opacity/-font/-font-size/-contents/-author/-x/-y/-w/-h'. Text-field
sync: `_syncedFor` = (document identity, primary slot) — fields
rewrite only when that key changes, so typing never gets clobbered;
commits run on submit AND Focus(onFocusChange: false). Sliders keep
the toolbar's dragging-state pattern (one revision per gesture).
New plumbing: `PdfEditor.setAnnotationContents/setAnnotationAuthor`
(annotation_editor.dart — in-place dict edits, appearance untouched;
empty/null removes the entry; author on a Widget throws, /T is the
field name there) and controller `setSelectedContents` (single
selection; textEditable subtypes route via setSelectedText so the
page matches, others are metadata-only with pages: const []) +
`setSelectedAuthor` (whole selection, one apply, pages: const []).
Preferences: `showPropertiesPanel` host-chrome flag +
`propertiesPanelWidth`; example app: tune AppBar button + keyed
panel after the annotation sidebar. (2) Sidebar search: a compact
TextField (key 'pdf-annotation-search', clear button '-clear') always
present above the list (constant tree shape — the session-5 lesson);
filters tiles case-insensitively against the tile title (_title,
factored from the tile builder) and _detail subtitle (author,
contents, field name/value, link text/target); page headers only
survive with matching tiles; query non-empty + all filtered → 'No
matching annotations'; the query deliberately survives revisions
(the document-identity reset clears checkboxes, not the search).
Tests: pdf_document annotation_metadata_test (3), dart_pdf_editor
editing_properties_test (11: 3 controller + 8 panel widget tests),
editing_sidebar_test +3 search tests. Gotchas: the search TextField
hosts its own Scrollable — pdf_theme_test's annotation-bar test had
find.byType(Scrollable).first and silently grabbed the field's; scope
to find.descendant(of: byKey('pdf-annotation-list')). Panel widget
tests need a tall surface (tester.view.physicalSize 800×1400 +
reset) — ListView children below 600px never build, and enterText
on an unbuilt field fails. receiveAction(TextInputAction.done) fires
onSubmitted on multiline fields too. Remaining batch-4: page-number
jump field, slimmer search bar + results panel, PDF.js corpus.
Batch 4, session 4 (navigation & search chrome): three widgets + the
controller API under them. (1) `PdfViewerController.searchResults` →
`PdfSearchResult` (match + prefix/matchText/suffix snippet; matchText
keeps the page's own case) built in `_searchAllPages` via `_snippetFor`
(rest of the match's line, capped 36 chars before / 48 after, '… '/' …'
when cut, whitespace squashed) — search() now stores results and
derives `_matches` from them; `goToMatch(index)` = currentMatch +
_showMatch (range-guarded). (2) `PdfPageNumberField`
(page_number_field.dart, exported) — "N / M" with N an editable
TextField (key 'pdf-page-number-field', digitsOnly, width from the
digit count): enter jumps (clamps 1..pageCount, junk/empty resets),
focus selects all, blur re-syncs, controller changes re-sync only
while unfocused. (3) `PdfSearchField` + `PdfSearchResultsPanel`
(search_panel.dart, exported): the field is a slim fixed-width (200)
rounded TextField (key 'pdf-search-field') with debounced live search
(350ms Timer; submit searches immediately; emptying clears instantly),
spinner while searching, clear suffix ('pdf-search-clear'), and
count 'n/m' + prev/next ('pdf-search-prev'/'-next') outside the box —
optional external searchController/focusNode for host ⌘F and clearing
on open. The panel mirrors the properties panel's shape (side
left-docked by default, resizable, grip 'pdf-search-resize-grip',
PdfScrollbar 'pdf-search-scrollbar-thumb', bar-clearance padding)
but takes a PdfViewerController + OPTIONAL PdfEditingPreferences
(width persists as `searchPanelWidth` only when provided; without
prefs the dragged width just stays in _dragWidth — don't null it on
drag end); states: no query → hint, isSearching → spinner, 0 results
→ 'No matches for "q"', else 'N matches' header + ListView.builder
of page headers + ListTiles (key 'pdf-search-result-<i>', Text.rich
bold+searchMatchColor-washed match, selected = currentMatch, tap →
goToMatch). Known gap: the list doesn't auto-scroll to follow
next/prev stepping (builder tiles aren't built off-screen).
Preferences: `showSearchResultsPanel` + `searchPanelWidth`. Example:
the AppBar 'N / M' text is now PdfPageNumberField; the full-row
bottom search bar is GONE on wide windows (≥720px: inline
PdfSearchField + manage_search toggle in actions) and a slim 48px
bottom row on narrow ones (phones — the inline field would overflow
the AppBar); results panel docks left of the viewer (keyed, after
the thumbnail strip). Tests: search_navigation_test.dart (10).
Gotchas: the demo's page-number field broke demo_test two ways —
find.text('1') also matches the field's EditableText (counter
asserts now use a Text-widget predicate) and find.byType(TextField)
.last hits AppBar fields because Scaffold mounts body BEFORE appBar
in tree order (the demo note field is keyed 'demo-note' now); the
panel's page header and a 'Page N' snippet both render the same
string — findsNWidgets(2). Remaining batch-4: PDF.js corpus.
Batch 4, session 5 (PDF.js corpus — the last batch-4 item):
`test_corpora/pdfjs/` (checked in, 3.4MB) — 171 edge-case PDFs curated
from mozilla/pdf.js test/pdfs @ 2466a76 (only committed files, none of
the .link ones; provenance + per-file notes in the corpus README; raw
URL pattern in there too). Survey workflow that built it:
`pdf_graphics/tool/pdfjs_survey.dart` opens + interprets everything and
buckets ok/open-fail/page-fail/blank — kept for future corpus drops.
Test layers mirror Ghent: pdfjs_corpus_test.dart (pdf_graphics, pure
Dart; per-file pinned expectations — passwords {issue6010_1 abc,
issue6010_2 æøå, issue15893_reduced test, bug1782186 Hello, issue3371
ELXRTQWS, encrypted-attachment 000000}, print_protection must throw
CosPasswordException (pdf.js shows its password dialog too — NOT a
bug), 6 fuzz files pinned "controlled CosParseException or zero
reachable pages", 14 mayBeBlank files annotated in-test) and
pdfjs_render_test.dart (dart_pdf_editor, rasterizes ≤5 pages/file at
ratio 1, no baselines — exercises the image decoders; skips the
unopenable+password files).
Bugs the corpus caught (all fixed, all with inline-fixture regression
tests): (1) self-referential stream /Length (`4 0 obj <</Length 4 0 R>>`)
recursed to StackOverflow — getObject now keeps a `_loadingObjects`
re-entrancy set; a re-entrant load answers CosNull WITHOUT caching and
the parser's endstream scan takes over (poppler-91414). (2) xref
entries pointing at the wrong object threw — `_parseIndirectAt` returns
null on junk/mismatch and `_parseScannedHeader` lazily runs the same
`N G obj` scan recovery uses (factored to `_scanObjectHeaders`), then
dangling-null (poppler-395). (3) stray operators inside array operands
(`[(a) 0.0 Tc -250.0 (b)] TJ`) aborted the page — ContentStreamParser
`_parseLenientArray` drops non-true/false/null keywords, keeps numbers,
tolerates unterminated arrays (operator-in-TJ-array). (4) pageCount
trusted a lying root /Count — it is now ALWAYS the cached leaf walk
(`_leaves`, shared with pageIndexOf; /Count survives only as page()'s
subtree-skip hint), so page(i) never RangeErrors below pageCount
(Pages-tree-refs is an interior-node CYCLE 3→4→5→3 with /Count 2 and
one real page — the visited-set is right, /Count lies). (5) a content
stream whose filter rejects its data killed the page — contentBytes
skips that stream, the rest of the /Contents array still draws
(PDFBOX-4352). (6) unresolvable fonts dropped text — _setFont falls
back to a synthesized Helvetica dict (`_fallbackFontDict`) so text
paints and stays selectable. (7) function-based (type 1) shadings were
blank — `PdfFunction.evaluateAt(List)` (type 4 pushes all inputs,
clamped per /Domain pair; others use input[0]) +
`PdfShading.toFunctionMesh` (24×24 grid sampled through the shading
/Matrix into PdfMesh) wired into sh, pattern fills, and _patternColor.
(8) Tr 3 invisible text never reached devices, so OCR scan text was
unselectable/unsearchable — PdfTextRun.invisible; the interpreter
emits mode-3 runs flagged, canvas_device early-returns on it, the
corpus/Ghent counting devices don't count it as paint (interpreter_test
"Tr 3" expectations updated — old test encoded the bug).
Encryption non-bugs worth remembering: print_protection.pdf has
NUL-padded 239-byte /O//U (the R6 sublist windows handle that fine) and
NO empty password — verified against an independent python+openssl
algorithm-2.B implementation before concluding our handler is correct.
encrypted-attachment.pdf (/StmF /Identity /EFF /StdCF, unsigned /P
4294967292) just needs password 000000 (pdf.js api_spec). pdf.js files
absent from test_manifest.json are unit-test fixtures — check
test/unit/*_spec.js (api_spec) and the adding commit before assuming a
render expectation. Survey gotcha: PdfDocument.open is lazy — catalog
and page-tree failures surface at pageCount, so harnesses must guard
BOTH; the corpus test's unopenable branch pins "CosParseException or
pageCount == 0". Known gaps the corpus documents but doesn't close:
JBIG2 Huffman/refinement (decode-fails gracefully, image skipped).
Predefined CJK CMaps are now handled (was a gap): `CjkCmap.forName`
(pdf_graphics fonts/cjk_cmap.dart) decodes non-embedded Type0 text for
Shift-JIS (`*-RKSJ-*`), EUC-JP (`EUC-H/V`), GBK/GB2312 (`GB*`/`GBK*`),
Big5 (`*B5*`), UHC/EUC-KR (`KSC*`), and the Unicode CMaps
(`Uni*-UCS2/UTF16-*`, code = Unicode directly). Each legacy charset has a
packed `(code, unicode)` table generated from a Python codec
(tool/gen_cjk_cmaps.py, same recipe as `_shift_jis_data.dart`); the font
then has no outlines so the device substitutes a system CJK font. EUC-TW
(`CNS-EUC`) and EUC-JP's JIS X 0212 (SS3) supplement still fall back to
the Identity two-byte path. Corpus: noembed-sjis/eucjp + issue3521 now
paint (dropped from `mayBeBlank`); unit coverage in cjk_cmap_test.dart.
Batch 5, session 1 (annotation sync surface): three layers.
(1) /NM identity: `_addAnnotation` stamps a v4 UUID /NM on every
created annotation (single funnel for all ten creators; each creator
gained an optional `name:` that wins over generation — pass it ONLY
when rewriting/replaying), `PdfAnnotation.name` reads it,
`setAnnotationName` edits in place, `nameAnnotations()` stamps all
unnamed non-Popup/Widget/Link annots (legacy-file onboarding). In-place
ops (restyle/resize/slice/rotate/move) keep /NM for free; the
controller's `_rewriteSelected` (remove+re-add) passes `name:
annotation.name` through addFreeText/addStamp/addNote. pasteAnnotation
mints a fresh /NM when the snapshot lacks one (clipboard captures drop
it — a paste is a NEW annotation; annotation_clipboard_test's "NM is
null" expectation updated). (2) Serializable snapshots:
`capture(keepName: true)` keeps /NM (sync identity), `snapshot.name`,
`toJson()`/`fromJson()` — tagged COS encoding ({'n'} name, {'s' b64,
'h'} string, {'d'} dict, {'d','b'} stream, natives map natively),
version field v:1, appearance streams travel as base64 so replay is
byte-identical. (3) Diff + replay: `pdfDiffAnnotations(before, after,
pages:)` (annotation_sync.dart, new part of editor.dart) — keyed on
/NM; anonymous annots key on content fingerprint (jsonEncode of
toJson), so unchanged ones match and edited ones split into
removed+created; cross-page moves are `modified` (page is part of the
comparison); Popup/Widget/Link skipped (capture returns null).
`PdfEditor.upsertAnnotation(page, snapshot)` (remove-by-name then
paste; throws on nameless) + `removeAnnotationByName(name,
pageIndex: hint)`. Controller: `annotationChanges` (lazy broadcast
stream of per-revision List<PdfAnnotationChange>; apply/undo/redo all
emit; `pages: const []` metadata edits diff ALL pages — author/contents
change annotations without repainting), `applyRemoteChange` (one
revision, `_applyingRemote` suppresses the echo, pages: the touched
set, selection slots on touched pages dropped), `ensureAnnotationNames`
(silent — baseline is the explicit hand-off), `annotationBaseline()`
(whole state as created-changes), `findAnnotationByName`. CRITICAL
gotcha (cost two test-debug rounds): PdfEditor MUTATES the in-memory
COS of the document it runs on, so a diff's "before" must be a FRESH
PdfDocument.open of the prior revision's bytes — the controller's
`_emitAnnotationChanges` takes beforeLength and reopens the prefix
(only when the feed has a listener); pdf_document diff tests use an
editBytes helper for the same reason. Number formatting also differs
between in-memory CosReal and reparsed CosInteger, so an aliased diff
reads phantom `modified`s. Remote applies join the undo stack (byte
prefixes can't skip revisions) — undoing past one reverts it locally
and re-broadcasts the revert; documented, deliberate. Tests:
pdf_document/test/annotation_sync_test.dart (17),
dart_pdf_editor/test/editing_sync_test.dart (9 — incl. two piped
controllers converging both ways). Remaining gaps: per-annotation
read-only enforcement (host predicate + /F readOnly), hide-all
annotations viewer toggle.
Batch 5, session 2 (read-only enforcement + hide-all annotations): two
features. (1) Read-only: `PdfAnnotation.isReadOnly/
isLocked/isLockedContents` (/F bits 7/8/10) + `PdfEditor.
setAnnotationFlags` (in-place, like setAnnotationName). Controller:
`canEditAnnotation` (typedef PdfAnnotationEditPredicate; setter drops
newly ineligible slots from `_selected` and notifies) +
`isAnnotationEditable(annotation)` = !readOnly && !locked && predicate.
Gated paths: selectableAnnotationAt, selectAnnotationsIn (covers
marquee + ⌘A), selectAnnotation (sidebar), deleteAnnotation,
deleteAnnotations (filters targets — a sweep delete silently skips
locked), inkAnnotationAt + sliceErase (eraser); LockedContents only
gates canEditSelectedText + setSelectedContents (still selectable,
movable). Everything else (move/resize/restyle/clipboard cut) acts on
the selection, so gating selection entry is sufficient — that's the
design: locked annotations still render, list, zoom-to, and flash;
they just can't ENTER the selection. applyRemoteChange bypasses by
construction (editor-level, no selection) — the predicate governs this
user's UI, not document convergence (tested). (2) Hide-all:
`PdfPageRenderer.renderPicture/renderImage/sampleColor/
PdfPageColorSampler.of` take `annotations:` (default true; skips
drawAnnotations in BOTH interpreter passes — collector and paint).
Threaded: `PdfViewer.showAnnotations` → _PdfViewerPage → PdfPageView
(`showAnnotations`; didUpdateWidget drops the cached picture on
change, same as pageColor) and → EditingPageOverlay (sampler keyed on
document AND pageColor AND annotations); viewer `_annotationAt`
returns null while hidden, so invisible links/buttons take no taps
(test has a shown-mode control tap so the coordinates can't go stale
vacuously); `PdfThumbnailSidebar.showAnnotations` (cache key gains
'|noannots'; the enqueue closure captures it like pageColor).
Preference `showAnnotations` (bool, default true); example: AppBar
visibility/visibility_off toggle wired into viewer + thumbnails.
Tests: annotation_metadata_test +1 (flags round-trip),
editing_readonly_test.dart (7), annotations_visibility_test.dart (6).
Publishing round (Ben: pub.dev hosting + web demo): the Flutter package
is now **dart_pdf_editor** (pub.dev already had a `pdf_flutter`; Ben picked
the name) — directory, lib entry, and every reference renamed
(mechanical sed; suites re-ran green). All five packages are
publish-ready: Apache-2.0 LICENSE at root + copied per package,
CHANGELOG.md + README.md per package, pubspecs carry repository
(tree/main/packages/<pkg>), issue_tracker, and topics; `publish_to:
none` removed everywhere except the example. `false_secrets` allowlists
the deliberate test keys (pdf_cos /test/pki_test.dart, pdf_test_fixtures
/lib/src/signer_identity.dart) — pub's secret scanner blocks publish
otherwise. dump_charproc.dart moved pdf_cos→pdf_document tool/ (it
imports pdf_document; publish validation rejects undeclared imports —
also killed the long-standing analyzer info). All 5 dry-runs pass with
only the dirty-git warning; archives 63–500KB. First-publish order
(hosted constraints must resolve): pdf_cos → pdf_test_fixtures →
pdf_document → pdf_graphics → dart_pdf_editor; repo must be PUBLIC first so
pub.dev verifies the repository links; publishing is Ben's manual step
(needs his pub.dev auth). pdf_test_fixtures publishes too — it's a dev
dep of the others, and pana resolves dev deps, so leaving it private
would tank scores. Web demo: Firebase project `dart-pdf-demo` (Ben's
account), hosting serves example/build/web at
https://dart-pdf-demo.web.app (firebase.json + .firebaserc in example/;
no immutable cache headers — main.dart.js isn't content-hashed);
redeploy = build web --release + firebase deploy --only hosting.
Text reflow (#128) has since landed: a paragraph-aware reading view
with its own extraction logic (commit ec2c174).
Touch round (Ben's comments: fling, paste on touch, visible fields):
three features. (1) Touch fling: the overlay's viewport pan
(_viewportPanning) ended by dropping details.velocity, so finger
scrolls with a tool armed stopped dead at lift-off (reader-mode
scrolls fling fine — the list's physics own them). `onPanViewportEnd`
(overlay → _PdfViewerPage → viewer `_flingViewport`): the viewer's
`_touchFlinger` (unbounded controller, value = elapsed time via the
`_FlingClock` Simulation, since one controller carries one double and
the fling needs two axes) feeds FrictionSimulation deltas (drag 0.135
≈ UIScrollView; tolerance velocity 5 so the tail doesn't tick for
seconds) through `_grabPanBy` — extent clamping and zoom-window
spillover come free, and no ScrollActivity surgery (goBallistic was
rejected: stopping it on pointer-down risks killing list drags). The
tick self-stops when a nonzero delta moves nothing (all absorbers
pinned). Stopped beside every `_panFlinger.stop()` (raw pointer-down,
wheel, pinch/trackpad start) + dispose. Test gotcha
(editing_fling_test.dart): TestGesture stamps every event t=0 —
velocity reads 0.0 at lift; pass explicit `timeStamp:` to
moveBy/up or the fling silently never starts. (2) Touch long-press
context menu: `_MenuLongPressRecognizer` (editing_overlay.dart,
touch+stylus, RawGestureDetector between the overlay's MouseRegion
and Stack) — addAllowedPointer consults `_menuLongPressClaims(pos)`
(select mode: annotation hit or clipboard non-empty; form tool:
field hit) so a press with no menu to offer NEVER enters the arena —
text selection, marquees, and slow move drags keep their gestures
(claim-then-no-op would kill them). Handler mirrors _onSecondaryTapUp:
hit joins the selection (multi-selection intact), empty area = paste
menu at the point. `onShowAnnotationMenu` grew (pageIndex,
{pagePoint}) — paste needs them with no selection; the form branch
factored to viewer `_showFormFieldMenu` + overlay
`onShowFormFieldMenu`. Reader mode: viewer `_onLongPressStart`'s
range==null branch tries `_maybeAnnotationMenu` before
_clearSelection (tool null only; annotation → select+menu, empty +
clipboard → paste menu). (3) Form-field highlight:
`PdfViewer.highlightFormFields` (default TRUE, like Acrobat) →
`_FormFieldPainter` in the page Stack under the text-highlight
painter (wash + hairline border; border = fill color at alpha×2.5);
rects from `_formFieldRects` cached beside _annotCache (Widget
subtype, !hidden, !noView); auto-off while showAnnotations is false
(boxes would mark invisible fields). Theme:
`PdfViewerThemeData.formFieldHighlightColor` (used as given — carry
your own alpha; default 0x2E4D90FE). Preference `highlightFormFields`
+ example AppBar dynamic_form toggle — which overflowed the 800px
test window's AppBar by 35px: ALL example AppBar actions are now
VisualDensity.compact (the row was already at its limit; remember
this before adding another button). Pre-existing test failure fixed
in passing: 9bbfc87 (Ben, outside sessions) flipped
showThumbnailSidebar's default to true; editing_preferences_test
still expected false — suites had been red since. Tests:
editing_fling_test (3), editing_longpress_menu_test (6, incl. the
claim-gate regression "long-press on page text still selects the
word"), form_field_highlight_test (5).
Finger-toggle visibility (Ben: "still shown on non-touch displays"):
`controller.hasTouchInput` — true on iOS/Android/Fuchsia
(defaultTargetPlatform), elsewhere flips on the first TOUCH
pointer-down seen by the viewer's raw listener or a Listener wrapping
the toolbar (arming a tool is usually a session's first touch);
transient, not persisted (`noteTouchInput()`, idempotent notify). The
toolbar's touch_app button now also requires it. Test gotchas
(editing_touch_toggle_test.dart): resetting
debugDefaultTargetPlatformOverride in addTearDown is TOO LATE — the
binding's invariant check runs first; use `variant:
TargetPlatformVariant.only(...)`. A touch tap with ink armed draws a
DOT whose 800ms auto-commit timer outlives the test (!timersPending)
— touch in reader mode, then arm ink. flutter_test's default platform
is android, so existing touch_app-dependent tests pass unchanged.
Drop-in shells (Ben: out-of-the-box viewer/editor widgets; the example
must use them): `PdfReader` (pdf_reader.dart) and `PdfEditorView`
(dart_pdf_editor_view.dart), both exported — composed entirely from the
existing public parts. Shared package-private chrome in
shell_chrome.dart: `PdfShellBar` (header = spaceBetween Row inside
ConstrainedBox(minWidth: viewport) inside a horizontal scroll — a
Spacer can't live in an unbounded-width Row), `PdfShellViewOptionsButton`
(menu: show annotations / highlight form fields / page color…), toggle
keys 'pdf-shell-*'. Both shells: bytes in (the reader wraps them in a
never-edited PdfEditingController so thumbnails + pageAt caching work),
optional external viewer controller, optional shared
PdfEditingPreferences (owned instances disposed), `viewerTheme` wrap,
⌘F/Ctrl+F focuses the header search, panels keyed (the viewer-element
clobber lesson), panel visibility = persisted prefs gated by
`PdfReaderFeatures`/`PdfEditorFeatures`; swapping `bytes` (identity
compare) reopens in place via didUpdateWidget. PdfEditorView takes
bytes XOR an external PdfEditingController (then preferences must be
null — they come from the controller); `onDocumentChanged` fires per
revision, detected by bytes LENGTH (revisions are byte prefixes of one
buffer, so equal length == same revision). PdfEditingToolbar gained
`tools:` + showMarkup/showUndoRedo/showStyle/showFlatten (filtered
toolButtons return SizedBox.shrink; the signature button isn't a
toolButton — gated explicitly). PdfThumbnailSidebar gained
`allowPageEditing` (false = no _ReorderDragStartListener wrapper +
no footer delete — the reader's mode). Example app: ViewerScreen now
holds `Uint8List? _bytes` (no controller management) and swaps
PdfEditorView/PdfReader with an AppBar read-only toggle; search, page
number, author, view options, and panel toggles all moved into the
shell header — AppBar keeps copy/theme/demo/open. The pub-page README
leads with the example screenshot, which lives at REPO-ROOT
doc/dart_pdf_editor_example.jpg and is referenced by raw.githubusercontent
URL — out of the pub archive, renders once the repo is public. Tests:
pdf_shell_test.dart (16); the example tests passed unchanged (their
coordinates derive from the live viewer rect, so the 48px header is
absorbed).
Fast-scroll previews (Ben: "Bluebeam shows low-res content while
scrolling, ours is blank"): the render hold stays — held pages now
paint a small cached raster stretched to page size instead of blank
paper. `PdfPagePreviewCache` (preview_cache.dart, exported) — LRU
(capacity 300) of ≤200px-longest-side images keyed by page INDEX,
each entry remembering the page object it was rendered from
(`isFresh`); `imageFor` hands out `ui.Image.clone()`s so eviction/
clear can't pull pixels from a painting widget. Two fill paths:
`putFromPicture` (PdfPageView feeds the cache from the picture it
already interpreted, raster-thread downscale only — pages seen once
keep a preview after their state dies) and `renderPreview` (full
interpret, the background path). PdfPageView gained
`previewCache`/`previewIndex`: placeholder branch paints the preview
when one exists, the clone drops the moment a full raster lands, and
a cache listener refreshes blank pages when a prerender arrives.
Viewer: `PdfViewer.pagePreviews` (default true), `_previews` +
`_prerenderPreviews()` — one page at a time, nearest the viewport
first, SKIPPING pages within ~300px of the viewport (they render
fully on their own; prerendering them would interpret twice), bails
between pages whenever a scroll is live (hold up or settle timer
active) and is restarted by the settle timer; between pages it
`await SchedulerBinding.instance.endOfFrame` — deliberately NOT a
Timer (fake timers pend at widget-test end) and endOfFrame schedules
a frame when idle so the loop can't stall. `_previewAttempts`
(identity set) stops a throwing page from being retried forever.
Doc swaps: same geometry → `rebind` (entries re-point at the new
page objects WITHOUT re-render — re-interpreting 300 pages per pen
stroke is the alternative; off-screen edited pages stay briefly
stale and refresh when viewed), different document / pageColor /
showAnnotations change → clear. `PdfViewerController.
debugPreviewCache` (@visibleForTesting) is the test hook. Tests:
page_preview_test.dart (5: cache LRU/clones, held page paints
preview then full render, putFromPicture freshness, viewer
integration via debugPreviewCache + jump — full rasters held while
previews paint — and pagePreviews:false); render_hold_test's
mid-flight assertion is now "no FULL raster" (RawImage ≤200px =
preview, the feature working as intended). Verified live on macOS
against corpus AMT-SP-101.pdf (291 pages): mid-scrollbar-drag pages
show soft content, settle renders crisp.
Branding (Ben: logo/banner doubling as app icon): doc/logo.svg is the
master mark — 1024 rounded square (rx 224), Dart-blue gradient
#16BAFD→#0169B4, white dog-eared page, amber highlight bar, gradient
ink swoosh. doc/banner.svg = mark + wordmark + tagline on #202124; its
text is Helvetica Neue, so regenerate PNGs on macOS (rsvg-convert;
doc/logo.png 512, doc/banner.png 2560, doc/icon-1024.png = full-bleed
square via sed rx="224"→rx="0" — feed that to icon generators).
Example-app icons all regenerated from the masters (rsvg-convert +
magick): iOS full-bleed, macOS = rounded mark at 80.5% centered on a
transparent canvas (Big Sur grid; rx 224/1024 ≈ Apple's 185/824),
Android mipmaps / web Icon-* / favicon / Windows multi-res .ico =
rounded mark, web MASKABLE icons = full-bleed (the page's corners sit
at 39% radius — inside the 40% safe-zone circle). Banner heads the
root README (relative path) and the dart_pdf_editor README
(raw.githubusercontent URL, same pattern as the screenshot); web demo
manifest.json/index.html renamed to 'dart-pdf demo' (the template
theme_color was already #0175C2). Verified: macOS debug build
compiles the new appiconset into AppIcon.icns; example tests green.
Linux has no icon in the flutter template — none added.
Package rename #2 (pub.dev rejected `pdf_editor` at real publish —
"too similar to another active package: pdfeditor", an abandoned
3-year-old iOS plugin; similarity = names matching with underscores
stripped, and it's only checked server-side at publish, never by
dry-run): the Flutter package is now **dart_pdf_editor** (Ben picked
it; pdf_editor_flutter was rejected as risky — `flutter_pdf_editor`
exists and is active). Mechanical: git mv of the package dir, lib
entry (lib/dart_pdf_editor.dart), and doc/dart_pdf_editor_example.jpg,
then one global sed — which is NOT idempotent (the new name contains
the old; never re-run it) and had exactly one casualty:
lib/src/pdf_editor_view.dart is named for the PdfEditorView WIDGET and
keeps its name (the entry's export URI was reverted by hand). Class
names (PdfEditorView, PdfEditorFeatures) are unchanged. Residual-check
pattern: `git grep -P '(?<!dart_)pdf_editor'`. Publish order is
unchanged with dart_pdf_editor last; its dry-run re-verified.

Colour-lock split + translucent paper: two changes that let a host hide
the colour controls while keeping style controls. (1) Colour controls
split from style controls so a colour-locked markup session can HIDE
the colour changer while keeping stroke/opacity/font editable — the
single `styleControls`/`showStyle` flag bundled them. New
`PdfEditorFeatures.colorControls` (default true) →
`PdfEditingToolbar.showColor` (default true): gates the palette
swatches + 'More colors…' picker + eyedropper, and (threaded into
`_StyleMenu.showColor`) the text-box fill/border colour ROWS only —
the stroke/opacity/font sliders + font segmented button stay ungated.
The leading VerticalDivider shows if `showColor || showStyle`, and
`_StyleMenu` itself now mounts on `showStyle` alone. A host hiding the
colour changer passes `colorControls: false, styleControls: true`.
Migration note:
`styleControls: false` no longer hides the palette/picker/eyedropper
— set `colorControls: false` too (pdf_shell_test's "tool subset"
test updated). (2) Translucent `pageColor` now washes over white
paper: `renderPicture` paints an opaque white rect under the page
colour when `pageColor.a < 1.0` (opaque stays a no-op — no extra
draw), so a copy-type tint reads as a wash on paper, not composited
onto the (dark) viewer canvas; `PdfPageView`'s placeholder ColoredBox
gets the same white backing when translucent so it matches the
raster. Eyedropper/sampler inherit the wash for free (they rasterize
through the same path). Tests: pdf_shell_test (colorControls hides
changer / present by default), page_color_test ("a translucent paper
colour washes over white" — 0x80FF0000 reads ~(255,127,127) not
(255,0,0), the clean discriminator vs the old un-backed raster).
Shape resize line-width stretch (Ben: "annotation line width gets
stretched in the preview before returning to original"): the
move/resize drag previews via a rasterized appearance ghost scaled
from the resting rect onto the dragged rect, so a Square/Circle's
stroke thickened with the box and snapped back on commit — because the
editor REGENERATES the shape at a constant stroke width
(`_regenerateResizedAppearance`), not the §12.5.5 stretch. Fix mirrors
the existing FreeText `_textResizeStyle`/`wrapResize` path: overlay
`_shapeResizeStyle(rect, rotation)` (editing_overlay.dart) returns the
shape's draw params (ellipse flag, stroke/fill colour, page→view-scaled
border width, opacity) when the resize will regenerate — gated EXACTLY
like the editor's Square/Circle branch (normalAppearance present, no
cloudy /BE, no dashed /BS, has a stroke or fill) so preview never
disagrees with commit. Build computes `shapeResize` = live preview
(while a resize handle is dragging) ?? `_afterShapeResize` (the frozen
afterimage, held until rasterCurrent like the others), suppresses the
ghost when it's set, and hands the painter a `_ShapeResize` record;
painter `_paintShapeResize` strokes/fills the rect (inset by half the
view-space stroke width to match `_shapeContent`), rotated about the
rect centre by the resting angle, dimmed via saveLayer to the
appearance opacity. The `_panEnd` resize branch captures the style
BEFORE commit (the annotation's pre-resize border width is the constant
one) and freezes it as `_afterShapeResize` instead of
`_commitWithGhost`. Rotated shapes work for free (resizeSelectedLocal
already regenerates at the local box then re-rotates; the preview
rotates the same local box about its centre). Ink/stamps/embedded-font
free text still stretch (the ghost is correct there — they don't
regenerate). Tests: editing_shape_resize_test.dart (3 — the painter's
`shapeResize` via the dynamic cast: constant 2px stroke at 0.5px/pt
under a big widen, ellipse flag, ghost suppressed; commit keeps the
original borderWidth).
Reopen-where-you-left-off (Ben: "opening the same document should open
with the same viewport"): `PdfViewport` (viewport.dart, exported via
pdf_viewer) — a resolution-INDEPENDENT snapshot (page at the viewport's
top-left + fractional top/left into it + effective zoom), so it restores
at any window size; JSON-encoded. `PdfViewerController.captureViewport`/
`restoreViewport` + `PdfViewer.initialViewport`. State side
(`_captureViewport`/`_restoreViewport`/`_placeViewport`): capture
unprojects the viewport top-left to list space via the same (p−t)/s the
selection/visibleFraction code uses; restore sets `_layoutZoom` in build
(zoom≤1 → layout zoom, transform identity; zoom>1 → layoutZoom 1, the
zoom rides the transform) then places scroll+transform in a POST-FRAME
callback once the new extents exist (ExactExtentListView makes them
exact). `_pendingViewport` (from initialViewport in initState, or
restoreViewport before layout) is consumed in build alongside the
initialFit path — a saved viewport wins over initialFit. Persistence:
`PdfEditingPreferences.viewportFor`/`setViewport` — a per-document LRU
map (cap 64, key→PdfViewport) stored as one JSON string under
`documentViewports`; deliberately does NOT notifyListeners (called on
every scroll/zoom settle) and loads OUTSIDE the `_modified` guard
(write-mostly, merges by key) so a viewport saved before the disk read
survives (`_viewportsDirty` flush). Shells: `PdfViewportMemory`
(shell_chrome.dart, package-private) — listens to viewer
`viewportChanges`, captures into `_last` per tick (so flush works after
the viewer detaches) and debounces the disk write (400ms); `rekey` on a
bytes/documentId swap saves the outgoing doc and restores the incoming;
`flush` on dispose. `PdfReader`/`PdfEditorView` gained `documentId`
(null → `pdfDocumentKey(bytes)`, an FNV-1a sample hash); the editor only
remembers when it owns the session (bytes given, not an external
controller). Example passes `documentId: _title`, so the read-only
toggle and reopening a file both land where you were. Test gotchas
(viewport_test.dart, 12): re-pumpWidget with the same tree shape reuses
the State (didUpdateWidget, NOT initState) so initialViewport is skipped
— pump a blank tree between to force a fresh element; the thumbnail
strip's raster loop never settles without runAsync, so the shell test
turns thumbnails off and uses bounded pumps (no pumpAndSettle/
pumpEventQueue).

OCR / ingestion / Document-AI seams (interfaces, not engines — none ship
in-tree): three pluggable layers landed. (1) OCR: pure-COS injection
`PdfEditor.injectTextLayer(pageIndex, spans)` (ocr_editor.dart, part of
editor.dart) writes each `PdfOcrSpan` (text + user-space PdfRect bounds +
confidence) as one BT/Tj at render mode 3 (invisible) — font size = box
height, baseline = bottom + 0.25·h, and a `Tz` horizontal scale stretching
the run's natural width (measureStandardText) onto the box width, so the
em box (0.75 ascent / −0.25 descent the extraction quad reconstructs) lands
exactly on `bounds` — selection/search highlights track the word. Wrapped
in q/Q so Tr/Tz don't leak; embeds a WinAnsi base-14 font with explicit
/Widths (`_ensureOcrFont`, reused only when shaped exactly like ours, else
the interpreter's measurement skews the boxes). The interpreter already
emits mode-3 runs flagged `invisible` and CanvasPdfDevice early-returns on
them, so the layer is selectable/searchable/extractable but paints nothing.
The raster-facing half is in dart_pdf_editor (needs ui.Image, so it can't
sit in pdf_document below the layering line): `PdfOcrEngine` (abstract,
raster→spans), `PdfOcrPageImage` (the rendered page + geometry;
`userSpaceRect(pixelRect)` inverts the SAME transform renderPicture builds
— crop box + /Rotate aware — via PdfMatrix), and
`PdfEditor.applyOcr(pageIndex, engine)` = renderImage → engine.recognize →
injectTextLayer. (2) Images→PDF: `PdfImageDocument.fromImages/fromImageBytes`
(image_pdf.dart) — one page per PNG/JPEG via CosDocumentBuilder +
PdfEmbeddableImage (lives in pdf_document, not on the builder, because
pdf_cos knows nothing about image embedding); page sized image-px·72/dpi.
toXObject(builder.add) registers the SMask first (lower obj number) — fine.
(3) Seams: `PdfImportSource` (pdf_document, Office/DOCX→PDF bytes,
host-provided, interface only) + `PdfDocumentContext.of(document)`
(pdf_graphics document_ai.dart — concrete read adapter: per-page reflow
text, fields with values, annotation summaries, toJson/toPromptText) and
abstract `PdfDocumentActionSink` (the write side, host-provided). Tests:
pdf_graphics ocr_layer_test.dart (selectable/searchable + rect on bounds +
invisible flag via a recording device) and document_ai_test.dart;
pdf_document image_pdf_test.dart + import_source_test.dart; dart_pdf_editor
ocr_test.dart (userSpaceRect mapping; applyOcr with a fake engine —
invisible proven by the OCR'd raster being byte-identical to the original).

Stretch-flip (Ben: "allow inverting the annotation if stretching past
the 0 point"): a resize handle dragged past the opposite edge now
inverts the annotation instead of clamping at the minimum. `_resizedRect`
(editing_overlay.dart) lets the dragged edge cross its anchor — it
returns `(normalizedRect, flipX, flipY)` (the rect stays positive so
chrome/ghost layout is untouched; the flip rides booleans), keeping
|size| ≥ minSize on whichever side of 0 it lands so the box never
collapses to a line; aspect-locked (Shift) drags keep the old
clamp-at-minimum and never flip. Flip flows commit-side through
`resizeSelected`/`resizeSelectedLocal({flipX, flipY})` →
`PdfEditor.resizeAnnotation`/`resizeAnnotationLocal({flipX, flipY})`. For
the §12.5.5 STRETCH path the mirror is a reflection about the BBox center
premultiplied into the form /Matrix (`_flipFormArtwork`) — reflection
maps the BBox onto itself so the BBox→/Rect fit (and thus /Rect) is
unchanged, only the interior flips — and the point arrays (/InkList/
QuadPoints/L/Vertices/CL) reflect about the /Rect center to match
(mapX/mapY gained a flip branch). For the ROTATED local path the flip
folds straight into the local scale as a NEGATIVE factor (sx/sy), which
mirrors both the appearance /Matrix and the mapped points about the local
center in one shot — no separate matrix write needed (a flip commutes
with the scale). REGENERATE types (Square/Circle/FreeText/Line) ignore
the flip: a mirrored rectangle/ellipse is identical and text stays
readable. Live preview + afterimage mirror too: `paintAnnotationDragPreview`
gained `flipX`/`flipY` (negative scale about the box center for the
rotated branch, about the appropriate edge for the page-axis branch);
the painter carries `ghostFlipX`/`ghostFlipY` and the afterGhost record +
`_commitWithGhost` carry the flip so an inverted resize stays inverted
until the raster lands. Tests: annotation_editor_test (flipX mirrors the
matrix + /InkList about the rect center; a rotated double-flip restores
the geometry — each flip is its own inverse) and editing_rotate_test (a
handle dragged past the opposite edge bakes a = −1 into a Stamp's form
matrix). Gotcha: a rotated local-frame flip test must size `localTo`
from the appearance quad's edge lengths (not the page /Rect, whose dims
are swapped under rotation) or the "flip" silently resizes too.

Interactive form fill in reading mode (Ben: "users need to enter text
into form fields, and interact with check boxes, buttons, drop-downs"):
filling was already complete behind the form-AUTHORING tool
(`PdfEditTool.form`) — this surfaces it in plain reading / default mode
so a reader clicks a field and types, the way Acrobat/Chrome/Preview do,
with no tool to arm. `FormInteractionLayer` (editing_form_layer.dart) is
mounted per page by `_PdfViewerPage` over the editing overlay: it places
a per-field `GestureDetector` tap target over each visible widget rect
(from `PdfEditingController.formWidgetsOn(page)`), so only the field
rects are hit-testable — the rest of the page still scrolls, selects
text, and follows links. Tap routing reuses the controller fills
(setFormFieldText / toggleFormCheckBox / setFormRadioValue /
setFormChoiceValue / setFormButtonImage); text fields open an inline
`TextField` (key 'pdf-form-text-editor', /DA font+size, multiline,
Enter/blur/tap-outside commit, Escape cancels via its own
CallbackShortcuts), the committed value freezes as a pageColor-washed
afterimage until the new raster lands (same `rasterCurrent` signal the
overlay uses). Gating: `PdfViewer.interactiveForms` (default true) +
`showAnnotations`; active only when `editing == null` (reader) or the
tool is null/select — a drawing or the form-authoring tool owns the
whole page, so the layer leaves the tree (suppressed, not just inert).
Two controller channels: the editor passes `editing:` (fills persist as
revisions, onDocumentChanged fires); the read-only reader passes the new
`PdfViewer.formController:` (a standalone session — forms fill but
annotation move/resize/delete never turn on), `formController = editing
?? widget.formController`. The viewer's focus-steal and the inner
overlay-Stack gate both consult `editing ?? formController`
(`_textEditController`) so the reader's inline editor keeps focus and
the layer mounts without an `editing` controller. `PdfReader` gained
`PdfReaderFeatures.fillForms` (default true) and now wraps its viewer in
a `ListenableBuilder(_session)` so a fill's revision repaints (filled
values live in the session for the widget's life; surfacing them as
bytes needs PdfEditorView). Tests: editing_form_interactive_test.dart
(11 — text/checkbox/radio/dropdown fills with no tool armed, reader path
via formController, Escape cancel, interactiveForms:false + drawing-tool
suppression + select-tool keeps it, PdfReader mounts/omits the layer).
Gotchas: a commit tap must land inside the 800x600 viewport — view(450,
620) not view(450,300) (y=643px is off-screen, the tap silently misses
and the editor never closes); the choice /V stores the EXPORT value ('L'
not 'Large'); don't tap-test suppression with the ink tool armed (the
dot's 800ms auto-commit timer trips !timersPending) — assert the layer's
absence with find.byType(FormInteractionLayer) instead.

Shape-style batch (Ben's comment list): seven features. (1) Line type
(dash) for ALL stroked subtypes: the model's boolean `dashed` collapsed
into an explicit `List<double>? dashPattern` (null = solid) threaded
through `_borderStyle`/`_shapeContent`/`_lineContent` and every creator
(addSquare/addCircle gained it; addLine/addPolyLine/addPolygon/
addMeasurement swapped `dashed:`→`dashPattern:`), so Square/Circle can
now be dashed too. Dashed shapes REGENERATE on resize/restyle instead of
falling back to the §12.5.5 stretch — `pdfCanRestyleAnnotation`'s
Square/Circle `/BS /D`-refusal dropped (cloudy `/BE` still stretches),
`_regenerateResizedAppearance` and `restyleAnnotation` read
`annotation.borderDash` and pass it back (the actual array survives a
resize now, not a width-recomputed default; `_dashPattern` helper gone).
`restyleAnnotation` grew a `(List<double>?,)? dashPattern` sentinel.
The enum lives in the editing layer (`PdfLineStyle` in
editing/line_style.dart, exported): solid/dashed/dotted/dashDot →
`dashArray(width)` (width-scaled, 2pt floor) and `ofDashArray()` (classify
a stored array back by segment count + dash:gap ratio). Preference
`dashedStroke` (bool) became `lineStyle` (persisted by name, migrates the
old bool); controller keeps a `dashedStroke` compat shim (the drag
previews still think in dashed/solid) plus `lineStyle`, `_lineDashPattern`
(= lineStyle.dashArray(strokeWidth), fed to every creator),
`canSetLineStyleSelected`, `selectedLineStyle`, and `restyleSelected(
lineStyle:)` (per-annotation dash recomputed at its own — or the
just-changed — width). UI: the toolbar `_StyleMenu`'s old dashed
SwitchListTile is now a `pdf-line-type` DropdownButton (shows for shapes
AND a line/shape selection, restyles live); `_StyleFields.dashed`→
`lineType`; the properties panel got a matching `pdf-prop-line-type`
dropdown (`_lineStyled` set). (2) Fill polygons: `PdfEditor.addPolygon`
already wrote `/IC` but the controller's `addPolygon` never passed a fill
— now threads `shapeFillColor`; `canFillSelected` + properties `_fillable`
+ `_stroked`/`_translucent` gained 'Polygon'; the shapes-group/selection
`shapeFill` field covers the polygon tool; the live poly preview fills via
the new painter `dragPathFill`, and the commit afterimage (`_afterPath`)
carries the fill so it doesn't blink. (3) Stroke/opacity drag readout:
`_styleReadout()` + a generalized `_buildReadoutChip(key:)` (the measure
readout chip, reused) shows "{w} pt · {n}%" near the cursor while drawing
a rect/ellipse/line/arrow/poly (`_strokeTools`) or resizing a stroked
selection — key `pdf-style-readout`, suppressed for measure tools (their
own readout shows). (4) Cross-page drag: a single-selection move dropped
over another page re-homes the annotation there instead of leaving it
off-crop-box behind the neighbour. Overlay tracks `_moveCurrentGlobal`
(drag-end carries no position) and, on commit, asks the viewer's new
`onResolvePagePoint` callback (global→list-space via `_listSpaceKey`'s
RenderBox, then `_pagePointAt`) for the drop page; if it differs,
`controller.moveSelectedToPage(page, dx, dy)` (capture keepName +
removeAnnotation source + pasteAnnotation target, one undo, appended on
top, selects the re-homed slot). Grab-relative: dx/dy = drop − grab so
the held interior point stays under the cursor. (5) Paste at cursor: the
viewer tracks `_lastPointerLocal` (hover + pointer-down); ⌘V resolves it
to a page point and `pasteAnnotations(page, at:)` there (cascade fallback
when no pointer seen). (6) Select toggle-off: tapping the armed Select
chip in the toolbar (`_openGroupTap`, group.id=='select' && tool==select)
sets `tool=null` + `_openGroupId=null` → reader mode; re-tap re-arms.
Tests: pdf_document annotation_editor_test/annotation_restyle_test updated
(dashed shapes now regenerate, not stretch; `dashed:`→`dashPattern:`),
editing_shape_styles_test.dart (10 — line style create/restyle/classify,
polygon fill, moveSelectedToPage + undo, select toggle, drag readout),
editing_clipboard_test's ⌘V test now hovers before pasting. Gotchas: the
line-type Row label must be `Expanded` (a fixed Text + Spacer + the
"Dash-dot" dropdown overflows the 268px popup under Ahem); the drag-
readout widget test ends with pump(400ms) to drain the double-tap timer;
14 Ghent render-baseline tests fail on this machine independent of these
changes (pre-existing raster diffs, confirmed by stashing).

Bottom-sheet panels on small screens (Ben: "the panels and strips should
be bottom sheets on small screens"): below `pdfShellCompactWidth` (700,
the existing compact threshold) the shells float the side panels and the
thumbnail strip up from the bottom instead of docking them — a docked
280px panel crowds the page out on a phone. `pdfShellUseBottomSheets(
constraints)` + `pdfShellBottomSheets(sheets)` + `PdfPanelBottomSheet`
all live in shell_chrome.dart (package-private). Each panel
(PdfThumbnailSidebar/PdfAnnotationSidebar/PdfAnnotationPropertiesPanel/
PdfSearchResultsPanel) gained a `bottomSheet` bool (default false): when
true it fills its parent (no fixed-width SizedBox), drops the side resize
grip, and the scrollbar/list clearance loses the grip width — factored
through local `showGrip`/`onLeftEdge` flags so the grip-side scrollbar
inset goes to 0. The thumbnail strip is the exception: it keeps its
preferred-width tile column `Center`ed in the wider sheet rather than
stretching one giant thumbnail to phone width (raster resolution, reorder,
and delete all keep working unchanged); a grid/horizontal strip was
rejected as too invasive for `_PageTile`'s AspectRatio layout.
`PdfPanelBottomSheet` is the chrome: rounded top, a drag handle that
swipes down to dismiss (onVerticalDragEnd primaryVelocity > 200) plus a
titled header with a close button (keys 'pdf-shell-<panel>-sheet-close');
`pdfShellBottomSheets` lays the active sheets out in a bottom-anchored
Column (Positioned.fill + Align.bottomCenter, so the clear area above
keeps scrolling/tapping the page through to the viewer), each `Flexible`
+ capped at 0.55 of the content height — one sheet rises to 55%, several
share the area evenly without overflowing off the top. The shells build
panel closures `panel({required bool bottomSheet})` and switch on
`useSheets`: docked panels go in the Row (`!useSheets`), sheet-wrapped
ones go in `pdfShellBottomSheets`; closing a sheet flips the panel's
visibility preference off (showThumbnailSidebar/showAnnotationSidebar/
showPropertiesPanel/showSearchResultsPanel). PdfEditorView hides the
floating toolbar while a sheet is open (`features.toolbar &&
sheets.isEmpty`) since the sheet covers the bottom; PdfReader (thumbnails
only) grew a Stack around its viewer Row to host the overlay. The
thumbnail compact default (`pdfShellShowThumbnailSidebar` — closed on
compact unless an explicit pref) is unchanged; an explicit on shows the
strip as a sheet. Tests: pdf_shell_test.dart +4 (compact toggles open a
sheet, the close button hides it + clears the pref, wide stays docked
with a resize grip, the reader strip is a sheet). Gotcha: the default
800x600 test surface is ABOVE 700, so existing shell tests stay docked
untouched; `compactScreen` (600x800) drives the sheet path.

Form-tool field manipulation (Ben: "the form tool should allow
manipulating the forms — size, field name — since reading mode already
fills them"): with read-mode `FormInteractionLayer` owning fill, the
`PdfEditTool.form` tool now SELECTS widgets for move/resize/rename on a
single tap, and DOUBLE-tap fills (Ben's pick of the tap-fork). Widgets
were excluded from the generic selection (`_unselectable` has 'Widget')
because the §12.5.5 stretch breaks a field — so manipulation goes
through form-aware paths instead. Controller (editing_controller.dart):
`selectableWidgetAt`/`selectFormWidgetAt` (mirror the annotation hit
test but for Widget subtype; read-only fields ARE selectable — readOnly
gates VALUE edits, not geometry; still respects isAnnotationEditable for
/F Locked + host predicate), `canResizeSelected` adds a Widget branch
gated on `tool == form` (arming another tool drops the affordance),
`resizeSelected`/`resizeSelectedLocal` route Widgets to `_resizeWidget`
→ `e.resizeFormWidget(name, widgetIndex, to)` (field re-resolved by name
inside apply, like the fills; `_widgetFieldForSlot` maps the /Annots
slot → (field name, widget index) by dict identity), and `deleteSelected`
under the form tool removes the whole FIELD (`e.removeField`, one
revision) so /AcroForm /Fields never dangles — never `removeAnnotation`
on a widget. Move reuses the generic `moveAnnotation` (translation; the
/AP follows /Rect via BBox→Rect, no regen). Editor (form_editor.dart):
`resizeFormWidget` rewrites the widget /Rect then REGENERATES the
appearance at the new size — text/choice re-lay their value via
`_regenerateVariableText` (so the box refits instead of scaling the
font), checkBox/radio via new `_regenerateButtonStates` (rebuilds /AP /N
preserving each state name, unlike `_ensureButtonAppearances` which
skips existing states; checkmark draw factored to `_paintCheckMark`);
push-button/signature/unknown keep their /AP (only /Rect moves —
push-button images would otherwise be lost). Overlay (editing_overlay):
`_onTapUp` form branch → `selectFormWidgetAt`; `_onFormTap` renamed
`_fillFormFieldAt(local, global)` and driven by `onDoubleTap`
(`_onDoubleTapDown` stashes `_doubleTapDownDetails`; double-tap wired for
the form tool alongside the poly tool); `_panStart` form branch routes a
press on a resize handle or the selected widget body to `_selectPanStart`
(the existing move/resize machinery — selection chrome + handles appear
automatically once `canResizeSelected` is true), a press on another
widget selects-and-moves it in one drag, and only truly empty page area
drags out a new field; hover cursor shows move/resize/click/precise
accordingly. The resize drag previews via the generic stretch ghost then
snaps to the regenerated appearance on raster (same as the FreeText
fallback) — no widget-specific preview. Single-tap select costs the
~300ms double-tap delay (inherent to enabling onDoubleTap) — Ben's
accepted trade for the fork. Tests: pdf_document form_fill_test (+3:
resize rewrites /Rect + re-lays the value at the new BBox, checkbox mark
regenerates at the new size, missing-field no-op); dart_pdf_editor
editing_form_test — the OLD single-tap-fills widget tests now DOUBLE-tap
(new `doubleTap` helper: tap, pump 60ms, tap, pump 400ms), plus new
"single tap selects (no fill)", controller move/resize/delete round-trip,
and the `canResizeSelected` tool gate; the "drag on a widget" test now
asserts the widget MOVED (it used to assert nothing happened). Toolbar
tooltip is now 'Form fields — tap to select, double-tap to fill, drag to
add' (pdf_shell/toolbar tests that find it by tooltip updated).

Bold/italic text-box fonts (Ben: font selection + outline/fill in the
style popup, expand font choices): `PdfStandardFont` grew from 3 to all
12 base-14 text faces — `PdfStandardFontFamily {sans, serif, mono}` is
the family axis, orthogonal to `isBold`/`isItalic`; `styled(family,
{bold, italic})` + `withBold`/`withItalic` pick a variant. New AFM width
tables (`timesBoldWidths`/`timesItalicWidths`/`timesBoldItalicWidths`;
Helvetica oblique reuses upright widths, Courier stays flat 600).
Resource names: existing `Helv`/`TiRo`/`Cour` kept for the regular faces
(backward-compatible /DA), variants get detectable names (`HelvBold`,
`TimesBoldItalic`, `CourBoldObl`…) — `tryFromName` now detects family by
substring AND bold (`bold`) / italic (`italic`/`oblique`/`obl`), so our
short /DA names and foreign producers' both round-trip with style. The
Times variants use `Times*` (not `Ti*`) names so `times`-substring family
detection fires. Rendering was already style-aware: canvas_device's
`_styleFor` keys FontWeight/FontStyle off `name.contains('Bold')`/
`'Italic'`/`'Oblique'`, so the variant /BaseFont paints correctly with no
font-engine change (verified by editing_font_render_test: timesBold lays
more ink than times, italic renders). UI: shared package-private
`FontStyleToggles` (editing_font_controls.dart, NOT exported) — a B/I
toggle pair that flips one axis of the current family; the toolbar
`_StyleMenu` now has a family SegmentedButton (Sans/Serif/Mono, bound to
`.family`) + a 'Style' row of toggles, and the properties panel's font
dropdown switched to a family dropdown + the same toggles. The font chip
label shows the suffix (' B'/' I'/' BI'). Properties panel also gained
the missing 'Outline' swatch for FreeText (`pdf-prop-text-border` →
`restyleSelectedText(border:)`; the toolbar already had 'Text border').
The two inline-editor `_uiFamily` switches (overlay + form layer) map by
`.family` now and set fontWeight/fontStyle so the live editor previews
bold/italic. Toggle keys 'pdf-font-bold'/'-italic' (toolbar) and
'pdf-prop-font-bold'/'-italic' (panel). Tests: annotation_editor_test
(12-variant coverage, name round-trips with style, bold-italic /BaseFont
+ /Widths), editing_text_edit_test (toolbar B/I toggles + family keeps
style), editing_properties_test (panel B/I toggles + the outline row),
editing_font_render_test (end-to-end raster). The existing 'Serif'/'Mono'
tap tests still pass — tapping a family with no B/I set yields the base
variant.

Insert image (Ben: "allow inserting an image into the PDF"): a new
`PdfEditTool.image` inserts a PNG/JPEG as a /Stamp annotation, so it
inherits select/move/resize/rotate/delete for free. pdf_document:
`PdfEditor.addImageStamp(pageIndex, rect, PdfEmbeddableImage, {opacity,
author, name})` (annotation_editor.dart) registers the image XObject via
`image.toXObject` and writes an appearance that `cm`-maps the unit image
onto the rect (BBox = rect, so the §12.5.5 fit is the identity);
`_resources` gained an `xObject:` param. CRITICAL: the stamp carries NO
/Contents, so `pdfCanRestyleAnnotation` returns false — the restyle path
(`_regenerateStyledAppearance` case 'Stamp') would regenerate a /Stamp as
a TEXT stamp and wipe the picture; resize falls through to the stretch
path (Stamp isn't in `_regenerateResizedAppearance`), which scales the
form matrix so the image scales with the box, and rotate bakes the matrix
like any stamp. Controller (editing_controller.dart): `placeImage(page,
x, y, bytes, {maxSize: 200})` (tap — aspect-preserving box clamped to 90%
of the crop box, centered on the tap) and `addImageInRect(page, box,
bytes)` (drag-out — fits the image within the dragged box); both decode
ONCE (`PdfEmbeddableImage.decode`, junk → false, no revision) and reuse
the decoded image in the apply closure. UI: `PdfImagePicker = Future<
Uint8List?> Function(BuildContext)` (text_prompt.dart), threaded
`PdfViewer.imagePicker` → _PdfViewerPage → EditingPageOverlay (overlay
`_onTapUp`/`_commitRect` image branches await the picker then call
place/addInRect); `PdfEditorView.imagePicker`; toolbar Insert group gained
an Icons.image_outlined button. Example: `_pickImage` (file_selector,
reuses `_imageTypeGroup`) wired into PdfEditorView. No afterimage (tap-
placed, like text stamps — the picker dialog covers the re-render). Tests:
pdf_document image_stamp_test.dart (4 — XObject in appearance, not
restyleable, resize stretches keeping /Img0, opacity→ca) and
dart_pdf_editor editing_image_test.dart (7 — placeImage aspect/clamp,
addImageInRect fit, junk reject, viewer tool tap runs picker / cancel /
no-picker). Pre-existing example/test failures (7, Text("0") duplicate
+ others) are unrelated — present without this change.

Per-tool style memory (Ben: "save the styling preferences per annotation
tool"): each annotation tool now remembers its own colour, stroke,
opacity, font, line style/endings and fills, so the yellow highlighter
stays yellow while ink stays black across tool switches and sessions.
The live single values in `PdfEditingPreferences` stay the source of
truth the creation methods read (unchanged); on top of them sits a
per-scope snapshot map `_toolStyles` (persisted as one JSON blob under
`toolStyles`, colours as ARGB ints, enums by name). `beginStyleScope(
scope, fields)` activates a scope — restoring its saved style into the
live values by driving the public setters under a `_restoringScope`
guard (so the load doesn't re-record) — and while a scope is active every
style setter ALSO records its field into the slot via `_recordScoped`
(only the `fields` the scope remembers). The controller's `tool` setter
calls `beginStyleScope(_styleScopeKey(tool), _styleScopeFields(tool))`:
key = the tool's name for the styled creators (ink/eraser/shapes/lines/
measure/freeText/note/stamp), null for select/content/form/redact/
signature (signature shares the global colour, which `_drawSignature`
seeds from the drawn ink). The per-tool `fields` mirror each tool's
toolbar strip — ink keeps stroke not endings, rectangle keeps fill not
font, freeText keeps font + box colours, etc. Markup arms no tool, so
`PdfEditingController.useMarkupStyleScope()` scopes 'markup' {color,
opacity}; the toolbar calls it when the Markup strip opens
(`_openGroupTap`) and when the mobile sheet's markup tab is selected.
A tool with no saved slot inherits the current live value (no restore),
so first use of each tool picks up the last-used style — independent
thereafter. Tests: editing_preferences_test +4 (each tool keeps its own
style, markup highlighter colour, no-slot inherits, persistence into a
fresh session). The 14 Ghent render-baseline failures are pre-existing
on this machine, unrelated.

Thumbnail multi-select (Ben: "shift click to multi select pages in the
thumbnail strip"): the strip gained a page selection alongside the
annotation selection. Controller (editing_controller.dart, "page
selection" section): `_selectedPages` (a Set<int>) + `_pageSelectionAnchor`
(the last plain/⌘ click — what a shift-click extends from); getters
`selectedPages` (ascending), `hasPageSelection`, `selectedPageCount`,
`isPageSelected`; gestures `selectPage` (plain — single + re-anchor),
`togglePageSelection` (⌘/Ctrl — add/remove + re-anchor), `selectPageRange`
(shift — contiguous anchor..index, replacing, anchor stays so a further
shift re-extends from the same origin), `selectAllPages`,
`clearPageSelection`; bulk ops `removeSelectedPages` (editor `removePages`,
one undo, refused when it would empty the doc — at least one page must
remain) and `exportSelectedPages` (= `exportPages(selectedPages)`, null
when empty). Every structural page edit (move/remove/insert/addBlank)
clears the page selection too (indices shift), beside the existing
`_selected.clear()`. UI (editing_thumbnails.dart): `_PageTile._onTap`
reads HardwareKeyboard — shift → selectPageRange, ⌘/Ctrl →
togglePageSelection (neither navigates, so a selection builds without the
viewport jumping), plain → selectPage + jumpToPage; a selected tile gets a
primary-tinted rounded chip behind the thumbnail (a color-only
BoxDecoration on the tile's Container adds no padding, so per-tile layout
and `_estimateOffset` are unchanged — don't switch it back to Padding).
When `selectedPageCount > 1` a selection bar shows above the list ('N
selected' + export (keys 'pdf-thumbnail-export-selected', only with
onExportPages) + delete ('pdf-thumbnail-delete-selected', only with
allowPageEditing) + clear ('pdf-thumbnail-clear-selection')); a single
selection is just the navigation cursor (the per-tile delete handles it).
Tests: editing_page_ops_test.dart — a "page selection" controller group
(11) + strip widget tests (shift-click range→delete, ctrl-click toggle);
widget tests set tester.view 800×1400 so the lazy list builds every tile,
and drive modifiers with sendKeyDownEvent/sendKeyUpEvent(LogicalKeyboardKey
.shift/.controlLeft) around the tap.

Count tool / check-marks (Ben: "a check symbol they can place, like
Bluebeam's count tool"): `PdfEditTool.count` — tapping drops a check-mark
and keeps a running tally. pdf_document: `PdfEditor.addCheckMark(pageIndex,
rect, {color, opacity, author, name})` (annotation_editor.dart) writes a
tick (`_checkMarkContent` — a stroked 3-point path, round caps, centered in
the rect's largest square so it stays proportional at any aspect) as a
/Stamp with /Name /Check, so it inherits select/move/resize/rotate/delete
for free; carries NO /Contents, so `pdfCanRestyleAnnotation` is false (the
text-stamp restyle would regenerate over it, like image stamps).
`PdfAnnotation.iconName` (/Name, distinct from `name` = /NM) +
`isCheckMark` (Stamp + iconName 'Check'). Controller (editing_controller):
`placeCheckMark(page, x, y, {size = checkMarkSize=18})` — centers a square
mark on the tap, clamped to the crop box, following the selected
color/opacity; `checkMarkCount` is the live document-wide tally
(`_countCheckMarks` walks the pages counting isCheckMark, cached per
revision via `_checkMarkCount`, invalidated in `_invalidateElements`, so
undo/redo/delete keep it accurate). Per-tool style scope 'count' {color,
opacity}. Overlay: count is a tap-place tool (`_onTapUp` →
placeCheckMark; `_onPanStart` breaks like note/content). Toolbar: Insert
group gains an Icons.task_alt 'Count' tool, and `_insertToolExtras` shows
a tally Chip (key 'pdf-count-tally') while armed. Tests:
pdf_document/test/check_mark_test.dart (4) + dart_pdf_editor/test/
editing_count_test.dart (6 — placement/clamp/colour, cross-page tally with
undo/redo, viewer tap drops marks). The 14 Ghent render-baseline failures
are pre-existing on this machine, unrelated.

OCR engine plugin (Ben: "support SOTA OCR + docs to set it up"): the OCR
seam (`PdfOcrEngine`/`applyOcr`, dart_pdf_editor) now has a shipping
backend — a new workspace package **`packages/pdf_ocr_vlm`**
(`VlmOcrEngine implements PdfOcrEngine`). It POSTs each page raster (PNG
via `ui.Image.toByteData(format: png)`, no extra deps) to an out-of-process
HTTP OCR service and maps the returned pixel boxes back through
`PdfOcrPageImage.userSpaceRect`. Two paths: the default ctor speaks a small
documented JSON contract (`{image,width,height} → {spans:[{text,bbox,
confidence}]}`; lenient parser accepts spans/words/lines/results/regions/
cells/data, bbox/box/rect or polygon/poly/points/quad, confidence/score/
conf), and `VlmOcrEngine.dotsOcr(...)` targets a vLLM server hosting
`rednote-hilab/dots.ocr` (current SOTA OSS doc-OCR VLM) over its
OpenAI-compatible chat endpoint with NO adapter — `openAiChatRequestBody`
sends the image+layout prompt, `dotsOcrResponseParser(categories)` reads
the JSON-array-in-message-content (strips ```json fences) and keeps
text-bearing layout categories (`dotsOcrTextCategories`; Picture/Table
skipped). `requestBody`/`responseParser` typedefs are the override seams
for cloud VLMs / PaddleOCR / Tesseract. CRITICAL: `PdfOcrSpan` lives in
pdf_document (part of editor.dart), so the package depends on AND imports
pdf_document, not just dart_pdf_editor. Tests (vlm_ocr_engine_test.dart, 5)
use http's MockClient — no network/GPU: simple-contract request shape +
pixel→user mapping, dots.ocr OpenAI shape + category filter, applyOcr
end-to-end selectable layer, non-200 → VlmOcrException, polygon/varied-key
parsing. README is the setup doc (SOTA landscape table, Docker/vLLM
one-liner, the JSON contract + a ~30-line FastAPI/PaddleOCR reference
adapter, cloud-VLM override example). Added to the root workspace list;
deps http ^1.2.0. Not in the first-publish order yet (Ben's call).
Example-app wiring (Ben: "with a way to supply creds or login"): main.dart
'More actions ▸ Add OCR text layer…' (enabled iff a session tab is active)
opens `_OcrSettingsDialog` (keys 'ocr-endpoint'/'ocr-model'/'ocr-api-key'/
'ocr-run' — endpoint + model + optional bearer token, obscured, plus a
'How to set up an OCR server' link to the package README), then runs
`applyOcr` over every page behind `_OcrProgressDialog` (ValueNotifier page
counter) and opens the result in a NEW tab '$title (OCR)'. Creds live in
`_ViewerScreenState` (`_ocrEndpoint`/`_ocrModel`/`_ocrApiKey`) for the
app's life — the API key is kept in MEMORY ONLY, never written to disk (so
the example needs no shared_preferences for it). dep pdf_ocr_vlm ^0.1.0.
The 9 example test failures are pre-existing on this machine (raster/
headless) — identical set with and without this wiring, zero regressions.

On-disk cache (Ben: "implement on-disk cache to further optimise the
library; minimal deps, must work everywhere"): a pluggable persistent
cache layered across the stack, matching the existing host-seam pattern
(PdfOcrEngine/PdfImportSource) — the library never touches storage itself
(dart:io stays banned below the Flutter layer, web keeps working), the
host supplies a backend and the cache logic lives on top in pure Dart.
Core (pdf_document, web-safe, zero new deps): `PdfCacheStore` (abstract
async key→bytes: read/write/delete/keys/clear) + `PdfMemoryCacheStore`
(the everywhere default + test double, copies buffers on write);
`PdfDiskCache` wraps any store with versioning (a `version` mismatch
purges the namespace on first use — bump it on a format/renderer change
that invalidates cached bytes), a byte-budget LRU (`maxBytes`, default
64MB, evicts least-recently-used; an entry bigger than the whole budget
is skipped), and a PERSISTED manifest (key→size + LRU order stored under
a reserved key, so eviction survives sessions). The version is NOT part
of the key (it lives in the manifest) so a bump physically reclaims old
bytes instead of orphaning them under a stale prefix. All ops serialize
through an internal Future queue (the viewer fires many at once) and are
best-effort — a throwing backend degrades to a miss, the queue keeps
running (`_run` catches per-action, keeps the chain alive). `pdfContentKey`
(FNV-1a over length + ~4KB sampled bytes) is the pdf_document-level
content key (the editor's existing `pdfDocumentKey` stays; hosts with a
path/URL pass that). Text layer (pdf_graphics): `pdfEncodePageText`/
`pdfDecodePageText` — a compact little-endian binary codec for PdfPageText
(magic+version word; pageIndex, full text, per-run text/startIndex/6×f64
transform/width/4×f64 bounds), decode returns null on any mismatch (a
miss). GOTCHA: BytesBuilder must be copy:true — the reused 8-byte scratch
buffer is overwritten between writes, so copy:false retained live views
and serialized garbage. `PdfPageTextCache(diskCache)` memoizes extraction
(the same heavy content-stream walk rendering pays) keyed by
documentKey+page: `get(docKey, page, compute)` reads on a hit, runs+caches
compute on a miss. Wired into the viewer via `PdfViewer.textCache` (+
threaded through `PdfReader`/`PdfEditorView`): `_searchAllPages` routes
each page through `_extractText`, which checks the per-revision in-memory
`_textCache`, then the persistent cache, then a fresh extraction. GUARDED
on `editing == null` AND a non-null `documentId` — an edit session mutates
page content, so its text stays in-memory-only (the persistent cache is
content-keyed and would otherwise go stale after an edit); the reader,
whose document is static, reads search text back from disk on a cold
reopen. Form fills don't affect page-content extraction, so the reader's
formController doesn't compromise the guard. Raster layer (dart_pdf_editor): `PdfRasterCache(diskCache,
{documentKey})` persists the SMALL low-res page previews (≤200px, tens of
KB PNG each — not full rasters; modest budget, big win) so a cold reopen
paints soft navigable content immediately instead of blank paper. PNG via
`ui.Image.toByteData(format: png)` / decode via `ui.instantiateImageCodec`
(no extra dep); empty documentKey no-ops (an un-bound cache is harmless);
`forDocument(key)` derives a per-file view sharing one store+budget.
Wired into `PdfPagePreviewCache` (new `disk` field): write-through in
`_store` (fire-and-forget — the encode is a raster-thread readback, a slow
store must never stall rendering), and `loadFromDisk(pages)` primes the
in-memory cache from disk (skips pages with a fresher in-session entry,
binds loaded entries to the current page objects so the prerender treats
them as done and the on-screen full render still replaces them). Viewer:
`PdfViewer.rasterCache` + `documentId`; `_bindRasterCache()` sets
`_previews.disk = rasterCache.forDocument(key)` and post-frame
`loadFromDisk(_pages)`. The disk key folds in pageColor+showAnnotations
(both baked into a preview, so changing either must not load a mismatched
raster) — rebinds/re-primes on document swap (prime only for a different
file; an edit revision's rebound previews make the prime a no-op) and on
pageColor/annotation change. Shells: `PdfReader.rasterCache`/
`PdfEditorView.rasterCache` pass through with the shell's `_documentKey`.
Example: `persistent_cache.dart` is the host backend via conditional
import (conditions evaluated in order, first match wins) —
`persistent_cache_io.dart` (dart:io, one base64url-named file per key
under systemTemp/dart_pdf_editor_cache; a real app points this at
path_provider's app cache dir) on native (`dart.library.io`),
`persistent_cache_web.dart` (an IndexedDB-backed PdfCacheStore via
package:web + dart:js_interop — one object store keyed by the cache key,
binary Uint8List values, each callback IDB request wrapped in a Future;
localStorage is too small/synchronous for raster bytes) on web
(`dart.library.js_interop`, which is ALSO true on the VM so io MUST be
listed first), and `persistent_cache_memory.dart` (session-only) as the
ultimate fallback; one app-wide `PdfRasterCache` shared across tabs,
passed to both shells. The example needs a direct `web: ^1.1.0` dep to
import package:web; the web build compiles (Wasm dry run passes).
Tests: pdf_document disk_cache_test (12 — LRU/budget eviction, manifest
persistence across instances, version-bump purge, namespace isolation,
flaky-backend degradation, concurrent writes), pdf_graphics text_cache_test
(5 — codec round-trip incl. utf8/empty, junk→miss, compute-once-then-serve,
keying), dart_pdf_editor raster_cache_test (3 — write-through→load-back as
an image across two sessions, empty-key no-op, loadFromDisk leaves a fresh
in-session preview alone). GOTCHA: tests must capture page objects ONCE
(like the viewer's `_pages`) — repeated `document.page(i)` calls can return
fresh wrappers, defeating the preview cache's identity-based `isFresh`.
