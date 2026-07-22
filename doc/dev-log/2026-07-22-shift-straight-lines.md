# Shift-to-draw straight lines (line / polyline / polygon / ink)

Holding **Shift** now constrains the straight-line drawing tools in the
editing overlay (`packages/dart_pdf_editor/lib/src/editing/editing_overlay.dart`):

- **Line family** (line, arrow, distance/slope measure, calibrate): a drag
  snaps to the nearest 45° axis off the press point (8 directions:
  horizontal, vertical, both diagonals).
- **Polyline / polygon** and the poly-shaped measurements (perimeter, area,
  angle, arc, volume) and the cloud polygon's click path: each edge snaps to
  a straight 45° axis off the previous vertex.
- **Ink** (pen / freehand highlighter): the freehand stroke collapses to a
  single ruler-straight segment from where it began to the pointer,
  rubber-banding as it moves. This one is *not* 45°-constrained — "straight
  ink" means a straight line at any angle, matching how drawing apps behave.

## Implementation notes

Two small geometry helpers do the work, both operating in **view space** (the
gesture Offsets) so previews and commits share one source of truth:

- `_straightSnap(anchor, point)` — projects `point` onto the nearest 45°
  direction from `anchor`. Returns `point` unchanged when Shift is up. Used
  directly by the single-segment line drag.
- `_straightChain(raw)` — snaps a whole vertex chain, each vertex relative to
  the previous *already-snapped* one. Returns `raw` untouched when Shift is up.

### Why poly stores raw points, not snapped ones

The first cut snapped each vertex as it was placed and stored the snapped
point in `_polyPoints`. That broke **double-tap-to-finish**: the poly vertex
dedup (`distance >= 2`) compares the incoming tap against the last stored
vertex, and once a vertex snapped *away* from where it was tapped, the second
tap of the finishing double-tap landed >2px from the snapped vertex and got
appended as a stray short segment.

The fix: keep `_polyPoints` (and `_polyHover`) as the **raw** tapped/hovered
points — so the dedup stays exact — and apply `_straightChain` only where the
chain is *drawn* (the `polyPreview` builder) and *committed*
(`_finishPolyPath`, just before simplification → page-space). Snapping is a
pure view-of-the-data transform; nothing about placement/dedup changes.

### Ink

Both ink-extension paths (raw-pointer `_onPointerMove`, gesture-arena
`_applyDragPosition`) were duplicated append-a-point blocks; they're now one
`_extendActiveStroke(localPosition)`. While Shift is held it truncates the
stroke to `[origin]` and appends the current point (and mirrors that on the
parallel pressures list), so release commits a two-point line. Stroke
prediction is display-only and extrapolates along the segment direction, so a
straight stroke stays straight and never folds the lead into the commit.

Live shift state is read from `HardwareKeyboard.instance.isShiftPressed` at
each pointer sample, so toggling Shift mid-gesture updates the next move
(standard drawing-app behaviour).

Tests: `test/editing_straight_lines_test.dart` (line axis + diagonal snap,
per-edge polyline snap through a double-tap finish, ink straightening).
