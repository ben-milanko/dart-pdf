# Tap to select lands on the lift

"Tap to select an object feels slow." It was a fixed ~300 ms
(`kDoubleTapTimeout`), not slow work: `selectAnnotationAt` is a linear hit
test and cheap.

## Cause

The viewer wraps the whole canvas in a touch/stylus
`DoubleTapGestureRecognizer` (double-tap zoom, `pdf_viewer.dart`). After a
first tap lifts, that recognizer **holds** the gesture arena until the
double-tap timeout expires, so the editing overlay's `onTapUp`
(`_onTapUp`, which selects) only fired ~300 ms after the finger left the
glass. Mice were never affected there because the zoom recognizer excludes
them. The form tool has the same delay for every pointer kind, because its
own `onDoubleTap` (double-tap fills a field) sits in the same detector as
its select-on-tap.

## Fix

The poly tools already took this route for the same reason (`_onPolyTap`).
Plain selection taps now also commit from the overlay's raw
`Listener.onPointerUp` (`_onSelectionTap` in `editing_overlay.dart`):

- A press is a tap candidate (`_selectTapPointer`/`_selectTapDown`) while
  it's the only contact, uses the primary button, and stays within
  `computeHitSlop`. `_selectTapTimer` drops it at `kLongPressTimeout`,
  because a long press belongs to the menu or to text selection. A second
  finger bails, and a drag clears it. Use a `Timer`, not the events'
  `timeStamp` difference: synthetic test gestures stamp every event
  `Duration.zero`, so a 600 ms long press read as a tap and wiped the text
  selection it had just made (`pdf_touch_selection_test.dart` caught it).
- Handled: a select-mode hit on an annotation (touch/stylus), the content
  tool's `selectElementAt` (touch/stylus), and the form tool's
  `selectFormWidgetAt` (any kind). A select-tool tap on empty page clears
  the selection early, but still falls through to `_onTapUp`, which may
  follow a link.
- Left to the arena, unchanged: placing tools, the re-tap that opens a
  selected free text (`_tapEditsSelectedFreeText`, now shared), following a
  link, shift/⌘ toggles, and reader mode with no tool (clearing the
  selection there unmounts the overlay's recognizers).
- A press on the touch selection chip is never a candidate. The chip's
  buttons are children of the overlay, so its raw listener sees their taps
  too. An early select at the button's position used to clear the selection
  before Delete ran, which then deleted nothing (`editing_ipad_test.dart`).
  A `Listener` around the chip records `_chipPointer`, and because the
  innermost listener runs first, it is set before the overlay's own
  `_onPointerDown` sees the press.
- `_selectTapUp` records the handled lift's global position so the arena's
  late `_onTapUp` for that same press returns early. Without it, the first
  tap on a free text would select it early, and then the delayed tap would
  read as "tap the selected free text" and open the editor. The value is
  reset on every pointer-up. That's safe because a held tap always resolves
  (by timeout, or when the next pointer goes down) before the next pointer
  lifts.

A double-tap on an annotation now selects it *and* zooms. Before, it only
zoomed.

Test: `test/editing_tap_select_latency_test.dart`.
