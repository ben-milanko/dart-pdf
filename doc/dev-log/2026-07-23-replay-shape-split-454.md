# 2026-07-23 — within-replay text-shaping split (#454)

## Context

#454 decomposed into a decode-bound half (page-0 DCTDecode on the UI thread,
addressed by #458) and a **replay-bound** half: the `ui.Picture` construction
itself, which on dense vector/CAD pages is 877 ms of pure `replay` with ~0
decode. The ticket's stated cost was "raw `ui.Canvas` call volume plus
`TextPainter` shaping of mostly-unique CAD labels," but *which* dominates was
never measured. This adds the split — consistent with how #455/#457 drove the
build-phase attribution — before anyone picks a fix.

## The instrumentation

`CanvasPdfDevice` draws substituted-font runs (non-embedded fonts — the
standard-14 case) by shaping them through `TextPainter` in `_measureLayout`,
cached by full run text (`_textCache`, 2048 LRU). The cache-miss factory is the
shaping; a hit is a cheap map lookup. So:

- `_measureLayout` now, when `PdfPerfLog.enabled`, times only the miss factory
  (`debugTextShapeUs`) and counts miss vs hit (`debugTextShapeMiss/Hit`). The
  shaping body was extracted to `_shapeLayout` so the hot (non-instrumented)
  path stays a one-liner and pays nothing.
- `pdf_page_view` resets those static accumulators before the retained-scene
  replay and reads them after, into `_lastInterpretTextShape*`.
- `PdfPerfLog.interpret` prints ` shape=<ms> shaped=<miss> cached=<hit>` next to
  the existing `decode=`/`replay=` split (only when measured).

## What it measured (desktop web harness, `PERF_VERBOSE=true`)

**scroll-plan** (16-sheet CAD plan set, substituted Helvetica):

```
page 2  replay=23.6ms  shape=0.0ms  shaped=0    cached=417
page 5  replay=57.7ms  shape=20.3ms shaped=362  cached=0
page 7  replay=54.2ms  shape=22.3ms shaped=397  cached=0
```

**scroll-diagram** (ultra-dense): `replay=84.3ms shape=0.0ms shaped=0 cached=1338`.

## The finding — shaping share is gated on label uniqueness

The "shaping dominates" assumption is **half right, and the half matters**:

- **Repeated labels** (plan pages 2–4; the whole diagram) → the run-cache
  absorbs them, `shape≈0`, and replay is 100% raw canvas-call volume.
- **Unique labels** (plan pages 5–7 — exactly #454's "mostly-unique CAD label"
  condition) → 100% cache miss, and shaping is **~37% of replay** (~20 ms of
  ~55 ms). The other ~63% is still canvas-call volume.

So a per-glyph cache (making unique labels cheap — the natural fix) is worth up
to ~37% of replay *on the worst, all-unique pages* and ~0 elsewhere. It is **not**
a fix for the vector-dense diagram case, which is canvas-call-volume bound with
shaping already at zero. That recalibrates the fix: per-glyph caching helps the
unique-label pathology specifically; command-count / slug-layer work is the
bigger lever for the dense-vector case.

## The worst case, made reproducible: `cad-labels-6p.pdf` / `scroll-cad-labels`

The corpus scenarios don't fully reproduce #454's device pathology because their
labels repeat. Added a dedicated worst case: `buildCadLabels` emits A3 sheets of
660 survey-point labels that are **unique across the whole document**
(substituted Helvetica), so the run-cache misses on every one — the "mostly-
unique CAD label" condition in pure form. Measured:

```
page 2  replay=55.7ms  shape=37.1ms  shaped=660  cached=0   <- first render, all unique
page 4  replay=52.3ms  shape=37.0ms  shaped=660  cached=0
page 5  replay=48.0ms  shape=33.0ms  shaped=660  cached=0
page 5  replay= 3.8ms  shape= 0.0ms  shaped=0    cached=660  <- re-render, all cached
```

### Both levers, quantified on the worst case

- **Text-cache lever ≈ 92% of replay.** The same page replays in **48 ms cold
  and 3.8 ms warm** — a ~13× collapse once the labels are cached. So ~44 ms of a
  unique-label page's replay is first-encounter text work: the measured **33 ms
  is layout** (`shape=`) and the remaining ~11 ms is first-paint/glyph-raster the
  `shape=` clock doesn't cover. A **per-glyph** cache — which turns unique *runs*
  into cached *glyphs* — is what could push a cold unique-label page from ~48 ms
  toward the ~4 ms floor.
- **Canvas-call-volume floor ≈ 3.8 ms** (~8% here). This is what the warm and
  vector-dense (diagram) cases are bound by; the per-glyph cache does nothing
  for it.

### Conclusion for the fix

The per-glyph cache is strongly justified **for the unique-label pathology**
(up to ~10× replay on those pages), and irrelevant elsewhere. It is a large
cross-layer change (interpreter → codec → device, Ghent/pdf.js pixel-baseline
gated), but it now has a measured ceiling and a reproducible A/B target
(`scroll-cad-labels`, cold vs warm). The canvas-call floor is a separate lever
(command count / slug layer) for the dense-vector case.
