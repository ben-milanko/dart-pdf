# 2026-07-10 — Mainlining sparse-strip rendering + stroke cache + zoom router

Branch `feat/strip-rendering`, stacked on `perf/retained-zoom-replay`
(PR #208, open at branch time — this PR rebases onto main once #208
merges). Three phases: extraction of the strip experiment's productizable
core, a new content-keyed stroke/fill strip cache, and the opt-in
dense-page strip zoom router. Slug (curve-in-texture glyphs) stays
shelved on `experiment/strip-shader` per the cross-track summary.

## Phase 1 — extracted from `experiment/strip-shader` (strips only)

- `pdf_graphics`: `lib/raster.dart` (minus the `curve_quads.dart`
  export — Slug foundations excluded), `src/raster/{flatten,
  stroke_contours,strip_generator}.dart` (incl. the glyph strip cache),
  `test/raster/` (minus `curve_quads_test.dart`),
  `tool/benchmark_strips.dart`.
- `dart_pdf_editor`: `shaders/pdf_strips.frag` + `pdf_probe.frag` (+ the
  pubspec `shaders:` entry, no `pdf_slug.frag`), `lib/strips.dart`,
  `src/strips/{strip_device,strip_batch}.dart` (no `slug_batch.dart`),
  the strip test set (`strip_device/probe/curve_probe/overlap_probe/
  skia_calibration/debug/parity` + `benchmark_strip_render_test.dart`),
  the `RUN_STRIPS=1` hunk in `benchmark/run.sh`.
- `strip_device.dart` and the parity/benchmark tests were taken at their
  **pre-Slug commits** (`e1ce718`/`baae230`) so no `slugGlyphs` flag or
  `slugMinGlyphPx` guard ever landed here — outline text always goes to
  strip binning.
- Renderer plumbing: `PdfRenderDeviceMode` + `PdfPageRenderer.deviceMode`
  + `_renderImageStrips` applied as a 3-way patch over #208's renderer
  changes (they touch disjoint regions; `preparePageCanvas` from #208 and
  the strips path coexist). `CanvasPdfDevice.endSoftMasked` split into
  `beginSoftMaskComposite`/`finishSoftMaskComposite` (behaviorally
  unchanged for canvas-only rendering; the whole file was checked out
  from the branch because of its embedded NUL byte, then verified to
  carry only the split).
- Excluded as stray: `pdf_document/tool/_inspect_page.dart` (debug
  helper) and the experiment dev-logs (they live on the branch).

## Phase 2 — content-keyed stroke/fill strip cache (`ShapeStripCache`)

Track A/C data said stroke expansion + binning dominate dense-CAD strip
generation. The glyph cache's design — relocatable strip blobs,
subpixel-phase quantization with y kept inside the 4-px strip row,
cache-on-second-sight — applied to geometry with **no shared object
identity**: the key is content (segment opcodes + point deltas from the
first point at 1/64 px + stroke/fill params + tolerance + anchor
subpixel phase), hashed to 32 bits with **full content verification on
every hit** (collision → direct raster; 14 collisions corpus-wide,
correctness never rides on the hash). First sights raster from the same
quantized content later replays use, so pixels never shift with cache
state (byte-identity tested in `shape_cache_test.dart`).

Design points that came from measurement, not the plan:

- **Generational rotation, not FIFO.** At a 16k entry cap, FIFO
  per-entry eviction rebuild-stormed ly9-far-cad (~36k keys/render)
  *slower than no cache at all* (165 vs 139 ms/page). Two generations
  rotate wholesale (O(1) bulk drop, promote-on-verified-hit); each
  generation (64k entries / 32 MB) holds a worst-case document's working
  set. Steady state on the heavy corpus: ~48k entries / ~24 MB.
- **The seen-filter is generational too.** A wholesale clear of the
  second-sight set used to land — deterministically, both passes —
  mid-corpus-sweep exactly when WAT_L0001_S rendered, so its keys never
  got past first sight. A sliding window fixes that failure mode; a 2×
  window was also tried to catch cross-sweep repeats and made everything
  worse (202k vs 48k builds — sweep-scale one-shots thrashed the entry
  generations). Cross-document-sweep reuse is not a pattern worth buying.
- **1/8-px anchor quantization** (finer than the glyph cache's 1/4):
  snapping a fill shifts whole edges, and at 1/4 px the Ghent parity
  relaxed-edge gate dropped to 48/57 (< 90%). 1/8 px restores 53/57 on
  software Skia (was 54 pre-cache; the two losses are the same
  glyph-cache-era text pages plus one transparency page at mean 2.0x),
  57/57 under Impeller. Hit rates barely moved (WAT 63.4% vs 64.9%).
- **No-joins stroke pad**: single straight hatch/dimension segments (the
  hot CAD case) skip the conservative `hw × miterLimit` bbox pad, which
  otherwise pushed ordinary wide strokes into the offscreen bypass.
- Only paths ≤ 64 segments attempt the cache (huge one-off boundary
  paths must not pay the content walk + hash); > 512 px a side or not
  fully in-viewport bypasses to the direct unquantized raster, exactly
  like glyphs.

### Numbers (interpret+stripgen, scale 2, ≤ 10 pages/file, repeat 2, M4)

| corpus | cache off | cache on | Δ |
|---|---|---|---|
| real corpus mean (49 files, 255 pages) | 29.96 | 27.25 | −9.0% |
| ly9-far-cad (in sweep) | 147.8 | 133.5 | −7.9% |
| WAT_L0001_S (in sweep) | 106.9 | 104.4 | −2.4% |
| ly9-far-cad (solo, repeat 3) | 149.9 | 124.8 | −16.7% |
| WAT_L0001_S (solo, repeat 3) | 107.8 | 63.0 | **−41.6%** |

Corpus hit rate 86%, no per-file regression > 10% and > 2 ms/page.
The solo numbers are the product-relevant steady state (re-rendering
one document, e.g. zoom re-bins); the in-sweep numbers approximate a
first encounter under cross-file cache pressure (≈ neutral for WAT —
its reuse is cross-page/cross-render, and 48 other files render between
its passes). `benchmark_strips.dart` grew `--no-shape-cache` and a
`shapeCache` stats block.

## Phase 3 — dense-page strip zoom router (`PdfPageView.stripZoomReplay`)

#208 made pages above `retainedZoomReplayMaxCommands` skip scene
retention (flat replay was useless for them). Strips invert that: dense
pages are the *best* replay case on Impeller. Opt-in wiring:

- `PdfPageView.stripZoomReplay` static flag, **default false**. When
  true, over-ceiling pages DO retain their scene and zoom-driven
  re-rasters — full page and the deep-zoom detail patch — replay through
  `StripPdfDevice` at the new ratio (`PdfRetainedScene.rasterizeStrips` /
  `rasterizeRegionStrips`; `PdfPageRenderer.pageToDeviceMatrix` made
  public as the transform seam). Under-ceiling pages keep #208's flat
  replay — strips lose on office pages.
- Default-off rationale: software Skia's SkSL interpreter makes the
  strip shader ~2× slower than the canvas, and there is no reliable
  runtime Impeller detection — the embedding app opts in where it knows
  its backend. And the trade is honest: the re-bin runs on the UI thread
  (~270 ms per settle on the CAD page below) — blocked longer, sharp
  ~4× sooner. **Worker-isolate strip generation is the path to
  default-on**: the strip core is deliberately dart:ui-free for exactly
  that (bin off-thread, ship the SoA buffers back, upload + drawVertices
  on the UI thread). Not built in this pass.

### Zoom-settle latency (ly9-far-cad page 4, ~99k retained commands, Impeller/Metal, mean of 5 steps × 3 passes)

| path | build | toImage | readback | total |
|---|---|---|---|---|
| a-current (cached picture) | 4 | 87 | 1485 | 1576 |
| b-retained (flat replay) | 80 | 67 | 1364 | 1511 |
| d-strips (router, flag on) | 268 | 14 | 98 | **380** |

~4.2× faster to sharp pixels than the shipping path (the experiment's
1446→414 on the same page, reproduced post-merge). The a/b readback
dominance is Impeller deferring the actual raster of the 99k-path
picture into `toByteData`; strips genuinely rasterize in the `toImage`.
`zoom_latency_test.dart` grew the (d) strips path + per-step batching
telemetry (~2 flushes/settle, 87–189k quads, 1.3–3.3 MB atlas).

Tests: `strip_zoom_router_test.dart` — routing (flag on + over ceiling →
strip telemetry ticks; flag off → exactly #208's cached-picture path,
zero strip activity) and a strip-vs-canvas replay image sanity check
(non-blank, mean diff ≤ 2/255, full page + region variant). Gotcha: the
image-sanity test must run *before* the widget zoom tests in that file —
after them, later `tester.runAsync` platform work (the
`decodeImageFromPixels` inside the atlas upload) never completes.

## Verification matrix

- Root `fvm dart analyze`: clean.
- `pdf_graphics`: 757 tests green (incl. 66 raster + Ghent/PDF.js corpus
  passes).
- `dart_pdf_editor`: 1304 green on software Skia; strip parity 53/57
  relaxed-edge (gate ≥ 90%), Impeller parity 57/57; probes, device
  tests, router tests green on both backends.
- `corpus_render_test`: 49/49 rendered (canvas path untouched).
- `ghent_render_test` vs checked-in baselines: green, no baseline
  changes (the default render path is byte-identical to before).

## Files

- Phase 1: see the extraction commit (`007e352`).
- Phase 2: `pdf_graphics/lib/src/raster/strip_generator.dart`
  (`ShapeStripCache`, `CachedShapeStrips`, `StripGenerator.shapeCache`,
  the content walk/quantized raster), `test/raster/shape_cache_test.dart`,
  `tool/benchmark_strips.dart`.
- Phase 3: `dart_pdf_editor/lib/src/pdf_page_view.dart` (flag + router),
  `lib/src/retained_scene.dart` (strip replay seam),
  `lib/src/renderer.dart` (`pageToDeviceMatrix` public),
  `test/strip_zoom_router_test.dart`, `test/zoom_latency_test.dart`.
