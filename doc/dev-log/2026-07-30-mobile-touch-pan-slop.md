# 2026-07-30 — mobile touch pan: the platform's touch slop, and the canvas beside the page

Closes out the bug left open in
[2026-07-19-devtools-mobile-touch-logging.md](2026-07-19-devtools-mobile-touch-logging.md)
§3: *"panning while zoomed doesn't work from a fresh app open, but works after I
pick the select tool."* That session's leading hypothesis was right —
`InteractiveViewer`'s own `ScaleGestureRecognizer` wins the arena on-device and
eats the drag as a no-op — but the *why* was missing, and without it the fix
would have been a guess. Here it is, plus a second dead zone found on the way.

## 1. `RawGestureDetector` does not propagate `gestureSettings`

`GestureDetector.build` assigns `..gestureSettings = MediaQuery
.maybeGestureSettingsOf(context)` to every recognizer it constructs (nine call
sites). `Scrollable` does the same by hand for its drag recognizers.
`RawGestureDetectorState._syncAll` does **not** — it calls the factory's
`constructor()` and `initializer()` and nothing else. So a recognizer built in a
`RawGestureDetector` keeps `gestureSettings == null` and falls back to the
framework constants: `kTouchSlop` 18, `kPanSlop` 36 (`computePanSlop` in
`gestures/events.dart`).

Every gesture recognizer the viewer owns lives in a `RawGestureDetector`. So:

| recognizer | built by | pan slop on a phone |
| --- | --- | --- |
| `_ZoomedTouchPanRecognizer` | the viewer's `RawGestureDetector` | **36** (default) |
| IV's `ScaleGestureRecognizer` | `GestureDetector` inside `InteractiveViewer` | **~16** (`touchSlop * 2`, Android's 8dp) |

`ScaleGestureRecognizer._advanceStateMachine` resolves **accepted** as soon as
`focalPointDelta > computePanSlop(kind, gestureSettings)` — a *single* finger is
enough. So on a device IV accepted a one-finger drag at ~16px, twenty pixels
before the viewer's pan recognizer would even consider it, won the arena, and
then did nothing with it: `panEnabled: false` means `_onScaleUpdate` ignores a
one-pointer gesture. The drag was swallowed whole. Arming select "fixed" it
because the editing overlay's per-page `GestureDetector` is both deeper *and*
platform-configured, so it beats IV at the same 16px.

This is exactly why it never reproduced in `flutter_test`: the test view reports
no `physicalTouchSlop`, `MediaQuery.gestureSettings` is null, both sides fall
back to 36, and the inner recognizer wins on dispatch order. Any test written
without an explicit `DeviceGestureSettings` is blind to this class of bug.

Fix: capture `MediaQuery.maybeGestureSettingsOf(context)` once in
`_PdfViewerState.build` and assign it to all six recognizers the viewer mounts
(double-tap, trackpad pan, eager pinch, zoomed touch pan, mouse selection pan,
selection long-press). Note this makes the tie *safe*, not lucky: the viewer's
recognizer is strictly inside IV's in the hit-test path, so it handles each move
event first, and `DragGestureRecognizer` accumulates **path length** where
`ScaleGestureRecognizer` measures **net displacement** — so at equal slop the
pan crosses the threshold no later than IV, never later. It also removes 20px of
dead travel before a zoomed pan starts moving, which was its own mobile
paper-cut.

## 2. The canvas beside the page was a dead zone at fit scale

Found while reproducing #1. The list's `physics` is
`NeverScrollableScrollPhysics` whenever a tool is armed *or* the viewer is
zoomed, but `_zoomedTouchPanEnabledAt` bailed on `if (!_zoomed) return false`.
So at fit scale with a tool armed, nothing owned an off-page touch drag: the
list wouldn't scroll, the viewer's pan recognizer stayed out of the arena, and
the editing overlay only covers pages. A drag starting on the canvas or in an
inter-page gap moved nothing at all — and `PdfViewerFit.page`, the default,
leaves canvas down both sides of a portrait page on a phone, which is precisely
where a thumb lands.

The gate's own comment already named this hazard ("Canvas and inter-page gaps
have no overlay, so the viewer must claim them") — it just never got the chance
below zoom. Fixed by making both sites read one invariant,
`_listOwnsTouchScroll` (`!_zoomed && widget.editing?.tool == null`), so the
physics and the pan gate cannot drift apart again. `_zoomedTouchPanEnabledAt` →
`_touchPanEnabledAt`, and the gesture-log lines are `touch-pan gate:` now
(they also carry `zoomed=` since the gate is no longer zoom-only).
`_ZoomedTouchPanRecognizer` keeps its name; its doc comment carries the real
condition.

## Tests

`mobile_touch_pan_test.dart` — pumps the viewer under a
`MediaQuery(gestureSettings: DeviceGestureSettings(touchSlop: 8))`, which is the
only way to see #1 from a test at all. Four of its six tests fail on the parent
commit, and #1's failures are the reported symptom exactly: the visible region
comes back *bit-identical* after the swipe, not merely short. Also asserts the
viewer's six recognizers all carry the platform settings (constructing each from
its live factory), that a tool-armed drag over a page still draws rather than
pans, and that reader mode keeps `physics == null` and the platform fling.

Full `dart analyze` clean; all 2048 `dart_pdf_editor` tests pass.

## If this comes back

The device-only signal is already wired: devtools → Log section → "Log touch
input", then filter for `gesture`. A swallowed pan shows
`InteractiveViewer interaction START` with **no** `viewer zoomed-touch-pan
START`; a healthy one shows `touch-pan gate: ENABLED` followed by the pan's
START/END pair.
