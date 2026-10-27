# Loading feedback for a mobile cloud pick

**Symptom.** Opening a OneDrive (or other cloud) PDF on a phone/tablet: the
picker closed and nothing changed for ~30 s until the document appeared.

**Cause.** The reference picker's reply (`pickDocuments` on the
`dev.milanko.dartpdf/mobile_file` channel) described each pick *before*
replying, and the description touched content:

- Android `describeOpenedDocument` called `fileLength` and `probeSeekable`,
  each `openFileDescriptor(uri, "r")`. OneDrive's DocumentsProvider downloads
  the whole file before it hands over an FD.
- iOS `describePickedURL` called `probeSeekableURL`, an `NSFileCoordinator`
  read with no options, which makes a File Provider materialize the whole file.

Dart only puts up the loading tab (`_openLoadingBatch`) once that reply lands,
so the full download ran with no UI.

**Fix.** The pick reply is metadata only (Android: `OpenableColumns.SIZE` via
the new `declaredLength`; iOS: `fileSizeKey` as before) and omits `seekable`.
`MobilePickedPdf.seekable` is now `bool?`; `_pickAndOpenMobile` puts the
placeholders up first, then asks `probeMobileSeekable` (the existing
`probeSeekable` method) for a single pick. A batch never opens progressively,
so it skips the probe. An older runner that still sends `seekable` keeps
working unchanged.

The download still happens - the probe now pays it behind the "Opening …"
spinner. Note that iOS `readRange` also coordinates without options, so on iOS
the first ranged read likely materializes the whole file too; progressive
open buys little there until reads use a byte-range-friendly path.

Test: `mobile_progressive_open_test.dart` holds the probe open and asserts the
loading tab is already showing.

## Web and desktop

**Web** had the same shape. `pickInMemoryFilesWeb` (web_file_picker.dart)
awaited `File.arrayBuffer()` for every picked file before completing, so a
file in a cloud-synced or network folder read in full before the app saw the
pick. It now completes on `change` with `PickedWebFile`s: an `XFile` over the
browser `web.File` whose name/type/size come from metadata and whose bytes are
read on the first `readAsBytes()` (still `arrayBuffer()`, never the `blob:`
XHR that hangs under COEP - see 2026-07-19-web-pick-coep-hang.md), memoized,
with a failed read left retryable. `_openPickedFile` already sizes the file
with `length()` and reads behind the placeholder. Browser test:
`test/web/web_file_picker_test.dart` (in CI's chrome step).

**Desktop** needed nothing in Dart: `_pickAndOpen` puts the loading tabs up
(`_openLoadingBatch`) before any stat, bookmark or read, all of which are
async - pinned by session_restore_test's "a multi-file pick shows every
placeholder before any file is read". macOS runner file access runs on
`FileAccessExecutor`'s background queue. The one stall left is outside the
app: if the OS dialog itself downloads a cloud file before returning (macOS
NSOpenPanel does this for dataless iCloud items, with its own progress UI).
