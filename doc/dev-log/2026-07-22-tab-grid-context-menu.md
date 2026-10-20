# 2026-07-22 - Right-click context menu for the tabs grid view

The desktop tab strip already had a right-click context menu
(`EditorScreen._showTabMenu`: Open in Finder / Close / Close others /
Close to the right / Close all). The tabs **preview grid** - the tile grid
shown in the desktop "view all tabs" dialog (`desktop-tabs-grid`) and the
mobile tabs bottom sheet (`mobile-tabs-grid`), both built by
`_buildTabsGrid` from `_MobileTabTile` - only supported tap-to-activate and
the per-tile close button. This adds the same context menu to the grid.

## What changed (`app/lib/editor_screen.dart`)

- `_MobileTabTile` gained an optional
  `onContextMenu(Offset globalPosition)` callback. It fires from the tile's
  `InkWell.onSecondaryTapUp` (right-click, carries the pointer position) and
  from `InkWell.onLongPress` for touch parity - long-press has no position,
  so we anchor the menu at the tile's centre via
  `context.findRenderObject()`/`localToGlobal`. Null (the default) leaves the
  tile as it was, so no other caller changes behaviour.
- `_buildTabsGrid` wires `onContextMenu` to the existing `_showTabMenu`,
  re-resolving the tab index by identity first (the grid can reorder).
- `_showTabMenu` took an optional `onChanged` callback, run after the chosen
  action resolves. The grid passes a `refreshOverlay` closure (extracted from
  the tile's existing `onClose` path) so the modal grid rebuilds after a close
  action, or dismisses itself once the last tab is gone - the modal grid does
  not rebuild off the screen's own `setState`. The tab-strip call site omits
  it, so its behaviour is unchanged.

Reusing `_showTabMenu` means the grid menu is automatically consistent with
the strip: same items, same enable/disable rules (Close others needs >1 tab,
Close to the right disabled on the last tab), same "Open in Finder" gating on
`supportsOpenContainingFolder && tab.originPath != null`.

## Tests (`app/test/tabs_menu_test.dart`)

Added `openTabsGrid`/`gridTile`/`rightClickGridTile` helpers and three cases:
right-click on a grid tile opens the menu; "Close others" from the grid leaves
one tile with the grid still open; "Close all" empties the grid and dismisses
the dialog.
