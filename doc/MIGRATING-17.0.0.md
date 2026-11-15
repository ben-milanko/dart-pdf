# Migrating to 17.0.0

Update the eight established packages together to 17.0.0. The CLI remains 0.12.0, printing 0.13.0 and the GPU companion 0.14.0. Flutter packages require Flutter 3.50.0.

## Custom localizations

Custom `DartPdfEditorLocalizations` subclasses must implement `sidebarFilter`, `sidebarFilterType`, `sidebarFilterAuthor` and `sidebarFilterClear`. The supplied localizations already implement them.

## Mobile file saving

Android and iOS can save edits to the picked file when its provider supports writing. Read-only providers still require saving a copy.

## Reader integrations

`PdfReader.pageMenuActionsBuilder` lets hosts add thumbnail context-menu actions. The reader does not allow page editing.
