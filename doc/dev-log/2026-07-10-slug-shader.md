# 2026-07-10 — B3: Slug glyph shader (pdf_slug.frag + SlugBatch)

Branch `experiment/strip-shader`, third B3 session (two prior sessions
stalled mid-debug; this one salvaged their WIP nearly whole and fixed the
two platform bugs that stalled them). Outline text through
`StripPdfDevice` can now render as em-space curve evaluation in a
fragment shader — one `drawVertices` per flush window, glyph outlines in
an rgba8888 curve atlas — behind the experimental static flag
`StripPdfDevice.slugGlyphs` (default false; default behavior unchanged,
full editor suite still green).

## What was salvaged vs rewritten

Salvaged as-built (the stalled sessions' design was sound):

- `curve_quads.dart` extensions: vertical band tables (`GlyphBands.vBands`)
  for the second AA ray, `glyphCoverageAA` (the dual-ray AA Dart reference
  the GLSL mirrors), relocatable `encodeGlyphStream` (stream-relative
  offsets so cached streams concatenate into a per-flush atlas verbatim),
  the Numerical-Recipes stable quadratic roots (`q = -(b + sign(b)√disc)/2`;
  textbook roots misplace crossings on the near-degenerate quads that
  fixed-point-rounded LINES become), and endpoint-sign crossing counting
  (strict `p > level` at shared, fixed-point-identical joints — never
  root-in-range tests).
- `slug_batch.dart`: `SlugGlyphData.of` Expando cache per outline identity,
  slot keying `(outline, qsx, qsy)` at 1/16 px/em, the 4-texel directory
  (stream base u16-pair / minY+bandH / minX+bandW / sx+sy), atlas assembly,
  chunked `ui.Vertices`.
- The whole shader body (band walk, both rays, AA weights) and all five
  test files. The tests were already excellent — the atlas-walk probe
  (Dart re-implementation of the shader against the assembled atlas bytes)
  is what proved the data path exact and pinned both bugs on the platform.

Rewritten: `readPair` decoding (bug 1), the texcoord scheme end-to-end
(bug 2), plus flush economics and the minification guard (below).

## The two platform bugs (why the previous sessions stalled)

1. **u16 texel decode double-rounding breaks integer comparisons.** The
   sampler normalizes bytes to [0,1]; `texel.b * 255.0` can come back as
   7.0000003. The loop break `float(i) >= count` then never fires at
   i == count, and the walk runs past the band list into adjacent table
   texels interpreted as curve refs — a re-counted crossing = ±1 winding
   over whole band-rows of pixels (the "horizontal stripe of 0.5
   coverage" the stalled session was chasing; mode-3 per-curve dumps
   showed iteration i=7 of a 7-count list contributing a duplicate
   crossing). Every encoded value is an integer u16, so the fix is
   `floor(v + 0.5)` inside `readPair` — after it, the shader is
   **byte-exact vs `glyphCoverageAA` on Skia (mean 0.00, max 0/255)** on
   the DejaVu 'g' probe. A float32-emulated Dart walk (scratch, deleted)
   matched float64 exactly, which is what pointed the finger at the GPU
   decode rather than precision.

2. **Impeller evaluates drawVertices runtime effects on an integer
   texcoord-unit grid.** Measured with a raw-uv debug mode (kept as
   pdf_slug.frag uDebug mode 4 + `slug_shader_debug_test.dart`):
   under Impeller `FlutterFragCoord()` values are always X.5 in *texcoord
   units*, constant across fragments whose texcoords span < 1 unit —
   i.e. Impeller snapshots the effect at ~1 texel per texcoord unit
   (integer-aligned) and samples that texture with the vertex UVs,
   bilinearly. The M0 probe never caught this because its texcoords were
   integer pixel-scaled (as are the strip batches' — why pdf_strips.frag
   is exact under Impeller). Em-unit texcoords (a glyph spans < 1 unit)
   collapsed to a single evaluated sample. Also measured: the snapshot
   grid does NOT follow the CTM (canvas.scale(4) still steps X.5), so
   per-fragment re-evaluation under zoom is Skia-only, permanently, until
   Impeller changes.

   Fix: texcoords are now in **record-time device-pixel units** per slot —
   `u = 2 + (emX − minX)·S`, `v = slot·cellH + 2 + (emY − minY)·S` with S
   the slot's quantized px/em and cellH a per-batch constant (patched into
   the tex array at build time, uniform uCellH); the shader inverts to em
   through the directory. minX/minY use the directory's fixed-point
   quantization so the inversion is exact. The 2-texel cell inset keeps
   Impeller's bilinear snapshot resampling from bleeding across slots.
   Skia semantics are unchanged (continuous interpolation, still
   byte-exact); Impeller now renders slug text as a correct
   record-resolution glyph raster (its snapshot **is** a glyph atlas
   rasterized by our shader, one cell per distinct (glyph, scale)).

## AA model and tolerance vs the reference

- `glyphCoverageAA`: per ray, sum over curve crossings of
  `sign · clamp(rootDistance_px + 0.5, 0, 1)`; coverage =
  `(min(|covH|,1) + min(|covV|,1)) / 2`. Binary-winding `glyphWindingAt`
  agrees away from edges; on edges the ramp is a linear-distance
  approximation of area coverage.
- Shader vs `glyphCoverageAA` (Skia): mean 0.00, max 0/255 ('g' 24px);
  synthetic square/circle/triangle micro glyphs max 1/255.
- Slug vs strip rendering (exact-area coverage), 3-run text page:
  mean 2.24/255, **signed +0.19/255** — symmetric per-edge noise, no
  systematic weight bias, so no coverageGamma knob was added (gputext
  carries one for Impeller's blending; ours measured unbiased — revisit
  only if real-device output looks weighted).
- Impeller: mean 4.98 max 169/255 vs the reference (bilinear resampling
  of the snapshot at subpixel quad offsets — resampling error, not model
  error; tolerances documented in slug_test.dart, SLUG_IMPELLER=1).

## Device integration

- `StripPdfDevice.slugGlyphs` (static, snapshotted per device) routes
  fill-only outline text (`run.fill`, no stroke/gradient, normal blend)
  to `SlugBatchBuilder`; everything else keeps its existing path.
  Per-run fallbacks to strips: any glyph's `GlyphBands.overflow`, or
  em size below the **minification guard** `slugMinGlyphPx`
  (constructor param, default 4 px/em — below that the per-pixel band
  walk aliases; strips supersample correctly; mirrors gputext's
  minificationGuardPx).
- Painter's order: strips draw before slug within a window. A
  strip-routed fill/stroke arriving while slug quads pend only forces a
  window close when its control-point bbox overlaps the pending quads'
  page-space bbox (`SlugBatchBuilder.overlaps`) — rules/borders around
  text keep batching. Delegated paints still close windows
  unconditionally (no bounds available).
- `estimatedVExtent > 8192` forces a flush so stacked slot cells stay
  under Impeller's snapshot/texture dimension cap.
- Curve streams build once per outline identity (`SlugGlyphData.of`,
  Expando like `FlattenedOutline`); the per-flush atlas is memcpys of
  cached streams. Stats: `totalSlugQuads`, `totalSlugAtlasTexels`,
  `SlugGlyphData.totalBuilds/totalBuildMicros`.

## Verification

- `slug_test.dart` (both backends; Impeller with SLUG_IMPELLER=1):
  shader-vs-reference, slug/strip/canvas text-page parity, painter-order
  window split, minification guard, batching stats, and the C2 micro-test.
- **C2 sharpness (the test that matters):** a picture recorded at 1×
  containing slug quads, replayed under a 3× canvas scale, vs a native 3×
  strip render: slug 1.78/255 vs baked-strip control 5.43/255 (Skia).
  Resolution-independent text in a single recorded picture works — the
  foundation for Track C transform-only zoom. On Impeller the same test
  asserts only parity with the control (4.84 vs 5.43 — no worse, no
  sharper; see bug 2).
- Ghent parity (`STRIP_PARITY_SLUG=1`), vs strip-glyph baseline
  (Skia 54/57 = 94.7%, Impeller 57/57):
  - Skia: **56/57 (98.2%)**, 0 blank, with a documented slug-mode mean
    backstop of 3.5/255 (15 text-dense pages sit at mean 2.2–3.1 with
    100% edge share and ~0 off-edge — the AA-model edge noise above,
    accumulated over glyph-heavy pages). The one failure is GWG120
    White overprint-knockout — the same low-contrast edge-classifier
    evader that fails the strip-glyph gate.
  - Impeller: **52/57 (91.2%)** (gate ≥90% holds); the 5 failures are
    the densest text pages at mean 8.5–9.5 vs the 8.0 Impeller backstop
    (snapshot-resampled glyphs vs the MSAA canvas baseline).

## Numbers (Impeller/Metal, matched back-to-back)

Text-heavy subset (NPR3JZA, documentsample, NSFS_550, Flutter CTO report,
ENV-SP-001, gs1au, TA20 from `corpus/`; 59 pages, scale 2, ≤10 pages/file,
repeat 2, `benchmark_strip_render_test.dart`, PDF_BENCHMARK_SLUG=1):

| mode | render ms/page | flushes | strip quads | alpha atlas | slug quads | curve atlas | interpret+gen | atlas decode | replay |
|---|---|---|---|---|---|---|---|---|---|
| strips + glyph cache | **61.0** | 69.0 | 7 259 | 386 KB | — | — | 10.8 | 3.9 | 1.0 |
| slugGlyphs | **86.7** | 136.3 | 2 349 | 369 KB | 1 220 | 468 KB | 7.5 | 10.6 | 1.6 |

One-time curve-stream builds: 2 260 outlines in 53 ms (~23 µs/outline,
process-lifetime cache; ~0.9 ms/page amortized on first render).

Verdict: slug static rendering is ~40% slower than strips-with-glyph-cache
on the shipping backend. Interpret+stripgen drops 3.3 ms/page (binning
moved off the CPU) but Impeller pays it back in per-draw snapshot renders
(~+20 ms/page unattributed "rest") plus a second per-flush atlas decode
(+6.7). Window count roughly doubles because the two accumulators split
windows the strip path shared. On software Skia the SkSL interpreter runs
the band walk per fragment: 474 ms/page — GPU-only technique, full stop.
This matches gputext's production conclusion: static text wants the
cached-raster path (strips); slug's unique value is Skia's per-fragment
re-evaluation — the C2 sharpness property — not steady-state throughput.

## Contract for Track C (transform-only zoom)

- A recorded strip picture with slug quads re-resolves text sharply under
  any later canvas transform **on Skia**; strips in the same picture stay
  record-resolution rasters. Replay seam: `StripPdfDevice` construction →
  interpreter walk → `await finish()` → `endRecording()`; `dispose()`
  after — unchanged from B1/B2.
- Curve data is scene-lifetime: `SlugGlyphData.of(outline)` streams live
  as long as the outline objects (font-engine memoized), so re-recording a
  page at a new zoom rebuilds only vertices + atlas memcpys (no curve
  math). The per-flush atlas (`SlugBatch.atlasPixels`) is still rebuilt
  per record; a persistent cross-flush/cross-record atlas is the next
  optimization if Track C records often.
- The slot key includes the quantized record scale (AA ramp width bakes
  into the directory), so a picture zoomed far beyond its recorded scale
  keeps a record-width AA ramp (~1 recorded px). Re-record when the zoom
  drifts far from record scale; between re-records the transform-only zoom
  is sharp (geometry exact, ramp slightly soft).
- On Impeller, transform-only zoom of slug pictures degrades exactly like
  strips (snapshot ignores the CTM). Track C's zoom story is therefore
  backend-split until Impeller evaluates runtime effects per fragment on
  drawVertices; a Skia-style `--no-enable-impeller` viewer or re-record on
  zoom-settle are the options.

## Debug tooling kept

- `pdf_slug.frag` uDebug modes (1 band select, 2 ray sums, 3 per-curve H
  contribution for curve index uDebug.y, 4 raw uv varying) driven by
  `StripPdfDevice.debugSlugMode/debugSlugParam`;
  `slug_shader_debug_test.dart` (gated: SLUG_DEBUG=1) prints all four.
  These found both platform bugs; keep them.
- `slug_atlas_probe_test.dart` re-walks the assembled atlas in Dart —
  splits atlas-assembly bugs from shader-semantics bugs.
- `slug_micro_probe_test.dart` asserts square/circle/triangle synthetic
  glyphs through the real shader path (Impeller-aware tolerances).

## Status

- Root `fvm dart analyze` clean; pdf_graphics 755 green; dart_pdf_editor
  1295 green (+26 skipped); non-slug parity unchanged (Skia 54/57).
- Not pushed.
