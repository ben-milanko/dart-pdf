# Stroke hit testing for line annotations

The select tool's `selectableAnnotationAt` used to hit everything but text
markups on `/Rect`, so a diagonal polyline, an unfilled polygon or a callout
claimed every click anywhere in its bounding box - mostly empty page that
belonged to whatever lay behind.

`PdfEditingController._strokeHit` now decides these shapes precisely
(page units, `_strokeHitTolerance` = 4 past the stroke's edge):

- **/PolyLine**: near a segment, plus a `max(10, 5w)` disc at each end when
  `/LE` draws an ending (the arrowhead size `_endingPath` uses).
- **/Polygon**: near the closed outline; inside too only when it has `/IC`
  fill. Cloudy borders widen the reach by the scallop bulge
  (`_cloudArcRadius * _cloudBulgeFactor`).
- **FreeText callouts**: the text box (`calloutBox`), every leader in
  `calloutLeaders` (arrow-tip disc when `/LE` is set), and a cloud callout's
  marked region - its *interior* stays hittable, because dragging inside the
  cloud is how it is moved (`editing_callout_test.dart`).

Measurements (`/Measure` or a takeoff value) keep the `/Rect` hit: their
caption is drawn off the line and must stay clickable. Plain `/Line` and
`/Ink` are unchanged (still `/Rect`); `inkAnnotationAt` already did the
same centerline test for the eraser.

Tests: `test/editing_stroke_hit_test.dart`; `editing_menu_test.dart`'s
polygon right-click now clicks the outline.
