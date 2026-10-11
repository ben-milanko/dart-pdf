# Unembedded serif fonts: Termes by name/flag, and slot-fitted pieces

Reported: a relay datasheet heading ("A twin, dc biased, ac immune, tractive
armature relay") drawn in a sans-serif with gaps inside words ("bi ased",
"armatu re", "rel ay") and round letters crowding their neighbours.

## Cause

The heading's `/F1` is **MinionPro-Regular, unembedded**, with Minion's
/Widths and a `TJ` full of per-letter kerns typeset against them. Its
descriptor's /Flags is 32 (Nonsymbolic) - the Serif bit is clear - and
`pdfBundledSubstituteFor` only knew `Times`/`Serif` as serif names, so it fell
through to TeX Gyre Heros (Helvetica). Exact placement
(`CanvasPdfDevice.exactSubstitutedGlyphPlacement`, #649) pins each piece to
the PDF's own pen offset, so Helvetica's narrow `i l t r` (vs Minion's wider
ones) left air *after* them inside the word, and its wide `a e s c` ran into
the next letter. The uniform per-run scale only matches the two faces on
average.

## Fix 1 - pick the right face

- `pdfBundledSubstituteFor(name, {serif})` (font_substitution.dart): a list of
  common serif families (`_serifFamilies`: Minion, Garamond, Georgia,
  Palatino, Book Antiqua, Cambria, Caslon, Baskerville, ...) routes to Termes;
  so does the descriptor's Serif flag. A recognised name wins over the flag
  (Calibri/Courier stay Carlito/Cursor), and any name containing `sans` is
  Heros first - `MicrosoftSansSerif` used to land on Termes.
- The flag is plumbed: `PdfFontInfo.isSerif` (bit 2 of /Flags) →
  `PdfTextRun.serif` (interpreter, translating device) → render-command codec
  (**format version 12**, one bool after the font name) → every consumer:
  `CanvasPdfDevice._styleFor`/`_kernFreeFace`, the run-layout key and glyph-key
  suffix (a serif and a sans run of one unknown name are different layouts),
  the web Canvas2D device, the worker's bundled-face loader, and the GPU
  outliner's family pick.

## Fix 2 - fit each piece to its slot

`pdfFitSubstitutedPiece(slot:, drawn:)` (font_substitution.dart, pure Dart):
a piece narrower than the PDF's width for it is centred; wider is squeezed
horizontally from the slot's start (PDF.js's rule for unembedded fonts).
Within `pdfSubstituteFitToleranceEm` (0.02 em, the cut tolerance) nothing
changes, so a metric-compatible clone draws bit-identically to before.
`slot` runs from the piece's first offset to the end of its last glyph
(`glyphWidthAt`, spacing excluded) so Tc/Tw stay gaps.

Applied in both exact-placement planners: `CanvasPdfDevice._buildPlacedLayout`
(`_GlyphRun.scaleX`, painted under save/translate/scale) and
`pdfCanvas2dTextLayout` (`PdfCanvas2dTextPart.scaleX`). The GPU outliner
(`FlutterGpuTrueTypeTextOutliner`) still places glyphs flush-left at the run's
uniform scale - it would need per-glyph outline transforms.

Updated expectations: `substituted_glyph_placement_test.dart` (synthetic
1.6/1.0 em slots now centre the first `A` and squeeze the second) and the
Century Gothic `BOOK 1B` Canvas2D test (asserts each glyph centred-or-squeezed
in its slot rather than flush on its offset). New: Minion `biased` against
Helvetica advances, routing/flag tests, codec + font-info round trips.
Counter gate unchanged (`tool/perf.sh gate` OK).
