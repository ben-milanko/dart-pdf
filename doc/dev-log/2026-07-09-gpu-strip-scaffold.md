# 2026-07-09 - Track A: sparse-strip GPU pipeline scaffolding

Session 1 of the shader-rendering experiment's Track A (plan:
`glittery-shimmying-gosling`). Goal: land the GPU half of vello_hybrid-style
sparse strips on `experiment/flutter-gpu` before the shared CPU strip
generator (`experiment/strip-core`, another agent) exists - shaders, a
one-draw batch class, and a byte-exact synthetic smoke test.

## Merge + re-baseline

- `git merge main` (main at a2331f0) merged **clean, zero conflicts** - the
  branch's near-copy of the pdf_cos lexer change was byte-identical to
  PR #199's landed version (`git diff main -- packages/pdf_cos/lib/src/lexer.dart`
  is empty post-merge). `packages/pdf_cos`: 198 tests green.
- Post-merge GPU spot baseline (pdfjs corpus only, scale 2, max 5
  pages/file, `PDF_GPU_MSAA=0 PDF_GPU_PIPELINE=1`): **11.3 ms/page**
  (195 pages, 158 files ok, 12 pre-existing file errors; per-file mean
  12.4, median 4.0). Not comparable to the 52.8 combined-corpus figure -
  the spot run excludes the big real-corpus CAD pages; use 11.3 as the
  same-protocol reference for the A1/A2 before/after.

## What landed

- `tool/gpu_shaders/pdf_strip.vert` + `pdf_strip.frag`, registered in
  `build.sh` (`PdfStripVertex`/`PdfStripFragment`) and compiled into the
  checked-in `assets/shaders/pdf_gpu.shaderbundle` (impellerc
  `--runtime-stage-metal`, bundle now 51,080 bytes).
- `lib/src/gpu/gpu_device.dart`: `PdfGpuPipelines.strip` +
  `stripVertInfo`/`stripFragInfo`/`stripSampler` uniform slots.
- `lib/src/gpu/gpu_strips.dart`: `StripBatch` - takes the strip
  generator's raw SoA arrays, builds one interleaved vertex buffer (two
  triangles per strip) + one RGBA8 alpha atlas, issues ONE alpha-blended
  draw. Exported from `lib/gpu.dart`. Reuses the HostBuffer
  1MB-block-boundary `emplace` fallback (own device buffer on throw).
- `test/gpu_strip_probe_test.dart`: synthetic smoke test, passing with
  exact byte checks.

## Vertex/data contract (for the strip-core agent)

`StripBatch.setStrips` consumes (documented in gpu_strips.dart, must match
`pdf_graphics/lib/src/raster/strip_generator.dart`):

- `xy: Int32List` - per strip `x | (y << 16)`, u16 device px, strip
  top-left; strips are 4 px tall.
- `widthFlags: Uint32List` - **low 16 bits = width in px**; high-bit
  generator flags are ignored by the GPU side (solid comes from
  alphaOffset, fill rule is a generator-side concern).
- `alphaOffset: Uint32List` - first coverage column's index **in texels
  (columns)**, `0xFFFFFFFF` (`stripSolidOffset`) = solid strip.
- `color: Uint32List` - premultiplied RGBA8, little-endian packing
  `r | g<<8 | b<<16 | a<<24` (i.e. bytes [r,g,b,a] in memory).
- `alphas: Uint8List` - column-major, 4 bytes per column, **byte 0 = the
  strip's TOP pixel row**; 4 bytes upload verbatim as one RGBA8888 texel
  (row 0 -> R ... row 3 -> A).

GPU-side vertex layout (StripBatch builds it; generator never sees it):
8 floats/vertex - x, y (device px, y-down), alphaTexelIndex (left edge =
alphaOffset, right = alphaOffset+width; fragment floors the interpolant),
yFlags (0 top / 4 bottom; +4 both for solid), premul r, g, b, a.

## Shader details / gotchas

- **Vertex uniforms work** in flutter_gpu runtime stages: `VertInfo{vec2
  viewport}` on the vertex shader converts device px -> NDC, first use on
  this branch (all prior pipelines pre-transform on CPU).
- Uniform blocks upload as 16-byte-padded `Float32List(4)` like the
  existing FragInfo pattern.
- Channel select is the SkSL-safe step-mask dot: one-hot
  `step(vec4(-0.5,.5,1.5,2.5), row) - step(vec4(.5,1.5,2.5,3.5), row)`
  dotted with the sampled texel - no bitwise ops, no dynamic indexing,
  no texelFetch (which SIGABRTs impellerc's GLES2 stage).
- Texel index -> atlas x/y via floor/div/sub (`mod` avoided for exactness);
  nearest sampling at texel centers `(x+0.5)/size` is byte-exact on Metal.
- Solid strips still execute the texture sample (uniform control flow);
  StripBatch keeps their interpolated texel index in [0, width) so the
  fetch stays defined, and `mix(coverage, 1.0, solid)` discards it.
- `StripBatch.encode` mutates pass state (pipeline, blend enable+equation,
  bindings; `clearBindings()` at the end). **When GpuPdfDevice wires this
  in, it must invalidate `_boundPipeline` and `_blendState` after encode**
  - same discipline as `drawImage`'s tail.
- Atlas is a fresh `hostVisible` r8g8b8a8 texture per `setStrips` (contents
  change every batch); pool later if allocation shows in profiles.

## Smoke test result

`gpu_strip_probe_test.dart` (needs `--enable-impeller
--enable-flutter-gpu`; skips otherwise): 64x64 box at (16,16) in a 96x96
aliased target (no depth/stencil/MSAA), 1px border ring at coverage 127,
interior 255; middle 14 strip rows use border alpha strips (width 1) +
interior **solid-flag** strips (width 62); `atlasWidth: 64` forces the 156
coverage columns across 3 atlas rows. Full 96x96 sweep of rawRgba
readback: outside == 0 exact, interior == 255 exact (both the alpha-texel
and solid paths), border in {127,128} (127/255 float round-trip), G == B
== 0 everywhere. Passed first run; validates vertex layout, u16 packing,
solid flag, all four channel selects, multi-row atlas addressing, and
src-over blending - everything except the generator.

## State / next

- `fvm dart analyze` clean; `gpu_render_smoke_test` + `gpu_probe_test`
  still green post-merge and post-bundle-rebuild.
- NOT started (next session, when `experiment/strip-core` lands): routing
  `GpuPdfDevice` fills through StripBatch, flush ordering vs the solid/text
  batches, clip coverage, `PDF_GPU_STRIPS` toggle, A1 gate benchmark.
