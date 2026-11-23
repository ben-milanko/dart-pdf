# Touch pinch keeps the content under the fingers

Reported feel: "when I pinch, I don't end up zooming in on the thing I
want to". Measured, not imagined: in a 3x pinch whose midpoint drifts (as
every real pinch does), the page content that started under the fingers
ended 19 px (from fit-width) to 24 px (from an already-zoomed view) away
from them, and the gap grew with the zoom ratio.

## Cause

`_EagerPinchRecognizer` sits *inside* the InteractiveViewer transform, and
`_onPinchUpdate` fed `details.localFocalPoint` to `_zoomTo` and
`details.focalPointDelta` to `_touchGrabPanBy` as live list-space values.
They aren't. Flutter's `GestureRecognizer.startTrackingPointer` registers
the route with `event.transform` from the pointer-down hit test, and
`PointerRouter` transforms every later move through that same matrix. So a
pinch's local positions are mapped through the zoom **at finger-down**, and
the pinch changes the zoom on every update:

- the anchor was the content that *used to be* at the current midpoint,
  not what is under it now;
- the pan was in start-zoom pixels, so content travelled `s / s0` times as
  far as the fingers.

Trackpad pinch is unaffected: its position is fixed for the whole gesture,
so the stale mapping consistently names the same content. Wheel events are
hit-tested fresh each time.

A second, smaller miss: `ScaleGestureRecognizer` measures `scale` from the
finger set at the last pointer down/up (`_initialFocalPoint`, private), but
fires `onStart` on the first *move* after acceptance, with that move's focal
point. Anchoring at `onStart` dropped the first move's drift, and the zoom
then multiplied it.

## Fix (`pdf_viewer.dart`)

- `_onPinchUpdate` works from the **global** focal point: maps the previous
  and current midpoints into the viewport through `_zoomViewportKey` (a key
  on the InteractiveViewer - outside the transform), zooms about
  `_sceneOf(before)` (live matrix), then pans by `(now - before) / scale`.
  `focalPointDelta` is not usable either - it is in the same stale local
  space - so the previous global focal is tracked in `_pinchFocal`.
- `_EagerPinchRecognizer.origin` records the touches' global midpoint each
  time the finger set changes; `_onPinchStart` seeds `_pinchFocal` from it.

Tests: `editing_ipad_test.dart` - "a pinch from fit keeps the content under
the fingers" and "a pinch from an already zoomed view keeps its content"
(`globalRectOf` tracks the grabbed page point; within 3 px, judged with the
fingers still down, lifted before asserting so a failure can't leak
pointers into later tests).
