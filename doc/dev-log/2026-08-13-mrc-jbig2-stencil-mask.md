# Scanned MRC pages rendered as a flat grey sheet

A VicTrack A3 drawing (`STD_C0001A.PDF`) rendered page 1 as a dark grey
blur - no white ground, no legible text, just a smear where the keyplan
should be. Every other page in the file (vector CAD) was fine.

## What the page actually is

Page 1 is a scan in the mixed-raster-content layout every scanner emits:

```
/BG0  2482x1757  JPXDecode   DeviceRGB          the background picture
/CL   1241x878   JPXDecode   DeviceRGB /Mask →  the low-resolution colour layer
/…    4964x3513  JBIG2Decode /ImageMask         the high-resolution text stencil
```

The colour layer is drawn over the whole sheet and is *mostly dark*; only
the stencil keeps it off the paper. Lose the stencil and the layer paints
edge to edge, which is exactly the grey smear.

## Two bugs stacked

**1. The mask decode paths can't reach the image codecs.**
`pdfImageStencilMask` and `pdfImageSoftMask` (`pdf_graphics`
`image_pixels.dart`) pulled their samples with `cos.decodeStreamData`, the
plain stream-filter chain. JBIG2 and JPX are image codecs, not filters, so
that throws `UnsupportedFilterException` - which both helpers caught and
turned into `null`, i.e. "no mask, paint the base opaque". The base decode
(`decodePdfImageBase`) has always routed those two through `Jbig2Decoder` /
`JpxDecoder`; the mask paths never did.

Fixed with one shared `_maskSampleData` helper both call. It returns the
samples *plus the shape and depth they came out in*, because the codec, not
the dictionary, is authoritative: JPX carries its own dimensions and always
yields 8-bit samples whatever `/BitsPerComponent` claims. The stencil path
then rejects anything that didn't come back 1-bit, since §8.9.6.3 has no
wider form.

Silent-opaque is a nasty failure mode in general - it turns "we can't read
this mask" into "this image covers everything below it". Worth remembering
if another mask codec shows up.

**2. The JBIG2 decoder rejected refined text symbols.**
With the mask reachable, `Jbig2Decoder.decode` still returned null:
`FormatException: refined text symbols`. The stream refines most of its
instances (SBREFINE=1) - a scanner shares one symbol dictionary and then
re-codes each instance's own ink against it, which is how it stays lossless
on real scanned glyphs. Implemented §6.4.11 in `_readTextRegion`: read
SBRAT off the flags, decode IARDW/IARDH/IARDX/IARDY per refined instance,
and run `_decodeRefinement` with the symbol as the reference.

Two things to get right there:

- The reference is *offset*, not aligned: region pixel (x, y) refines
  reference pixel (x − GRREFERENCEDX, y − GRREFERENCEDY) where
  GRREFERENCEDX = floor(RDW/2) + RDX. `_decodeRefinement` and the two
  context builders grew `dx`/`dy` for it (a generic refinement *region*
  segment passes 0, its previous behaviour). Dart's `>>` is the floor
  division the spec asks for at negative deltas - `~/` is not.
- One refinement context set is shared by every refined instance in the
  region, so it has to be allocated outside the instance loop. Per-instance
  stats decode to noise.

`curS` advances by the *refined* width, not the dictionary symbol's.

## Testing

`pdf_test_fixtures`' JBIG2 encoder learned to emit refined instances
(`Jbig2Placement.refined` / `refinedDx` / `refinedDy` +
`_encodeRefinement`), so `jbig2_roundtrip_test.dart` round-trips a region
mixing refined and verbatim instances with RDW/RDH of both signs and
non-zero RDX/RDY. The encoder's context layout mirrors the decoder's bit
for bit - that agreement is the whole contract, and the independent proof
is the real file above decoding to a legible page.

The mask paths are covered in `pdf_graphics/test/image_pixels_test.dart`
(a JBIG2 stencil `/Mask`, a JPX `/SMask`). The JPX codestream fixture moved
to `pdf_test_fixtures` (`grayJpxCodestream` / `grayJpxExpectedSamples`) so
both packages can use a real one.

Ghent baselines, the PDF.js suite, and the perf counter gate are unchanged -
no corpus file previously reached either mask path with these codecs.
