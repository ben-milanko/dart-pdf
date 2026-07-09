# 2026-07-09 — Track C: retained-scene zoom substrate + latency baseline

Track C of the 3-track shader-rendering experiment (branch
`experiment/zoom-retained`). Thesis: zoom must not re-interpret or re-decode
anything — retain the page as a replayable scene and re-render from it. This
session builds the strips-free substrate (the retained scene + measurement
harness); later phases swap the replay target for the strip/shader device
Track B is building.

## What landed

- `packages/dart_pdf_editor/lib/src/strips/strip_scene.dart` —
  `PdfRetainedScene`: records a page ONCE (interpret →
  `RecordingPdfDevice` command buffer) and decodes its images ONCE
  (shared `PdfImageCache`), then `replay({pixelRatio})` /
  `replayRegion(region, {pixelRatio})` rebuild a `ui.Picture`
  synchronously — only canvas calls, no parse, no codec. `rasterize` /
  `rasterizeRegion` wrap `toImage` with the same clamps as
  `PdfPageRenderer.rasterize`/`rasterizeRegion`. `fromCommands` adopts a
  worker-recorded buffer. This was mostly plumbing, as suspected: the
  scene is `renderPictureRecordedWithPlan` split at its natural seam
  (record+decode vs replay), with the decoded-image map's lifetime
  extended from per-call to scene-owned.
- `packages/dart_pdf_editor/lib/strips.dart` — opt-in barrel; the main
  barrel does not export experimental strip APIs.
- `renderer.dart` — new public `PdfPageRenderer.preparePageCanvas`
  exposing the background+page-transform preamble (previously the
  private `_paintBackground`/`_applyPageTransform` pair) so replay
  targets reuse the exact transform stack instead of copying it.
- `test/strip_scene_test.dart` — replay rasters **byte-identical** to
  the shipping cached-picture path (ratios 0.7/1.0/2.4 + a region at
  3.0) on the classic fixture. Passes.
- `test/zoom_latency_test.dart` — the latency harness (below).
- `example/lib/strip_zoom_demo.dart` + an app-menu entry
  ("Retained-scene zoom (experimental)") — opens a PDF via
  `file_selector`, records one page, `InteractiveViewer` pinch-zoom
  re-replays at the gesture scale, throttled to every 3rd transform
  change mid-gesture, exact settle scale on interaction end. Status bar
  shows commands / record(once) / replay / toImage ms.

## Latency harness

`test/zoom_latency_test.dart` (testWidgets + runAsync; corpus-gated, skips
cleanly when `ZOOM_CORPUS_DIR`/`../../corpus` is absent):

- Pages scale-to-fit a 2382×1684 target; zoom sequence
  [1.0, 1.5, 2.4, 1.2, 3.0]; every ratio capped by pdf_page_view's
  full-page raster caps (16.7M px / 8192 per side) so numbers reflect
  what the viewer actually rasterizes. 1 warmup + 3 timed passes.
- Paths per step: **(a) current** — cached `ui.Picture` →
  `drawPicture`-at-ratio → `toImage` (what `pdf_page_view._renderNow`
  does via `PdfPageRenderer.rasterize`); **(b) retained** —
  `scene.replay(pixelRatio)` → `toImage`; **(c) full** — re-interpret
  (`renderPictureRecordedWithPlan`, warm image cache) → `toImage`.
- Each split into build (picture production) / toImage / readback
  (`toByteData(rawRgba)`, forcing full realization so a GPU backend
  can't defer past the clock).
- Env: `ZOOM_LATENCY_FILES` (`name.pdf#page` per-file page selection),
  `ZOOM_LATENCY_PAGE`, `ZOOM_LATENCY_PASSES`, `ZOOM_BACKEND` (label).
- Test pages: `Flutter_CTO_Report_2024_by_LeanCode.pdf#0` (office,
  text+images), `INVOICE-1000664832.pdf#0` (office, text), and
  `ly9-far-cad.pdf#4` — page 4 is that file's heaviest sheet at ~677k
  content operators (page 0 is a light title sheet; ranked via a
  ContentStreamParser ops scan).

## Results

One-off costs (software run): report interpret 80.8 ms / record+decode
8.6 ms (warm image cache); invoice 29.0 / 2.9; CAD#4 interpret 458.2 ms,
record+decode 374.3 ms, 98 936 recorded commands.

### Software backend (`fvm flutter test`)

mean ms/step, 3 passes × 5 steps:

| page | path | build | toImage | readback | total |
|---|---|---:|---:|---:|---:|
| CTO report #0 | (a) current | 0.0 | 95.6 | 1.5 | 97.1 |
| CTO report #0 | (b) retained | 1.3 | 95.3 | 1.6 | 98.2 |
| CTO report #0 | (c) full | 5.3 | 97.9 | 1.7 | 104.8 |
| Invoice #0 | (a) current | 0.1 | 10.0 | 1.4 | 11.5 |
| Invoice #0 | (b) retained | 1.8 | 11.3 | 1.1 | 14.2 |
| Invoice #0 | (c) full | 3.2 | 10.6 | 1.1 | 15.0 |
| ly9-far-cad #4 | (a) current | 2.9 | 108.6 | 1.7 | 113.1 |
| ly9-far-cad #4 | (b) retained | 67.8 | 102.3 | 1.6 | 171.8 |
| ly9-far-cad #4 | (c) full | 444.0 | 101.7 | 1.6 | 547.3 |

### Impeller (`fvm flutter test --enable-impeller`)

mean ms/step, 3 passes × 5 steps (headless Impeller surface — absolute
numbers are not device numbers, the structure is what matters):

| page | path | build | toImage | readback | total |
|---|---|---:|---:|---:|---:|
| CTO report #0 | (a) current | 0.1 | 104.7 | 598.2 | 703.0 |
| CTO report #0 | (b) retained | 3.1 | 16.0 | 534.6 | 553.8 |
| CTO report #0 | (c) full | 8.7 | 24.2 | 561.1 | 594.0 |
| Invoice #0 | (a) current | 0.1 | 6.5 | 90.8 | 97.3 |
| Invoice #0 | (b) retained | 1.8 | 6.7 | 90.2 | 98.6 |
| Invoice #0 | (c) full | 3.3 | 6.1 | 91.6 | 101.0 |
| ly9-far-cad #4 | (a) current | 3.2 | 91.0 | 1469.9 | 1564.1 |
| ly9-far-cad #4 | (b) retained | 79.0 | 61.2 | 1392.6 | 1532.9 |
| ly9-far-cad #4 | (c) full | 450.5 | 71.6 | 1375.4 | 1897.5 |

The readback column (`toByteData(rawRgba)`) is a harness artifact on
Impeller: the viewer never reads pixels back (RawImage keeps the
texture on the GPU), so the app-relevant zoom cost is
**build + toImage**. The readback stays in the harness because on the
software backend it is near-free and it guarantees toImage can't defer
work past the clock. Impeller one-off costs matched software (CAD#4
interpret 517 ms, record+decode 362 ms).

## Where the time goes in (a)

- **Software**: toImage is ~everything — 95.6 of 97.1 ms (report),
  10.0 of 11.5 (invoice), 108.6 of 113.1 (CAD). That is Skia's software
  rasterization of the page display list at the new resolution; the
  "picture build" half of `PdfPageRenderer.rasterize` (recorder +
  `drawPicture` + endRecording) is ≤ 0.1 ms, and scheduler overhead is
  not in this harness at all. Zoom-settle latency on this backend IS
  the raster, full stop.
- **Impeller** (app-relevant = build + toImage): report (a) 104.8 vs
  (b) 19.1 — a 5.5× win for the retained scene from pure plumbing.
  Replaying the flat command buffer into a fresh picture rasterizes
  far faster under Impeller than `drawPicture`-nesting the cached
  picture at a new scale (toImage 16 vs 105 ms; the CAD page shows the
  same direction, 61 vs 91 ms). Nested-picture re-raster appears to
  defeat batching/culling that a flat replay keeps. The invoice is at
  the floor either way (~6.5 ms).
- (b) = (a) ± replay cost. Replay (re-issuing commands through
  `CanvasPdfDevice`) costs 1.3–3.1 ms for ~500-command office pages
  and 67.8–79.0 ms for the 98 936-command CAD sheet — the plan's
  ">~3000 fill ops stay on (a)" cutoff is confirmed by measurement.
- (c) adds interpretation: +5–9 ms warm for office pages, +444–450 ms
  for the CAD sheet. Never re-interpret on zoom.

## Read on the strip gate (can strip/Slug replay beat 0.5×(a)?)

- **Impeller: yes — already beaten without strips.** The report page's
  (b) is 0.18×(a) app-relevant. If the strip device's re-bin +
  drawVertices + toImage lands anywhere near flat-replay cost, the
  0.5×(a) office-page gate has headroom on Impeller targets — and the
  measured 5.5× plumbing win argues for wiring `PdfRetainedScene` into
  `pdf_page_view` regardless of how strips turn out.
- **Software backend: the gate is much tighter.** (a) is already the
  near-minimal Skia software raster; the invoice's 0.5×(a) budget is
  ~5.7 ms/step, below the plan's own 16 ms stretch re-bin target, and
  toImage of even a strips-only picture still pays the pixel-fill
  floor at deep zoom (up to 16.7 Mpx). Strips only win here if the
  Dart fine raster + one drawVertices genuinely undercuts Skia's path
  rasterization — plausible for glyph-heavy text pages (flatten cache,
  solid runs), not for the image-heavy report where (a)'s time is
  dominated by image blits strips don't touch (images flush to the
  canvas fallback).
- **CAD**: excluded from the gate by design, and rightly so — replay
  alone (68–79 ms) exceeds 0.5×(a) ≈ 56 ms before any binning. C2's
  Slug/transform-uniform zoom (no re-bin) is the only credible path to
  sub-frame zoom there, or Track B rendering strips live so zoom is a
  uniform update.

## Gotchas / notes for the next session

- Don't route per-zoom replays through `pictureFromCommandsWithPlan` —
  it decodes images per call (cache-hit clones, still churn). The
  scene owns its decoded map; `CanvasPdfDevice` borrows it per replay.
  Dispose order is safe: pictures hold their own image refs.
- `ly9-far-cad.pdf` page 0 is a light title sheet (231 commands,
  8 ms interpret). The scroll-hang reputation lives in pages 4/5
  (~677k content operators). Density was ranked with a throwaway
  ContentStreamParser ops scan; the harness's `name.pdf#page` file
  syntax exists for exactly this.
- One recorded command ≠ one operator: 677k operators collapse to
  98 936 commands (paths aggregate their segments).
- `flutter test --enable-impeller` works headless on macOS (Metal);
  toByteData readback there is 0.6–1.5 s per full-page image — never
  put a readback on the app's zoom path.
