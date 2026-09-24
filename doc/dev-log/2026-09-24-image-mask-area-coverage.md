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
are skipped, and the rest are split at cell boundaries and counted with a
popcount per piece. The byte-to-cell split is identical for every row, so it
is planned once per decode (`pieceStart`/`pieceColumn`/`pieceMask`).

Cost, 7360x5239 stencil, VM, scaling only (CCITT decode excluded):

| content | point sample | coverage |
| --- | ---: | ---: |
| blank paper (0xff), ->1500 wide | 16ms | 19ms |
| all painting (0x00), ->1500 wide | 13ms | 62ms |
| alternating bits (0x55), ->1500 wide | 13ms | 76ms |

A first cut looped per bit over every painting byte and cost ~200ms on the
dense rows - a `/Decode [1 0]` stencil, where the paper is what paints, hits
exactly that case. The adversarial review caught it. A randomized test in
`image_pixels_test.dart` compares against a brute-force per-bit box filter
across odd widths, mid-byte regions and both polarities.

## Not done

`_scaledIndexed1Region` still point-samples both its palette indices and its
stencil `/Mask`; same symptom is possible on 1-bit Indexed CAD underlays.
