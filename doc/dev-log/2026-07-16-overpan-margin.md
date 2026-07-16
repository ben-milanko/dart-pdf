# Over-pan margin: reach content outside the page box

## Problem

The zoom-window pan clamp pinned the content edges to the viewport edges:
the horizontal translation was clamped to `[_viewWidth * (1 - scale), 0]`
and the vertical to `[_viewHeight * (1 - scale), 0]`, so no blank edge
could ever show. But real PDFs sometimes draw material *outside* the page
box - bleed, crop/registration marks, art that overflows the MediaBox -
and the vector display path (`_SlugPagePicturePainter` in a plain
`CustomPaint`) applies no clip at the page boundary, so that material is
actually painted. It just wasn't reachable: you couldn't pan far enough to
bring it in from the edge.

## Change (`pdf_viewer.dart`)

Widened the allowed translation range by a bounded over-pan margin on each
axis. New helpers next to the clamp methods:

- `_panMarginX` / `_panMarginY` = `min(viewportExtent * 0.25, 160.0)` - a
  modest fraction of the viewport, capped so a large viewport doesn't pan
  off into a wide empty margin.
- `_panBoundsX(scale)` / `_panBoundsY(scale)` return the tight cover range
  widened by the margin on each side:
  `(_viewWidth * (1 - scale) - _panMarginX, _panMarginX)` (and the Y twin).

All the *interactive* clamps now go through these bounds:
`_clampedTransform`, `_clampedTransformVerticalOnly`, `_onPanFlingTick`,
`_rubberBandClamp`, `_horizontalOverscroll`, `_springBackHorizontal`. The
touch rubber-band's free zone now extends to the margin (you can rest
anywhere in `edge ± margin`); only past the margin does it dampen and
spring back - to the margin edge, not the page edge. Non-touch pans
(mouse/trackpad/scrollbar/fling) hard-clamp to the widened range, so they
rest in the margin.

Left *tight* on purpose: the programmatic placement clamps in
`_placeViewport` and `_showRect` - restoring a saved viewport or framing a
rect should land in-bounds, not in an over-panned position.

## Why it's safe downstream

`_visibleFractionOf` (thumbnail viewport indicator) clamps via
`Rect.intersect`, so an over-pan just reports a smaller in-page region, not
an out-of-range fraction. `_captureViewport` reports the true unclamped
fraction (can go slightly negative), and restore re-clamps it. The
rubber-band already produced transient out-of-range translations, so every
consumer of `storage[12]`/`storage[13]` already tolerated it.

## Test

`pdf_viewer_test.dart` - "trackpad pan rests a reasonable amount past the
page edge": zoom in, trackpad-pan hard right past the page's left edge, and
assert `captureViewport().left` rests `< 0` (past the edge) but `> -0.2`
(bounded). Existing "rubber-bands and springs back" / "within bounds" tests
still pass unchanged (the region indicator's intersect-clamp keeps their
`left ≈ 0` assertions valid).
