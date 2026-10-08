# Font for dropdown (combo box) fields

Stacked on #1045 (bulk form-field style). The form-field style controls
(properties panel, toolbar tune popup, "Text style…" popup, font menu) now
act on choice fields - dropdowns and list boxes - as well as text fields.

## What changed

- `pdf_document`: `PdfEditor.setChoiceFieldStyle(field, {font, fontSize,
  autoSize, color, align})` in `form_styling.dart`. It writes the /DA and /Q
  a choice field shares with a text field, then regenerates through
  `_regenerateChoice`. The /DA rewrite is factored into
  `_setDefaultAppearance`, which `setTextFieldStyle` uses too. Embedded fonts
  needed no new work: the choice appearance paths (`_regenerateVariableText`
  for a combo box, `_regenerateListBox`) already read the /DR font back,
  including the Type0 show path.
- `dart_pdf_editor`: the controller's style targets went from text-only to
  `_styleableFieldTypes` (text, comboBox, listBox). `_styleFormField` sends
  each field to the editor call for its type. A choice field ignores
  `multiline`, and a multiline-only edit skips it entirely, so a dropdown
  isn't regenerated for nothing. The edit then adds no revision and returns
  false.
- `PdfFormFieldStyle.supportsMultiline` (false for choice fields) hides the
  Multiline switch in `PdfFormFieldStyleControls` and the properties panel.
  In a mixed selection the panel's switch reflects only the text fields.
- The field context menu's "Text style…" entry now appears for combo and
  list boxes too.
- Renamed #1045's `selectedFormTextFieldNames` to
  `selectedFormStyleFieldNames`. #1045 is unmerged, so nothing outside it
  used the old name.

## Notes

- A list box's auto size (/DA size 0) still draws rows at the conventional
  12 pt (`_listBoxAutoFontSize`). Shrinking every row to fit would make long
  lists unreadable.
- Tests: `pdf_document/test/form_styling_test.dart` (`setChoiceFieldStyle`
  group) and `dart_pdf_editor/test/editing_form_choice_style_test.dart`
  (fixture `buildListBoxFormPdf`).
