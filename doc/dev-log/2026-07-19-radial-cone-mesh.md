# Radial shadings with non-nested circles: cone mesh

## The mismatch

`radial_gradients.pdf` page 4 (the "r0=0 point outside" grid, `p3` in the
PDF.js render gallery) rendered wrong wherever a radial shading's two
circles are **not nested** and an end is **/Extend=false**. The failing
cells (`Sh18 [true false]`, `Sh20 [false false]`: `Coords [521 y 0  431 y
60]`, so an r0=0 focal point 90 units outside the r1=60 circle) painted
only a thin crescent near the focal point; PDF.js paints the full swept
"tear-drop" — the large circle filled with the radial gradient plus the
cone converging to the point.

## Why the device gradient can't do it

The canvas device renders type-2/3 shadings with `ui.Gradient.radial`
(Skia's two-point conical gradient). That gradient can't express the PDF
radial when the focal circle lies outside the end circle:

- With both ends /Extend=true it *looks* right only by coincidence — the
  far region clamps to the terminal colour, which is the same blue the
  cone ends on, so the wrong parametrisation is invisible.
- With /Extend=false we used to append a transparent stop so `TileMode.
  clamp` stops at the end. But Skia maps the whole far disk to the
  swapped/"beyond" side of the focal parametrisation, so that transparent
  tail wipes out the disk interior — leaving just the crescent. Clipping
  to the true swept region fixes the *shape* but not the *colour*: Skia
  still fills the disk with a flat terminal blue instead of the gradient.

So the two-point conical gradient is simply the wrong primitive here.

## The fix — foliate the sweep into a mesh

A radial shading (§8.7.4.5.4) sweeps a circle from `(c0, r0)` at s=0 to
`(c1, r1)` at s=1; a point takes the colour of the **greatest** s whose
circle passes through it. `PdfShading.toRadialConeMesh`
(`pdf_graphics/shading.dart`) turns the non-nested case into a Gouraud
mesh instead of a gradient:

- One constant-colour ring per sampled s (`centre = lerp(c0,c1,s)`,
  `radius = r0 + s·dr`), joined into quad strips.
- Rings are emitted in **increasing s**, so a later (larger-s) ring paints
  over an earlier one — that ordering *is* the "greatest s wins" rule,
  including the two-root overlap region, with no explicit root solving.
- /Extend widens the s-range: toward the radius-0 apex on the shrinking
  side (a finite tip) and out past the fill (`clip`, mapped back into
  shading space to size the reach) on the growing side. An unextended end
  stops at s=0 / s=1, leaving the correct hard circle edge.
- Sampling is fine across the in-domain `[0,1]` band (48 steps × 96
  angular) where the colour actually varies, coarse over the extended
  tails (constant terminal colour, moving geometry).

`toGradient` now returns null for non-nested radials (nested/​concentric
still map cleanly onto the device radial gradient and keep that path), and
the interpreter's three shading sites (`_fillWithPattern`, `_applyShading`,
`_patternAverageColor`) fall through to `toRadialConeMesh` the same way
they already do for mesh (types 4–7) and function (type 1) shadings — via
`device.fillMesh`, which every backend already supports. No device, shader
or async change.

## Verification

`packages/pdf_graphics/test/shading_test.dart` gains coverage: nested →
gradient (no mesh); non-nested → mesh not gradient, colours spanning the
function, and the sweep bounded to the swept region / the unextended end.
The full `pdf_graphics` suite and the interpreter tests pass; the Ghent
render baselines are unchanged (the one pre-existing `GWG030` spot/
overprint deviation is unrelated).

The checked-in PDF.js render gallery
(`test_corpora/pdfjs/_renders/radial_gradients.pdf.p3/p4`) needs
regenerating on a host with the substituted system fonts available
(`loadSystemFonts` resolves macOS paths); this Linux CI box renders the
labels as tofu, so the gallery PNGs were intentionally left untouched.
Re-run `PDFJS_ONLY=radial_gradients PDFJS_BASELINE_DIR=… fvm flutter test
test/pdfjs_render_test.dart` there to refresh them.
