# Drag pages between windows; undo from the thumbnail panels

## Pages dragged out of the strip move to another window

A reorder drag in `PdfThumbnailSidebar` keeps its pointer captured after it
leaves the window, so moves keep arriving in the source view's coordinates.
The strip wraps its `ReorderableListView` in a `Listener`
(`_trackDragOut`): outside the view's bounds the drag becomes a
`PdfPageDragOut` (source controller + dragged pages: the selection when
the grabbed tile is in it, else that page), reported through
`PdfThumbnailDropController.onPageDragOutside` (null when the pointer
returns). `onReorderEnd` fires synchronously on release, before the drop
animation calls `onReorderItem`, so a release outside hands the drag to
`onPageDropOutside` and sets `_suppressReorder` to swallow the in-strip
reorder that follows.

The `Listener` is always in the tree. The first cut added it only when the
callbacks were set, and a host that wires them after mount then remounted
the list in the middle of a drag (a "RenderPointerListener was mutated in
performLayout" assertion in tests).

App side: `PageDragCoordinator` (`app/lib/page_drag.dart`, owned by
`TabDragCoordinator.pages`, so it reuses the same native cursor locator)
looks up the window under the cursor. Hovering another window calls that
window's `_thumbnailDrop.dragOver`, which paints the file-drop insertion
marker. On release the destination inserts first (at the marked slot, or
after its current page; with nothing editable open the pages become a new
untitled tab), then the source runs `removePages`. That is one undo on
each side. Dragging every page out is a copy, because `removePages`
refuses to empty a document. A drop on the desktop or back on the source
window does nothing.

Only the docked strip does this. The page grid (`PdfThumbnailView`) uses
`Draggable`, which doesn't report drags outside the window this way.

## Ctrl/Cmd+Z in the thumbnail panels

Undo/redo was bound only in `PdfViewer`'s `CallbackShortcuts`. After a paste
from the strip or grid, focus stays in the panel, so Ctrl+Z did nothing.
Both panels now bind undo and redo (`_undoShortcuts`: Cmd/Ctrl+Z,
Cmd/Ctrl+Shift+Z, Ctrl+Y). `PdfEditingController._reopen` (undo/redo) now
also clears the page selection when the reverted revision changed page
structure. Before this, undoing a paste left the selection on pages that no
longer existed.
