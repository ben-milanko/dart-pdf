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

When /V holds the value, the appearance draws one `*` per character. A
withheld value draws a fixed 8 (see below). The reasons for asterisks:

- Bullets (U+2022) are byte 0x95 only under WinAnsiEncoding. A /DR font
  with StandardEncoding or MacRoman, or no /Encoding, would print a
  different glyph. `*` is 0x2A in every simple-font encoding and is in
  practically every embedded subset's source font.
- Leaving the appearance blank, as some viewers do, makes a filled
  password field look empty on the page and in print.

Because the appearance holds only asterisks, text extraction, search and
anything else that reads page or appearance content never sees the value.

## Password values kept out of the file (follow-up)

§12.7.4.3 says interactive readers "shall never store the value" of a
password field. The first cut still wrote /V. Ben's decision: don't write
it, and remember the value on the device instead.

- **pdf_document:** `PdfFormFilling.setPasswordValue(field, value,
  {storeValue = false, documentId})` removes /V (from reconciled widgets
  too) and sets the private `/DartPdfPasswordWithheld true` marker.
  - The appearance is a **fixed** 8 asterisks
    (`withheldPasswordMaskLength`), or blank for an empty value. Once the
    value isn't in the file, the appearance is the only trace of it left,
    so it shouldn't give away the length. Masks with one asterisk per
    character stay for the /V path, where the value is in the file anyway.
  - The marker is what lets a later redraw (resize, rotation) keep drawing
    the mask. It only records that the field is filled.
  - Refuses non-password fields.
  - `setTextValue` is unchanged and still writes /V for library callers
    (backward compatible). It drops the marker.
- **Document identity:** `pdfPermanentDocumentId` (new
  `document_identity.dart`) uses trailer /ID[0], or the SHA-256 of the
  opened bytes when there is no /ID.
  - Incremental saves carry /ID forward, so every revision keeps the key.
  - The fallback would change on the first save, so a withheld fill in a
    file without /ID writes `[id id]` as the trailer /ID. The saved file
    then answers to the same key.
  - Copies of a file share an /ID, so they share remembered values. That's
    intended.
- **dart_pdf_editor:** `PdfFormSecretStore` (`readAll`/`read`/`write`/
  `remove`/`clearDocument`), with `InMemoryFormSecretStore` and
  `SecureFormSecretStore`. The secure one keeps one JSON object per
  document in flutter_secure_storage, plus an index for `clearAll`. It
  mirrors `PdfIdentityStore`. The key is the lowercase hex of the permanent
  id (`pdfFormSecretDocumentId`) + the field's fully qualified name.
  - `PdfEditingController(formSecretStore:)`: `setFormFieldText` on a
    password field goes through `setPasswordValue` and files the value in
    the store.
  - `formFieldTextValue(field)` is what the inline editors prefill from.
  - `formPasswordMask(value)` gives the afterimages the same mask the file
    draws.
  - `forgetFormSecrets()` clears the document's entries.
  - Without a store, behaviour is unchanged.
- **Undo/redo:** `_revisionSecrets` runs parallel to `_revisions` (like
  `_revisionImpacts`). A password fill records a fresh map through
  `_pendingSecrets` in `_finishRevision`. Undo and redo write the diff
  between the two revisions' maps to the store, which therefore always
  holds the current revision's values. `_resetTo` (redaction burn) keeps
  the current map.
- **Loading:** `_loadFormSecrets` runs at construction (`formSecretsLoaded`
  completes when it's done). It only adopts values for fields the opened
  file still shows as withheld and filled (password flag, no /V, marker
  set), so a stale entry for a field someone cleared elsewhere is ignored.
  - Values fill in via `putIfAbsent` across the revision maps. No revision
    is created and the document isn't dirtied.
  - Store errors are swallowed: an unreadable keychain loses the remembered
    value, never the edit.
- **App:** `app/lib/form_secrets.dart`. `appFormSecretStore` is the secure
  store off the web and in-memory on the web (flutter_secure_storage's web
  backend keeps its key next to the data, so it isn't secret there).
  `DocumentTab` passes it to every session.
- **What can leak:**
  - Flatten, save, export and autosave only ever see the file bytes, which
    hold the mask.
  - The CLI reads /V and finds nothing.
  - A /V that an **earlier** revision of an incrementally saved file already
    holds stays in that file's history. Withholding stops new copies; it
    doesn't rewrite old ones.
  - There is no "forget" button in the UI yet, only the controller API.

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
- `pdf_document/test/form_fill_test.dart`, group "setPasswordValue
  withholds /V": /V absent and the value nowhere in the file, a mask that
  doesn't depend on length, the mask surviving a resize, empty clears it,
  storeValue/setTextValue restore /V, non-password fields are refused,
  the trailer /ID is written when missing (and an existing /ID is kept),
  and flatten burns only the mask.
- `dart_pdf_editor/test/form_secret_store_test.dart`:
  - no store keeps the old behaviour;
  - with a store, the value goes to the store and never into the bytes
    (flatten included);
  - reopening the saved bytes restores the value without dirtying the
    document (a fallback-id file);
  - a different /ID doesn't get it, and a stale entry is ignored;
  - undo/redo keep the store in step;
  - clearing the field and `forgetFormSecrets` remove the value;
  - `SecureFormSecretStore` round-trips over the flutter_secure_storage
    mock.
- `app/test/form_secrets_test.dart`: secure off the web, in-memory on it,
  and document tabs use `appFormSecretStore`.

The limits list on `site/guides/pdf-forms-and-signatures.html` no longer
lists these, and the text-field row and the appearance paragraph mention
them.
