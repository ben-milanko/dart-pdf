# Corner radius on the properties panel

Follow-up to `2026-07-16-rectangle-corner-radius-restyle.md`, which made
corner rounding an editable property of a selected /Square but only
surfaced it in the toolbar's tune popup. The properties panel - the other
place a selection's style is edited - had no row for it, so a rectangle's
radius was invisible there.

## Editor UI (`dart_pdf_editor`)

- `editing_properties.dart`'s `_styleControls()` gains a "Corner radius"
  slider (`pdf-prop-corner-radius`, 0–40 pt, typeable past the scale up to
  `kPdfTypedSizeMax`), placed after stroke width and before the line-style
  rows. It is gated on `PdfEditingController.canRoundSelectedCorners` - the
  same gate the toolbar uses - so it shows only when *every* selected
  annotation is a restylable /Square. Ellipses, polygons, text markups and
  the rest never see it.
- The value comes from the selected annotations' own `cornerRadius`
  (`_common` over the selection, so a mixed multi-selection reads "Varies"
  like the other rows) rather than the creation-default preference: the
  panel is selection-only, so unlike the toolbar's shared slider there is no
  armed-tool case to fall back to and no `preferences.cornerRadius` write.
  `_draggingCornerRadius` holds the live thumb value while a drag is in
  flight, mirroring `_draggingStroke`; the restyle commits one revision on
  release via `restyleSelected(cornerRadius:)`.
- The readout is unit-suffixed ("12 pt"), so it passes a `parse` that strips
  the suffix - the default `double.tryParse` would reject its own display
  string and revert the typed value.

## l10n

New `propCornerRadius` key (the panel uses `prop*` keys; `tbCornerRadius` is
the toolbar's). Translations reuse the already-translated toolbar string in
all 20 locale ARBs; regenerated with `flutter gen-l10n`.

## Tests

`editing_properties_test.dart`: dragging `pdf-prop-corner-radius` rounds a
selected rectangle (and typing an exact value into the readout commits it);
a selected ellipse gets the stroke row but no corner-radius row.
