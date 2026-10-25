# Compact floating toolbar (#1161)

The desktop (non-compact) editing toolbar's floating cards took too much of
the page, and a side dock was worse: its contextual strip is a column beside
the rail, so every text label (`Content`/`Form`/`Redact`…, `Totals`,
`Scale 1:100`, the font chip) and the 96px opacity slider set the column's
width - up to ~170px of strip plus a 66px rail.

- **Density.** `_buildDesktop` wraps the cards in an `IconButtonTheme`
  (`VisualDensity.compact`, 20px glyphs - 48px -> 40px buttons), merged
  under any host `IconButtonTheme`. Group chips and the hand/select pair
  are 36px; the card padding is 6. The mobile/compact bar is untouched
  (it keeps touch-sized targets).
- **Side strips drop their text** (`_sideStrip`): `_LabeledToolButton`
  goes `iconOnly` (the tooltip carries the name), the strip label is
  dropped (the active rail chip names the group; a hint becomes an info
  icon with a tooltip), the scale chip becomes an icon button, the tune
  trigger uses the icon instead of the font chip, stroke presets stack, and
  the opacity slider stands up in a `RotatedBox`.

Measured with a throwaway widget-test screenshot harness at 1280x800: side
dock footprint (rail + widest strip) 254px -> 126px; bottom dock card
66px -> 54px tall, strip 64px -> 56px.
