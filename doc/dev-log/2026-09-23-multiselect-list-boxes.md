# Multi-select list boxes (#933)

A list box with the MultiSelect flag (/Ff bit 22) could only hold one value:
`PdfFormField.value` read /V as a single string, `setChoiceValue` wrote one
value plus a one-entry /I, and every option menu was single-choice.

## Model (`pdf_document/lib/src/form.dart`)

- `PdfFormField.multiSelectFlag` / `isMultiSelect`: only true for /FT /Ch.
  Bit 22 means something else on buttons and text fields, so the getter
  checks the field type as well as the bit.
- `values`: a /V array (string entries, in file order) or the single value
  as a one-element list, following the same reconciled-widget precedence as
  `value`. `value` is unchanged and still returns the first array entry, so
  existing callers keep working.
- `selectedIndices`: /I when it agrees with /V (same count, every export
  covered). Otherwise the indices come from /V, taking the first option whose
  export matches each entry. /I is optional, and another tool can rewrite /V
  without touching it, so trusting a stale /I would highlight the wrong rows.
- `topIndex`: /TI, 0 when absent.

## Filling (`form_editor.dart`)

`PdfEditor.setChoiceValues(field, values)`:
- Matches each value against export or display text, like `setChoiceValue`,
  dedupes, and sorts into option order.
- Writes /V as an **array when two or more** values are selected, a **plain
  string when exactly one** is (what Acrobat writes, and what single-value
  readers expect), and removes /V and /I when nothing is selected.
- Writes /I as the sorted indices and moves /TI so the first selected row is
  visible (it is left alone when that row is already in view).
- A field without MultiSelect takes at most one value: two or more throw, and
  one value goes to `setChoiceValue`.

There was no list-box row renderer before this. A list box was drawn like a
one-line text field showing the chosen display value. `_regenerateListBox`
now draws the real thing: one row per /Opt entry from /TI down, row height
`1.15 x` the /DA size (12pt when /DA says auto), and each selected row filled
in the usual viewer highlight (0x99C1DA) behind its text, which goes through
the shared `writePdfTextBox` per row. **Single-select list boxes use this path
too** (one highlighted row), so their appearance changes from "just the value"
to "the list with the value highlighted". Combo boxes, and list boxes with no
/Opt, keep the text path. `_regenerateChoice` is the single dispatcher, and
resize, page rotation and missing-appearance repair (`form_admin.dart`) all
call it.

## Editor

- `PdfEditingController.setFormChoiceValues(name, values)` returns false for
  an unchanged selection (compared as a set of exports), and for a refused one.
- `pickFormChoiceOption(name, export)` toggles the option on a multi-select
  field and replaces the value on any other choice field. All four option
  menus call it: the form layer's tap menu, the overlay menu, the right-click
  menu and the selected-field toolbar. On a multi-select field they show
  `CheckedPopupMenuItem`s with the current selection checked. The menu closes
  after each pick, so each tap is one undoable toggle.

## Other consumers of field values

- CLI `forms list` (`dart_pdf_cli` service): multi-select fields add
  `multiSelect: true` and a text-budgeted `values` array. `value` stays the
  first selection.
- `PdfFieldContext` (document_ai): an optional `values`, which is also in
  `toJson`, and the prompt text shows the whole selection joined with `, `.
- There is no FDF/XFDF export in the repo yet, so nothing to change there.

## Tests

- `pdf_document/test/form_multiselect_test.dart`: reading a foreign /V array,
  the array round trip with sorted /I, single-string and clear behaviour, the
  highlight count in the appearance, single-select rows, /TI scrolling, stale
  /I, and the refusals. The fixture is `buildListBoxFormPdf()`
  (`pdf_test_fixtures/src/list_box_form.dart`).
- `dart_pdf_editor/test/editing_form_multiselect_test.dart`: the controller
  API, undo, and a widget test of the checkable menu toggling options in and
  out.
- CLI `service_test.dart` and `document_ai_test.dart` cover the value
  surfaces.

## Left out

- The menu closes after each pick. A menu or sheet that stays open while you
  toggle several options would be nicer, but needs a custom popup.
- Choice-field authoring (adding list boxes) is still not supported. It is
  tracked separately on the FAQ page's "not supported yet" list.
