# Extract a shared PdfColorSpace module (issue #310)

The knowledge "given a COS colour-space object, how many components does it
have and how do N component values become sRGB" was re-derived
independently in four places, each covering a slightly different subset -
and they had diverged: the interpreter's `sc`/`scn` path supported ICCBased
spaces, the shading path did not.

## What landed

New `pdf_graphics/lib/src/color_space.dart`: `PdfColorSpace.parse(cos,
object, {resources, iccCache})` returns a strategy exposing
`int channels`, `PdfColor toSrgb(List<double>)`, and
`PdfColor toSrgbFromSamples(List<int>)` (the image sample-decode helper, so
Lab keeps its L*/a*/b* default decode). The device families,
`PdfCalibratedColorSpace` (CalGray/CalRGB/Lab), `IccProfile` (ICCBased),
Indexed palettes, and Separation/DeviceN tint transforms are all internal
strategies behind that one interface. Pattern reports 0 channels;
`PdfColorSpace.deviceGray` is the const default. ICCBased exposes its parsed
profile via `iccProfile` for the image decoder's per-family LUT paths.

Callers now all consume it:

- **interpreter.dart** - deleted `_PdfColorSpaceResolver` /
  `_PdfResolvedColorSpace` (~220 lines). `cs`/`CS` call
  `PdfColorSpace.parse(..., iccCache: _iccCache)` (the interpreter keeps the
  ICC-parse cache so a space chosen in a tight `q`/`Q` loop parses once).
  `sc`/`scn` resolve through `_resolveScn`, which keeps the historical
  leniency: operands convert through the space only when their count matches
  its channels, else fall back to a device reading by count (`_colorFromValues`).
- **shading.dart** - `_colorConverterFor` / `_componentCount` deleted;
  `PdfShading.parse` reads `colorSpace.channels` / `colorSpace.toSrgb`. This
  is where the ICC gap closes for free - ICCBased shading spaces now convert
  through the profile instead of a device fallback.
- **mesh.dart** - `PdfMeshParser` takes a `toColor` converter (the shading's
  `PdfColorSpace.toSrgb`) instead of calling `colorFromComponents` directly,
  so Separation/DeviceN/ICCBased/CIE mesh shadings convert the same way
  axial and radial ones do.
- **image_pixels.dart** - `_AlternateColorSpace` + `_alternateColorSpaceFor`
  + `_alternateComponents` collapse to a two-line `_alternateColorSpaceFor`
  that returns the Separation/DeviceN `PdfColorSpace`; `_alternateToRgba`
  uses `.channels` / `.toSrgb`. `_iccProfileFor` is now a one-liner over
  `PdfColorSpace.parse(...).iccProfile`. The hot LUT/decode-range/fast-path
  and `_indexedPalette` machinery is untouched.

## Behaviour deltas (intended, all baselines still pass)

Unifying the fuller behaviour into every caller means a few paths that used
to fall back now convert properly: multi-colorant DeviceN `sc`/`scn`
(the old interpreter only wired single-colorant DeviceN, so a 2+-colorant
fill kept the previous colour), ICCBased shading/mesh/Separation-alternate
spaces, and Separation/CIE mesh shadings. The whole `pdf_graphics` suite -
including the Ghent and PDF.js render baselines - and the editor's
`mesh_shading` / `color_processing` / `page_color` tests pass unchanged, so
none of the checked-in corpus exercises those paths in a way that moves a
baseline beyond tolerance.

## New test

`test/color_space_test.dart` - the first direct test of the conversion
(previously only reachable through whole-page `interpreter_test` /
`shading_test`). Covers device families + abbreviations, resource-name
resolution, ICCBased channel count + real-profile application (vs the
littleCMS reference in `icc_test`), Indexed palette lookup + clamping,
Separation and multi-input DeviceN tint transforms, and CIE delegation
including Lab's default sample decode.
