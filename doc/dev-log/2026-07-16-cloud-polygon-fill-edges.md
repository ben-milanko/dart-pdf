# Cloud polygon fill: paint to the scalloped edges

## What changed

A cloudy (`/BE` Cloudy) filled polygon painted its interior colour only up
to the *straight* polygon footprint (the line through the /Vertices), while
the scalloped border puffs bulge outward past those edges. The result was an
unfilled crescent between each straight edge and its row of scallops - the
fill visibly stopped short of the cloud outline.

Now the interior is filled along the **scalloped cloud path** itself, so the
colour reaches the puffed edges.

## Where

- `pdf_document` `annotation_editor.dart` `_cloudPolygonContent`: instead of
  filling the straight vertex polygon (`f`) and then stroking the cloud path
  (`S`) as two separate constructions, it now builds the cloud path once via
  `_appendCloudPath` and fills+strokes it in one pass (`B`) - nonstroking
  colour for the fill, stroking colour for the outline. All three cloud
  callers (add, update, style-flatten) go through this function, so they all
  get the fix.
- `dart_pdf_editor` `editing_overlay.dart` `_paintCloudPolygon`: the live
  preview mirrored the same "fill the straight polygon" shortcut; it now
  fills the `_cloudPath` (already a closed path) so the preview matches the
  committed appearance.

## Tests

- `annotation_editor_test.dart` "cloud polygon carries border effect …" now
  asserts a combined `B` operator (fill+stroke of the cloud path) rather than
  separate `f`/`S`.
- The BBox-containment test is unchanged: the cloud path geometry didn't
  move, only what gets filled.
