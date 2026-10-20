# Thumbnail strip: per-tile viewport frame and a soft-preview seed watch

Every tile in the thumbnail strip (and in the `PdfThumbnailView` grid, which
builds the same `_PageTile`) drew its current-page outline and viewport mark
inside a `ListenableBuilder` over `viewerController` merged with
`viewerController.viewportChanges`. The builder's closure built the whole
tile body: the `Container` ring, the `Stack`, `RepaintBoundary(_PageThumbnail)`
and both devtools overlays (`ValueListenableBuilder<bool>` each). So every
viewer scroll tick rebuilt that subtree on every mounted tile, including the
tiles whose mark was null before the tick and still null after it.

`viewportChanges` exists so scrolling does not spam controller listeners
(see 2026-08-10-visible-page-prefetch-demotion.md for the house pattern:
subscribe, recompute your own answer, setState only when it flips). The tile
subscribed correctly and then rebuilt everything anyway.

## What changed

1. **`_TileViewportFrame`** (editing_thumbnails.dart). A small
   `StatefulWidget` that listens to `viewerController` and `viewportChanges`
   itself, caches `(currentPage == pageIndex, visiblePageRegion(pageIndex))`,
   and calls setState only when that pair changes (`Rect?` has value
   equality). `_PageTile` builds `RepaintBoundary(_PageThumbnail)` and the two
   `Positioned.fill` overlays and hands them in as fields, so a frame rebuild
   gives Flutter the same widget instances and it skips them. Paint order is
   unchanged: thumbnail, viewport `CustomPaint`, overlays. It rebinds in
   `didUpdateWidget` (and re-reads there, since the parent rebuilding is the
   other way the answer can change) and unlistens in `dispose`.

   Not a `CustomPainter` with `repaint: viewportChanges`. That moves the cost
   from build to paint and loses the existing skip: today a tile whose region
   is null or unchanged does not repaint at all
   (`_ViewportPainter.shouldRepaint` compares the region, and a `RawImage`
   fed a clone does not repaint). A repaint listenable would re-record every
   mounted tile's layer on every tick.

2. **The seed watch** in `_PageThumbnailState`. The per-tick rebuild was
   load-bearing: `_seedPlaceholder()` (clone the viewer's soft preview from
   `pagePreviewCache.imageFor`) only runs in `build`, and nothing else told a
   blank tile that its page's preview had landed. The shared thumbnail queue
   deliberately holds visible tiles' own renders while the viewer is busy
   (`PdfThumbnailCache`'s foreground gate and `shouldDeferUiWork`; the test
   "visible tile renders also stand down for the viewer"), so mid-scroll the
   viewer preview is the only thing a tile can show. With the body simply
   hoisted out of the builder, a tile that mounted before its page's preview
   existed stayed blank paper for the whole scroll.

   So while `_image == null && _placeholder == null` the tile listens to the
   same two viewer notifiers plus `pagePreviewCache` (a `ChangeNotifier`),
   and setStates when `pagePreviewCache.has(pageIndex)` becomes true; `build`
   then seeds the placeholder as before. `has()` is true exactly when
   `imageFor()` returns an image (both read the base and intermediate tiers).
   The cache's identity follows the viewer's state, so it is re-resolved on
   each notification. `_syncSeedWatch()` runs from `build` and detaches once
   the tile has a placeholder or its own raster; `didUpdateWidget` re-syncs
   when `viewerController` changes (with an assert that the watch never sits
   on a stale controller), and `dispose` detaches.

   Gotcha: the preview cache notifies from inside the viewer's
   `didUpdateWidget` (`_previews.clear()` on a paper-colour change,
   `rebind()` on an edit swap). A strip tile is not the viewer's descendant,
   so a setState there throws "setState() or markNeedsBuild() called during
   build". `_onSeedTick` checks `SchedulerPhase.persistentCallbacks` and
   re-checks in a post-frame callback instead.

## Measurements

Per-wheel-tick element rebuilds, attributed with `debugOnRebuildDirtyWidget`
+ `findAncestorWidgetOfExactType<PdfThumbnailSidebar>()`. Full app, the
checked-in `test_corpora/dartpdf/letterhead-report-40p.pdf`, 1600x1000,
30 ticks of 60px (a scratch harness, not committed). Deterministic:

| | strip / tick | rest / tick | total / tick |
|---|---:|---:|---:|
| main | 44.0 | 86.1 | 130.1 |
| this change | 6.4 | 86.1 | 92.5 |

Strip breakdown before: Positioned 14, ValueListenableBuilder<bool> 12,
ListenableBuilder 6, Container 6, `_PageThumbnail` 6 (six mounted tiles).
After: Positioned 2.2, `_TileViewportFrame` 2.0, Container 2.0,
ValueListenableBuilder<bool> 0.2 - only the tiles whose mark moved.

Frame times are not claimed from this branch. The same harness also records
debug-mode BUILD/LAYOUT per tick. Over 5 interleaved process-level rounds
every round favoured the change, but LAYOUT moved by the same 1.2-2.5x as
BUILD, and layout is work this change does not touch. The machine was busy
with other jobs, so those numbers are process-to-process noise.

An earlier release-web measurement of the frame half of this design (a
prototype without the seed watch, which only listens while a tile is blank;
the strip beside the viewer on the wheel-letterhead journey, 6 interleaved
reps) put wheel-frame build P50 at 1.69 -> 1.49 ms (0.88x), with no change in
jank. It was not re-run for this branch. That is about 0.2 ms per scroll
frame, or roughly 1% of a 60 Hz budget: CPU and battery headroom while
scrolling, not a smoothness fix.

## Tests

`editing_thumbnail_cache_test.dart`, next to "visible tile renders also stand
down for the viewer" (a strip beside a live viewer, 8 pages, all tiles
mounted; a tile's own raster never lands under the fake clock, so a
`RawImage` in a tile can only be the viewer's preview):

- a preview injected after the tile mounted, then wheel ticks: the tile
  shows it;
- the same preview landing with no scroll at all: the tile shows it (this is
  the `pagePreviewCache` listener);
- with every tile seeded, wheel ticks rebuild no `_PageThumbnail`, rebuild
  fewer frames than ticks x tiles, and every tile's mark and 2px current-page
  ring still agree with `visiblePageRegion` / `currentPage`.

With the seed watch disabled (a plain child hoist) the first two fail.

## Left out on purpose

- `_onPreferences` still setStates unfiltered. No preference setter fires
  during a scroll, so filtering it is off the scroll path and risks a missed
  rebuild for no measured gain.
- The follow reveal: `_onViewerChanged` runs a 200 ms animated
  `Scrollable.ensureVisible` on every current-page flip, so the strip is
  animating for most of a continuous scroll. An earlier web measurement put
  that at a cost similar to this rebuild. Jumping or deferring it is a UX
  change and belongs in its own measured follow-up.
