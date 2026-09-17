# Shift-snap the segment a vertex drag reshapes

Drawing a straight-line annotation already honours Shift: #620 added
`_straightSnap` / `_snap45` to `editing_overlay.dart`, and the line family
(line, arrow, measure distance/slope, calibrate) constrains its rubber-band
drag through it, while polyline / polygon / the measure and takeoff poly
tools constrain each newly placed vertex against the one before it. Editing a
shape that already exists did not: `_applyDragPosition`'s vertex branch put the
dragged handle at `_snapPointToGrid(position)` and nothing else, so a line you
had straightened while drawing could only be re-aimed free-hand.

That branch now runs the grid-snapped point through `_snapVertexPosition`
before it lands in `_vertexPoints` - the same list the live preview paints and
`_commitVertexDrag` writes back - so the preview, the commit and the
afterimage all agree without touching any of them.

## Which segment is "the current" one

A terminal vertex of a line or polyline has a single neighbour, so there is no
question: it snaps against that one. An interior vertex has two, and so does
*every* vertex of a polygon, whose ends wrap (a `/Polygon`'s `/Vertices` does
not repeat the first point; the renderer closes it). Snapping against a fixed
one of the two - "the previous vertex", say - means half of all drags fight the
user.

Both candidates are computed instead and the one that lands nearest the pointer
wins. `_snap45` rounds the direction to the nearest of eight and projects the
pointer's reach onto it, so a candidate's distance from the raw pointer is
exactly how far that segment had to be bent to straighten it: the winner is the
segment the drag was already closest to lining up, which is the one the user is
aiming at. Dragging a middle vertex down under its successor takes the vertical
it is 5pt from, not the diagonal it is 39pt from.

Callout handles are left out. `_selectedVertexPoints` exposes two for a
callout - the terminus and the base where the leader meets the text box - but
those are not the ends of a path segment the way a line's are (the base slides
along the box, and `_commitVertexDrag` routes each through its own
`reshapeSelectedCallout*` call), so a 45° constraint there would be a different
feature with a different anchor. `_snapVertexPosition` returns the point
unchanged for anything that is not line-family (`_selectedLineTool == null`).

Like every other Shift constraint outside ink, the modifier is read live per
pointer sample: releasing Shift mid-drag frees the next move rather than
re-snapping on release.

Tests: `editing_straight_lines_test.dart` gained three - a line endpoint pulled
level with its anchor, a polyline middle vertex choosing the nearer of its two
segments, and a polygon's `v0` snapping against the closing edge (the wrap).
Each fails by exactly the un-snapped offset without the change.
