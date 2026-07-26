# Mobile cloud progressive open (#364)

Follow-up to #359 / #363. #363 made the *desktop* open path progressive (first
paint from ranged reads, full bytes streamed in behind it). Mobile was gated
off because the win it targets — a big OneDrive/iCloud/Drive file — pays its
whole cloud transport **inside the OS document picker's copy**, before the app
sees a byte or a path, so app-level ranged open can't intercept it:

- **Android** — `file_selector_android` does `contentResolver.openInputStream`
  → `copy(...)` of the entire content URI into `{cacheDir}/{uuid}/{name}`, then
  hands back that local path.
- **iOS** — `file_selector_ios` uses `UIDocumentPickerViewController(... in:
  .import)`, which copies the file into a temp location.

The fix is a *reference* picker + a mobile ranged `PdfByteSource`, wired into
the same `_openProgressive` swap machinery #363 built. Desktop is untouched.

## Design — reuse everything from #363

The whole progressive pipeline (`PdfByteSource` → `PdfDocument.openSource` with
`firstPaintPages: 1` → read-only `DocumentTab.preview` → background
`readSourceFully` → swap to a full `DocumentTab.document`) is origin-agnostic.
The only desktop-specific bits were "build a source from a path" and "read the
whole thing from a path". Those became two seams:

- `_progressiveSource({path, bookmark, token})` and
  `_readOriginFully({path, bookmark, token})` in `editor_screen.dart` pick the
  desktop path source or the new mobile token source.
- `DocumentTab` gained `originToken`, carried through `loading`/`preview`/
  `document` the same way `originBookmark` is, so the preview→document swap and
  the full-read fallback know how to re-read a mobile origin.

`_openProgressive` now takes `path` **or** `token` (asserted exactly one). Every
existing desktop call site is unchanged.

## New pieces

### `PdfMobileByteSource` (`app/lib/pdf_mobile_source.dart`)

The mobile sibling of `PdfBookmarkFileByteSource`: a `PdfByteSource` over an
opaque native **token**, reading ranges through the
`dev.milanko.dartpdf/mobile_file` method channel (`fileLength` / `readRange`).
`PdfCancelToken` + `onProgress` mirror the other sources. A negative native
length is normalized to `null` ("unknown"), so the loader falls back to a
sequential read. No `dart:io`, no conditional import — the channel is only ever
invoked behind a platform guard, so the class compiles everywhere.

### `file_io.dart`

- `MobilePickedPdf { token, name, length, seekable }` — the reference picker's
  result per file.
- `supportsMobileProgressiveOpen` — true on Android/iOS off-web (the mobile
  counterpart of `progressiveOpenSupported`, which stays desktop-only).
- `pickPdfMobileReferences()` — invokes `pickDocuments`; maps the native list to
  descriptors; throws `MissingPluginException` on a runner without the channel
  so the caller falls back to the copy-based `pickPdfFiles`.
- `pdfByteSourceForMobileToken(token)` — the token → source factory.

### Wiring (`_pickAndOpenMobile`)

`_pickAndOpen` branches to `_pickAndOpenMobile` on
`supportsMobileProgressiveOpen`. There, a **single seekable** pick opens
progressively (`_openProgressive(token:)`); a **non-seekable** pick or a
**batch** streams the reference whole via `_readOriginFully(token:)` —
still one read of the original, no OS copy, i.e. never worse than the old path.
On `MissingPluginException` it falls through to the copy-based picker.

### Reopen snapshot

A mobile pick has no reopenable path and the token dies with the pick, so on the
full-read swap (`_swapPreviewToDocument`) — and in the non-seekable/batch and
fallback paths — the now-complete bytes are snapshotted via
`_snapshotOpenedDocument` / the existing `cacheOpenedPdf` store. Recents/session
restore then reopen from the local snapshot (fast, no transport), exactly as a
plain mobile open already did. The first-paint recent add is skipped for a
mobile pick (no reopenable origin yet) and added when the snapshot lands.

## Native handlers

### Android (`MainActivity.kt`)

`dev.milanko.dartpdf/mobile_file`:

- `pickDocuments` → `ACTION_OPEN_DOCUMENT` (`CATEGORY_OPENABLE`, `application/
  pdf`, `EXTRA_ALLOW_MULTIPLE`, **no** `EXTRA_LOCAL_ONLY` so cloud providers
  stay in the list). The async result lands in `onActivityResult`, which
  `takePersistableUriPermission`s each URI and returns
  `{token: uri, name, length, seekable}`. The token is the `content://` URI.
- `probeSeekable` / `fileLength` / `readRange` via
  `contentResolver.openFileDescriptor(uri, "r")` + `Os.lseek`. Reads run on a
  single-thread executor (a multi-MB read must not ANR the platform thread).

**The Android risk, called out in #364:** many cloud providers (incl. OneDrive)
hand SAF a **non-seekable** `ParcelFileDescriptor` (a pipe) — `statSize == -1`,
`lseek` throws `ESPIPE`. `probeSeekable` detects exactly that (statSize check +
a forward/back `lseek`) and returns false, so the app streams the reference
whole instead of attempting random access. **Whether progressive wins on Android
is provider-dependent** — OneDrive was confirmed seekable on-device (see
Verification); other providers remain to be checked and a pipe-returning one
degrades safely to whole-stream.

### iOS (`SceneDelegate.swift`)

`dev.milanko.dartpdf/mobile_file`:

- `pickDocuments` → `UIDocumentPickerViewController` in **`.open`** mode
  (`forOpeningContentTypes: [.pdf]` on iOS 14+, `documentTypes:in:.open` on 13),
  `allowsMultipleSelection`. Each picked URL becomes a base64 **security-scoped
  bookmark** token (`url.bookmarkData()` under
  `startAccessingSecurityScopedResource`).
- `probeSeekable` / `fileLength` / `readRange` resolve the bookmark and do an
  `NSFileCoordinator` coordinated read + `FileHandle` `seek`/`read`, so the File
  Provider serves just the requested range. Reads run off the platform thread on
  a serial queue. iOS coordinated ranged reads are more likely to work than
  Android SAF (the issue's assessment), but this is still on-device territory.

## Verification

- **CI (done):** `pdf_mobile_source_test.dart` covers the source (length,
  ranged slice, progress, cancel, unknown-length, `openSource`) and
  `pickPdfMobileReferences` / `supportsMobileProgressiveOpen` against a mocked
  channel. `mobile_progressive_open_test.dart` drives the whole pick → first
  paint → full-read swap end-to-end on an Android platform override with the
  native channel mocked to serve a real PDF by range. Full app suite green.
- **On-device (native handlers can't run in CI/desktop):** per #364's
  acceptance criteria —
  1. **Android + OneDrive — CONFIRMED (2026-07-19, release build, devtools
     traces).** The de-risking gamble — does SAF's `openFileDescriptor` hand
     back a **seekable** FD for a mainstream cloud provider? — is met for
     OneDrive. Evidence, not inference: `rangeRequests` / `rangeBytesFetched`
     are emitted only by the ranged source (0 on the old copy path), and were
     non-zero on `platform: android`, so `PdfMobileByteSource` is the code path.
     `rangeBytesFetched: 444 KB` across three OneDrive files of 58 / 21 / 36 MB
     (`rangeRequests: 122`) — ~1% of a single 36 MB file, i.e. the sparse
     seekable `_fetch` path; a non-seekable pipe would have streamed ~115 MB via
     `_downloadFully`. Progressive swap confirmed per document (e.g. 107-page
     first paint, then `full read complete — 36,383,879 bytes` ~636 ms later),
     and `objectRescueScanBuilt: 1` shows xref recovery still works over the
     ranged source. So Android progressive is viable — **not** iOS-only.
  2. **iOS — pending:** verify a coordinated ranged read paints a large
     iCloud/OneDrive PDF before the whole file downloads (not yet exercised).
  3. **Other providers — pending:** only OneDrive confirmed; Google Drive /
     iCloud outstanding. A pipe-returning provider degrades to whole-stream
     (correct, no win) via `probeSeekable`.
  4. **Speedup magnitude — pending:** the traces prove progressive *works* and
     fetches ~1% for first paint, but not (no A/B yet) that first paint is
     *faster* than the old copy path.

The design is fail-safe by construction: a missing channel, a cancelled pick, a
non-seekable provider, or any first-paint failure all fall back to a whole read
(or the copy-based picker), so nothing a plain mobile open handled can regress —
the only variable is whether the first-paint speedup materializes per provider.
