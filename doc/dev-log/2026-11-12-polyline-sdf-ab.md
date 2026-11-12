# 2026-11-12 - Straight-polyline submission A/B (#1270)

Flutter 3.50's Impeller draws lines, rects and rrects analytically (UberSDF)
on desktop instead of tessellating them. Plan/CAD sheets are almost all thin
straight strokes, so #1270 asks whether handing those to the engine as line
segments beats a stroked `drawPath`.

## What the corpus says

A pass over the corpus (`RecordingPdfDevice`, 115,509 strokes):

| Shape | Share |
| --- | --- |
| Short straight, <=4 segments | 35.4% |
| Straight polyline, >4 segments | 28.5% |
| Multi-subpath straight | 18.8% |
| Single line (already `drawLine`, `debugDrawSimpleLines`) | 17.0% |
| Curves / dashed | 0.2% |

So about 83% of strokes are straight multi-segment paths that still go through
`drawPath`. `plan-set-16p` has ~3,050 such strokes a page (segments p50=5,
max 11, widths 0.3-1.0 pt, butt caps + miter joins, all opaque);
`diagram-dense-3p` has the same shape at ~10.7k a page.

DisplayList already records rect-shaped paths as `DrawRect` (25 B/op vs 33 B
for a generic path, from `approximateBytesUsed`), so rects are not the lever;
polylines are.

## The switch

`CanvasPdfDevice.debugStraightPolylines` (`PdfPolylineSubmission`, default
`path` = unchanged behaviour):

- `lines`: one `drawLine` per segment;
- `rawPoints`: one `drawRawPoints(PointMode.lines, ...)` per stroke.

Only eligible strokes are split: no curves, >2 segments, opaque, width <=
`debugStraightPolylineMaxWidth` (1 pt), undashed, srcOver blend. A split drops
miter joins (each segment gets its own cap), which is the visual cost being
measured; at <=1 pt the join is sub-pixel at normal zoom but shows at deep
zoom. `closePath` contributes its closing segment.
`test/canvas_polyline_submission_test.dart` pins the eligibility rules.

## The A/B

`example/patrol_test/polyline_ab_perf_test.dart`, run by the macOS Patrol job
(Metal). Fixture: `buildSyntheticPlanPolylines()` in pdf_test_fixtures - one
A3 sheet of 3,000 strokes generated to the plan-set shape above, deterministic
(LCG, seeded). One recording, then a warm-up plus 8 repetitions rotating the
three modes so none always runs first; per mode it logs p50 picture record
time, p50 raster time (`rasterizeViaLayer` at 2x), picture bytes, and the
mean/visible pixel diff vs `path` at 2x and at 8x zoom on a 300x200 pt
window. The `[polyline-ab]` lines land in the job summary. It is diagnostic:
only a "drew the same sheet" sanity bound can fail.

Decision rule: flip the default only for a clear raster win with visible-pixel
diffs that stay negligible at 2x. Results are recorded on #1270.
