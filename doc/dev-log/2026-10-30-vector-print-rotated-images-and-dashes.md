# Vector print: rotated images and dashed lines on Windows

A user printed a Word-exported Design Change Notice on Windows and got two
defects, both in the GDI replay of the vector-print stream (`VPR1`, see
2026-07-17-vector-print-windows-linux.md):

1. **Logos printed squashed and streaked.** The letterhead JPEGs are stored
   portrait (41x173, 104x493) and placed under the page's 90deg CTM with a
   flipped `cm`. `ReplayImage` in `dart_pdf_printing/windows/native_print.cpp`
   blitted every image into its device bounding box with `StretchDIBits`,
   ignoring rotation and mirroring - a tall image stretched into a wide box.
2. **Dashed lines printed solid.** `ReplayStroke` read the dash array and
   discarded it ("solid fallback").

Cairo (Linux) was already right on both; it takes the full matrix and
`cairo_set_dash`.

## Fix - in the encoder, where it is testable

`pdf_graphics/src/vector_print.dart`:

- `uprightVectorPrintImage` normalizes any quarter-turn/mirror placement to an
  upright axis-aligned quad (a > 0, d < 0, b = c = 0) by rearranging pixels -
  exact and lossless. Tested over all 8 orientations by sampling every device
  point before and after, plus a letterhead-shaped PDF.
- `strokePath` pre-dashes: `flattenPath` (tolerance 0.01pt) + the strip
  rasterizer's `dashSubpaths`, emitted as a solid stroke with dash count 0.
  Zero-length dashes become zero-length lines so round caps still dot. A
  pattern with no positive length (or a negative entry) strokes solid,
  unflattened. The byte layout is unchanged; readers still honour a non-zero
  count.

Windows also gained a `SetWorldTransform` (GM_ADVANCED) path for images
placed at a non-right angle or skewed, which the encoder leaves alone. That
native code cannot be built in the Dart CI container - verify on a Windows
printer/"Microsoft Print to PDF".
