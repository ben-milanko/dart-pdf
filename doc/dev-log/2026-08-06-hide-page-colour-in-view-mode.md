# Hide the page colour tool in view mode

The app's read-only ("view") mode swaps `PdfEditorView` for `PdfReader`
(`EditorScreen._readOnly`, toggled from the DartPDF menu's "Switch to
read-only"). Until now that reader used the stock `PdfReaderFeatures`, so the
View options menu still offered "Page color…" — paper colour is an authoring
choice, not something a reader should be changing.

The plumbing already existed: `PdfReaderFeatures.pageColorEditable` gates the
item in both the desktop popup and the mobile sheet (`shell_chrome.dart`, key
`pdf-shell-page-color`). The fix is just to pass
`features: const PdfReaderFeatures(pageColorEditable: false)` when
`EditorScreen` builds the reader. Edit mode is untouched — `PdfEditorView`
keeps its own `pageColorEditable`, still defaulting to true.

Covered by `app/test/read_only_view_options_test.dart`: the item is gone after
switching to read-only and present in edit mode. Note the read-only menu entry
carries no `ValueKey`, so the test drives it by its label and calls
`ensureVisible` first — with a document open the menu runs past the fold of the
default 600px-high test window and a plain tap hits the scrim.
