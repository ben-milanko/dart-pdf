# 2026-07-23 — per-glyph substituted-text composition (#454)

## What this is

The replay-bound half of #454 is substituted-text shaping: `CanvasPdfDevice`
shapes non-embedded-font runs through `TextPainter`, cached by full run text.
Unique labels (CAD survey points, coordinate grids) miss that run cache on every
render and re-shape — the measured worst case was a cold page's `replay` at
~48 ms vs ~4–8 ms warm (see 2026-07-23-replay-shape-split-454.md).

This composes such a run from **per-character** layouts instead. Each character
is shaped once and cached in a new `_glyphCache`; a run is built by placing those
cached glyphs at their cumulative advances, then scaled to the PDF's own total
width exactly as the whole-run path is. A page of 660 unique labels collapses to
an alphabet of ~14 cached glyphs.

## The result (desktop web harness, `scroll-cad-labels`)

`?perGlyph=1` vs the default on the same build:

```
                 perGlyph=0 (whole-run)     perGlyph=1 (composed)
cold page 2      replay=39.5ms shape=26.9    replay= 8.0ms
cold page 4      replay=48.1ms shape=34.1    replay= 8.1ms
cold page 5      replay=50.8ms shape=34.4    replay=15.1ms
```

**~5–6× less replay on the exact pathology** (48 → 8 ms), landing near the warm
floor. The shaping the ticket identified is essentially eliminated for these
pages.

## Fidelity: gated so the change is pixel-nil, then defaulted on

Per-character placement drops cross-character kerning and any contextual shaping.
A first cut allowed all uppercase, but a **real-Chrome probe** (whole-run
`fillText` vs per-character `measureText` advances, both scaled to one box, on
Helvetica/Arial/Courier - exactly what the device does) showed realistic all-caps
words diverge a lot: `PAY ATTENTION` 57%, `TAX INVOICE` 38%, `AVENUE` 31%,
`WATER TANK` 27%, even `WARNING` 17% of inked pixels changed. Digit/coordinate
strings were 0%.

The cause is narrow: kerning only fires between adjacent **letters** (and
letter↔punctuation). So `_composableRun` was tightened - a letter may only
neighbour a digit or a space, never another letter or punctuation. That is
exactly the shape of coordinate/survey/part labels (`N1234.567 E7654.321`,
`A3 B7`), and the probe then reported **0% diff for every gate-passing string**
across all three fonts, while every kerning-pair word fell to whole-run shaping.
Lowercase, non-ASCII (Arabic/CJK), and stroked/gradient runs also stay on the
whole-run path.

With the pixel diff proven nil on real fonts, `perGlyphSubstitutedText` is
**default on**. It is conservative - safe adjacent-letter strings like `SHEET`
or `DN200` also fall back (they happen not to kern, but the gate can't cheaply
know that) - so a future per-font kerning table could widen it; the coordinate-
label win is captured regardless.

## Validation

- `per_glyph_text_test`: (1) a composable run composes pixel-identically to
  whole-run shaping, (2) a non-composable (lowercase) run is untouched by the
  flag, (3) 200 unique runs leave the run cache empty and the glyph cache at an
  alphabet (< 20).
- No baseline shift from defaulting on: the byte-identical substituted-text
  render test passes, and the Ghent suite fails exactly the same 20 tests as a
  clean tree (CMYK/overprint/softmask, pre-existing) - the test font has no
  kerning, so composed and whole-run render identically there anyway.
- `flutter build web` compiles the device + harness change.

## Incidental fix

The run-cache key `'${run.text} ${run.fontName} '` had its two literal spaces
stored as NUL bytes (`\x00`) — pre-existing corruption present since before this
session (harmless: NUL is still a valid separator, but wrong). Fixed to real
spaces while rewriting `_measureLayout`.

## Harness

`?perGlyph=0` (perf_harness.dart, default on) and the `PERF_PER_GLYPH` driver
env knob A/B the feature on a single build — no webdiff needed, since `main`
lacks the flag. The fidelity probe was a throwaway puppeteer script (whole-run
`fillText` vs per-character advances, pixel-diffed) run against system Chrome.
