# Docked toolbars: UX hill-climb on #991

A screenshot-driven pass over the docked (Bluebeam-style) toolbars from
#991. Widget screenshots were rendered at 800/1024/1280/1440px (light and
dark), plus an armed tool, Shapes as a right rail, and the main toolbar as a
left rail. Each change below came from something visible in those shots and
was checked again in a fresh set.

## What the screenshots showed

- **The docked area was one row taller than it needed to be at common
  widths.** Edit's tools (Content, Erase, Form, Link, Redact, Snapshot,
  Color) and Flatten were outlined, labelled buttons. That made the Edit
  toolbar ~800px wide, which is a row on its own. Measure's "Totals" was the
  same. The result was three toolbar rows at 1280 *and* 1440px (1440 left
  ~400px of row one empty, because Insert didn't fit after Shapes). At 800px
  it was five rows, and Flatten was cut off past the right edge of its
  scrolling slot.
- **Rails were uneven.** The labelled buttons already went icon-only on a side
  strip, but Flatten's condition was `!_docked && _sideStrip`, so it was never
  icon-only when docked. On a left rail it stayed a labelled pill and widened
  its column to 67px. Three rail columns took 175px.
- **The armed tool was hard to find.** A selected `IconButton` only tints its
  glyph. With every group's toolbar out at once (~45 icons), that tint was
  easy to miss. The grey disc in early shots was mouse hover, not selection.
- **The empty Properties bar's hint was 9px.** `_StripLabel` stacks its hint
  as a caption under the name, but the bar is a fixed 48px whatever it
  holds, so there was room for readable text.

## Changes (`editing_toolbar.dart`)

- `_iconOnlyLabels` (`_sideStrip || _docked`) replaces the per-site
  conditions on all five `_LabeledToolButton` sites: command buttons, Edit's
  tools, Color, Flatten and Totals. Docked bars show icons with tooltips,
  like other desktop editors' icon toolbars. Floating strips show one group
  at a time and keep their labels. This also fixes the Flatten rail case.
- `_denseTheme` adds an `iconButtonTheme` for docked surfaces:
  - **Selected** icon buttons get the Hand/Select pill's active fill
    (primary at 15%), so the armed tool reads as a tile.
  - **Padding 7, minimum 38** gives a 38px tile instead of 40; the glyph
    stays 24px. Material 3's `IconButton` ignores the theme's visual density
    (its defaults pin `VisualDensity.standard`) and enforces a 40px minimum,
    so the minimum has to be lowered too.
  - Two pixels a button brings row two at 1280px from 1320px to 1268px.
  - A host's own icon button theme is merged *over* this one, so its
    choices still win.
- `_PropertiesEmptyLabel`: the docked Properties bar's resting state is now
  "PROPERTIES" and the hint on one line, with the hint at 12px. Side rails
  keep the `_StripLabel` info icon.

## Gotcha: the dense theme must be memoized by equality

The first cut failed `app_prefs_rebuild_test` (2,423 element rebuilds per
stroke-width tick, budget 1,100). The app hands down an *equal but new*
`ThemeData` on every tick. `_denseTheme`'s memo was identity-only, so it
remade the dense theme each tick. Before this change that was harmless: the
remade copy compared equal, and `Theme` didn't notify. The selected-tile
style is a `WidgetStateProperty.resolveWith` closure, though, so each remade
copy compared *unequal*, and every themed control in every docked bar
rebuilt. The memo now also accepts an `==` source, and the test passes
again. Anything else that puts a closure into a dense/derived theme needs
the same care.

Tests: `toolbar_layout_test` gains three cases. Each fails on the pre-change
toolbar and passes now:
- Edit's tools and Flatten are bare icon buttons, and the Edit bar is
  < 500px;
- the selected-tile fill;
- the one-line Properties hint at >= 12px.

The editor suite passes (3,731). The app suite passes, except
`paced_read_test`, which flaked once under `-j 8` and passes 3/3 alone. It
is a file-read timing test, unrelated to the toolbar.

## Result

| width | rows before | rows after | chrome above the page |
|---|---:|---:|---|
| 1440 | 3 | 2 | 216 → 176px |
| 1280 | 3 | 2 | 216 → 176px |
| 800 | 5 (Flatten clipped) | 5 (nothing clipped) | unchanged |
| left rail | 3 columns, 175px | 3 columns, 120px | - |

The 1280 fit has about 12px to spare in English. A locale with longer group
names wraps to a third row, as before.

## Second round (follow-up requests)

Rule for this round: new layouts are opt-in. Each one gets a Settings switch,
so users can keep the current UI.

### First-fit packing (`toolbarPackTightly`, off by default)

- **`FirstFitWrap`** (`editing/first_fit_wrap.dart`) is a custom
  `RenderBox`. Each docked toolbar goes into the first row (or rail column)
  with room for it, so a shorter toolbar back-fills the gap a longer one
  left when it wrapped.
  - A child only moves *up* to an earlier run, never ahead of an earlier
    child on its own run.
  - Runs are as thick as their thickest child, and children are centred
    across them.
  - Dry layout and intrinsics are implemented.
- **Result:** at 800px, Insert joins Shapes' row, and the area is four rows
  instead of five.
- **Wiring:** `PdfEditingToolbar.packToolbars` is the seam. The switches are
  `settings-pack-toolbars` (app Settings, disabled while floating) and
  `pdf-layout-pack` (the layout dialog, only when docked). Reset clears it.
- **Tests:** `first_fit_wrap_test.dart` covers the packing with exact boxes:
  back-fill, run thickness/centring, an oversize child, and rail columns.

### More on the properties bar

The bar is a full window width, so the tune popup's most-used rows now sit
on it (`_inlineStyleControls` / `_inlineTextControls`):
- shape fill (`_InlineFillButton`, a bucket over the current fill, opening
  the swatch row);
- line type;
- line start/end (drawn, named in the menu);
- for text, bold/italic + alignment after the font chip.

They drive the same preferences and selection restyles as the popup, which
keeps them too. They only appear when docked, in the horizontal bar
(`_docked && _bareCards`); floating strips and rails keep the popup.
`PdfDropdown` gained `selectedItemBuilder` (one closed widget per item, like
`DropdownButton`'s) so an ending reads as its drawing alone. The menu rows
need `Flexible` + ellipsis: long locale names overflowed them.

### Main toolbar in the header (`toolbarMainInHeader`, off by default)

**Why this option.** The header's editor row leaves ~540px empty between
search and View options at 1280px. No arrangement saves a whole row there,
because the toolbars need two rows either way. So the gap gets controls
rather than height: undo/redo + Hand/Select, Acrobat-style quick tools.

**How it works:**
- A second `PdfEditingToolbar(mainToolbarOnly: true)` builds just `_dock`,
  bare, at dense density, for the header. `_docked` is true for it, so it
  shows no group switcher.
- The docked toolbar gets `mainInHeader` and leaves `pdf-docked-main` out.
- It applies only while docked, with the main toolbar on top, and at
  `_mainInHeaderMinWidth` (1100px) or wider. At 800px the header scrolled
  its panel switch off the edge.
- `PdfHeaderParts.tools` hands it to host headers (the app places it after
  search).
- `_HeaderToolsSlot` reports when a host header has mounted it. Until then
  the toolbar keeps the main toolbar, so a host that leaves the part out
  never loses undo. The stock header counts as mounted.
- Dragging the grip to another edge brings it back down.

**Switches:** `settings-main-toolbar-in-header` and
`pdf-layout-main-in-header`.

## Third round: floating leak, reorder, names, customize mode

### Floating showed the docked layout's rails

The bug: switching to floating left Measure/Shapes/Draw as stray rails beside
the group switcher.
- Both modes read one `toolStripDocks` map (and one `styleBarDock`).
- Docked, a group's edge means "my toolbar lives there".
- Floating, the same entry means "pin me as a palette over the page".

The fix: each mode keeps its own arrangement.
- `toolStripDocks` / `setToolStripDock` / `styleBarDock` / `toolStripOrder`
  read and write the current mode's.
- Floating persists under `floatingToolStripDock.*`,
  `floatingStyleBarDock` and `floatingToolStripOrder`.
- Reset clears both modes.
- Callers (toolbar, layout dialog, grips) needed no changes.

### Toolbar names off by default (`toolbarShowNames`)

- The group names cost ~350px.
- They are now off; the name is in each grip's tooltip and menu.
- Switches: Settings (`settings-toolbar-names`) and the layout dialog
  (`pdf-layout-show-names`).
- Result: 800px goes from 5 rows to 3.

### Customize mode (`toolbarCustomizing`, not persisted)

- Grips now show only while customizing (`PdfEditingToolbar.showGrips`).
  Outside the mode, `_barGrip` returns an empty box and `_toolBarGrip`
  returns null.
- The main toolbar ends with a Done button (`onDoneCustomizing`,
  `pdf-toolbar-customize-done`).
- Ways in:
  - View options → "Customize toolbars" (`pdf-shell-customize-toolbars`);
  - the layout dialog's `pdf-layout-customize`.
- The phone bar never shows grips.

### Reorder (`toolStripOrder`, per mode)

- **The data.** `PdfToolbarDragData` gained `id`, the dragged group.
  `PdfEditingToolbar.onToolStripOrder` receives the whole new order.
- **Dropping.** Each docked group toolbar is a `_ToolStripReorderTarget`
  while customizing.
  - It lands before or after the target, by which half the pointer is over.
  - A 3px primary bar marks the spot.
  - Dropping on a toolbar elsewhere also takes that toolbar's placement:
    an edge, or "with the main toolbar".
- **Keyboard and touch.** The grip's menu has "Move earlier" / "Move later"
  (`_shiftToolStrip`).
- **Rules.** `_visibleGroups` sorts by the order; unlisted groups keep stock
  order after the listed ones. Select stays out of the order, because it
  lives in the main toolbar.
- **Gotcha.** `PdfPanelDock.isHorizontal` means a *left/right* edge, which
  stacks vertically. `_stripAxis` already maps it that way; the drop target
  must too.

## Not done (considered)

- **The properties bar in the header's gap** would save its 48px row, but
  only on windows of about 1700px or wider. Its content is up to ~900px.
