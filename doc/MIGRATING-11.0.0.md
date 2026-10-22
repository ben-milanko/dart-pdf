# Migrating to 11.0.0

## Custom localizations

Implementations of `DartPdfEditorLocalizations` must supply these 22 new getters:

- `textVerticalAlign`
- `textAlignTop`
- `textAlignMiddle`
- `textAlignBottom`
- `table`
- `tableEdit`
- `tableRows`
- `tableColumns`
- `tableStyle`
- `tableStyleHint`
- `tableBackgroundColor`
- `tableHeaderColor`
- `tableTextColor`
- `tableGridLines`
- `tableGridColor`
- `tableGridWidth`
- `tableHeaderRow`
- `tableColumnWidth`
- `tableRowHeight`
- `tableSelectionHint`
- `tableClipboardError`
- `duplicate`

The generated built-in localizations already supply them. This source-breaking change requires a major release even though the editor features are additive.

## Annotation resize switches

The public enum `PdfAnnotationResizeBehavior` adds `reflowTable`. Add a case to exhaustive switches. It rebuilds editable table cells at the new widths while preserving font size. Persist enum names rather than indices because the inserted value shifts later indices.

## Versions

Use the eight established packages at 11.0.0. Companion versions are dart_pdf_cli 0.8.0, dart_pdf_printing 0.8.0 and dart_pdf_editor_flutter_gpu 0.10.0. Their dependency bounds now require this major suite; they have no additional public API changes.

## Editing behaviour

Pasting tab-separated text creates an editable table. Embedded annotation font defaults now persist between sessions. Selecting a standard font clears the embedded default.
