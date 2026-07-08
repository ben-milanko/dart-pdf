# flutter_gpu render backend experiment (branch: experiment/flutter-gpu)

**Question.** Impeller ships a low-level GPU API (`package:flutter_gpu`).
Would a direct-to-GPU PDF rasterizer - triangles + stencil buffer instead of
recording `ui.Canvas` display lists - beat the existing Canvas renderer, and
how does it stack against PDFium?

**Answer (TL;DR).** It works, renders the corpus visually well, but it is
*slower* than the existing Canvas path on real documents and much slower than
PDFium. The experiment stays a lab exercise; the interesting outputs are the
backend itself (a second, display-list-free consumer of `PdfDevice`), the
tester-can-do-GPU discovery, and the numbers below.

## What was built

- `packages/dart_pdf_editor/lib/gpu.dart` (+ `src/gpu/`):
  - `gpu_geometry.dart` - CPU tessellation: adaptive cubic flattening
    (Wang's bound), convex-loop detection, fan triangulation for
    stencil-then-cover, full stroke expansion (miter/round/bevel joins,
    butt/round/square caps, dashing, single-point dots).
  - `gpu_device.dart` - `GpuPdfDevice implements PdfDevice`. One render pass
    per page: batched solid triangles (fills/strokes/meshes share one
    pipeline + vertex format, flushed on scissor change); non-convex paths
    and glyph runs go stencil-then-cover (incrementWrap/decrementWrap per
    face for nonzero, invert for even-odd, union mode for translucent
    strokes); images are textured quads (premultiplied RGBA upload, cached
    across renders like the decode cache); axial/radial gradients evaluate
    in a fragment shader against a 256x1 LUT texture built from the stops.
    Clips become scissor rects. 4x MSAA color + stencil attachments.
  - `gpu_renderer.dart` - `PdfGpuPageRenderer.renderImage`, mirroring
    `PdfPageRenderer.renderImage` (same parse-once + scan-collect + decode
    shape) but painting with the GPU device and returning
    `resolveTexture.asImage()`.
- Shaders: `tool/gpu_shaders/*.vert|frag`, compiled offline by
  `tool/gpu_shaders/build.sh` via the engine's `impellerc
  --shader-bundle` (no native-assets hooks needed); the `.shaderbundle` is
  checked in as a package asset (Metal runtime stage only for now).
- Tests: `gpu_probe_test.dart` (context/orientation/attribute-layout probe),
  `gpu_render_smoke_test.dart` (CPU-vs-GPU parity on Ghent/pdfjs pages),
  `benchmark_gpu_render_test.dart` (4th harness, shared JSON schema).
  All skip cleanly without the GPU flags.

## Fidelity gaps (counted per render in `GpuPdfDevice.unsupported`)

substituted-font text paints nothing (no TextPainter without a Canvas);
non-normal blend modes composite as srcOver; soft masks are skipped
(content paints unmasked); transparency groups reduce to an alpha
multiplier (knockout ignored); non-rect clips scissor to their bbox.
Parity on the smoke pages is still tight - mean channel diff 0.7-2.9/255
vs the Canvas renderer, and the Ghent composite page reads correctly.

## How to run

```bash
# feasibility probe + visual parity
cd packages/dart_pdf_editor
fvm flutter test --enable-impeller --enable-flutter-gpu \
  test/gpu_probe_test.dart test/gpu_render_smoke_test.dart

# full 4-way comparison (PDFium / canvas / GPU / interpret)
benchmark/run.sh /abs/path/to/corpus 2 10
```

## Results

Scale 2.0 (144 DPI), 10 pages/file cap, best-of-3, dev Mac,
PDFium 5.9.0 / libpdfium 150.0.7869.0, Flutter 3.44.4 (Impeller Metal).
Timing = interpret + rasterize + full readback; totals only count pages
every tool rendered without error. JSONs in `benchmark/out/*-corpus.json`
and `*-ghent.json`.

**Real-world corpus (49 files / 255 pages: CAD, scans, reports, forms)**

| engine | throughput | ms/page | vs PDFium |
|---|---|---|---|
| PDFium | 40.1 pages/s | 24.9 | 1.00x |
| dart-pdf interpret (no raster) | 58.6 pages/s | 17.1 | **1.46x faster** |
| dart-pdf render (Canvas) | 16.3 pages/s | 61.3 | 2.46x slower |
| **dart-pdf GPU (flutter_gpu)** | 8.5 pages/s | 117.1 | **4.69x slower** |

**Ghent PDF Output Suite V5.0 (54 files / 57 pages, print conformance)**

| engine | throughput | ms/page | vs PDFium |
|---|---|---|---|
| PDFium | 46.0 pages/s | 21.7 | 1.00x |
| dart-pdf interpret | 79.9 pages/s | 12.5 | **1.74x faster** |
| dart-pdf render (Canvas) | 12.8 pages/s | 78.3 | 3.61x slower |
| **dart-pdf GPU** | 10.3 pages/s | 96.9 | 4.46x slower |

Per-file, the GPU path beats the Canvas path on only 6 of 49 corpus files
(best 0.62x on a transparency-group-heavy brief - saveLayer costs vanish
when groups become an alpha multiplier) and loses up to 4.3x on
text-dense pages. The pattern:

- **Text is the killer.** Every show-text run is a stencil pass + cover
  quad (2 draw calls) plus a fresh CPU flatten of each glyph outline.
  The Canvas path amortizes this through Skia/Impeller's glyph caching
  and the process-wide text-layout cache; this backend re-tessellates the
  same glyphs on every occurrence.
- **CAD linework** (ly9-far-cad: 4.7s vs 1.9s Canvas) pays for CPU stroke
  expansion: tens of thousands of segments -> ~6 triangles each ->
  hundreds of thousands of Float32 vertices built in Dart per render.
- Big-image scans are roughly at parity (AO-PR: 0.91x) - both paths are
  codec-bound, and the GPU texture cache mirrors the decode cache.
- The interpret row is the ceiling reminder: the pure-Dart walk is
  already faster than PDFium; everything lost is in rasterization.

## Gotchas discovered

- **The headless tester can host flutter_gpu.** `flutter test
  --enable-impeller --enable-flutter-gpu` gives a real Metal Impeller
  context inside `flutter_tester` (color b8g8r8a8, stencil s8, offscreen
  MSAA supported). No device or integration test needed.
- **`HostBuffer.emplace` SDK bug**: the bump allocator only opens a new
  block when the *start* offset passes the block end, so an emplacement
  that merely *crosses* the 1 MB boundary throws. `GpuPdfDevice._emplace`
  wraps it and falls back to a dedicated `DeviceBuffer`.
- `impellerc --shader-bundle` is enough to build flutter_gpu shader
  bundles offline; `flutter_gpu_shaders`/native-assets hooks are not
  required. The `--sl` output loads via `ShaderLibrary.fromAsset` with the
  usual package-prefixed asset key (bare key when the package is the test
  root - the loader tries both).
- `ui.ImageByteFormat.rawRgba` readback of a `Texture.asImage()` is the
  timing fence; `commandBuffer.submit()` alone returns before GPU work
  completes.
- The stencil-then-cover cover pass must reset stencil to 0
  (`StencilOperation.zero` on pass) so the buffer is clean for the next
  path without a clear between draws.

## Verdict / next steps

Keep as an experiment branch; do not merge into the product render path.
If it's ever revisited, the wins would come from (a) cross-page batching
and glyph-atlas caching rather than per-run stencil passes, (b) moving
tessellation off the UI thread (it is pure Dart and worker-friendly), and
(c) proper layer support (soft masks, blend modes) via offscreen textures,
which is where the approach stops being simpler than Skia/Impeller and
starts being a second Impeller.
