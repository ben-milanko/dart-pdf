# 2026-07-09 — Sparse-strip raster core (shared core + M1 gate)

Branch `experiment/strip-core` (on top of the M0 probe commit). Track B /
shared-core session of the 3-track shader-rendering experiment (plan:
`glittery-shimmying-gosling`). Everything here is pure Dart in
`packages/pdf_graphics/lib/src/raster/`, barrel `lib/raster.dart`
(deliberately NOT exported from `pdf_graphics.dart` — experimental
substrate, and worker-isolate reusable since it has no dart:ui).

## M1 gate: PASS

Target: interpret + strip-generate ≤ 38 ms/page mean on the real corpus at
scale 2 (interpret alone: 12.9 ms/page measured this session).

| run (scale 2, --max-pages 10, repeat 2, M4 VM) | ms/page | strips/page | alpha KB/page | % solid |
|---|---|---|---|---|
| real corpus (49 files, 255 pages) — first working version | 45.2 | 13 126 | 320 | 9.9 |
| real corpus — after the one optimization pass | **30.1** | 13 126 | 320 | 9.9 |
| test_corpora/pdfjs (171 files, 214 pages) — first version | 7.6 | 1 722 | 43 | 23.3 |
| test_corpora/pdfjs — after optimization | **2.8** | 1 722 | 43 | 23.3 |

Combined blend (the plan's reference mix): ~17.7 ms/page vs interpret 13.3
and Canvas 52.0. Strip output was byte-identical across the optimization
(identical strip/alpha counts). Zero corpus files error. Worst files are
all CAD sheets: ly9-far-cad 148 ms/pg (38k strips/pg), document.pdf 112,
WAT_L0001_S 109 (68k strips/pg, 1.4 MB alphas/pg) — these set the agenda
for any future pass (they are also the pages Track B's `> ~3000 fill ops`
fallback heuristic would keep on the canvas path).

## Files

- `lib/src/raster/flatten.dart` — `FloatBuilder`/`DoubleBuilder`/
  `FlatSubpath`/`FlatBounds`/`flattenPath` (Wang's bound on cubic second
  differences, `n = ceil(sqrt(3d/4tol))`, cap 128) + `dashSubpaths`, ported
  semantically identical from `experiment/flutter-gpu`'s
  `gpu_geometry.dart` (only dart:ui-free already; imports narrowed to
  `../path.dart` + `../matrix.dart`). Plus `FlattenedOutline`: em-space
  glyph flattening cached per `PdfPath` identity via `Expando` (same
  lifetime trick as canvas_device's `_glyphPaths`; the font engine memoizes
  outline instances). Tolerance 1/256 em = 0.25 px at a 64-px em.
- `lib/src/raster/stroke_contours.dart` — stroke expansion emitting closed
  polygon contours into a reused `StrokeContours` (flat DoubleBuilder +
  ring-end table): per-segment quads, miter/round/bevel join wedges
  (miter→bevel past the limit; round fans ≤ 0.35 rad/step), butt/round/
  square caps, isolated-dot handling, `width` clamped ≥ 1 px. **Every ring
  is winding-normalized (shoelace-positive)** — see gotchas.
- `lib/src/raster/strip_generator.dart` — `StripGenerator`/`StripBuffer` +
  `premulRgba8`. SoA layout per plan: `xy` u16|u16, `widthFlags` (width |
  `stripFlagSolid` 0x10000 | `stripFlagEvenOdd` 0x20000), `alphaOffset`
  (column index, `0xFFFFFFFF` solid sentinel), `color` premul RGBA8
  little-endian, `alphas` column-major 4 bytes/column (one RGBA8888 texel;
  stored internally as `Uint32List` texels so appends are single 4-byte
  stores, exposed as `Uint8List` view for upload).
- `tool/benchmark_strips.dart` — corpus benchmark, same JSON schema as
  `benchmark_interpret.dart` (compare.py-compatible) plus per-file
  `strips` and top-level `stripStats` extras. Headless device strips
  fills/strokes/outline-glyph text; counts images/gradients/meshes/groups/
  softmasks/clips/substituted runs (Track B's delegation set).
- Tests in `test/raster/`: flatten + dash goldens (hand-derived Wang
  n = 6 case), stroke contour structure (miter point at the computed
  apex, limit fallback, cap variants, wrap join on closed subpaths) and
  stroke coverage parity, strip coverage vs a supersampling reference
  rasterizer (convex pentagon, nonzero + even-odd self-intersecting
  stars, hole ring, thin sliver, subpixel rect, viewport-straddling
  shape) at ≤ 2/255 mean, `fillOutline`-vs-`fillPath` parity, and
  emission-structure invariants (solid runs, sentinel, column-major
  bytes, xy packing, buffer reuse).

## Fine-raster pipeline (per fill)

`fillPath` flattens straight into edges (no `FlatSubpath`
materialization, no per-op allocation; subpaths implicitly closed) →
`_edge` clips: y parametrically to the strip range, x by **splitting at
x=0 / x=width and projecting outside pieces onto the boundary as vertical
edges** (winding-exact viewport clip) → `_binSegment` y-slices into 4-px
rows, preserving direction so dy keeps its sign; nodes go into intrusive
typed-array linked lists (`_rowHead`/`_nodeNext`, coords row-local in
`_nodes`), touched rows tracked in a dirty stack with per-row min/max x →
`_rasterizeRow` does font-rs signed-area accumulation into a reused
`Float32List(4×(width+2))` (scanline-major), then a single fused scan:
prefix sum + fill rule (nonzero `min(1,|w|)`, even-odd triangle wave
`|w − 2·round(w/2)|`) + strip emission + **zeroing behind the scan**.
Strokes ride the same kernel: flatten → dash → contours → nonzero fill.
Glyphs: `fillOutline` transforms the cached em-space polylines directly
into `_edge` (transform-and-bin).

Emission state machine: zero runs end strips; all-255 runs ≥ 2 columns
become solid strips (planned economics; a lone 255 column joins the mixed
strip as a 0xFFFFFFFF texel); interior 255 runs inside a mixed strip are
held as `pending` and split out when they reach 2.

## The optimization pass (45.2 → 30.1 ms/page)

Instrumented split on WAT_L0001_S (68k strips/page): accumulate 23,
emit 39, zero 10 ms/page, stroke expansion only 9. So the scan, not
geometry, dominated:

1. **Fused zeroing** — the emission scan now zeroes each accumulator cell
   as it reads it (store only when the cell is nonzero) instead of four
   `fillRange`s afterwards; only the ≤ 2-cell spill tail past the scan end
   is zeroed separately.
2. **Column fast paths** — all-zero and all-`≥1` coverage columns skip the
   4× float→byte conversion (gaps between islands and fill interiors are
   the two dominant cases).
3. **Cull-pass skip for tiny paths** — the bbox pre-cull is a full extra
   pass over the path; paths ≤ 8 segments (CAD quads by the tens of
   thousands) go straight to flatten-and-bin, which clips anyway.

## Gotchas (for Track A/B consumers)

- **Stroke contours must share a winding orientation.** Overlapping rings
  at joins are only harmless under nonzero because `_endRing` normalizes
  every ring shoelace-positive; opposite-winding overlap would *cancel*
  (`|+1−1| = 0` holes at joins). Don't feed hand-built rings without
  normalizing.
- The nonzero rule uses `min(1,|w|)`, so nothing distinguishes w=1 from
  w=2 — same-winding overlap is safe, and CAD's opposite-winding
  edge-sharing triangle pairs are also safe (each triangle's interior gets
  its own row span; cancellation only happens where interiors overlap,
  which SAT-disjoint pairs don't).
- x-clipping must *split then project*, not clamp endpoints: clamping
  changes the slope and therefore the coverage of the visible part.
  Float drift at the split points is re-clamped in `_binSegment` (an
  x0floor of −1 would index `a[-1]`).
- The accumulate kernel writes up to one cell past `ceil(max x)` — the
  buffer is `width+2` wide and the emission scan's tail zeroing covers
  `[xEnd+1, xMax+2)`; touch that math and the reuse invariant breaks
  silently (next fill inherits garbage).
- Even-odd triangle wave relies on Dart's round-half-away-from-zero:
  `w=1 → 1 − 2·round(0.5) = −1 → |−1| = 1` (inside). A round-half-even
  port (JS?) would flip exact-integer windings.
- `Expando` keys on `PdfPath` identity: glyph caching only pays because
  `PdfFontInfo.outlineFor` memoizes outline instances. Text via
  substituted fonts has `glyphs == null` and must stay on the canvas
  fallback.
- Strip `y` is the row top (`r*4`); the last row can overhang the page
  bottom by up to 3 px — consumers clip to the viewport (Track B draws
  through `canvas.clipPath` anyway).
- Test literal trap: `<double>[2.0, 2, …]` — a leading double doesn't make
  a context-free list literal `List<double>`.

## Not done / next (Track B session)

- `curve_quads.dart` (Slug band lists) — plan lists it for B3/C2/A3; not
  needed for the M1 gate, deferred.
- `StripPdfDevice` in dart_pdf_editor (B1): awaiting go-ahead; the bench
  device in `tool/benchmark_strips.dart` sketches the delegation split.
- Remaining perf headroom if ever needed: per-stroke allocation in
  `flattenPath` (builders + Float64List copies), interval (not min/max)
  row spans for dashed near-horizontal strokes.
