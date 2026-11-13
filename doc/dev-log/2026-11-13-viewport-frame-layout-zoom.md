# The viewport frame owns layout zoom too (#1208)

#1240 and the follow-up in #1248 put the scroll and the zoom transform into
`PdfViewportFrame` and moved capture, place, framing and zoom-about-focal
onto pure maths. Layout zoom (the zoom at or below fit, applied by laying the
pages out smaller) still sat outside the value. So `_zoomTo` crossed the fit
boundary step by step against the live controllers: relayout, read the
jumped scroll back, then build the transform. `_settleZoomGesture` folded
the regimes with an inline matrix product. This change closes that gap.

## What moved

- `PdfViewportFrame.layoutZoom`: the frame is now the whole position:
  layout zoom, scroll and transform.
  - `zoom` is the effective zoom (the old `_currentZoom` rule: a transform
    within 1% of the identity defers to the layout zoom).
  - `zoomed` is `scale > 1.01`.
  - `sameTransformAs` compares the transform alone.
  - `showing`, `zoomedAbout` and `placePdfViewport` take the layout zoom
    they frame over.
- `PdfViewportFrame.zoomParts(zoom, minZoom:, maxZoom:)` splits an
  effective zoom into `(layoutZoom, scale)`. It replaces the
  `zoom <= 1 ? clamp : 1` split that build, `_restoreViewport` and
  `_placeViewport` each wrote.
- `frame.withLayoutZoom(to, axis:, anchor:, content:)` is `_setLayoutZoom`'s
  maths. It relays out and keeps `content` at view-main `anchor`.
- `frame.zoomedTo(zoom, listMain:, listCross:, axis:, ...)` is the whole of
  `_zoomTo` across the fit boundary, in both directions. One detail is kept
  from before: a sub-fit transform belongs to an InteractiveViewer gesture
  still in flight, so zooming to at or below fit leaves it alone and only
  drops a zoomed-in one.
- `frame.settled(axis:, mainView:, crossView:, minZoom:)` is
  `_settleZoomGesture`'s fold. The matrix product
  `before · T(c) · S(fold) · T(-c)` reduces to
  `crossTranslate += scale · c · (1 - fold)` with `c = crossView / 2`. The
  main axis is pinned at its centre, as before.
- `capturePdfViewport` reads the zoom from the frame. It no longer takes a
  `zoom:` argument.
- `_preserveReadingAnchor` (viewport resize) captures the list's leading
  edge with `capturePdfViewport` and re-derives the scroll with
  `placePdfViewport`. Its own slot walk is gone.

## The one writer

`_applyFrame(frame)` in pdf_viewer.dart is now the only place a computed
frame reaches `_layoutZoom`, `_scroll` and `_transform`. `_zoomTo`,
`_setLayoutZoom`, `_placeViewport` and `_settleZoomGesture` all go through
it.

- It writes only what changed. This matters because `_setLayoutZoom` runs
  mid-gesture (double tap, settle), and the transform there must not be
  rebuilt from frame components under the gesture.
- It keeps the old write order. A transform that goes away is written
  before the relayout. A zoomed-in transform that stays is written after
  the scroll jump that re-anchors it. The scroll and transform listeners
  therefore see the same intermediate states as before.
- After a relayout, the post-frame clamp of the scroll's far end lives here.

## Still direct writes

- **Live gesture handlers**: wheel pan, touch and trackpad pan, rubber band
  and spring-back. They are the input, not a projection.
- **The double-tap and `_showRect` animations**: a `Matrix4Tween`.
- **`_applyViewSync`**: `PdfViewSync` is public API and carries an opaque
  matrix.
- **The reset paths**: the layout-flip reset in `didUpdateWidget` and
  `PdfViewportCarry.reset`.
- **The initial fit in build**: it sets `_layoutZoom` before the first
  layout, so there is no scroll yet to move.
- **`_zoomed`**: deliberately not derived from the frame. It is the
  *settled* zoom state, updated on settle, place and gesture end. It gates
  scroll physics and gesture routing, and it must not flip mid-gesture.

## Tests

`viewport_frame_test.dart` adds widget-free property tests:

- `zoom` and `zoomParts`;
- capture ∘ place across layout zooms below fit;
- `zoomedTo` keeps the content under the pointer across 300 random
  below/above-fit pairs (main axis always; cross axis above fit);
- zooming to fit drops a zoomed transform but keeps a sub-fit gesture
  transform;
- each of the three `settled` branches, including that every cross point
  stays put through the fold.
