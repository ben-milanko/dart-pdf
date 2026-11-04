# printPdfBytes reports a cancelled print dialog (#1221)

`printPdfBytes`, `printPdfWithProgress` and `printPdfWithPreview` now return
`PrintDialogResult` (`lib/src/print_result.dart`) instead of `void`:
`cancelled` when the dialog was dismissed, `handedToSystem` once the job left
the app. It says nothing about the physical printer. Asked for by a manual
duplex host that needs to know whether pass 1 went out before offering pass 2.

The return type is a widening (`Future<PrintDialogResult>` is a
`Future<void>`), so `await printPdfBytes(...)` and `PdfPrinter`-typed
injection keep working. A `.catchError` with a void handler on the returned
future now trips `body_might_complete_normally_catch_error` (the one test that
did so uses `then(onError:)`).

Per platform (the Dart side reads `false` from `printPdf` / `endJob` as a
cancel; `null` from an older runner counts as handed over):

- **macOS**: `NSPrintOperation.run()` already answered the cancel. An
  unreadable PDF or a missing print operation used to answer `false` too, so
  it would have read as a cancel - both are now `native_print_failed` errors.
- **iOS**: the `UIPrintInteractionController` completion's `completed` was
  already sent. Printing unavailable is now `printing_unavailable` (it was
  `false`), and the completion's `error` is surfaced.
- **Android**: used to answer `true` the moment `PrintManager.print` returned.
  It now answers from `PrintDocumentAdapter.onFinish`, reading the `PrintJob`
  state: the spooler sets QUEUED (confirmed) or CANCELED (backed out) before
  it finishes the adapter, so CANCELED/CREATED read as a cancel. `OnceResult`
  guards the reply; activity detach settles a pending reply early so the
  Dart future and the channel's `print_in_progress` lock cannot hang.
- **Windows**: `endJob` already separated cancel (`false`) from failure
  (`print_failed`). A `destination` job has no dialog and reports
  `handedToSystem`.
- **Linux**: GTK's ERROR and CANCEL both answered `false`; ERROR is now a
  `print_failed` error.
- **Web**: browsers don't expose the print dialog's outcome; always
  `handedToSystem` (documented).

The native code was not built in this session (no Swift/Kotlin/GTK toolchain
in the container); the Dart contract is covered in `native_print_io_test`,
`printing_test` and `print_flow_test`.
