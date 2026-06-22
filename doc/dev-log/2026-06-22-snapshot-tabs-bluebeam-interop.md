# Snapshot copy/paste between tabs + Bluebeam interchange

Two asks: let the Snapshot tool's captured region move **between open
tabs**, and make snapshots **interoperate with Bluebeam** (paste our
snapshot into Bluebeam as vectors, and import one copied out of it).

## What shipped

### A portable interchange for `PdfVectorSnapshot` (pdf_document)

The snapshot already detaches a page region as inline vector graphics
(`vector_snapshot.dart`), but it lived only in memory. Added:

- `PdfVectorSnapshot.toPdfBytes()` — serializes the snapshot as a
  self-contained **single-page PDF** whose page *is* the captured region
  (MediaBox `[0 0 displayWidth displayHeight]`, /Rotate already baked into
  the content, resources hoisted to indirect objects). Built with
  `CosDocumentBuilder` (pdf_cos's from-scratch writer). This is the same
  shape Bluebeam's Snapshot exchanges — a small PDF of the region — so the
  bytes paste into Bluebeam as vectors. Hosts put them on the OS clipboard
  as `application/pdf`.
- `PdfVectorSnapshot.fromPdfBytes(bytes)` — re-imports one: opens the PDF
  and captures the whole first page's crop box as a snapshot (so a region
  copied out of Bluebeam, or any single-page PDF, round-trips back in).
- `_hoistBuilderStreams` — the `CosDocumentBuilder` counterpart of the
  updater's `_hoistStreams` (inline streams in /Resources must become
  indirect objects, §7.3.8, before the page references them).

Round-trip is covered in `vector_snapshot_test.dart` (toPdfBytes writes a
one-page PDF sized to the region; fromPdfBytes re-imports and pastes the
captured vectors).

### Snapshot clipboard shared across sessions (dart_pdf_editor)

Each tab owns its own `PdfEditingController`, and the snapshot clipboard
was a private field on it — so a region copied in one tab was invisible to
the next. Introduced `PdfSnapshotClipboard` (a tiny `ChangeNotifier`
holding the current `PdfVectorSnapshot?`), mirroring how `preferences`
are injected:

- `PdfEditingController(..., PdfSnapshotClipboard? snapshotClipboard)`.
  Passed one → shares it; omitted → keeps a private one (single-document
  hosts and every existing test need no change). The controller listens to
  it and re-notifies, so a copy in tab A lights up tab B's paste
  affordance. Only a *private* clipboard is disposed with the controller.
- Per-document bookkeeping (`_snapshotCapturedRef`, `_snapshotPasteCount`)
  stays local; `pasteSnapshot` resets it when the shared clipboard has
  moved to a snapshot this session hasn't pasted (`_lastPastedSnapshot`)
  — otherwise tab B would reuse tab A's captured-form object number, which
  doesn't exist in tab B's document.
- `pasteSnapshotBytes(pdfBytes, page, {at})` — imports an interchange PDF
  (e.g. read off the OS clipboard from us or Bluebeam) onto the clipboard
  and pastes it. The import primitive for the cross-application direction.
- `PdfSnapshot.pdfBytes` getter exposes `vector.toPdfBytes()` on the
  handler payload so `PdfViewer.onSnapshot` hosts can write it to the OS
  clipboard.

### App wiring (app/)

`EditorScreen` owns one `PdfSnapshotClipboard` (like `_prefs`) and passes
it to every `DocumentTab.document(...)`, so snapshots copy/paste between
tabs end-to-end. (The Snapshot tool fills the vector clipboard on drag
regardless of an `onSnapshot` handler, so cross-tab paste works in the app
today.)

## Left for the host

Writing/reading the actual OS clipboard in **binary** (`application/pdf`
on macOS/Windows/X11) needs a platform clipboard plugin — Flutter's
framework `Clipboard` is text-only, and `lib/` is `dart:io`-free. The
library now produces/consumes the interchange bytes (`pdfBytes` /
`pasteSnapshotBytes`); the app's last-mile OS-clipboard transport for
true Bluebeam exchange is a follow-up that adds such a plugin.
