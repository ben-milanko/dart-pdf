# Line & shape properties in the annotation panel

The annotation properties panel (`editing_properties.dart`,
`PdfAnnotationPropertiesPanel`) only surfaced a subset of a line's
editable properties: a selected /Line or /PolyLine showed **Color** and
**Line type**, but not the stroke width, opacity, or — most visibly — the
start/end line endings. All of that was already wired through the
controller (`restyleSelected`, `setSelectedLineEndings`,
`selectedLineEndings`, `canSetLineEndings`) and reachable from the
toolbar's style menu; the panel just never built the rows. Shapes
(Square/Circle/Polygon) were already complete.

## What changed

- `_stroked` and `_translucent` (the subtype sets that gate the Stroke and
  Opacity sliders in `_styleControls`) now include `Line` and `PolyLine`.
  `restyleAnnotation`'s `'Line' || 'PolyLine' || 'Polygon'` case already
  honours `strokeWidth`/`opacity`, so no model change was needed — the
  sliders just drive the existing path.
- New **Line start** / **Line end** dropdowns appear in `_styleControls`
  when `controller.canSetLineEndings` (a single /Line or /PolyLine with a
  normal appearance). Each calls `setSelectedLineEndings(start:/end:)`,
  keyed `pdf-prop-line-start-ending` / `pdf-prop-line-end-ending`.

## Shared line-ending widget

The toolbar's `_StyleMenu` had a private `_LineEndingPainter` and
`_endingLabel` plus a `_lineEndingRow` builder. To reuse the same preview
in the panel without duplicating the painter, I pulled the painter and
label into a new `line_ending_controls.dart`:

- `pdfLineEndingLabel(PdfLineEnding)` — the human label.
- `PdfLineEndingPainter` — the short-segment preview (was
  `_LineEndingPainter`, verbatim).
- `PdfLineEndingDropdown` — a `DropdownButton<PdfLineEnding>` with the
  per-item preview icons; `atEnd` orients the preview, `dropdownKey` lets
  tests target it.

The toolbar's `_lineEndingRow` now wraps `PdfLineEndingDropdown` (keeping
its 86px label column); the panel's `_lineEndingRow` wraps it with a 78px
label to match the panel's row rhythm. Both read identically.

## Tests

`editing_properties_test.dart` gained a case that selects a line and
asserts the stroke/opacity/line-type/start-ending/end-ending controls all
render, that picking "Open arrow" for the end restyles in place
(`pdfLineEndings(...).$2 == openArrow`), and that the stroke slider moves
`borderWidth`. Existing line-ending and mobile-toolbar tests still pass
(the painter refactor is behaviour-preserving).
