# Callout tool

Added a Bluebeam-style **Callout** annotation tool: a `/FreeText` text box
joined to a point on the page by a leader line that ends in an arrow.

## Model (`pdf_document`)

- `PdfEditor.addCallout(pageIndex, boxRect, text, target, {...})` in
  `annotation_editor.dart`. It writes a `FreeText` annotation carrying the
  callout-specific entries on top of what `addFreeText` writes:
  - `/IT /FreeTextCallout`
  - `/CL` - the leader points, arrow tip **first**, box attachment **last**
    (§12.5.6.19). `_calloutLine(box, target)` picks the box edge nearest the
    target and adds a short horizontal/vertical knee stub into the box, so the
    leader reads as `[target, knee, attach]` (or `[target, attach]` when a
    knee would be degenerate, e.g. the target lands inside the box).
  - `/LE` - a **single** name (the arrow style on the tip), unlike a Line's
    two-element `/LE`.
  - `/RD` - the inset from the enclosing `/Rect` to the text box, so the box
    is a sub-rect of `/Rect` (which must also enclose the leader + arrowhead).
- The appearance is composed by `_calloutContent`: `_lineContent` draws the
  leader + arrowhead (reusing the Line tool's `_drawEnding`), then
  `_freeTextContent` draws the box on top. To merge the two writers a small
  `ContentWriter.append(other)` was added (content_writer.dart).
- `/Rect` == form `/BBox` == `_pointBounds([box corners, ...CL,
  ...endingExtent])`, so the whole markup survives §12.5.5 appearance fitting.
- **Reading it back:** `PdfAnnotation.isCallout` and `.calloutLine`
  (annotation.dart) mirror the existing `.line`/`.vertices` getters. `/CL`
  was already carried through every move/resize/rotate point-mapping loop
  (`['QuadPoints', 'L', 'Vertices', 'CL']`), so the dict coordinates scale for
  free.
- **Resize/restyle regeneration:** the single `case 'FreeText':` in
  `_regenerateResizedAppearance` now detects a callout (via `_calloutInfo`)
  and redraws the leader + box together - mapping `/CL` and the `/RD` box
  sub-rect through the same from→to affine the Line case uses, and rewriting
  `/RD` to match. Both resize and restyle funnel through this case, so the
  leader recolors with the box border on restyle. Move needs nothing extra:
  the appearance is in page space and the identity BBox→/Rect fit translates
  it. Plain free text (no `/CL`) keeps the old whole-rect path.

## Editor UI (`dart_pdf_editor`)

- New `PdfEditTool.callout`. Only one exhaustive switch (the overlay's
  `_panStart`) needed a new arm to compile; the rest carry `default`/`_`.
- Placement mirrors Bluebeam: **press at the terminus, drag to where the box
  goes**. `editing_overlay._panEnd` routes a callout drag to
  `_openCalloutEditor`, which remembers the terminus as a page-space point
  (`_textEditCalloutTarget`) and opens the same inline box editor free text
  uses. A plain tap (no drag) makes the tap the terminus and offsets the box.
  `_commitTextEdit` calls `controller.addCallout(...)` when a target is set.
  During the drag a leader-line preview is shown by extending `dragLine` to
  the callout tool.
- `PdfEditingController.addCallout` dispatches to the model with the box
  styling from the free-text preferences plus the stroke color/width for the
  arrow. The callout tool shares free text's style scope (font/box colors/
  align/opacity) via `_styleScopeFields`.
- Toolbar: a "Callout" chip in the **Insert** group (so it inherits the
  insert group's font/box controls). Shortcut **Q** (Bluebeam's), in
  `tool_shortcuts.dart`. The sidebar and properties panel label a callout
  "Callout" with a chat-bubble icon (branching on `isCallout`, since the
  subtype is still `FreeText`).

## Tests

- `pdf_document/test/callout_test.dart` - creation (`/IT`/`/CL`/`/LE`/`/RD`,
  Rect enclosure, appearance has the arrow + text), the `calloutLine` getter,
  and resize keeping it a callout.
- `dart_pdf_editor/test/editing_callout_test.dart` - controller `addCallout`,
  the drag-to-place flow through the overlay (leader points back at the
  terminus), empty-box no-op, and a save/reload round-trip.

Gotcha worth remembering: the 800×600 default test surface clips
`view(x, y)` taps whose page-y is small - a commit tap must land inside the
viewport (page-y ≳ 333 at `PdfViewerFit.width`).

## Follow-up: preview arrow + independent terminus/box editing

Review feedback drove three UX fixes:

1. **Drag preview shows the arrow.** `_paintPathPreview` now draws an open
   arrowhead at the *first* point for `PdfEditTool.callout` (the terminus is
   the drag start, not the end like the arrow tool), matching the committed
   `/OpenArrow`.
2. **Leader stays visible while the box editor is open.** The preview painter
   gained a `calloutLeader: (terminus, box, color, width)?` field, fed by
   `_calloutLeaderPreview()`. `_paintCalloutLeader` draws the leader from the
   terminus to the box's nearest edge + arrow, so the arrow doesn't vanish
   between release and commit. The same helper feeds the leader while the
   terminus handle is being dragged.
3. **Terminus and text box move independently** (Bluebeam's model). New model
   primitive `PdfEditor.reshapeCallout(annotation, {box, target})` rebuilds
   `/CL`/`/RD`/`/Rect`/appearance from a new box and/or terminus, keeping the
   other fixed and preserving text + style + ending. Wiring:
   - `PdfAnnotation.calloutBox` reads the text-box sub-rect (/Rect inset by
     /RD) - the counterpart to `calloutLine`.
   - Overlay `_selectedViewRect` returns `calloutBox` for a callout, so the
     resize handles + selection chrome hug the box, not the /Rect that also
     encloses the leader/arrow. `resizeSelected`/`resizeSelectedLocal`
     intercept callouts → `reshapeCallout(box:)` instead of scaling `/CL`.
   - Overlay `_selectedVertexPoints` returns `[terminus]` for a callout, so
     the Line/PolyLine vertex-handle machinery gives it one draggable handle
     at the arrow tip; `_commitVertexDrag` routes callouts to
     `reshapeSelectedCalloutTarget`. `showHandles` stays true (a callout isn't
     `_selectedLineFamily`), so box handles and the terminus handle coexist.
   Move (dragging the body) still translates the whole callout - only the
   scale handle and the terminus handle are independent, which is what the
   "scale handle scales both" complaint was about.
