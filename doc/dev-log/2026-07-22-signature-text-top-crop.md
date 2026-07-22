# Signature detail text clipped at the top of the box

The visible-signature appearance box (`_installSignatureAppearance` in
`signature_editor.dart`) draws its two detail blocks - the large name in
the left panel and the "Digitally signed by … / Date … / Reason …" lines on
the right - vertically centred via `writePdfTextBox`'s
`PdfTextBoxVAlign.centerBlock`. In tight boxes the top line's ascenders were
being shaved against the top edge (see the reported "Digitally signed by …"
crop).

## Cause

`centerBlock` placed the first baseline one ascent below the centred block
top:

```
blockTop = box.bottom + (box.height + N * lineHeight) / 2;
firstY   = blockTop - ascentPts;
```

That pins the first line's ascent flush to `blockTop` and drops the entire
per-line leading (`lineHeight - fontSize`, ~0.3·fontSize here) *below* the
baselines. The block is therefore biased upward by half a line's leading.
The auto-fit loop in `_drawSignatureText` grows the font until
`N * lineHeight ≈ boxH`, so `blockTop ≈ box.top` and that upward bias pushes
the first line's ascenders to within a fraction of a point of the clip - less
than the amount real glyph tops exceed the nominal 718/1000 ascent, so they
get clipped. Measured top margins collapsed to 0.2–0.95 pt while the bottom
kept 2–4 pt of slack.

## Fix

Split the leading symmetrically: reserve half of it *above* the first line's
ascent.

```
final halfLeading = math.max(0.0, (lineHeight - fontSize) / 2);
firstY = blockTop - halfLeading - ascentPts;
```

This is the standard leading model (line box = `lineHeight`, glyph em =
`fontSize`, leading split top/bottom). Top and bottom margins are now equal up
to a constant `ascent + descent - fontSize` residual (the metric ascent+descent
of 925/1000 is a hair under the em) - top margins rose to 0.9–2.3 pt across the
same box heights and the first line clears the clip. Only the signature box
uses `centerBlock`; form fields use `centerLine`/`top` and are untouched.

## Tests

`text_box_appearance_test.dart` - updated the `centreBlock` baseline
expectation for the half-leading offset and added "centreBlock balances the
top and bottom margins" asserting the top margin is positive and the top/bottom
difference is exactly `ascent + descent - fontSize`.
