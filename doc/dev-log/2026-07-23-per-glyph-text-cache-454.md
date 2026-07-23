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

## Fidelity: why it is gated and opt-in

Per-character placement drops cross-character kerning and any contextual shaping,
so it is **restricted to a safe set** (`_composableRun`): ASCII digits, uppercase
letters, space, and common technical punctuation — none join or ligate, and the
digits (the bulk of CAD labels) are tabular, so per-character placement matches
whole-run placement. Lowercase (fi/fl/ff ligatures) and everything outside ASCII
(Arabic/CJK/combining marks) fall back to whole-run shaping. Stroked and gradient
runs also stay on the whole-run path (their fresh painters must stay
width-consistent with the layout).

It is behind `CanvasPdfDevice.perGlyphSubstitutedText`, **default off**. The
flutter_test font has no kerning, so the mechanics are pixel-exact there
(`per_glyph_text_test`: composed == whole-run byte-identical), but real-font
uppercase kerning (`AV`, `WA`, …) can only be judged in a real browser against
the Ghent/pdf.js renders. That browser fidelity pass is the precondition for
turning it on by default; until then it ships as a proven, validated opt-in.

## Validation

- `per_glyph_text_test`: (1) a composable run composes pixel-identically to
  whole-run shaping, (2) a non-composable (lowercase) run is untouched by the
  flag, (3) 200 unique runs leave the run cache empty and the glyph cache at an
  alphabet (< 20).
- Default-off render is unchanged: the byte-identical substituted-text render
  test passes, and the 20 Ghent failures are pre-existing (CMYK/overprint/
  softmask — verified identical on a clean tree), not from this change.
- `flutter build web` compiles the device + harness change.

## Incidental fix

The run-cache key `'${run.text} ${run.fontName} '` had its two literal spaces
stored as NUL bytes (`\x00`) — pre-existing corruption present since before this
session (harmless: NUL is still a valid separator, but wrong). Fixed to real
spaces while rewriting `_measureLayout`.

## Harness

`?perGlyph=1` (perf_harness.dart) and the `PERF_PER_GLYPH` driver env knob A/B
the feature on a single build — no webdiff needed, since `main` lacks the flag.
