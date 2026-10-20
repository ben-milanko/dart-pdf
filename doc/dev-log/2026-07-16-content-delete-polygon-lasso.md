# content-delete: drag a rectangle OR click a polygon lasso

Historical implementation notes. The current implementation and validation
are described in [the September refresh](2026-09-06-content-delete.md).

Follow-up to the content-delete tool (PR #112). The tool now mirrors the
cloud tool's hybrid gesture model: a **drag** rubber-bands a rectangle
(existing behaviour), and a **tap** starts (and each further tap extends)
a free-form polygon, finished by a **double-tap**. Both erase the page
content the region encloses.

## Model layer (`content_editor.dart`)

- Factored the region-delete body out of `deleteElementsInRect` into
  `_deleteElementsInRegion(elements, hitsBounds, sliceText)` — a
  bounds-membership predicate plus a text-run slicer. `deleteElementsInRect`
  passes the rect predicates; the new `deleteElementsInPolygon(elements,
  polygon)` passes polygon ones. Non-text elements that pass `hitsBounds`
  drop whole; text runs slice.
- `_textSlicePolygon` is the lasso counterpart of `_textSlice`: it walks
  the run's glyphs and erases those whose **centre point** (baseline
  cross-centre, advance mid along the axis) is inside the polygon —
  the same centre rule the rectangle slicer uses, so the two behave
  identically for an axis-aligned box. Centres are monotonic along the
  baseline, so the erased indices stay contiguous and reuse the single-cut
  `_slicedTextReplacement` (TJ gap that holds the tail in place).
- Geometry helpers, all page-space: `_pointInPolygon` (even-odd ray
  cast), `_polygonHitsRect` (vertex-in-rect OR rect-corner-in-polygon OR
  edge crossing), `_segmentsCross`. A polygon with < 3 vertices is a
  no-op.

Non-contiguous coverage (a concave lasso dipping in and out of one run)
collapses to the `[first, last)` span — acceptable for a lasso over a
line of text; a genuinely multi-cut run isn't worth the extra TJ
bookkeeping here.

## Controller (`editing_controller.dart`)

`deleteElementsInPolygon(pageIndex, polygon)` mirrors the rect method but
skips the pre-scan: `apply()` already drops a no-op edit (the editor
reports no changes), so a miss adds no revision.

## Overlay (`editing_overlay.dart`)

Generalised the cloud-tool hybrid plumbing to cover `contentDelete`:

- `_cloudPolyInProgress` → `_regionPolyInProgress`, gated by a new
  `_hybridPolyTool` (cloudPolygon || contentDelete). Used to stop a stray
  drag rubber-banding a rectangle once vertices are down.
- Tap drops a vertex for either hybrid tool; double-tap finishes.
  `_finishPolyPath` treats contentDelete as a closed region (min 3
  vertices) and commits via `deleteElementsInPolygon`, then clears the
  vertices and returns **without** an `_afterPath` afterimage (there's no
  shape to hold — the content is gone; the new revision renders).
- Hover rubber-bands the next edge; the tool-change cleanup clears an
  abandoned in-progress lasso.
- Preview: `_paintPathPreview` special-cases contentDelete to the orange
  `_elementChrome` dashed marquee with a faint fill (matching the
  drag-rectangle preview) instead of a shape stroke.

Toolbar tooltip and the `PdfEditTool.contentDelete` doc updated to
describe both gestures.

## Tests

- `content_edit_test.dart`: polygon slices enclosed glyph centres
  (`"first line"` → `"firne"`), removes a fully-enclosed path element,
  degenerate polygon is a no-op.
- `editing_test.dart`: "the content delete tool lassos a polygon to
  remove content" — three taps leave the region open (nothing removed,
  `dragPath` previewing), the double-tap closes it and clears the run.
