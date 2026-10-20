# Native render pool: apply revisions in place instead of copying the document

The revision-aware worker (#308, `2026-07-16-revision-aware-render-worker.md`)
stopped restarting the pool on every edit. Two whole-document copies per
revision were left behind, and nobody had measured them:

1. **Every worker isolate** handled an `'update'` message by allocating an
   exact-size `Uint8List(base + tail)` and copying the whole prefix into it.
   Undo did this too. The superseded buffer never died:
   `applyIncrementalUpdate` keeps unchanged cached objects, and their
   `CosStream` views pin the old buffer. So each worker held about one more
   document for every revision.
2. **The pool's urgent lane** (`PdfPooledRenderWorker._urgentBytes`, the seed
   for the lazily spawned priority -2000 long-jump worker) was rolled forward
   by rebuilding it as a full copy on the UI isolate. That happened
   synchronously inside the controller's `notifyListeners`
   (`shell_session._syncWorker` -> `PdfRenderWorkerHost.sync`) on every edit,
   undo and redo.

Web was never affected: its backend reports `supportsRevisionUpdate == false`
and restarts instead.

## What changed

- `render_worker_isolate.dart` `_workerMain`: `workerBytes` is now a capacity
  buffer, and `workerLength` is the revision the worker reflects. The update
  validates everything before writing (consistent lengths,
  `baseLength <= workerLength`). It then writes only the tail at `baseLength`
  and hands `PdfDocument` a `sublistView(buffer, 0, newLength)`. An undo is
  just a shorter view. The buffer grows only when the tail doesn't fit, to
  `newLength + newLength/16 + 1 MiB`. It does not double: each isolate owns
  its buffer, so doubling would park up to a document of dead capacity in
  every worker.
- `PdfRenderWorker.updateRevisionTo(revisionBytes, baseLength, changedPages)`,
  non-breaking. Its default copies out the tail and calls `updateRevision`, so
  custom backends and test fakes that override only `updateRevision` keep
  working. `PdfCachingRenderWorker` forwards it with the same epoch
  invalidation (`_invalidateRevision`). `PdfPooledRenderWorker` fans one tail
  copy out to its lanes and adopts `revisionBytes` itself as the urgent seed.
  `_rollUrgentBytes` moves the `cosSparseBufferRanges` entry onto the new view,
  because that Expando is keyed by buffer identity. `PdfRenderWorkerHost.sync`
  calls it with its current `bytes`. The tail-only `updateRevision` keeps the
  old copying path for callers that have no view.

## Why holding the view is safe (and the stale comments)

Several comments said the session buffer is "only ever replaced, never mutated
in place". That has been false since #413: `_commitSavedTail` writes each new
tail at the current revision's end, so an edit after an undo overwrites the
undone revisions' bytes. The invariant that actually holds is narrower. The
bytes inside the current revision's view do not change until the next revision
is synced. The session writes only past its current revision, and the
controller notifies the undo (the host syncs it) before a new edit can reach
bytes an earlier view covered. The generation-start seed (`copySource: false`,
#359) already relied on exactly this. A spawn copies synchronously
(`TransferableTypedData.fromList` runs before the first `await` in
`_spawnInner`), so an urgent worker never reads the view later.

One corner is not covered: `PdfEditingController.notifyListeners` defers to a
post-frame callback during the build/layout phase. If an undo *and* a new edit
both landed in one build phase, and an urgent spawn happened before the frame
ended, the lane would read overwritten bytes. Undo only comes from input
events, so this cannot happen today. The #359 seed has the same exposure.

The tail itself is still copied when `sync` runs. A queued update ships only
when its worker is idle, and by then the session may have overwritten that
range.

Inside the worker, the in-place write is safe because updates run only while
the worker is idle, in FIFO order. The write lands at or past `baseLength`. On
a forward append that is past everything the open document views. Every other
shape has `baseLength != doc.cos.bytes.length`: an undo, or a coalesced undo +
edit whose base is below the live revision. Those re-open and evict every cache
that saw the old document (bin commands, suspended record, text cache, image
cache) before anything reads the overwritten bytes again. The controller has
run the same pattern since #413/#395.

## Numbers

Harness: a scratch flutter test on the **real** pool (3 isolate workers via
`PdfRenderWorkerHost`'s default spawn). `PdfEditingController.apply(addNote)`
committed 5 appended revisions, and `host.sync` was called the way the shell
calls it. After each edit it recorded the edited page, plus one record per
lane so every worker had applied the update. It then read macOS
`phys_footprint` via `proc_pid_rusage`. `host.sync` was timed with
`CLOCK_THREAD_CPUTIME_ID`. Runs were interleaved against origin/main. The
documents were built with `PdfMerger.merge`: 40 copies of
`test_corpora/dartpdf/photo-jpeg-6p.pdf` (60.4 MB, 240 pages) and 10 copies of
`plan-set-16p.pdf` (20.9 MB, 160 pages).

60.4 MB / 240 pages, 5 rounds each (edit 1 excluded from the time medians
because of JIT warm-up):

| | base | worker in place only | both |
| --- | ---: | ---: | ---: |
| footprint after spawn + warm | +184 MB | +185 MB | +184 MB |
| after edit 1 | +477 MB | +476 MB | +418 MB |
| after edit 5 | +1228 MB | +592 MB | +419 MB |
| growth per edit after edit 1 | 187.8 MB | 29.0 MB | 0.5 MB |
| `host.sync` thread CPU, median (p90) | 11.81 (17.56) ms | 10.07 ms | 0.10 (0.13) ms |
| edit -> record of the edited page, median | 17.6 ms | 13.0 ms | 1.9 ms |

The "worker in place only" column is the first commit alone (3 runs). Its
growth oscillates by one document as the UI-side urgent copy is replaced and
collected. Records were non-decoding (`decodeImages: false`), so the latency
is update + interpret, not image decode.

20.9 MB / 160 pages, 3 rounds: `host.sync` 3.54 -> 0.08 ms. Growth per edit
77.0 -> 12.0 MB. The remaining 12 MB is record and text caches, not document
copies.

## Not done

- **The first edit still copies once per worker.** The spawn buffer comes out
  of `TransferableTypedData.materialize()` at exact size, so edit 1 grows it
  (+173 MB across 3 workers at 60 MB, plus the controller's own doubling).
  Seeding slack at spawn would avoid that. It would cost a larger
  UI-side copy on every open, including the view-only sessions that never
  edit.
- **Undo still re-opens the worker's document** and drops its caches. Only the
  copy part is gone. An incremental reopen would be the next step for
  documents with many pages.
- **The FFI-shared spawn buffer** (one malloc'd image for all workers instead
  of one `TransferableTypedData` copy each, about -2x document at spawn) is a
  separate, riskier change. It needs refcounted frees and copy-on-write on
  undo. Publishing a new shared buffer per revision would bring back the
  per-edit UI copy this change just removed.

## Tests

`test/render_worker_revision_test.dart`:
- A real session (edit, undo, an edit that overwrites the undone bytes, redo)
  and a coalesced undo + edit on one isolate worker. Each step is compared
  byte-for-byte (`serializeCommands`) against a fresh worker on a copy of the
  bytes. Skipping the coalesced re-open fails it.
- `updateRevisionTo`'s default gives an `updateRevision`-only backend a private
  tail copy.
- The pool adopts the view for its urgent lane (identity), shares one tail
  across lanes, and rolls the sparse ranges.
- Controller + host + a **raw** pool (the caching wrapper would serve the
  urgent request from its record cache): the pool lanes and the urgent lane
  both match a fresh worker. Leaving the urgent seed stale fails it.
