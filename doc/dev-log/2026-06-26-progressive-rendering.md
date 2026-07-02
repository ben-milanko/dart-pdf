# Progressive rendering: paint vector/text first, drop the raster in late

## Why

After the image-resolution cap landed, a heavy CAD page could still take
~10 s to appear: the render worker decodes the page's raster underlay
(JBIG2/CCITT/Flate over 100+ megapixels — a sequential, full-image decode)
*before* it returns the command buffer, so the page stays blank until that
finishes. Profiling the decode path showed the sample decode — not the RGBA
expansion the cap removes — dominates that time and can't be skipped for
these formats. So instead of shaving decode time, make the page *usable*
while it decodes.

## What

A fast first pass that paints the page's vector/text immediately, then the
existing full pass re-rasters with the images once they're decoded.

- `PdfRenderWorker.record(..., decodeImages: false)` records the page but
  ships its images **un-decoded** (just their streams), so the buffer comes
  back in ~1 s even on a page whose underlay takes seconds. Threaded through
  the abstract, isolate (`request[4]`), and web (`decodeImages` postMessage
  field) backends; the web entry defaults it true so an older client still
  decodes.
- `PdfPageRenderer.pictureFromCommands(..., includeImages: false)` skips
  image decoding entirely and replays with an empty image map — the
  `CanvasPdfDevice` draws the linework and skips every image.
- `PdfPageRenderer.hasImageDraws(commands)` tells the page whether a slow
  full pass needs to follow the fast one.
- `_PdfPageViewState._paintVectorFirst` (run from `_renderNow` on the first
  interpret) does the fast record → vector-only picture → raster → paint.
  It deliberately leaves `_rasteredRatio` null so the full pass's
  resolution-unchanged guard doesn't skip the re-raster that brings the
  images in, and only adopts its raster if the full pass hasn't already
  landed. When the page draws no images the fast buffer is the whole page,
  so it's cached as `_picture` and the full pass reuses it — no second
  record.

No color-conversion code changed, so Ghent/PDF.js baselines are untouched.

## Trade-offs / follow-ups

- Image-bearing pages now record twice (vector, then full) — the content
  walk runs twice in the worker, off the UI thread. Wasteful for light
  pages but invisible (both fast); the win is all on heavy pages. A future
  optimization could have the worker keep the buffer and decode-on-demand
  to avoid the second walk.
- A full-page scan with little vector content shows mostly blank during the
  fast pass (then fills in) — still strictly better than blank-for-10 s.
- Still ahead (the other phases discussed): downsample-on-decode (drop the
  489 MB allocation + filter pass) and re-decode the visible region sharper
  on deep zoom.
- Reminder: all of this runs in the worker bundle (`pdf_render_worker.dart.js`),
  which is compiled separately — it must be rebuilt
  (`dart run dart_pdf_editor:build_web_worker`) for the change to take effect
  on web.
