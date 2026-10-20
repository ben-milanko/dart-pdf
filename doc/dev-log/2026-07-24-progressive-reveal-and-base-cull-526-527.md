# 2026-07-24 — #526 closed on measurement, #527 landed as a prefix paint

Second half of the #520 deep-tier session (the first half, #525 JPX
`cp_reduce`, is in `2026-07-24-jpx-cp-reduce-525.md`). Two outcomes: **#526
measured as a regression and closed**, **#527 landed** as PR #565 — and the
faithful version of #527 split out as **#564**.

## #526 — base-raster viewport cull: measured, not landed

The ticket wanted the region-index/grid machinery (which today drives only the
deep-zoom *detail* patch) to also cull the **base** raster. Measured before
building, using the existing grid via `PdfRetainedScene.rasterizeRegion` with
`spatialRegionReplayMaxCommands = 0`, on a 120k-command synthetic CAD
transcript, two page shapes, median of 3:

| visible | wide-strip gathered → ratio | A1-portrait gathered → ratio |
|---|---|---|
| **100%** (the `PdfViewerFit.page` default) | 100.0% → **1.228x** | 100.0% → **1.092x** |
| 75% | 77.9% → 0.951x | 90.1% → 0.916x |
| 50% | 52.2% → 0.621x | 62.7% → 0.612x |
| 25% | 26.5% → 0.304x | 34.1% → 0.357x |
| 12.5% | 13.7% → 0.143x | 19.9% → 0.204x |

Full base raster: 1463 ms (wide) / 1574 ms (portrait).

Three reasons it doesn't land:

1. **The default view is a 9–23% regression.** `initialFit` defaults to
   `PdfViewerFit.page` — the whole page is visible, so there is nothing to cull
   and you pay the index build for nothing. The ticket's premise ("even when the
   initial view shows the whole page downscaled") is inverted.
2. **Break-even is ~75% visible**, and the portrait shape gathers *more* than
   its visible fraction (75% visible → 90% gathered) because a band on a
   normal-aspect page intersects more spatially-spread commands. The cull is
   least efficient on the common page shape.
3. **The win regime is load-bearing.** Wins only appear below ~50% visible —
   zoomed in, where the base raster exists precisely to be the pannable
   whole-page underlay (`_replayOnto` with `rasterRegion == null`; the cached
   image transform-scales during pan with no re-render). Culling there
   reintroduces the janky pan `cad_wide_region_replay_test` guards, and the
   detail path already culls that same region.

Gating on command count (as the ticket proposed) avoids (1) but just narrows
engagement to (3). Consistent with #520's meta-finding: PDFium's progressive
machinery compensates for a single-threaded model; we already have the stronger
mechanisms, so the technique doesn't transfer.

## #527 — progressive reveal: the filed approach was wrong; `commandLimit` was right

Two corrections found while scoping:

- **Strips are the wrong seam.** `StripPlan.totalFlushPoints` "must equal the
  consuming device's own count for the plan to be valid" — a partial plan is
  invalid *by construction*, and `StripPlanBinner` does one `bin()` → one
  `finish()` → one buffer. Making strips incremental is a bigger change than
  the record path.
- **`commandLimit` is the right seam, and the ticket never mentions it.** It is
  already on every `record()` override, and the worker maps it to the parse
  cursor's `operationLimit`, so a bounded record genuinely stops early.
  `PdfCachingRenderWorker` already keys its cache on it, and a truncated prefix
  is replay-safe because `serializeCommands` takes the prefix *before* q/Q
  compaction. It was already used this way — but only by the low-res preview
  cache, never by `PdfPageView` itself. That was the actual gap.

Also worth recording: the gap was narrower than the ticket claims.
`_paintVectorFirst` and `_updateDetail` already give a two-stage progressive
render; what stayed blank-until-complete was specifically a **dense vector**
page, where the vector-first record still walks the whole transcript.

### What landed (PR #565)

`_paintEarlyPrefix` issues a bounded record before the full one and rasterizes
it into the existing `_preview` slot (view-owned, already cleared when `_image`
arrives; `_vectorFirstRatio()` is already capped by `_previewMaxPixels`, so a
big sheet can't turn it into an expensive fill). Every await is followed by a
`_superseded` / `_image != null` guard so a full pass that overtakes the prefix
is never downgraded.

Measured first ink (synthetic CAD strip, uncached worker):

| fixture | full record | prefix (limit 20000) | first ink |
|---|---|---|---|
| 120k ops (2.1 MB raw) | 420 ms | **57 ms** (4501 cmds) | **7.4× sooner** |
| 400k ops (6.9 MB raw) | 923 ms | **97 ms** (4501 cmds) | **9.5× sooner** |

The prefix costs ~10% of the full walk, so the complete page lands ~10% later —
the expected progressive-rendering trade.

**Gotcha:** `commandLimit` bounds *operations*, not commands (20000 ops → 4501
commands). That also kills the tempting optimisation of "if the prefix came
back shorter than the limit it must be the whole page, so skip the full
record" — a page with many non-drawing ops would be silently truncated
forever. Hence the gate is `PdfPage.rawContentLength` (an O(streams), decode-free
size proxy) rather than any post-hoc truncation check.

### Caveat, and #564

What landed is a **painter-order prefix**, not PDFium's spatial top-down band.
On a sheet authored in region order it reads naturally; authored by layer, it's
a partial drawing. The faithful version needs one job emitting partials as it
walks, which the worker protocol cannot express: `_inFlight` is cleared by the
first id-matching message and `_PendingRequest`'s `Completer` fires once — and
`PdfCachingRenderWorker`'s shared-future dedup depends on exactly that. Filed as
**#564** (6 files, 2 packages, twin-implemented native+web, bundle rebuild),
to be built with **#530**, which needs the same resumable-cursor primitive.

## Study status

9 landed, 3 closed after measuring (#521, #523, **#526**), 2 report-only (#528,
#529), 2 open (#530, #564). The three measured-and-closed are the study working
as intended: each looked plausible on paper and lost to a number.
