# One shared `PdfBudgetedCache` + a coordinated memory-pressure path

Issue #307. Six-plus in-memory caches each hand-rolled the same
LinkedHashMap-as-LRU, each inventing its own budget unit and its own
take/claim clone dance, and none could cooperate under memory pressure. The
ad-hoc shape had already bred an eviction-bug *class* - the weight-0
unbounded-growth bug fixed in `2026-07-16-render-cache-entry-cap.md` is exactly
what a shared, property-tested LRU makes impossible.

## What landed

`lib/src/budgeted_cache.dart` - one `PdfBudgetedCache<K,V>` that every
in-package cache now delegates to, plus a `PdfCacheRegistry` that owns the one
memory-pressure fan-out.

`PdfBudgetedCache<K,V>` is a plain insertion-ordered map (first key = LRU) with:

- **Two independent bounds.** A weight budget (`maxWeight`, measured in the
  `weigher`'s unit) and/or an entry count (`maxEntries`). Weight eviction skips
  weight-0 entries (evicting them frees nothing yet costs a re-decode) and never
  drops the single most-recently-used entry (a lone value larger than the whole
  budget stays for the render that just asked for it, then ages out on the next
  insert). The count cap *does* see weight-0 entries - it is what bounds the
  image-free / vector-first buffers the byte budget can't see (#283).
- **`cloner`** - `take`/`putAndClone` return `cloner(value)` so a handed-out
  clone (a `ui.Image.clone`) survives its master being evicted.
- **`disposer`** - run on every dropped value (eviction, `evict`, `clear`,
  `dispose`, same-key overwrite), so engine resources free deterministically.
- **`getOrAdd`** - the compute-once counterpart used by the text-layout cache.

The invariants live once, in `test/budgeted_cache_test.dart`: never evict the
just-inserted entry; a handed-out clone survives master eviction; weight-0
entries stay bounded by the count cap; the disposer fires on every drop.

`put` returns the value un-cloned (the caller handed it off); `putAndClone`
returns an independent clone for callers that populate *and* paint in one step
(the decoded-image cache, the exact-raster cache). Splitting these two was the
one real subtlety - a single clone-returning `put` leaks a clone at every call
site that ignores the return (the thumbnail and record caches hand off
ownership and never touch the passed object again).

## The six adapters

| call site | bound(s) | clone | dispose |
|---|---|---|---|
| `PdfImageCache` (decoded XObjects) | bytes | yes | yes |
| `PdfPagePreviewCache` soft previews | count | via image | yes |
| `PdfPagePreviewCache` exact rasters | pixels | via image | yes |
| `PdfThumbnailCache` | count | yes | yes |
| `PdfCachingRenderWorker` record cache | bytes + count | no | no |
| `PdfWorkerTranscriptCache` | command-weight + count | no | no |
| `CanvasPdfDevice` text layouts | count | no | painter |

Each keeps its own domain logic on top (disk write-through and `rebind` on the
preview cache, in-flight decode dedup and the weightless region-reuse fallback
on the record cache, the viewport-ordered render queues on the thumbnail
cache, the wire-graph compaction on the transcript cache) - only the
map+LRU+weight+evict+dispose+clone mechanics moved into the shared module.

Behaviour was held byte-for-byte: the record cache still rejects a single
buffer bigger than the whole budget outright (the LRU would otherwise protect
it as MRU and starve every reusable buffer), which stays a call-site guard
before `put`, unlike the image/transcript caches that keep one oversize hot
entry. The transcript cache's `hits`/`misses`/`evictions` are now getters over
the shared counters.

## Coordinated memory pressure

Before: `PdfViewer.didHaveMemoryPressure` cleared only the decoded-image cache
and the previews; the text-layout, render-record, and thumbnail caches were
deaf to pressure.

Now: process-wide and per-worker caches register with `PdfCacheRegistry` (the
image cache's `instance`, the static text-layout cache, each
`PdfCachingRenderWorker`'s record cache) via `clearsUnderMemoryPressure: true`;
the thumbnail cache registers a clear *callback* (its clear notifies no one but
must still run). `didHaveMemoryPressure` drives
`PdfCacheRegistry.handleMemoryPressure()`, which fires them all, then clears the
previews directly (its clear also `notifyListeners`). `totalWeight` reports live
occupancy across every registered cache - the seam a future single top-level
budget would rebalance against.

The worker **transcript** cache is the one cache the pressure path can't reach:
it lives in the render isolate, unreachable from the UI thread. It stays bounded
per-worker and dies with the worker, so that is acceptable.

## Not done / future

The issue's "single memory manager owning the *total* budget, rebalancing
across caches" is only seam-deep here: `PdfCacheRegistry.totalWeight` exists,
but each cache still carries its own independently-measured budget. A real
rebalancer (one top-level number split across caches by live hit-rate) is the
obvious next step and now has one place to live.
