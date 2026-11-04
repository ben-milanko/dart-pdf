# Print follows the thumbnail strip's selection

The print preview already offered a **Selected** range (fed by
`PdfEditingController.selectedPages` from `editor_screen.dart`'s `_print`),
but it always opened on the range the previous job used, so a multi-page
selection in the strip was ignored unless the user picked the chip again.

`PrintPreviewDialog` (`dart_pdf_printing/lib/src/print_preview_dialog.dart`)
now opens on Selected when **two or more** pages are selected
(`_followsSelection`). One selected page does not count: a plain thumbnail
click selects the page it navigates to, so that would silently turn every
"print" after a click into a one-page job. The override is not written back
to `PrintPreferences`; the remembered range only changes when the user picks
one. A remembered Selected with nothing selected now falls back to All
instead of opening on an empty job.

Tests: `print_preferences_ui_test.dart` ("a multi-page strip selection
overrides the saved range").
