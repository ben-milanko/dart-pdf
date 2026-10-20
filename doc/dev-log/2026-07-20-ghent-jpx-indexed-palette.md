# Ghent self-grading JPEG2000 pages: honour the /Indexed palette on a JPX base

## The self-grading failure

Two Ghent V5.0 pages state their own pass criterion and we failed them
(issue #431):

- `1-CMYK/GWG170_JPEG2000_compression_DeviceCMYK_X4` — "No 'X' must be
  visible when rendered correctly." We drew a large black **X** on a red
  square.
- `3-ICC-CMS/GWG172_JPEG2000_compression_ICCBasedRGB_x4` — same criterion,
  a black X on a green square.

Both pages draw a fail-marker X in the page content and then paint a
JPEG2000 image, **clipped to that X shape**, on top. When the image renders
in the right colour it covers the X and the X disappears; that is the whole
test.

## Root cause

The image's `/ColorSpace` is `[/Indexed <base> 0 <lookup>]` — a
single-entry palette (`hival 0`), so every sample is index `0`. JPEG2000
stores those indices in one component. `decodePdfImageBase` took the
`JPXDecode` branch and handed the decoded samples straight to `_jpxToRgba`,
which for a 1-component image treats the sample **as gray**. Index `0`
became gray `0` — a solid **black** square. That is the black X: the image
did cover the marker, just in the wrong colour.

The `/Indexed` colour space was ignored entirely on the JPX path, even
though the raw-sample path (`_indexedToRgba`) has resolved indexed palettes
for a long time.

## Fix

`decodePdfImageBase`, JPX branch: when `pdfImageColorFamily` is `Indexed`,
map the single-component JPX samples through the palette
(`_jpxIndexedToRgba`, reusing `_indexedPalette`) instead of through
`_jpxToRgba`. Out-of-range indices clamp to `0`, matching `_indexedToRgba`.

- **GWG170** (all DeviceCMYK): the image now paints the palette CMYK red,
  which is exactly the DeviceCMYK red the page fills the marker with, so the
  X vanishes and the page grades itself as passing. It is pixel-enforced
  against a fresh baseline.
- **GWG172** (ICCBasedRGB): the image now paints its palette green (was
  black), but the square is DeviceCMYK green while the image is
  ICCBased-RGB green, and we do not colour-manage those to a common output
  so a *faint* X remains. That residual is a genuine colour-fidelity
  deviation (the class already documented for the ICC/overprint pages), not
  an image-loss, so GWG172 moves into `_knownBaselineDeviations`.

## Why a green run did not catch it, and what now does

The render suite's `_knownBaselineDeviations` tolerance only asserts a page
"renders non-blank", which a total image loss slips through because the page
still draws its text and frame (issue #431, item 3). Rather than lean on the
rasterized baseline — which also cannot tell "drew its palette colour" from
"drew black" — the guard is a dedicated pure-Dart decode test,
`pdf_graphics/test/ghent_jpx_indexed_test.dart`: it decodes each page's JPX
image and asserts a **uniform, opaque, distinctly-hued** square (red for
GWG170, green for GWG172), never the old black. These pages grade
themselves, so we pin the criterion at the decode layer where it is
deterministic on CI (no `dart:ui`, no macOS/Linux AA skew).

## Not addressed here (separate root causes from #431)

- `GWG166`/`GWG167` softmask images decode to null via the DCT-non-CMYK /
  DCT-`/SMask` platform-codec path — a compositing question, not this
  decode bug.
- `GWG161` blend-mode and the aggregate `*_X4` suite pages remain colour /
  transparency deviations.
- DeviceN `GWG080`/`GWG081` were fixed earlier under #430.
