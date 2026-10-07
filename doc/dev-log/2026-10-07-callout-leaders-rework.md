# Callout rework: multiple leaders, box moves keep arrows, mid-edit colour

Follow-up to [2026-07-09-callout-tool.md](2026-07-09-callout-tool.md). Five
review items, plus a data-loss bug found along the way.

## Multiple leaders (`pdf_document`)

- `/CL` (§12.5.6.19) can only describe one leader, so extra leaders live
  under the vendor key `kPdfCalloutLeadersKey` (`/CalloutLeaders`, annotation.dart):
  an array of point arrays shaped exactly like `/CL` (tip first, base last).
  The first leader stays in `/CL`, so other readers still see a valid
  callout, and the appearance stream draws every leader, so they still see
  every arrow.
- `PdfAnnotation.calloutLeaders` reads `[/CL, ...extras]`; `PdfCalloutLeader`
  is the `({target, attach?})` record the editor takes.
- `addCallout(..., attach:, extraLeaders:)` (it also gained the spacing/
  underline params so a rewrite can reproduce a box exactly).
  `addCalloutLeader` / `removeCalloutLeader` (refuses the last leader;
  removing leader 0 promotes the next into `/CL`). `reshapeCallout` takes
  `leader:` to say which arrow `target`/`attach` act on; every other leader
  keeps its tip and its base rides a box change at the same relative spot.
- All of them funnel through `_rebuildCallout` (geometry via
  `_calloutGeometry`, persistence via `_writeCalloutLeaders`). It now also
  reproduces a recovered **embedded** font (`PdfEmbeddedFont.fromFreeText`)
  and the line/char spacing, which the old reshape silently dropped.
- The extra-leader key rides every point-mapping loop next to `/InkList`
  (move, resize, rotate, local resize, paste), so a whole-annotation
  transform keeps the extras in step with `/CL`.

## Bug: editing a callout's text flattened it

`_rewriteSelected`, `_rewriteSelectedRich` and `_restyleSelectedFreeText`
remove the box and re-add it with `addFreeText` over `annotation.rect` -
which for a callout is the /Rect that also spans the leaders. So editing a
callout's text, or changing its font/size, turned it into a plain, huge text
box and threw the arrows away. All three now re-add callouts through
`_addCalloutLike` with the shape captured by `_calloutShapeOf` (box +
leaders + `/LE`). A rich commit on a callout flattens to the first run's
style (a callout appearance is single-style).

## Moving a callout keeps the arrows

`moveSelected` (drag, arrow-key nudge) and `alignSelected` go through
`_moveAnnotationIn`: an unrotated callout moves only its text box via
`reshapeCallout(box:)`, so every tip stays where it was aimed. Alignment
measures a callout by its box. A cross-page move still re-homes the whole
callout (it can't point at the old page). The overlay paints the stretched
leaders live during the drag (`_calloutLeaderPreview` - fixed tips, bases
shifted by the drag delta) and holds them (`_afterCalloutLeaders`) until the
new raster lands; handle reshapes hold theirs the same way.

## Editor UI

- Handles: `_selectedVertexPoints` returns `[tip0, base0, tip1, base1, ...]`;
  `_commitVertexDrag` maps handle `i` to leader `i ~/ 2`, odd = base.
- Right-click menu: "Add leader" (`addSelectedCalloutLeader()`, aimed 48pt
  off the box on the side farthest from existing tips -
  `_freeCalloutTarget` - ready to drag) and "Remove leader" (the leader
  nearest the click, `selectedCalloutLeaderNear`; disabled with one left).
  New l10n keys `menuAddLeader` / `menuRemoveLeader` in every locale.

## Preview arrow size

`_EditingPreviewPainter._arrowHead` used `max(10, width * 5)` with `width`
already in view pixels, so the 10 floor was in pixels while the model's
`_endingPath` floor is 10 **points**: at any zoom above 100% the preview
arrowhead was smaller than the committed one. The floor is now
`10 * geometry.scale`. This also fixes the arrow tool's preview. The callout
placement drag now draws through the callout-leader painter (box stroke
colour = border, else text colour) instead of the generic drag line.

## Alt+Z with wrapped text

`_autosizeTextRect`: when the text already soft-wraps at the box's width and
every wrapped line fits (no word wider than the box), keep the width and fit
only the height to the wrapped lines. Otherwise (no wrapping, or a box too
narrow for a word) the old natural-width behaviour applies.

## Colour mid-edit

Two causes:
1. On desktop a click on a toolbar swatch is a tap *outside* the text field,
   which unfocuses it, and focus loss commits the box - so the colour landed
   after the editor had closed. The swatches (desktop strip + mobile dock)
   are wrapped in `TextFieldTapRegion`; "More colours" holds the focus commit
   (`beginEditingTextFocusHold`) while its picker is open.
2. With just a caret, `restyleEditingTextSelection` returned false and the
   chip's colour button was disabled. It now restyles the whole box when
   nothing is selected (`_restyleWholeTextEdit`; a uniform box stays uniform,
   no `/RC`), and an existing box commits the changed default style through
   `setSelectedText(text, font:, size:, color:, underline:)` in one revision.
   The chip's colour button is always enabled; its font/size buttons still
   need a selection (enabling those too changed the gesture-arena timing the
   chip widget tests rely on, and the toolbar covers whole-box font/size).

## Tests

- `pdf_document/test/callout_test.dart` - "multiple leaders" group.
- `dart_pdf_editor/test/editing_callout_test.dart` - move keeps tips (+ nudge),
  add/remove/nearest leader, text/font/rich edits keep the callout, box drag
  in the viewer, per-leader terminus handle, context-menu add/remove.
- `editing_text_edit_test.dart` - Alt+Z keeps a wrapped column's width,
  caret recolour (new + existing box), toolbar swatch keeps the editor open.

## Follow-up: third-party (Bluebeam) callouts

A real Bluebeam mark-up file exposed two more problems:

- **`/RD` order.** §12.5.6.19's prose says left, top, right, bottom, but
  Bluebeam (and PDFBox, and evidently Acrobat) store left, **bottom**, right,
  **top** - in every callout of that file the `/CL` attach point sits on the
  edge of the box only under that reading. We read the spec order, so the
  selection chrome and resize handles hugged the wrong slice of `/Rect`.
  `PdfAnnotation.calloutBox` now builds both candidates and keeps the one
  the leader's last point lies on (ties / symmetric insets → left-bottom-
  right-top), so old files we wrote in the spec order still open right, and
  `_rdArray` now *writes* left, bottom, right, top so our callouts open
  right in those tools. `_boxFromRd` is just `calloutBox ?? rect` now.
- **Unrecoverable fonts.** Their `/DA` names `/F2` (Arial per `/DS`), which is
  neither base-14 nor recoverable, so `_rebuildCallout` refused and
  `_moveAnnotationIn` fell back to a whole-annotation move - the arrow
  travelled with the box. It now redraws in Helvetica instead of refusing.
- The callout placement drag also showed the generic rubber-band rectangle
  once callouts left `dragLine`; `dragRect` now excludes the callout tool.
