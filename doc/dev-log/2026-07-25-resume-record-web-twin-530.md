# Resume a preempted record on the web worker too (#530 web twin)

#572 landed resume-on-preemption in the **isolate** worker (`_recordResumablePage`
+ a one-slot `_SuspendedRecordCache`), deliberately isolate-only so it wouldn't
touch the web bundle before the #422/#571 `WORKER_REGEN_TOKEN` existed. The token
is now set, so this brings the web worker to parity.

## Where it goes on web

The two workers have different caches. The isolate records full pages through
`_recordResumablePage` directly; the **web** worker records them through
`PdfWorkerTranscriptCache.transcriptFor` (a budgeted LRU of complete transcripts
it replays for strip planning and reuses across records). So the resume seam is
*inside* `transcriptFor`, not a bolt-on cache.

`transcriptFor` used the same terminal-on-cancel shape the isolate had pre-#530:
`drawPageContentAsync(cancellation: token)` throws on cancel and the partial is
discarded, so a requeue re-interpreted the prefix. Reworked its record phase to
the resumable pattern:

- A one-slot `_suspended` field on the cache (`_SuspendedTranscriptWalk`), with
  `_takeSuspended` / `_keepSuspended` / `_evictSuspended` — the exact take/keep/
  evict semantics of the isolate's `_SuspendedRecordCache`.
- The record drives `beginPageContent` + bounded `advance(operations:
  _resumeChunk)` chunks with **no** interpreter cancellation token (a token throws
  mid-chunk and finishes the walk, discarding the partial), checking the token
  between chunks. On cancel it stashes the partial and rethrows; on completion it
  draws annotations and serializes exactly as before. A finished walk is never
  resumed (defensive guard against a hang).
- `clear()` and `evictPages()` also drop the suspended slot.

## Web specifics that make this simpler than it looks

The web backend reports `supportsRevisionUpdate == false`, so there is **no
'update' message** — an edit recreates the whole worker (fresh cache), and the
suspended slot dies with it. So the slot only ever spans one worker's lifetime,
which is exactly the scroll-preempt→requeue window this targets; edits need no
special handling, and the `evictPages`/`clear` slot-eviction is correct-but-
defensive.

`transcriptFor` is used only by the web entry (the isolate imports this file just
for shared helpers), so the change is web-scoped. The `_recordPageAsync`
preview/prefix path (`commandLimit` set) still records fresh, matching the
isolate's non-resumable preview gate.

## Tests

`render_worker_transcript_cache_test.dart` gains two #530 cases, using a new
`resumeChunkOperations` seam (tiny chunk) to force a multi-chunk walk and a
deterministic mid-walk cancel (the walk yields at each chunk boundary, handing
control back before the between-chunk check):

- a preempted record **resumes** on the next call and serializes byte-identically
  to a one-shot record;
- a revision `evictPages` drops the suspended partial and the next record starts
  fresh and completes.

The walk-composition correctness itself is already proven by the isolate's
`resume_record_test.dart` (identical `beginPageContent`+chunked-advance). Full
transcript-cache + compaction suites pass; the no-cancel path is unchanged.

## Bundle

Shared `dart_pdf_editor` code reachable from the web entry, so the checked-in
`pdf_render_worker.dart.js` is rebuilt here. With `WORKER_REGEN_TOKEN` now
configured, CI can auto-regen if a rebuild is ever missed — but the committed
rebuild is the primary path (as in #554, a local build matched CI's byte-for-byte).

Files: `render_worker_transcript_cache.dart`,
`test/render_worker_transcript_cache_test.dart`,
`packages/dart_pdf_editor_assets/assets/web/pdf_render_worker.dart.js` (regenerated).
