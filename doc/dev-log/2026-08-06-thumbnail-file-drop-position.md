# Dropping a PDF at a position in the thumbnail strip

Dragging a PDF onto the window already offered *open in a new tab* or
*insert pages* (appended at the end - see
`2026-06-22-app-drag-drop-open-or-insert.md`). This session adds the
placement the dialog can't express: drop the file **between two page
thumbnails** and its pages land exactly there.

## The seam

The platform's drag stream (desktop_drop on desktop/web) lives with the
host app; `dart_pdf_editor` must not depend on it, and the strip is the
only thing that knows where its tiles are. So the two halves meet through
a small controller - `PdfThumbnailDropController`
(`editing/editing_thumbnail_drop.dart`, exported):

- panels register a `PdfThumbnailDropResolver` (`int? Function(Offset
  globalPosition)`) on mount and withdraw it on dispose;
- the host calls `dragOver(globalPosition)` from `onDragEntered`/
  `onDragUpdated`, `endDrag()` when the drag leaves, and `indexAt(...)`
  on drop;
- panels read `indicatorIndexFor(theirResolver)` while building and paint
  an insertion marker at that slot.

The most recently attached panel answers first, so the full-area page
grid overlaid on a still-mounted docked strip wins the area it covers.
Registration identity is `identical`, so each panel keeps its resolver in
a `late final` field - a method tear-off is a fresh object every time
it's read, and attach/detach would disagree.

`pdfThumbnailDropIndexAt` does the geometry for both panels: bound the
point to the panel's own render box, pick the **nearest built tile** by
squared distance to its rect (a scrolled-away tile has no render object,
and gaps/header/footer fall to the closest tile), then take the slot
before or after it depending on which side of its centre the point is -
`dy` for the stacked strip, `dx` for the flowing grid (flipped under
RTL). The result is a slot in `0..pageCount`, i.e. exactly the `at:`
`insertPagesFromBytes` wants.

## Rendering the marker

`_PasteInsertionMarker` became `_InsertionMarker` with an `axis`, so the
same capped bar serves the paste indicator (bottom edge, horizontal) and
the drop indicator (any edge; vertical on the grid). `_PageTile.dropEdge`
carries the edge, computed by `_tileDropEdge`: the marker *leads* the
tile the pages would land before, and *trails* the last tile for a drop
past the end - so it always paints in the gap that will be filled. Keys
are `pdf-thumbnail-drop-indicator-<page>-<edge>`; the panel also outlines
itself (`pdf-thumbnail-drop-outline` /
`pdf-thumbnail-view-drop-outline`).

## App side

`EditorScreen` owns one `PdfThumbnailDropController` and hands it to
`PdfEditorView(thumbnailDropController:)`, which forwards it to the strip
and the grid only when `PdfEditorFeatures.pageEditing` is on. `_onFilesDropped`
now takes the whole `DropDoneDetails`: it reads the slot **before**
`endDrag()` (clearing repaints the geometry away), and a non-null slot
skips the open/insert dialog entirely - the drop point already answered
the question. Multiple files keep their order by advancing the insert
position by each file's page count. While the drag is over a panel the
full-window "Drop PDF to open or insert" hint hides, since the strip's own
marker is more precise.

## Testing

`packages/dart_pdf_editor/test/editing_thumbnail_drop_test.dart` covers
the geometry (top/bottom half of a strip tile, left/right of a grid cell,
past the last tile, off-panel, read-only panels decline) and the
controller (detach clears, most-recent-panel-wins, notify-on-change only).

`app/test/drop_insert_test.dart` gains the app half. One of them reads a
**real file**: unlike the dialog path (whose byte read is triggered by a
UI tap, so it can't be wrapped - see the 2026-06-22 note), the positioned
drop takes no tap, so writing the temp file and delivering the
`performOperation_linux` message inside `tester.runAsync` lets the lazy
`XFile.readAsBytes` actually complete and the insert land. The test then
asserts the strip grew to four tiles. Two caveats: pump the snackbar out
(6 s) so no timer outlives the test, and give the surface a desktop width
- the docked strip collapses on a compact one.
