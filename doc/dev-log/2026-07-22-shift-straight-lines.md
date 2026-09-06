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
- **Ink** (pen / freehand highlighter): Shift anchors a straight tail at the
  latest sampled point, preserving any freehand prefix. The tail snaps to
  the nearest 45° direction and rubber-bands until pointer-up, including
  when Shift is released just before the mouse or pen. The next stroke starts
  with a fresh constraint state.

## Implementation notes

Snapping operates in **view space** (the gesture Offsets):
`_snap45(anchor, point)` projects `point` onto the nearest 45° direction from
`anchor`. `_straightSnap` returns the point unchanged when Shift is up. It's
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

Both ink-extension paths use `_extendActiveStroke(localPosition)`. The first
sample with Shift down latches `_inkShiftAnchorIndex` to the latest existing
sample. Subsequent moves preserve the prefix and replace only the snapped
endpoint, with matching pressure samples. Pointer completion, cancellation,
and gesture bails clear the latch.

Prediction is disabled for the constrained tail so its preview ends where
the saved line will end. `_inkStrokeParts` splits the freehand prefix and
straight tail at their shared anchor in both preview and commit. This keeps
Catmull-Rom smoothing from bending the tail. Both paths remain in one Ink
annotation and one undo operation.

Tests in `test/editing_straight_lines_test.dart` cover line and polyline
snapping, early Shift release for mouse/touch/stylus, subsequent freehand
strokes, raw-pointer cancellation, stylus pressure, and Ctrl-wheel zoom.
Pixel checks verify the active preview, buffered preview, and reopened PDF
all retain a straight tail without prediction overshoot.
