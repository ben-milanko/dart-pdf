# Stamp template canvas: overlay-style touch handles

## Problem

The custom-stamp editor's in-dialog composer (`_StampTemplateCanvas` in
`editing_stamps.dart`) was finicky on touch, "especially the scale box":

- It listened to **raw pointer events** (`Listener`, `onPointerDown/Move/Up`)
  with no gesture recognizer, so no touch slop - the faintest jitter during a
  tap-to-select dragged the component - and no gesture-arena participation.
- It exposed **one tiny resize handle at the bottom-right corner only**
  (`12 / scale` template units, drawn at `10 / scale`). A finger had to land
  almost exactly on that corner or the press read as a *move* instead.

On-page placed stamps never had this problem: a placed stamp is an ordinary
`subtype == 'Stamp'` annotation and already flows through the shared
`EditingPageOverlay` (8 handles, `_handleHitRadius` = 12 logical px, rotate
knob). Only the template composer rolled its own controls.

## Change

Ported the overlay's interaction model into `_StampTemplateCanvas` (keeping the
two coordinate systems decoupled - the composer works in template space before
any PDF exists, so it can't literally reuse the overlay, which is bound to a
live `PdfDocument`):

- **`GestureDetector` with `dragStartBehavior: DragStartBehavior.down`**
  (`onPanStart/Update/End` + `onTapUp`), mirroring the overlay's own wiring.
  `DragStartBehavior.down` anchors the drag at the press point, so the handle
  grab and the move both start where the finger actually landed. The
  recognizer also gives real touch slop, so tap-to-select no longer nudges the
  component. Inside the dialog's `SingleChildScrollView` the inner pan wins the
  arena over the scrollable (and mouse drags, used by the widget tests, don't
  contend since `Scrollable`'s default drag devices exclude the mouse).
- **Eight handles** (`_stampHandles`, corners + edge midpoints) with the same
  `(dx, dy)` edge convention as the overlay's `_Handle`, hit-tested in **logical
  pixels** against `_stampHandleHitRadius` = 14 so the target is the same size
  at any template zoom. `_resizeSelected` now takes the grabbed handle and moves
  only the edge(s) it owns, clamped to a minimum size and the template bounds
  (previously it only grew width/height from a fixed top-left anchor).

## Gotchas / pointers

- The resize callback signature changed: `onResizeSelected` is now
  `void Function(_StampHandle handle, Offset delta)`; the frame-coalescing in
  `_queueDelta`/`_flushPendingDelta` carries the handle alongside the delta.
- `DragStartBehavior` lives in `package:flutter/gestures.dart` - added that
  import (material alone doesn't re-export it).
- Handle centers are computed once by the top-level `_stampHandleCenter` and
  shared by both the painter (draws in template space, scaled by the canvas) and
  the state's hit-test (converts to logical px via the canvas scale).
- Tests: `editing_stamps_test.dart` keeps the existing move/resize case (still
  drives the bottom-right corner) and adds one that grabs the **top-left**
  corner a few px off-center - impossible with the old single handle - to guard
  the new multi-handle path and the forgiving radius.
