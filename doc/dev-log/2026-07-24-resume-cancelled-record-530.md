# Resume a preempted page record instead of restarting (#530)

#566 landed the resumable-cursor primitive (`PdfInterpreter.beginPageContent` →
`PdfPageContentWalk`): a walk records a bounded chunk of operations and can be
called again to continue from where it stopped, appending to the same device.
#530 is the render-path consumer: hold that walk across a cancellation so a
requeued render resumes instead of re-interpreting the prefix.

## Where the restart actually was

The issue named `render_scheduler.dart` / `page_render_session.dart`. Those are a
synchronous main-thread control plane and never touch the interpreter walk. The
mid-walk cancel-and-restart lives in the **render worker**:
`render_worker_isolate.dart` (native) and its full twin
`render_worker_web_entry.dart` (web).

The mechanism is the existing **preemption requeue**
(`PdfRenderWorker._pump` → `requeueAfterPreemption`): when a higher-priority page
is queued while a record is interpreting, the in-flight record is cancelled, the
worker replies `[id, null]`, and the main side puts the *same* record back on the
queue behind the urgent page. Pre-#530 the requeued record re-ran
`_recordPageAsync` from operation 0 — the whole prefix re-interpreted.

## The change (isolate worker only)

`_recordPageAsync`'s full-page path (`decodeImages == true`, i.e. no operation
cap) now runs through `_recordResumablePage`, backed by a one-slot
`_SuspendedRecordCache`:

- **Fresh start or resume.** `take(page, annotations)` returns a walk suspended
  by an earlier cancel of the same page, or the record starts a new
  `beginPageContent` walk.
- **Chunked, tokenless drive.** The interpreter carries **no** cancellation
  token, because a token makes `advance` throw mid-chunk, which *finishes* the
  walk and restores the device — discarding the partial. Instead the loop
  advances `_resumeRecordChunkOperations` (4096) at a time and checks
  `token.cancelled` between chunks. 4096 bounds the post-cancel overshoot to a
  sliver of a heavy page while keeping per-chunk cost negligible; the walk still
  yields internally every 512 ops so the isolate keeps servicing the cancel port.
- **Suspend on cancel.** `keep(entry)` stashes the partial walk (cursor +
  interpreter graphics state + recorder commands + page) and the record rethrows
  `PdfCancelledException`; the outer handler replies null and the main side
  requeues, exactly as before. The next record of that page resumes.
- **Completion is unchanged.** On the last chunk the walk auto-finishes (the
  balancing `device.restore()` runs), then annotations + `serializeCommands`
  happen once, identical to the one-shot path.

Preview/prefix records (`decodeImages == false`, bounded by `commandLimit`) keep
the simple discard-on-cancel path — they are already cheap and their op cap makes
resume pointless.

### One slot, and why it's enough

The target workload is: page P is preempted by an urgent neighbour, the neighbour
records fresh, then P requeues and resumes. `take` only removes the slot's entry
on a *matching* page, so the neighbour's fresh record leaves P's suspended walk in
place. Nested preemption of a second page evicts the first (`keep` abandons the
previous) — a bounded-memory trade that degrades the older page to today's
restart, never a correctness problem, since an abandoned walk's partial recording
is just discarded.

### Eviction

A suspended walk reads the old document, so it follows `_BinCommandCache`'s
eviction: on a revision `update` the worker calls `suspendedRecord.evict(changed
pages)` (or clears all on a re-open). Updates only arrive when the worker is idle,
and suspending completes the record request (the worker goes idle), so a resume
can only happen against the identical document.

## Scope: isolate first, web twin is a follow-up

Deliberately native-only. Reasons:

- The iPad heavy-page hang this targets runs on the **isolate** worker, so this
  is the actual target.
- The web worker is a separate twin; editing it forces a `dart compile js` bundle
  rebuild, which is currently gated on the `WORKER_REGEN_TOKEN` from #422/#571
  that isn't configured yet. Leaving `render_worker_web_entry.dart` untouched
  keeps the checked-in bundle fresh and CI green.

The web twin should get the same treatment once the regen token is in place;
tracked on #530.

## Tests / measurement

- `interpreter_test.dart` already proves the chunked walk emits the same device
  calls as the unbounded one. New `resume_record_test.dart` adds the
  serialization round-trip: a walk suspended mid-page and resumed serializes
  **byte-identically** to a one-shot record, and the bytes are independent of
  chunk size.
- Existing real-isolate suites pass unchanged (`render_worker*`,
  `render_record_replay`, `strip_worker_latency`, `retained_scene`,
  `command_replay_latency`); the CAD strip-latency numbers are unmoved.
- The win is **perceived latency** — a preempted heavy page no longer throws away
  its interpretation — which is inherently hard to put a throughput number on
  without a cancel-mid-scroll harness. Correctness (identical output) is what the
  tests pin; the saved work is structural (the resumed walk starts at the cursor,
  not op 0).

Files: `packages/dart_pdf_editor/lib/src/render_worker_isolate.dart`,
`packages/dart_pdf_editor/test/resume_record_test.dart`.
