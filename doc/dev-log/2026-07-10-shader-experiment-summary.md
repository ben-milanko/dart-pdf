# Shader-driven rendering experiment — cross-track summary

Coordinator's summary of the 3-track "GPU-rendered shader-driven, not
CPU-redrawn" experiment (2026-07-09/10). Per-session detail lives in the
sibling dev-logs; this file is the arc and the verdicts.

## Question

Can vello_hybrid-style sparse strips and Slug-style curve-in-texture
glyphs — CPU bins geometry once, fragment shaders do the pixels — beat
our two existing rasterizers (Canvas display lists, flutter_gpu
triangles+MSAA), and make zoom re-raster-free?

## Branch map

- `experiment/strip-core` — shared pure-Dart core: `pdf_graphics/lib/src/raster/`
  (Wang's-bound flattening, stroke→contour expansion, sparse-strip fine
  raster, glyph strip cache, `curve_quads.dart` Slug foundations).
- `experiment/strip-shader` (off strip-core) — Track B: `StripPdfDevice`
  on stock dart:ui (`shaders/pdf_strips.frag`, one drawVertices per
  flush) + B3 Slug glyphs (`shaders/pdf_slug.frag`, `slug_batch.dart`).
- `experiment/flutter-gpu` — Track A: strip pipeline in the GPU renderer
  (`gpu_strips.dart`, `tool/gpu_shaders/pdf_strip.*`), MSAA dropped in
  strip mode.
- `experiment/zoom-retained` (off strip-shader pre-slug) — Track C:
  `PdfRetainedScene` record-once/replay-any-ratio + zoom latency harness
  + example pinch-zoom demo.

## Gate results

| Gate | Target | Result |
|---|---|---|
| M0 probes | platform deps hold | PASS both backends; drawVertices+FragmentShader evaluates in texcoord space |
| M1 core | interpret+strips ≤38 ms/pg corpus | **30.1** (interpret alone 12.9) |
| A2 GPU strips | ≤52.8 combined w/ AA | **41.1–41.8**; AA at +6–9% over aliased where MSAA cost +41%; MSAA attachment (~64 MB) gone |
| B1 parity | ≥90% Ghent relaxed-edge | Skia 54–56/57, Impeller 52–57/57 (per mode) |
| B2 perf | ≤52 ms/pg corpus | software 111 = **no-go** (SkSL interpreter); Impeller **115.2 vs canvas 159.1 = 28% faster** — accepted on Impeller (GPU is the premise) |
| C1 zoom | ≤0.5× current on office pages | strips replay 1.2× = miss; **flat retained replay 0.18×** (the accidental headline); dense CAD: strips **0.24×** (1446→414 ms/step) |
| B3 slug | sharp text from one picture | Skia PASS (1.78 vs 5.43 control); **Impeller impossible by platform design** |

## What we learned (load-bearing)

1. **Sparse strips work in Dart.** Single-thread fine raster costs ~17
   ms/page corpus-wide (~2.8 on pdf.js pages), anti-aliased by
   construction, byte-stable, and the alpha layout uploads as raw RGBA8
   with zero conversion. The glyph strip cache (cache-on-second-sight,
   FIFO) makes text pages ~free (−36–43%); strokes are the remaining CPU
   cost (stroke/symbol cache = documented next lever).
2. **The MSAA gap is killed** (Track A): analytic-coverage strips give
   near-MSAA AA at +6–9% over aliased rendering vs MSAA's +41%, with no
   MSAA attachments and 164→2 draw calls on the profiled page.
3. **Stock dart:ui can host this** (Track B): whole-page strip batches in
   one drawVertices per flush; texcoord-space shader evaluation, exact
   rgba8888 texel reads, modulate-tint all verified byte-accurate. On
   Impeller it out-renders the Canvas device 28% corpus-wide; on software
   Skia the SkSL interpreter makes it a 2× regression — the device stays
   opt-in, canvas remains the software default.
4. **Zoom**: the win was already latent in the recording layer — flat
   replay of retained commands rasterizes 5.5× faster than re-rasterizing
   the nested cached picture on Impeller (nested-picture penalty), no
   shaders required. Strip replay inverts the plan's assumption: it loses
   on office pages (raster-floor + delegated images) and wins 4× on dense
   CAD (replaces 99k-path deferred tessellation). Router: flat replay by
   default, strips above an op-count threshold, never on software.
5. **Slug glyphs are real but platform-boxed**: byte-exact vs the Dart
   reference on Skia, parity gates hold, tiny-glyph minification guard at
   4 px/em (gputext's trick). But Impeller snapshots drawVertices runtime
   effects on an integer texcoord-unit grid, not CTM-aware — so
   resolution-independent text inside one picture is Skia-only, and slug
   costs more than cached strips to render (86.7 vs 61.0 ms/pg on text
   pages). Ships nowhere today; candidate for web/CanvasKit later, or if
   Impeller ever evaluates runtime effects per device pixel.
6. **Platform traps for posterity**: texelFetch SIGABRTs impellerc's
   GLES2 stage (breaks Android builds — use texture() at half-texel
   centers); vertex colors are not shader inputs (modulate only);
   FlutterFragCoord is local-space on Impeller; `texel.b*255` needs
   floor(+0.5) before comparisons (double-rounding); flutter test default
   backend is software SkSL — always dual-run.

## Productization candidates (in value order)

1. `PdfRetainedScene` flat replay in `pdf_page_view` zoom (0.18×, no
   shader risk) + strip replay above an op-count threshold on Impeller.
2. Track A strip mode as the GPU renderer's AA answer (lab branch).
3. Stroke/symbol strip cache in the core (closes most of the remaining
   strips-vs-aliased gap on CAD).
4. Slug: shelve; revisit for web or a future Impeller.

Corpus numbers throughout are matched back-to-back pairs (machine drift
~10%); reference floor moved mid-experiment when main's lexer PR #199
landed, so compare within sessions, not across.
