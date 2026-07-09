# 2026-07-10 — Glyph strip cache + Slug foundations (curve_quads)

Both items land on `experiment/strip-core` (`d0b78f5`, `aa5fd13`) and are
merged into `experiment/strip-shader` (`b497bbd`). Track A picks the cache
up by merging strip-core.

## 1. Glyph strip cache (`GlyphStripCache`, in strip_generator.dart)

Minimal core API addition: `StripGenerator.glyphCache` (mutable field,
default `GlyphStripCache.shared`, null = pre-cache direct path),
`GlyphStripCache(maxEntries, maxAlphaBytes)` with `hits/misses/
firstSights/bypasses/entryCount/alphaBytes/resetStats()/clear()`, and a
memoized `FlattenedOutline.bounds`. `fillOutline`'s signature is
unchanged; the caching is internal.

Design (as specified, plus two field-driven adjustments):

- Key `(FlattenedOutline identity, a,b,c,d quantized 1/64, x offset
  quantized 1/4 px, y offset quantized 1/4 px WITHIN its 4-px strip row)`.
  The y phase lives in [0,4) — 16 bins — because the replay translate must
  keep strip y row-aligned; x translate is any integer. Rasterization uses
  the fully quantized matrix, so hit and miss paths are deterministic per
  key (byte-identical build-replay vs hit-replay, tested).
- Entries are single-allocation relocatable blobs
  `[xy | widthFlags | alphaOffset | alphaTexels]` built in a glyph-local
  scratch StripGenerator (origin shifted to a row-aligned local frame);
  replay = one texel memcpy + a per-strip add of the packed `(dx | dy<<16)`
  translate + color override.
- **Cache-on-second-sight**: an approximate seen-hash set gates storage;
  first occurrence of a key renders directly (with the same quantized
  matrix, so nothing shifts when later occurrences replay). This is what
  rescued CAD pages — dimension labels at continuous positions produce
  huge one-shot key populations (corpus: 277k first-sights vs 391k hits)
  that previously paid build+store for nothing.
- **FIFO eviction, no LRU promotion** — LinkedHashMap remove+reinsert per
  hit was measurable churn; at 32k entries FIFO evicts fine. Caps:
  32k entries / 32 MB alpha texels (corpus steady state: 3.4 MB).
- Bypass (direct, unquantized): glyph leaves the viewport or exceeds
  512 px a side.

### Numbers (interpret+stripgen, scale 2, ≤10 pages/file)

| corpus (repeat) | cache off | cache on | replay rate |
|---|---|---|---|
| real corpus (r4) | 29.8 ms/page | 29.8 ms/page | 50% of draws (hits 391k / 789k; 76.5% of post-first-sight lookups) |
| — text-dense subset (>500 glyphs/page, 122 pages) | 31.4 | 30.4 | — |
| — clean text documents | 17.0 / 19.0 / 9.2 | 10.8 / 10.9 / 7.1 (−36..−43%) | — |
| test_corpora/pdfjs (r3) | 2.63 | 2.65 | 80.3% hit rate |

Corpus-wide it's a wash because CAD stroke/fill raster dominates and CAD
text is one-shot-heavy; the win is real and large exactly where Track A
hurt (text-dense pages). Per-file repeat-6 head-to-heads confirmed the
apparent sweep regressions were machine noise (e.g. CTC demo
20.8→19.4 ON). B2 Impeller spot pair (corpus, repeat 2): strips
116.2 ms/page with cache vs 115.2 pre-cache (readback-bound wash;
interpret+stripgen 23.7 vs 23.9). Strip stats unchanged
(12.2k quads/page, 476 KB atlas/page).

### Fallout fixed along the way

- **Latent fine-raster bug**: stepwise x in the accumulate loop can drift
  one ulp below the clamped node endpoints; glyph-local frames start
  exactly at 0, so WAT_L0001_S indexed the accumulator at −1 (crash).
  `xnext` now clamps at 0. This could in principle bite any fill whose
  geometry touches x=0 exactly.
- **API trap**: `StripGenerator({GlyphStripCache? glyphCache})` with
  `?? shared` silently re-enabled the cache for explicit-null callers —
  benchmarks measured nothing. Hence the mutable-field API.
- B1 parity moved 56/57 → **54/57 (94.7%)** on Skia (still ≥90% gate):
  the ≤1/8-px quantization pushes two text-dense pages (GWG090,
  GWG161-ICC) just past the mean-diff backstop (2.20/2.04 vs 2.0);
  edge-share stays 100%. Impeller parity remains 57/57. The curve probe
  now pins its transform to the 1/4-px grid (`62795f7`).

## 2. Slug foundations (`curve_quads.dart`, core-only)

API surface for the B3 shader session:

- `outlineToQuads(PdfPath, {tolerance = 1e-3})` → `List<QuadCurve>` —
  em-space cubic→quadratic within tolerance (midpoint-parabola bound
  `err0 = √3/36 |P3−3P2+3P1−P0|`, `n = ceil(cbrt(err0/tol))` pieces,
  piece control `(3Q1+3Q2−Q0−Q3)/4`); lines = midpoint-control degenerate
  quads; subpaths implicitly closed.
- `buildBands(curves, {bandCount = 8, maxCurvesPerBand = 16})` →
  `GlyphBands` — uniform horizontal bands over the curve bbox, per-band
  index lists sorted by descending curve max-x (shader early-out),
  `overflow` flag → caller falls back to outline strips (all tested DejaVu
  glyphs fit 16/band at 8 bands).
- `glyphWindingAt(curves, bands, x, y)` — the Dart reference evaluator the
  GLSL must match step for step: band select, early-out walk, quadratic
  roots of `Y(t)=y` in `[0,1)`, crossings `X(t)>x` signed by `Y'(t)`.
- `encodeGlyphTexels(curves, bands, {width = 256})` → `GlyphCurveTexture`
  (rgba8888 pixels + bandCount/bbox/bandHeight fields for uniforms).

**Texel encoding spec** (byte-exact under M0's verified reads): each texel
packs two 16-bit little-endian values `r=lo(u) g=hi(u) b=lo(v) a=hi(v)`.
Coordinates are fixed point `u16 = round(em * 8192) + 32768` — range
[−4, +4) em, resolution 1/8192 em; counts/offsets raw u16. Layout by texel
index: `0` header `(bandCount, curveCount)`; `1..bandCount` band table
`(listOffset, count)` with absolute texel offsets; band reference lists
(one texel per entry, `(curveTexelOffset, 0)`, max-x descending); curve
data 3 texels/curve `(p0, control, p1)`. Streams >65535 texels throw
(strip fallback). GLSL decode: `v = (lo + hi*256 - 32768) / 8192`.

Tests run on real DejaVu Sans outlines via `TrueTypeFont` (`a g B S e o`):
tolerance bound, closed-loop balance, band coverage/sort/overflow,
fixed-point + full encode/decode roundtrip (decoded winding matches at 200
random points), and band-evaluator coverage vs the strip fine raster
within 2.5/255 mean per glyph at a 24-px em.

## Status

- pdf_graphics: 754 tests green (63 raster).
- dart_pdf_editor post-merge: 1288 green; strip probes green; parity
  Skia 54/57 relaxed-edge (gate ≥90% holds), Impeller 57/57.
- Not pushed. Track A merges `experiment/strip-core` for the cache;
  B3/C2 consume `curve_quads.dart` + this encoding spec.
