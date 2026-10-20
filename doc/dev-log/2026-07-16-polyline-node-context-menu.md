# Add/remove polyline & polygon nodes from the context menu

## What

Right-clicking (or touch long-pressing) a selected /PolyLine or /Polygon
now offers **Add node** and **Remove node** in the annotation context
menu, so a vertex can be spliced in or dropped without re-drawing the
whole shape. Dragging vertex handles already existed
(`_commitVertexDrag` → `reshapeSelectedLine`); this fills the gap for
changing the vertex *count*.

## Where

- `editing_controller.dart` — new API around the existing
  `reshapeLineAnnotation` editor call:
  - `canAddSelectedVertex` / `canRemoveSelectedVertex` gate the menu
    entries. Remove is disabled at the subtype floor (a /PolyLine keeps
    2+ vertices, a /Polygon 3+) so the reshape never throws.
  - `addSelectedVertexAt((x, y))` splices the page point into the edge
    nearest it (`_nearestEdgeInsertIndex`, using point-to-segment
    distance; a polygon also weighs the closing last→first edge).
  - `removeSelectedVertexNear((x, y))` drops the vertex closest to the
    point (`_nearestVertexIndex`).
  - `_editableVertexAnnotation` is the shared guard: exactly one selected
    /PolyLine or /Polygon with real /Vertices. A plain /Line is excluded
    (it is fixed at two points) as are non-line subtypes.
- `editing_menu.dart` — two entries (`pdf-annot-menu-add-node`,
  `pdf-annot-menu-remove-node`) between "Send to back" and "Delete".
  They only appear when the menu was opened with a `pagePoint` (the
  right-click / long-press paths both pass one); the selection-chip
  "More" button has no point, so it hides them.

## Notes / gotchas

- Geometry is all page-space and scale-independent — the menu layer has
  no view transform, so "nearest vertex/edge" is computed on the raw
  /Vertices. Predictable: whatever the click is closest to is what gets
  added-beside or removed.
- The reshape goes through `reshapeLineAnnotation`, so the appearance
  stream, /Rect, BBox, endings, and any measurement caption all
  regenerate for free, and each edit is one undo step.

## Tests

`editing_menu_test.dart` — a `polyline/polygon nodes` controller group
(splice into the nearest edge, polygon closing-edge splice, remove the
closest node, floor enforcement, unavailable for /Line and /Square) plus
two widget tests (a polygon right-click shows and applies Add node; a
rectangle right-click shows neither entry).
