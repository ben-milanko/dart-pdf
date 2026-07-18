# Progressive local-file open (#359)

Opens the app's own file path through the ranged byte-source API (#325/#328)
so a big cloud-synced document paints in ~1-2 s instead of stalling on tens of
seconds of pure byte transport. Three parts.

## 1. `PdfFileByteSource` — the missing local half

`PdfByteSource`/`CosDocument.openSource`/`PdfHttpByteSource` (PR #328) gave the
parser a random-access, ranged source, but the only concrete source was HTTP.
The app's open path still `readAsBytes`'d the whole file first. #359 adds the
local-file source.

`dart:io`'s `RandomAccessFile` can't live in any package `lib/` (web + layering
rules), so the sources live in the app:

- `app/lib/pdf_file_source_io.dart` — `PdfFileByteSource` over one
  `RandomAccessFile`. Reads are serialized on the shared handle (a RAF has one
  cursor) via a `Future`-chain mutex, which still satisfies the concurrency
  contract. `PdfCancelToken` + `onProgress` mirror `PdfHttpByteSource`.
- `app/lib/pdf_file_source_stub.dart` + `pdf_file_source.dart` — web stub +
  conditional-export facade (throws if ever used; web opens never take a path).
- `app/lib/pdf_bookmark_source.dart` — `PdfBookmarkFileByteSource` for sandboxed
  macOS. The app is sandboxed (`com.apple.security.app-sandbox`); a file
  reopened across launches (OneDrive/iCloud) needs its security scope
  reactivated from a bookmark, which a raw RAF can't do. This source reads
  ranges through a new native `readFileRange` method (see below).

Factory + helpers in `file_io.dart`:
- `pdfByteSourceForPath(path, {bookmark})` picks the bookmark source on
  sandboxed macOS, else the RAF source.
- `progressiveOpenSupported(path)` gates it to desktop with a real path. Web
  has no filesystem. **Mobile is a real gap, not "already in memory":** you can
  pick a OneDrive/iCloud file on a phone, but `file_selector` hands us a *copy*
  — `file_selector_android`'s `getPathFromCopyOfFileFromUri` streams the whole
  content URI into `{cacheDir}/{uuid}/` at pick time, and `file_selector_ios`
  uses `UIDocumentPickerViewController(in: .import)`, which copies too. So the
  full cloud transport is paid inside the OS picker, before the app sees a byte
  or a path; app-level ranged open can't intercept it. Making mobile progressive
  needs a custom picker (Android `ACTION_OPEN_DOCUMENT` keeping the content Uri;
  iOS `.open` + a security-scoped URL) plus native ranged reads
  (`ContentResolver.openFileDescriptor` — often non-seekable for cloud
  providers; iOS `NSFileCoordinator` + `FileHandle`) — a separate,
  provider-dependent effort, tracked in #364. Mobile *reopens* already read the
  local snapshot (`cacheOpenedPdf`), so only the first pick pays cloud transport.
- `readSourceFully(source, {onProgress})` reassembles the **complete**
  contiguous buffer with progress — unlike the sparse buffer `openSource`
  assembles (zeros in the free space the parser never reads), this is what the
  edit session, signing, and the render workers need.

Native (macOS runner, `MainFlutterWindow.swift`): `fileLength` and
`readFileRange(bookmark, offset, length)` reactivate the security scope per
call (no leaked handle/scope), so the loader pulls only the ranges it needs
from a cloud-synced file. Deployment target is 10.15, so it uses the classic
`FileHandle` seek/readData API (no `read(upToCount:)` availability guard).

## 2. First paint from ranges, full bytes behind it

The whole editing model needs the complete contiguous buffer synchronously
(`PdfEditingController(bytes)` → `PdfDocument.open`; grow-only buffer; signing
over full ranges). So progressive open can't hand the sparse buffer to the edit
session — it renders it **read-only** for the first paint, then swaps to a real
session once the full read lands.

New tab kind `DocumentTab.preview` (`document_tab.dart`): a read-only
`PdfDocument` from `PdfDocument.openSource`, its sparse bytes, a `progress`
notifier and a `PdfCancelToken`. `EditorScreen`:

- `_openProgressive` opens the source, `await`s the ranged first paint, shows a
  `_ProgressivePreview` (a `PdfReader` over the sparse bytes + a slim
  `LinearProgressIndicator` for the background read), records the recent, then
  `unawaited`s `_finishProgressive`.
- `_finishProgressive` runs `readSourceFully` (feeding `progress`), then
  `_swapPreviewToDocument` replaces the preview with a full
  `DocumentTab.document` **in place** (same `documentId` → viewport/search
  memory carries across the swap, like the deferred→document swap already does).
- Failure of the first paint falls back to the plain `readPdfAtPath` full read
  (`_fallbackFullOpen`), so nothing a normal open handles regresses; a failed
  background read falls back too, else surfaces an error tab.
- Save / Digitally sign are gated on `tab.session != null` throughout, so they
  stay disabled during the read-only preview and light up only after the swap —
  exactly the issue's "queue until full bytes" requirement, for free.

Wired into the single-file desktop paths: `_pickAndOpen` (1 file),
`_openIncoming` (path), `_openDropped` (1 file), `_openRecent` (desktop
origin). Batch opens keep the deferred whole-file path so the picker doesn't
fan out many concurrent streams.

**Session restore is lazy *and* progressive.** A new `DocumentTab.deferredPath`
holds only a path - no bytes read at launch. Restore probes each desktop file's
length (cheap metadata, no content read / cloud hydration) so a moved/deleted
file is still dropped silently, then adds a path-only tab. When a
`deferredPath` tab is first shown it opens progressively in place
(`_materializeDeferredPath` → `_openProgressive(into:)`). A `_restoringSession`
flag suppresses materialization while the tabs are being re-added (each is
briefly the active one mid-loop), so only the tab left active when restore
finishes opens - the rest read nothing until visited. This kills the old
"every restored tab reads its whole file at launch" cost (`_reopenSessionDocument`
used to `await readPdfAtPath` the full bytes for each). Mobile/snapshot restore
keeps the existing read-bytes-then-defer-parse path (`progressiveOpenSupported`
is false there).

Milestones are logged to the **F12 devtools** log
(`AppDevTools.instance.addLog`), and the whole ranged fetch is already timed by
`PdfPerfPhase.sourceFetch` — enable the panel's perf-log toggle to see it.

## 3. Fewer worker byte copies

`PdfPooledRenderWorker` made one defensive `Uint8List.fromList` snapshot of the
document and seeded every worker from it; each isolate then materializes its own
copy (unavoidable). On a 179 MB doc across a pool that snapshot is another full
copy per worker generation. Added `copySource` (default true, public contract
unchanged); `startPdfRenderWorker` and `PdfRenderWorker.start`/`_backend` pass
`false` because their bytes never change under the worker (the edit session's
grow-only buffer is replaced, not mutated in place; the reader/preview bytes are
read-only). The pool then adds **zero** source-byte copies of its own beyond
each isolate's unavoidable materialization. The bigger win — a shared-source
model where isolates read ranges instead of holding the whole buffer — is left
as a follow-up.

Snapshot-behind-first-paint (the issue's third note) needs no change: the
`cacheOpenedPdf` snapshot is mobile-only and progressive open is desktop-only,
so they don't intersect; the mobile snapshot already runs `unawaited` off the
open hot path.

## Tests

- `app/test/pdf_file_source_test.dart` — ranged reads, past-EOF clamp/short
  read, progress, cancellation, concurrent reads, `readSourceFully` exactness,
  and an end-to-end `PdfDocument.openSource` over a real temp file.
- `app/test/progressive_open_test.dart` — a desktop path-open (platform forced
  to Linux → RAF source) first-paints and swaps to a `PdfEditorView`, with the
  devtools milestones logged.
- `render_worker_test.dart` — `copySource: false` seeds workers directly from
  the caller buffer (no snapshot).

## Gotchas

- `debugDefaultTargetPlatformOverride` must be reset **inside** the test body
  (try/finally), not in tearDown — the foundation-var invariant check runs
  before tearDown.
- The progressive first paint renders `doc.cos.bytes` (the sparse buffer). It's
  a full-length `Uint8List` with zeros in free space; the renderer only touches
  live objects, so it paints correctly, but it must never reach the edit session
  or signing — hence the separate `readSourceFully` complete read.
