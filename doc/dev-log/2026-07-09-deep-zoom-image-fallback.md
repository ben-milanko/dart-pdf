# Deep-zoom detail patch: re-decode every image type, not just Flate

## Symptom

At high zoom, raster images (a scanned map, a logo) looked soft while text
stayed crisp. Text is vector, so it re-sharpens at any zoom; images are
raster and re-sharpen only when the deep-zoom detail patch re-decodes the
visible slice at higher resolution.

The detail patch (`PdfPageView._updateDetail` →
`_detailPictureFromWorker` → `serializeCommands(imageDecodeRegion:)`) was
added in the resolution-cap follow-up (see
[2026-06-25-image-resolution-cap.md](2026-06-25-image-resolution-cap.md)),
so region re-decode already existed. But it only re-sharpened a narrow
class of images.

## Root cause

`serializeCommands`'s region path (`_decodeImageForCommand` in
`pdf_graphics/render_command_codec.dart`) re-decoded the visible slice
through `decodePdfImagePixelsRegionScaled` - a deliberately narrow fast
path that only handles **single-filter Flate** RGB/gray 8-bit and
Indexed-1-bit streams (plus 1-bit `/ImageMask` stencils). For anything
else the general decoder handles - an Indexed **8-bit** palette
(PNG-origin), an image with an `/SMask` (a transparent logo), an
ICC/CalRGB/Lab/Separation colour space, 16-bit, a stacked filter - the
fast path returns `null`.

When it returned `null`, the code fell straight through to the full-page
`_capImageResolution` branch, which caps to ~2× the image's on-screen
footprint at the **base** ratio. So those images stayed pinned at the
page-raster cap under deep zoom - exactly the asymmetry the detail patch
exists to remove. (Genuine platform-codec images - non-CMYK DCT/JPEG -
still decode `null` in pure Dart and ship un-decoded at native
resolution, so they were already sharp; they are not the issue.)

## Fix

In the region branch, when the fast path declines (`decoded == null`,
in-region, no predecoded pixels) fall back to decoding the whole image
once via the general `decodePdfImagePixels` and crop+downsample it to the
visible region with the existing `_cropDownsampleDecodedPixels`. Every
decodable image type now re-sharpens on zoom, keyed per region+resolution
by `_regionKeyStream` like the fast-path result. If the general decoder
also declines (returns `null`) the old full-page-cap fall-through is
unchanged.

Cost: the fallback decodes the full source image on the worker to crop a
small slice, where the Flate fast path decodes only the crop. This is
symmetric with the base render (which already decodes these images fully
via the same `decodePdfImagePixels`), runs off the UI thread, fires only
on settle, and is region-cached - acceptable for the sharpness win.

## Tests

- `render_command_codec_test.dart` "imageDecodeRegion sharpens images the
  fast path declines (SMask)" - an `/SMask`'d DeviceRGB image (the fast
  path is asserted to decline it) still comes back cropped, retargeted,
  and premultiplied through the fallback.

Ghent render baselines are untouched: the region re-decode is worker-only
and gated on `imageDecodeRegion`, which the direct (no-worker) Ghent
render path never sets.
