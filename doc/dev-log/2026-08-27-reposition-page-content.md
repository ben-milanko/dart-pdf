# Repositioning embedded page content (text, images, logos)

A user report: the content tool could select, retype, restyle, reflow and
delete a drawing on the page, but there was no way to *move* one. This adds
that, end to end - a drag (or the arrow keys) repositions the selected text
run, image, logo, form XObject or filled path.

## The model: move the space, not the drawing

`PdfEditor.moveElements` (`content_editor.dart`, tier 2b next to
`deleteElements`) never touches the operators or operands it moves. The
drawing stays byte-identical; only the space it draws in shifts. That is
what keeps a rotated logo rotated and a scaled image at its scale, and it is
why a moved run keeps whatever colour, font, clip and blend state the
surrounding stream set up for it.

A page-space delta has to be carried back through the transform the drawing
speaks in. That conversion is `translationUnder(ctm, dx, dy)` in
`matrix_geometry.dart`: `ctm x T(dx,dy) x ctm-1`. Concatenating it under the
element's own CTM lands exactly `(dx, dy)` in page points - the same matrix
works as a `cm` and as a post-multiplier on a text matrix, which is why both
branches share it. Null for a degenerate CTM.

Paths, images, forms, inline images and shadings are then bracketed:

    q <delta> cm   ... the element's operations ...   Q

## Text is the interesting half

`q`/`Q` are not legal inside a text object (§8.2 lists them as special
graphics state operators, excluded between `BT` and `ET`), and this library
is strict on output. So a text run is moved by rewriting the text matrix
around it instead:

    <seed x delta> Tm     ( the run )     <lineMatrix> Tm  [ kern ] TJ

Three things had to be right for that to leave the rest of the page alone:

1. **The seed.** For `Tj`/`TJ` it is the run's own text matrix, so a run
   that starts partway along its line stays there (seeding with the *line*
   matrix instead snapped it back to the left margin - caught by the "not
   first on its line" test). For `'` and `"` the operator performs its own
   `T*` **after** our `Tm`, so the seed is the line matrix the operator
   *entered* on and the operator is left to do the line move itself.
   `PdfTextPlacement` records all three matrices for exactly this.
2. **The line matrix.** `Tm` is the only operator that sets the text matrix,
   and it always resets the line matrix with it. Restoring the line matrix
   exactly is what keeps a following `Td`/`T*`/`'` - which is how nearly
   every generator places the next line - landing where it did.
3. **The advance.** Restoring the line matrix throws away how far the run
   had carried the text matrix, so a neighbour sharing the line would slide
   left. A kern-only `TJ` replays it: `[ -1000 x advance / size ] TJ`. The
   offset already accumulated before the run is recovered as
   `matrix x lineMatrix-1` (a pure translation - the two differ only by
   advances).

Refused, and reported by the return count rather than thrown: a path that
also establishes a clip (`W`/`W*` - bracketing it in `q`/`Q` would confine
the clip to the moved drawing), a degenerate CTM, and text at size 0 (the
advance cannot be expressed as a kern).

## Element ids survive a move

Every other content edit invalidates the element selection, because ids are
positions in paint order. A move must not, or a drag could not be followed
by a nudge. The splices are all transform operators - except the
compensating `TJ`, which the parser *would* have listed as a text element.
So `PdfPageElements` no longer emits an element for a `TJ` whose array
contains no strings at all: it shows nothing, it is not a drawing, and
keeping it out is what makes ids stable across a move. (It still advances
the text matrix, of course.)

`PdfContentElement` grew `ctm` and `textPlacement`, and
`PdfPageElements.serialize` grew `before`/`after` splice maps alongside the
existing `drop`/`replacements`.

## The UI

`PdfEditingController.moveSelectedElement` / `canMoveSelectedElement`
(`editing_controller.dart`) reapply the selection after the revision lands.
`nudgeSelected` now falls through to the element when no annotation is
selected, so the arrow-key bindings in `pdf_viewer.dart` (1 pt, 10 pt with
Shift) reach page content too - the binding gate widened to
`hasAnnotationSelection || selectedElement != null`.

In `editing_overlay.dart` the content tool's pan start claims a press inside
the selected element's box (with 4pt of slop - text runs are thin targets),
or on any other element, selecting and moving it in one gesture. The drag
state is deliberately **separate** from `_moveStart`: none of the annotation
move machinery - cross-page drops, appearance ghosts, resize handles -
applies to a drawing inside the content stream.

The preview floats the real artwork. There is no cheap way to render the
page *without* one content element (unlike an annotation, where
`skipAnnotation` does it), so instead: render the page as it stands once per
revision (`_ensureElementLift`, deferred past `endOfFrame` so the press-to-
first-frame path never waits on a page interpretation), wash the element's
resting footprint with paper, and paint the same pixels - clipped out of
that picture - translated to the pointer. Until the lift lands the orange
chrome box carries the drag on its own.

## Tests

- `pdf_document/test/content_move_test.dart` - the rewrite itself, verified
  by re-reading the page through `PdfPageElements` and checking bounds
  shifted by exactly the delta while neighbours held: images, paths, text
  first/mid-line, `'`, rotated and scaled CTMs, clip refusal, id stability.
- `dart_pdf_editor/test/editing_content_move_test.dart` - controller and
  viewer: drag-to-move, select-and-move in one gesture, a click that selects
  without moving, arrow-key nudges, undo.

Note the tolerance in the geometry assertions: the shift is carried through
the drawing's own transform, so a scaled placement pays one rounding of
`ContentWriter.fmt` on the way in (a 3x scale turns 5 into 1.667 x 3 =
5.001).

## Known limits

Horizontal scaling (`Tz`) is not in the element parser's model, so the
advance replay assumes `Th = 1` - it only matters when another run shares
the moved run's line under a non-default `Tz`. And this repositions the
drawing, not the flow: a moved run does not re-wrap (that is `reflowText`),
and moving content out from under a clip or a tiling pattern's phase can
change how it looks.
