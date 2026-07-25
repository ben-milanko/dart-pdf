# 2026-07-22 — Chrome-style tab sizing

Made the desktop tab strip size its tabs the way Chrome does.

## Behaviour

- **Equal share.** Every open tab gets the same slice of the strip
  (`available / count`), so the tabs together fill the space instead of each
  being sized to its own title.
- **Shrink as they fill.** The slice is clamped to `[_tabMinWidth (56),
  _tabMaxWidth (240)]`. Few tabs sit at the max (leaving slack for the trailing
  controls, as in a wide Chrome window); as more open they shrink toward the
  floor, below which the strip scrolls horizontally (unchanged fallback).
- **Narrow tabs drop the close button.** Below `_tabCloseHideWidth (100)` an
  inactive tab hides its `×` so the label keeps room; the active tab always
  keeps it. (Chrome does the same.)
- **Width hold on close.** While the pointer is over the strip, closing a tab
  pins the survivors at their current width (`_heldTabWidth`, captured `??=` on
  the first close of a streak) so the next `×` lands under the cursor. The hold
  releases when the pointer leaves the strip (`MouseRegion.onExit`), and the
  tabs animate back out to fill the freed space.

## Implementation notes

All in `app/lib/editor_screen.dart` (`_EditorScreenState`):

- `_estimatedTabStripWidth` (title-measuring TextPainter loop) is replaced by
  `_chromeTabWidth(available)`, a plain equal-share clamp.
- `_buildTab` now takes the computed width and fills it: outer `AnimatedContainer`
  + `Expanded` label + conditional close.
- The release animation stays pixel-consistent by animating both the strip's
  outer `AnimatedContainer` and each tab's inner one with the **same duration
  and `Curves.linear`** — linear interpolation is homogeneous, so
  `outer = count * inner` holds at every frame (no `AnimationController`,
  no sync drift, no clipping/gaps mid-animation).
- `_lastNaturalTabWidth` is captured during layout so `_closeTabs` (which has no
  layout constraints) can pin to it; `_addTab` clears the hold (a new tab shrinks
  the others).

## Tests

- `app/test/tabs_sizing_test.dart` (new): tabs shrink as more open; a close over
  the strip holds a survivor's width, which then grows once the pointer exits.
- `app/test/tabs_menu_test.dart`: the desktop-strip dialog test now sets a
  realistic desktop surface (`setDesktopSize`, 1400×800) — with Chrome-style
  filling, three max-width tabs nearly fill the old 800px default and collapse
  the spacer the test asserts on.
