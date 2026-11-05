# One coordinator for the viewer's background render work (#1202)

`_PdfViewerState` ran six background lanes, each with its own attempt sets,
generations, timers and running flags, and it answered "is the viewer idle?"
three slightly different ways. `PdfBackgroundWork`
(`lib/src/background_work.dart`) now owns all of that. The viewer creates one
per state (`_work`).

## Shape

- **Facts** come from `PdfBackgroundHost`. The viewer implements it as
  `_PdfViewerBackgroundHost` at the end of `pdf_viewer.dart`, which reads the
  live viewer state: direct gesture, scroll and zoom settle windows, deep
  zoom, armed tool, active, policies, page list and layout.
- **Idle answers** are written once, on the coordinator: `directMotion`
  (host gesture or the coordinator's own 250 ms release window),
  `motionHold`, `previewUiMustDefer`, `rasterWarmIdle`, `textWarmIdle` and
  `commandWarmUiIdle`.
- **Scheduler flags** (`holding`, `activeGesture`, `slowMotion`, `parked`,
  `focus`) are only written through the coordinator, via
  `PdfBackgroundScheduler`, which `PdfPageRenderScheduler` implements. The
  viewer calls `beginMotion`, `endMotionSoon`, `settle`, `settleAfterBuild`,
  `markScrollGesture`, `slowScroll`, `holdForScroll` and `scrollSettled`.
- **Lanes.** The raster warm and slow-scroll look-ahead loops live in the
  coordinator, as do every lane's page pickers (`nextRasterWarmPage`,
  `nextSlowScrollWarmPage`, `nextPreviewPage`, `planCommandWarm`). The host
  renders a page with `warmFullRaster`. The preview pass, command warm and
  text warm bodies stay in the viewer because they are rendering. They ask
  the coordinator which page is next, record their attempts on it, and the
  coordinator decides when they start.
- **Events**: `invalidate(PdfPageSetChange)` (#1201's result),
  `rasterCachePolicyChanged(raised:)`, `rasterWarmPolicyChanged`,
  `previewPolicyChanged`, `previewLodPolicyChanged`, `tileBackendChanged`,
  `activeChanged`, `memoryPressure`, `schedulerActivity`,
  `performanceChanged`.

## Pricing rule

The coordinator never prices a page. `host.rasterWarmTarget(i)` is the
viewer's `_rasterWarmTarget`, which is `PdfPageRasterGeometry`. The on-screen
page runs the same arithmetic. The slow-scroll byte window sums those same
signatures.

## Tests

`test/background_work_test.dart` uses a fake host and a fake scheduler under
`fakeAsync`. It covers the idle clauses, nearest-first ordering, preempting a
scroll and retrying, re-arming on a page-colour invalidation, an incremental
edit re-arming only its page, park/unpark, slow-scroll direction and
capacity, the motion-hold release window, gesture quiet, the text warm, and
the tile warm-up. `raster_warm_test.dart` keeps its widget smoke tests for the
real preview cache and the policy wiring; the nearby-window, scroll-preempt
and disabled-policy polling tests moved to the unit file.

