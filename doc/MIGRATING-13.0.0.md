# Migrating to 13.0.0

The eight established packages now use 13.0.0. Update their constraints together. The CLI and printing companions use 0.10.0; the GPU companion uses 0.12.0.

Custom subclasses of `DartPdfEditorLocalizations` must implement five new getters:

- `notePopupKeepOpen`
- `menuEditLink`
- `menuRemoveLink`
- `linkEditDialogTitle`
- `propSectionComments`

Applications using the supplied generated localizations need no implementation changes. New form-data exchange, remote-signing and experimental shared-folder transport APIs are opt-in. The shared-folder transport is not enabled in the standalone app.
