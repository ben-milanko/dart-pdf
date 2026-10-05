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

## Left on the table

- JBIG2 is now ~12 ns per MQ-decoded pixel; going further means inlining the
  MQ decoder into the row loop.
- JPX tier-1 (`_BitModel` passes) is ~90 ms on the background - the next JPX
  hot spot after the DWT.
- At ratio 2 the backgrounds still decode at full resolution (the target
  needs it); only a faster decoder helps there.
