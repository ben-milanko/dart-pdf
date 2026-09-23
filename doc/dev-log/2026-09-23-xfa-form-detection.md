# XFA forms: detect, warn, and drop stale XFA on fill (#929)

Items 1 and 2 of #929. Rendering or filling dynamic XFA (item 3) is out of
scope; ISO 32000-2 deprecates XFA.

## Detection (pdf_document `form.dart`)

- `PdfAcroForm.hasXfa`: `/AcroForm /XFA` resolves to a stream (a single XDP
  document) or a non-empty array of named packet streams.
- `PdfAcroForm.xfaNeedsRendering`: the catalog's `/NeedsRendering true`.
  The flag lives on the catalog, not the AcroForm dictionary.
- `PdfAcroForm.isDynamicXfa` = `hasXfa && (xfaNeedsRendering ||
  fields.isEmpty)`. A hybrid form (XFA plus a matching AcroForm field tree,
  no `/NeedsRendering`) is not dynamic, and it fills normally.
  `fields` is only walked when XFA is present, so plain forms pay a single
  dictionary lookup.

## Hybrid forms (pdf_document `form_editor.dart`, `form_admin.dart`)

- `PdfEditor.removeXfa()` (on the `PdfFormFilling` extension) deletes
  `/XFA` from the AcroForm dictionary and `/NeedsRendering` from the
  catalog. It restages the indirect AcroForm object (or the catalog when
  the AcroForm is inline), then returns whether anything changed.
- `_finishFieldEdit` calls it, so every setter (text, check box, radio,
  choice, button image, and the `form_styling.dart` restyles that share
  `_finishFieldEdit`) drops XFA on the first fill of an edit. Later fills
  find nothing to remove. In the editing controller each edit is its own
  incremental save, so the first fill's revision carries the removal and
  undo brings the XFA back along with the old value.
- `flattenForm` calls it too: with the fields removed, an XFA-aware viewer
  would otherwise rebuild them from the XFA packet over the flattened
  content.
- We don't update `<xfa:datasets>` to match. Removing `/XFA` is what most
  non-XFA tools do, and it avoids an XML round-trip.
- The packet streams become unreferenced but stay in the file. The save is
  incremental, so the earlier revision still refers to them anyway.

## Editor notice (dart_pdf_editor `editing/xfa_notice.dart`)

- `showPdfXfaNoticeIfNeeded(context, controller)` shows a floating,
  closable snack bar (`pdf-xfa-form-notice`, l10n key
  `formXfaUnsupportedNotice`, 10 s) when `controller.acroForm.isDynamicXfa`.
  It shows once per `PdfEditingController`, tracked in an `Expando`, so
  remounts, tab switches and later revisions don't repeat it.
- `PdfViewer._scheduleXfaNotice` runs it from a post-frame callback at the
  end of `initState` and `didUpdateWidget`. It only runs when there is a
  revision controller (editing, or `formController` with
  `interactiveForms`) and the viewer is `active`. It checks
  `pdfXfaNoticePending` synchronously first, so ordinary rebuilds schedule
  nothing.
- Hybrid forms get no notice, because they are fillable.

## Tests

- `packages/pdf_document/test/form_xfa_test.dart`: detection variants,
  fill/flatten removal, the incremental tail rewriting object 4 without
  `/XFA`, and the no-op cases.
- `packages/dart_pdf_editor/test/editing_form_xfa_test.dart`: the notice
  shows once in reader and editor modes, never for hybrid/plain forms or
  with interactive forms off; a controller fill drops `/XFA` and undo
  restores it.
- Fixture: `buildXfaFormPdf({withFields, needsRendering, xfaAsArray})` in
  `pdf_test_fixtures/lib/src/xfa_forms.dart`.

## Docs

The forms guide's "What isn't supported (yet)" bullet and FAQ JSON-LD
(`site/guides/pdf-forms-and-signatures.html`) plus the pdf_document README
forms line now describe the behaviour above.
