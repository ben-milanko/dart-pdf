# 2026-07-22 — i18n phase 2: no-context strings (app + example)

Sibling of the editor-package no-context refactor
(`2026-07-22-i18n-no-context-refactors.md`, PR #499). That session cleared the
`dart_pdf_editor` package's inventory of user-facing English produced where no
`BuildContext` was in scope; this one clears the remaining app/example items the
#499 note flagged as "their own change". English extraction is now complete
across all three bundles.

## The pattern (unchanged)

The enum / platform / error code is the stable key; the visible string is
resolved from the localizations at the consumer, which has a context. Where the
string was built inside a context-less helper, the label is threaded in as
plain data (a resolved `String`) rather than a `BuildContext`, so nothing has to
carry a context across an async gap.

## What landed (20 new ARB keys)

- **`settings_screen.dart` default-app help** — the two platform `switch`
  getters (`_defaultAppSubtitle`, `_defaultAppInstructions`) dropped their
  seven literal arms each. They now resolve one ICU `select` key apiece
  (`settingsDefaultAppSubtitle` / `settingsDefaultAppInstructions`, branches
  `web/windows/macos/linux/android/ios/other`, `other` = Fuchsia) from a small
  `_defaultAppPlatform` selector. Both call sites already had a context.
- **OCR chip label** — `OcrJobStatus.label` (a getter on the pure model, which
  only imports `foundation`) is gone. The four phase strings now live in the app
  ARB (`ocrChipDownloadingModel` / `…Percent` / `ocrChipRecognising` /
  `ocrChipFinishing`) and resolve through a new presentation helper
  `ocrStatusLabel(l10n, status)` (`app/lib/ocr_status_label.dart`). The chip in
  `editor_screen.dart` calls it with `appL10n(context)`; `ocr_status_test.dart`
  drives the same helper through `AppLocalizationsEn()`, so the string coverage
  is preserved without pinning English on the model.
- **`XTypeGroup` file-picker filter labels** — the desktop file dialog's
  type-filter dropdown was the last English in the picker flow. The `const`
  groups in `file_io.dart` (PDF / Images / DartPDF stamps),
  `digital_signature.dart` (RSA private keys / X.509 certificates), and the
  example's `main.dart` (PDF / Images / Fonts) became **functions taking the
  localized `label`**; the platform matchers (extensions/MIME/UTI) stay `const`.
  The `file_io` pickers gained a `String` label param and the savers a
  `required String …Label`; every caller resolves `appL10n(context).fileType*`
  (app ARB `fileTypePdf`/`fileTypeImages`/`fileTypeStampBundle` +
  `appSigKeyFileType`/`appSigCertificateFileType`; example
  `exFileTypePdf/Images/Fonts`). `devtools_panel.dart` stays English (out of the
  app l10n) and passes a literal.
- **Signing key/cert parse errors** — the package model
  `PdfDigitalSignatureIdentity.fromFiles` used to throw plain `FormatException`s
  with English messages. It now throws a `PdfSignatureIdentityException` (a
  `FormatException` subclass, so `on FormatException` handlers and the existing
  `.message` assertions keep working) carrying a `PdfSignatureIdentityError`
  `code` (+ 1-based `certificateIndex` for the invalid-certificate case). The
  app's key/cert loader maps the code to a localized message
  (`appSigError*`, six keys) at the display site; the pure model stays
  Flutter- and locale-free.

## Why labels-as-data, not context, for the pickers

Several pickers reach the file dialog as bare tearoffs handed to the package
viewer's callbacks (`onPickPdfToInsert`, `logoPicker`, `formImagePicker`,
`imagePicker`) — no `BuildContext` at the construction point, and the callback
signatures are fixed. Passing a resolved `String` label keeps `file_io` free of
context-lifetime concerns and lets each caller resolve the label from whatever
context it does have. The tearoffs became small closures that capture the
enclosing context and resolve the label synchronously before the first await.

## Gotcha — the Save-As test seam

`_EditorScreenState._save` picks `widget.saveDocumentAs ?? saveBytesAs`. Adding
the `required String pdfLabel` to `saveBytesAs` broke that fallback: the seam's
type is a three-positional-arg function, and the real function no longer matches
it (it failed at runtime as a `NoSuchMethodError`, not at analysis, because the
tearoff was coerced to the seam type). Fixed by binding the label in a
three-arg closure — `(ctx, bytes, name) => saveBytesAs(ctx, bytes, name,
pdfLabel: appL10n(ctx).fileTypePdf)` — which matches the seam and leaves the
test double untouched. The lesson: when a converted function is also reachable
through an injected function-typed seam, adapt at the seam, not just the direct
call sites.

## Verification

- `dart analyze --fatal-infos` clean across app + `dart_pdf_editor` (incl. the
  package model change).
- App suite green (254 tests), `dart_pdf_editor` + example suites green.
- New keys carry `@key` descriptions and typed placeholders; English values are
  byte-identical to the previous literals (the platform help strings were pulled
  from git to guarantee it), so the English-fallback path and text-finding
  widget tests are unaffected.

## Still deferred (unchanged)

`DateFormat`/`NumberFormat` for the stamp month abbreviations and user-visible
`toStringAsFixed` readouts, the RTL sweep, the Settings language picker, the
machine-translated seed ARBs + tier-1/2 locales, and the per-locale CI coverage
gate. `progressive_source.dart`'s engine-error interpolation is still kept as-is.
