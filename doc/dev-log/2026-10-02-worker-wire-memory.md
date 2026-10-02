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

`PdfImageDecodeCache.decode/put` take `reusable` from the call site. The
cache cannot infer it: the null-ratio fallback writes a native key that only
DCT decodes can serve to other records. That is why the fallback passes
`reusable: pdfImageDecodeIgnoresRegion(...)` rather than a constant.

- **Reusable entries**: native DCT decodes (region and ignoresTarget),
  luminosity masks and browser-codec decodes. They share the whole budget,
  and the newest one may exceed it alone, up to the old 64 MB
  (`maxOversizeEntryBytes`). Without that allowance, deep zoom on an 8 MP+
  JPEG under a 16-32 MB budget would decode the whole image again for every
  tile.
- **Transient entries**: decodes at one exact target size, and the
  Flate/CMYK composites on web. Each is admitted only up to 2 MB, and it may
  only displace other transient entries.

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

Measured (private corpus, 3 workers behind a 72 MB host record cache):

- **Worker hits**: 57-page image document 267 at a flat 64 MB → 322 at
  32 MB. 138-page CAD set 103 → 70 at 32 MB; the lost hits cost no
  measurable CPU.
- **Memory retained at the end** (57-page document, desktop 64 MB budget):
  185.6 → 64.5 MB.
- **Deep zoom** on a 3000x3000 CMYK JPEG page: 31 of 36 hits at 16 MB,
  against 1 of 36 for a flat 16 MB cache.
- **One saturated native worker**: its footprint drops by 70+ MB more with
  the trim than without.

## 3. Records streamed straight to the wire (native)

`PdfStreamingCommandWriter` is a `PdfDevice` that writes each command into the
`_Writer` buffer as it arrives, through `_writeCommand`, so the v11 writer
state stays in write order. A partial is `snapshot()`, a prefix copy with
the count at offset 1 patched. This is valid because path blocks pad to 4
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

A decoding record with images ships the stream as its vector snapshot. Its
final buffer is
`serializeCommands(compactTranscriptSourceCommands(deserializeCommands(stream), imageRequests), decodeImages: true, ..., compactStateScopes: true)`;
recompacting is idempotent.

The web worker, the transcript cache and `_entryFor` still use the recorder.

A/B, old graph + serialize vs the stream. Ratios are thread CPU / process CPU
/ max RSS:

| page | ratios |
|---|---|
| 850k-command synthetic wide sheet | 0.69x / 0.51x / 0.61x |
| real 285k-command sheet | 0.80x / 0.67x / 1.12x |
| dense diagram | 0.85x |
| text | 1.00x |
| image pages (decoding fallback) | 0.85-0.99x |

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
