# Snapshot PDF interchange and desktop clipboard (#168)

Completed against current main on 2026-09-06. The shared snapshot clipboard
had already landed in main: controllers use `PdfSnapshotClipboard.instance`
by default, with an injectable private clipboard when isolation is needed.
This completion preserves that API and the per-document captured-form cache.

## Portable PDF API

- `PdfVectorSnapshot.toPdfBytes()` writes one page sized to the captured
  region, with its display rotation baked into content. Nested streams are
  indirect objects, resource number precision is retained, and source images
  keep their encoding. Exporting does not mutate the detached snapshot.
- `PdfVectorSnapshot.fromPdfBytes(bytes, password: ...)` captures the first
  page's crop box. Zero-page, unreadable, or empty-sized inputs are rejected.
- `PdfSnapshot.pdfBytes` exposes export on the Snapshot handler payload.
- `PdfEditingController.pasteSnapshotBytes` imports and pastes one editable
  vector Stamp in one undo step. Invalid input or a missing destination leaves
  the document and clipboards alone. Repeat imports reuse the captured form.

The capture retains the source page content behind a region clip; it is not
redaction. It captures page content, not separate annotation appearances.

## Desktop clipboard

The app's existing method channel now offers PDF and PNG in one update:

| Platform | PDF representation | Image fallback |
| --- | --- | --- |
| macOS | AppKit `.pdf` (`com.adobe.pdf`) | `.png` |
| Windows | `application/pdf`, `Portable Document Format` | PNG, DIBV5 |
| Linux | GTK `application/pdf` selection target | `image/png` |

Native ownership tracking ignores this process's own snapshot write, so
cross-tab Paste uses the original detached snapshot and its reuse/cascade
bookkeeping. `PdfClipboardPdf.changeToken` carries the native clipboard
revision; once that revision has been pasted it yields to subsequent local
copies. A new external revision wins even when its PDF bytes are identical.
`systemPdfPasteProvider` is forwarded through both editor-shell constructors
and split panes. Keyboard and context-menu Paste read PDF before local
annotations/snapshots, then image/text fallback. Merely opening a context menu
does not access the system clipboard. Pending PDF reads are discarded when
the destination viewer closes, changes sessions, or moves to another revision.
Web and mobile retain their PNG clipboard transport.

## Interoperability limit

PDF clipboard exchange works with applications that offer/accept the PDF
formats above. Bluebeam-specific vector exchange is **not verified**. The
original PR's universal Bluebeam claim was too strong: [Bluebeam's Snapshot
documentation](https://support.bluebeam.com/user-manual/menus/edit/snapshot.html)
describes raster output when pasting into other applications. PNG fallback is
retained for consumers that do not accept PDF data.

## Validation

Snapshot serialization, rotation, resources, invalid input, encryption,
controller undo/shared-clipboard behavior, keyboard/menu paste precedence,
app wiring, and tab regressions are covered by Dart/Flutter tests.
`app/tool/test_snapshot_clipboard.swift` exercises real AppKit PDF/PNG transfer
and ownership changes on a private pasteboard, without altering the user's
clipboard. CI runs it on macOS and builds the desktop runners.
