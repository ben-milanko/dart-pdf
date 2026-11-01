# Migrating to 14.0.0

Update the eight established packages together to 14.0.0. The CLI uses 0.10.1, the printing companion 0.11.0 and the GPU companion 0.12.1.

Custom subclasses of `DartPdfEditorLocalizations` must implement `shellTwoPageView` and `shellTwoPageCover`. Applications using the supplied generated localizations need no implementation changes.

The printing entrypoints now return `Future<PrintDialogResult>` instead of `Future<void>`. Awaiting and discarding the result still works. Use `PrintDialogResult.cancelled` to detect dismissal and `PrintDialogResult.handedToSystem` for hand-off to the operating system. Hand-off does not confirm physical printing. Browsers cannot report cancellation and return `handedToSystem`.

Two-page layout is opt-in. Existing single-page defaults remain unchanged.
