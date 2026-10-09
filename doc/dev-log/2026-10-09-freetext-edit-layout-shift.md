# Opening a free-text box to edit: no more face, wrap or baseline shift

Reported against a tight one-line CAD label (`(PJ267/14)`, centred, red):
selected, it read as one line in Arial-ish Helvetica; double-clicked into
the inline editor, it changed face, wrapped onto two lines and dropped.
There were three independent causes, all in `editing_overlay.dart`.

## 1. The editor asked the host for "Helvetica"

`_textEditUiFamily` mapped the base-14 families to the platform names
`Helvetica` / `Times New Roman` / `Courier`. The page never draws them that
way: `CanvasPdfDevice._styleFor` draws unembedded base-14 text in the bundled
metric-compatible TeX Gyre clones (`font_substitution.dart`). Most
Windows/Linux/Android hosts have no Helvetica, so the editor fell back to
whatever the engine picked. That face is wider than Helvetica's AFM advances,
so a box the appearance had fitted to the width (the generator wraps at
`width - 2 * 3pt` using those advances) overflowed and wrapped as soon as it
opened. The editor now asks for `pdfBundledSubstituteFor(baseFont).packageFamily`
with the renderer's own host fallbacks behind it (`_textEditUiFallback`). The
resize preview and the post-commit afterimage (`_wrappedTextBox`) get the same
face.

A box whose appearance embeds its font also opened in Helvetica, because the
editor's default style came from `/DA` alone (`selectedTextStyle`). It now
takes `selectedTextFont`, which recovers the embedded font from the appearance,
and registers it for preview. The field's base style is built from that
default style rather than from `_textEditFont`, which can only hold a base-14
face.

## 2. The first baseline was guessed

The appearance writes the first baseline at `3pt + ascent * size` below the
box top (`writePdfTextBox`, `_freeTextRichContent`). The field approximated
that with `pad - 0.1 * size`. That only holds for one face's ascent/descent
split at a 1.2 line height, and it ignored the line-spacing setting.
`_firstBaselineShift` now lays out a painter exactly like the field (same
style, strut and height behaviour) and pads, or translates when the shift is
negative, by the difference. The result is cached per style, so typing costs
nothing extra.

The gotcha that cost a round: the `TextField` merges the Material 3 theme's
body style, which sets `leadingDistribution: even`, while the measuring
painter never sees the theme - so the real line sat 2pt off the replica.
The field style, the strut and the afterimage now all pin
`TextLeadingDistribution.even` explicitly. Pinning `proportional` instead
also lines the baselines up, but it moves the selection line box ~0.4px
and breaks the end-of-text caret check from #1052; `even` leaves the field
laid out exactly as before.

## 3. OS text scaling

The page ignores the platform text size. The editor didn't, so at 200%
system text the live text was twice the committed size. The field now sits
under `MediaQuery.withNoTextScaling`, and the afterimage uses
`TextScaler.noScaling`.

## Test

`editing_text_edit_test.dart` ("opening a box to edit keeps its face and
first baseline in place") runs at a 2x OS text scale with a 1.6 line spacing.
It asserts the field's family is the bundled Heros, and that the editor's
first baseline and the post-commit afterimage's both land at
`top + (3 + 14 * 0.718)pt`. On the old code it fails on the family check.
