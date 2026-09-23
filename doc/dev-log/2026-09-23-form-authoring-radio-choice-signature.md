# Form authoring: radio groups, choice fields, empty signature fields (#934)

Before this, `PdfFormAdmin` (`pdf_document/lib/src/form_admin.dart`) could
only create text, check box and push-button fields, and `PdfFormFieldKind`
covered only those three. Every other field type could be filled but not
authored.

## pdf_document

- `addRadioGroup(page, name, [(rect, onState)...], {selected})` writes one
  indirect parent field (`/FT /Btn`, `/Ff` Radio | NoToggleToOff, `/V`,
  `/Kids`) and one pure kid widget per button (no `/T`, `/Parent` back to
  the group, `/AS`). Kids go on the page's `/Annots`. `/Fields` gets only
  the parent.
- `addRadioButton(group, page, rect, onState)` appends another kid. The
  page can differ from the group's other buttons. It refuses a group that
  is a single merged field/widget dict, because there are no `/Kids` to
  extend.
- Radio appearances come from the fill-time generator. `_appendRadioKid`
  seeds `/AP /N {onState: null, Off: null}` as placeholders, then
  `_generateRadioStates` runs `_regenerateButtonStates` on every widget
  still holding placeholders. That generator keeps state names, which
  `_ensureButtonAppearances` doesn't: it gives every widget
  `onStates.first`, which is wrong for a group. `/D` is a copy of the `/N`
  state dict (same stream refs). A later resize rebuilds `/AP` with `/N`
  only, which is fine.
- `addComboBoxField` / `addListBoxField(page, name, rect, options,
  {editable | multiSelect})`: `/Opt` holds a plain string when the export
  and display text match, and an `[export display]` pair otherwise.
  `field.options` reads both forms back the same way. The appearance is
  generated up front with `_regenerateVariableText(field, '')`.
- `setChoiceOptions(field, options, {editable, multiSelect})` backs the
  editor's options dialog. It clears a `/V` the new options no longer
  offer, unless the combo box is editable, and keeps `/I` in step for
  list boxes.
- `addSignatureField(page, name, rect)` creates a merged `/FT /Sig` widget
  with no `/V` and a blank `/AP /N`, and ORs `/SigFlags` with 1.
  `_attachSignatureField` in signature_editor.dart already filled an
  existing unsigned field by name and raises SigFlags to 3. Tests cover
  `saveSigned`, `saveSelfSigned` and `saveSelfSignedPades` filling an
  authored field, both after a save/reload and in the same editor session.
- `changeFieldType` accepts every type except `unknown`. Choice options
  carry over between combo and list boxes. A radio group's on-states
  become a choice field's options, and a check box's on-state becomes a
  one-button radio group. Values don't carry over. It throws `StateError`
  for a signed signature, since retyping would throw the signature away.
- `_installField` was split into helpers (`_checkFreshName`,
  `_prepareWidget`, `_ensureAcroFormDict`, `_appendRootField`,
  `_stageAcroForm`, `_registeredField`) so the split-field radio path can
  reuse them.
- `PdfFormField` gained only two constants, `noToggleToOffFlag` and
  `multiSelectFlag`. Multi-select reading and filling belong to #933, so
  there is no `isMultiSelect` getter here.

## dart_pdf_editor

- `PdfFormFieldKind` gained `radioGroup`, `comboBox`, `listBox` and
  `signature`, plus `fieldType` / `PdfFormFieldKind.of(type)`, which
  replace the per-site switches. `addFormField` creates a radio group with
  one `Choice1` button, and combo/list boxes with no options.
- `addFormRadioButton(name, {pageIndex, rect, onState})` places a
  same-size button 1.5 heights below the group's last button, or beside it
  if that would leave the crop box. It picks the next free `ChoiceN` and
  selects the new widget by hit-testing its centre (it's the topmost
  annotation there).
- `setFormFieldOptions(name, options, {editable, multiSelect})` returns
  false when nothing would change, so an unchanged dialog save adds no
  revision.
- UI: the new-field kind popup (`pdf-form-type-{radio,combo,list,signature}`)
  and the selected-field type menu reuse the existing `propFieldType*`
  labels. The selected-field toolbar (desktop icon buttons and the mobile
  overflow) and the form-field context menu gain "Edit options…"
  (`pdf-*-options`), "Add button to group" (`pdf-*-add-radio`) and the
  four new "Convert to …" entries. The options dialog is
  `editing_form_options.dart` (`showPdfFormOptionsDialog` +
  `PdfFormOptionsEditor`, exported).
- 11 new l10n keys. check_arb_coverage requires every locale, so they're
  translated in all 19 translation ARBs (en_AU/en_GB via
  `sync_english_locales`).

## Left out

- Tapping an unsigned signature field in the editor still does nothing. To
  sign into it, a host passes its name to `saveSigned(fieldName:)` and the
  other signing APIs. The app's sign dialog doesn't offer existing empty
  fields yet.
- Radio buttons use the check-mark appearance that the check box and
  resize code already draw, not a filled circle.

Tests: `pdf_document/test/form_authoring_test.dart`,
`dart_pdf_editor/test/editing_form_authoring_test.dart`.
