# Revision-aware render worker: stop restarting the pool on every edit

Issue #308 (perf). Follow-up to #306/#307. The render worker's interface used
to be a fixed byte snapshot, so `PdfShellSessionLifecycle._syncWorker` disposed
the whole pool and called `startPdfRenderWorker` again on *every* edit, undo,
and redo: N private `PdfDocument` re-parses (xref + content) plus an empty
decoded-image cache **and** transcript/record cache, all to reflect a change to
one page. Yet revisions are append-only (one growing buffer, a stack of
lengths), so an edit to page 5 leaves every other page's bytes identical.
Identity-based restart was the coarsest possible invalidation.

## What landed

A deeper worker interface that absorbs a revision in place instead of being
torn down:

`PdfRenderWorker.updateRevision(int baseLength, Uint8List appendedBytes,
int newLength, Set<int>? changedPages)` plus a `bool supportsRevisionUpdate`
capability. The worker keeps its buffer's first `baseLength` bytes (the shared
prefix), appends `appendedBytes` to reach a `newLength`-byte revision, feeds
that into its already-open document, and evicts only `changedPages` from its
per-page caches (null = every page).

### Layering

- **pdf_cos** `CosDocument.applyIncrementalUpdate(newBytes)`: `bytes`/`trailer`/
  `startXref` became mutable. It parses only the xref sections newer than the
  current `startXref` (walking `/Prev`+`/XRefStm` until it reaches the old
  start offset), overrides the matching `_xref` entries (newest wins), merges
  the trailer (keeping doc-level keys the incremental trailer omits, like
  `/Root`), swaps in the new bytes, and drops cached state (`_cache`,
  `_objectStreams`, `_streamOwners`) for the redefined objects only. Returns the
  changed object numbers. Refuses recovered documents (`startXref <= 0`) and
  non-append buffers. Safe because the prefix bytes are byte-identical, so cached
  objects that hold views into the old buffer stay valid.
- **pdf_document** `PdfDocument.applyIncrementalUpdate` = cos + `invalidatePageCache()`.
- **budgeted_cache** `evictWhere(predicate)` — targeted per-key eviction. The
  record/transcript caches already key on `(pageIndex, ...)`, so per-page
  invalidation is a filtered eviction, not `clear()`.
- **transcript cache** `evictPages(Set<int>?)`; isolate `_BinCommandCache.evictPages`.
- **render_worker** wrappers: `PdfCachingRenderWorker.updateRevision` evicts the
  record cache for the changed pages and forwards to the inner worker;
  `PdfPooledRenderWorker` fans the update to every platform worker and rolls the
  urgent-worker seed bytes (`_urgentBytes`) forward so a long-jump preview after
  an edit opens the edited document.

### The isolate backend

`_IsolateRenderWorker.updateRevision` routes the update through the **same
priority queue** as records (priority `-1000`), so it dispatches only when the
worker is idle. That matters: the update mutates the worker's document in place,
and the record/bin walks are async and yield — running them concurrently would
let an interpret see a half-updated document. A queued update preempts a
running record (which requeues via `requeueAfterPreemption` and then re-runs
against the new revision) exactly like an urgent visible record preempts
prefetch. In `_workerMain` the `'update'` message rebuilds the worker's byte
buffer and tries `applyIncrementalUpdate`; if that throws (an undo shrinks to a
shorter prefix, so it's not an append) it re-opens from the target prefix. On
the in-place fast path only the changed pages' `_BinCommandCache` entries are
evicted; a re-open makes a fresh document so **all** cached commands (which
referenced the old one) are dropped.

### The stale-inflight guard (subtle)

The isolate processes messages serially, so an in-flight record for page P
finishes against the *old* document before the `'update'` runs — its buffer is
stale. `PdfCachingRenderWorker` therefore stamps a revision epoch: a decode
captures `_epoch` at dispatch and stores its result only if its page was not
invalidated since (`_invalidationEpochFor(page) <= dispatchEpoch`). Without this
a decode dispatched just before an edit to its page would cache pre-edit content
and a later request would hit it. Covered by the "in-flight decode ... is not
cached (stale)" test.

### Controller + shell

`PdfEditingController.lastRevisionDelta` (a `PdfWorkerRevisionDelta` of
`baseLength`/`newLength`/`changedPages`) is set at each transition:
- forward edit / redo: `baseLength` = previous live length, append the tail,
  `changedPages` = `impact.visualPages`;
- undo: `baseLength == newLength` (keep the shorter prefix, append nothing);
- **null** for the initial open, a `pageStructureChanged` edit, or a redaction
  burn (`_resetTo` replaces the buffer with a non-prefix compaction) — the shell
  falls back to a full worker restart there.

`_syncWorker` now takes the incremental path when the worker
`supportsRevisionUpdate`, the delta is non-null, and its `newLength` matches the
live revision; otherwise it starts a new generation as before. It copies the
appended slice (`Uint8List.fromList`) so transferring it to the isolate can't
detach the controller's buffer.

## Scope / what's deferred

- The **native isolate** backend is fully wired (VM tests exercise it). The
  **web** backend and its bundled prebuilt worker asset are *not* updated:
  `supportsRevisionUpdate` stays false there, so web keeps restarting the worker
  on an edit (no regression, no gain). Wiring the web-worker `'update'` message
  and rebuilding `assets/web/pdf_render_worker.dart.js` is a clean follow-up.
- Undo/redo take the isolate's re-open fallback (a prefix re-parse), not a true
  incremental step, and clear that worker's bin cache wholesale — the record and
  decoded-image caches still survive, so the headline "only the edited page
  re-renders" holds. The forward-edit path (the measured case) is fully in place.

## Measures / tests

- `debugWorkerGenerations` stays flat across form-fill / edit / undo / redo and
  bumps once on a redaction burn (`shell_session_test.dart`).
- Edit page 5 → page 6's record survives, page 5's is dropped
  (`render_worker_revision_test.dart`, both a fake-backend unit test and a real
  isolate integration test that confirms the in-place document actually reflects
  the edit).
- `applyIncrementalUpdate` matches a full reopen; unedited pages stay
  byte-identical; redefined objects resolve to the new value
  (`pdf_document/test/incremental_update_test.dart`).
- `evictWhere` / `evictPages` unit tests.
