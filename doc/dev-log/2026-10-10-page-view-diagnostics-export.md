# Per-page render state in the devtools export

A field report ("the top-left of a deep-zoom CAD page never sharpens") came
with a devtools export that could not say *why*: the tile store was idle
(`inFlight: 0`, `scheduled == landed`), but nothing recorded what the page view
itself was doing - whether it still owed an exact patch, which route
`_updateDetail` last took, or which visible tiles were missing. The blur was an
L-shaped band along the top and left edges whose inner corner did not sit on
the 90.5 pt tile grid, which points at a stale, offset detail patch with no
tile layer covering the gap - but several states produce that picture and a
synthetic reproduction (worker, DPR 2, the reporter's geometry and 96 MB
budget, random pan/zoom settles) stayed sharp every time.

## What landed

- `PdfPageViewDiagnostics` (`debug_overlays.dart`): a pull-based registry.
  Each `_PdfPageViewState` registers a snapshot closure in `initState` and
  drops it in `dispose`; nothing is computed until an export asks.
- `_PdfPageViewState._diagnosticsSnapshot`: widget inputs (onScreen,
  qualityVisible, scale, settleGeneration, render hold, scheduler busy/parked),
  base raster/picture state, scene (vector-only, image veto), detail patch
  (fraction, ratio, `awaitingExactPaint`) and tile route (`pathStatus`,
  whether the layer is mounted, fraction, pan-ahead, image-detail gate).
- `_noteDetail(outcome)` tags every exit of `_updateDetail`: `tiles`,
  `reuse`, `index-warming`, `adopted-*`, `worker-declined`, `render-hold`,
  `paused`, and `superseded` with the failing `_acceptsForegroundDetail`
  condition (`_detailRejection`). `requested` is written when a generation is
  claimed, so a request that never resolves stays visible as `requested`.
- `PdfTileStore.debugExactCoverage`: visible exact-rung cells retained /
  in flight / missing, as a pure peek (no LRU touch, no scheduling). The page
  reports it both over its stored `_tileFraction` and over where the page is
  on screen *now*, and evaluates the tile veto on each missing cell
  (`missingVetoed`) - so a stale fraction, a stuck veto, and a missing tile
  layer read differently.
- The app's export gains `pageViews`.

## Reading a "never sharpens" export

- `tiles.layerMounted: false` with `detail.awaitingExactPaint: true` and a
  `lastOutcome` of `requested`/`superseded` - the exact-first obligation never
  discharged; the tiles are hidden behind it.
- `layerMounted: true`, `coverage.tileFraction.missing == 0` but
  `coverage.liveViewport.missing > 0` - `_tileFraction` is stale (no refresh
  after the last pan).
- `missingVetoed > 0` with `scene.vectorOnly` or `tiles.imageDetailWanted` -
  a tile veto that never lifted.

Test: `test/page_view_diagnostics_test.dart`.
