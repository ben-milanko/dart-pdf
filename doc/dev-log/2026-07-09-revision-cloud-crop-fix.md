# Revision cloud: uncrop the puffs + preview the first polygon edge

Follow-up to `2026-07-09-revision-cloud-shape-and-polygons.md`. Two reported
defects: the committed cloud's scallops were clipped at the edges (corners
rendered as flat brackets), and building a polygon cloud gave no feedback
until the third vertex.

## The crop

`_appendCloudPath` draws each scallop's apex `arc * 1.15` past the polygon
edge (plus half the stroke). For a rectangle every point of an edge sits on
the box extreme, so the puffs protrude by the *full* bulge on all four sides.
`_cloudPadding` returned exactly that bulge - but `_pointBounds` insets the
`/Rect` and form BBox by only `pad / 2 + 1`, so the box was padded by roughly
half the puff height and the form XObject clipped the outer half of every
scallop (~5.5 pt at a 2 pt stroke; the visible "edges removed").

Fix: `_cloudPadding` now returns `2 * arc * bulgeFactor + strokeWidth`, so
after `_pointBounds` halves it the inset is `arc*1.15 + strokeWidth/2 + 1` -
the full bulge plus half the stroke plus a point of margin. `annotation_editor.dart`.

The new `annotation_editor_test.dart` case parses every `m`/`l`/`c` operand
in the appearance stream, takes the path's bounding box, and asserts it (plus
half the stroke) fits inside the form BBox - and that the puffs still bulge
past the vertices. It fails on the old padding (path reaches 105.6, BBox
starts at 111.1) and passes now.

## The missing first-edge preview

`_paintPathPreview` sent the cloud tool straight to `_paintCloudPolygon`,
which needs 3+ points, so a polygon cloud with one vertex placed + the hover
point (2 points) drew nothing at all - no rubber-band. It now falls back to
the straight connecting path for < 3 points, so placing the first side gives
feedback like every other poly tool. `editing_overlay.dart`. (The drag
rectangle preview and the 3+-vertex polygon preview already drew clouds and
are unchanged.)

## Verified

Rendered committed rectangle + triangle clouds to PNG (via
`PdfPageRenderer.renderImage`): corners are now complete scallops, nothing
clipped. `annotation_editor_test.dart` (all 71) and the three `editing_test`
cloud widget tests pass; `dart analyze` clean on the touched files.
