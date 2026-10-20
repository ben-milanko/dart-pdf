# Bulk form-field editing (#1041)

Select several form fields, then change their text style or size in one
edit. Before this, the style controls only worked when exactly one text
field was selected (`_selectedFormTextField` required `_selected.length ==
1`). The properties panel's multi-selection view also had no form rows.

## Selecting

- The form tool already supported Shift/⌘/Ctrl-click to toggle a widget in
  or out of the selection (`selectFormWidgetAt(toggle:)`).
- New: a Shift/⌘/Ctrl mouse drag on empty page area in the form tool draws
  a rubber band (`selectFormWidgetsIn`) instead of a new field. A plain
  drag still creates a field. The band always adds to the selection. The
  general `selectAnnotationsIn` can't be reused here because
  `PdfAnnotationBehavior.selectable` is false for widgets.

## Controller (`editing_controller.dart`)

- `_selectedFormTextFields` lists every distinct text field with a
  selected widget, primary (most recently selected) first. It skips other
  annotations and other field types. `_selectedFormTextField` (the single
  case) is now built on top of it.
- `canStyleSelectedFormField` is true for one or more text fields.
  `selectedFormFieldName` still needs exactly one, so single-field callers
  of `setFormFieldStyle(name, …)` work as before.
- `selectedFormFieldStyle` returns the primary field's style.
  `selectedFormFieldStyles` returns all of them so the UI can show
  "Varies". The parsing moved into `PdfFormFieldStyle.of(field)`.
- `setSelectedFormFieldStyle(...)` applies to every selected text field in
  a single `apply()`, so it is one revision and one undo step. Read-only
  fields are skipped. Edits keep the selection because /Annots slots don't
  move.
- `resizeSelectedFormWidgets({width, height})` sizes every selected widget
  through `resizeFormWidget` in one revision, so appearances regenerate
  per type. Each widget keeps its **top-left** corner, so a column of
  fields keeps its top edges in place. A null dimension is left alone.
  Sizes under 1pt and no-op resizes return false and add no revision.
- `selectedFormWidgetCount`.

## UI

- Properties panel (`editing_properties.dart`): `_formFieldControls` now
  covers the whole selection. Font, alignment, size, auto-size, multiline
  and colour show "Varies" when they differ. The toggles show the primary
  field's state. The size row appears if any field has a fixed size, so a
  mix of auto-size and fixed-size fields can be set to one size. With
  several widgets selected, `_buildMulti` adds the form text group and a
  Width/Height row. Those fields start blank with a "Varies" hint when the
  values differ, and commit through `_commitWidgetSize`. A blank field
  leaves that dimension alone. X/Y are not shown, because one shared
  position doesn't make sense for a group.
- `PdfFormFieldStyleControls` (the toolbar tune popup and the "Text
  style…" popup) and `pdfApplyFont` now call the bulk setter. The
  selection strip's tune popup shows the form style block for a
  multi-selection because it gates on `canStyleSelectedFormField`.

Tests: `dart_pdf_editor/test/editing_form_bulk_test.dart`.

## Left out

- The style toggles (bold/italic, alignment) show the primary field's
  state, not a tri-state. Applying one sets that value on every field.
- Bulk edits for non-text field properties (check box style, choice
  options) are not included.
