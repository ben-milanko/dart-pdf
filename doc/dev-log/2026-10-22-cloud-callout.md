# Cloud callout tool

`PdfEditTool.cloudCallout` (Insert group, Shift+Q, `Icons.cloud_queue`) is
Bluebeam's Cloud+: drag a revision cloud around the area to mark, type the
note, and a plain leader joins the note to the cloud. It is **one** annotation -
an ordinary /FreeText /FreeTextCallout that also marks a region - so the note
drags on its own (the leader follows), the cloud drags the whole thing, and the
properties panel switches the cloud to a plain polygon/rectangle (and dashes it).

A first cut drew the cloud around the *text box* (`/BE` on the callout); that is
not what a cloud callout looks like, and it was replaced before merge.

## Model (pdf_document)

- `PdfCalloutRegion` (vertices, `PdfCalloutRegionShape { cloud, polygon }`,
  `cloudScale`, `dash`) and `PdfAnnotation.calloutRegion`. Stored as a point
  array under `kPdfCalloutRegionKey` (`DartPdfCalloutRegion`) plus a style dict
  under `kPdfCalloutRegionStyleKey`; the appearance stream draws it, so other
  viewers still show the cloud.
- The region key joined every flat point-key list (`'QuadPoints', 'L',
  'Vertices', 'CL', kPdfCalloutRegionKey`) in annotation_editor (move, resize,
  rotate, local-frame restyle), annotation_group_editor and annotation_clipboard,
  so every transform carries the region for free. A new path that maps callout
  points must include it.
- `addCallout(region:)` - with a region the first leader's target is computed:
  `_calloutRegionTip` takes the point of the region outline nearest the box
  centre and, for a cloud, moves it out by `_cloudOutlineHeight` (the scallop
  over that point, half-ellipse approximation of `_appendCloudPath`; it can be
  negative at a cusp, so the tip touches the drawn outline). The base attaches
  to the box edge facing the tip (`attach: null` - a region callout never pins
  its base), so moving the note re-aims the leader.
- The region outline is stroked with the leader's colour/width, its own dash,
  no fill, drawn after the leaders and before the text box; /Rect grows by
  `_calloutRegionPad`.
- `_rebuildCallout` reads the region (or takes one in the rotated local frame
  from `_calloutLocalFrame`, extracted from `restyleCalloutLeader`) and always
  recomputes geometry for region callouts (never `preservedLines`).
- `reshapeCallout(region:)` and `restyleCalloutRegion(shape:, cloudScale:,
  dash:)`.
- Cloud polygons now write the spec's `/BE /S /C`; `hasCloudyBorder` still reads
  the old `/S /Cloudy`.

## Editor

- Placement: the drag lays out the cloud (`_openCloudCalloutEditor`); the note
  opens up-left of it (`_cloudCalloutNoteRect`, first corner with room); a tap
  drops a default 120x72pt cloud. Commit calls
  `PdfEditingController.addCloudCallout` - borderless note in the tool colour,
  leader + cloud in `textBorderColor ?? color`, no arrowhead,
  `preferences.lineScale` scallops.
- Preview: the painter's `calloutBox` record (region polygon + cloud flag,
  note outline, plain leader). Drag shows cloud + note outline + leader; typing
  keeps cloud + leader around the editor; the arrow callout's drag outlines the
  box it will drop.
- Selected cloud callout: vertex handles are the region corners
  (`reshapeSelectedCalloutRegion`); a press inside the cloud (off the note)
  sets `_moveWholeCallout` and the move commits
  `moveSelected(wholeCallout: true)`; a press on the note moves the note only.
- Properties: a "Marked area" group - Outline (Cloud/Polygon), Line type, Scale
  (clouds only); `restyleSelectedCalloutRegion`.
- Strings: `tbNameCloudCallout`, `tbTipCloudCallout`, `propRegion`,
  `propRegionCloud`, `propRegionPolygon` in every locale (the row label reuses
  `propOutline`).
- Widget tests: keep taps inside the 800x600 test view (y > ~340pt page space
  at fit-width) and grab notes in their middle - a touch press near a small
  note's edge lands on a resize handle.
