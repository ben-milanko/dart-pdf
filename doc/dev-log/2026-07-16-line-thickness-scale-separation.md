# Separating line thickness from pattern scale

## Problem

The size of a shape's dash pattern and a cloudy /Polygon's scallops were
both derived from the pen width (`strokeWidth`): `PdfLineStyle.dashArray`
multiplied its dash units by the stroke, and `_cloudArcRadius` was
`max(12, strokeWidth * 4)`. So you couldn't have a thin outline with big
puffs, or a heavy line with tight dashes - thickness and pattern moved
together.

## Change

A separate **pattern scale** (a multiplier, `1` = the historical look)
now drives dash and cloud sizing, decoupled from the pen.

- `PdfLineStyle.dashArray(strokeWidth, {scale})` (dart_pdf_editor
  `line_style.dart`): the dash unit is `max(strokeWidth, max(2, 2*scale*m))`.
  The scale drives the nominal size; `strokeWidth` only floors each segment
  so the gaps stay visible under a heavy pen. At `scale: 1` + the default
  2pt pen the arrays are byte-identical to before.
- `_cloudArcRadius(strokeWidth, scale)` (pdf_document
  `annotation_editor.dart`): `max(strokeWidth*4, 12*scale)`. The
  `strokeWidth*4` term stays only as a crowd-avoidance floor. Threaded
  through `_cloudPadding`, `_cloudPolygonContent`, `_appendCloudPath`.

## Persistence

Dashes already round-trip: the scaled lengths live in the stored
`/BS /D` array, so restyle keeps them. Clouds had nowhere to keep the
scallop size (it was recomputed from the pen on every regenerate), so the
scale is stored on **`/BE /I`** - the border-effect intensity, which in
Acrobat already tracks scallop size, so the overload is semantically
aligned and round-trips. `PdfAnnotation.cloudBorderScale` reads it back
(default 1). `addPolygon(cloudScale:)` writes it; `reshapeLineAnnotation`
and `_regenerateLineLikeAppearance` read it; `restyleAnnotation(cloudScale:)`
updates `/BE /I` before regenerating so the regenerate picks it up.

Latent fix along the way: the line-like restyle regenerate never re-derived
a cloud's `/Rect` from the padded footprint, so a scallop that grew (a
bigger pen *or* scale) was clipped by the unchanged form BBox.
`_regenerateLineLikeAppearance` now recomputes the cloud bounds from the
points + `_cloudPadding` and rewrites `/Rect` (unrotated path; the rotated
path re-derives its own local rect as before).

## UI

- `PdfEditingPreferences.lineScale` (persisted, in the tool-style scope
  memory next to `lineStyle`).
- `PdfEditingController.lineScale`, `selectedLineScale` (a cloud's
  `/BE /I`, else null), and `restyleSelected(scale:)` - which recomputes
  the dash array from the scale (a pen-width change alone no longer
  resizes the dashes) and updates the cloud `/BE /I`.
- A **"Pattern scale"** slider (0.5×–4×) in the toolbar style popup and
  the properties panel, shown wherever the line-type control is
  (`_StyleFields.lineScale`).
