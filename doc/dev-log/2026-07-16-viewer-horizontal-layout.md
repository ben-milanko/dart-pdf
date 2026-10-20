# Configurable page layouts (horizontal continuous) in PdfViewer

Issue #324: `PdfViewer` only stacked pages vertically. Added a public,
extensible `PdfPageLayout` and a working horizontal-continuous layout that
reuses the whole viewer (virtualization, zoom/pan, selection, search,
overlays, links, forms) rather than reimplementing it.

## Public API

- `PdfPageLayout` (in `pdf_viewer.dart`, exported via the existing
  `export 'src/pdf_viewer.dart'`): a value type with named const
  constructors `verticalContinuous()` / `horizontalContinuous()` and a
  `scrollAxis` getter. Deliberately **not** a bare enum, so a
  facing/two-page mode can be added later as a new constructor without
  touching `PdfViewer`'s signature (the issue's explicit forward-compat
  ask).
- `PdfViewer.pageLayout` (defaults to `verticalContinuous()`), forwarded by
  `PdfReader` and `PdfEditorView`.

## How it works: the main/cross axis abstraction

The viewer's zoom model is unchanged and was already axis-friendly: at/below
fit the zoom lives in `_layoutZoom` (pages relayout smaller); above fit it
rides the `InteractiveViewer` transform (a scale+translate window). The list
is an `ExactExtentListView` (now given `scrollDirection`).

Everything was written against "vertical list, horizontal cross-axis in the
transform". Rather than fork every path, the state now speaks **main** (the
scroll axis) and **cross** (the fixed fit/centre axis). Vertical is the
identity case (main = Y, cross = X); horizontal swaps them. The primitives
(all in `_PdfViewerState`):

- `_horizontal`, `_mainTranslate`/`_crossTranslate` (Matrix4 storage index
  12/13 by axis), `_mainView`/`_crossView` (viewport extents),
  `_mainOf`/`_crossOf(Offset)` and `_axisOffset(main, cross)`.
- Geometry: `_crossPointOf`/`_mainPointOf` (page size in points per axis,
  from `_pointWidths`/`_aspects`), `_maxCrossPoint` (fit reference -
  `_maxPointWidth` or the new `_maxPointHeight`), `_fitScale`,
  `_pageCross`/`_pageMain`, `_crossInsetOf`, `_mainOffsetOf` (cumulative
  scroll offset), `_pageContentX/Y`/`_pageContentRect`, `_crossFactor`.
- `_pageWidth`/`_pageHeight` now mean literal on-screen w/h (they pick
  main/cross by axis) so `PdfPageGeometry` and `toViewRect` are untouched.

Every offset↔page mapping was rewritten in these terms: `_captureViewport`,
`_placeViewport`, `_showRect`, `_visibleFractionOf`, `_pagePointAt`,
`_pageContainsListPoint`, `_toPageView`, `_updateCurrentPage`, `_jumpToPage`,
`_scrollToDestination`, `_showMatch`, `_setLayoutZoom` (focal is now
`focalMain`), `_crossPageGhostFor`, and the initial-fit + reading-anchor
logic in `build`.

Gestures: the transform-translation cluster that was hard-wired to
"horizontal = free/rubber-band, vertical = scroll-bound" became main/cross.
`_clampedTransformVerticalOnly` → `_clampedTransformMainOnly`,
`_springBackHorizontal` → `_springBackCross`, `_horizontalOverscroll` →
`_crossOverscroll`, `_onHorizontalBounceTick` → `_onCrossBounceTick`;
`_rubberBandClamp`, `_onPanFlingTick`, `_scrollbarScrollBy`/`_scrollbarPanBy`,
`_grabPanBy`/`_touchGrabPanBy`, the trackpad pan/fling, and `_onPointerSignal`
(wheel) all route through the axis accessors. `_clampedTransform` already
clamped both axes symmetrically - no change.

`PdfDestination`/`_showMatch`: a `/FitH top` drives a vertical layout's
scroll; a horizontal layout scrolls to the destination/match's **left**
(the main axis) instead, leaving the fully-in-view cross axis to the zoom
window.

## Scrollbars

`PdfScrollbar` keyed "scroll-driven vs transform-only" off `axis ==
vertical`. Decoupled: it's now `_scrollDriven = scroll != null`, and the
transform storage index is `axis == vertical ? 13 : 12` (by the bar's own
orientation). So the same widget serves a horizontal *main* (scroll-driven)
bar and a vertical *cross* (transform-only) bar. The viewer positions each
bar by its orientation (vertical → right, horizontal → bottom, inset for the
corner) via `_positionedScrollbar`, so they never collide whichever axis is
which.

## Runtime switching

`didUpdateWidget` on a `pageLayout` change drops the zoom window, re-fits,
and re-anchors on `currentPage` in a post-frame callback (the new extents
only exist after the relayout). It skips the re-anchor when the `document`
also changed in the same rebuild - that branch already resets fit + scroll,
so running both would schedule competing post-frame scrolls.

## Example app

The demo app (`example/lib/main.dart`) exercises the API: a "Horizontal
page layout" / "Vertical page layout" toggle in the app menu flips
`_pageLayout` (a `PdfPageLayout`), passed to both the `PdfReader` and
`PdfEditorView` shells - so both the read-only and editing modes can be
seen in either layout.

## Tests

`test/pdf_horizontal_layout_test.dart` - 12 tests: value semantics, the
horizontal `Scrollable`, drag/jump current-page tracking, `visiblePageRegion`,
capture/restore round-trip, overlay geometry at the fit-height scale, search
nav, `Fit.page`, runtime layout switching, and mixed-size centring. All the
existing viewer/scrollbar/viewport/selection/comparison suites still pass
(vertical is the byte-for-byte identity case).

## Not done (future)

Facing/two-page and single-page paging - the API admits them; only the two
continuous layouts are implemented. `_showMatch`/`_scrollToDestination`
intra-page offsets ignore page `/Rotate` on the horizontal axis, same
simplification the vertical path already made.
