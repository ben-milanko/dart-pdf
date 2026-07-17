# Rounded corners for rectangle shapes

Rectangle (/Square) annotations can now be drawn with rounded corners.

## Core (`pdf_document`)

- `PdfEditor.addSquare` gains a `cornerRadius` parameter (page points, 0 =
  square). Threaded through the private `_addShape` into `_shapeContent`,
  which now emits `ContentWriter.roundedRect` instead of a single `re` when
  the radius is positive. The radius is pulled in by the stroke half-width
  along with the rest of the box so the rounded outer edge stays inside
  `/Rect`; `roundedRect` clamps it to half the smaller side. `Circle` and
  every other subtype ignore the radius.
- The radius is recorded in the annotation's `/Border` array
  (`[hCornerRadius vCornerRadius width]`, §12.5.4). `/BS` still governs the
  actual border render (and hides `/Border` from conforming viewers), but
  the baked `/AP` appearance is authoritative so the rounding shows in every
  viewer regardless. We read the radius back from `/Border` in the resize
  path so a rounded rectangle keeps its corners when resized
  (`_regenerateResizedAppearance`, `Square` case).
- New `PdfAnnotation.cornerRadius` getter parses `/Border[0]`. The
  interpreter already reads `/Border[2]` as the synthesized-border width, so
  writing the width there stays consistent (that fallback only fires for
  annotations with no `/AP`, which ours always have).

## Editor UI (`dart_pdf_editor`)

- `PdfEditingPreferences.cornerRadius` — a persisted, style-scoped double
  mirroring `strokeWidth` (load, restore, snapshot, `_recordScoped`). Added
  to the rectangle tool's style scope (`_styleScopeFields`), which was split
  out of the shared rectangle/ellipse/polygon case so only the rectangle
  remembers a radius.
- `PdfEditingController.cornerRadius` getter/setter; `addRectangle` passes
  `preferences.cornerRadius` to `addSquare`.
- `_StyleFields.cornerRadius` gates a new "Corner radius" slider (0–40 pt) in
  the tune popup, shown only for the rectangle tool (`_groupStyleFields`
  `shapes` case). The `editing_test` style-menu test now expects three shape
  sliders (stroke, corner radius, opacity).

Not done: restyling the corner radius of an already-selected rectangle (the
slider only sets the creation default); ellipse/polygon rounding.
