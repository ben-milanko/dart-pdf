# Sub-pixel strokes grow with the zoom (0.25-1 recorded px band)

Report: on a Metro Trains CAD layout (LIL-L4209, A3, Adobe-exported), the
red power-conduit runs read as a thick band zoomed out but collapsed into a
faint thread zoomed in. Each run is 3 or 7 parallel **0.72 pt** strokes,
~0.6 pt apart - a ~4.5 pt band in Poppler at any zoom. (The blue comms runs
are true `0 w` hairlines; their "bold when zoomed out" look is correct -
seven one-pixel lines closer than a pixel merge.)

## Cause

`CanvasPdfDevice.strokeWidthFor` floors a stroke at one device pixel by
replacing it with Skia's zero-width hairline when `width * pixelRatio < 1`.
Every page picture is recorded at `pixelRatio` 1 (renderer's three
`renderPicture` variants, the retained scene's `_replayOnto`, the strip
fallback) and replayed at the viewer's zoom through the canvas transform, so
the test really read "under 1 pt": any sub-point stroke stayed one pixel wide
at every zoom. The canvas2d mirror (`pdfCanvas2dStrokeWidth`) copied the same
page-unit test (`width < 1`). The strip rasterizer was already right - it
floors in device space against its real `pageToDevice`.

## Fix

- `CanvasPdfDevice.strokePath`: a stroke in the band
  `thinStrokeTrueWidthMin` (0.25) <= `width * pixelRatio` < 1, opaque, with
  an idempotent blend (srcOver/src/darken), keeps its **true width** and gets
  a hairline drawn down the same path (`_thinStrokeOverlay`,
  `_strokeHairlinePaint`) - the `_floorThinRectFill` trick: the hairline is
  the floor where the stroke is sub-pixel and lies inside it otherwise, so
  one scale-free picture is right at every replay ratio. Below the band, and
  for translucent / non-idempotent paint, it is the plain hairline as before.
- `pdfCanvas2dStrokeWidth`: `width < hairlineWidth ? hairlineWidth : width`
  (the web surface knows its device pixel, so it floors exactly - free).
- 22 Ghent baselines re-accepted: sub-1 pt lines at the 2x baseline scale now
  draw at true width. Checked against Poppler at the same raster size
  (GWG030's 0.8 pt frame: Poppler 2 px solid; before 1 px grey; after ~2 px
  dark). GWG1610/1611's "lighter" pixels are white separator strokes widening.

## Dead ends (measured, don't retry)

- **Deciding the width at raster time** (`fixedScale` device for
  `PdfRetainedScene.rasterize`/`rasterizeRegion`, single exact draw): breaks
  retained_scene_test's byte-equality between `scene.rasterize` and
  `rasterizeViaLayer(scene.replay(pixelRatio: 1))`, which the viewer's first
  base raster relies on - and the scale-free picture is the hot path anyway.
- **Batching consecutive hairline overlays into one path** per paint: no
  gain (within noise or worse); the cost is raster, not draw-call overhead.

## Cost (headless `benchmark_render_test`, scale 2, best of 2-4 runs)

| file | before | overlay on all sub-px | band (shipped) |
|---|---|---|---|
| LIL-L4209 p91 | 163 ms | +39% | +21% |
| cad-sheet-8p | 1508 | +38% | +31% |
| cad-labels-6p | 278 | +9% | +1% |
| plan-set-16p | 3228 | +54% | +51% |
| diagram-dense-3p | 3327 | +71% | +70% |
| hatch-sections-4p | 1435 | +40% | +29% |
| text-report-40p | 141 | +8% | +13% (noise) |

The dense fixtures are almost all 0.25-1 pt linework (diagram-dense: 10171
of 10674 strokes), i.e. exactly the strokes that mis-rendered, so the band
saves little there. Roughly half the remaining cost is drawing true widths
at all (measured "true width, no overlay": +3-28%), which the strip path
already paid. Headless numbers are software-raster; confirm on device /
web harness before tuning `thinStrokeTrueWidthMin`.

Tests: `test/thin_stroke_zoom_test.dart` (record once, replay at 1/3, 1, 4;
7-run band fuses to ~17 px at 4x; dashed; translucent; below-band hairline).
