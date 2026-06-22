# App drag-and-drop: open or insert

The `/app` already wrapped its editor body in a `desktop_drop`
`DropTarget` (`app/lib/editor_screen.dart`) that opened every dropped PDF
in a new tab. This session adds the second behavior the drop should offer
— inserting the dropped pages into the document that's already open.

## What changed

`_onFilesDropped` now:

1. Filters the dropped items to `.pdf` names up front.
2. If there's an active, editable session (`tab.session != null` and not
   read-only), shows `_promptDropAction` — an `AlertDialog`
   (`ValueKey('drop-action-dialog')`) offering **Open in new tab(s)** /
   **Insert pages** / Cancel.
3. On *insert*, `_insertDropped` reads each PDF and calls
   `PdfEditingController.insertPagesFromBytes` (appends, one undoable step
   per file), reporting the result via a toast.
4. On *open* (or with nothing open / in read-only mode), `_openDropped`
   keeps the original per-file new-tab behavior.

`_DropOverlay` gained a `canInsert` flag so the drag hint reads
"Drop PDF to open or insert" when an editable document is open.

## Testing gotchas (widget test of an OS drop)

`app/test/drop_insert_test.dart` drives the `desktop_drop` channel
directly (`performOperation_linux` with a path + centre-of-surface
offset; `DropTarget` only fires `onDragDone` for an in-bounds point, and
its Linux branch fires even without a prior `entered`). Two traps:

- **No real file I/O.** `File.writeAsBytes`/`XFile.readAsBytes` return
  real-event-loop Futures that never complete under the widget tester's
  fake clock, so awaiting them hangs the test to its timeout. The drop
  only needs a *path* (bytes are read lazily, later), so the test passes a
  synthetic `/dartpdf-test/<name>.pdf` and never touches disk. It asserts
  the synchronous branch effects instead: the dialog appears; the *open*
  branch adds a loading tab (added before the byte read) so the title
  shows in the tab strip; the *insert* branch adds no tab. The actual page
  copy is covered by the editor package's `insertPagesFrom*` tests.
- **Dialog dismiss needs time.** After tapping a dialog action, pump past
  the ~200 ms route-pop transition (the test pumps 350 ms) before
  asserting the dialog is gone. `pumpAndSettle` is unusable here because
  the open branch's loading spinner animates forever.
