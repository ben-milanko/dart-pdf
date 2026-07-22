# 2026-07-22 — cap prefetch image resolution (#451, issue #1)

A single page record reached 39 MB on the #451 mobile-web trace because
FlateDecode images (unlike DCTDecode, which ships raw for the browser codec)
decode in pure Dart and ship as **full RGBA at 2× headroom**. Those big records
are shipped for **prefetched neighbours** too — pages the user isn't looking at —
so they compete with the visible page on the single effective worker.

## Change

Off-focus (prefetch) pages decode their embedded images at a reduced
resolution; the focused page always gets full resolution.

- `PdfPageView.focusDistance` (0 = the page the viewport is on), wired from the
  viewer as `|index − focusPage|` (mirroring `_renderPriority`).
- `_imageRatioTarget()` multiplies the display image ratio by
  `PdfPageView.prefetchImagePixelRatioFactor` (0.5) when `focusDistance > 0`.
  Only images shrink — vectors/text are resolution-independent commands.
- Invalidation: `_pictureImageRatio` records the ratio a buffer was built at.
  `didUpdateWidget` drops a reduced buffer's *picture* when the page moves closer
  to focus (`focusDistance` decreases) so it re-renders sharp, guarded on an
  actual ratio increase (fires once on approach, not a churn loop). It leaves the
  reduced base raster up (right geometry, soft images) until the full one
  replaces it, so a page scrolling into focus never flashes blank. The three
  preview/full-raster cache seeds are gated on `_renderedAtFullImageRatio()`, so
  a reduced prefetch raster never seeds the dimension-keyed shared cache (which
  would let `_restoreFullRaster` serve it back blurry to a now-focused page).

The worker transcript cache keys on `(page, annotations)` and holds the *command
graph* only — images are decoded at serialize time per the request's ratio — so
a full-res focus request re-decodes full images even on a command-cache hit.
No transcript-key change is needed.

## Measured (real Chrome, `tool/perf.sh` web harness)

A 6-page synthetic doc, two 4200×2700 FlateDecode underlays per page (the #451
image shape). One scroll run, `PERF_VERBOSE` scraping the worker record log:

```
                  record     images decoded
  focus/settled   45.0 MB    11.1 Mpx   (pages that settle under the viewport)
  prefetch        11.8 MB     2.8 Mpx   (neighbours scrolled past)
```

**Prefetch neighbour records drop 45 → 11.8 MB (~74%, the 4× the 0.5 factor
predicts).** Pages that settle as focus ship full resolution (11.1 Mpx), so the
page being viewed is unaffected — confirmed by the per-page `decodedMpx` in the
trace, not just the byte count. Frames stayed healthy (buildP50 1.1 ms, no new
jank). In the #451 trace shape (viewing page 0, prefetching 1 & 2) this saves
~58 MB of prefetch traffic and frees the worker to serve the visible page.

An earlier run with 1600×1100 images showed only 3.5 → 2.8 Mpx — those images
are near their display size, so the display cap barely binds and the reduction
looks small. The cap (and the win) only bind hard on genuinely
over-resolution artwork, which is exactly #451's class.

## Not addressed here

#451 issue #2 (background prerender should preempt the visible page on the
worker) and the visible-page 39 MB record itself (that needs progressive
first-record resolution, not a prefetch cap). This is issue #1.
