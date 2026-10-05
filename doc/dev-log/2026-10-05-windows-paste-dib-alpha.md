# Windows image paste: keep the DIB's alpha (pasted images looked inverted)

**Symptom:** on Windows, pasting an image copied from a web app (reported from
Trax, in the browser) came in with its colours apparently inverted: light
drawing on black.

**Cause:** `ReadImageFromClipboard` (`app/windows/runner/image_clipboard.cpp`)
prefers the registered `PNG` format. When the source publishes only a DIB,
which browsers do for some copies, it fell back to the system-synthesized
`CF_BITMAP` and encoded it with `WICBitmapIgnoreAlpha`. Those 32bpp DIBs carry
real (usually premultiplied) alpha, and transparent pixels are stored as
`0,0,0,0`. With the alpha dropped, a dark map or diagram on a transparent
background becomes dark-on-black, and only the light parts stay visible.

**Fix:** a new middle step reads `CF_DIB` directly (Windows synthesizes it
from `CF_DIBV5`) through `dart_pdf::DecodePackedDib32`
(`app/windows/runner/dib_pixels.h`, header-only and free of `<windows.h>`):
- uncompressed 32bpp, `BI_RGB` or standard-mask `BI_BITFIELDS`; masks after a
  40-byte header or inside a V2+ header; bottom-up and top-down rows. Other
  layouts return nullopt and still go through the old `CF_BITMAP` path;
- all-zero alpha means the byte is unused (screenshots, DDBs), so the image
  is treated as opaque. This keeps the reason the old path ignored alpha;
- if every colour channel is <= its alpha, the data is treated as
  premultiplied and un-premultiplied for PNG, which stores straight alpha;
- opaque results encode as `32bppBGR`, so the PDF gets no needless /SMask.
  Transparent results keep their alpha and land as a soft mask.

The pure-Dart side (PNG/JPEG → `PdfEmbeddableImage` → `decodePdfImagePixels`)
was checked first with RGBA/RGB/16-bit/palette PNGs and decodes correctly.
The bug was only in the native read.

**Tests:** `app/windows/test/dib_pixels_test.cc`, plain g++ with ASan/UBSan,
run by CI's `linux` job. Nothing in per-PR CI builds the Windows runner, so the
WIC glue is compiled only by the Windows release/nightly builds.
