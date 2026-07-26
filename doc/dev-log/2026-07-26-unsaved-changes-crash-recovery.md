# Crash recovery: unsaved changes mirrored to disk (and to IndexedDB)

Until now an unsaved edit lived only in the tab's `PdfEditingController`
buffer. Session restore reopened the *files* you had open, flat, from
their origin - so a crash, an OOM kill, or a closed browser tab took the
edits with it. This adds a durable mirror: while a document has unsaved
work, its bytes are kept outside the process, and the next launch hands
them back.

## Why it's cheap

The editor's revision model does the heavy lifting. Every edit is an
incremental save, so revisions are byte prefixes of one growing buffer
(`_revisions` / `bytes` in `editing_controller.dart`). A mirror pass
therefore writes only the tail past what the store already holds -
annotating a 200 MB PDF a hundred times costs the annotations, not a
hundred copies of the file. Undo walks the length back, and the store
truncates to match rather than leaving bytes it would never read.

That property is the *contract* on `UnsavedChangesStore`, not an
implementation detail of one backend - see the class doc in
`app/lib/unsaved_changes.dart`.

## Torn writes

Bytes are appended first and the metadata record (`UnsavedRecord`, which
carries `length`) is committed second. A crash in the middle of an append
is then indistinguishable from never having started it: recovery reads
exactly `record.length` bytes and gets the previous whole revision. The
native backend commits through a temp file + rename so the commit itself
can't be seen half-written; a record that still tears decodes to null and
is skipped, because half a document is not a recovery.

`unsaved_changes_store_io_test.dart` drives all of this against a real
filesystem (path_provider pointed at a temp dir): it poisons a byte the
store already wrote to *prove* the second pass appended rather than
rewrote, appends junk to simulate a crash mid-append, and checks the
truncate-on-undo path.

## Web

`unsaved_changes_store_web.dart`, IndexedDB, two object stores: `meta`
(id → JSON) and `chunks` (`<id>/<8-digit index>` → bytes). Chunking is
what makes an append an append here - IndexedDB replaces values whole, so
a single-value document would rewrite the entire PDF on every keystroke.
1 MB pieces mean an edit rewrites its tail chunk and nothing else.

IndexedDB can't run under `flutter test`, so the off-by-one-prone part
(`UnsavedChunking`: chunk count, first dirty chunk, short last chunk)
lives platform-free in `unsaved_changes.dart` and is covered there. The
JS interop around it is thin. `flutter build web` is the compile check.

The IDB open/request boilerplate that `pdf_cache_web.dart` had grown is
now shared in `idb_web.dart` (`openIdb` generalized to N stores,
`idbRequest`), used by both web stores.

## Lifecycle

`AutosaveController` (`app/lib/autosave.dart`) holds a record for a
document exactly while it has unsaved work:

- **Starts** on the first edit. `EditorScreen._persistSession` already
  runs at every tab-set mutation, so `syncTracking(_tabs)` hangs off it -
  one hook, ahead of the session-load gate.
- **Ends** on save (`noteSaved` - saving doesn't notify the session, so
  the editor has to say so), on undo back to the last-saved state, on tab
  close, and on a confirmed discard-and-quit (`didRequestAppExit`).
- **Flushes early** on `didChangeAppLifecycleState` - on mobile and the
  web, backgrounding can be the last callback we get.
- Writes are debounced 400 ms, with a 5 s ceiling so a continuous edit
  stream (dragging an annotation) can't defer forever.

So anything found in the store at launch is, by construction, work a
previous run lost. `_recoverUnsavedChanges` runs *before* the session
restore loop, so a recovered document wins over the same file being
reopened flat (the loop already skips paths that are open).

## Gotchas

- **`alwaysAllowSave`.** A recovered document opens at the revision it
  was lost on, so `PdfEditorView` sees no edits of its *own* and disabled
  its Save button - the user couldn't save the very work we just handed
  back. The app knows better (`tab.isDirty` compares against the baseline
  that was actually written to disk), so `alwaysAllowSave` now takes
  `tab.isUnsaved || tab.isDirty`. Caught by the widget test, not by
  reading the code.
- **The undo stack does not survive.** The mirrored bytes are one flat
  chain of incremental updates, so recovery opens a single revision. The
  edits come back; the history behind them does not.
- **`DocumentTab.savedLength` travels in the record**, which is what makes
  the recovered tab come back *dirty* rather than merely open - and what
  points Save back at the original file.
- **iOS backups.** The store sits under Application Support (same place as
  the Recent-pick snapshots), which iOS backs up. Cache would be purgeable
  and defeat the point, so this is the deliberate trade.
- Every store method swallows its own failure. A safety net that throws
  into the editor is worse than no safety net; a full disk or a
  private-mode quota just means that document isn't recoverable.

## Files

`app/lib/unsaved_changes.dart` (record, store contract, chunking,
in-memory store), `unsaved_changes_store{,_io,_web,_stub}.dart`,
`idb_web.dart`, `autosave.dart`; wiring in `editor_screen.dart`, the
`savedLength` seam in `document_tab.dart`. Tests:
`unsaved_changes_test.dart` (controller + chunking),
`unsaved_changes_store_io_test.dart` (real filesystem),
`unsaved_changes_recovery_test.dart` (the editor at launch).
