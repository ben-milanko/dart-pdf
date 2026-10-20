# Web render worker: revisions in place instead of a restart per edit

The native pool has taken editor revisions in place since #308 (and without
the extra document copies since #957). The web backend never did:
`_WebRenderWorker` reported `supportsRevisionUpdate == false` and the worker
entry had no `update` message. So every edit, undo and redo on the web went
through `PdfRenderWorkerHost.sync`'s restart path:

- the worker was terminated and a new one booted (a new
  `PdfCachingRenderWorker` too, so the main-side record cache went with it);
- on a cross-origin isolated page, `_sharedDocumentBuffer` allocated and
  filled a new document-sized `SharedArrayBuffer` on the UI thread, because
  its Expando is keyed by the revision view and every revision is a new view
  (without isolation, `Uint8List.fromList` of the whole document instead);
- the new worker re-opened the document and re-warmed from cold: every image
  on the edited page was decoded again, every other page re-recorded on its
  next visit.

## What changed

Main side (`render_worker_web.dart`):

- **Capability handshake.** The worker adds `revisionUpdate: 1` to its
  `ready` envelope, beside `imageDecodeCache`. `supportsRevisionUpdate` is
  `isActive && _ready && _workerRevisionUpdate`. The worker is a separately
  compiled and separately cached bundle, so a new main bundle can meet an old
  worker that would silently drop an `update`; against such a worker (or
  before `ready`) the host keeps restarting as before. If an update is ever
  dispatched to a worker without the capability anyway, the backend fails
  over to local rendering instead of posting it.
- **`updateRevision`** queues a `_WebRequestKind.update` through the normal
  `_queue`/`_pump`, so it is dispatched only when the in-flight slot is free,
  and its priority makes the existing preemption cancel and requeue a running
  record or surface. `updateRevisionTo` keeps the base class default (one
  exact private tail).
- **The tail is cloned, never transferred.** `PdfPooledRenderWorker`
  hands one tail to every lane (the library's web default pool is 3). An
  earlier prototype transferred `appended.buffer`, which detached it for every
  lane after the first. The update posts the tail with a plain `postMessage`
  (a structured clone of an exact-size buffer copies only the append).
- **Failure means local, then restart.** An error ack, or no ack within the
  record watchdog, `_fail()`s the backend: queued and later requests render
  locally rather than risk a record of the pre-edit document cached under the
  new revision, and `supportsRevisionUpdate` reads false, so the next `sync`
  starts a fresh worker.
- **Priority.** The update sorts ahead of every request (`-(1 << 30)`), not
  at the isolate backend's -1000. A single web worker (the app runs a pool of
  one) also serves the -2000 long-jump preview directly; at -1000 such a
  record queued in the same turn as an edit would be dispatched first and read
  the document the edit replaced.

Worker side (`render_worker_web_entry.dart`), mirroring the isolate handler:

- **Validate, then write.** `newLength == baseLength + tail` and
  `baseLength <= workerLength` are checked before anything is written. The
  worker keeps a capacity buffer (`workerBytes`/`workerLength`) and parses
  from `sublistView(buffer, 0, newLength)`. It grows only when the tail does
  not fit, to `newLength + newLength/16 + 1 MiB`.
- **The shared seed is never written.** On an isolated page the init buffer is
  the pool's `SharedArrayBuffer`, which the other lanes and the main thread
  read. The first update that appends bytes copies the prefix into a private
  buffer; an undo that appends nothing just re-opens a shorter view of it. No
  resizable `ArrayBuffer` and no doubling.
- **In place or re-open.** `applyIncrementalUpdate` when `baseLength` is the
  open document's length; otherwise (undo, or an undo coalesced with the next
  edit) re-open the prefix with `renderWorkerRevisionRanges`.
- **Caches.** In place: `transcriptCache.evictPages(changed)`, a new
  `_PageSurfaceBitmapCache.evictPages` on every surface (closing the matching
  bitmaps), and `_BrowserFlatePredecoder.evictPages`. The image-decode and
  flate-sample caches stay: they are keyed by stream object, and the update
  gives every redefined object a new one. A re-open resets everything `init`
  resets plus the transcripts (`resetDocumentCaches`, now shared with `init`).
- **No walk sees the document change.** Record, surface, bin, detail and
  region-index walks now run through `_WorkerWalks`, which tracks them until
  they end. The main side sends an update only when its slot is free, but its
  record watchdog can free the slot while a slow walk is still running here,
  so the update cancels every running walk and applies once they have
  unwound. The body is wrapped in `try`/`finally` and always acks
  (`{kind:'result', id, incremental, error?}`).

Undo stays a cold re-open on the web, as it is natively: the worker re-opens
the shorter prefix and drops its decoded images. What it saves over a restart
is the worker boot and the UI-thread document copy.

## Tests

`test/render_worker_revision_web_test.dart`, in the worker-compiles Chrome
step (it reuses the `sparse_test_worker.js` build):

- On an 8-page document: warm pages 4-6, edit page 5, and page 6 is still a
  worker transcript hit while page 5 re-records (`lastRenderTrace`, perf
  logging on). Every step - the edit, a second edit and two undos, an edit
  that overwrites the undone bytes, undo + redo - records byte-identically
  (`serializeCommands`) to a fresh worker on a copy of the bytes.
- A pool with two web lanes fed through `updateRevisionTo` (one shared tail):
  pages on both lanes match a fresh worker after two edits and an undo, and
  the pool still supports updates (no lane failed).
- Through `PdfRenderWorkerHost`: two edits, an undo and a redo keep one
  generation.
- A stub worker (a Blob-URL script) whose `ready` lacks `revisionUpdate`:
  `supportsRevisionUpdate` is false and the next edit starts generation 2.

Mutation checks: transferring the tail fails the pool test; skipping the
worker's transcript eviction fails the first test (page 5 stays a hit and its
record is stale) and the pool test.

CI runs Chrome without COEP, so it covers the transferred-buffer seed. The
`SharedArrayBuffer` seed ran in the cross-origin isolated release harness
below (every B run: SAB init, private copy on the first append).

## Measurements

Release harness (`editlat`), real headless Chrome, cross-origin isolated (so
both arms seed workers from a `SharedArrayBuffer`; every branch run took that
path and applied all its updates in place). A is main at cc144ae7 plus the
same harness method, B is this branch; both bundles were built once and
single runs alternated ABAB with alternating order, 5 pairs per document. Each
run makes 8 edits 1.5 s apart on the first page (a rectangle, then a 20pt move
of the page's image or first element, alternating). Figures are medians of per-run
medians; ratios are the median of the per-pair B/A. Load average 10-17 on 10
cores.

| document | metric | A | B | B/A |
|---|---|---|---|---|
| raster-underlay-1p (1.1 MB) | worker generations | 9 | 1 | |
| | content edit to new raster | 1518 ms | 171 ms | 0.112 (range 0.106-0.123) |
| | annotation edit call (apply + hand-off) | 2.4 ms | 1.8 ms | 0.74 |
| plan-set-16p (2.1 MB) | worker generations | 9 | 1 | |
| | content edit to new raster | 220 ms | 164 ms | 0.71 |
| a 24 MB private real-world drawing | worker generations | 9 | 1 | |
| | content edit to new raster | 184 ms | 68 ms | 0.369 (range 0.324-0.401) |
| | annotation edit call (apply + hand-off) | 5.3 ms | 1.7 ms | 0.336 |

Annotation edit-to-raster is unchanged (17-22 ms either way): in an editing
session the edited page's annotations are drawn on the UI thread and its base
raster is kept, so the worker is not on that path.

`PdfRenderWorkerHost.sync` itself, timed with a temporary (uncommitted) probe
in both arms, 8 annotation edits x 5 interleaved pairs, excluding the initial
open: 24 MB document 3.65 -> 0.10 ms per edit (0.028x; A allocates and fills
a new shared buffer and spawns a worker), 1.1 MB document 0.81 -> 0.08 ms
(0.13x).

Pixels: the final screenshot of every B run matched its paired A run exactly
(15 pairs; 0 pixels differ at all, so 0 above 8).

Worker memory (`editlatWorkerMemMb`, JS heap `measureUserAgentSpecificMemory`
attributes to the dedicated worker at the end of the run): 60 -> 66 MB on the
underlay, 11 -> 29 MB on the plan set, 38 -> 160 MB on the 24 MB drawing. The
A figure is a worker generation that has rendered one page since its last
restart; B is a warm worker. For scale, a reader (no editing) that opened the
same 24 MB file and jumped a few pages had a worker context of about 139 MB. B adds the private copy of the document
(1.06x + 1 MB, 26.6 MB there) to what a warm worker holds, and the level does
not grow with the edit count: 159.6 MB after 2, 8 and 16 edits (153 MB with
annotations only), 157.8 MB after 10 s idle. The first append costs the worker
that copy once (the first update round trip on the 24 MB file was 7.4 ms, the
rest 0.5 ms).

Undo is not in the harness journey; it re-opens in the same worker, which
saves the boot and the UI-thread document copy but still re-decodes.

## Notes

- The worker now holds a private copy of the document next to the shared
  seed (the seed stays alive while cached objects view it). That is about one
  document per lane more than before on an isolated page; the app runs one
  lane on the web. Before, each edit allocated a new shared buffer on the UI
  thread and the old one lingered until collected.
- `editlat` (harness method + `editlat-underlay`/`editlat-plan` in
  scenarios.json) emits `editlatWorkerGenerations`, `editlatUpdatesInPlace`/
  `Reopened`/`Failures` (counted from the viewer's own `webworker` log lines),
  per-kind sync/ready medians and `editlatWorkerMemMb`
  (`measureUserAgentSpecificMemory` attributed to dedicated workers).
- AES-256 documents: an in-place update reuses the open document's keys, so an
  edit no longer re-runs Algorithm 2.B in a fresh worker; an undo re-open
  still does (see `2026-09-28-sha512-web.md`).
