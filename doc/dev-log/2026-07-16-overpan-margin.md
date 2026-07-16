# Over-pan margin: reach content outside the page box

## Problem

The zoom-window pan clamp pinned the content edges to the viewport edges:
the horizontal translation was clamped to `[_viewWidth * (1 - scale), 0]`
and the vertical to `[_viewHeight * (1 - scale), 0]`, so no blank edge
could ever show. But real PDFs sometimes draw material *outside* the page
box - bleed, crop/registration marks, art that overflows the MediaBox, or
a narrow page islanded in a wide canvas (CAD) - and the vector display
path (`_SlugPagePicturePainter` in a plain `CustomPaint`) applies no clip
at the page boundary, so that material is actually painted. It just wasn't
reachable: you couldn't pan far enough to bring it in from the edge.

## Change (`pdf_viewer.dart`)

Widened the allowed **horizontal** translation by a bounded over-pan
margin. New helpers next to the clamp methods:

- `_panMarginX` = `min(_viewWidth * 0.25, 160.0)` - a modest fraction of
  the viewport, capped so a large viewport doesn't pan off into a wide
  empty margin.
- `_panBoundsX(scale)` returns the tight cover range widened by the margin
  on each side: `(_viewWidth * (1 - scale) - _panMarginX, _panMarginX)`.

The interactive horizontal clamps go through these bounds:
`_clampedTransform` (x only), `_onPanFlingTick`, `_rubberBandClamp`,
`_horizontalOverscroll`, `_springBackHorizontal`. The touch rubber-band's
free zone now extends to the margin (you can rest anywhere in
`edge ± margin`); only past the margin does it dampen and spring back - to
the margin edge, not the page edge. Non-touch pans
(mouse/trackpad/scrollbar/fling) hard-clamp to the widened range and rest
in the margin.

### Horizontal only - and why

Sideways overflow lives *entirely* in the zoom-window transform (pages are
laid out fit-width or narrower and centered; there is no horizontal
scrollable), so widening the transform's x-clamp is the whole story.

The vertical axis is different: it is driven by the scrollable's own
extents, and the transform's y-translation only *covers the current view*
(spillover past the scroll extents at the very top/bottom of the
document). Widening the y-clamp lets the zoom window rest on blank canvas
*mid-document* - which `exact_extent_test.dart`'s "zoomed canvas gaps keep
scrolling with the select tool armed" explicitly guards against
(`storage[13]` must stay within `[height * (1 - scale), 0]`). So the
vertical clamp stays tight. Vertical document-end overscroll, if ever
wanted, belongs to the ListView's scroll physics, not this transform.

Left *tight* on purpose: the programmatic placement clamps in
`_placeViewport` and `_showRect` - restoring a saved viewport or framing a
rect should land in-bounds, not in an over-panned position.

## Why it's safe downstream

`_visibleFractionOf` (thumbnail viewport indicator) clamps via
`Rect.intersect`, so an over-pan just reports a smaller in-page region, not
an out-of-range fraction. `_captureViewport` reports the true unclamped
fraction (x can go slightly negative), and restore re-clamps it. The
rubber-band already produced transient out-of-range x-translations, so
every consumer of `storage[12]` already tolerated it.

## Test

`pdf_viewer_test.dart` - "trackpad pan rests a reasonable amount past the
page edge": zoom in, trackpad-pan hard right past the page's left edge, and
assert `captureViewport().left` rests `< 0` (past the edge) but `> -0.2`
(bounded). Existing "rubber-bands and springs back" / "within bounds" tests
still pass unchanged (the region indicator's intersect-clamp keeps their
`left ≈ 0` assertions valid), and `exact_extent_test.dart`'s vertical-bound
assertion is preserved because the vertical clamp stays tight.
