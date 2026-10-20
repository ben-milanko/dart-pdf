# Fixing the content-drag preview: neighbours and the blank page

Two defects reported against the content-element move that landed earlier
today, both traceable to one shortcut in the drag preview.

1. Other content appeared inside the drag box and travelled with the
   element, then snapped back on release.
2. After the drop the page went white for a while.

## What the first cut did

It rendered the page once and, during the drag, painted paper over the
element's bounding rect and the same picture clipped to that rect at the
pointer.

Both problems follow directly. A bounding rect is not the drawing: anything
overlapping it - the rest of a line, a rule, a filled panel - is inside the
clip, so it rode along in the float, and the paper wash erased it at the
source. Only the element actually moved on commit, so the neighbours snapped
back. And the preview tore down at pointer-up, leaving nothing over the gap
while the page re-rendered.

## Rendering the element apart from its neighbours

You cannot separate a drawing from what overlaps it in a flattened picture.
So render two, from one parse, filtered two ways -
`PdfPageElements.operationsRetaining(keep)`:

- **clean** - `(e) => e.id != id`, the page without the element. Fills the
  hole truthfully; neighbours sharing the box keep their pixels.
- **only** - `(e) => e.id == id`, the element by itself, with
  `PdfPageRenderPlan(paper: false)` so it composites over the live page and
  `annotations: false` so nothing else rides along.

The float needs no clip at all now, which also fixes a quieter bug: text
bounds are estimates (§ the element parser measures advances but guesses the
vertical extent), so a clipped float could shave a tall glyph.

**Dropping a text run means replacing it with the advance it owed.** State
operators are kept - colour, font, `cm`, `gs` - so the survivors still look
right; but a text-showing op also moves the text matrix, and simply deleting
it slides the rest of the line left. `operationsRetaining` substitutes a
kern-only `TJ` for the advance (preceded by the `T*` that `'` and `"`
perform, and their `Tw`/`Tc`), so every run after it in the text object holds
position. That matters in *both* lists: in `clean` the moved run's line must
not reflow, and in `only` the target's own position depends on the advances
of the runs before it.

(`deleteElements` still shifts a line when it drops a run mid-line - the same
latent bug, now with a ready fix in `operationsRetaining`. Left alone here to
keep this change to the reported defects.)

Renderer seam: `renderPictureWithPlan` takes an optional `operations` list
(it already parsed once into `pageOps`; this just lets a caller supply it),
and `PdfPageRenderPlan` gained `paper`. A transparent `pageColor` would not
have worked - `_paintBackground` paints white under any translucent colour.

## The blank page

A content edit is not an annotation edit. The viewer's incremental
reconciliation calls `_previews.rebind(_pages, changed: contentPages.contains)`
and `_rasteredPages.removeAll(contentPages)`, which *drops* the page's cached
raster rather than keeping it stale - so the page has nothing to show until
the fresh interpret lands. Annotation edits keep the base raster, which is
why they never flashed.

The re-render itself is not something this change can make faster. What it
can do is make it invisible, which is what "faster" means to the user here.
The same pair is held past the commit (`_holdElementAfterimage`, ownership
transferring out of the per-revision cache, which is dead the moment the
revision changes) and painted **unclipped**: clean over the whole page, plus
the element at the committed offset. That composition *is* the new page, so
it stands in exactly until `widget.rasterCurrent` clears it through the
existing `_afterRevisionId` contract every other afterimage uses.

Hence `elementLiftSettled`: mid-drag the clean page is clipped to the
footprint (everywhere else the live raster is already correct, and the clip
lets Skia cull the replay); settled, the clip comes off.

## Cost

Two page pictures instead of one, per selected element per revision, built
off the selection rather than the drag start - a quick press-and-flick would
otherwise commit before the render landed and blank on its own. Deferred past
`endOfFrame` so the press-to-first-frame path never waits on an interpret,
cached by (document, revision, page, element, colour, annotations), and
released when the selection clears. Same profile as the annotation path's
`_ensureSourceClean`, which already renders a clean page per revision.

## Tests

`content_move_test.dart` covers the filter directly, including the property
the whole thing rests on: dropping a mid-line run leaves its neighbours
exactly where they were. `editing_content_move_test.dart` asserts the drag
paints both pictures with `elementLiftSettled` false, and that after the drop
the pair is still held, unclipped, at the committed offset.
