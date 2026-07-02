# Capping embedded-image resolution to kill raster-thread jank

## Symptom

Panning a 58 MB CAD document (mixed raster + vector, ~40+ sheet pages) on
**web (CanvasKit/WASM)** janked badly — not during the drag, but as each
scroll settled. A `PDF_PERF_LOG` (`?perf=1`) trace was decisive:

- Every interpret was `path=worker` — the render worker was already doing
  its job; interpretation was *not* the bottleneck.
- Every janky frame was **raster-bound**: `build` was <10 ms while `raster`
  ran 150–650 ms. So the cost was on CanvasKit's (single, on web) raster
  thread, not the UI isolate.
- The worker result sizes were the smoking gun: `webworker result page=30
  639,867,067B` — a **640 MB** decoded-pixel payload for one page, and
  ~70 MB each for pages 33–36. These pages embed full-resolution scanned
  raster underlays (page 30 ≈ 160 megapixels, ~12 600²).

Root cause: images were decoded, shipped across the worker boundary, drawn
into the page picture, and rasterized (`picture.toImage`) at **native
resolution**, regardless of the page's on-screen size. Two compounding
effects:

1. Each `toImage` of a picture wrapping a 640 MB texture is a 150–650 ms
   single-threaded GPU readback on web.
2. A single 640 MB image exceeds the whole `PdfImageCache` budget (256 MB),
   so `put` keeps it only until the next insert evicts it — it **never
   stays cached**. Every settle re-requested it from the worker (640 MB
   `postMessage` again) and re-rasterized it, producing a *train* of
   180–260 ms raster-jank frames at a fixed scroll position.

## Fix

Downsample each decoded image to ~display resolution **in the worker,
before serialization**, so the giant buffer never crosses `postMessage`,
fits the cache, and rasterizes in tens of ms.

- `serializeCommands(..., maxImagePixelRatio:)` (pdf_graphics
  `render_command_codec.dart`) caps each image after `decodePdfImagePixels`.
  The cap target is `2× (drawn-size-in-points × ratio)` — i.e. ~2× the
  pixels the image covers on screen (`PdfMatrix` column lengths give the
  drawn point size; `ratio` is screen px/point incl. device pixel ratio).
  Hard ceilings (`_maxImagePixels` = 1<<24, `_maxImageDimension` = 8192)
  mirror the viewer's full-page raster caps so even a sheet-sized underlay
  stays cacheable and within a GPU texture limit. Null ratio = historic
  native behaviour; only consulted when `decodeImages: true` (worker path).
- `downsamplePdfDecodedPixels` (pdf_graphics `image_pixels.dart`) — an
  area-average (box filter) resampler over premultiplied RGBA. Local int
  accumulators (safe on web's float64 ints and native 64-bit); never
  upscales.
- The `ratio` is threaded from the viewer through the worker protocol:
  `PdfRenderWorker.record(..., imagePixelRatio:)` → isolate message
  (`request[3]`) and web `postMessage` (`imageRatio` field) → both
  `_recordPageAsync`s. `PdfPageView._interpretPicture` passes
  `_effectiveRatio()`; the preview prerender and editing thumbnails pass
  their (small) raster ratios so they no longer ship full-res underlays
  just to be downscaled into a 200 px tile.

### The cache-key trap

`PdfImageCache` is process-wide and keys inline (worker-sourced) images by
stream **content**. Once images are capped *per call*, the same source
image can be decoded at two sizes — sharp for the on-screen page, tiny for
its 200 px preview/thumbnail. Content-only keying would let one resolution
evict and stand in for the other (a blurry page, or a needlessly huge
preview). `pdfImageKey` now folds the decoded dimensions into the key
(`PdfSizedImageKey`) when a request carries worker-decoded pixels, so each
resolution caches independently. Local renders (`decoded == null`) keep the
plain content key — unchanged.

## Trade-off (chosen by the user)

The deep-zoom detail patch (`PdfPageView._updateDetail`) re-rasters the
visible region from the *same* cached picture — it does not re-decode — so
under deep zoom an image softens at this cap rather than re-sharpening. The
`2×` headroom keeps normal viewing (and one zoom-doubling) sharp; a future
follow-up could have the detail patch re-decode the zoomed region at higher
resolution. The absolute 16.7 Mpx ceiling is what actually fixes the cache
thrash: every page now fits the 256 MB cache (~4 heavy pages), so a settled
scroll reuses the raster instead of re-decoding it.

## Tests

- `pdf_graphics/test/image_downsample_test.dart` — box-filter correctness
  (averaging, no-upscale, clamps, degenerate target).
- `render_command_codec_test.dart` "image resolution cap" — tiny ratio
  shrinks, huge/null ratio leaves native, transcript unchanged (pixels only).
- `render_worker_test.dart` — end-to-end: `record(imagePixelRatio:)` ships
  fewer pixels than the uncapped record.

Ghent render baselines are untouched: the cap is worker-only and those
tests render directly (no worker, no ratio).
