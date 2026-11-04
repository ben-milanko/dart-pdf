# Document library: the tab set's stores behind ports (#1204)

Second half of #1204, after `DocumentTabs` (#1241). `app/lib/document_library.dart`
owns what the open tabs persist to, so `EditorScreen` no longer carries it.

- **Ports.** `SessionPersistence` (in session_store.dart, implemented by
  `SessionStore`), `RecentsLog` (in recents.dart, implemented by
  `RecentsStore`) and `PdfSnapshotStore` (`PlatformPdfSnapshots` over
  pdf_cache.dart). `UnsavedChangesStore` was already a port. `EditorScreen`
  takes `sessionStore:` / `pdfSnapshots:` overrides like `unsavedChangesStore:`.
- **Every tab change persists.** `DocumentLibrary` listens to `DocumentTabs`
  itself: `onTabsChanged` (the autosave mirror's `syncTracking`) runs first and
  ahead of the session-load gate, then the restore list is saved through
  `sessionDocumentsOf`, a pure function.
- **One recording rule.** `recentRecordingFor` decides "record now" versus
  "snapshot, then record". The open, whole-file, preview-swap and rename
  sites used to spell it four ways. `recordOpened` and `snapshotIfUnbacked` apply it,
  and snapshot writes stay serialized against prunes (`_cacheWork`), as
  `_recentCacheWork` did. Thumbnail retention hangs off `onPruned`.
- **Metadata in one place.** `DocumentTab.promoted`, `.fromHandoff` and
  `.recovered` are the only places that carry origin, snapshot and save baseline from one
  tab shape to the next.
- **Nothing starts from build.** `_advanceActiveTab` (run on every tab change,
  and once restore ends) materializes a deferred or path-only tab and runs the
  auto-OCR check. Gotcha: the old build-time kick usually missed a restored
  deferred tab's brief moment as the active one, because the next restored tab
  replaced it before a frame. The eager trigger would parse every restored
  tab, so deferred opens are now held while `_restoringSession` like
  path-only ones (session_restore_test caught it).

Tests: `app/test/document_library_test.dart` (fake session, recents and
snapshot stores; no `EditorScreen`).
