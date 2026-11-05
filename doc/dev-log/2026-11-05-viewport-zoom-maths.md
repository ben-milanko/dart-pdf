# Layout zoom, zoom-about-focal and reconcile remaps on the frame maths (#1208)

#1240 added `PdfViewportFrame` for capture, place, `_showRect` and
`_revealRect`. This finishes the job for the paths that still wrote the scroll
and transform inline.

## What moved

- `PdfViewportFrame.zoomedAbout(scroll:, listMain:, listCross:, scale:,
  atMain:, atCross:, mainView:, crossView:, clampCross:)` is the
  zoom-about-focal frame: it keeps list content under a view point at a new
  scale and leaves the scroll where it is. It replaces `_zoomTo`'s
  hand-built `translate · scale · translate` matrix and its
  `_clampedTransform` / `_clampedTransformMainOnly` choice. The clamps match
  those helpers, including the snap to identity at or below 1.01x and the
  unclamped cross axis during a touch pan.
- `PdfLayoutZoomAxis` (slot extents at layout zoom 1, spacing, cross view)
  replaces the viewer's `_remapMain` / `_remapCross`:
  - `remapMain` and `remapCross` move a point across a layout-zoom change;
  - `scrollKeeping` gives the offset `_setLayoutZoom` jumps to.
  The viewer builds one with `_layoutZoomAxis`. The trackpad pinch fold uses
  it as well.
- `PdfPageSetChange.remapViewport` carries a captured `PdfViewport` across a
  revision (#1201). `_applyPageSetChange` only chooses the timing: sync for
  the keyed reorder, `_pendingViewport` for the rest.
- `_currentFrame` is `_viewportFrame` that also works before layout, at
  scroll 0. `_zoomTo` needs that.

## Left as direct writes

- Live gesture handlers (wheel pan, touch and trackpad pan, rubber band,
  spring-back) still nudge the matrix incrementally. They are the input
  itself, not a projection.
- `_applyViewSync` restores an opaque `PdfViewSync` matrix.
- The layout-flip reset in `didUpdateWidget` sets the identity.

## Tests

`viewport_frame_test.dart` adds round-trip property tests with no widgets:
- `zoomedAbout` keeps the focal content under the pointer, clamps at the
  edges, leaves the cross axis free when asked, and snaps near fit;
- `remapMain` keeps a point's fraction into its page and round-trips;
- spacing does not scale; `remapCross` scales about the centre;
- `scrollKeeping` holds the content at the anchor.

`page_set_test.dart` checks `remapViewport` across a reorder.
