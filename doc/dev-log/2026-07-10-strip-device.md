# 2026-07-10 — Track B: StripPdfDevice on stock dart:ui (B1 + B2)

Branch `experiment/strip-shader` (off `experiment/strip-core` after the M1
pass). Delivers the shader-driven strip device, the Ghent device-vs-device
parity gate (B1), and the render benchmark (B2), plus two strip-core
accuracy fixes the parity work flushed out.

## Verdicts

- **B1 parity gate: PASS.** Ghent, both devices in-process at 2x:
  57/57 non-blank; relaxed-edge gate 56/57 (98.2%) on Skia, 57/57 under
  `--enable-impeller` with the documented Impeller thresholds. A
  delegate-everything render diffs **0.000%** on both backends (tape,
  transform, ordering exact).
- **B2 bench gate: FAILS on the software backend, WINS on the GPU one.**
  Corpus (scale 2, ≤10 pages/file, repeat 2, ms/page):

  | backend | strips | canvas |
  |---|---|---|
  | Skia software (`flutter test`) | 111.2 | 55.5 |
  | Impeller / Metal (`--enable-impeller`) | **115.2** | 159.1 |

  PDF.js corpus: software 28.3 vs 10.0; Impeller 42.2 vs 36.3.
  The ≤52/no-go-65 gate was defined against the software-Skia reference
  numbers → formally a no-go there; the shipping-relevant backend
  (GPU/Impeller — the environment Track B exists for) has strips **28%
  faster** on the heavy corpus. Coordinator call.

## Files

- `packages/dart_pdf_editor/shaders/pdf_strips.frag` (+pubspec `shaders:`)
  — coverage shader: `u` = global alpha-texel index (atlas position =
  `(mod(t,W), floor(t/W))`, sampled at half-texel centers), `v` = strip row
  `[0,4)` mixed (step-mask dot channel select) / `[4,8)` solid. Outputs
  `vec4(cov)`; color arrives as straight-ARGB per-vertex colors via
  `BlendMode.modulate` (Skia premultiplies vertex colors first, so
  modulate yields premul color × coverage exactly).
- `lib/src/strips/strip_batch.dart` — StripBuffer snapshot → `ui.Vertices`
  chunks (Uint16 indices cap ⇒ ≤16 000 quads/draw) + rgba8888 atlas
  (width 1024, final row padded, ≥1 texel so solid-only batches sample
  in-bounds).
- `lib/src/strips/strip_device.dart` — `StripPdfDevice`. **Key design: the
  painter's-order tape.** dart:ui has no synchronous pixels→`ui.Image`
  path (`decodeImageFromPixels` & friends are async), so drawing is
  deferred: interpret-time callbacks either bin into the StripGenerator or
  append `void Function(CanvasPdfDevice)` closures; `finish()` awaits all
  atlas decodes then replays the tape onto the one canvas (batches under
  `save(); transform(deviceToPage);`). Flushes: clip change, restore of a
  clip-bearing save frame, every delegated paint, group/soft-mask
  boundaries. Soft masks decompose via the new
  `CanvasPdfDevice.beginSoftMaskComposite`/`finishSoftMaskComposite` split
  (endSoftMasked itself is unchanged behaviorally — full editor suite
  incl. Ghent baselines still green); `drawMask()` runs at interpret time
  so its ops land on the tape between the halves. Knockout-group content
  delegates (`BlendMode.src` isn't expressible in the batched draw).
  Sub-device-pixel strokes match Skia's model: 1-px band at
  `alpha × deviceWidth`.
- `lib/strips.dart` — barrel (one export per file; Track C's
  `strip_scene.dart` should union-merge cleanly).
- `lib/src/renderer.dart` — `PdfRenderDeviceMode` + static
  `PdfPageRenderer.deviceMode`; `_renderImageStrips` records at the target
  pixelRatio (strip quads are only valid at the recorded ratio),
  `_pageToDeviceMatrix` mirrors `_applyPageTransform` incl. /Rotate.
- Tests: `strip_device_test.dart` (byte-level synthetic coverage incl.
  fractional edges/diagonals/translucency, painter-order with clips, flush
  stats), `strip_parity_test.dart` (the B1 gate), probes
  (`strip_curve_probe_test`, `strip_overlap_probe_test`,
  `strip_skia_calibration_test` — all assert strips vs analytic ground
  truth), `strip_debug_test.dart` (env harness: dumps canvas/strips/diff
  PNGs; `STRIP_DEBUG_DELEGATE_{ALL,FILLS,STROKES,TEXT}` bisection knobs).
- `benchmark_strip_render_test.dart` + `RUN_STRIPS=1` in `benchmark/run.sh`
  (adds `dart-strips.json` to the comparison).

## What the parity work found (chronology matters for Track A/C)

1. **Stroke min-width clamp** (strip core): the GPU experiment's
   `hw = max(width,1)/2` doubled Ghent's 0.25-pt X patches. Fixed in core:
   widths are exact; `width <= 0` = 1-px PDF hairline
   (`426ed77`, with test).
2. **Skia hairlines thin strokes**: sub-device-pixel widths render as
   1-px bands at `alpha × width`, not true thin bands. The device now
   matches (device-level, core stays exact).
3. **Skia's own curve AA is inexact.** Probe (glyph-sized cubic):
   analytic 77, strips 79, **skia 135** — up to ~0.2 coverage off true
   area on cubic edges; strips stay within 4/255 of analytic everywhere
   probed. Consequence: strict 8/0.05% parity vs Skia is unattainable on
   curve edges *by design*, and the diff is in strips' favor. Hence the
   documented relaxed-edge gate: differing pixels on canvas-side contrast
   edges (3×3 range > 48) are tolerated; **off-edge** strict fraction ≤
   0.05% + mean |diff| ≤ 2/255 per page. One page fails it on Skia
   (GWG120 White overprint-knockout, 95% edge-share — white-on-white
   low-contrast edges evade the edge classifier).
4. **Impeller's canvas is 4×-MSAA-coarse**: dense-page mean diff ~6/255
   with strips unchanged (unit tests + delegate-all still exact under
   Impeller). Impeller parity thresholds: mean ≤ 8, off-edge ≤ 1%,
   `STRIP_PARITY_IMPELLER=1`. This is literally the Track A motivation
   (analytic AA beats MSAA) showing up as a parity "failure".
5. Glyph em-cache tolerance tightened 1/256 → 1/1024 em while chasing
   text diffs (2× points, still cached once per glyph); the residual text
   diffs turned out to be (3), not flattening.

## B2 numbers (corpus, ms/page, repeat 2)

Phase split (strips): interpret+stripgen 24.7 · atlas decode 2.7 · tape
replay 1.6 · toImage 52.8 software / **3.5 Impeller** · rest ≈ parse +
pure-Dart image decode + readback (`toByteData`; ~80 ms/page of both
Impeller totals is readback+decode overhead common to both devices).
Strip shape stats: 49.2 flushes/page, 12.2k quads/page, 476 KB atlas/page,
202 delegated paints/page (pdfjs: 14.7 / 1.7k / 79 KB / 22).

- Software failure cause, measured with `debugNoShader`: the SkSL
  interpreter runs the coverage shader per fragment — 52.8 → 15.6 ms/page
  when the shader is removed (~37 ms/page). Native path raster is simply
  faster than interpreted per-pixel SkSL on CPU; no strip-side batching
  fix changes that.
- GPU story: strip draws (3.5 ms/page) replace Impeller's tessellated
  path rendering (canvas 159 vs strips 115 total). Light pages lose ~6
  ms/page to fixed atlas-decode+replay overhead (pdfjs 42.2 vs 36.3).
- Ideas not taken (documented for a possible B3): drawing solid strips
  shader-less in a second drawVertices breaks painter's order between
  overlapping fills of one batch (no safe static split); per-batch
  overlap tracking could enable it. Readback-free benchmarking (keep the
  image GPU-side) would show the draw-path gap more directly.

## For Track C (swapping replay onto this device)

- Construct `StripPdfDevice(canvas, pageToDevice: ..., deviceWidth/Height,
  pixelRatio, images)` per render; feed it device callbacks (a
  RecordingPdfDevice replay works — `drawMask` closures replay at
  interpret time and are safe); `await device.finish()` **before**
  `endRecording()`, `device.dispose()` after.
- Strip pictures are valid only at the recorded `pixelRatio`; re-zoom =
  re-bin (`begin()` + refill) — that's C1's whole premise.
- Vertex colors are straight ARGB (the generator's color payload is
  caller-defined; `premulRgba8` is for CPU compositing only).
- `StripPdfDevice.totalFlushes/totalStripQuads/totalAtlasTexels` +
  `resetStats()` give per-frame batching telemetry; expect ~1–3 flushes
  per re-bin frame when no delegated content interleaves.
