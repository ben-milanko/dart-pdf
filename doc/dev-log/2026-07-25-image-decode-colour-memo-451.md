# 2026-07-25 — #451: the record-serialize outlier is colour conversion, not resolution

Issue #451 opened on a device trace where a render record's cost tracked
neither its payload nor its command count: **5.3 MB serialised in 1817 ms
while 39 MB serialised in 329 ms**, same worker, same run. A later comment
root-caused it as full-resolution decode ahead of the downsample, and
proposed *downsampling in the source colour space before converting*.

Measuring per image first says the proposal would have missed most of the
cost. This is what the measurement found, what landed, and what is left.

## Reproducing it on the VM

Two new tools, both in `packages/pdf_graphics/tool/`:

- **`bench_image_serialize.dart`** — runs the record path's exact call
  (`serializeCommands(cos:, decodeImages: true, maxImagePixelRatio: 2.0)`)
  over a corpus and splits each page's serialize into its image half and
  its command-encode half.
- **`bench_image_decode.dart`** — one level down: for every image a page
  draws, decodes it at the size the record path actually asks for
  (`cappedImagePixelSize` at ratio 2.0) and reports the cost beside the
  image's *shape* — colour space, bits, filters, mask, source vs target
  pixels. Best-of-5, because a single sample cannot separate a real change
  from scheduler jitter.

The device profile reproduces immediately. Pure command encode tops out at
~22 ms for 6k commands — no superlinearity there. With image decode on, the
outliers appear, and they are disproportionate to output bytes:
`GWG205_ICC-V4-CMYK-Image_x4.pdf` p0 cost **235 ms for 110 commands and
1.43 MB of output**.

## What the shape breakdown showed

Across the Ghent + PDF.js corpora at ratio 2.0 (155 images), before any
change:

```
     732.7ms    30 images  DeviceCMYK/8b      <- 65% of all image-decode time
     167.6ms     3 images  DeviceN/8b
      58.9ms    25 images  DeviceGray/1b
      55.9ms     5 images  DeviceRGB/8b
      46.6ms    40 images  Indexed/8b
      37.5ms     1 images  Indexed/8b+Stencil
```

The decisive detail: **almost every one of those CMYK images is drawn at or
above native size** (scale 1.00 in the per-image table). Decoding straight
to the display size cannot help an image that is not being downscaled. The
tool's closing line makes the ceiling explicit — of 1125 ms total, only
463 ms was spent on images that are downscaled *at all*, and the saving on
those is proportional to `1 − scale`, not to the whole.

So the cost is the per-pixel conversion itself. Timed directly on GWG205's
profile:

| path | per pixel |
|---|---|
| `PdfColor.cmyk` (the SWOP polynomial) | 0.147 µs |
| `IccProfile.toSrgb` (v4 CMYK, 4-D CLUT over 16 corners) | 0.853 µs |

At 0.853 µs/px, GWG205's 227695 pixels are 194 ms of its 235 ms.

## What actually collapses it: the tuples repeat

GWG205's image resolves to **29027 distinct colours across 227695 pixels**
(12.7%); GWG1610's to 8785 across 154135 (5.7%). Press artwork is built from
a small ink palette, and even photographic content has strong local
coherence. So memoize the conversion on the sample tuple.

This is not a new idea in this file — `_alternateToRgba` already did it for
tint transforms. What landed applies it where the corpus says the time is,
with a table that holds up under pressure.

### `_ColorMemo`

Direct-mapped over a pair of typed arrays rather than a `Map`:

- no hashing of boxed keys, no rehash growth;
- **no cliff when the working set exceeds capacity** — a colliding tuple
  evicts and is recomputed, where the old size-capped `Map` stopped learning
  at 65536 entries and then paid a *failed* lookup on every remaining pixel
  of the image.

It replaces that `Map` on the tint path too, which retires a latent web bug
along the way. The old key packed up to 8 components into one int via
`key = (key << 8) | sample`. Past four 8-bit components that exceeds 32 bits,
where dart2js's bitwise operators wrap and the VM's do not — so two distinct
tuples would compare equal **on the web only** and silently take each other's
colour. Keys are now compared as raw component bytes, which is exact
everywhere.

Two deliberate choices worth keeping:

- **Slot hash by small multiplies** (`s0*7 + s1*31 + …`), not shift-and-mix:
  every partial sum stays far inside the 53-bit range dart2js gives a plain
  int, so a tuple lands in the same slot on the VM and on the web.
- **A pixel-count floor** (`_minPixels`, 8192): below it the tables cost more
  to allocate than the conversions they save, so small images are untouched.

### Allocation-free `_Lut.apply`

The second part. `_Lut.apply` is the inner loop of every ICC-managed image
and allocated **five lists per call** — mapped inputs, low indices,
fractions, accumulator, PCS output. Those now live on the profile and are
reused; `apply` reads its input and its single call site consumes the
returned PCS values on the next line, so one set serves a whole image.

## Result

Best of 5, same corpora, versus the pre-#451 baseline:

| shape | before | after | |
|---|---|---|---|
| DeviceCMYK/8b | 732.7 ms | **213.5 ms** | −71% |
| Separation/8b | 14.5 ms | 6.4 ms | −56% |
| DeviceN/8b | 167.6 ms | 140.7 ms | −16% |
| **total** | **1125 ms** | **561 ms** | **−50%** |

## Why this is safe, and how that was checked rather than asserted

A memo hit returns the colour that tuple genuinely converts to, so both
parts are output-preserving *by construction*. That claim is verified, not
trusted:

- **`tool/hash_image_decodes.dart`** (written for an earlier decode change,
  exactly the right tool here) hashes every image XObject through both decode
  entry points. All **420 images** across both corpora hash **byte-identically**
  before and after.
- `ghent_render_test` needs **no baseline change** — which matters given
  [the #550 finding](2026-07-25-ghent-baseline-drift-550.md) that a green
  Ghent run is not by itself proof of correctness. Here the stronger claim
  (zero baseline movement) is available, so it is the one being made.
- Full suites: pdf_cos 356, pdf_document 805, pdf_graphics 927,
  dart_pdf_editor 1969, app 321.

The new unit test targets the one way this could go wrong. A fixed-size
direct-mapped table can lie in exactly two ways — a stale eviction, and two
tuples hashing to one slot — so the test makes it thrash on purpose: 65536
distinct CMYK tuples through 16384 slots, every pixel checked against an
independently computed conversion. It was confirmed to **fail** when the key
comparison is deleted.

## What is left, and why it was not bundled

Three things the measurement surfaced, all deliberately out of this change
because they alter output and the issue itself warns against landing colour
changes blind:

1. **Downsample before converting** — #451's original proposal. Still real,
   but now bounded: only 168 ms of the remaining 561 ms is spent on
   downscaled images at all, and the saving is a fraction of that. Worth
   doing *after* the free wins, not instead of them.

2. **The scaled fast path stops at direct device colour spaces.**
   `GWG161_Transp_Basic_BM_ICCBasedRGB` decodes 2045×1018 to display at
   128×64 — a 254× overdraw — because `_isDirectDeviceColorSpace` rejects the
   `ICCBased` array even when the profile is sRGB-equivalent and the
   conversion is the identity copy. Extending it there looks free, but the
   fast path resamples **bilinearly** while the full path box-filters, so at
   a 16× downscale it would trade decode time for aliasing on a
   pixel-enforced Ghent page. That is a quality decision, not a perf one.

3. **A mask larger than its base blows the decode up to the mask's grid.**
   `pdfApplyImageAlpha` upsamples the base to the mask resolution to preserve
   the cutout's detail — deliberate, and right in principle, but unbounded:
   `issue4246.pdf` decodes a **50×40** image to **1000×800** (400×, 3.2 MB of
   RGBA for 2000 source pixels), and `smaskdim.pdf` a 2×2 to 76×102 (1938×).
   The fix is not to clamp to the base — that would destroy exactly the
   detail the upsample exists to keep — but to bound the blow-up by the
   *display* cap, which `_targetDecodedSize` currently cannot express because
   it derives the target from the declared base size alone. Only 2 images in
   these corpora, but it is a memory pathology as much as a time one, and the
   39 MB page-1 record in the original trace is the shape that would expose it.
