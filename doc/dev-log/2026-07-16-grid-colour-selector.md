# Grid colour selector: palette + recents + document colours

Added a swatch **grid** to the annotation colour picker, plus two
context-aware quick-pick rows: the colours the user recently chose, and
the colours already used in the open document.

## What changed

- `PdfColorPicker` (`editing_color_picker.dart`) now renders labelled
  swatch grids under the value-entry row:
  - **Palette** - a fixed general-purpose set (`PdfColorPicker.defaultSwatches`:
    a grayscale ramp plus a spread of hues). Always shown; pass
    `swatches: const []` to hide it.
  - **Recent** - from the new `recentColors` param (empty ⇒ hidden).
  - **In document** - from the new `documentColors` param (empty ⇒ hidden).
  Each grid deduplicates by RGB (alpha ignored - the picker deals in opaque
  colours), wraps to the picker's 260px width, and rings the swatch that
  matches the current colour. Tapping a swatch adopts it into the model and
  refreshes the SV area, hue slider, and value fields. Swatch keys are
  `pdf-color-swatch-<grid>-<HEX>`; grid containers are `pdf-color-grid-<grid>`.
  `showPdfColorPicker` gained matching `recentColors`/`documentColors`
  params and now wraps its content in a `SingleChildScrollView` so the taller
  dialog never overflows on short screens.

- **Recents persistence** (`editing_preferences.dart`): `recentColors`
  getter + `noteRecentColor(Color)`. Move-to-front, deduped by RGB, capped
  at 18, stored as a `StringList` of RGB ints under
  `dart_pdf_editor.editing.recentColors`. Re-noting the current newest colour
  is a no-op (no write, no notify).

- **Document colours** (`editing_controller.dart`):
  `documentAnnotationColors({limit = 24})` gathers each annotation's `/C`
  stroke and `/IC` interior colours across all pages, most-frequent first,
  deduped by RGB. Cheap and synchronous (a dict read per annotation) - unlike
  the existing `documentContentColors`, which scans page content streams and
  is async for large docs. The picker's "In document" grid is annotation
  colours; the colour-processing dialog keeps its own page-content list.

- **Wiring**: new helper `pickEditingColor(context, controller, initial:)`
  (`editing_color_pick.dart`) opens the picker with the preferences' format +
  recents and the controller's annotation colours, and records the committed
  colour as a recent. Routed through the annotation-styling entry points:
  the properties panel (`editing_properties.dart`), the toolbar "More
  colours" button and the text-box fill/border rows (`editing_toolbar.dart`,
  via a new optional `pickColor` callback on `PdfColorSwatchRow`), the inline
  free-text colour (`editing_overlay.dart`), and form-field colour
  (`editing_form_style.dart`). The colour-processing dialog and the page-
  colour picker pass `recentColors` (+ `noteRecentColor`) but not a document
  grid. The stamp-template editor and the standalone styled-text prompt keep
  the plain picker (no controller in scope) - they still get the palette grid.

## Gotchas

- `PdfColorSwatchRow.pickColor` is optional and defaults to a plain
  `showPdfColorPicker`, so callers without a controller (the styled-text
  prompt) still work and stay decoupled from the editing layer.
- Removing the now-unused `editing_color_picker.dart` import from
  `editing_toolbar.dart`/`editing_properties.dart`/`editing_overlay.dart`/
  `editing_form_style.dart` after swapping to the helper is easy to miss -
  the analyzer flags it as `unused_import`.

Tests: swatch-grid rendering/selection/dedup in `editing_test.dart`
(`PdfColorPicker` group), recents move-to-front/dedup/cap/persist in
`editing_preferences_test.dart`, and `documentAnnotationColors`
frequency-ordering + limit in `editing_test.dart`.
