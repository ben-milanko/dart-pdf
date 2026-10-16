# Substituted text: baselines bounce under Impeller when glyphs are stretched

## Symptom

`SNA-ARTC-IM-0000-MP-0001` (a PDF-XChange-printed Word report), page 4: the
heading "1.1 Signalling Work" rendered with its letters at different heights
at 1 px/pt in the macOS app. Stemmed letters (`l`, `i`, `W`, `k`) ended a
device pixel below `n`, `a`, `o`, `r` beside them, and "1.1" sat higher
again. The body text on the same pages looked right.

## What the page does

The heading is `/F0 12 Tf (1.1) Tj ... (Signalling Work) Tj` in
**Arial-Black**, TrueType/WinAnsi, *not embedded*. We substitute TeX Gyre
Heros (regular weight - the name has no "Bold"), whose advances are far
narrower than Arial Black's. `_buildPlacedLayout` (#649) scales the glyph
shapes uniformly by `k = Σ natural ÷ Σ PDF width`, so these shapes were
stretched about 1.2x horizontally. The body text is ArialMT, which Heros
matches to within a fraction of a percent, so its scale stays at about 1.

## Root cause: Impeller, not our geometry

- The VM/Skia render (`render_smoke_test.dart`, direct and worker) is
  correct and matches pdfium. The same page with
  `flutter test --enable-impeller` reproduces the screenshot exactly.
- A minimal probe (a `TextPainter` at 100 px drawn under
  `scale(0.12 * sx, -0.12)` after a y-flip) shows the jitter depends only
  on `sx`, the horizontal-over-vertical scale. At `sx` <= 1.02 the
  baselines are always level. At 1.04 they jitter at some sub-pixel
  baselines, and from about 1.15 at most of them. Compression (`sx` < 1) is
  exact. This fits Impeller rasterizing each glyph at the transform's
  *larger* axis scale and mapping it back down the other axis, which snaps
  each glyph's vertical extent separately.

## Fix

`_buildPlacedLayout` now clamps `k` so the shapes widen by at most
`_maxPlacedShapeStretch` (1.02). Narrowing is still free. When a
substitute is narrower than the PDF's widths, its glyphs keep their own
proportions, and the existing cut/fit machinery positions the pieces
instead: a disagreement over 0.02 em starts a new piece at its PDF offset,
and `pdfFitSubstitutedPiece` centres a piece in its slot. Character origins
are as exact as before. The trade-off is visual: a much wider unembedded
face now reads as slightly letter-spaced Heros instead of stretched Heros,
and on every backend, not only Impeller.

Tests: `substituted_glyph_placement_test.dart` gains "a narrower substitute
is placed, not stretched to fit". The first test's expectations are updated
because its 1.3x example is no longer stretched.

## Not done

- The whole-run paths (gradient/stroke fills, complex scripts, runs without
  an offset table) still stretch by `targetWidth / layout.width` and can
  show the same jitter on Impeller when the substitute is much narrower.
- `Arial-Black` (and other `Black`/`Heavy` names) maps to regular weight
  because `_styleFor` only checks for "Bold". A heavier substitute would
  match better and would need less placement.
