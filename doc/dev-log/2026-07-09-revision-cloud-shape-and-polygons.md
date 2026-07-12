# Revision cloud: real puffs + polygon input

## What changed

Two things about the cloudy `/BE` border effect ("revision cloud"):

1. **The scallops looked like a stamp perforation, not a cloud.** The old
   generator drew a shallow, tangent-footed ripple whose arc radius was tied
   to the (usually hairline) stroke width - `max(4, strokeWidth * 3)` - so a
   default 2 pt stroke got ~6 pt bumps, dozens of them, each barely lifting
   off the edge. Rewrote it as proper revision-cloud puffs: each scallop is
   two quarter-arc Béziers that **leave the edge perpendicular** (so adjacent
   puffs meet in a cusp/neck) and bulge outward, with a fixed arc radius
   `max(12, strokeWidth * 4)` in page points and a 1.15x bulge so the puffs
   read as slightly-overlapping circles. Scallops are spread one per arc
   diameter (`round(edgeLen / (2*arc))`, min 1), and the bulge is capped at
   `arc * 1.15` so a lone puff on an awkward-length edge can't balloon past
   the padded `/Rect`.

2. **The cloud tool could only make rectangles.** Now it's a hybrid: **drag**
   still rubber-bands a rectangle, but a **tap** drops a free-form vertex and
   each further tap extends it - **double-tap finishes** (same close gesture
   as the polygon/polyline tools). Once one vertex is down the tool is "in
   progress" and a stray drag is ignored instead of restarting a rectangle.

## Where

- `pdf_document` `annotation_editor.dart`: `_appendCloudPath` (the appearance
  stream), plus `_cloudArcRadius` / `_cloudBulgeFactor` and a `_cloudPadding`
  that now matches the real puff height (`arc * 1.15 + strokeWidth`) so the
  `/Rect` and form BBox contain the scallops.
- `dart_pdf_editor` `editing_overlay.dart`: `_cloudPath` mirrors the same
  math for the live preview/afterimage. It maps the page-unit arc radius into
  view space (`max(12 * geometry.scale, strokeWidth * 4)`) so the preview
  lines up scallop-for-scallop with the committed appearance. Input wiring:
  `_onTapUp` adds a vertex for the cloud tool, `_onDoubleTap`/`_finishPolyPath`
  commit it via the new `PdfEditingController.addCloudPolygonPoints`, `_panStart`
  bails while a cloud polygon is in progress, and the build-time
  `_polyPoints` clear + `_onHover` rubber-band now keep the cloud tool alive
  even though it is deliberately *not* in `_polyTool` (that set adds points on
  pointer-down, which would kill the drag-rectangle path).

## Gotchas

- The preview painter (`_paintPathPreview`) and afterimage were already
  cloud-aware; only the *input* side (tap-to-add / double-tap-to-finish) was
  missing, so most of the change is gesture plumbing, not painting.
- Tap-to-add rides `onTapUp` (not pointer-down like the other poly tools) on
  purpose: `onTapUp` fires for a tap but not a drag, which is exactly the
  drag-vs-click arbitration the hybrid needs. The double-tap's extra coincident
  taps are dropped by the existing `distance >= 2` vertex de-dup.

## Tuning harness

Geometry was tuned against a Chromium screenshot of a faithful JS port of the
Dart algorithm (rectangle CW/CCW + triangle, `/Rect` box overlaid to confirm
the padding contains the puffs) rather than eyeballed blind.
