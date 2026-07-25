# Image overprint: colorant readings for decoded rasters (issue #604)

Follow-up to `2026-07-25-overprint-colorant-buffer.md` (#502), whose closing
"still out of scope" note this removes. That session made **vector** overprint
faithful by recording the device colorants each draw leaves behind; an image
draw had no such reading, so a raster neither overprinted what was under it nor
accepted overprint from ink drawn over it. GWG190/191/192 leave
`_knownBaselineDeviations` with all four patches solid, and GWG031 - the page
whose entire subject is an overprinting grayscale raster over a spot green -
now renders its own "Correct" reference rather than its "Wrong" one.

## The shape of the fix: a substitute raster

Overprint is defined over colorants, and a decoded pixel is sRGB, which has no
colorant decomposition. The colorants exist exactly once in the pipeline: in
the image's **samples**, in the image's own colour space, before `_toRgba`
turns them into pixels. So that is where the composite happens.

Three pieces, all pure Dart in `pdf_graphics`:

- **`PdfColorSpace.inkColorants` for `/Indexed`** - an Indexed space writes
  whatever its *base* writes for the selected palette entry (§8.6.6.3). Null
  for an RGB-ish palette, like every other space with no reading. GWG031's
  raster is `/Indexed` over DeviceCMYK, so without this it had no reading at
  all.
- **`image_colorants.dart`** - `pdfImageColorants` reads what colorants a
  raster carries; `pdfImageOverprintStream` composites every sample over a
  backdrop (`PdfInkColorants.over`) and returns a **substitute image stream**
  whose colours are the result.
- **`PdfOverprintCompositor.image`** - the policy: rasterize the image's quad,
  read the backdrop under it, offer it to the caller, and record what the image
  leaves behind.

The substitute is a plain unfiltered `/DeviceRGB` 8-bit XObject of the same
dimensions carrying the source's `/SMask`, stencil `/Mask`, `/Interpolate` and
`/Intent` through unchanged. That choice is the whole reason this change is
small: **an image XObject is a thing every path already knows how to draw**, so
the canvas device, the strip device, the recorded command buffer, the render
worker, the codec and the decoded-image cache need no change at all - the
interpreter simply draws a different stream. The alternatives (a new device
call, a flag on `PdfImageRequest` threaded through `decodePdfImageBase` and
every scaled/region fast path, or a per-pixel hook) all end up editing six
layers to say one thing.

## Two rules carried over from the vector path

**The exact-answer rule.** `PdfOverprintCompositor._srgbFor` reuses the
backdrop's own rendered colour when the composite equals the backdrop, and the
ink's when it equals the ink, so an overprint that changed nothing is
*invisible* rather than a shade off. The substitute builder applies the same
rule per sample - which is what makes GWG031's white background reproduce the
green rectangle's pixels exactly instead of a round trip through
`colorantsToSrgb`.

**Bare paper is the identity.** Overprinting onto no colorant leaves every
written channel at the ink's own value and every unwritten one at zero, i.e.
the ink's own colorants - so the source stream already *is* the composite.
`pdfImageOverprintStream` returns null for `PdfColorants.none`, and nothing is
built. This matters more than it sounds: `/op` is set defensively across most
of the Ghent corpus and the overwhelming majority of those draws land on white.

## Where it declines, and why each line is where it is

- **A raster with no colorant reading** - DeviceRGB, ICCBased, Lab, CalRGB, an
  Indexed space over any of them. Same rule as vector colour: inventing
  colorants for an RGB image would knock backdrops out that a real separations
  device leaves alone. Checked *before* the samples are touched
  (`space.inkColorants` of a zero vector), so a photographic page never pays to
  decompress a raster to find out.
- **DCT / JPX / JBIG2** - their samples are not in the stream's own bytes.
- **A colour-key `/Mask`** - its ranges are stated in source-sample space and
  mean nothing against DeviceRGB samples; dropping the mask would paint pixels
  that must not appear.
- **A stencil (`/ImageMask`)** - it carries no colour of its own, it paints the
  *fill* colour through its alpha. Resolving it means reading the backdrop
  under the stencil's coverage rather than its quad, which the buffer does not
  model.
- **More than one backdrop under the raster.** One substitute composites
  against one backdrop; a raster straddling two would need one per region. This
  is the one visible incompleteness - see GWG010 below.
- **Past 4 Mpx** - the uniformity scan and the per-sample composite are both
  O(pixels) and the substitute holds 3 bytes per pixel for as long as its
  source stream lives (12 MB at the cap). Past it a raster reads as
  colorant-less, which is exactly where image overprint stood before.

For **recording** (an image acting as a backdrop) the bar is higher than for
resolving: the buffer stores one colorant vector per cell, so only a raster
whose samples all carry the same colorants *and* which covers its whole quad
(no `/SMask`, no `/Mask`) is recorded; everything else stays "unknown". A
masked raster still has a reading - it can be composited *onto* a backdrop -
which is why `PdfImageColorants` separates `uniformInk` from `backdropInk`.
Uniformity is compared on raw sample tuples with an early exit, so a
non-uniform raster costs a handful of samples, and the answer is memoised per
stream.

## The identity of the substitute is load-bearing

The decoded-image cache keys XObject images by **stream identity**, and one
render path (`renderPictureWithPlan`, and the strips harness) discovers images
with a *separate* scan-only walk before the paint walk. Two consequences:

1. `pdfImageOverprintStream` memoises per `(stream, backdrop, mode)` on an
   `Expando` - the same pair must return the same object on every
   interpretation pass, or the paint walk would ask the cache for a stream the
   collect walk never decoded and the image would silently fail to appear.
2. The scan-only walk builds no paths, clips or colours, so it cannot run the
   buffer - and would therefore collect the *original* stream while the paint
   walk draws the substitute. `_beginOverprint` now clears `_scanImages` for
   any page that opens a buffer: **a page that resolves overprint is walked in
   full even to collect its images.** Pages that declare no overprint (the
   overwhelming majority) keep the cheap scan, and the default render path
   (`renderPictureRecordedWithPlan`) never used the two-walk shape anyway.

That interaction cost more thought than the compositing did, and it is the kind
of thing that fails as "the image is just missing" rather than as a wrong
colour.

## Measured effect on the Ghent suite

Rendered every page before and after and diffed. **Five pages change**, and the
suite goes from 41 to 44 pixel-enforced pages:

| page | before → after |
|---|---|
| GWG190 DeviceN Overprint (Black) | 2 vector patches solid → **all 4 solid** |
| GWG191 DeviceN Overprint (Yellow) | same |
| GWG192 DeviceN Overprint (White) | same |
| GWG031 Gray Image Overprint | the "Wrong" white box around the drop shadow → the **"Correct"** green |
| GWG010 CMYK Overprint Test | its OPM-1 "mask" patch now shows the backdrop through |

GWG190/191/192's own legends state the grading exactly: "a + b must be rendered
to solid Black (100C100K) rectangles… a faint X means that OP is not honored
(or image was converted to DeviceCMYK for b)"; "c + d must be rendered to solid
Cyan rectangles". Patch d is the OPM trap - the mode-1 zero rule is DeviceCMYK's
alone (§8.6.7.3), so a DeviceN `100C0Y0K` must still knock the backdrop's black
out - and it is flat under both a right and a wrong overprint, so what pins it
is the *colour* assertion, not flatness.

### GWG010, honestly

GWG010 is a visual-comparison page with no self-grading legend, and it moved.
Its "mask" patch paints a rich-black X (`.5 .5 .5 .5 k`), then draws an
`/Indexed`-over-DeviceCMYK 50%-magenta raster clipped to that X with `/op true`.
Under OPM 1 the raster's three zero components leave the backdrop's C, Y and K
standing, so the X shows through; under OPM 0 the raster writes all four and
knocks it out to flat pink. That contrast between the two rows is the page's
subject, and the rule producing it is the same one GWG031 grades explicitly and
GWG011 pins for vector paint ("if an X appears the Overprint Mode is not
respected"). The baseline was re-seeded.

Its neighbouring "image" patch is the same test with the raster covering the
whole square instead of just the X - so the raster straddles the pink square
*and* the black X, two backdrops at once, and the buffer declines. It stays a
flat knockout. Making it right means a per-pixel backdrop, i.e. carrying the
buffer's own raster into the substitute rather than a single vector; that is
the natural next step if it ever matters, and it is the last piece of image
overprint still missing.

## Cost

Where the work lands, by construction:

- a raster whose space has no colorant reading (DeviceRGB, ICCBased, Lab - most
  image content) pays a colour-space parse and **nothing else**: the refusal
  happens before `decodeStreamData` is called, so no raster is decompressed to
  find out;
- a CMYK/gray/spot/Indexed raster pays one uniformity scan per stream per
  document (a tight `Uint8List` walk with an early exit at the first differing
  tuple), memoised on the stream;
- a substitute is built only for a raster that actually overprints onto
  something *other than paper*, and is memoised per (stream, backdrop, mode) -
  which also caps it, since a page that draws one raster onto five different
  backdrops stops building after four.

The A/B that exercises this is `tool/perf.sh diff HEAD ghent-suite-open` - most
of the Ghent corpus declares overprint, so it is the scenario where the buffer
is live. Numbers go in this section when the run lands; the deterministic
counter gate (`tool/perf.sh gate`) is the other half.

## Tests

- `pdf_graphics/test/image_colorants_test.dart` (new): the `/Indexed` colorant
  reading, what `pdfImageColorants` reads and refuses, the substitute's two
  exact-answer branches and its per-sample composite, the bare-paper
  short-circuit, the colour-key refusal, the memo's stable identity, and
  `PdfOverprintCompositor.image`'s decisions (backdrop offered, two backdrops
  declined, a uniform raster recorded as a backdrop, a varying one not).
- `dart_pdf_editor/test/overprint_render_test.dart`: extended from GWG030 to
  GWG190/191/192 (four patches each, flatness plus the graded colour, with the
  no-overprint control showing the marker the fixture describes) and GWG031
  (the panel margins keep the spot green under the raster's white background,
  and are knocked out to white without overprint). `_measure` now takes the box
  set so all four pages share one measure.
- `ghent_render_test.dart`: GWG190/191/192 removed from
  `_knownBaselineDeviations`; the GWG010 re-seed documented there.
