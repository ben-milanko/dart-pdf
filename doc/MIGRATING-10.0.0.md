# Migrating to 10.0.0

## Tool switches

`PdfEditTool` adds `measureCustom`, a dimension line with a user-written value.
Add a case to exhaustive switches over the enum. The stock tool catalogue and
behaviour registry already handle it. Code that persists enum indices should
migrate to enum names: inserting the value changes later indices.

## Custom localizations

Implementations of `DartPdfEditorLocalizations` must supply four new getters:

- `measCustomValueTitle`
- `menuEditMeasurementValue`
- `menuAddNoteHere`
- `tbNameMeasureCustom`

The generated built-in localizations already supply them.

## Shell and link defaults

Compact `PdfReader` and `PdfEditorView` shells hide their reading chrome while
scrolling. Set the corresponding features object's `autoHideChrome: false`
to keep it visible. Wide layouts keep their chrome visible.

`PdfEditingController.addLink` now draws a border and chain-link badge when
no decoration is specified. Set decoration arguments explicitly to control
the appearance; a negative colour suppresses that decoration.

The standalone mobile app opens documents in Hand mode. This does not change
the package controller's default tool.

## Versions

Use the eight established packages at 10.0.0. Companion versions are
`dart_pdf_cli` 0.7.0, `dart_pdf_printing` 0.7.0 and
`dart_pdf_editor_flutter_gpu` 0.9.0. Their dependency bounds now require
this major suite; they have no additional public API changes.
