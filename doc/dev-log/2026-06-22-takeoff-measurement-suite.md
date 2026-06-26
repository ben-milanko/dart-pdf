# Takeoff measurement suite (Slice 1)

## Construction takeoff — Slice 1: full takeoff suite

The AEC takeoff workflow lands its first slice: measurement beyond
length/area/perimeter, per-tool running totals, and a document-borne
(portable) drawing scale. Pure-Dart core in `pdf_document`; the editor
layer (`dart_pdf_editor`) only wires UI + persistence.

**New measurement kinds.** `PdfMeasurementKind` (moved from
annotation_editor.dart into `measure.dart` so the readers in
annotation.dart and the summary can share it) gained `count`, `volume`,
`angle`, `arc`, `slope`, and `areaCutout`. Geometry math is free
functions in measure.dart (`pdfPolylineLength`, `pdfNetPolygonArea`,
`pdfAngleDegrees`, `pdfSlopeDegrees`, `pdfArcMetrics` — circumcircle of
three points → radius/length/sweep). `PdfMeasure` grew a `volume` format
list (serialized under the non-standard `/V` key — viewers that don't
know it ignore it, we round-trip it) plus `formatVolume(pointArea,
depth)`, `formatAngle(deg)`, `realArea`/`realDistance` numeric accessors;
`PdfMeasure.scale` now also seeds default angle (`°`) and volume
(`unit³`) formats.

**Persisted extras (`/Takeoff`).** Several kinds share a subtype (slope
is a /Line, angle/arc are /PolyLines, volume/cutout are /Polygons), so
the kind + its inputs (depth, holes, group label) live in a namespaced
`/Takeoff` dict on the annotation (`PdfTakeoffData` in takeoff.dart,
read/write). Classic distance/perimeter/area stay inferred from the
subtype — `/Takeoff` is only written for the new kinds or when a label is
set. `PdfAnnotation.measurementKind` returns the explicit `/Takeoff /K`,
else the subtype mapping, **and** treats Bluebeam check-mark stamps
(`isCheckMark`) as `count` so the existing count tool feeds the totals.
`PdfAnnotation.measurementResult` (new) computes
`(kind, value, unit, text)` for every kind; `measurementText` now
delegates to it. (annotation.dart dropped its `dart:math` import — the
sqrt math moved to measure.dart helpers.)

**Authoring.** `PdfEditor.addMeasurement` rebuilt to branch by kind:
Line (distance/slope), PolyLine (perimeter/angle/arc — arc tessellates a
real curve for the appearance via `_arcPolyline` while storing the 3
control vertices in /Vertices), Polygon (area/cutout/volume — cutout
draws hole outlines), and a `/Square` "×" count marker (`_countMarker`,
no /Measure needed). New params `depth`, `holes`, `label`. The shared
caption helper became `_takeoffCaption` (anchors: segment midpoint,
angle/arc vertex, or centroid; count returns empty → no caption box);
`_appendMeasurementCaption` now reads `annotation.measurementKind` +
`takeoff` so a restyle/resize regenerates the *right* caption for every
kind (the old subtype-only inference would have mislabelled slope as
distance).

**Running totals.** `PdfTakeoffSummary.of(document)` (pure Dart, no
dart:ui) buckets every `measurementResult` by `/Takeoff /Label` (else
`kind · unit`), summing value + count per `PdfTakeoffGroup`
(`formattedTotal([measure])` renders through the scale so totals match
on-page captions). Convenience grand totals: `totalLength`, `totalArea`,
`totalCount`.

**Document-borne scale (portability).** `PdfEditor.setPageMeasurementScale`
writes the scale into the page's `/VP` viewport array (§12.9) — a single
Measurement viewport over the crop box — replacing any prior measurement
viewport. `PdfPage.measure` reads it back. So the calibration travels
*with the file*, surviving a reopen and portable across devices, not just
in the device preference. Controller: `persistScaleToDocument({pageIndex})`
and `adoptDocumentScale()` (seeds the session scale from the document
when it has none). `PdfMeasurementScale.fromMeasure` reconstructs the
editor scale from a document `PdfMeasure`.

**Editor + example wiring.** `PdfEditingController.addMeasurement` gained
`depth`/`holes`/`label`; `addCountMark`; live readouts `measuredAngle`,
`measuredSlope`, `measuredArc`, `measuredVolume`, `measuredNetArea`; and
`takeoffSummary`. New `PdfTakeoffPanel` widget (editing_takeoff.dart,
exported) renders the running-total register and listens to the
controller. The example app's AppBar gained a Σ "Takeoff totals" button
opening the panel in a bottom sheet. The overlay's `_measureKind`
switches got a `default:` arm (the 5 new kinds aren't wired as in-overlay
drag tools yet — controller API + panel only; full per-tool gestures are
a follow-up).

**Tests.** `pdf_document/test/takeoff_test.dart` (geometry, formatting,
each kind's round-trip + value, the summary, and the /VP scale reopen) —
note round-trips through `editor.save()` lose a little precision in the
serialized /X conversion factor, so numeric asserts use realistic
tolerances while the *formatted* captions (which round) stay exact.
`dart_pdf_editor/test/editing_takeoff_test.dart` (controller kinds +
readouts, totals incl. the check-mark count tool, persist/adopt reopen,
and a `PdfTakeoffPanel` widget test). Analyze clean across the workspace.
