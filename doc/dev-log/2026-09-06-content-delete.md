# Content deletion (#112)

The Delete content tool is in the shared Edit catalogue (toolbar, mobile
picker and command palette), with localized labels and Shift+E. Drag a
rectangle, or click polygon vertices and double-click to close a lasso.
The orange preview uses the same even-odd fill rule as polygon hit testing.
Switching tools clears an unfinished lasso. Each completed deletion is one
undoable revision; a miss creates none. Annotations are untouched.

`PdfEditor.deleteElementsInRect` and `deleteElementsInPolygon` remove
non-text elements whose bounds overlap the region. Text is sliced by
encoded glyph centre, preserving the font's bytes and replacing each removed
glyph with its measured advance in a `TJ` array. Original kerning entries
remain, including advances at the end of a run so the following show operator
keeps its position. A concave lasso can remove several disjoint spans.

`PdfContentGlyph` records the glyph centre, byte length and advance from
`PdfPageElements`' font decoder. Enumeration accounts for character/word
spacing, horizontal scale, text rise and q/Q text-parameter restoration.
Text matrices reset at BT; font parameters persist. Move/stand-in operations
compensate for horizontal scale when replaying the recorded advance.

Non-text paths finish with `n` instead of their paint operator. This keeps
any pending W/W* clipping path and graphics-state changes intact. Unbounded
elements are skipped. Font advances are measured; glyph heights remain
approximate. Composite slicing supports Identity-H; other composite
encodings, malformed composite strings and text establishing a clip are
left alone. Form XObjects and images remain whole elements.

The earlier Helvetica/axis-estimation slicer and unused rectangular
clip-mask eraser have been removed. Regression coverage includes suffix and
whole-run deletion, concave lassos, rotated/reflected text, TJ backtracking,
spacing, composite glyphs, Unicode ligatures, clipping paths, tool changes,
undo/redo and a raster comparison outside the removed glyph.
