# Page rulers follow the viewport when zoomed in

**Bug:** with View options -> Page rulers on, zooming past fit-width made
the rulers disappear. `_PageRulerPainter` always drew its bands at the
page's own top/left edge (overlay origin), and zoom is the viewer's
InteractiveViewer transform, so those edges scroll off screen as soon as
the page is wider/taller than the viewport.

**Fix:** the viewer hands every page's `EditingPageOverlay` two new seams:
`visibleRegion` (the page's `_visibleFractionOf`, the same fractions as
`PdfViewerController.visiblePageRegion`) and `viewportChanges` (the
controller's notifier, bumped on scroll and transform). The ruler painter
repaints on `viewportChanges` (merged with `_cursorRepaint`), clips to the
visible slice and hangs both bands from its top/left. Values stay page
distances in points from the page's top-left; only ticks inside the slice
are drawn, so the count is bounded at any zoom. A null callback (a bare
overlay outside the viewer) treats the whole page as visible.

Test: `editing_guides_grid_test.dart` "page rulers follow the visible slice
when zoomed in" (`visibleRectFor` is the `@visibleForTesting` probe).
