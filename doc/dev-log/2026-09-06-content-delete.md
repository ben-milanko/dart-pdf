# Content deletion (#112)

The Delete content tool is in the shared Edit catalogue (toolbar, mobile
picker and command palette), with localized labels and Shift+E. Drag a
rectangle, or click polygon vertices and double-click to close a lasso.
The orange preview uses the same even-odd fill rule as polygon hit testing.
Switching tools clears an unfinished lasso. Each completed deletion is one
undoable revision; a miss creates none. Annotations are untouched.

`PdfEditor.deleteElementsInRect` and `deleteElementsInPolygon` erase the
portions of bounded graphics inside the region. Crossing vectors, images,
and Form XObjects retain their outside portions. Text is sliced by
encoded glyph centre, preserving the font's bytes and replacing each removed
glyph with its measured advance in a `TJ` array. Original kerning entries
remain, including advances at the end of a run so the following show operator
keeps its position. A concave lasso can remove several disjoint spans.

`PdfContentGlyph` records the glyph centre, byte length and advance from
`PdfPageElements`' font decoder. Enumeration accounts for character/word
spacing, horizontal scale, text rise and q/Q text-parameter restoration.
Text matrices reset at BT; font parameters persist. Move/stand-in operations
compensate for horizontal scale when replaying the recorded advance.

`_RegionGraphicsClipper` wraps crossing draws in an inverse, even-odd PDF
clip. It captures path coordinates under the construction-time CTM and
replays them under the paint-time CTM, retaining curves, stroke widths,
dashes, fills, and resource references. Stroke bounds include line width,
joins, and ExtGState settings. The original pending W/W* clip takes effect
after painting, as before; paths under construction survive an interleaved
image or Form invocation. Fully enclosed graphics can be removed outright.
The saved result remains vector content with PDF clipping, without rasterizing.

Unbounded elements are skipped. Font advances are measured; glyph heights remain
approximate. Composite slicing supports Identity-H; other composite
encodings, malformed composite strings and text establishing a clip are
left alone.

The earlier Helvetica/axis-estimation slicer and unused rectangular
clip-mask eraser have been removed. Regression coverage includes suffix and
whole-run deletion, concave lassos, rotated/reflected text, TJ backtracking,
spacing, composite glyphs, Unicode ligatures, clipping paths, tool changes,
undo/redo and a raster comparison outside the removed glyph. Graphic raster
tests require every pixel outside the cut (apart from a boundary margin) to
remain identical, and every interior pixel to be cleared. They cover curves,
dashes, compound paths, changing transforms, pending clips, concave lassos,
images, Forms, thick strokes, and repeated cuts. A rotated-page overlay test
drags the tool and verifies the resulting pixels through undo and redo.
