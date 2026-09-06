# The toolbar swatches read back the selection's colour

Selecting an annotation left the toolbar's palette ringing the *last-used*
creation colour. Draw a red box, pick blue for the next one, then click the
red box: the ring said blue while every other control in the same strip -
stroke width, opacity, line style, shape fill - had already switched to
showing the box's own values. Tapping a swatch there recolours the
selection, so the row was a readout of something it wasn't about to change.

## The fix

`PdfEditingController.displayColor` (editing_controller.dart, beside
`selectedAnnotationStyle`) is the one reading:

```dart
Color get displayColor {
  if (!canRestyleSelected) return color;
  final rgb = selectedAnnotation?.behavior.style.color;
  return rgb == null ? color : Color(0xFF000000 | rgb);
}
```

Two gates matter:

- **`canRestyleSelected`, not just "something is selected".** It is exactly
  the condition under which a swatch tap recolours in place
  (`_applyColor` → `restyleSelected`). A selected annotation the editor
  can't restyle still only moves the creation default, so it keeps showing
  that default. Same predicate `_strokePresets` and the tune popup already
  use.
- **Reading `behavior.style.color` (an `int?`) rather than
  `selectedAnnotationStyle.color`.** That record maps a missing `/C` to
  `Color(0xFF000000 | 0)`, i.e. black - fine as a mutation default, a lie
  as a readout. An image stamp or a shape with no `/C` falls back to the
  creation colour instead of claiming to be black. Free text resolves to
  its `/DA` text colour, which is what a swatch tap changes there.

Call sites in editing_toolbar.dart: `_colorCluster` (swatch rings, the
"more colours" palette icon *and* the colour picker's `initial`),
`_mobileSwatches`, and the tune popup's `strokeColorValue` - which also
picks up the null-`/C` fix, since its old `annotationStyle?.color ??
controller.color` could never see the null.

`_StyleFields`' free-text `textValue` was left alone on purpose: it is gated
on `canRestyleSelectedText` (any single FreeText), a broader condition than
`displayColor`'s, and already carries its own fallback chain.

Tests: `test/editing_selection_color_test.dart` - controller readback
(no selection / selected / deselected / after a restyle / free text /
multi-select primary) plus a widget test that watches the 3px ring move
between the red and blue palette swatches as the selection comes and goes.
The strip only carries the palette when a group is open, so the
no-selection half of that test arms the rectangle tool.
