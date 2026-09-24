# Tabs grid: open on the active tab, search by title

The open-tabs grid (compact bottom sheet `_showTabsSheet`, desktop dialog
`_showTabsDialog`) is now `_TabsOverview` in `app/lib/editor_screen.dart`.

- **Opens on the current tab.** The grid's `ScrollController` is created in
  the first `LayoutBuilder` pass with an `initialScrollOffset` that centres the
  active tab's row (`_activeOffset`, clamped to the content extent). The row
  math comes from the same `SliverGridDelegateWithMaxCrossAxisExtent.getLayout`
  the grid uses, so it cannot drift from the real layout. A measured initial
  offset (not a post-frame `jumpTo`) matters because the grid has a zero cache
  extent: building the top rows first would render their thumbnails for
  nothing.
- **Search.** A title filter (case-insensitive substring) above the grid;
  Enter activates the first match, the clear button resets it. It autofocuses
  only in the desktop dialog - on a phone it would raise the keyboard over the
  grid. The grid stays mounted (with a "No matching tabs" overlay) while
  nothing matches, so its position is reset per query rather than re-seeded
  from the active-tab offset.

Tests: `app/test/tabs_menu_test.dart` ("tab grid opens scrolled to the active
tab", "tab grid search filters tabs by title"); the fast-fling test now flings
toward the first tab, since the grid opens on the last-opened one.
