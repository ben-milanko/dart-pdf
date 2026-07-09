# 2026-07-10 — Track C session 2: strip replay on the retained scene

Merged `experiment/strip-shader` (Track B's `StripPdfDevice`, B1 parity
passed) into `experiment/zoom-retained` and swapped the retained scene's
replay target: zoom can now re-bin into strips instead of replaying onto
the canvas. Latency harness gained path (d); demo gained a replay-mode
toggle.

## What landed

- Merge commit `e6f9baa` — `lib/strips.dart` union-resolved to export
  `strip_batch.dart` + `strip_device.dart` + `strip_scene.dart`. Strip
  device tests + parity + `strip_scene_test` all green post-merge.
- `PdfRetainedScene.replayStrips({pixelRatio})` /
  `rasterizeStrips` (`strip_scene.dart`) — replays the retained command
  buffer into `StripPdfDevice` per Track B's contract (construct with
  `pageToDevice`/`deviceWidth`/`deviceHeight`/`pixelRatio`/scene-owned
  `images`; `await finish()` before `endRecording()`; `dispose()`
  after). Async (atlas decodes). Zero re-interpret / re-decode; the
  re-bin at the new ratio is the entire per-zoom cost, per C1.
- `PdfPageRenderer.pageToDeviceMatrix` made public (was
  `_pageToDeviceMatrix`) so the scene hands the strip device the
  renderer's exact transform.
- `zoom_latency_test.dart` path **(d) d-strips** + per-step telemetry
  via `StripPdfDevice.resetStats()`/`totalFlushes`/`totalStripQuads`/
  `totalAtlasTexels`/`totalDelegatedPaints`.
- `strip_scene_test.dart`: strip replay smoke — same raster shape,
  non-blank, mean channel diff vs canvas raster < 2/255 (strips are
  analytically-AA'd, not byte-identical, by design).
- Demo (`example/lib/strip_zoom_demo.dart`): "Flat replay / Strip
  replay" SegmentedButton, status line shows the mode; every-3rd-frame
  throttle unchanged.

## Latency (mean ms/step, 3 passes × zoom [1.0, 1.5, 2.4, 1.2, 3.0], 2382×1684 fit, viewer raster caps)

### Software (`fvm flutter test`) — documented strips no-go, confirmed

| page | (a) current | (b) retained flat | (c) full | (d) strip replay |
|---|---:|---:|---:|---:|
| CTO report #0 | 101.1 | 100.5 | 102.3 | 1255.4 |
| Invoice #0 | 12.0 | 15.2 | 15.2 | 58.9 |
| ly9-far-cad #4 | 116.0 | 166.2 | 515.4 | 559.0 |

(d)'s toImage explodes on software (report 1191.7 ms) — the SkSL
interpreter runs the coverage shader per fragment, exactly Track B's B2
finding. Not a target backend for strips.

### Impeller (`--enable-impeller`) — totals include the harness's toByteData readback

| page | (a) current | (b) retained flat | (c) full | (d) strip replay |
|---|---:|---:|---:|---:|
| CTO report #0 | 543.0 | 476.3 | 451.2 | 639.9 |
| Invoice #0 | 96.9 | 99.2 | 98.6 | 115.4 |
| ly9-far-cad #4 | 1446.3 | 1462.8 | 1826.7 | **413.8** |

Split highlights (build / toImage / readback):

- CAD (a): 3.1 / 70.9 / **1372.3** — Impeller defers the actual path
  rasterization past `toImage` into the readback (the invoice's ~90 ms
  readback is the pure 16.7 Mpx transfer floor; anything above that is
  deferred raster work). The cached-picture path really costs ~1.36 s
  of GPU-side work per zoom step on this sheet.
- CAD (d): **316.7 re-bin / 6.8 / 90.3** — the strip picture is fully
  rasterized by `toImage` (readback = pure transfer). Realized raster
  ≈ 324 ms ≈ **0.24×(a)**. Strips turn 99k tessellated paths into 2
  drawVertices flushes.
- Report (d): 63.7 re-bin — the re-bin, not the raster, is the office-
  page cost. Invoice (d): 19.4 re-bin vs (a)'s ~7 ms realized total.

## Gate verdict for (d)

**(d) ≤ 0.5×(a) on office/text pages: NOT MET — on either backend.**
Report 639.9 vs 543.0 → 1.18×(a); invoice 115.4 vs 96.9 → 1.19× (and
~3.5× on realized raster, 25 vs 7 ms). The office pages are already at
or near the raster floor, so the 19–64 ms re-bin can only lose there.
**(b) flat replay remains the best office-page zoom path** (report
0.88×(a) this run; 0.18× app-relevant in yesterday's run — image-heavy
GPU timings swing run-to-run, the ordering is stable).

**The plan's cutoff is inverted on Impeller.** "Pages > ~3000 fill ops
stay on (a)" is exactly backwards there: the dense-vector CAD sheet is
where strips demolish (a) — 413.8 vs 1446.3 total (0.29×), ~0.24× on
realized raster — while light pages should stay on (b). Suggested
router for the viewer: (b) flat replay by default, (d) strips when the
scene's command count (or Track B's fill-op count) crosses a threshold,
software backend always (b).

## Strip telemetry per zoom step (path d, Impeller run)

| page | flushes | quads z1.0→z3.0 | atlas KB z1.0→z3.0 | delegated |
|---|---:|---|---|---:|
| CTO report #0 | 11 | 11.6k → 25.6k | 128 → 248 | 38 |
| Invoice #0 | 66 | 3.8k → 21.8k | 268 → 456 | 1 |
| ly9-far-cad #4 | 2 | 87.4k → 189.3k | 1348 → 3304 | 1 |

Quads/atlas scale ~linearly with zoom until the 16.7 Mpx ratio cap
bites (z2.4 ≡ z3.0). CAD's 2-flush shape is the ideal batched form;
the invoice's 66 flushes are clip-driven (one flush per clip change)
yet cheap; the report's 38 delegated paints are its images (strips
don't cover image draws — that raster stays on the canvas fallback,
which is also why (d) can't win image-heavy pages).

## Demo feel

Not driven on-device this session (headless harness only). Structural
note: mid-gesture BOTH modes scale the stale raster (the throttle
replays at most every 3rd transform event), so gesture-time sharpness
is identical today — strip mode only changes the settle latency, which
on office pages is worse and on dense CAD dramatically better. The
sharp-during-gesture selling point arrives with B3/Slug transform-only
replay, when the strip/curve data survives the scale change and
mid-gesture frames can re-render for real instead of scaling a raster.

## What C2 (Slug transform-only zoom) needs from the scene API

1. **A device-agnostic replay seam.** `replayStrips` hardcodes
   `StripPdfDevice`; a third target (Slug device) would copy-paste the
   canvas-setup + replay + finish scaffolding. Generalize to something
   like `replayInto(PdfDevice Function(ui.Canvas, PdfMatrix pageToDevice)
   factory, {pixelRatio})` when C2 lands — the scene owns canvas setup,
   image map, and command replay; the device is a parameter.
2. **Scene-lifetime caches for scale-independent artifacts.** C2's
   premise is zoom = uniform update, no re-bin: curve-in-texture band
   lists must be built ONCE per scene and reused across zoom steps.
   Today every `replayStrips` rebuilds everything (correct for C1's
   re-bin model, wrong for Slug). The scene should carry an opaque
   per-device cache slot (e.g. `Expando<Object>` keyed on the scene, or
   an explicit `Map<Type, Object> deviceCache`) whose entries die with
   `dispose()` — Slug's curve textures are `ui.Image`s and need the
   same owned-lifetime treatment as `_images`.
3. Already in place and worth preserving: stable command identity (the
   final immutable `commands` list is a valid cache key), scene-owned
   decoded images shared by every replay target, glyph outlines
   retained in em space inside `PdfTextRun` commands (Slug wants
   em-space curves — no extra API needed), and `replayRegion` semantics
   that a Slug device should also honor for the deep-zoom patch
   (region variants exist only for flat replay today).

## Files

- `packages/dart_pdf_editor/lib/src/strips/strip_scene.dart` (strips
  mode), `lib/strips.dart` (merged barrel), `lib/src/renderer.dart`
  (`pageToDeviceMatrix` public), `test/zoom_latency_test.dart` (path d
  + telemetry), `test/strip_scene_test.dart` (strip smoke),
  `example/lib/strip_zoom_demo.dart` (toggle).
