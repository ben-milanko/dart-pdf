# Live sync in the app (experimental)

This turns on the end-to-end flow from the plan in
`2026-10-28-shared-folder-live-sync.md`. Two people, or one person on two
desktops, open the same PDF from a synced folder (OneDrive or SharePoint,
Google Drive for desktop, iCloud Drive, Dropbox, a network share). Each picks
**Start live sync (experimental)** from the app menu. Each then sees the other
by name in the header and gets the other's annotations within a few seconds.
The folder ends up holding one PDF with everyone's work, never a conflict
copy.

## Pieces

- **`live_sync.dart`.** `LiveSyncSession` (a ChangeNotifier) owns the
  `PdfSharedFolderSyncTransport` and the `PdfEditingSync`, and polls every 2 s.
  It exposes:
  - `status` (connecting / live / offline) and the error behind offline;
  - `peers` (name and device from the presence files);
  - `peerChanges` (join/leave, used for toasts);
  - `isWriter`.

  It only notifies when something visible changes (`_visibleState`). A tick
  every 2 s that rebuilt the header would also keep `pumpAndSettle` from ever
  settling.
- **Writing the PDF back (compaction).** Exactly one session writes the PDF:
  the live peer with the lowest writer id. Writer ids are random, so it's
  effectively a random pick. It writes:
  - after `compactAfter` (10 s) with no local or remote change;
  - on Save;
  - when it closes.

  Every session holds the same merged annotations, so whichever one writes,
  the file carries everyone's work, and a single writer means no conflict
  copies. Two writers can overlap only in the moment a lower id joins and the
  old writer hasn't seen it yet. Because writing needs 10 quiet seconds, that
  overlap is practically never acted on.
- **First participant.** If the sidecar has no op files yet and the document
  has annotations without an /NM, the session runs `ensureAnnotationNames` and
  writes the PDF **before** joining, so everyone starts from the same names.
  A joiner never renames anything.
- **`live_sync_store*.dart`** (conditional export).
  - `FolderSyncStore` is a directory with writes to a temp name followed by a
    rename. The temp names start with `~$`, which OneDrive doesn't upload,
    and `list` skips them.
  - `FolderLiveSyncBackend.sidecarFor` puts the store at
    `<folder>/.<file>.dartpdf-sync`.
  - `requestFolderAccess` covers the sandboxed Mac: the app holds only the
    opened file, so it asks the user to pick the folder in the open panel
    (`getDirectoryPath`, which uses the existing user-selected read-write
    entitlement). That grant lasts for the session and is re-asked next time.
  - Phones and web get the stub (`platformLiveSyncBackend == null`) and the
    menu item isn't shown.
- **`live_sync_chip.dart`.** The header chip shows a spinner and
  "Connecting…", a green dot and "Live", or "Offline" on the error colour,
  plus up to three peer avatars (initials, colour hashed from the writer id)
  and "+N". The tooltip lists names. Tapping it opens a dialog listing
  everyone (with "(you)" and the device name), which device writes the PDF,
  and a Stop button.
- **`editor_screen.dart`.**
  - The `live-sync` menu action (desktop only, hidden read-only) and
    `_toggleLiveSync` / `_stopLiveSync`.
  - Starting saves a dirty tab first, because edits made before joining would
    never reach the others.
  - The display name is the annotation author name, falling back to the host
    name.
  - Save while syncing calls `saveNow()` and shows the toast "Changes synced…"
    instead of overwriting the file.
  - Once the folder holds every change, the tab is `markSaved` (and the
    crash-recovery mirror is told), so closing doesn't prompt.
  - `DocumentTab.dispose` closes the session before disposing the controller.
    Everything in `LiveSyncSession.close()` that touches the controller runs
    before its first await.
  - `EditorScreen.liveSyncBackend` is the test seam.

## Library additions this needed

- `PdfEditingController.pageStructureLocked` + `onPageStructureLocked`.
  `apply` refuses an edit whose `PdfEditImpact.pageStructureChanged` is set.
  The editor has already staged it against the open document's objects, so
  `_discardRefusedEdit` reopens the revision from its bytes instead of
  trusting the in-memory document. Undo and redo refuse to cross a structural
  revision. `PdfEditingSync` sets the lock for its lifetime and restores it
  afterwards. When unlocked, the cost is one boolean check per `apply`.
- `PdfEditingSync` skips a remote upsert whose snapshot equals what the
  document already holds. Without that, reopening a compacted PDF replayed
  the whole log as one revision (and one sealed undo checkpoint) per op.
- `PdfSharedFolderSyncTransport`:
  - `presenceInfo` is written into the presence file, and peers read it back
    as `peerInfo`, re-read only when the file's modified time changes;
  - `errors` reports failures from the background `startPolling` ticks, which
    used to escape as unhandled async errors.

## Tests

- `app/test/live_sync_test.dart` uses a real temp folder on disk:
  - `FolderSyncStore` round-trips and hides temp files;
  - Alice and Bob see each other by name and merge each other's annotations;
  - page edits are refused;
  - exactly one of them writes;
  - the PDF on disk ends up with all three annotations, and the folder holds
    only `Plan.pdf` plus its sidecar;
  - leave/join events fire;
  - a later reader (Carol) lands on the same annotations with no replayed
    revisions;
  - the first session names legacy annotations;
  - an unreachable store reads as offline.
- `app/test/live_sync_ui_test.dart` drives the real `EditorScreen`:
  - menu → chip "Live";
  - a colleague's presence shows her initials and a "joined" toast;
  - her note lands in the open document and ours reaches her;
  - removing a page is refused with a toast;
  - Save syncs;
  - the dialog lists everyone and Stop removes the chip and the lock.

  Gotcha: `await PdfSyncSession.dispose()` never completes inside
  `testWidgets`' fake async, so the test leaves it unawaited.
- `keyboard_availability_test`: the palette's fuzzy "print" now also matches
  "Start live sync (ex**p**e**r**ime**nt**al)", so the "Needs an open
  document" check is `findsWidgets`.

## Known limits (experimental)

- Desktop only. Phones need provider-aware folder access; the web needs an
  API store (Graph, Drive, WebDAV).
- The op log is never pruned. It is replayed (cheaply, thanks to the
  identical-skip) on every open. Checkpoint-and-prune is the next step.
- On a Mac, folder access is asked for each session; persisting it would need
  a folder bookmark.
- When the app quits, up to one poll interval of changes may not have been
  flushed. Closing the tab normally flushes them.
- A joiner that opened the PDF *before* the first participant named its
  annotations still holds the unnamed copies. Reopen the file before turning
  live sync on.
- The writer folds changes into the PDF through the app's normal in-place
  save, which isn't atomic. Someone opening the PDF in another reader at that
  exact moment can see a truncated file, just as with an ordinary Save. The
  e2e test's stand-in writer uses a temp file plus rename because the test
  reads the PDF while it is being written (that race flaked 1 in 3 runs before
  the change).
