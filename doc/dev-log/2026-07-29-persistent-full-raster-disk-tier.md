# Persistent full-resolution raster disk tier (#615)

`PdfRasterCache` already persisted two small things through the pluggable
`PdfCacheStore` seam: low-resolution page previews and size-bucketed
thumbnails. Both are tens of KB of PNG per page, which is what makes a cold
reopen paint navigable content instead of blank paper.

Exact full-resolution page rasters were memory-only. `PdfPageRasterCachePolicy`
lets a desktop host retain a large visited-page working set in RAM, but every
byte of that work died with the process, and a host whose RAM budget is smaller
than the document's useful working set had no overflow path at all.

This adds an **optional** persistent tier for exact rasters. Host opt-in, no
package-owned filesystem dependency, and structurally unable to evict the small
tier that navigation depends on.

## Shape

```dart
PdfRasterCache(
  PdfDiskCache(store, namespace: 'previews'),          // unchanged
  fullRasters: PdfDiskCache(store,                     // new, opt-in
      namespace: 'page-rasters', maxBytes: 256 << 20),
)
```

`fullRasters` is a **separate `PdfDiskCache`**, not a namespace inside the
existing one. That is the whole answer to "the full-raster tier cannot evict
the small preview/thumbnail tier": `PdfDiskCache` owns its own manifest, its
own LRU order, and its own `maxBytes`, so the two budgets never see each other.
A shared budget would have let a handful of page images - three orders of
magnitude larger than a preview - flush the entire preview and thumbnail set on
the first document a user scrolls through.

Null (the default) leaves everything exactly as it was.

## Key

`PdfRasterCache.fullRasterKey` covers every input that changes the baked
pixels:

    <documentKey>/f<fullRasterVersion>/<revision>/<page>/<w>x<h>/<argb>/<annots>/r<rot>

- **document identity** - `documentKey`, the host's stable id or `pdfContentKey`
- **renderer/format generation** - `PdfRasterCache.fullRasterVersion`, in the
  key rather than only in the manifest, so a bump is a miss that ages out
  rather than a payload read by code that would interpret it differently
- **page index + content revision** - the page view passes
  `pageEpoch.contentStamp.destructiveStamp`, the same identity the render
  session uses to decide what a completed raster is still valid for
- **physical raster width and height** - a zoom level is a different entry
- **rotation**, **paper colour**, **annotation visibility**

The viewer's `_rasterKey()` already folds paper colour, annotation visibility
and view rotation into `documentKey`; keying them again at the entry level
costs nothing and makes `PdfRasterCache` correct for hosts that call it
directly.

### Stale content

The tier hangs off `_bindRasterCache`, which **unbinds for an editing
session** - the same gate the preview tier and the text cache already use.
Insert/remove/reorder shift the index a stored raster was keyed by, and a
redaction burn removes content the stored pixels still show; neither can be
made safe by an index-keyed cache, so an edit session neither reads nor writes
exact rasters. The revision component of the key is the second line of defence
for hosts that drive `PdfPagePreviewCache` themselves.

## Container

Payloads carry a 20-byte header (`PRAS` magic, container version, format,
width, height, payload length) ahead of the encoded bytes. The key already
pins the dimensions, so the header is redundant on the happy path - it exists
so that a truncated write, a store that hands back another entry's bytes, or a
key collision is a **miss** rather than a page drawn at the wrong size. Every
failure mode (corrupt payload, absent entry, quota wall, throwing backend)
returns null and the page renders exactly as it did before the cache existed.

## Encoding

`PdfRasterDiskFormat` is a real choice, not a formality.
`test/benchmark_full_raster_disk_test.dart`, 1200x1600 (1.9 MP, 7500 KB raw),
`flutter_tester` with software rendering on this machine - treat the absolute
milliseconds as indicative and the ratios as the finding:

| page kind | format | encode | decode | stored | vs raw |
| --- | --- | --- | --- | --- | --- |
| vector/CAD | png | 282 ms | 30 ms | 646 KB | 9% |
| vector/CAD | rawRgba | 116 ms | 46 ms | 7500 KB | 100% |
| form | png | 88 ms | 17 ms | 19 KB | 0.3% |
| form | rawRgba | 66 ms | 3 ms | 7500 KB | 100% |
| photo/scan | png | 354 ms | 134 ms | 6517 KB | 87% |
| photo/scan | rawRgba | 134 ms | 3 ms | 7500 KB | 100% |

So the issue's warning is confirmed: **PNG is not always a win.** On a scan
page it costs 2.6x the encode and 50x the decode of raw and still stores 87% of
raw - strictly worse on every axis. On vector and form pages it is 11x and 400x
smaller, which is what decides how much of a document survives a fixed byte
budget.

`png` is the default because the **byte budget**, not the CPU, is what usually
bounds how many pages survive to the next session, and the encode is off the
critical path by construction (queued, preemptible, fire-and-forget) while the
byte budget is not. A scan-heavy corpus should set
`fullRasterFormat: PdfRasterDiskFormat.rawRgba` and size the budget for it -
raw's decode is a straight buffer upload via `ui.ImageDescriptor.raw`.

Re-run the benchmark on each platform before changing the default: the encode,
the decode, and the store are all platform work (GPU readback on desktop/
mobile, a canvas readback plus IndexedDB on web), so the crossover moves. The
env-gated half of the same file (`PDF_BENCHMARK_PDF=...`) puts a real
document's fresh-render cost next to its disk-restore cost on the same machine,
which is the number that says whether the tier is worth enabling at all.

## Scheduling

- **Stores are asynchronous and preemptible.** `putFullImage` queues a *clone*
  of the raster (cheap - it shares the engine image) and returns; a serial
  drain does the readback, the encode, and the store. While
  `PdfPagePreviewCache.deferBackgroundIo` returns true - the viewer wires it to
  `_motionRenderHoldActive`, i.e. a scroll in flight - the drain waits. The
  queue is capped at two pending writes and a write still contended after ~3s
  is dropped rather than allowed to pin page-sized images or steal the raster
  thread from the page the user is looking at. The page re-queues when the view
  settles.
- **Loads are not deferred.** A disk read *is* the foreground first paint it
  exists to serve.
- `_render()` tries memory first (`_restoreFullRaster`, synchronous), then the
  persistent tier, then schedules the interpret+rasterize it was going to do.
  The disk attempt is gated on the page having nothing to paint and on the tier
  actually being wired, so nothing changes for hosts that did not opt in. A
  miss costs an in-memory manifest lookup: `PdfDiskCache.read` answers from
  `_sizes` without touching the backend.
- The async lookup takes a generation token via the new
  `PdfPageRenderSession.fullGeneration` **without** claiming it, so losing the
  race to a real render drops the decoded image instead of invalidating work
  that was about to land.

## Memory policy

A disk hit is admitted through `PdfPageRasterCachePolicy` on the way past, and
the admission can decline (entry too large, budget exhausted) while the image
is still returned to the caller. So an oversize raster serves the page in front
of the user without displacing the memory working set - which is the point of
having the disk tier be the overflow path rather than a second copy of the same
policy.

## Diagnostics

- `PdfRasterCache.fullRasterStats` (`PdfRasterCacheStats`, shared across
  `forDocument` views): hits, misses, stores, rejects, errors, bytes read/
  written, and total encode/decode microseconds with per-operation means.
- `PdfDiskCache` gained plain counters - hits, misses, writes,
  `oversizeRejections`, `evictions`, bytes read/written/evicted - plus
  `debugStats` and `resetStats()`. Cheap enough to leave on; the oversize
  counter is how you tell "the budget is too small for this document" from
  "the cache is thrashing".
- `PdfPerfLog` gains `full-raster disk hit page=N WxH`.

## Gotchas

- `PdfDiskCache` skips an entry larger than the whole budget rather than
  force-evicting everything and still not fitting. With the raster tier that
  case is reachable in practice (one large-format page at high zoom), so it is
  now counted (`oversizeRejections`) and covered by a test that asserts the
  entry that *does* fit survives.
- The write-through happens **before** the memory admission in `putFullImage`,
  deliberately: a raster the RAM policy rejects is exactly the one most worth
  keeping for the next session.
- `loadFullFromDisk` calls the private `_admitFullImage`, not `putFullImage`,
  so a restore does not immediately write itself back to the store it just came
  from.
- Physical size is in the key, so one page zoomed through several levels
  occupies several entries. That is correct (each is a different raster) and
  the LRU absorbs it, but it means the useful budget for a document is "pages x
  distinct zoom levels visited", not "pages". Size accordingly; `evictions`
  climbing with a flat `hits` is the signal that the budget is too small.
- `PdfDiskCache` serializes work behind a `Future` created at construction, and
  a `Future`'s continuations are scheduled in the zone that `Future` was
  created in. A cache built in a widget test's (fake-async) body therefore
  never progresses inside `tester.runAsync` - it deadlocks rather than fails.
  Tests that `await` disk operations build their caches inside the runAsync
  block; the viewer-level tests are fine because every store is
  fire-and-forget and `pump()` drains the fake microtask queue.
