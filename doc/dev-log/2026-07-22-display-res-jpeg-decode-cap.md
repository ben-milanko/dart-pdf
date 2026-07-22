# 2026-07-22 — cap the UI-thread JPEG decode to display resolution (#458)

## The report

An 8.2 MB single-page survey/CAD drawing (`BROCKRDLXDRG00116`) rendered
badly, worst on web. Structure (via `CosDocument` inspection):

- 1 page, A1-ish landscape.
- **Two 9460×2918 `DeviceRGB` `DCTDecode` underlays** (82.8 MB decoded RGBA
  each), each with a **9460×2918 `DeviceGray`, non-DCT (Flate) `/SMask`**
  (27.6 MB each).
- 71 optional-content layers, ~94 content streams.
- ~258 MB of decoded image bytes on one page; the two tiles + masks are
  ~220 MB of it.

## Root cause

A non-CMYK `DCTDecode` base needs the platform JPEG codec, so it can never
be decoded in the pure-Dart worker (`decodePdfImagePixels` returns null).
The render worker therefore ships it **un-decoded at native resolution**
(`render_command_codec.dart` `_decodeImageForCommand` returns null → the raw
stream is inlined), and the UI thread decodes it in `image_decoder.dart`'s
`_decodeOne` via `ui.instantiateImageCodec(jpeg)` **with no
`targetWidth`/`targetHeight`** — full native 9460×2918. Then, because the
soft mask is non-DCT, the code pulls the base back with
`base.toByteData(rawRgba)` (~110 MB) and runs `pdfApplyImageAlpha` — a
27.6 M-pixel alpha-multiply — per tile.

This is exactly **#458** ("perf(web): the worker's browser JPEG decode
silently declines, so the main thread pays 643 ms"): the device trace shows
`decode=643.4ms` for two `/DCTDecode` images on the UI thread under
CanvasKit. On web it is worse than desktop three ways: the `toByteData`
readback is a slow GPU→CPU copy, the pixel loops run as compiled JS, and
9460 px exceeds the common **8192 px GPU max texture** dimension. And
~220 MB overruns the web image-cache budget (128/64 MB), so it re-decodes on
every settle.

## The fix

Cap every locally-decoded image to display resolution, reusing the exact
cap the worker already applies (`cappedImagePixelSize`, headroom 2×, 8192-px
max edge, 16 MP ceiling).

- `decodeImages(cos, requests, {maxImagePixelRatio})` computes a per-image
  target from the image's native dims, its on-page footprint
  (`PdfImageRequest.transform`), and the ratio. With no ratio it still
  applies the hard ceilings (8192-px edge, 16 MP), so no path ever hands the
  engine a texture past the GPU limit.
- `_decodeOne` decodes to the target: the pure path via
  `decodePdfImage(targetWidth, targetHeight)`, the JPEG path by passing
  `targetWidth/targetHeight` to `instantiateImageCodec` (the browser
  downscales during decode), and the soft mask is fitted to the base
  (`_fitMask`) so the composite stays at the target instead of ballooning
  back to a mask larger than the capped base (`pdfApplyImageAlpha` upsamples
  the *base* to the mask otherwise).
- Cache-key split: the returned per-render `images` map still keys by the
  ratio-independent `pdfImageKey` (the paint side has no ratio and must
  match), while the shared `PdfImageCache` keys by a size-qualified
  `PdfSizedImageKey` so two zoom levels of the same image don't evict or
  stand in for each other. `PdfSizedImageKey.content` was generalised from
  inline-only to any content key.

Wiring — every path that decodes locally now passes the display ratio:

- `renderImageWithPlan` → `renderPictureWithPlan` /
  `renderPictureRecordedWithPlan` / `_renderImageStrips` (the last one so the
  strip device stays pixel-parity with the canvas device).
- `pictureFromCommandsWithPlan` (the worker-fallback replay).
- `PdfRetainedScene.record` / `fromCommands`, and the viewer
  (`pdf_page_view.dart`) passes the **same** `imagePixelRatio` it gives the
  worker into the fallback decode — so the JPEG the worker declined is capped
  to the size the worker intended. This is the path that actually pays the
  #458 643 ms.

## Measured

A/B on the DCT fixture (`raster-underlay-mixed`, two 9460×2918 JPEG
underlays + Flate soft masks), same decode path, desktop headless engine:

```
native (no cap)   694 ms   -> 9460x2918, 9460x2918   (~220 MB RGBA)
display-capped     258 ms   -> 2384x1684, 2384x1684   (~24 MB RGBA)
```

**2.7× faster decode, ~9× less resident image memory** — and the capped
texture no longer exceeds the 8192-px GPU limit, and 24 MB fits the web
cache budget (no re-decode thrash). Web (CanvasKit WASM, where the readback
is a GPU round-trip) is where the 643 ms lives, so the win there is larger.

## Fixture

Added the synthetic twin of this document class (see
`test_corpora/dartpdf/README.md`):

- `pdf_test_fixtures` `buildSyntheticRasterUnderlaySheet` +
  `gen_raster_underlay_pdf.dart` (`faithful` = hermetic Flate, `mixed` = DCT
  via `cjpeg`).
- Committed `test_corpora/dartpdf/raster-underlay-1p.pdf` (Flate, 1.1 MB) via
  `tool/gen_corpus.sh`.
- `raster-underlay-render` flutter-render perf scenario over the pre-seeded
  DCT variant (`gen_perf_docs.sh`) — the one that exercises the platform-JPEG
  pathology a vm-sweep can't.

## Tickets

- **#458** — directly addressed: the UI-thread JPEG decode is now capped to
  display resolution on the viewer's worker-fallback path (and every other
  local decode). Complementary to #458's other angle (getting the web
  worker's browser codec to stop declining); even a fixed worker should
  decode to this same cap so records don't balloon (cf. #451).
- **#427 / #405** (RSS / live-raster budget) — related: reduces the
  decoded-image cache footprint (220 MB → 24 MB on this class), though
  #427's specific numbers are page rasters, not document images.

## Follow-ups / notes

- The synchronous `renderImage` path now matches the viewer's worker path
  (which already capped), which shifts 5 Ghent render baselines by <1% —
  all localized to embedded raster reference images (edge resampling), not
  vector/text. Verified against the dumped diffs; re-baseline is a deliberate
  `GHENT_UPDATE` decision (excluding the pre-existing GWG030 hard failure).
- Adding `raster-underlay-1p.pdf` to `test_corpora/dartpdf/` changes the
  `dartpdf-corpus` sweep set — the counter baseline wants a deliberate
  `tool/perf.sh gate --update-baseline`.
