# Migrating to 16.0.0

Update the eight established packages together to 16.0.0. The CLI uses 0.12.0, the printing companion 0.13.0 and the GPU companion 0.14.0. The GPU companion requires Flutter 3.50.0; the other Flutter packages retain their declared minimum versions.

## Custom localizations

Custom `DartPdfEditorLocalizations` subclasses must implement `tbRedactAsImages`, `tbRedactAsImagesDetail` and `tbConvertToFreeText`. The supplied localizations already implement them.

## Redaction

Whole-word removal is now enabled by default. Review the output because it can remove text beyond the marked area. The optional image-replacement mode replaces affected pages with raster images: text on those pages is no longer selectable or searchable and files can grow. Review all redacted output before sharing; this is not a guarantee against every crafted PDF.

## Host integrations

Hosts can add thumbnail context-menu entries with `pageMenuActionsBuilder`. Snapshot copies now retain links. Layout zoom is part of `PdfViewportFrame`; hosts constructing frames should include their layout zoom when below fit.

## Printing localizations

Custom `DartPdfPrintingLocalizations` implementations must add the preset members `printPresets`, `printPresetLabel`, `printPresetNone`, `printPresetNoneSaved`, `printPresetSave`, `printPresetDelete`, `printPresetModified`, `printPresetSaveTitle`, `printPresetName`, `printPresetReplaces`, `printPresetIncludePrinter`, `printPresetSaveAction`, plus `printOptionsPrinterMargins` and `printOptionsPaperUnsupported`. The supplied implementations already include them.

## Print-dialog widget tests

Hosts whose widget tests open `PrintPreviewDialog` should set `PrintPreviewDialog.debugRenderWorkerEnabled = false` in their test configuration. Production uses off-thread rendering; a real render isolate does not complete under the widget-test clock.
