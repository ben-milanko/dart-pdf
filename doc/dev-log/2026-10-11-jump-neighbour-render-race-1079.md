# 2026-10-11 - #1079: off-screen neighbours no longer render beside the focused page

## The race

On `parity-plan` the jump back to page 7, right after the jump to page 8, was
bimodal: either about 20 ms ready (a cached raster) or 300–1200 ms. A
diagnostic build logged `PdfPageView._render`'s off-screen decision for every
page (`apply_variant.py diag1079` in the session scratchpad). It showed the
cause.

- `_render()` already declined an off-screen page with **nothing to paint**,
  which is the documented intent: "do not turn cache-window placeholders into
  first-render worker jobs" beside the page the user jumped to.
- A neighbour that **already painted something** (a preview, a retained picture
  from an earlier pass) skipped that guard. When the render hold released at the
  jump, it was granted beside the focused page (`scheduler grant page=7 focus=8`,
  `raster ... conc=2`).
- Whether page 7 held anything at that moment depended on the order the
  command-warm queue happened to run. So the jump-back was sometimes fast, and
  whenever it was, the page the user had actually asked for (8) paid for it.
  Page 8 and its neighbour shared the worker and the raster thread: page 8's
  interpret wait was 420 ms against 263 ms.

## The fix

`_render()` now applies the off-screen deferral to any page that is not the
focus (`focusDistance != 0`) and isn't geometrically on screen, whatever it
holds. Such a page sets `_deferredOffscreenRasterRefresh`, cancels its queued
request and schedules the visibility check. The page then refreshes when it
enters the viewport, through the existing `didUpdateWidget` and post-frame
paths. Preparing neighbours ahead of time is left to `PdfPageRasterWarmPolicy`,
which the DartPDF app already sets to `nearby()` (`app/lib/devtools.dart`).

Test: `pdf_page_view_test.dart`, "an off-screen neighbour that already paints
defers its re-render until visible (#1079)". A visible page renders, becomes
the off-screen neighbour, and then a device-pixel-ratio change asks every page
for a new raster. The neighbour must stay at its old width until it comes back
on screen. The test fails on `main`, where the neighbour re-renders to 1224 px.

## Measured

Chrome for Testing 154, SwiftShader container, `parity-plan`, DartPDF only,
interleaved. Three passes of `main` against the fix (4, 4 and 6 clean runs per
side), with the harness default of warm off:

| metric | `main` | fix |
|---|---|---|
| page-stable p95 | 1166–1526 ms | 599–844 ms |
| jump to page 8 (p50 of runs) | 1147–1231 ms | 517–520 ms |
| jump back to page 7 | 546–596 ms (bimodal) | 239–300 ms (steady) |
| page-stable p50 | 529–558 ms | 464–515 ms |
| wheel journey p50 | 1166–1528 ms | 845–964 ms |
| wheel rAF p95 (median of runs) | 217–250 ms | 100–117 ms |
| peak browser RSS (pass 2) | 2064 MiB | 1833 MiB |

- **Open was unchanged** (3093 vs 3106 ms median in pass 3). One earlier pass
  showed the fix about 10% slower at open, but every open phase was uniformly
  slower in those runs, worker startup included, which runs before any page
  view code. It didn't reproduce.
- **The jump to page 4 and zoom were unchanged.**
- **The wheel gain has the same cause.** Neighbours no longer re-render
  off-screen while a wheel gesture is moving pages through the cache window.

## With the app's warm policy (`warm=nearby`)

One pass of 4 runs per side:

| metric | `main` | fix |
|---|---|---|
| page-stable p50 | 534 ms | 433 ms |
| page 7 ready | 20–277 ms | 17–119 ms |

Zoom p50 was 295 ms for the fix with `nearby` in that pass, against 135 ms for
`main`. But `main` with `nearby` measured 291 ms in an earlier pass, while
every warm-off arm stayed at 122–135 ms. So it's the warm's idle raster
landing on top of the zoom, a pre-existing interaction of the warm policy,
not this change. Worth its own look before the warm becomes a library default.

## Notes

- The measurement harness mounts the viewer with warming disabled
  (`?warm=off`), unlike the app. `?warm=nearby` reproduces the app.
- A cold neighbour that becomes visible purely by moving inside a bare `Stack`
  (no viewer, no scale change) never asks to render. The viewer drives that
  through its on-screen span, so the test mounts the second page fresh instead.
