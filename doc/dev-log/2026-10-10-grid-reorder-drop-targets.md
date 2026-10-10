# Page grid: visible drop targets for reorder drags

The page grid (`PdfThumbnailView`) used to give each cell its own
`DragTarget<int>`, framing the hovered cell. The frame did not say where the
page would go (before or after that cell depended on the drag direction,
because `movePage(from, to)` takes a destination *index*), and the 12px gaps
between cells accepted nothing.

Now the grid's whole scrolling area is one `DragTarget` (`_reorderTarget`).
`onMove` resolves the pointer to an insertion *slot* with the same
`pdfThumbnailDropIndexAt` the external-file drop uses, and paints the same
`_InsertionMarker` bar via `_PageTile.dropEdge`. The drop calls the new
`PdfEditingController.movePageToSlot(from, slot)`: a slot names one gap
whatever direction the pages move, and a multi-page selection lands as a
block in it.

Gotchas:
- Where a row wraps, one slot has two ends (end of one row, start of the next).
  `_reorderMarkAt` puts the bar on whichever cell edge is nearer the pointer,
  so it never jumps to the other side of the grid.
- `pageSlotMoves` hides the bar over gaps that would not change the order (the
  gaps beside the dragged page, or inside a contiguous selection).
- `movePage` refuses a `to` inside the selection. Converting a slot to a `to`
  can produce such an index for a valid move (select {1,2}, drop before page
  5), so `movePageToSlot` reorders directly via the shared
  `_moveSelectionTo` and does not go through `movePage`'s guard.
- Edge auto-scroll while dragging is still not implemented (it was not before
  this change either).
