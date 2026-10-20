# Warn, don't block, when a document's file has gone away

A file that was moved, renamed or deleted since the app last saw it used to
fail in one of two unhelpful ways. Both now surface a non-blocking warning
toast and carry on.

- **Session restore** (`EditorScreen._restoreSession`) dropped such documents
  *silently*. Snapshot restores now report failure from
  `_reopenSessionDocument` (returns `bool`), the restore loop collects the
  titles and `_warnFilesUnavailable` shows one toast for the batch
  (`editorReopenFilesUnavailable`, ICU plural: names the file when there is
  one, counts them otherwise) a frame later. Path-only tabs
  (`DocumentTab.deferredPath`) read nothing until first shown, so their
  failure surfaces then, through `_materializeDeferredPath`'s `onOpenFailed`,
  with the same warning. The rest of the session is never held up, and the
  dropped tab still closes rather than leaving an error tab.
- **In-place Save** to an origin whose folder has gone away fell back to
  Save As but swallowed the reason (the failed `SaveResult` was overwritten),
  so a cancelled dialog said nothing at all. `_save` now logs the failure and
  toasts `editorSaveOriginUnavailable` before offering Save As; the edits stay
  in the open tab either way. (A moved file whose folder still exists simply
  gets re-created by the write, as before.)

Recents already toasted `editorCouldNotReopen` and drop the stale entry -
unchanged.

Tests: `progressive_open_test.dart` (restored missing file now warns),
`save_shortcuts_test.dart` (failed in-place save warns and offers Save As).
Snackbar note: a toast that replaces another needs ~a frame of animation
before `find.text` sees it - pump a few hundred ms.
