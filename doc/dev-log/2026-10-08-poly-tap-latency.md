# Poly-tool taps land on the raw pointer events

Symptom: with the snapshot, cloud or content-delete tool, tapping out a
polygon left the rubber band chasing the cursor for ~300ms after each tap
before the vertex appeared at the tap point.

Cause: those hybrid tools (a drag rubber-bands a rectangle, taps place
vertices) placed their vertex from `GestureDetector.onTapUp`. The same
detector runs a double-tap recognizer for the finishing double-tap, and with
one in the arena every tap is held back for `kDoubleTapTimeout`. The plain
poly tools (polyline/polygon/measure) never had the lag - they add on raw
pointer-down. A second, related bug: a quick finishing double-tap was ignored
while the recognizer was still holding an earlier, far-away tap, and taps
faster than the timeout could resolve out of order.

Fix (`editing_overlay.dart`): `_onPointerDown/Move/Up` track a poly-tool
press (`_polyTapPointer`/`_polyTapDown`, cancelled past `computeHitSlop`). On
the raw up, `_onPolyTap` adds a hybrid tool's vertex and pairs the tap with
the previous one (`_polyLastTap`, expired by a `kDoubleTapTimeout` `Timer`,
paired at the second *down* within `kDoubleTapSlop`, like the recognizer) to
finish the path. `onTapUp` no longer places vertices.

Gotcha: the double-tap recognizer must stay in the arena for poly tools even
though `_onDoubleTap` now ignores them - without it the viewer's
double-tap-to-zoom wins the finishing double-tap and zooms the page
(`editing_straight_lines_test` caught this as shifted view coordinates).
Also: test pointer events carry zero `timeStamp`s, so time the pairing window
with a `Timer`, not event timestamps.

Test: `editing_snapshot_test.dart` "a polygon vertex lands on the tap, not
after the timeout" (fails on the old path: vertex order scrambled and the
finish dropped).
