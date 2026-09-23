# Form scripts without a JS engine: the AF* helpers (#930)

Calculated fields, format, keystroke and validate actions now work for the
scripts real forms actually contain, which are nearly all one-line calls to
Acrobat's built-in AForm helpers. There is still no JavaScript engine.

## Where things live

- `packages/pdf_document/lib/src/form_scripts.dart` (standalone library,
  exported): recognition plus the Dart ports.
  - `parsePdfFieldScript(source, trigger)` is a tiny tokenizer, not a regex.
    It accepts exactly one `Name(args);` call. Comments, whitespace and a
    trailing `;` are ignored. Arguments can be numbers, strings (with JS
    escapes), booleans, `new Array(...)`/`[...]`, or a comma-list string
    (AFMakeArrayFromList). Anything else becomes a
    `PdfUnsupportedFieldScript` with a reason. A helper found under the wrong
    trigger (a format helper in /K, say) is also unsupported, so it never runs
    in the wrong phase.
  - Simplified field notation (`/*** BVCALC Qty * Price EVCALC ***/ ...`) is
    detected before the call parser. `_SfnParser` is recursive descent over
    `+ - * /`, parentheses, unary minus, numbers and field names (a backslash
    escapes, as in `Line\ 1`).
  - Script class hierarchy: `PdfFormatScript` / `PdfKeystrokeScript` /
    `PdfValidateScript` / `PdfCalculateScript` are sealed roles; the concrete
    classes are `PdfNumber{Format,Keystroke}Script` (shared `PdfNumberStyle`),
    `PdfPercent*`, `PdfDate*` (also covers AFTime_* and the legacy numeric
    `AFDate_Format(n)`/`AFTime_Format(n)` tables), `PdfSpecial*` (psf 0-3 and
    `AFSpecial_KeystrokeEx` masks), `PdfRangeValidateScript`,
    `PdfSimpleCalculateScript`, `PdfSimplifiedCalculateScript`.
  - `extension PdfFormFieldScripts on PdfFormField`: `scripts` (cached per
    field instance in an `Expando`, so form.dart is untouched), `displayFor`,
    `formattedValue`, `checkInput`, `acceptsPartialInput`. Scripts are read
    from the field dict's /AA, falling back to a kid widget's /AA; /JS can be
    a string or a stream (via `PdfAction.parse`).
  - `extension PdfAcroFormCalculations on PdfAcroForm`: `calculationOrder`
    (/CO first, then any calculated text field /CO leaves out, in field order,
    for producers that omit /CO) and `calculate({skip, overrides})`, a pure
    planner that returns the changed values without writing anything.
- `form_scripts_editor.dart` (part of editor.dart):
  `PdfEditor.enterTextValue` (user-entry semantics: keystroke commit, then
  validate, then store the normalised value, or throw
  `PdfFieldInputException`, which is an `ArgumentError`) and
  `recalculateFields()`.
- `form_editor.dart` has three hooks. `setTextValue`, `_selectButtonState`
  (checkbox/radio) and `setChoiceValue` call `_recalculateAfter(field)`.
  `_regenerateVariableText` runs text fields through `field.displayFor` and
  uses its `textColor` (negStyle 1/3 red) in place of the /DA colour. Every
  appearance path (fill, resize, rotate, restyle, flatten) goes through that
  one function, so the format applies everywhere with no further edits.

## Semantics decisions (checked against the AForm helper behaviour)

- /V stays raw and the format only reaches the appearance. The inline editor
  opens on the raw value, like Acrobat.
- `setTextValue` is unchanged: it is the programmatic setter (like assigning
  `field.value` from script) and skips keystroke/validate.
  `enterTextValue` is the user-entry path, and
  `PdfEditingController.setFormFieldText` now uses it.
- AFNumber_Format: sepStyle 0-4 (4 is `1'234.56`). negStyle 0 puts a minus
  first (before a prepended currency). 1 is red with no sign. 2 is
  parentheses around currency and number. 3 is red parentheses. A value that
  rounds to zero shows no sign. Empty and non-numeric values show `''`.
- AFNumber_Keystroke: the partial patterns are the helper's
  (`^[+-]?\d*\.?\d*$`, or with `,` for sepStyle 2/3). The commit is a little
  more forgiving than the helper, so what the formatted display itself shows
  reads back: the field's currency, *well-formed* thousands grouping, and
  `(n)` for a negative. `1,5` in a dot-decimal field is refused, not guessed
  at. Comma decimals are stored with `.`, as the helper does.
- AFPercent_Keystroke accepts a trailing `%` and divides by 100, so "15%"
  stores 0.15. That is our convenience. The helper would refuse it, and bare
  "15" still stores 15 (shown as 1500%), which is faithful.
- Dates: `pdfParseDate` tries an exact read of the format first. It then
  falls back to the helper's lenient read: numbers in the format's own
  day/month/year order, month names anywhere, am/pm. A 4-digit number is
  always the year, and one leading the input means ISO order. Too few
  numbers drops the year, which then defaults to the current one. A bare
  time means today. Two-digit years below 50 are 20xx. Keystroke commit
  keeps the value as typed; the format reprints it. An unreadable value
  displays unchanged.
- AFSpecial: `pdfPrintMask` is util.printx. It stops as soon as the source
  runs out, literals included (`99999-9999` over `12345` gives `12345`).
  The keystroke accepts either the masked form or the bare placeholders
  (the helper's two-pass check), and phone picks the 7- or 10-digit mask
  from the text.
- AFRange_Validate: inclusive bounds. Empty and non-numeric values pass.
  The messages are the helper's English sentences.
- Calculations: one pass in /CO order, faithful to the viewer model, so a
  wrongly ordered /CO leaves later fields stale (that is tested). Values
  seen by later fields include earlier results. Read-only calculated fields
  are written directly, without `_checkFillable`. The field the user just
  entered is skipped, so a hand-typed override stands until an input
  changes. AFSimple_Calculate rounds to 1e-6 like the helper. SFN results
  are cleaned to 15 significant digits (0.1*3 stores 0.3). Division by zero
  stores `''`. Only text fields are calculation targets.

## Editor UI (dart_pdf_editor)

`editing_form_layer.dart`:

- A recognised keystroke script becomes a `TextInputFormatter` that refuses
  characters as they are typed.
- Enter on a refused value keeps the editor open with a red label under the
  field (`pdf-form-input-error-label`). Gotcha: Flutter still calls
  `onSubmitted` after a custom `onEditingComplete`, so `onSubmitted` checks
  `_editError`.
- Leaving a refused value (blur or tap outside) drops it, as other viewers
  do, and shows a floating SnackBar (`pdf-form-input-error`) via
  `ScaffoldMessenger.maybeOf`.
- The afterimage paints `formattedValue`.

`PdfEditingController.checkFormFieldText` is the non-editing check.

The messages come from pdf_document in English. They are not in the editor's
ARB files yet.

## Left out

- Arbitrary JavaScript, including show/hide, `event.rc` logic, custom
  formats, and `AFExactMatch`/`AFMergeChange`-style helpers.
- Format on combo boxes (only text fields are formatted and calculated).
- Keystroke and validate checks on editable combo box entry.
- `/Next` action chains.
- Recalculation triggered by non-UI bulk paths such as `flattenForm` or
  merges (call `recalculateFields()`).
- A persistent "this form has scripts we skipped" warning in the editor
  chrome. The API exposes it (`field.scripts.hasUnsupported`); a host can
  surface it.

## Tests

- `pdf_document/test/form_scripts_test.dart`: helper semantics (recognition
  shapes, number sepStyle/negStyle/currency, keystroke partial/commit,
  percent, printd tokens, date parse edge cases, printx, special
  masks, range edges, calc ops, rounding, parent names).
- `pdf_document/test/form_scripts_fill_test.dart`: builds forms with
  `CosDocumentBuilder` (/AA as string and stream /JS, /CO optional). It
  covers the invoice chain (SUM, then SFN tax, then SUM total) in /CO
  order, stale-by-order, the no-/CO fallback, formatted appearances with raw
  /V, red negatives, flatten, and `enterTextValue` normalise/refuse.
- `dart_pdf_editor/test/editing_form_scripts_test.dart`: keystroke filter,
  Enter keeps the editor open with the reason, blur drops the value with a
  toast, and controller check/normalise.
