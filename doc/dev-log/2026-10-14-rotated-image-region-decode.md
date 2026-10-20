# Deep zoom re-sharpens rotated images (region decode took only axis-aligned)

A user reported that a combined drawing set stayed blurry at 3342% zoom. Its
first page is a 1200/300 dpi scan cut into 728 small `Indexed` 8-bit Flate
tiles, about 10 x 15 pt each. Each tile is placed **rotated 90 degrees**
(`0 10.306 -10.512 0 e f cm`), because the sheet is landscape on a portrait
`/MediaBox` with `/Rotate 90`. Vector pages in the same file sharpened fine.

## Root cause

`_imageRegionPlan` (pdf_graphics `render_command_codec.dart`) is how a detail
record (`imageDecodeRegion`) crops each image to the visible slice. It
returned `null` for any transform with a non-zero `b`/`c`. A `null` plan has
two effects:

1. The image is not cropped. It falls through to the full scaled decode at the
   zoom ratio.
2. `_imageBudgetScale` counts it at its **full** capped size, even when it is
   nowhere near the viewport. The budget it counts against is the region's own
   raster, which is viewport-sized.

So all 728 tiles counted against a budget sized for the ~24 tiles on screen.
`budgetScale` dropped to about 0.38, and every visible tile shipped well below
native, which looked worse than at moderate zoom. Measured on the reporter's
page 1 at ratio 33.42 with an 80 x 54 pt region:

| | images shipped | median decoded px/pt | record |
|---|---|---|---|
| before | 728 | 6.4 | 20.4 MB |
| after | 24 (rest are 1 px placeholders) | 16.7 (native 1200 dpi) | 4.9 MB |

## Fix

- `_imageRegionPlan` now accepts any invertible transform. The visibility test
  uses the page-space bounding box of the transformed unit square. The visible
  box is mapped back through the inverse transform to a unit-space crop. For
  axis-aligned transforms that is exactly the old arithmetic. For rotated or
  skewed ones it is the smallest source-pixel crop that covers everything
  visible. The cropped transform stays `crop.concat(t)`, so it lands where
  the full image did. If the mapped range is empty, the plan marks the image
  outside.
- The web worker's predecode skip (`_axisAlignedImageOutsideRegion` →
  `_imageOutsideRegion` in `render_worker_web_entry.dart`) uses the same
  bounding-box test. This keeps off-region rotated draws from being
  natively inflated and then thrown away by the serializer.

## Tests

`render_command_codec_test.dart`:

- "imageDecodeRegion crops and retargets a rotated image draw" checks the
  exact cropped transform and pixel for a 90-degree placement.
- "off-region rotated images do not shrink the visible one" places one
  visible rotated tile and 200 off-region ones. Before the fix the visible tile
  shipped at 9 x 9 instead of 100 x 100.

Both fail on the old code. The counter gate (`tool/perf.sh gate`) is
unchanged, since region records are not in the VM sweep.
