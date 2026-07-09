# 2026-07-10 - Track A sessions 2: strip core merged, A1+A2 wired

Continues [2026-07-09-gpu-strip-scaffold.md](2026-07-09-gpu-strip-scaffold.md).
The shared CPU strip generator (`experiment/strip-core`, M1-passed at
30.1 ms/page interpret+strips on the real corpus) merged clean - only
additions (pdf_graphics `lib/raster.dart` + `src/raster/`, the Track B M0
probe files). All 48 `pdf_graphics test/raster/` tests green in this
worktree; full pdf_graphics suite 739 green.

The landed SoA contract matched the scaffold's spec except `xy` is
`Uint32List` (spec said Int32List) - `StripBatch.setStrips` adapted, and it
now uses the core's `stripSolidSentinel` (local `stripSolidOffset` constant
removed).

## Integration cross-check (before device wiring)

`gpu_strip_probe_test.dart` gained a second test: the classic
self-intersecting even-odd star (hollow core) rendered twice - (a)
`StripGenerator.fillPath` -> `StripBatch` into a 1-sample target, (b) the
same `PdfPath` through `GpuPdfDevice.fillPath`'s stencil-then-cover into a
4x MSAA target. Result: mean channel diff < 2.5 (edge-only), and every
pixel that is fully-in/fully-out in both renders matches **exactly**;
hollow core + solid arms asserted in both. The generator's real output
composites identically to MSAA away from edges through the strip pipeline.

## What landed (device wiring)

`GpuPdfDevice(strips: true)` - plumbed from `PdfGpuPageRenderer.
stripsEnabled`, env `PDF_GPU_STRIPS=1` in the benchmark harness,
`gpu_render_smoke_test`, and `gpu_profile_test` (all also honor
`PDF_GPU_MSAA`). Strip mode forces a 1-sample target (`useMsaa` off).

- **A1 fills**: `fillPath` -> `StripGenerator.fillPath` at device scale
  (`pageToDevice`), `premulRgba8(color, alpha*groupAlpha)`. Shape
  instancing/classification bypassed entirely.
- **A2 strokes**: `strokePath` -> `StripGenerator.strokePath` (device-scaled
  dash + width, contour expansion + nonzero fill CPU-side - translucent
  strokes no longer double-blend at joins, an improvement over the aliased
  path).
- **A2 glyphs**: `drawText`'s batched common case (fill, no gradient/stroke)
  -> `FlattenedOutline.of(outline)` (em-space flatten cache) +
  `fillOutline(emToDevice)` per glyph. Gradient/stroked text and the
  weird-scale fallback stay on stencil-then-cover.
- **Batching**: strips are a third deferred batch next to solid/text - at
  most one open at a time; `_ensureStripBatch` flushes the other two,
  `_ensureSolidBatch`/`_openStencilBatch`/`_stencilRaw`/`drawImage`/
  `finish` flush strips. `_flushStrips` = one atlas upload + ONE draw
  (fresh atlas texture per flush - earlier encoded draws reference their
  texture at submit time, so no overwrite), then invalidates
  `_boundPipeline`/`_blendState` (encode owns pipeline+blend+bindings).
- **Clips**: the device's clip machinery is scissor-rect (non-rect clips
  were already bbox-approximated), and the strip batch draws under the
  scissor it opened with (flush on change) - strip clipping is therefore
  exactly as correct as the existing pipelines. Full CPU clip-coverage
  intersection (for real non-rect clips) deliberately not built: it would
  exceed the fidelity of everything else in this device. If it comes, it
  belongs in the shared generator.
- Non-strip draws (images, gradients, meshes) unchanged, interleaved in
  painter's order via the flush discipline.
- `setStrips` hot loop rewritten to straight-line indexed writes (was a
  closure per corner; tens of thousands of strips/page).

## Numbers (scale 2, max 10 pages/file, pipelined, this machine today)

Corpus = `/Users/ben/repos/dart-pdf/corpus` (255 pages), pdfjs =
`test_corpora/pdfjs` (214 pages, 12 pre-existing file errors in all
configs). "Combined" matches the historical 52.8/52.0 reference protocol.

Absolute numbers drift up to ~10% with machine thermal/background state,
so each row below is a **matched pair** (run back-to-back under the same
conditions); compare within a pair, not across pairs.

| matched pair        | corpus | pdfjs | combined |
|---------------------|-------:|------:|---------:|
| GPU aliased (am)    |  60.6  | 11.2  |  38.0    |
| GPU strips A1 fills |  60.0  | 13.3  |  38.7    |
| GPU strips A2 full  |  65.8  | 13.2  |  41.8    |
| GPU aliased (pm)    |  66.0  | 11.0  |  40.9    |
| GPU strips A2 (pm)  |  72.0  | 14.3  |  45.7    |
| GPU MSAA (am)       |  85.7  |   -   |    -     |

- **A1 gate (≤60 combined)**: passed - 38.7, dead even with aliased 38.0.
- **A2 gate (≤52.8 combined WITH AA)**: passed - 41.8 (pm re-check 45.7,
  still under), 21% under the gate; strips cost **+9-12% over aliased**
  in both matched pairs, where MSAA costs +41% (85.7 vs 60.6 corpus).
- Corpus-only A2 is 65.8/72.0 vs the aliased 60.6/66.0 of its pair; the
  plan's corpus no-go (>70) is not hit like-for-like (aliased itself
  measured 66.0 in the warm pair).
- Old references for context: pre-merge combined GPU aliased 52.8 / Canvas
  52.0 / MSAA 79.5 - main's lexer + interpreter wins moved the whole floor
  down since. The setStrips inline-write rewrite is within noise
  (unresolvable at ±10%); kept for its zero cost.

## AA quality evidence

Ghent smoke pages, mean channel diff **vs the canvas renderer** (the AA
reference), GPU configs at scale 2:

| page                | MSAA | aliased | strips A1 | strips A2 |
|---------------------|-----:|--------:|----------:|----------:|
| CMYK_X4 composite   | 1.57 |  4.99   |   4.92    | **2.55**  |
| GWG060 Shading      | 0.56 |  4.14   |   4.14    | **2.08**  |
| GWG090 Font-Support | 2.55 | 13.42   |  12.97    | **6.04**  |

GPU-to-GPU (strips A2 vs MSAA render): mean diff 1.06-3.61 where aliased
vs MSAA is 3.53-11.01 - strips sit 3x closer to MSAA than aliased.
Eyeballed crops (font page): aliased shows staircase glyph edges, strips
is near-indistinguishable from MSAA. Remaining gaps vs MSAA: gradient
fills (stencil-then-cover into the 1-sample target - gradient edges still
aliased) and image edges; both show in GWG060/GWG090's residual diff.

## Where the time goes (gpu_profile, strips mode, best-of-3)

Paint (= interpreter walk + CPU strip generation + vertex build) dominates;
GPU execution and upload are near-free:

- WAT_L0001_S p1 (CAD linework): paint 88ms (1595 strokes + 606 fills ->
  44k strips), GPU exec ~18ms, atlas upload 0.1ms - vs aliased paint 21ms.
  Stroke binning is the single biggest strip cost.
- CTC p0 (text-dense): paint 29ms (2596 text runs re-bin every glyph
  occurrence; `FlattenedOutline` caches flattening but not strips), GPU
  ~11ms - vs aliased paint 11ms (glyph triangle cache).
- Draw calls collapse: WAT = 2 strip draws for 44k strips (aliased: 56
  solid + 54 stencil + 54 cover).

Next optimization lever (deferred to the shared core, noted for the
strip-core agent): a glyph strip cache keyed on (outline, quantized 2x2
matrix + subpixel offset) replaying translated strips would kill the
re-binning cost that separates strips from aliased on text-dense pages;
same idea for repeated CAD symbols (the aliased path's shape-instancing
cache has no strip equivalent yet).

## Memory

Strip mode allocates no MSAA color (64MB transient at A3@2x) and a
1-sample stencil (16MB, still needed for gradient fills / gradient+stroked
text) vs MSAA mode's 4-sample pair (~128MB transient). Same footprint as
aliased mode, with AA.

## State

- `fvm dart analyze` clean; pdf_cos 198, pdf_graphics 739 (incl. 48
  raster), gpu probe/geometry/strip-probe/smoke all green.
- Strip mode remains opt-in (`stripsEnabled=false` default) - stock tests
  and baselines untouched.
- Not done: gradient fills through strips (they keep the stencil
  attachment alive), real non-rect clip coverage, glyph/symbol strip
  caching (above), Ghent full-corpus device-vs-device diff run.
