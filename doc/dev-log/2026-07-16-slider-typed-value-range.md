# Looser typed range for slider readouts

The editing UI's style sliders (stroke width, font size, opacity, eraser
size, line/char spacing, font width) each pair a `Slider` scaled to a
compact `min`..`max` with an editable numeric readout
(`PdfSliderValueField`). The readout used to clamp a *typed* value to the
same `min`..`max` as the slider, so e.g. a 12 pt max stroke could never be
set to 20 pt by typing - the scale that keeps the slider usable also
capped what you could enter.

Now the field's clamp is decoupled from the slider's scale.
`PdfSliderValueField` gained `fieldMin`/`fieldMax` (default to `min`/`max`,
so unchanged callers keep the old behaviour); the `_slider`
(`editing_toolbar.dart`) and `_sliderRow` (`editing_properties.dart`)
helpers thread them through. The slider thumb still moves only within
`min`..`max`; typing accepts the wider `fieldMin`..`fieldMax`.

Widened bounds (chosen "within reason / to not crash"):

- Open-ended point/size values - stroke width, eraser size, font size,
  font width, char spacing - clamp the typed field to `kPdfTypedSizeMax`
  (= 1000, in `editing_value_field.dart`). Far past any slider max but
  bounded so an accidental huge value can't blow up appearance generation
  or rendering. Stroke allows 0; char spacing allows the negative side too.
- Line spacing: 0.1..100×.
- Opacity: kept a true ratio - the field reaches 0% (fully transparent,
  below the slider's 0.05/0.1 floor) but never past 100%.

Note: the shared `_parsePoints` still strips non-`[0-9.]`, so a *typed*
char-spacing value can't currently go negative regardless of `fieldMin`;
that's pre-existing and only the positive side is widened in practice.

Test: `editing_properties_test.dart` "typing an exact value into a slider
readout" now asserts 80 pt is accepted (past the 16 pt slider max), 999999
clamps to 1000, and opacity 150 clamps to 100%.
