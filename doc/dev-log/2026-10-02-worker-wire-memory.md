# Worker wire and memory: unboxed char offsets, a budgeted worker decode cache, records streamed to the wire

Three changes to the render-worker path, one commit each so any one can be
reverted alone. They share `render_command_codec.dart`.

## 1. Unboxed per-character offsets

Since #903 every worker record collects per-character offsets for every
horizontal run. They were gathered into a growable `List<double>`, so the VM
boxed every character, and every for-in in the serializers and readers boxed
it again.

- `_showText` collects into a take-and-restore `Float64List` scratch
  (`_charOffsetScratch`). There is no busy flag: a nested Type3 CharProc run
  finds the scratch null and allocates its own buffer, and an exception just
  drops it. Buffers longer than 4096 entries are not kept. Each run is copied
  out into an exact-size `Float64List` by index. Do not use `sublist`: dart2js
  builds a view plus a second typed array per run, which regressed short-run
  documents on web.
- `_Writer.f64List` has an indexed `Float64List` path. `_Reader.f64Array`
  reads unboxed; it is used for text runs, page text and the tiled-cell
  origins. The wire bytes are unchanged.

## 2. Worker decode cache: budget, admission, trim

`PdfImageDecodeCache.decode/put` take `reusable` from the call site, since
only the call site knows what a decode is good for.

- **Reusable entries**: every native-resolution decode, whatever the format
  (DCT ones are cropped and downsampled for every other record; any format's
  native key serves every record at or past native size), luminosity masks
  and browser-codec decodes. They share the whole budget,
  and the newest one may exceed it alone, up to the old 64 MB
  (`maxOversizeEntryBytes`). Without that allowance, deep zoom on an 8 MP+
  JPEG under a 16-32 MB budget would decode the whole image again for every
  tile.
- **Transient entries**: decodes at one exact target size, and the
  Flate/CMYK composites on web. Each is admitted up to half the budget
  (`maxTransientEntryBytes`: 32 MB on desktop, 16 MB on mobile/web, 8 MB on
  a small web device), and it may only displace other transient entries.

The budget comes from `pdfDefaultWorkerImageCacheBytes` and is computed on
the main thread: desktop 64 MB, mobile and web 32 MB, web with
`deviceMemory <= 2` 16 MB. It reaches the worker in its init message
(native: `_WorkerInit.imageCacheBytes`; web: an `imageCacheBytes` property).
If the property is missing the worker keeps 64 MB, so an older web bundle
still works.

`PdfRenderWorker.trimMemory()` is forwarded by the caching wrapper and by
every pool lane, including the urgent lane.

- **Native**: the trim is a string sentinel on the cancel port, handled
  before the `is! int` check. Never send it on the request port, which
  carries the per-id slot accounting.
- **Web**: it is a new `{kind:'trim'}` message.

On a trim the worker clears its decode cache in place (the diagnostics hold
that object and read its counters), and calls
`CosDocument.trimDecodedStreamCache()`. Web also drops its flate samples and
page-surface bitmaps.

`PdfCacheRegistry` has pressure listeners. `handleMemoryPressure` calls them
after it clears the caches, and `trimPressureListeners` calls them alone. The
app's mobile-background branch uses `trimPressureListeners`.

Browsers send no memory-pressure signal, so on web only the budget helps.

Measured with the first cut's 2 MB transient cap (private corpus, 3 workers
behind a 72 MB host record cache; the cap is now half the budget, see the
edit/undo section below, and these were not re-run with it):

- **Worker hits**: 57-page image document 267 at a flat 64 MB → 322 at
  32 MB. 138-page CAD set 103 → 70 at 32 MB; the lost hits cost no
  measurable CPU.
- **Memory retained at the end** (57-page document, desktop 64 MB budget):
  185.6 → 64.5 MB.
- **Deep zoom** on a 3000x3000 CMYK JPEG page: 31 of 36 hits at 16 MB,
  against 1 of 36 for a flat 16 MB cache.
- **One saturated native worker**: its footprint drops by 70+ MB more with
  the trim than without.

The first cut marked a non-DCT native decode transient, so a scan page
(Flate, JBIG2, CCITT: 1700x2200 px is 15 MB of RGBA) was never retained, and
a zoom between two past-native levels decoded it again. Occupancy sim, one
worker behind a 72 MB host record cache: scroll forward with a 128px tile
per page, back, then zoom steps 3, 4, 6, 3, 2, each forward and back; median
of 5 interleaved runs:

| document | flat 64 MB (before) | transient native, 64 MB | reusable native, 64 / 32 MB |
|---|---|---|---|
| scan-book-12p (Flate gray) | 20 hits, 1354 ms | 0 hits, 1528 ms | 20 / 10 hits, 1340 / 1427 ms |
| 12-page JBIG2 scan (`gen_jbig2_scanned_pdf.dart`) | 12 hits, 3182 ms | 0 hits, 3378 ms | 12 / 6 hits, 3196 / 3259 ms |
| image-scan-4p (1.9 MB images) | 12 hits | 12 hits | 12 / 12 hits |

Every hit the flat cache got on a scan came from the native key, so marking
native decodes reusable restores it exactly; scaling the transient cap
instead (8 MB at 64 MB) left the scans at 0-3 hits. On the 138-page CAD set
(ratios 2, 3, 2) it moves worker hits 374 -> 317 at 64 MB and 272 -> 289 at
32 MB with CPU inside the run-to-run noise.

A trim on web waits until no walk is running (`_WorkerWalks.whenIdle`): a
walk in flight has prepared the decoded-stream seeds it is about to read,
and trimming under it sent them back through the pure-Dart inflate. It also
drops the transcript cache's retained command graphs
(`PdfWorkerTranscriptCache.trimRetained`), keeping the text cache (search
and selection would re-walk for it) and the suspended walk (work in
progress, not reuse).

### Edit and undo: why target-size decodes are kept up to half the budget

The first cut admitted a target-size decode only up to 2 MB, on the theory
that only a repeat of the same record hits it and the host's record cache
answers those. That holds for a scroll, not an edit: an edit or an undo
bumps the revision, misses the host cache, and re-records the page at the
ratio it was just recorded at - and the worker keeps its decode cache across
in-place revision updates and undo for exactly that re-record. With a 2 MB
cap every downscaled scan, underlay, JPX or large Flate image decoded again
on every edit, at every budget, desktop included.

Sim (AOT, one worker behind a 72 MB host record cache): open + the scroll
and zoom pattern above, then one edit and one undo re-record per page at
ratio 2. Edit/undo time is the median of 5 rounds (3 on the private
documents); hits are deterministic.

| document | budget | 2 MB cap: edit/undo, hits | half-budget cap |
|---|---|---|---|
| raster-underlay-1p (a ~30 MB target) | 64 MB | 884 ms, 0 | 39 ms, 4 |
| raster-underlay-1p | 32 / 16 MB | ~900 ms, 0 | ~900 ms, 0 (target past the cap) |
| scan-book-12p | 64 / 32 / 16 MB | 16 / 14 / 13 hits | the same |
| image-scan-4p, letterhead-report-40p | all | unchanged | unchanged |
| 57-page image document (private) | 64 / 32 MB | 287 / 262 hits | the same, CPU within noise |
| 57-page image document | 16 MB | 255 hits | 229 hits, CPU within noise |
| 58-page design pack (private) | 64 / 32 MB | 292 / 268 hits | the same; scroll+zoom hits 108 / 86 -> 44 / 44 at the same or lower CPU |

A quarter-budget cap (16 MB at 64 MB) still misses the underlay; the whole
budget let one zoom level's targets churn out the last one's (0 scroll+zoom
hits on the underlay, against 2). Re-recorded bytes are identical to an
uncached record on every page. Pinned by `image_decode_cache_test`'s "a
downscaled decode is reused by a same-ratio re-record".

## 3. Records streamed straight to the wire (native)

`PdfStreamingCommandWriter` is a `PdfDevice` that writes each command into the
`_Writer` buffer as it arrives, through `_writeCommand`, so the v11 writer
state stays in write order. A partial is `snapshot()`, a prefix copy with
the count at offset 1 patched (it throws inside a soft mask, where the nested
list's header is half-written, rather than return a corrupt buffer). This is valid because path blocks pad to 4
bytes from the buffer start. For the same reason no splice that changes a
length (a tombstone, or an image slot) is possible.

Scope compaction is now online (`_ScopeCompactor`) and shared with
`serializeCommands(compactStateScopes: true)`.

- A pending save is written before a clip, a group, a soft mask or a tiled
  cell, and then every pending save goes, outermost first.
- The rule that writes only on a clip (and only the innermost save) is
  wrong. It puts a save inside a layer whose restore lands outside it. With
  that rule the pixel check differs on GWG161 Knockout p1 and V50 CMYK p2.
- The compacted bytes changed deliberately; the pixels did not (0 differences
  on 271 ghent + pdfjs pages).

The worker streams only when `commandLimit` is null. A limit counts commands
before compaction, so command-limited records keep the recorder. If a
suspended streamed walk is found by a limited record, the walk is abandoned
and the record starts over.

A streamed decoding record with images ships the stream as its vector
snapshot. Its final buffer is
`serializeCommands(compactTranscriptSourceCommands(deserializeCommands(stream), imageRequests), decodeImages: true, ..., compactStateScopes: true)`;
recompacting is idempotent. That second pass costs more than the command
graph the stream saved, so the device is picked up front
(`pdfWorkerRecordStreams`): a decoding record of a page whose resources
declare an image XObject keeps the recorder and serializes once, unless its
decoded content is at least 16 MB (`pdfWorkerStreamedImagePageMinContentBytes`).
Non-decoding records, image-free pages and heavy image pages stream.

"Declares an image" covers what the page can reach, not just its own
/XObject dictionary: forms and tiling patterns below it (8 deep, 512 objects,
conservative past either bound, memoised per resource dictionary or form so
a shared resource dictionary is resolved once per revision), a `BI` token in
content up to 256 KB (the scan is linear like the walk, ~0.8 ms per MB, and
the recorder's lead is largest on light pages), and the normal appearances of
the page's annotations when the record draws them (the editor's image stamps
and signatures). Across ghent, pdfjs, dartpdf and the private corpus (first
50 pages per file) that moves 14 pages to the recorder and none the other
way; the bytes do not depend on the device. The decision costs 11 ms over a
138-page CAD set against 4.4 s of walking (JIT). An image the scan still
misses (inline on a page past 256 KB) streams and takes the re-serialize:
correct, just not the cheapest.

Where the 16 MB comes from, streamed vs recorded decoding record (ratio 2,
persistent decode cache, text capture, annotations), AOT, 5 interleaved
rounds:

| page | stream / recorder |
|---|---|
| letterhead-report-40p (5 KB content + a logo per page) | 1.21x in-process wall |
| real CAD sheets with 1-12 images, 0.2-1 MB of content | 0.99-1.12x wall |
| real CAD sheet, 1 raster, 1.1 MB, ~30k commands | 1.06x process CPU |
| real CAD sheets, 5-9 MB | 1.06-1.08x process CPU |
| real CAD sheets, 11 MB | 0.99x process CPU |
| real 25 MB sheet with 925 images | 0.92x process CPU, RSS ~700 -> ~600 MB |

With the choice in place, letterhead-report-40p decodes at 0.99x of the
recorder (median of 7 rounds: 331 vs 335 ms; streaming everything was
405 ms), the 1.1 MB raster sheet at 0.97x process CPU, the 9 MB sheet at
1.00x, and the 25 MB sheet keeps its win (0.88x process CPU).
text-report-40p, raster-underlay-1p and scan-book-12p are within noise.

The web worker, the transcript cache and `_entryFor` still use the recorder.

A/B, old graph + serialize vs the stream, on pages that stream. Ratios are
thread CPU / process CPU / max RSS:

| page | ratios |
|---|---|
| 850k-command synthetic wide sheet | 0.69x / 0.51x / 0.61x |
| real 285k-command sheet | 0.80x / 0.67x / 1.12x |
| dense diagram | 0.85x |
| text | 1.00x |

On the real sheet the RSS rise comes from the VM's default new-space growth.
With new space capped at 2 MB the same run is 245 → 166 MB.

## Not done

- **FFI-shared native spawn image** (worker-memory phase 1, one malloc'd
  document image shared by every pool lane). Deferred. It needs airtight
  lifetime tests (malloc/free counters across dispose-mid-spawn and
  kill-during-decode) and the mandatory "never write in place into a shared
  seed" rule for undo-then-edit on a lane spawned mid-session (see #957 and
  #981). It was not attempted here.
- **Streaming on the web worker and in the transcript cache.**
- **Writing paths straight from the builder's scratch arrays.**
