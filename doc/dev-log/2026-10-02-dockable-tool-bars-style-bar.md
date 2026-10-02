# Dockable tool bars and a separate style bar

Request: let the toolbars dock to the top/side/bottom like other PDF editors,
including the sub-toolbars ("shapes can go on the right"), and offer the
styling controls in one consistent place.

## Where it started

The main toolbar already docked to any of the four edges (grip →
`PdfToolbarDragData` → the shell's edge drop zones → `prefs.toolbarDock`).
But the contextual strip (a group's tools + its settings, or the selection's
actions + restyle controls) was glued to the dock and opened beside it. The
style controls also moved around: they sat after a variable-width run of
tools, and when an annotation got selected the whole strip swapped, so the
swatches jumped.

## UX model

Three kinds of bar:

- **Main toolbar**: undo/redo, Hand/Select, the group chips. Docks to an edge.
- **Tool bars**, one per group (Markup, Draw, Shapes, Insert, Measure,
  Edit). "With main toolbar" (the default) is the old behaviour: the bar
  opens beside the dock while its group is open. **Docked to an edge**, the
  bar is *pinned*: it stays there as a persistent palette even when its group
  is closed (tools only), and grows its settings while one of its tools is
  armed. That is how docked toolbars work in Acrobat, Bluebeam and Foxit, and
  it is what makes docking worthwhile: one click arms a tool from the rail.
- **Style bar** (optional). One bar for colour / stroke presets / opacity /
  the style popup, targeting the selection first and otherwise the armed
  tool, on a fixed edge. It is labelled "Style · <target>" and hides while
  nothing restyles. Off (the default), the style controls stay inside the
  tool bars, but now always at the **trailing end**: tools | tool options |
  style. Before, Draw/Insert/Measure interleaved options inside the style
  run, so even the inline layout is now consistent with the selection strip.

Every grip does two things: **drag** it onto an edge drop zone, or
**click/tap** it for a placement menu (top/bottom/left/right, plus "With main
toolbar" / "Inside tool bars" where that applies). A tool bar's menu also
toggles "Separate style bar", which is where most people will find it. View
options → **Toolbar layout** (`showPdfToolbarLayoutDialog`) lists every
choice as a dropdown with a reset, for keyboard and screen-reader users. A
tap on the grip never loses to the drag: the `Draggable`'s recogniser only
accepts past the slop, so the inner `GestureDetector`'s tap wins a stationary
press.

Dropping a tool bar on the main toolbar's own edge pins it there (what you
see is what you get); unpinning is the menu's "With main toolbar".

## Implementation

- **Prefs** (`editing_preferences.dart`): `toolStripDocks` /
  `toolStripDock(group)` / `setToolStripDock(group, dock?)` persisted as
  `toolStripDock.<group>`; `styleBarDock` (nullable) as `styleBarDock`;
  `resetToolbarLayout()`. Imports `PdfEditToolGroup` from `tool_shortcuts.dart`
  (widgets/services only, so the controller's headless closure stays
  Material-free).
- **Toolbar** (`editing_toolbar.dart`): new params `onDock`,
  `toolStripDocks`, `onToolStripDock`, `styleBarDock`, `onStyleBarDock`,
  `overlay`. In `overlay` mode the toolbar fills its area, and
  `_buildDesktop` collects bars per edge (outermost first: main, context
  strip, pinned tool bars, style bar). `_ToolbarEdgesLayout` (a
  `MultiChildLayoutDelegate`) lays top/bottom out first at full width, then
  centres left/right in the band between them, so a side rail can never run
  under a horizontal bar. Gaps pass pointer events through (no render object
  in the stack absorbs hits; the root `Material` is transparency). Without
  `overlay`, the old content-sized layout is kept: tool bar docks are ignored
  and a style bar stacks beside the dock.
- **Per-bar axis**: `_stripAxis` used to come from `widget.dock`. It now comes
  from `_buildEdge`, set around each bar's build by `_onEdge`. **Gotcha**:
  anything read inside a `LayoutBuilder`/`Builder` callback runs *after*
  `_onEdge` has restored the edge, so `_centeredCard` and `_barGrip` capture
  `_cardAlignment` / `_stripAxis` eagerly.
- **Top dock fix**: at the top edge the strip used to stack *above* the dock,
  so the main toolbar jumped down whenever a strip opened. `_edgeGroup` now
  always puts the main toolbar outermost, and strips open inward on every
  edge.
- `_groupSettings` splits into `_groupOptions` (ink commit, signature
  library, annotation library, count tally, scale chip, form type, flatten,
  apply redactions) and `_groupStyle`; `_selectionStyle` comes out of
  `_selectionStrip`. The mobile sheet still calls `_groupSettings` inline.
- **Shell** (`shell_chrome.dart`): `PdfToolbarDragData(onDock:)` lets a bar
  carry its own dock callback through the shared drop zones (null → the
  shell's `onToolbarDock`, as before). `PdfToolbarMoveHandle` takes a key,
  payload, tap action, tooltip, feedback icon, axis and size; without a drag
  scope it still renders when it has an `onTap`, so a standalone toolbar's
  grip opens the menu. `PdfShellPanelLayout.floatingToolbarFillsViewer`
  positions the toolbar over the whole viewer (less the scrollbar gutter).
  The placement menu goes through `PdfEditorPresenter.menu` and the dialog's
  pickers are `PdfDropdown`, so the design-import counters stay at 0.
- **Editor view**: the stock toolbar renders its own main grip (`onDock`)
  instead of the shell injecting `PdfToolbarMoveHandle` through `leading`.
  `overlay`/`floatingToolbarFillsViewer` apply only to the stock toolbar; a
  `toolbarBuilder` toolbar keeps the old edge positioning. The viewer's
  bottom tail (`trailingPadding`) now counts any bar on the bottom edge. The
  layout entry is in the desktop view-options popup only: the breakpoints
  are unified at 700px (`pdfShellCompactWidth`), so the compact settings
  sheet always pairs with the fixed phone bar, where docking does not apply.

## Strings

15 new `tb*` keys (dock edges, "With main toolbar", "Inside tool bars",
"Separate style bar", the dialog's title, sections, hints and reset, and the
grip tooltip), translated in all 19 non-English locales; en_AU/en_GB synced
by `tool/sync_english_locales.dart` (colour).

## Tests

`test/toolbar_layout_test.dart`: prefs persistence + reset; a right-docked
Shapes bar is a vertical palette while closed, stays above the bottom main
toolbar, and arming from it shows its settings without a duplicate strip;
dragging a tool bar grip to the right drop zone pins it; grip menus (unpin a
tool bar, move the main toolbar to the top); the style bar shows only while
something restyles, holds the only colour picker, and stays put across
tools; a tool bar's menu toggles the style bar; the view-options dialog sets
the style bar and a tool bar dock and resets. The existing dock tests in
`pdf_shell_test.dart` pass unchanged.
