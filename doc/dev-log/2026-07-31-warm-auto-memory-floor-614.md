# Auto memory reserves a floor for the idle raster warm (#614 follow-up)

A field trace from the real web app (build `522c1f7`, the #614 branch) showed
the idle full-raster warm doing nothing. Two separate findings came out of it,
and only the second was a defect.

## 1. Silence is what "off" looks like

Zero `raster-warm` lines in 45 s of trace. The warm logs `raster-warm page=` on
every completion and `raster-warm decline page=` on every refusal, so silence
means the loop never started - which is exactly right, because
`PdfPageRasterWarmPolicy.disabled()` is the default and `_scheduleRasterWarm`
returns before arming its timer when the policy is disabled.

Worth knowing for the next person reading a trace: the `prerender page=N worker
full warm=1500.9ms` lines are the *low-resolution preview* prerender
(`preview_cache.dart`), which has always run. Same word, different feature.

## 2. Auto walked the page-raster budget to zero

```
20:09:08  131MB total, 16MB/page
20:09:10  112MB / 14MB
20:09:23   48MB /  8MB   trimmedEntries=1, trimmedBytes=9996880
20:09:38   31MB /  8MB
20:09:53    0MB /  0MB
20:09:56  page-raster reject page=3 bytes=9996880 reason=disabled
```

With `maxEntryBytes: 0` every page fails `admitsFullRaster`, so an enabled warm
would have declined all of them - a no-op that still logs a decline per page.

The arithmetic (`computeAdaptiveMemoryDecision`, web, `physical` 4 GiB so
`safeProcessLimit` = 409.6 MB, reserve 163.84 MB): `nonCacheRss = rss -
reclaimable` climbs as the document loads because the registry only accounts
for registered LRUs, not worker heaps or transferred buffers. Envelope falls
under the **32 MB live-raster floor**, `allocatableRegistry` floors at 0, and
the page budget with it. Pre-existing behaviour from #628, but it makes warming
inert in the app's default web configuration.

### The fix

`computeAdaptiveMemoryDecision` gains `warmPageRasterFloorBytes` (0 unless a
warm policy is active; `pdfWarmPageRasterFloorBytes` is 192/96/64 MB for
desktop/web/mobile). When the live floor has taken the envelope, the page cache
claims a floor **out of the live budget**, down to a new
`_liveRasterWarmFloor` of 16 MB - reachable only when warming was explicitly
asked for. The focused page is exempt from the live budget, so this trades
neighbour-page responsiveness, never the page being looked at.

Two things this deliberately does *not* do:

- **It does not guarantee warming works.** When the envelope has genuinely
  collapsed there is nothing to claim and the floor yields to 0 rather than
  overcommitting the safe process target. Pinned by "a genuinely collapsed
  envelope still yields to zero".
- **It does not touch the no-warm path.** Pinned by "without a warm policy the
  squeezed budget is unchanged".

### Two traps found while building it

**The entry limit is the real gate, not the total.** The derived limit is
`pageBytes ~/ 8` with an 8 MB floor off-desktop, so any budget under 64 MB
admits nothing larger than 8 MB - and a letter page at DPR 2 is ~10 MB.
Raising the total alone buys literally nothing. Hence
`pdfWarmPageRasterEntryFloorBytes` (24 MB).

**The growth damper discarded the floor.** `applySnapshot` rate-limits growth
and re-derives the entry limit from the clamped total via `_entryLimitFor`,
which knows nothing about warming. The first version of this change produced a
budget with room for three pages that admitted none of them; the controller
test caught it. `_warmAwareEntryLimit` re-applies the floor after clamping.
The controller also listens to `tools.pageRasterWarmPolicy` and clears
`_lastGrowth`, so flipping the selector re-prices on the next sample instead of
waiting out a 45 s growth interval.

## 3. Viewer churn (also from the trace)

`didUpdateWidget` cleared `_rasterWarmAttempts` on *any* cache-policy change,
commented "a raised budget may admit pages the warm previously declined". Auto
re-prices every ~15 s, usually downward, so with warming on that re-offered and
re-declined the whole document on every tick. Now only a strictly larger
`maxBytes` or `maxEntryBytes` clears the attempt set.

## Verification boundary

The floor is verified by unit tests against the field snapshot (4 GiB machine,
276 MB RSS, 60 MB registry - reproducing the exact zero), not by a live browser
run: the perf harness sets a fixed `pageRasterCachePolicy` from
`?warmBudgetMb` and bypasses the app's Auto controller entirely. The
`warm-plan-*` / `warm-scan-*` scenario numbers in
`2026-07-29-idle-full-raster-warm-614.md` are unaffected for the same reason.
Counter gate unchanged: 12 inputs, 13 counters within 3%.
