# Cloud callout tool

A new `PdfEditTool.cloudCallout` (Insert group, Shift+Q, `Icons.cloud_queue`)
places a callout whose text box is outlined by a revision cloud - Bluebeam's
Cloud+. The cloud is the box's *style*, not a separate annotation kind: the
placed annotation is an ordinary /FreeTextCallout with a cloudy border effect,
and the properties panel switches it to a plain rectangle (or back) at any time.

## Model (pdf_document)

- `PdfCalloutBoxShape { rectangle, cloud }` + `PdfAnnotation.calloutBoxShape`
  (null for a non-callout). The cloud is persisted as the **standard**
  `/BE << /S /C /I scale >>` (§12.5.4 Table 167), which FreeText supports, so
  viewers that regenerate appearances draw a cloud too.
- `hasCloudyBorder` now reads `/S /C` *and* the non-standard `/S /Cloudy` that
  this package used to write for cloud polygons; new polygons write `/C`.
- `addCallout(boxShape:, cloudScale:)` and `restyleCalloutBox(shape:,
  cloudScale:, outlineDash:)`. The latter shares `_calloutLocalFrame` with
  `restyleCalloutLeader` (extracted from it), so rotated callouts restyle in
  their authored frame.
- `_freeTextContent(cloudScale:)` fills + strokes `_appendCloudPath` around
  the text box **in page space** (before the page-rotation counter-transform),
  so the outline is the one the leader geometry assumes. /RD stays the text
  box; /Rect grows by `_cloudPadding` (`_calloutPad`).
- Every rebuild path reads the cloud off the dictionary: `_rebuildCallout`,
  the resize regenerate path, and the controller's remove-and-re-add rewrites
  (`_calloutShapeOf`/`_addCalloutLike` carry `boxShape` + `cloudScale`).

## Leaders meet the cloud, not the edge under it

Puffs stand ~14pt proud of the box at scale 1, so a leader ending on the box
edge would run visibly into an unfilled cloud. `_calloutLine(cloudScale:)`
pushes the base out along the edge normal by `_cloudOutlineHeight` - the
scallop over that point, approximated as a half-ellipse from foot to apex using
the exact per-edge scallop layout `_appendCloudPath` uses (clamped at 0, so at a
cusp the base stays on the edge) - and moves the knee stub past the puffs.

Because the stored base is now off the box, `_clampToBoxPerimeter` measures to
each edge *segment* rather than each edge line: a base pushed out past the left
edge near a corner would otherwise snap to the bottom edge and drift on every
rebuild (covered by "repeated rebuilds do not drift the leader base").
`restyleCalloutBox` re-seats bases only when the shape or scallop size changes;
a dash-only change preserves the lines exactly, like `restyleCalloutLeader`.

## Editor

- Overlay: `_calloutTool` covers both tools (same placement gesture); commit
  passes `boxShape` by tool.
- `PdfEditingController.addCallout(boxShape:)` uses `preferences.lineScale` for
  the scallops; the tool has its own `cloudCallout` style scope (text fields +
  `lineScale`), and "Set as default" on a cloud callout seeds that scope.
- `restyleSelectedCalloutBox(shape:, lineStyle:, cloudScale:)` - one revision.
- Properties panel (text group, under the outline rows): Box shape
  (Rectangle/Cloud), outline Line type, and a Scale slider shown only when a
  cloud is selected (`_common` throws on an empty list - guard it).
- New strings: `tbNameCloudCallout`, `tbTipCloudCallout`, `propBoxShape`,
  `propBoxShapeRectangle`, `propBoxShapeCloud` in every locale.

## Placement preview

`_calloutBoxPreview()` feeds the preview painter's `calloutBox`: during the
placement drag both callout tools outline the text box at the spot the release
will drop it (`_defaultPlacementRect(_dragCurrent)` - still no rubber band),
and the cloud tool draws its cloud around it with the cloud tool's own
`_paintCloudPolygon`. The cloud stays around the inline editor while the text
is typed (the editor is the box, so no outline then); it is painted after the
leaders, as the committed appearance stacks them.
