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
- One gap is one drop point. Within a row the bar always goes on the
  leading edge of the page after the gap, and `_PageTile.dropMarkerOutset`
  (6 = half the grid's spacing) centres it in the gap, so it holds still as
  the pointer crosses from one page's half to the other's. The file-drop
  marker in the grid gets the same centring. Only where a row wraps (the end of
  one row and the start of the next are the same slot) does the nearer end win.
- `pageSlotMoves` hides the bar over gaps that would not change the order (the
  gaps beside the dragged page, or inside a contiguous selection).
- `movePage` refuses a `to` inside the selection. Converting a slot to a `to`
  can produce such an index for a valid move (select {1,2}, drop before page
  5), so `movePageToSlot` reorders directly via the shared
  `_moveSelectionTo` and does not go through `movePage`'s guard.

Edge auto-scroll uses Flutter's `EdgeDraggingAutoScroller`, the same helper
`ReorderableList` uses, on the grid's `Scrollable` (found under `_wrapKey`).
It gets a 96px-tall sliver centred on the pointer and scrolls while that
sliver overflows the viewport, i.e. while the pointer is within 48px of the
top or bottom. Its `onScrollViewScrolled` re-aims the bar and re-arms the
scroll, because the pointer is still while the cells move under it.

Reorder animation (`_reorderSlide`, 280ms easeOutCubic): this is a
first-last-invert-play (FLIP) slide. `pageSlotOrder` gives the new order
before the move, and `_wrapPositions` predicts where the `Wrap` will lay each
cell out (it mirrors `RenderWrap`'s line-break rule: break when
`x + spacing + w > width`; RTL is mirrored). Each cell starts at
`old - predicted`, so the very first frame of the new order already paints
everything where it was, with no flash of the end state. Measuring after the
rebuild would cost that one frame. Carried pages slide from the drop point.
The `AnimatedBuilder` + `Transform.translate` is always in the tree (offset
zero at rest) so starting a slide never remounts a cell.
