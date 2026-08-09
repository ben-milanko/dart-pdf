# Annotation copy/paste across document tabs

Annotation copy/cut/paste already produced fully detached snapshots, but the
clipboard holding them was a private field on `PdfEditingController`, so a
copy only ever pasted back into the tab it was made in. Moved it out to a
process-wide `ChangeNotifier` - the same shape the page and vector-snapshot
clipboards already use - so annotations copied in one open document paste
into another.

## The shared clipboard

`PdfAnnotationSnapshotClipboard`
(`dart_pdf_editor/lib/src/editing/editing_annotation_clipboard.dart`) holds
the copied `PdfAnnotationSnapshot`s plus the bookkeeping the paste cascade
needs:

- `snapshots` / `length` / `isEmpty` / `isNotEmpty` - the payload.
- `sourceOwner` + `sourcePage`, compared through `isSource(owner, page)`.
- `pasteCount`, stepped by `markPasted()`.

`instance` is the process-wide singleton every `PdfEditingController`
defaults to (new `annotationClipboard` constructor arg), so cross-tab paste
needs **zero host wiring** - the app's tabs each build a plain
`PdfEditingController(bytes, preferences: ...)` and share it automatically.
Pass a private clipboard to isolate a session (the tests do).

The controller registers `notifyListeners` on it in the constructor and
removes it in `dispose`, exactly like `pageClipboard` / `snapshotClipboard`,
so every tab's Paste affordance lights up the instant any tab copies.

### Why the name

`pdf_document` already exports `extension PdfAnnotationClipboard on
PdfEditor` (the `pasteAnnotation` half). `dart_pdf_editor` imports
`pdf_document`, so reusing that name would be ambiguous in every file that
sees both. Hence `PdfAnnotationSnapshotClipboard`, which also matches what it
actually holds - `PdfAnnotationSnapshot`s - the way `PdfSnapshotClipboard`
holds a `PdfVectorSnapshot`.

## Cascade across tabs

The old cascade rule was `pageIndex == _clipboardSourcePage`: paste onto the
page you copied from and the first paste already steps 12pt so the copy
doesn't sit exactly on its source. Page 3 of *another* tab's document is not
that page, so the comparison now has to include the owner - hence
`isSource(this, pageIndex)`, an identity check against the controller that
filled the clipboard. Pasting a copy into a different document lands it at
exactly the coordinates it was copied from, which is what you want when
carrying an annotation between two revisions of the same page.

`sourceOwner` is held **only** to compare identity. The source tab may well
have been closed (and its controller disposed) before the paste - nothing
ever reads through the reference. The snapshots themselves are detached
(dictionary and every referenced object, appearance streams included, copied
inline by `_SnapshotCopier`), so they outlive the document they came from;
that part already worked, it just had no way to travel.

`pasteCount` lives on the clipboard rather than the controller so one copy
keeps stepping its cascade wherever it is pasted. `markPasted()` deliberately
does **not** notify: what can be pasted hasn't changed, and the pasting
controller notifies anyway.

## Most-recent-copy-wins, now global

`copySelectedAnnotations` clears `snapshotClipboard` and `copyVectorSnapshot`
clears `annotationClipboard`, so ⌘V always pastes whatever was copied last.
Both clipboards being shared means that rule now holds across tabs too: copy
a region as vector in tab B and tab A's ⌘V stops pasting the annotation it
copied earlier.

## Tests

`editing_clipboard_test.dart` gained two groups: `PdfAnnotationSnapshotClipboard`
(notify semantics, the shared-instance default, private-clipboard isolation)
and `clipboard shared across document tabs` (copy in one controller pastes
into another with no cascade and the right style; the copy notifies the other
tab; repeat pastes cascade; the clipboard outlives `dispose()` of the source
controller; a later copy in either tab replaces the payload everywhere).

Because the clipboard is now process-wide, tests that copy annotations must
start from empty or one test's copy leaks into the next -
`PdfAnnotationSnapshotClipboard.instance.clear()` in `setUp` of
`editing_clipboard_test`, `editing_menu_test`, `editing_longpress_menu_test`,
and `editing_snapshot_test` (the same tax the snapshot clipboard already
pays).
