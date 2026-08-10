# Pages popping in and out at the screen edge (#657)

Reported against a 63-page, 36 MB CAD/scan correlation pack on Windows:
scrolling around, the pages above and below the one being read visibly
**pop in and out** as they sit near the screen edge. The attached devtools
export showed the decoded-image cache thrashing (11 entries / 130 MB held,
210 misses against 146 evictions) and the render-record cache at 67 MB of
100 MB with 201 evictions - a working set churning, not a working set
fitting.

## Root cause: focus is one page index, visibility is a range

Three separate prefetch economies keyed off `PdfPageView.focusDistance`,
which is `|index - controller.currentPage|`, and `currentPage` is
`_updateCurrentPage`'s answer to "which page is the viewport **centre**
on". On any document whose pages are taller than the viewport - every CAD
sheet, every A3 scan - there is always a *second* page filling a large
part of the screen at distance 1. All three treated it as an off-screen
prefetch neighbour:

1. `_imageRatioTarget()` decoded its embedded images at
   `prefetchImagePixelRatioFactor` (0.5x, #451). On a scan the image *is*
   the page, so half the screen rendered soft.
2. `PdfLiveRasterBudget.rebalance()` evicted farthest-distance-first and
   protected only distance 0, so the visible neighbour was the budget's
   first casualty when the on-screen pair alone exceeded the desktop
   384 MB ceiling - two large-format base rasters plus their retained
   scenes get there easily. `evictLiveRaster()` drops the base raster, the
   detail patch and the scene, leaving the soft preview: **the pop-out.**
3. The pressure path `evictReclaimable()` shed *every* non-focused page,
   visible ones included, on each platform low-memory signal (the export's
   log has these firing every 30-75 s).

And the flip is symmetric, so it oscillates: cross the midpoint and the
page that just lost focus is demoted while the page that gained it drops
its reduced-resolution buffer (`droppedForFocus` in `didUpdateWidget`) and
re-interprets at full ratio. Because `PdfImageCache` keys by content *and
decoded size* (`PdfSizedImageKey`), the 0.5x and 1.0x decodes of the same
scan are two entries - so the flip is a guaranteed miss, a fresh decode of
tens of MB, and an eviction of whatever the other page was holding. That
is the 146-evictions-for-210-misses signature in the export.

## The fix: `onScreen` as a first-class input

`PdfPageView.onScreen` (defaulting to true, so a directly-embedded page
view is unaffected) now says whether *any part* of the page overlaps the
viewport, and it - not `focusDistance` - gates the prefetch economies:

- `_imageRatioTarget()` returns the full ratio for any on-screen page.
  `focusDistance` still governs the reduction for genuinely off-screen
  cache-window neighbours, which is what #451 was actually about.
- `PdfLiveRasterHolder` gained `liveRasterOnScreen`, and `rebalance()`
  runs two passes over the same farthest-first order: every off-screen
  page first, and only if the total is *still* over budget does it reach
  the visible ones (zoomed far enough out, the visible set alone can
  exceed the ceiling - the valve has to stay open, it just isn't the
  first move any more).
- `evictReclaimable()` skips on-screen pages entirely. An on-screen page
  re-rasterizes the instant it is dropped, so evicting it under pressure
  buys a flicker and a *higher* peak - the same feedback loop
  `adaptive_memory.dart`'s `registryMaterialityPercent` comment documents
  from the 2026-07-29 trace.
- `didUpdateWidget`'s `droppedForFocus` also fires on
  `!oldWidget.onScreen && widget.onScreen`, so a page that scrolls in
  upgrades its reduced buffer on arrival instead of waiting to become the
  centre page.

## Where `onScreen` comes from

`_updateCurrentPage` already unprojected the viewport centre through the
zoom window and walked the page offsets; it now computes the viewport's
main-axis *span* in the same pass and records the first/last overlapping
index (`_setOnScreenRange`). One loop, same cost, and `currentPage` keeps
its exact old rule (the spacing after a page counts as that page) so page
numbering and render focus are untouched.

Two things worth knowing:

- **It rebuilds when the span changes.** Previously the page views only
  learned their new `focusDistance` at the 200 ms transform settle or the
  500 ms scroll settle, so a page crossing the edge kept its stale
  prefetch treatment for the whole gesture and then re-rendered in a batch
  at the settle - part of why the pop was so visible. The span changes at
  most a couple of times per page crossing, so this is far cheaper than a
  per-frame rebuild, and it lands the flag when it matters.
- **Scroll listeners can fire during layout**, so a mid-frame span change
  defers its `setState` to a post-frame callback - the same hazard
  `PdfViewerController._notifySafely` guards.

## Testing notes

`test/page_on_screen_test.dart` covers the viewer half. Gotcha: the
prefetch band is *offstage* - pages inside the list's 250 px cache extent
but past the viewport edge are laid out and not painted, so
`find.byType(PdfPageView)` misses them. Pass `skipOffstage: false` or the
"off-screen but mounted" case looks like "not mounted at all". At the
800x600 test surface with the 612x792pt fixture at fit-width each page is
1035.3 px tall and the band is narrow: scroll offset 440 has page 1
mounted and off-screen, 460 has it visible.

One test pins `onScreen` to `PdfViewerController.visiblePageRegion`
across a sweep of offsets, so the flag and the thumbnail strip's viewport
indicator can never drift apart about what "visible" means.

Budget ordering is unit-tested against fakes in
`test/live_raster_budget_test.dart` (the fake defaults to "only the
focused page is visible", the shape the pre-existing ordering tests
assume; the new cases pass `onScreen` explicitly).

## Follow-up: initialising the span

A document that opens and is never scrolled or zoomed calls neither
`_onScroll` nor `_onTransformChanged`, so the span stayed at `(-1, -1)` and
`_onScreenPage` fell through to its pre-layout "everything is visible"
answer - safe (it never blanks a page) but it skipped the prefetch
reduction on the pages behind the fold for the whole session. The build's
initial-fit block now takes the measurement in a post-frame callback, once
the extents that layout creates exist.

Testing that needs a viewport where a *third* page lands in the cache
window at rest, which the full-width fixture cannot produce (at 800px wide
each page is 1035px tall and page 1 is not built until it approaches). A
300px-wide viewer makes each page 388px tall: pages 0 and 1 share the
screen and page 2 sits below the fold, built and off-screen.
