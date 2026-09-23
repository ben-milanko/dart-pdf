# Comb fields, /MaxLen and password masking (#931)

Text-field filling used to ignore three attributes: /MaxLen, the comb flag
(Ff bit 25) and the password flag (Ff bit 14). All three are now honoured
by the model, the appearance generator and both inline editors.

## Model (`form.dart`)

- `PdfFormField.maxLength`: the inheritable /MaxLen (§12.7.4.3), text
  fields only. A non-positive or non-numeric entry reads as no limit. A kid's
  `/MaxLen 0` shadows its parent's limit, because `inherited()` stops at the
  first non-null entry, and then reads as no limit.
- `PdfFormField.isComb`: the comb bit, but only when /MaxLen is set and the
  multiline, password and file-select bits are clear, as the spec requires.
  A malformed comb field therefore falls back to ordinary single-line
  layout. New constants: `fileSelectFlag` (bit 21) and `combFlag` (bit 25).

## Filling (`form_editor.dart`)

- `setTextValue` truncates to /MaxLen before writing /V
  (`PdfFormFilling.truncateToMaxLength`). It counts Unicode code points,
  not UTF-16 units, so a surrogate pair is never split. The alternative was
  to reject long values with an error. Truncation matches what a
  length-limited text box does while you type, so programmatic and
  interactive filling agree.
- `_regenerateVariableText` re-applies the truncation (for /V values another
  tool wrote) and masks password fields before layout. Every regeneration
  path (fill, resize, rotate, vertical-alignment clear) goes through this
  function, so none of them can draw the plain value.
- Comb layout is `_writeCombText`. The widget's full oriented width splits
  into MaxLen cells with no side padding, the same model as other
  renderers' comb layouts. Each character is centred in its cell with one
  `Td` per glyph inside a single `BT`/`ET`. /Q picks the starting cell for
  short values: left starts at cell 0, right ends at the last cell, and
  centre starts at `(MaxLen - n) ~/ 2`. The baseline uses the single-line
  ascent-centred placement, plus the saved top/bottom preference. Auto-size
  (`0 Tf`) takes the size from the height, then shrinks until the widest
  glyph fits a cell. The border and 1pt clip inset are unchanged.

### Password appearance: asterisks, not blank, not bullets

The appearance draws one `*` per character. The reasons:

- Bullets (U+2022) are byte 0x95 only under WinAnsiEncoding. A /DR font
  with StandardEncoding or MacRoman, or no /Encoding, would print a
  different glyph. `*` is 0x2A in every simple-font encoding and is in
  practically every embedded subset's source font.
- Leaving the appearance blank, as some viewers do, makes a filled
  password field look empty on the page and in print. The masked inline
  editor already shows the length, so the length isn't secret in this UI.

Because the appearance holds only asterisks, text extraction, search and
anything else that reads page or appearance content never sees the value.

**Not changed:** /V still stores the real value. §12.7.4.3 says interactive
readers "shall never store the value" of a password field. Changing that
would make `setTextValue` silently discard its input and break reopening a
filled form, so it's a separate decision. The CLI already redacts password
values (`dart_pdf_cli` `service.dart`).

## Editor (`dart_pdf_editor`)

- `FormInteractionLayer` (tap-to-fill, `editing_form_layer.dart`) and the
  form tool's double-tap editor (`editing_overlay.dart`) pass
  `maxLength: field.maxLength` and `obscureText: field.isPassword`. The
  counter is suppressed (`buildCounter` returns null), so the cap is silent.
  `obscureText` requires a single-line field, so a password field always
  edits single-line even if its multiline bit is set too.
- The commit afterimages (painted until the new raster lands) show the
  masked text for password fields.
- The menu/toolbar "Edit value" prompts don't prefill a password field's
  value into their plain dialog. The `PdfTextPrompt` typedef is public, so
  it gained no `obscure` parameter. A typed replacement is still visible in
  that dialog.
- Flutter's `LengthLimitingTextInputFormatter` counts grapheme clusters and
  `setTextValue` counts code points. For combining sequences the editor may
  accept a few more code points than /MaxLen, and the commit trims them.

## Tests

- `pdf_document/test/form_fill_test.dart`, group "/MaxLen, comb and password
  (#931)": inherited /MaxLen, the isComb gating, code-point truncation, comb
  cell positions (the Td deltas step exactly one cell), /Q anchoring for
  short comb values, the auto-size fit, and a password appearance that stays
  masked through a resize.
- `dart_pdf_editor/test/editing_form_interactive_test.dart`: the inline
  editor's maxLength cap, and masked editing plus commit for password fields.
- `dart_pdf_editor/test/editing_form_test.dart`: the form tool's editor is
  masked and capped too.

The limits list on `site/guides/pdf-forms-and-signatures.html` no longer
lists these, and the text-field row and the appearance paragraph mention
them.
