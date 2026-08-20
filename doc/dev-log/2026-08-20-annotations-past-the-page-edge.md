# Annotations may run past the page edge

Annotation authoring used to be confined to the page's crop box: a
placement near an edge silently jumped back inside so the whole annotation
"fits". Drawing a stamp against the corner of a sheet, signing over the
bottom margin, or pasting a callout half off the paper were all impossible
- the editor moved your annotation for you.

Nothing in PDF requires that. `/Rect` is page-space geometry like any
other; a viewer clips annotation appearances against the page, so a
markup that hangs off the edge simply shows the part that lands on paper.
Our own renderer already did exactly that (`drawAnnotations` →
`_drawAppearance`, painted inside the page clip) - the confinement was
purely authoring-side.

## The rule

**A point the user picked is authoritative.** Tap-to-place, drop, and
paste-at-a-point commit where the pointer was, edge or not.

The one exception is a placement with *no* point behind it: the paste
cascade (⌘V with no cursor target, which shifts 12pt down-right per
repeat) has nothing the user aimed at, so an unbounded repeat would walk
the copies clean off the paper and out of sight. Those stay **tethered**:
`PdfEditingController._tetherShift` keeps `pageTether` (24pt) of the rect
over the crop box on each axis - or the whole rect when it is shorter
than the tether, or the whole page when the page is shorter still. An
interval already inside the tether does not move, so a paste that hangs
off the edge keeps hanging off it. This replaced `_clampShift`, which
pushed the whole rect back onto the page.

## What changed

`editing_controller.dart`:

- `_pageRectForVisualSize` - the shared "rect of this visual size centered
  on (x, y)" helper behind free text placement, image drop, stamp and
  template placement, and image element replacement. Dropped the centre
  clamp; the centre is now the point it was handed.
- `placeCheckMark` - split out `checkMarkPlacement`, which the count
  tool's hover preview now calls too (see below), and dropped the
  position clamp.
- `signaturePlacement` - dropped the position clamp.
- `pasteAnnotations` / `pasteSnapshot` - shift only when `at == null`,
  through `_tetherShift`.
- `_autosizeTextRect` - a free-text box grows from the anchor the user
  left it at, off the edge, instead of sliding inward to fit.

`editing_overlay.dart`:

- `_countPreviewAt` had its own copy of the check-mark placement math.
  Two copies of a placement rule is one drift away from the preview and
  the commit disagreeing (the mark visibly jumping on release), so it now
  calls `controller.checkMarkPlacement`.

Move and resize needed nothing: `moveSelected` / `resizeSelected` and the
overlay's drag math were already unclamped, as were shape/ink/markup
drags. Those paths just had no test pinning the behaviour - `editing_test`
now has one that drags a rectangle off the left edge and reopens the saved
bytes to prove `/Rect` survives the round trip.

## Size caps are not boundary rules

Auto-sizing still caps a stamp, image, or signature at 90% of the page.
That is about *size* - an auto-sized annotation bigger than the paper it
lives on is a bug, not a feature - and is unrelated to where the thing
sits. Both survive together: `placeStamp(height: 5000)` at the corner
gives a page-capped box centered off the corner.

Surfacing that cap found a real bug: `textStampPlacement` computed the
width as `measured.clamp(h, pageWidth * 0.9)`, and a tall stamp on a
landscape-ish page makes the floor (`h`) exceed the ceiling, which
`double.clamp` throws on. The floor is now `min(h, maxW)`.

## The one placement that still yields to the page

`EditingPageOverlay._defaultPlacementRect` still nudges a *default-sized*
tap-placed text box back on. That nudge is about the **editor**, not the
annotation: the rect it returns opens the inline text field, which the
page's `Stack` clips like everything else in this overlay, so a
200pt-wide box hung off the corner would have the user typing into pixels
they cannot see. Only the size there is the editor's guess - a box the
user drags out themselves keeps the bounds they drew.

Same clip is why an annotation dragged mostly off the page keeps only its
on-page resize handles. The on-page part is still grabbable, and the
annotation sidebar selects by slot regardless, so nothing becomes
unreachable.

## Follow-up: the off-page half was paint-only

Shipping the above was half the job. The geometry was free, and the editor
*painted* the part of an annotation that hung off the paper (the overlay's
painters are `CustomPaint` children that fit their box exactly, so the
page `Stack` never sets `_hasVisualOverflow` and never clips them) - but
pointer routing did not follow. `RenderBox.hitTest` refuses any position
outside `size`, so a press on the visible off-page half of a selected
markup reached nothing at all. It could only be moved or resized by
whatever was still on the paper.

### The reach

`PdfEditingReach` (`editing_reach.dart`) is a `RenderProxyBox` that accepts
those positions and forwards them into the page subtree at the nearest
point *inside* it.

Clamping is sound because **hit testing only decides routing**. Every
pointer event carries its true global position, and
`PointerEvent.localPosition` is derived from that through the target's own
transform - never from the position the hit test ran at. So the overlay
reads the real off-page point (negative, or past the page's width) and all
of its existing drag math works untouched. The move test asserts the
annotation travels the *whole* drag delta, which is exactly what would
break if the clamp leaked into the coordinates.

### Where it has to sit

Not inside the page. The first attempt wrapped `_PdfViewerPage`'s own
`Stack` and did nothing, because the gate is higher: the item is
`Padding → Center → FractionallySizedBox → page`, and
`RenderFractionallySizedOverflowBox` sizes itself to **its child** - so it
is the outermost box that refuses a margin position. Everything above it
(`Center`, `Padding`, the sliver) spans the viewport and forwards hit tests
through `RenderShiftedBox.hitTestChildren`, which does not gate on the
child's size. So the reach goes immediately outside the
`FractionallySizedBox`, and needs no reach distance of its own - its
ancestors bound it to this page's slot, margin and inter-page spacing
included.

Debugging this is easy if you stop guessing: dump
`tester.binding.hitTestInView(result, point, view)`'s path and read which
render object the walk stops at.

### Why it is not simply "the margin belongs to the page"

Because the canvas is already spoken for. `_touchPanEnabledAt` deliberately
hands canvas and inter-page gaps to the viewer's own touch pan while a tool
or selection is live - "a phone at `PdfViewerFit.page` leaves canvas down
both sides of a portrait page for a thumb to land on". Claiming every
margin press for the page would have quietly broken thumb-scrolling on
phones to buy off-page drawing nobody asked for.

So the reach takes a **predicate**, not a flag: `grabs(position)`, which the
viewer answers from `PdfEditingController.selectionGrabAt` - the selection's
own chrome rects (a markup's first quad, a callout's text box, else /Rect)
inflated by `_selectionGrabMargin` (24 view px, converted to points through
the page's scale) for the resize handles and rotate knob. A selection
hanging off the paper is the one thing out there worth grabbing; everything
else in the margin falls through exactly as before.

`_touchPanEnabledAt` draws the same line via `_selectionGrabsCanvasPoint`,
so the viewer yields precisely the positions the reach claims and the two
recognizers never meet in the arena.

### Consequence

Drawing a *new* annotation still has to start on the page - the canvas is
scrolling's. A stroke, shape or drag started on the page continues past the
edge as far as you like, which is what the geometry change above unlocked.
