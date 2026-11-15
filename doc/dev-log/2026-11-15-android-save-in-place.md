# Android: Save writes back into the picked PDF (#1304)

Before this, an Android edit could only leave the app through the share
sheet: the header button was "Share", and updating the original meant
exporting a copy and replacing the file by hand. Now a PDF opened through the
in-app picker saves straight back into that file when its provider allows it.

## How it works

- **Grant at pick time.** `MainActivity.launchOpenDocument` already used
  `ACTION_OPEN_DOCUMENT` (the #364 reference picker). It now also asks for
  `FLAG_GRANT_WRITE_URI_PERMISSION | FLAG_GRANT_PERSISTABLE_URI_PERMISSION`,
  and `describeOpenedDocument` persists read+write (falling back to read
  alone). It reports `writable` only when a *persisted* write grant is held
  **and** the document's `COLUMN_FLAGS` carry `FLAG_SUPPORTS_WRITE`
  (`canWriteBack`, a metadata query that never opens the file).
- **Write.** New `writeUri` channel method (`writeWhole`): a truncating
  descriptor (`rwt`) plus an explicit `ftruncate` (some providers ignore the
  `t`, and a longer old tail would leave a stale `startxref` that readers
  follow), then `sync`. Pipe-only providers fall back to
  `openOutputStream(uri, "wt")`. `SecurityException` comes back as
  `permission_denied`.
- **Dart model.** `DocumentTab.originUri` is the save destination, separate
  from `originToken` (which only serves the progressive first paint and is
  still dropped on promotion). It's set on the loading placeholder in
  `_pickAndOpenMobile` and handed on in **one place**:
  `_replaceLoadingTab` does `replacement.originUri ??= loading.originUri`.
  That covers progressive, whole-read, deferred-batch and fallback opens
  without threading a parameter through each one. `DocumentTab.promoted`
  carries it, and an XDP conversion clears it so a PDF is never written over
  the `.xdp`.
- **Save.** `_save` picks `_inPlaceUriOf(tab)` first, then `saveBytesToMobileUri`.
  A failure follows the desktop pattern: toast `editorSaveOriginUnavailable`,
  then Save As (the share sheet). On success it re-snapshots the bytes
  (`_library.snapshot`), so the private copy that Recent/restore fall back to
  is the saved revision, not the one first opened.
- **UI.** `_savesByShare(tab)` decides the header button. A writable tab shows
  Save (`Icons.save_alt`, default label), and the compact app bar's button is
  enabled only when there is something to save. The menu's Share entry stops
  being hidden for such a tab, so sharing a copy is still one tap away. Tap to
  rename the title is off for these tabs, because renaming the tab wouldn't
  rename the file.
- **Persistence.** `originUri` is stored as `'w'` on `SessionDocument`,
  `RecentFile` and `UnsavedRecord`. `RecentFile.id` is now
  `path ?? uri ?? cachePath ?? title`, because each in-place save re-takes the
  content-addressed snapshot under a new key and would otherwise duplicate the
  entry.
- **Reopen reads the file, not the snapshot.** `_readReopened` (session
  restore, Recent files, open-in-new-window) reads the Uri first via the
  existing `readUri` method, and uses the snapshot only if that fails. If it
  reopened from a stale snapshot, the next Save would overwrite edits another
  app made in the meantime.

## Seams and tests

`EditorScreen.saveDocumentToUri` / `readDocumentUri` (setting the first also
enables in-place mobile saves on a test host).
`app/test/mobile_in_place_save_test.dart` drives the real pick → edit → Save
flow with the `mobile_file` channel mocked: progressive and whole-read
writable picks write the session bytes to the Uri, a read-only pick still
shares, a refused write falls back to sharing, and a restored session re-reads
the file (which has changed since its snapshot) and saves back into it. JSON
round-trips are covered in `session_store_test` / `recents_test` /
`unsaved_changes_test`.

## Not done / follow-ups

- **Native side unverified here.** There's no Android SDK in the container,
  so the Kotlin changes were neither compiled nor run on a device. Check them
  against local storage, Google Drive and OneDrive providers.
- Only files opened through the in-app picker save in place. A PDF opened
  from a file manager's "Open with" (`ACTION_VIEW`, `IncomingPdfHandler`)
  arrives with a temporary read-only grant, so it still shares. Supporting it
  would need `ACTION_EDIT` handling or a "Save to original…" re-pick.
- An Android Save As that writes to a chosen location
  (`ACTION_CREATE_DOCUMENT`, with the tab adopting the new Uri) and an
  optional autosave-to-original setting were both asked for in the issue and
  are left for later. Crash recovery already mirrors unsaved edits.
- iOS keeps sharing. A `.open`-mode security-scoped URL could be written the
  same way.
- Files picked before this change hold only a read grant, so they keep
  sharing until they are re-picked.
