# 2026-07-10 — Retained-scene zoom replay, mainlined (perf/retained-zoom-replay)

Productizes the zoom-retained experiment's headline win for main: on zoom
settle, `PdfPageView` now replays the page's retained command transcript
into a fresh **flat** picture at the new ratio instead of re-rasterizing
the **nested** cached `ui.Picture` (`scale` + `drawPicture` + `toImage`).
Impeller rasterizes the flat replay several times faster; output is
byte-identical. No strips, no shaders — this branch is cut from `main`
and carries only the strips-free pieces of the experiment.

## What landed

- `lib/src/retained_scene.dart` — `PdfRetainedScene` (extracted from the
  experiment's `strips/strip_scene.dart`, renamed; all strip references
  gone): `record` (one interpret + one image-decode pass),
  `fromCommands` (adopts a worker-recorded buffer; decodes via the new
  public `PdfPageRenderer.collectImageRequests`), synchronous
  `replay({pixelRatio})` / `replayRegion`, `rasterize`/`rasterizeRegion`
  with the renderer's exact clamps, scene-owned decoded images
  (disposed with the scene; replayed pictures hold their own refs).
  Exported from the main barrel.
- `lib/src/renderer.dart` — public `preparePageCanvas` (the
  background + page-transform preamble, so the scene replays under the
  renderer's exact transform stack) and `collectImageRequests`
  (previously private).
- `lib/src/pdf_page_view.dart` — the actual wiring (below).
- `test/retained_scene_test.dart` — the regression anchor: replay
  rasters **byte-identical** to `PdfPageRenderer.rasterize` at ratios
  0.7/1.0/2.4 plus a region at 3.0.
- `test/zoom_latency_test.dart` — corpus-gated harness (skips cleanly
  without a corpus): per-zoom-step cost of (a) cached-picture re-raster
  vs (b) retained replay vs (c) full re-render, plus first-render-delta
  and retained-footprint reporting.

## Wiring points in pdf_page_view.dart

1. **Kill switch + density ceiling**: `PdfPageView.retainedZoomReplay`
   (static, default true; false restores the previous behavior
   everywhere) and `PdfPageView.retainedZoomReplayMaxCommands` (static,
   default 20 000; pages recording more top-level commands never retain
   a scene and keep the classic path — see the CAD note below). Both
   gates live in one `_retainScene(commandCount)` helper; `_renderNow`
   and `_updateDetail` need no threshold logic of their own because an
   over-ceiling page simply has no scene.
2. **State**: `_scene` field alongside `_picture`; `_setScene` disposes
   the predecessor; `_dropPicture` (content change, epoch bump,
   dispose) also drops the scene — scenes die with the document
   revision, so the editing controller's swaps and the slot-recycling
   machinery see exactly the lifetime the picture already had.
3. **Scene production** — every interpret already flows through a
   recorded command buffer, so retention is free:
   - `_interpretPicture` now returns `(picture, scene?)`; the worker
     branch adopts the worker's buffer via
     `PdfRetainedScene.fromCommands`, the local branch records via
     `PdfRetainedScene.record`. In both, the cached picture IS
     `scene.replay(pixelRatio: 1)` — pair consistency by construction.
     `_renderNow` adopts the scene only after the superseded check
     (same discipline as the picture).
   - `_paintVectorFirst`'s image-free fast path (the complete page)
     also retains the scene. The image-skipped partial buffer is NOT
     retained (it isn't the page).
4. **Zoom re-raster** (`_renderNow`, stale-ratio branch): when a scene
   is held, `scene.rasterize(pixelRatio: effective)` replaces
   `PdfPageRenderer.rasterize(picture, ...)`. The `_rasteredRatio`
   guard, scheduler pacing/coalescing, `_superseded` checks, preview
   cache feeding, and progressive vector-first semantics are untouched.
5. **Deep-zoom detail patch** (`_updateDetail` local fallback):
   `scene.rasterizeRegion(region, pixelRatio: ratio)` replaces
   `rasterizeRegion(picture, ...)`. The worker detail path is
   deliberately unchanged — it re-records with region-capped image
   decodes (sharper images at deep zoom), a quality feature replay
   can't reproduce from base-resolution scene images.
6. `/Rotate` is baked into the scene's plan (`preparePageCanvas` +
   `plan.pageSize`); rotation changes drop the picture AND scene via
   the existing `nonContentVisualChanged` branch, as do pageColor /
   showAnnotations changes (annotations are recorded into the scene).

## Numbers (Impeller, `--enable-impeller`, mean ms/step, 3 passes × zoom [1.0, 1.5, 2.4, 1.2, 3.0], 2382×1684 fit)

before = (a) cached-picture re-raster (the old path), after = (b)
retained replay (the new path); (c) full re-render for reference.
Totals include the harness's toByteData readback; "app" = build +
toImage (the readback is a harness artifact — the viewer keeps the
texture on the GPU — but on Impeller `toImage` can defer raster work
into the readback, so both views are shown).

| page | before app | after app | before total | after total | (c) total |
|---|---:|---:|---:|---:|---:|
| CTO report #0 (office, images) | 44.9 | **15.8** (0.35×) | 499.4 | 430.1 | 425.8 |
| Invoice #0 (office, text) | 6.9 | 7.7 (parity) | 96.2 | 94.4 | 94.9 |
| ly9-far-cad #4 (99k commands) | 65.1 | 123.6 | 1409.9 | 1425.0 | 1837.4 |

(Software backend, from the experiment sessions: before ≈ after within
noise on every page — the toImage software raster dominates both — so
the swap is neutral there.)

- Office/image pages are the win case: the nested-picture re-raster
  penalty under Impeller (structural, reproduced across four runs at
  1.9×–6.5×) disappears. Text pages already at the raster floor are
  unchanged.
- **CAD density ceiling** (`PdfPageView.retainedZoomReplayMaxCommands`,
  default 20 000): replaying 99k commands costs ~65 ms on the UI thread
  per zoom settle, where the old path's `drawPicture` wrap was ~3 ms
  (the raster then lands off the UI thread / deferred) - totals are a
  wash, but the UI thread isn't. Pages recording more top-level
  commands than the ceiling do **not retain a scene at all** and keep
  the classic cached-picture zoom path: not-retaining (rather than
  retaining-but-not-replaying) also skips the command buffer's ~31 MB
  on exactly the pages where replay is never used. Office pages record
  a few hundred commands; at 20k the worst-case retained replay is
  ~15 ms, about one frame. The final Impeller run confirms the routing:
  report/invoice → `viewerPath=b-retained` (rows unchanged), ly9-far-cad
  #4 (98 936 commands) → `viewerPath=a-current`, i.e. its zoom row is
  the "before" row again (64.7 ms app-relevant / 1370.6 total).

## First-render cost delta

None by construction: the local path already interpreted through
`renderPictureRecordedWithPlan` (record → decode → replay); the scene
path performs the identical steps and simply keeps the buffer + images
instead of discarding them. Measured (Impeller run):
record+decode+replay1x vs interpret = -62.6 ms (report), -19.9
(invoice), -83.4 (CAD) — negative only because the interpret sample
runs first and warms the image cache; the honest statement is ~0.

## Memory (retained per live page, alongside the existing raster + picture)

Rough Dart-heap estimate (object headers + boxed doubles; harness
`_sceneFootprint`):

- CTO report: 542 commands / 2.0k segments → **~124 KB**
- Invoice: 545 commands / 0.4k segments / 628 glyphs → **~72 KB**
- ly9-far-cad #4: 98.9k commands / 540k segments / 33.6k glyphs →
  **~31 MB**

Decoded images add no new memory: the scene's map holds clones of
`PdfImageCache` masters the render already kept. The engine-side
picture also still exists (unchanged from before). So the delta is the
command buffer itself: negligible for office pages — and the CAD-scale
buffer is never retained, because such pages sit above the
`retainedZoomReplayMaxCommands` ceiling and keep the classic path
(see above). Retained memory in practice is therefore bounded by
ceiling × ~56 B/command plus path segments, well under a MB/page for
anything that actually replays.

## Verification

- `retained_scene_test.dart`: byte-identity full-page ×3 ratios +
  region — PASS.
- `pdf_page_view_test.dart`: new widget test pins the over-ceiling
  fallback (`retainedZoomReplayMaxCommands = 0` forces every page onto
  the cached-picture path; zoom re-rasters still land at the right
  geometry) — PASS.
- Full `dart_pdf_editor` suite under the new default (includes every
  `editing_*` widget test — they pump `PdfViewer`/`PdfPageView` — and
  `ghent_render_test` against unchanged checked-in baselines):
  **1285 passed**, 24 env-gated skips.
- `corpus_render_test` over `/Users/ben/repos/dart-pdf/corpus` (~50
  real-world files): PASS (renders to a scratch dir).
- `render_smoke_test` on INVOICE-1000664832 p0, ly9-far-cad p4,
  Flutter_CTO_Report p0: PASS.
- `fvm dart analyze`: clean.
