# Migrating to DartPDF 16.3

Update the eight lockstep packages together to 16.3.0. The CLI (0.12.0),
printing plugin (0.13.0) and GPU companion (0.14.0) remain compatible. Flutter
packages still require Flutter 3.50.0.

Custom `DartPdfEditorLocalizations` subclasses must implement the page-resize
strings behind the thumbnail menu's new **Resize page…** entry and its dialog:
`thumbResizePages(int count)`, `pageResizeTitle(int count)`,
`pageResizeSize`, `pageResizeCustom`, `pageResizePortrait`,
`pageResizeLandscape`, `pageResizeWidth`, `pageResizeHeight`,
`pageResizeScaleToFit`, `pageResizeKeepSize`, `pageResizeConfirm` and
`pageResizeInvalid`. Apps that use the shipped localizations need no changes.

New, opt-in APIs:

- `PdfEditorView.pageThumbnailOverlayBuilder` (also on `PdfReader`,
  `PdfThumbnailSidebar` and `PdfThumbnailView`) stacks host widgets over each
  page thumbnail in the strip and the grid. Return `Positioned` widgets.
- `PdfEditor.resizePages` (pdf_document) and `showPdfPageResizeDialog`
  (dart_pdf_editor) resize pages to a new paper size.
