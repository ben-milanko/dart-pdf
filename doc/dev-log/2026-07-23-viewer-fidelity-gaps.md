# 2026-07-23 - Viewer fidelity: annotation fallbacks, print flags, Type3 d1, image Matte

An audit for "overprint-class" silently-missing features (a spec behavior
parsed away to a no-op, misrendering real PDFs with no signal) turned up a
short list. This session lands the four that are correct and self-contained.

## What landed

### Print vs screen annotation visibility (§12.5.3)
`PdfInterpreter.drawAnnotations` gained a `forPrint` flag and now honors the
/F flags per surface:

- **Screen** (`forPrint: false`, the default): skip Hidden and NoView; the
  Print flag is ignored. Unchanged from before.
- **Print** (`forPrint: true`): skip Hidden; render an annotation only when
  its **Print** flag (bit 3) is set, and **NoView** annotations DO print
  (NoView means "hide on screen, show on paper"). Screen-only markup stays
  off the page; a NoView watermark meant for print now prints.

`encodeVectorPrintPage` (the Windows/Linux vector-print path, the only print
caller) passes `forPrint: true`. New `PdfAnnotation.isPrint`
(`annotation.dart`). All other `drawAnnotations` callers are screen paths and
keep the default.

### Annotation fallback synthesis without /AP (`interpreter.dart`)
`_drawFallbackAnnotation` previously covered Square/Circle/Line/Ink/text
markup/text-field widgets; everything else with no appearance stream was
dropped. Added:

- **Polygon / PolyLine** from /Vertices (closed + /IC fill vs open), the
  direct analogue of the existing Line/Ink fallbacks.
- **Link** border - only when the link carries both /C and a positive border
  width (the common invisible `/Border [0 0 0]` link still paints nothing).
- **FreeText** - /Contents drawn through the /DA font/size/colour, explicit
  line breaks honored, top-anchored and clipped to /Rect. Auto-wrap and
  quadding are left to a real /AP.
- **Non-text button widgets** - /MK background + border, a pushbutton's
  /MK /CA caption, and a check (checkbox) or dot (radio) when the widget's
  own /AS is an on state. Text/choice widgets keep the existing value path
  (now `_drawFallbackTextWidget`).

The /DA parser was extracted to the shared `_parseDefaultAppearance(String)`
behind both the widget and FreeText paths.

### Type3 `d1` colour lock (§9.6.5) (`interpreter.dart`)
`d1` was a bare `break` alongside `d0`. A CharProc that opens with `d1` is a
shape-only glyph painted in the invoking text colour, and colour operators
inside it "shall be ignored". `d1` now sets `_type3ColorLocked`; the colour
ops (`g G rg RG k K cs CS sc scn SC SCN`) are skipped while it's set. The
flag is per-glyph (snapshotted/cleared around each CharProc in
`_drawType3Glyph`). Hot-path cost is one short-circuited boolean at the top
of `_execOp`, false on every ordinary page - the same "one branch" shape as
overprint. The advisory `d1` width/BBox operands stay ignored (the font
already supplies widths); BBox clipping is optional and left out to avoid
shifting baselines.

### Image /SMask /Matte un-preblend (§11.6.5.3) (`image_pixels.dart`)
A soft mask may carry a /Matte colour the base image was preblended against
(`c' = m + a·(c − m)`), which fringes at soft edges if decoded naively.
`pdfImageSoftMask` now parses /Matte, converting it to sRGB through the
*parent* image's colour space, and `PdfImageSoftMask` carries it. In
`pdfApplyImageAlpha` each partially-covered pixel is un-preblended
(`c = m + (c' − m)/a`) before the downstream premultiply, in both the
equal-res and higher-res-upsample paths. DCT-encoded masks (decoded at the
`dart:ui` layer) don't carry Matte - a narrower, tolerated gap.

## Tests
`interpreter_test.dart`: d1 colour lock (with a d0 control), the five new
annotation fallbacks, and a screen-vs-print flag group (a page with
Print / Print+NoView / no-flag annotations). `image_pixels_test.dart`: a
white-over-red-matte pixel that must decode to neutral grey. All pass;
`dart analyze` clean at root.

The 20 Ghent `ghent_render_test` failures in this container are pre-existing
(baseline pixel mismatches, reproduced on a clean checkout) and unrelated.

## Deferred (not "tier-1" fixes)

- **Non-isolated transparency groups (/I).** The interpreter already paints
  full-alpha/normal-blend groups directly onto the backdrop (non-isolated-
  equivalent); the only case where isolated vs non-isolated diverges is a
  blended/soft-masked group, and compositing that correctly needs the
  backdrop-removal of §11.4.8, which a Skia `saveLayer` (always a transparent
  layer) can't express. Reading the flag is trivial; a *correct* non-isolated
  compositor is a dedicated project that also touches knockout, region replay
  (which assumes isolated group semantics), and the Ghent baselines. Shipping
  a naive version would itself be a silent misrender.
- **ExtGState transfer functions /TR/TR2, /BG/UCR, /HT.** A legacy prepress
  feature operating in device colour space; our pipeline is sRGB, the common
  `/TR2 /Default` is already a no-op, and a faithful implementation needs
  plumbing through every device + the record/replay codec for a feature
  essentially absent from real screen PDFs.
