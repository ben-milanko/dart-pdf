# MRC scan decode speed (JBIG2 / JPX / MQ)

A 10-page A3 copier scan (YSoft SafeQ output) opened very slowly. It is MRC
compressed: every page is a 150 ppi JPX colour background, a 75 ppi JPX
colour layer under a 300 ppi (≈4975x3530) JBIG2 stencil, and a handful of
JPX photo layers under CCITT masks (up to 4818x3417). Nothing is exotic; it
was just all slow at once.

## Where the time went (before)

`perf_record_images.dart --image-ratio 1` (the worker's decode record):
**20.7 s** for 10 pages; `--image-ratio 2` **27.3 s**. Per image:

- JBIG2 full-page mask: ~700-850 ms. `_decodeGeneric` rebuilt the 16-pixel
  context per pixel through `_Bitmap.get` (bounds-checked) over a record list,
  and the PDF-polarity pack walked `page.get` per pixel too.
- JPX 2487x1764 background: ~630 ms, of which the inverse DWT was ~350 ms -
  the *horizontal* pass (per-row `sublistView` + closure-based lifts) cost ~4x
  the vertical one.
- `MqDecoder.decode` read its state from a const list of records.
- Native-size `decodeImages` (perf_sweep) additionally spent 27 s in
  `imageAlpha`: a 1244x883 base under a 4978x3532 mask is upsampled to the
  mask's size. The worker path doesn't take that (it decodes at target), so
  it was left alone.

## Changes

- `MqDecoder.decode`: flat typed tables (`_qeValue/_qeNmps/_qeNlps/
  _qeSwitch`) and register locals. Shared by JBIG2 and JPX.
- JBIG2 `_GenericWindow`: when every template row is a contiguous column run
  (all four nominal templates, incl. default AT pixels) the context rolls -
  shift, mask out each run's entry bit, read one new pixel per row. Custom AT
  layouts with gaps keep the per-pixel path. Pack is 8 pixels per byte.
- JPX: `_synthesizeRows` / `_synthesizeColumns` replace `_synthesize1d`
  (direct plane indexing; the vertical pass lifts whole rows). Same float ops
  in the same order per sample - decoded output is **bit-identical** (hashes
  checked on the scan's images). Scatter and the 8-bit interleave lost their
  per-sample bounds checks / `clamp`.
- `_jpxReduceLevels` (image_pixels.dart): skip levels while
  ceil(w/2^r) x ceil(h/2^r) still covers the target. The old
  `ratio >= 2` test missed exactly-half targets of odd-width images
  (2489 -> 1245 is ratio 1.999). `decodePdfImageBase` now honours its target
  for JPX too, so masked JPX layers (the MRC case) reduce; the targeted path
  decodes the mask at target separately, so no lockstep is needed.

## After

Same measure: **8.1 s** at ratio 1 (2.6x), **14.3 s** at ratio 2 (1.9x).
JBIG2 mask 697 -> ~320 ms; JPX background 632 -> ~400 ms; largest JPX layer
2991 -> ~1850 ms native.

Tests: `encodeJbig2GenericPage` (pdf_test_fixtures) round-trips a full-page
generic region for templates 0-3 plus two gapped custom-AT layouts
(`jbig2_roundtrip_test.dart`); image_pixels_test covers the half-size and
masked-base reduce.

## Second pass

After the first round the worker record was 8.1 s / 14.3 s. A fresh profile
put the remaining time in the JBIG2 mask's *consumer*, the MQ call, JPX
tier-1 bookkeeping and the 8-bit output step:

- `pdfImageStencilMask` with a target now counts shown bits per target cell
  straight from the packed rows (`_stencilCoverage`, factored out of
  `_scaledImageMaskRegion`'s popcount kernel - same partition and truncating
  `count * 255 ~/ area`, so pixel-identical to expanding and box-filtering;
  test in image_pixels_test). It used to expand a byte per pixel of the
  17 MP page mask and box-filter that. Note the web
  `pdfComponentBoxDownsampler` accelerator is no longer consulted for 1-bit
  stencils; the portable kernel is exact and cheaper. The native-size unpack
  skips blank bytes and fills solid ones. The dart2js interceptor probe now
  checks `_stencilCoverage`.
- `MqDecoder.decode` is a prefer-inline fast path (MPS, no renormalisation)
  with `_decodeSlow` out of line: raw JBIG2 183 -> 149 ms.
- JBIG2 `_GenericWindow`: rows -2/-1/0 (or -1/0) read zero-padded copies of
  the rows above with no bounds checks; the own-row entry pixel is the bit
  just decoded.
- JPX: table-driven sign context + `_decodeSign`, hoisted pass locals,
  edge-peeled horizontal lifts (`_liftRow`/`_liftRow53`), and an 8-bit
  interleave that clamps in floating point instead of `round()` (identical
  for every input, NaN included).

Result: **4.4 s** at ratio 1 and **8.8 s** at ratio 2 (from 20.7 / 27.3 s
originally). Decoded JBIG2/JPX output is still bit-identical.

Measured and rejected: cache-striping the vertical DWT (64-1024 column
strips - noise to 20% slower), and merging tier-1's significant/visited/
refined arrays into one state byte (no change, JIT or AOT).

## Left on the table

- Per page at ratio 2 the floor is now ~150 ms of JBIG2 MQ decode, ~280 ms
  per full-resolution JPX background and 0.2-1.3 s per photo layer (tier-1
  ~1/3, DWT ~1/2). Further single-thread gains are small; the larger lever
  is decoding a page's images concurrently (they are independent).
