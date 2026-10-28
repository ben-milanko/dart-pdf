# Wiring the editing controller to the sync layer

This is step 1 of the plan in `2026-10-28-shared-folder-live-sync.md`.

**`PdfSyncClock` (pdf_document `sync.dart`).** The last-writer-wins
bookkeeping now lives in one class instead of inside `PdfSyncSession`: a
Lamport clock plus the winning `(clock, origin)` per /NM. `stamp(change)`
wraps a local change as the newest write for its /NM. `accept(message)`
advances the clock and says whether a remote message wins, recording the
winner even when applying it turns out to be a no-op. `PdfSyncSession`
delegates to it with unchanged behaviour (`sync_test`, `sync_folder_test` and
`comment_test` all pass untouched).

**`PdfEditingSync` (dart_pdf_editor `editing/editing_sync.dart`).** Connects a
`PdfEditingController` to any `PdfSyncTransport`:

- Outbound: each batch on `annotationChanges` (edits, undo and redo alike) is
  stamped and sent.
- Inbound: each message the clock accepts goes through `applyRemoteChange`.
  That never re-emits, so nothing echoes back. It also seals local undo at
  that point, so you can't undo past a remote change.
- `peers` / `presence` come from the transport. `remoteChanges` carries each
  remote change that won the merge and changed the document, for toasts or a
  sidebar flash.
- `dispose()` stops both directions. It leaves the controller and the
  transport open, because the host owns both.

Because both sides use the same clock, a controller and a headless
`PdfSyncSession` on one transport converge together. That makes a server-side
or CLI participant possible later.

Tests are in `dart_pdf_editor/test/editing_sync_session_test.dart`:

- merge in both directions with no echo (a spy transport counts sends);
- a concurrent move of one /NM resolves to origin "b" on both sides;
- undo propagates as an edit;
- an editor and a headless `PdfSyncSession` interoperate;
- `dispose` stops both directions;
- two devices plus a late joiner converge over `PdfSharedFolderSyncTransport`
  on a `PdfMemorySyncStore`.

## Still the host's job, documented on the class

- Lock page insert/remove/reorder while a session is live. Changes carry page
  indices, so a structural edit on one device puts every other device's
  annotations on the wrong pages. Content, form and signing edits aren't
  synced at all.
- Every participant must start from bytes in which every annotation already
  has its /NM. Only the first participant may run `ensureAnnotationNames`,
  and must share the named bytes before anyone joins.
- Catch up before editing: await `startPolling` on the folder transport.
  Otherwise the clock hasn't moved past the shared history, and a fresh
  participant's first edits lose to older ones.
- A remote change that lands mid-gesture (drag, resize, ink stroke) clears
  the selection on the touched pages, as `applyRemoteChange` always has. It
  isn't queued until the gesture ends. That's worth revisiting once there is
  UI on top.

## Next

The app side: a `dart:io` folder store, a per-tab "Live sync (experimental)"
switch, a presence chip, and the structural-edit lock. After that comes
compaction (writing the merged state back into the PDF).
