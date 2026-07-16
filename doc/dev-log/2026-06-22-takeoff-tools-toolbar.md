# Takeoff measurement tools in the toolbar

Follow-up to the takeoff measurement suite: the five new measurement kinds
were reachable only through the controller API + the totals panel, so the
register filled from distance/perimeter/area + count alone. This wires the
new kinds into the editor toolbar/overlay so they're drawable. Four landed
as tools (slope, angle, arc, volume); area-cutout still needs a multi-ring
gesture and stays controller-only.

**Tools.** `PdfEditTool` gains `measureSlope`, `measureAngle`,
`measureArc`, `measureVolume` (after `measureArea`). Each is added to the
`measure` `_ToolGroup` in editing_toolbar.dart, routed through
`_armMeasureTool` (so it prompts for a scale first), and given the measure
style scope (`_styleScopeKey`/`_styleScopeFields` in
editing_controller.dart) - slope/angle/arc carry line endings, the closed
volume polygon doesn't.

**Gestures (editing_overlay.dart).** Poly tools place one vertex per
pointer-down and finish on double-tap; line tools commit on pan-end. So:
- `measureSlope` joins `_lineDragTool`; `_commitLineDrag` now picks the
  kind from `_measureKind` (distance vs slope) instead of hard-checking
  `measureDistance`.
- `measureAngle`/`measureArc`/`measureVolume` join `_polyTool`. A new
  `_fixedPolyCount` getter returns 3 for angle/arc; `_addPolyPoint`
  auto-finishes once that many clicks land (the user clicks three points
  and it commits - no double-tap). `_finishPolyPath` marks volume (and
  area) `closed`, computes `minPoints` from `_fixedPolyCount`, and gained
  `angle`/`arc`/`volume` cases. Volume routes to `_commitVolume`, which
  awaits a depth via the new `showPdfDepthDialog` (editing_measure.dart)
  then stamps the polygon with the depth - the early-return clears the
  in-progress poly state before the (synchronous) afterimage block, so a
  cancelled depth dialog drops the polygon cleanly.
- `_measureReadout` shows live values for all of them: slope through
  `measuredSlope`, angle through `measuredAngle`, arc through
  `measuredArc`; volume shows the footprint area while drawing (its depth
  isn't known until placement finishes).

Two `switch (_tool)` *statements* (pan-start dispatch, ~2257) are
exhaustive over the enum, so the new tools had to be added to the
line-drag and poly arms there too - the analyzer flags a missing case, so
nothing silently falls through.

Because both front-ends host the editor through the shared
`PdfEditorView`/`PdfEditingToolbar`, the new tools appear in the example
app and the DartPDF `app/` automatically - no per-app wiring.

**Tests.** `dart_pdf_editor/test/editing_takeoff_tools_test.dart` pumps a
real `PdfViewer(editing:)` and drives each tool: a slope drag → /Line
slope (45°), three angle clicks → /PolyLine 90° (auto-finish), three arc
clicks → swept length (π ft), and a volume polygon + double-tap → depth
dialog → /Polygon 800 ft³, plus a unit test that `showPdfDepthDialog`
returns the entered value. Gotcha: with `initialFit: width` the page is
taller than the 600px test surface, so gesture points must sit near the
page top (high page-Y) to stay on-screen - points near page-Y 100 map
below the viewport and never hit. Analyze clean across the workspace.
