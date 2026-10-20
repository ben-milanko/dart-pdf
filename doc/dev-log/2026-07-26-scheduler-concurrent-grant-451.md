# 2026-07-26 — #451: the scheduler could grant one page two concurrent renders

Item 3 of the [#601 write-up](2026-07-25-record-glyph-outline-dedup-451.md)
listed two untracked scheduler problems the device trace exposed. This is
the second one — "every focus page is granted exactly twice" — chased to a
mechanism, fixed, and pinned. **The fix is correct and exercised, but no
local scenario shows a measurable win.** That caveat is the point of this
note.

## The race

`PdfPageRenderScheduler.request` documents "the page is interpreted at most
once", and deduplicates by token. But it only compares against `_pending`,
and `_drain` *removes* the request before invoking it:

```dart
final next = _pending.removeAt(pick);
next.render();                       // returns at its first await
await SchedulerBinding.instance.endOfFrame;
```

`render` was typed `VoidCallback`, and Dart happily coerces the
`Future<void> Function()` both call sites pass — so the future was dropped
on the floor. On the worker path the callback returns in microseconds and
the recording lands hundreds of milliseconds later. A rebuild inside that
window finds an empty `_pending`, enqueues, and the next `endOfFrame`
grants the same page a **second concurrent pass**.

Both passes record the page in full. `_renderNow` opens with
`_renderSession.beginFull()`, so the newer pass bumps the generation and the
older one's result is discarded by its own `_superseded` guard when it
lands — a complete wasted record. `pdf_page_view.dart:1725` already
described the interleaving as a known hazard and defended the *state*
against it; nothing stopped the duplicate work itself.

The device trace's smallest same-page gap was 3 ms, which is exactly one
`endOfFrame` when a frame is already in flight.

## The fix

The scheduler now tracks the in-flight window: `request` for a token whose
render has not settled stores the re-request instead of queueing it, and
`_settle` (hung off the returned future, with `onError` so an async throw
cannot wedge a page out of the queue) grants it once the running pass
finishes. `cancel` drops a queued re-request so a recycled page is not
granted again when its abandoned render lands.

The re-request is **held, not dropped** — the rebuild that asked may carry a
new scale or revision. By the time it runs the page has its picture, so it
takes `_renderNow`'s `cached != null` branch and re-rasters rather than
recording from scratch.

Frame pacing is deliberately unchanged: `_drain` still awaits only
`endOfFrame`, never the render. Awaiting renders would serialize every page
behind the slowest worker round trip and defeat the point of three workers.
A test pins that (`an in-flight render does not block other pages`).

`VoidCallback` → `FutureOr<void> Function()`. Both call sites already passed
async functions.

## Measurement — and why it shows nothing

Interleaved web A/B, `scroll-scan` (the image/cache-heaviest scenario),
3 iterations vs the pre-fix commit: every metric inside noise, and the
grant log is **byte-identical modulo a startup offset** — 42 grants, 4 per
page, `worker=31 recorded=0` on both sides. (`jankCount` 1 → 2 tripped the
gate; it is a count of log lines, and the run before it went the other way.)

So the fix is a no-op there. To find out whether the race fires at all, the
coalesce now logs `scheduler defer page=N (render in flight)`. Across seven
scenarios:

| scenario | grants | defers |
|---|---|---|
| scroll-scan | 42 | 10 |
| scroll-plan | 25 | 5 |
| scroll-diagram | 6 | 0 |
| scroll-cad-labels | 8 | 0 |
| scroll-hatch | 8 | 0 |
| open-diagram-progressive | 2 | 0 |
| edit-annotate | 1 | 0 |

It fires — but reading the interleaving shows what it catches locally is
benign:

```
[perf 2359] scheduler grant page=2
[perf 2651] webworker result kind=record page=2 5589896B → worker
[perf 2651] scheduler defer page=2 (render in flight)
[perf 2857] scheduler grant page=2
[perf 2859] interpret page=2 path=worker FIRST interpret=1.5ms wait=0.0ms
```

The re-request arrives *as the record lands*, and the deferred grant replays
the record it already has in 1.5 ms. One record, not two. Serializing it
costs nothing and saves nothing — which is why `worker=` does not move.

The wasteful shape is in the device trace and not reproduced locally:

```
page=28  worker=1895ms  ser=1608ms
page=28  worker=1723ms  ser=1505ms   <- same page, again
```

Two full 1.5 s records for one page. Local records are ~450 ms against a
12-page corpus; the device ran a 62-page book on three workers with records
an order of magnitude slower, which is what widens the in-flight window
enough for a second *recording* pass to start. **Confirming the win needs a
device trace on this build** — count `scheduler defer` lines and check
whether any page still produces two large records.

## Adjacent, not chased

The same log shows page 1's 41277 B vector-only record produced at
`[perf 169]` and again at `[perf 2924]` — an identical re-record the record
cache should have served. Different problem, not scoped here.

Item 3's *first* half also stands: `_drain`'s one-per-frame pacing is
nominal on the worker path, since the grant returns before the expensive
work. Fixing that means awaiting renders, which as above is the wrong
trade; the real serialization now needed is per-token, which is what this
change adds.

Tests: four new, each confirmed to fail against the specific mutation it
targets (dedup removed, `cancel` leaving the re-request, `onError` dropped,
`_settle` discarding instead of granting). dart_pdf_editor 1982, analyzer
clean.
