# Migrating to 12.0.0

## Custom localizations

Implementations of `DartPdfEditorLocalizations` must supply 12 new members:

- `menuSaveAsImage`
- `propRegion`
- `propRegionPolygon`
- `propRegionCloud`
- `searchRedact`
- `searchRedactMark`
- `searchRedactMarkAll`
- `searchRedactHint`
- `searchRedactMarked(int count)`
- `tbFindToRedact`
- `tbNameCloudCallout`
- `tbTipCloudCallout`

The built-in localizations already implement them. Custom implementations need updating before they compile against 12.0.0.

## Editing tool switches

`PdfEditTool` adds `cloudCallout`. Add a case to exhaustive switches. Persist enum names instead of indices because the inserted value shifts later indices.

## Versions

Use the eight established packages at 12.0.0. Companion versions are `dart_pdf_cli` 0.9.0, `dart_pdf_printing` 0.9.0 and `dart_pdf_editor_flutter_gpu` 0.11.0. Their dependency floors require the new major suite. The CLI reports 0.9.0 from `dartpdf --version`.

## Redaction

Search matches and selected text can be marked for redaction. Marking leaves reviewable annotations; applying redactions removes the covered content. The text-removal fix preserves text outside the marked area in the same run.

If upgrading from 10.x, also apply the changes in [Migrating to 11.0.0](MIGRATING-11.0.0.md).
