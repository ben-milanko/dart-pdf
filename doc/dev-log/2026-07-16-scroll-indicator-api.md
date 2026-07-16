# Viewer scroll-indicator / page-scrubber API (issue #326)

Exposed a supported customization point for the viewer's scroll indicator
so a host can build a compact page number, a draggable page scrubber, or a
platform-styled scrollbar without reaching into the viewer's private
`ScrollController`. Both halves the issue asked for: a read-only scroll-state
snapshot + page-aware commands on `PdfViewerController`, and a builder on
`PdfViewer`.

All in `pdf_viewer.dart` (whole file is re-exported, so the new public types
ship automatically).

## What landed

- **`PdfScrollMetrics`** - immutable snapshot: `pageCount`, `currentPage`,
  normalized `position` (0 top … 1 bottom) and `extent` (visible fraction),
  the list-space pixel triple (`pixels`/`maxPixels`/`viewportPixels`),
  `zoom` (px/pt, same as `PdfViewerController.zoom`), and `hasOverflow`.
- **`PdfViewerController.scrollMetrics`** - reads the snapshot, null before
  layout. Listen to the existing `viewportChanges` `Listenable` to know when
  to re-read (it already fires on scroll and zoom; the controller itself
  stays quiet during scrolling and only notifies on a `currentPage` flip).
- **`PdfViewerController.jumpToNormalized(double)`** - immediate, zoom-aware
  scroll to a normalized position; what a scrubber-thumb drag maps to.
- **`PdfViewerController.animateToPage(int, {duration, curve})`** - the
  animated sibling of the existing `jumpToPage`.
- **`PdfViewer.scrollIndicatorBuilder`** (`PdfScrollIndicatorBuilder`) -
  replaces the built-in **vertical** scrollbar with a host widget, stacked
  over the right edge outside the zoom transform. The horizontal
  (zoom-window) bar is untouched.

## Design notes / gotchas

- **Reuse over reinvention.** The metrics mirror `PdfScrollbar`'s own
  measurement (`_verticalScrollExtents`): `total = maxScrollExtent +
  viewportDimension`, `visible = viewportDimension / scale`, and the
  viewport's leading edge unprojects through the transform as
  `-t_y/s + pixels` (the same formula `_visibleFractionOf` /
  `_captureViewport` use). So a custom thumb of height `extent` at
  `position` lines up pixel-for-pixel with the stock bar at any zoom and
  with mixed page sizes.
- **`jumpToNormalized` routes through `_scrollbarScrollBy`** (the scrollbar's
  own list-space motion), so it spills into the zoom window at the extents
  exactly like a bar drag - no separate zoom bookkeeping.
- **`hasOverflow` is threshold-based, not `maxPixels > 0`.** The list pads
  its bottom by `pageSpacing`, so a fully visible document still carries
  ~12px of nominal slack. The stock bar hides for it via
  `PdfScrollbar.minOverflow`; `hasOverflow` matches (`range > pageSpacing`),
  and the viewer skips the builder entirely while it is false, so a host
  never has to guard the "document fits" case. `extent` there is ~0.98 (the
  trailing margin), not 1.
- **`animateToPage` keeps `jumpToPage`'s far-jump snap.** Beyond
  `max(viewHeight*2, 2400)` px it snaps (warming the destination preview)
  rather than animating every intervening page into view; within range it
  animates for the given duration/curve. Both share the refactored
  `_jumpToPage(index, {duration, curve})`.
- **Full-fill builder + gesture arena.** The indicator is `Positioned.fill`
  so a host can float a page label anywhere or run a full-height scrubber.
  Interactive regions must set an opaque hit behavior (like the stock bar's
  strip) to win the vertical-drag arena over the scroll view underneath;
  non-interactive areas pass through to the viewer. The test's scrubber uses
  `HitTestBehavior.opaque` for this reason.

Tests: `test/scroll_indicator_test.dart` (metrics equality, snapshot
before/after layout, position tracking, no-overflow, `jumpToNormalized`
top/bottom/mid/clamp, `animateToPage`, builder replacing the stock bar +
receiving live metrics + not building on no-overflow + a scrubber drag).
