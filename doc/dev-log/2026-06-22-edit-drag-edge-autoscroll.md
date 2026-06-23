# Edit-drag edge auto-scroll

When a region/selection drag in the editing overlay reaches the viewport
edge, the viewer now keeps scrolling in that direction so you can drag past
what's on screen — snapshot rects, marquee (shift) selection, moves,
resizes, vertex drags, shape drag-outs. The held pointer re-tracks onto the
content scrolled under it, so the drag keeps growing; a manual shift-scroll
mid-drag tracks the same way.

## How it works

`EditingPageOverlay` gained an `edgeAutoScroll` callback (wired in
`pdf_viewer.dart` to `_PdfViewerState._edgeAutoScrollDelta`). The viewer
owns the viewport geometry, so it computes the per-frame pan delta: it reads
its own render box's global rect, measures how deep the drag pointer sits in
a 60px edge band, and ramps the speed linearly to 16 logical px/frame at the
rim. The delta is divided by the transform zoom because `onPanViewport`
(`_touchGrabPanBy`) deltas are list-space, then fed straight through the
existing grab-pan path (`_scrollbarScrollBy`/`_scrollbarPanBy`, which already
clamp at the scroll extents — so the drag just stops growing at the content
bounds, no runaway).

The overlay drives the loop with a `Ticker` (`_autoScrollTicker`), started in
`_panUpdate` whenever a region drag is active (`_autoScrollDragActive`) and
stopped in `_panEnd` / `_bailActiveGesture` / `dispose`. The mixin changed
from `SingleTickerProviderStateMixin` to `TickerProviderStateMixin` because
`_flashController` already held the single ticker.

## The key coordinate insight

The drag's "current" point is kept in the overlay's **page-local** view
space, which is **scroll-invariant** — a point on the page has the same
local coordinates no matter where the page is scrolled. So the ticker
re-derives the pointer each frame with `box.globalToLocal(global)`: a
stationary screen pointer maps to a *moving* page-local point as the page
scrolls under it, and `delta = current - start` (both page-local) is exactly
the page-space drag delta with no scroll offset to subtract. That's why the
same mechanism fixes manual shift-scroll tracking for free — the ticker runs
for the whole drag, not just at the edge, and re-applies on any layout
change. `_panUpdate`'s per-drag branch logic was extracted into
`_applyDragPosition(position)` so both the gesture and the ticker share it.

A redundant-rebuild guard (`_autoScrollLastLocal`) skips re-applying when the
re-derived local hasn't moved (held pointer, no scroll).

## Tests

`test/editing_autoscroll_test.dart`: a snapshot drag held at the bottom edge
keeps panning across idle frames and stops on lift; a drag held away from the
edges does not scroll; a drag to the top edge scrolls back up.
