# Indexed images over a Separation/DeviceN base render (#430)

## Symptom

An `/Indexed` image whose base colour space is `/Separation` or `/DeviceN`
decoded to null and painted nothing. Both images on the Ghent DeviceN
conformance pages are exactly this shape, so `GWG080_DeviceN-Support_6c_x3`,
`GWG081_DeviceN-Support_5c_X1a`, and `GWG082_DeviceN-Support_4c_x3` rendered
with **no images at all** - the pages self-grade, and the ✗ / missing-image
markers showed through where the photos should be.

## Root cause

`_indexedPalette` (`packages/pdf_graphics/lib/src/image_pixels.dart`) sized a
palette entry from a device-family switch (`DeviceRGB`→3, `DeviceGray`→1,
`DeviceCMYK`→4) plus a `/Lab` special case. A `/Separation` or `/DeviceN` base
fell to `_ => 0` and the whole image was dropped. The machinery to decode
these already existed - `_alternateToRgba` pushes non-indexed Separation/DeviceN
samples through the tint transform, and `PdfColorSpace.parse` covers both
(including the `/Lab` alternate that `GWG081`'s DeviceN base uses).

## Fix

`_indexedPalette` now parses a Separation/DeviceN base through
`PdfColorSpace.parse` and runs each palette entry through
`toSrgbFromSamples` (the default decode → tint transform → alternate), exactly
as `_alternateToRgba` does per pixel. The component count is the parsed base's
`channels` rather than a device switch. This is palette work, not per-pixel:
at most 256 entries converted once per image, no per-pixel cost. Lab and the
device families keep their existing decode paths untouched (no baseline churn
for those).

## Test-tolerance narrowing

`ghent_render_test`'s `_knownBaselineDeviations` set tolerated these pages as
"colour handling not pixel-exact - still asserted non-blank". That tolerance
was broad enough to hide *both images failing to draw entirely*: the page was
non-blank (text + ✗ marks), so the assertion passed. `GWG080`/`GWG081` are now
removed from that set and pixel-enforced against fresh baselines, so a future
total image-loss is caught rather than tolerated. `GWG082` was already
enforced; its stale baseline (images missing, floating checkmarks) is
refreshed. All three baselines were regenerated with
`GHENT_UPDATE=1 ... --plain-name "DeviceN-Support"` after visually confirming
the photos render with plausible spot colours (violet for Pantone 265C, green
for GWG Green, cyan for GWG082).

## Not in scope

`2-SPOT/GWG030_Gray_K_black_OP_X1.pdf` fails the render baseline on `main`
already (a gray-K overprint page, unrelated to indexed DeviceN) - left as-is.
