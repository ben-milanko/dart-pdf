# Outline colour in the tune menu (clouds and other shapes)

## What changed

The tune popup (`_StyleMenu`, the `Icons.tune` gear) already carried a "Fill"
colour row for shapes but no stroke/outline colour — that was only reachable
from the toolbar's colour swatches. For a revision cloud that's backwards: a
cloud usually has no fill, so its outline is the colour you actually want to
change, yet the tune menu only offered "Fill".

Added an **"Outline"** colour row to the tune popup, rendered just above
"Fill". It sets the creation default (`controller.color`) and, with a
restylable shape selected, restyles it in place via
`controller.restyleSelected(color:)` — the same path the toolbar swatches use.
No "none" swatch (a shape/cloud/line always strokes), matching the text-colour
row.

## Where

- `dart_pdf_editor` `editing_toolbar.dart`:
  - `_StyleFields` gains a `strokeColor` flag (folded into `isEmpty`).
  - `_groupStyleFields` sets it on the whole **shapes** group; `_selectionStyleFields`
    sets it on the Square/Circle/Polygon, Line/PolyLine, and Ink cases —
    wherever a stroke width already applies (`canStroke && supportsStrokeWidth`).
  - `_StyleMenuState._setStrokeColor` is the setter; the build method computes
    `strokeColorValue` (selected shape's `/C` when restyling, else the creation
    default) and renders the `pdf-shape-outline` `PdfColorSwatchRow`
    (`allowNone: false`) before the existing `pdf-shape-fill` row.

## Gotchas

- Revision clouds are cloudy `/Polygon`s (`canRestyle` is true for Polygon
  regardless of `/BE`, unlike Square/Circle which bail on a cloudy border), so
  `restyleAnnotation`'s Polygon branch already rewrites `/C` and regenerates
  the appearance keeping the cloud puffs (`_restyleRegenerate` reads
  `hasCloudyBorder`). The new UI just surfaces that existing capability in the
  tune menu.
- On desktop this is partly redundant with the toolbar colour swatches, but
  it puts the outline colour beside the fill colour where users look for it and
  matches the request ("from the tune menu").

## Test

`editing_shape_styles_test.dart` — "cloud outline colour from the tune menu":
selects a cloud, opens the tune popup, taps the blue outline swatch, and
asserts the annotation's `/C` became blue, no "none" swatch is offered, and the
cloudy border survives the restyle.
