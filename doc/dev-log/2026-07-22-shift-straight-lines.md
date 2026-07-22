# Shift-to-draw straight lines (line / polyline / polygon / ink)

Holding **Shift** now constrains the straight-line drawing tools in the
editing overlay (`packages/dart_pdf_editor/lib/src/editing/editing_overlay.dart`):

- **Line family** (line, arrow, distance/slope measure, calibrate): a drag
  snaps to the nearest 45° axis off the press point (8 directions:
  horizontal, vertical, both diagonals).
- **Polyline / polygon** and the poly-shaped measurements (perimeter, area,
  angle, arc, volume) and the cloud polygon's click path: the segment
  *currently being drawn* snaps to a straight 45° axis off the previous
  vertex. Only the live edge is constrained — already-placed vertices are
  never straightened retroactively, so Shift held at the end doesn't reflow
  the whole polyline.
- **Ink** (pen / freehand highlighter): the freehand stroke collapses to a
  single ruler-straight segment from where it began to the pointer,
  rubber-banding as it moves. This one is *not* 45°-constrained — "straight
  ink" means a straight line at any angle, matching how drawing apps behave.

## Implementation notes

One geometry helper does the work, operating in **view space** (the gesture
Offsets): `_straightSnap(anchor, point)` projects `point` onto the nearest 45°
direction from `anchor`, or returns `point` unchanged when Shift is up. It's
used by the single-segment line drag, by each poly vertex as it's placed, and
by the live rubber-band / measurement-readout edge.

### Per-segment, not whole-chain

Snapping happens **per vertex, at placement time**, based on the Shift state
at that moment — the placed point (already snapped) is stored in
`_polyPoints`. The preview and commit do *not* re-snap the chain, so holding
Shift only straightens the edge currently being drawn; earlier segments keep
whatever angle they were placed at. (An earlier cut re-snapped the entire
chain at commit/preview against the live Shift state, which straightened every
segment when Shift happened to be down at the finish — wrong.)

### The double-tap dedup: `_polyLastRaw`

Because a placed vertex can snap *away* from where it was tapped, the
near-duplicate dedup (`distance >= 2`, which rejects the redundant second tap
of a finishing double-tap) can't measure against the stored (snapped) vertex —
it would see the finishing tap as a new point >2px away and append a stray
segment. So `_polyLastRaw` tracks the raw tap position of the last placed
vertex, and both `_addPolyPoint` and `_finishPolyPath` dedup against it. It's
reset to null everywhere `_polyPoints` is cleared.

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
per-edge polyline snap through a double-tap finish, the per-segment guarantee
— Shift held only for the last edge leaves the opening segment angled — and
ink straightening).
