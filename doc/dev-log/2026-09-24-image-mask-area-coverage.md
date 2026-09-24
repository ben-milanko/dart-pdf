# Scaled /ImageMask stencils: area coverage instead of point sampling

## Symptom

Scanned engineering drawings (e.g. a Victorian Railways signalling plan: a
7360x5239 1-bit CCITT G4 `/ImageMask` per page, shown ~1500px wide) rendered
with dashed, broken and missing linework, while Bluebeam/Acrobat/PDFium show
continuous (lighter) strokes.

## Cause

`decodePdfImagePixelsRegionScaled` routes a stencil to
`_scaledImageMaskRegion` (pdf_graphics `image_pixels.dart`), which picked
**one source bit per destination pixel**. At a ~2.5-5x reduction most 1-2px
strokes fall between samples. The sibling `_scaledGray1Region` already
box-filtered; the stencil path never did.

## Fix

`_scaledImageMaskRegion` now writes each destination pixel's alpha as the
fraction of painting bits in its cell (premultiplied white, tinted by the
device's `srcIn`). The cell partition and truncation match
`downsamplePdfDecodedPixels`, so fast path and full-decode fallback agree.
Rows are walked a byte at a time; bytes with no painting bits (blank paper)
are skipped, so the cost stays close to point sampling: on the drawing above
the whole decode (CCITT included) went ~105ms -> ~164ms on the VM.

## Not done

`_scaledIndexed1Region` still point-samples both its palette indices and its
stencil `/Mask`; same symptom is possible on 1-bit Indexed CAD underlays.
