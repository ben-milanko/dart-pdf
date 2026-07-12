# Dense web Slug plans

Issue #227 follows the first transform-time Slug slice from #218. Ordinary
image-free pages already kept one painter-order Slug picture under the web
viewer transform, but pages above the retained-scene command ceiling could
not: building the curve atlas locally would undo the worker offload from
#224.

This slice makes the Slug plan transferable:

- `pdf_graphics` builds curve streams, atlases, and vertex arrays as pure
  typed data. The native isolate and Web Worker can now produce them.
- `StripPlan` carries Slug batches at exact strip flush ordinals, including
  explicit fallback ordinals so a successful blank glyph run is not confused
  with a minified/overflow fallback.
- `StripPdfDevice` consumes the strip and Slug portions as one painter-order
  tape. A plan is rejected if its Slug routing mode differs from the device.
- `PdfPageView` requests a ratio-1 Slug plan for an over-ceiling image-free
  page and never builds it locally. A declined plan keeps the existing
  worker-planned raster route.

The work also fixed a pre-existing async-cache trap exposed by the new
sequence test: `StripPdfDevice` cached `Future<FragmentProgram>` instances.
A future created in a widget test's dead FakeAsync zone stranded later tests.
The device now caches resolved `FragmentProgram` values and returns them from
fresh futures in the caller's current zone.

## Measurement

`slug_worker_latency_test.dart` on `corpus/WAT_L0001_S.pdf` page 0, software
Skia test backend, cold run:

- 12,021 retained commands
- 2,840 Slug glyph quads, zero outline fallbacks
- 6.12 MB encoded transferable plan
- 481.6 ms worker wall time
- 58.7 ms UI upload/replay time
- 243.5 ms equivalent local Slug build

The production gain is keeping the curve/band/atlas construction off the web
UI thread. The worker time overlaps loading and does not repeat at each zoom:
the transform-time picture is retained.

## Validation

- worker and local Slug plans encode bit-identically
- planned and local Slug rasters are raw-RGBA identical
- dense-page widget path consumes one plan and reuses one picture across zoom
- strip-plan codec, cancellation, region-detail, and stale-plan tests pass
- full `pdf_graphics` suite passes
- full `dart_pdf_editor` suite passes (1,362 tests, 25 skips with local corpus)
- web release build passes, including the skwasm dry run

Image-bearing pages remain deliberately out of this slice. They require
painter-order-preserving interleaved detail layers; a topmost text overlay is
not correct when later page content occludes text.
