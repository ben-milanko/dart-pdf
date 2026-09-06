# The inline free-text caret at deep zoom: Flutter's caret gutter (#692)

#691 fixed one half of the macOS caret detachment - Flutter's Apple
`-2 / devicePixelRatio` cursor nudge, which is a *screen*-space constant
applied in the editor's local pixels and therefore multiplied by the viewer's
transform. The app still reproduced the defect afterwards, and its regression
(asserting `RenderEditable.cursorOffset` and `getLocalRectForCaret`) still
passed. Both facts have the same explanation: **the caret was never wrong
relative to the editor's own text.** Within one `RenderEditable`, the caret
and the glyphs come out of the same `TextPainter`, so the only thing that can
separate them is `cursorOffset` or `_snapToPhysicalPixel` - which is exactly
what #691 measured, and exactly what it had already fixed.

What was still moving is the whole live line, off the box.

## The gutter

`RenderEditable` reserves a gutter at the end of every editable line for the
caret - `_kCaretGap` (a hard-coded `1.0`) plus `cursorWidth` - and lays the
text out inside what is *left* of the field:

```dart
double get _caretMargin => _kCaretGap + cursorWidth;      // rendering/editable.dart
final double availableMaxWidth = math.max(0.0, maxWidth - _caretMargin);
```

The paragraph is then painted at the field's origin, so a centred line sits
half a gutter, and a right-aligned line a whole one, left of where the box
centres it. Left-aligned text never notices - which is why the report was
about a *centred* Bluebeam box, and why nobody had seen it on ordinary
left-aligned notes.

The gutter is a constant in **layout** pixels, and the inline editor lives
under the viewer's zoom transform, so on screen it is `zoom x` that constant.
Measured off the composited frame, centred free text drifted:

| zoom | live text vs box centre |
| --- | --- |
| 4 px/pt | -2.75 logical px |
| 40 px/pt (transform 24x) | -13.25 logical px |

and right-aligned text twice that (-5.5 / -26.5). On a CAD sheet the fit
scale is small, so an 8pt em is only two or three layout pixels wide and half
a gutter is ~20% of a glyph: the caret at offset 0 stands off the first glyph
and the caret at `text.length` lands *inside* the last one - the two symptoms
in the issue, both growing with zoom.

## The fix

Hand the gutter back, out of the field's trailing content padding, so the
band the text aligns inside is the appearance's own text area at any zoom
(`_textEditRightPad` in `editing_overlay.dart`). A box on a big sheet can
have a 3pt inset under a layout pixel, i.e. smaller than the gutter; the
remainder comes out of the 2px chrome gutter instead
(`_textEditGutterOverflow`), which the border paints over either way, so
nothing visible moves. `pdfZoomAwareCaret` / `pdfCaretGutter` moved into
`editing_text_menu.dart` (already the shared home for in-page text-field
fixes) and the form-field inline editor now uses both - it had neither, so
its caret carried the full uncompensated nudge at zoom.

## Testing this class of bug

`editing_caret_zoom_test.dart` measures the **composited frame**, in physical
pixels, with the editor inside the transform: `RepaintBoundary.toImage` under
`tester.runAsync` (the byte conversion never completes in the fake async
zone), the box wash taken as the modal colour over the whole box interior
(a band tight around one line can be more glyph than background), and glyph
rows told from caret rows by run width - the Apple caret is drawn taller than
the text, so it owns rows above and below the line. It asserts, for left,
centred and right free text at 4 and 40 px/pt, that the painted caret hugs
the glyph it marks *and* that the painted line sits on the appearance's text
area. Reverting either half of the fix fails it; reverting #691's
compensation fails it too.

Gotchas for anyone extending it: `pumpAndSettle` never returns with an editor
open (the caret blinks), `setZoom` zooms about the viewport centre so the box
has to be placed there rather than scrolled to afterwards, and the viewer
clamps the transform at 24x - `setZoom(40)` on a fit-width page is 24x, not
31x.
