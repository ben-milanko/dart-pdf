# 2026-06-26 — CAD heavy-raster perf probe (testing loop)

Ben reported the image-resolution cap "doesn't seem to be working" on the
real 58 MB CAD file (LY9 FAR ... IFC.pdf). Built a reproducible testing loop
and it pinned the behaviour immediately.

## The loop

`packages/dart_pdf_editor/test/cad_perf_probe_test.dart` drives the EXACT
worker record path on the test isolate — interpret → `serializeCommands(
decodeImages: true, maxImagePixelRatio: r)` → `deserializeCommands` →
`decodedImageStats` / `pictureFromCommands` / `rasterize` — so the cap and the
progressive vector-first pass are measurable without a browser or the compiled
web worker. Skips unless a file is present (default `../../corpus/ly9-far-cad.pdf`,
which is git-ignored, so CI skips it).

```
cd packages/dart_pdf_editor
CAD_PDF=../../corpus/ly9-far-cad.pdf fvm flutter test test/cad_perf_probe_test.dart
# knobs: CAD_PAGE (default: heaviest by scan), CAD_RATIO (px/pt, default 2.0),
#        CAD_SCAN=0 to skip the per-page heavy-page scan
```

It prints per-page image megapixels (scan), then for the target page: native
vs capped decoded MP, shipped buffer size, decode/serialize ms, full render
ms, progressive vector-only first-paint ms, and asserts the cap honored its
contract (decoded ≤ ~4×/0.9 the on-screen footprint, or a correct no-op).

## What it found (page 29, a ~3868×1084 pt large-format sheet, 52 image layers)

| ratio | cap result | decoded | buffer | full render | vector-first |
|-------|-----------|---------|--------|-------------|--------------|
| 0.3   | 8.3%      | 13.2 MP | 54 MB  | 143 ms      | 43 ms |
| 0.5   | 23%       | 36.7 MP | 144 MB | 273 ms      | 45 ms |
| 1.0   | 100%      | 159 MP  | 610 MB | ~1 s        | 75 ms |
| 2.0   | 100%      | 159 MP  | 610 MB | 0.9–8.8 s   | 64 ms |

Key facts:

- **The cap only fires when zoomed far out (ratio ≲ 0.6).** At a normal retina
  fit-to-window view (`_effectiveRatio` ≈ 2–2.5 for this sheet) it is a 100 %
  no-op: 159 MP decoded, a **610 MB** RGBA command buffer, ~0.9 s+ raster. That
  is exactly what Ben sees — the fix as built does nothing at the zoom he uses.
- **Why the no-op is "correct" per the current contract:** the page's on-screen
  image footprint at ratio 2.0 is **146.6 MP** — already ≈ native (159 MP). The
  cap targets 2× the footprint, so there is nothing to trim. The images are not
  individually oversized at this zoom.
- **But footprint (146 MP) ≫ the page raster (16.78 MP, the maxPixels ceiling)
  by ~8.7×.** The 52 layers overlap / overdraw heavily, so we decode and ship
  ~8.7× more image pixels than the page raster can ever show. The per-image cap
  can't see this; it would need a *page-pixel-budget* cap.
- **Decode (~2–4 s) is not reduced by the cap** even when it fires: the codec
  decodes at native resolution first, *then* box-filters down. The 2 s decode is
  the same at ratio 0.3 as at 2.0. This is the phase-1 "downsample on decode"
  gap — only a smaller *buffer*/raster is saved today, not the decode.
- **Progressive vector-first paint is 43–75 ms** in this harness — linework
  lands instantly. The progressive path itself works.

## Conclusion / levers (not yet implemented — needs Ben's call)

The stale-worker-bundle hypothesis is effectively ruled out: the cap is
genuinely ineffective at retina zoom for this overlap-heavy page, by design.
Ordered by impact at the zoom Ben actually uses:

1. **Page-pixel-budget cap** (new): bound *total* decoded image pixels per page
   to a small multiple of the page raster cap (≈16.78 MP), not each image to
   its own footprint. Would cut 159 MP → ~33 MP at ratio 2.0. Architecturally
   significant — changes cap semantics from per-image to page-aware.
2. **Downsample-on-decode (phase 1)**: produce reduced RGBA directly so the
   2–4 s native decode shrinks too (today only the buffer/raster shrink).
3. **Progressive first paint**: already ~60 ms here; confirm it actually shows
   in the app (if not, the web worker wiring, not the cap, is the suspect).

## In-app verification: the cap was a stale-bundle no-op, then a re-decode storm

Running the real file in Chrome (`flutter run -d chrome`, `?perf` log) showed the
cap doing nothing — page 29 still shipped **641 MB**. Cause: the web worker is a
precompiled `web/pdf_render_worker.dart.js` (git-ignored, rebuilt by CI on
deploy), and the local copies were from **Jun 16**, before any cap code. Rebuilt
both (`app/`, `example/`) with `dart run dart_pdf_editor:build_web_worker`; the
cap then fired (page 4: 20.6→11.4 MB, progressive/`vector-first` live).

But the rebuilt run exposed the real ceiling — **redundant + speculative worker
decodes**, which the cap can't touch:

- Each heavy page costs ~**8 s** to FlateDecode in the worker (sequential, one
  isolate). All 52 images on page 29 are FlateDecode 2048×2048.
- The worker decode is **uncached**, and `ListView` recycles a `PdfPageView`'s
  State on scroll-out, dropping its `_picture` — so scroll-back re-decodes from
  scratch. Observed page 22 decoded **7×**.
- `previewWindow = 20` fired prefetch records for **±20 pages = 41 pages**, each
  paying the full 8 s decode just to rasterize a 200px thumbnail (the cap
  downsamples the output, not the decode). The single worker churned for 150 s+.

### Landed (Bluebeam-study sequence step 1: cache + trim prefetch)

Studied how Bluebeam/PDFium/Forge/Qoppa render large CAD (GPU raster, iterative
LOD, viewport culling + tiling, prefetch+debounce, multithreaded tiles). It
confirmed cache+prefetch as the cheap correct next step and flagged
viewport-tile decode + a worker pool as the higher-ceiling follow-ups.

- **`PdfCachingRenderWorker`** (`render_worker.dart`) — an LRU decorator around
  the platform worker, keyed by (page, annotations, decodeImages, ratio bucket),
  bounded by decoded bytes (default 96 MB), one-page-over-budget skipped, no
  in-flight dedup (keeps it clear of the worker's cancel/priority logic).
  `PdfRenderWorker.start` wraps every worker in it; cache dies with the worker
  (new doc → new worker → fresh cache). A recycled page is now a map lookup, not
  an 8 s re-decode. Test seam `PdfRenderWorker.startUncached` for the
  queue/cancel/priority tests (caching short-circuits those by design). Library
  stays Flutter-free so the web worker still compiles via `dart compile js` —
  hence `startUncached` carries no `@visibleForTesting`. Tests in
  `render_worker_test.dart` ("PdfCachingRenderWorker" group).
- **`previewWindow` default 20 → 6** (`pdf_viewer.dart`) — bounds the prefetch
  flood from 41 heavy decodes to 13; revisits are free now via the cache.

Both changes are main-isolate only (no worker-bundle rebuild needed). Next per
the agreed sequence: **viewport-culled tile decode** for the large-format
sheets, then a **worker pool** for the serial 8 s-per-page floor.

## Landed: page-pixel-budget cap (`_imageBudgetFactor = 2.5`)

`serializeCommands` now runs a cheap declared-size pre-pass (`_imageBudgetScale`,
no decode) and, when the per-image-capped target areas sum past
`2.5 × 16.78 MP ≈ 42 MP`, applies a global linear downscale on top of the
per-image cap (`_capImageResolution(..., budgetScale)`). Tunable via the new
`imageBudgetFactor` param; threaded through the soft-mask recursion.

Measured on page 29 (probe), retina zoom (ratio 2.0):

| metric | before | after budget cap |
|--------|--------|------------------|
| decoded image pixels | 159 MP | **42 MP** |
| command buffer shipped | 610 MB | **164 MB** (now under the 256 MB cache) |
| full render | 0.9–8.8 s | **0.41 s** |
| vector-first paint | — | ~0.05 s |

The 164 MB buffer fits the decoded-image cache, so panning no longer thrashes
it — the original jank cause. Tests: `pdf_graphics` "page image budget" group
(forces the budget with a tiny factor on a Ghent image page), and the CAD probe
asserts the binding ceiling at every zoom.

## Phase 2 (downsample-on-decode) re-scoped — deferred

Breakdown of the residual ~1.6 s decode: **all 52 images are FlateDecode
2048×2048**, 27–69 ms each. zlib inflate is sequential — you cannot skip rows
to decode at lower resolution, so the full 159 MP of samples must inflate
regardless. Downsample-on-decode could only fuse the RGBA-expansion + box-filter
passes (memory traffic), not the inflate floor → ceiling ~0.4–0.6 s on this
file, off a **one-time, off-UI-thread** decode that the user never blocks on
(linework is already up in ~50 ms). Low ROI; deferred pending real-app
validation of the budget cap. The bundled decode_breakdown one-off lived in
scratch.
