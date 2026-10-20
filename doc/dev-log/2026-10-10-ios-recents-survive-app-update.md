# iOS Recents survive an app update

**Symptom:** after updating the iOS app, every Recent entry on the welcome
screen read "Pick again to reopen" and the last session didn't restore.

**Cause:** mobile picks reopen from a private snapshot
(`pdf_cache_io.dart`, `<support dir>/recent_pdfs/<content hash>.pdf`), and the
Recent/session/unsaved-changes records stored that snapshot's **absolute
path**. iOS moves the app's data container to a new
`.../Data/Application/<UUID>/` on every update: the files come along, the old
paths don't resolve. Worse, `pruneCachedPdfs` compared full paths against the
stale keys, so the first prune after an update **deleted every snapshot**.

**Fix:**
- `resolveCachedPdfKey` (io/web/stub) re-anchors a key on the snapshot's file
  name under today's store; `RecentsStore.load` and `SessionStore.load` run
  every snapshot key through it (injectable `CachedPdfKeyResolver` for tests)
  and persist the rebased paths. An entry already marked missing becomes
  reopenable again if its file is still there. Crash recovery re-anchors the
  recovered tab's `cachePath` the same way (its own store already resolves
  its directory at runtime).
- `pruneCachedPdfs` matches by file name, so a stale key can no longer delete
  the snapshot it names.

Snapshots already pruned by an earlier build are gone; those entries still need
one re-pick. Tests: `test/pdf_cache_io_test.dart` (fake container move), plus
rebase cases in `recents_test.dart` / `session_store_test.dart`.

**Not done (option):** iOS reference picks already hold a security-scoped
bookmark (`MobilePickedPdf.token`), which survives updates and evicted
snapshots; persisting it on the Recent entry would let reopen fall back to the
original file. Android's persisted `content://` grant is the equivalent.
