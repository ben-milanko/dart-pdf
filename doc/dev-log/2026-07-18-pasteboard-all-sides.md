# Pasteboard: a drawable band on all four sides of the page

Follows 2026-07-16-pasteboard-off-page-authoring.md (which added the
left/right band) and the merge reconciliation with the page-layout
(main/cross axis) refactor. Two fixes and one feature here.

## Gap-on-zoom fixes (why the pages looked wrong when zooming)

1. **Page spacing didn't scale with layout zoom.** `pageSpacing` was a
   constant added to each slot, but `_pageMain`/`_pageCross` scale with
   `_layoutZoom`. Below fit the pages shrank while the gap stayed fixed, so
   the gap grew *relative* to the pages. Fix: `_spacing = pageSpacing *
   _layoutZoom` (at fit it is still exactly `pageSpacing`; above fit the
   transform scales the whole list). Every layout site uses `_spacing`.

2. **The pasteboard inset was a constant while the tile scales.** The tile
   is `_crossFactor * viewport = layoutZoom * viewport`, but the page was
   inset by a constant `_pasteboardX`. Below fit the raster then fell short
   of its (shrunken) tile and, keeping aspect, came up short vertically too
   - a big vertical gap that grew as `~aspect * 2*margin * (1-layoutZoom)`.
   Fix: pass `pasteboard: _pasteboardX * _layoutZoom` to `_PdfViewerPage`,
   so the inset tracks the tile and the raster fills it at every zoom.

## Feature: top/bottom band (draw above and below a page)

The band was left/right only; panning up at the top of the document did
nothing because there was no space above the first page. Now every page is
framed by a uniform band on all four sides.

- `_pbMain = _pasteboardX * _layoutZoom` - the main-axis (top+bottom) band,
  the same on-screen size as the cross band.
- Each page's scroll slot grows by `2*_pbMain`: `_scrollExtentOf` and the
  `itemExtentBuilder` add it, and the inline slot-advance loops (current-page
  detection, `_captureViewport`, render-warm heuristic) add `2*_pbMain` too.
- `_mainOffsetOf(index)` was redefined as *the raster top* =
  `_slotStart(index) + leadingSpacing + _pbMain`, computed from the shared
  `_scrollExtentOf`. Every search / jump / viewport-restore site already adds
  a within-page fraction of `_pageMain` to `_mainOffsetOf`, so folding the
  top band into `_mainOffsetOf` keeps all of them correct with no per-site
  change. Verified the capture/restore round-trip algebraically and with the
  viewport tests.
- `_pagePointAt` / `_pageContainsListPoint` were rewritten to use
  `_mainOffsetOf` instead of their own (now band-inexact) `mainStart`
  accumulation.
- `_PdfViewerPage`: `Padding(EdgeInsets.all(pasteboard))` and the editing
  overlay's geometry `origin: Offset(pasteboard, pasteboard)`, `viewSize`
  reduced on both axes - so a gesture in the top band maps to a PDF `y`
  *above* the crop box (PDF y grows upward).

At the top of the document the first page's top band is simply visible above
the page (no special overscroll needed); the last page's bottom band sits
below it. Still opt-in via `PdfViewer.pasteboardMargin` (0 = off, so the
whole existing suite and default view are unchanged); horizontal layout
keeps the band off for now.

## Tests

- `pdf_page_spacing_test.dart`: gap-ratio-across-zoom, now run with the
  pasteboard on *and* off (the on case used to blow up zooming out).
- `editing_pasteboard_test.dart`: a stylus stroke in the **left** band
  authors an off-page `x < cropBox.left`; a stroke **above** the page
  authors an off-page `y > cropBox.top`; and off-page ink round-trips
  through save/reload.
- Full scroll-geometry suites (viewer, viewport capture/restore,
  exact-extent, scrollbar, horizontal layout) pass unchanged at
  `pasteboardMargin: 0`.
