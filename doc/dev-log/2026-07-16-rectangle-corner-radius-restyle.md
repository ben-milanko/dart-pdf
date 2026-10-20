# Corner radius as a restyle property for selected rectangles

Follow-up to `2026-07-16-rectangle-corner-radius.md`, which added corner
rounding only as a *creation* default (the tune slider set
`PdfEditingController.cornerRadius`, and restyling an already-placed
rectangle was called out as out of scope). This adds it as an editable
property of a selected /Square.

## Core (`pdf_document`)

- `PdfEditor.restyleAnnotation` gains a `double? cornerRadius` parameter,
  folded into the "nothing to change" early-return guard. In the
  `Square || Circle` case it rewrites the `/Border` array
  (`[hCornerRadius vCornerRadius width]`, §12.5.4; the width mirrors the
  current stroke) and lets the existing `_restyleRegenerate` →
  `_regenerateResizedAppearance` path rebake the rounded `/AP` — that path
  already reads the radius back from `annotation.cornerRadius`, so no new
  geometry code. Radius `0` drops `/Border` and restores square corners.
- Rounding is rectangle-only. A `cornerRadius`-only call on a /Circle now
  returns false instead of staging a pointless regeneration (a circle has
  no corners), guarded before the shared Square/Circle body so a
  colour/width/opacity change on a circle still works.

## Editor UI (`dart_pdf_editor`)

- `PdfEditingController.restyleSelected` gains `cornerRadius`, threaded to
  every selected annotation (subtypes that don't round ignore it, so a
  mixed selection is safe). New `canRoundSelectedCorners` (every selected
  annotation is a restylable /Square) gates the control, and
  `selectedCornerRadius` exposes the primary rectangle's current radius for
  display.
- `_selectionStyleFields()` sets `cornerRadius: canRoundSelectedCorners` on
  the Square/Circle/Polygon branch, so the selection strip's tune popup
  shows the slider for a selected rectangle (and only a rectangle).
- The existing "Corner radius" slider is now restyle-aware, mirroring the
  stroke slider: a `_draggingCornerRadius` live readout, value from
  `selectedCornerRadius ?? cornerRadius`, and `onChangeEnd` calls
  `restyleSelected(cornerRadius:)` when a selection is being restyled
  (else it just updates the creation default).

## Tests

- `annotation_restyle_test.dart`: rounding a placed square rebakes Bézier
  corners + records `/Border` and keeps the same appearance object number;
  dialing back to 0 re-squares and drops `/Border`; a radius-only call on a
  circle is a no-op.
- `editing_shape_styles_test.dart`: `restyleSelected(cornerRadius:)` rounds
  and re-squares a selected rectangle (selection survives, control
  reflects it); the controls are off / no-op for a selected ellipse.
- `editing_test.dart`: a widget test opens the selection-strip tune popup
  on a selected rectangle and drags the `pdf-corner-radius` slider,
  asserting the annotation (not just the creation default) rounds.
