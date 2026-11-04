# Live annotation sync through network storage (experimental)

**Goal.** Two people (or one person on two devices) open the same PDF from a
company OneDrive/SharePoint folder, Google Drive, iCloud Drive, Dropbox, an
SMB share or any WebDAV server, and see each other's annotations appear while
both are working. The folder must never end up holding duplicates
("Report (1).pdf", "Report-LAPTOP.pdf") or a file where one person's save
wiped out the other's.

## What already existed

Most of the merge machinery was already in the library. Only the transport
was missing.

- `pdfDiffAnnotations` / `PdfAnnotationStates` (annotation_sync.dart): turns
  an edit into created/modified/removed changes keyed on /NM, each carrying a
  full `PdfAnnotationSnapshot` (appearance included).
- `PdfSyncMessage` + `PdfSyncSession` (sync.dart): Lamport clock,
  last-writer-wins per /NM ordered by `(clock, origin)`. It converges under
  any delivery order, so arrival order and duplicate delivery don't matter.
- `PdfSyncTransport`: the injected seam, until now with only the in-memory
  `PdfLoopbackSyncHub`.
- `PdfEditingController.annotationChanges` / `applyRemoteChange` /
  `ensureAnnotationNames`: the editor side of the same feed.

## Why not "just save the PDF to the shared folder"

A PDF is one file. Each of these providers handles two devices writing one
file the same way: last upload wins, or the loser gets forked into a conflict
copy. OneDrive and SharePoint do real co-authoring only for Office formats,
through Microsoft's own protocol (WOPI/Fluid), which isn't available for a PDF
from a third-party app. Writing the PDF on every edit is therefore exactly
what produces the duplicates and overwrites the user wants to avoid.

## Design: single-writer sidecar log + compaction

```
Contract.pdf                          <- the shared document (written rarely)
.Contract.pdf.dartpdf-sync/           <- sidecar folder (the PdfSyncStore)
  ops.<writer>.<seq>.json             <- immutable batches of PdfSyncMessages
  presence.<writer>.json              <- heartbeat, rewritten by its writer
  checkpoint.<writer>.json            <- (planned) what a compaction folded in
```

**Invariant: every file has exactly one writer.** A writer is one open session
(device id + per-open nonce), so the same user on a laptop and a phone counts
as two writers, and so do two windows on one machine. An op file is created
once and never changed. With no file ever written by two sessions, no provider
has a conflict to resolve, whatever its sync semantics. This is what makes the
design provider-agnostic: it only needs list/read/write/delete on a folder.

**Transport (`PdfSharedFolderSyncTransport`, landed, sync_folder.dart).**
`send` buffers messages and `flush` (debounced, 400 ms default) writes them as
one op file. `poll` lists the folder, reads op files it hasn't seen from other
writers, and emits their messages. The first poll replays the whole history,
which covers late joiners and reopening after a crash. That history includes
this device's earlier sessions, because each of those was a different writer.
Files that are unreadable or truncated (a sync client mid-download) are
retried on the next poll rather than dropped. Presence is judged by the
*store's* modified times against `presenceTimeout`. Pure Dart, no I/O; the
store is injected (`PdfSyncStore`, with `PdfMemorySyncStore` as the
reference). Tests are in `pdf_document/test/sync_folder_test.dart`.

**Compaction (planned).** Folding the log back into the PDF is the one write
to a shared file, so it needs a single writer at a time:

1. Elect the writer deterministically from fresh presence files (the
   lowest writer id among live peers). No lease file is needed, because a
   lease file would itself have two writers.
2. Write only when the log has been quiet for a while (say 30 s), or when the
   last peer leaves or closes.
3. The written PDF records which `(writer, seq)` it folded in, as private
   metadata in the same style as `DartPdfStampTemplate`. Once a writer's
   files appear in a committed checkpoint, that writer deletes its own op
   files. A writer only ever deletes its own files.
4. API stores can write the PDF with a conditional write (Graph and WebDAV
   `If-Match: <eTag>`, Drive `ifMatch`/revision check). A lost race is
   detected before it creates a copy, and the loser just rebases.
5. Folder stores can't do a conditional write, so as a backstop, any
   conflict copy that appears anyway (same `PdfDocumentIdentity`, sibling
   name) is folded in. Ops are idempotent upserts, so this loses nothing.
   The app then offers to remove the copy.

Between compactions, other PDF readers (Acrobat, Edge) see the file as of the
last compaction. Only dart-pdf sessions see the live state. That is the
honest limit of any design that doesn't own the storage protocol.

## Store implementations (planned, app side)

| Store | Platforms | Latency | Notes |
|---|---|---|---|
| Local folder (`dart:io`) | desktop; iOS/Android via the Files/SAF provider | whatever the sync client takes: OneDrive is usually 2-10 s; iCloud can be minutes and is lazy about downloading | works with *every* provider and SMB with zero integration; `Directory.watch` plus a poll fallback (watch events are unreliable on network mounts); write via temp + rename, named `~$...` so OneDrive skips the temp |
| Microsoft Graph | all, web included | ~1-3 s with `/delta` polling | `driveItem` children of the sidecar folder; `If-Match` for the PDF; MSAL sign-in; SharePoint libraries are the same API (`/sites/{id}/drive`) |
| WebDAV | all | per server | `PROPFIND` (Depth 1) for list + `getlastmodified`, PUT/DELETE, `If-Match` on ETags; covers Nextcloud/ownCloud and most NAS units |
| Google Drive API | all | ~1-3 s with `changes.list` | file-name semantics are loose (duplicate names are allowed), so key on file ids |
| iCloud | Apple only | no public REST API | folder store only; use `NSFileCoordinator` + `NSMetadataQuery` to force downloads |

**Recommended first slice: the folder store.** It gives OneDrive, SharePoint
(synced libraries), Google Drive for desktop, iCloud Drive, Dropbox and SMB in
one go with no sign-in, and the app already has security-scoped access to the
PDF's folder on desktop. A Graph store then adds web and phones without a
sync client, and both interoperate because the on-disk protocol is the same.

## Scope limits for the experiment

- **Annotations and comment threads only.** Page reorder/insert/delete,
  content edits, form fills and signing aren't representable as /NM-keyed
  annotation changes. Changes carry a *page index*, so a structural edit
  would scramble every later page. While a document is in a live session,
  those tools should be disabled (or force a "take ownership" compaction
  first).
- Form fields: `pdfDiffAnnotations` skips widgets. Syncing field *values* is
  a separate, simpler LWW keyed on the fully qualified field name.
- Signed PDFs: compaction must be an incremental save so the existing
  signatures stay valid. Certified (DocMDP P=1) documents can't be synced.
- Encrypted PDFs: snapshots are plaintext JSON in the sidecar. Either
  refuse to sync them or encrypt op files with a key derived from the
  document's file key.
- Clock skew only affects presence (`presenceTimeout` is judged on store
  times). The merge uses Lamport clocks, not wall time.
- Pre-existing annotations without /NM: the first session runs
  `ensureAnnotationNames()` and has to compact before anyone else joins.
  Otherwise two peers would mint different names for the same annotation.
  The sidecar's absence is the signal ("I'm first").
- Tombstones: a removed annotation's LWW entry lives only in the log. After
  pruning, a long-offline writer's stale edit could bring the annotation
  back, so the checkpoint has to carry the per-/NM `(clock, origin)` floor.

## Next steps

1. `PdfEditingController` adapter: drive a `PdfSyncTransport` from
   `annotationChanges` / `applyRemoteChange` with the same LWW table as
   `PdfSyncSession`. Extract that table so both can use it.
2. App folder store (`dart:io`, conditional import, stub on web) plus a
   "Live sync (experimental)" toggle per tab, a presence chip and a
   read-only lock for the non-annotation tools.
3. Compaction + checkpoint + conflict-copy folding.
4. Graph store (MSAL, `/delta`, `If-Match`).
