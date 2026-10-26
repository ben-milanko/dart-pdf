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
