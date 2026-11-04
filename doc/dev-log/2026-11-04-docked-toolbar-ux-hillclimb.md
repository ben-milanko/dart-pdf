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

## Not done (considered)

- **First-fit packing**, so a later group back-fills an earlier row (Edit
  beside Shapes at 800px), would save a row at some widths. It needs a custom
  wrap render object, and it moves groups out of their reading order.
- **Dropping the group names** (`MARKUP`, `DRAW`, …) would save ~350px. They
  are the docked mode's only orientation aid, so they stay.
