# Keep the space after the last page its nominal size at any zoom

**Symptom.** Scrolled to the end of a drawing pack in the editor, the last
page's bottom edge sat near the top of the viewer with ~730 px of blank
canvas below it, at a displayed zoom of only 74%.

**Cause.** `PdfViewer` pads the list after the last slot by
`pageSpacing + trailingPadding` (12 + 144 in `PdfEditorView` while the
desktop toolbar floats at the bottom). That padding is in **list space**, and
above fit the list rides the zoom transform, so the tail scaled with the
pages: 156 px x the zoom-window scale. Fit width is set by the widest page,
so in a pack with a long strip or A0 sheet, an A3 page at an ordinary 74%
already sits ~5x past fit, which works out to about 780 px of blank. The
screenshot's horizontal scrollbar thumb (~1/5 of the track) gave the scale
away.

**Fix.** `_PdfViewerState._trailingScale` records the settled zoom-window
scale (at least 1) in `_settleTransformChange`, the debounced settle every
transform change reaches. The list's trailing padding is
`_trailingExtent = (pageSpacing + trailingPadding) / _trailingScale`, so it
shows as 156 px on screen at any zoom. While a gesture is still moving, the
tail keeps its previous size until the settle. A smaller tail shortens the
scroll range. No clamp is needed for that: `Scrollable` applies the
viewer's `NeverScrollableScrollPhysics` (the list's physics while zoomed)
on top of the platform's clamping or bouncing physics, and those pull an
out-of-range position back after the relayout. A test pins this behaviour.
A layout-axis flip resets `_trailingScale` to 1 together with the
transform.

Spacing *between* pages still magnifies with zoom on purpose. It is part of
the zoomed content.

**Test.** `test/viewer_trailing_padding_test.dart`: a landscape-A3 pack
ending in a portrait sheet, wheeled to the end at 1x/2x/5x fit. Without the
fix the gap reads 312 / 780 px at 2x / 5x; with it, 156 px everywhere. A
second case zooms to 4x while already at the end, in both vertical and
horizontal layouts: the range must shrink by 3/4 of the tail and the
scroll must stay on its end. A `ScrollPosition` held across that zoom is
stale, because the physics flip swaps the position, so the test reads it
fresh each time.
