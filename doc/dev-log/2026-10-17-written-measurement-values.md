# Written measurement values (custom dimension tool)

A measurement can now show a value the user typed (`12'-6"`, `3.2 m`,
`TYP.`) instead of the one computed from the geometry and the scale - the
way a drafter writes a dimension the drawing isn't to scale for, or marks
up an uncalibrated sheet.

**Model (pdf_document).** `PdfTakeoffData.valueText`, stored as
`/Takeoff /Value`. Whenever it is set, `/Takeoff` is written even for the
classic distance/perimeter/area kinds (which otherwise are inferred from
subtype + /Measure), so `measurementKind` still resolves without a
/Measure. `PdfAnnotation.measurementResult` short-circuits on it: `text` is
the written value, `isCustom` is true, and `value`/`unit` come from
`pdfParseMeasurementValue` (takeoff.dart) so written values still total -
leading number (`1,250.5` thousands, or a lone decimal comma `1,5`), unit =
the trimmed rest; architectural feet-and-inches (`12'-6"`) read as decimal
`ft`; a bare number takes the measure's unit for the kind; no number at all
→ value 0, unit = the whole text (so `TYP.` items bucket and count together
in `PdfTakeoffSummary`).

**Authoring.** `PdfEditor.addMeasurement(valueText:)` - a written value
lifts the "needs a scale" `StateError`, becomes the caption and /Contents.
`_takeoffCaption(valueText:)` returns it at the kind's usual anchor, and
`_appendMeasurementCaption` no longer bails on a missing /Measure when there
is a written value - so every appearance regeneration (reshape, restyle,
resize, endings, caption font) keeps the written caption. That is the point:
a written value describes the drawing, so dragging the line doesn't
recompute it. `PdfEditor.setMeasurementValue(page, annot, text)` writes,
rewrites or clears it in place (reshape-based regeneration, /Contents
refreshed); clearing drops `/Takeoff` entirely for a classic kind with no
label, and is refused when the annotation has no /Measure to fall back to.
`setMeasurementCaptionStyle` accepts a written-value measurement too.

**Editor (dart_pdf_editor).** New `PdfEditTool.measureCustom` ("Custom
measurement (type value)", measure group, `Icons.edit_note`, Shift+W):
`_MeasureCustomTool` is a line-drag tool with `measureKind: distance` (so
the live readout shows the scaled length when there is a scale) and its own
style scope whose defaults put a closed arrow on both ends. Its commit needs
a prompt, so `commitLineDrag` returns false and the overlay's
`_commitCustomMeasurement` asks via `PdfEditorPresenter.text`
(`measCustomValueTitle`, pre-filled with `measuredDistance` or empty) and
stamps through `PdfEditingController.addMeasurement(valueText:)`; blank or
cancel stamps nothing. The afterimage bookkeeping moved into
`_holdLineAfterimage` so both commits share it. It is *not* in the toolbar's
`_isMeasureTool` / `editor_commands`' `_toggleMeasureTool` lists - arming it
never asks for a scale.

Existing measurements: `canEditSelectedMeasurementValue`,
`selectedMeasurementValue`, `selectedMeasurementValueIsCustom`,
`setSelectedMeasurementValue` on the controller, surfaced as the annotation
context menu's "Edit measurement value" (`pdf-annot-menu-measurement-value`,
in the node/leader row); a blank answer goes back to the computed value.

**Sheet overflow.** The 8th measure tool pushed the compact tools sheet's
grid to a third row, which overflowed the sheet at phone heights (the
`compact measure tools sheet` takeoff test caught it). The sheet body is now
a `SingleChildScrollView` - still sized to content, scrolls only when a
group outgrows it.

**Tests.** `pdf_document/test/measurement_value_test.dart` (parsing, no-scale
authoring, override under a scale, totals, reshape keeps the value,
set/clear/refusals) and `dart_pdf_editor/test/editing_measure_custom_test.dart`
(drag → prompt → stamp with and without a scale, cancel, controller
set/clear/undo), plus a context-menu case in `editing_menu_test.dart`.
