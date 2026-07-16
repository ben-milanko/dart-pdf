# 2026-07-10 - Local error logging attached to feedback

Added an in-app diagnostics log to the example app (`pdf_viewer_example`) and
wired it into the "Supply feedback…" flow so a bug report carries the
session's errors.

## Pieces

- `example/lib/error_log.dart`
  - `AppLog` (a `ChangeNotifier`) is a capped ring buffer (default 300) of
    `AppLogEntry(time, level, message, error?, stackTrace?)`. Nothing is
    written to disk or sent anywhere on its own - it lives for the session and
    is surfaced only when the user opens feedback.
  - `install()` chains `FlutterError.onError` and
    `PlatformDispatcher.instance.onError` (preserving the previous handlers so
    console reporting still runs) and returns a `runZonedGuarded` handler for
    async errors. Idempotent.
  - `buildDiagnosticsReport(...)` / `AppLog.buildReport(...)` render the plain
    text report (header: app version, platform, capture time, count; then each
    entry with a whitespace-collapsed error line and a stack trimmed to 12
    frames). Kept as a free function taking injected `entries`/`environment`/
    `now` so it's deterministic in tests.
  - `kAppVersion` mirrors the example `pubspec.yaml` version - update both
    together.
- `example/lib/feedback.dart`
  - `buildFeedbackUri(base, report, version, maxUrlLength)` prefills the GitHub
    issue form's `version` and `diagnostics` fields. The report is attached
    tail-first (recent events matter most) and binary-searched down to fit
    under a 6000-char URL budget, with a truncation marker prepended; the full
    report is still copied to the clipboard so nothing is lost.
  - `showFeedbackDialog(...)` shows the report for review (selectable
    monospace, live via `ListenableBuilder`), with Clear log / Copy
    diagnostics / Open feedback form actions and an "Attach these diagnostics"
    checkbox (default on). `onOpen` is injected so the host owns
    url_launcher + toasts.
- `main.dart`: `main()` installs the log and wraps `runApp` in
  `runZonedGuarded`; the feedback menu item now calls `_openFeedback` (dialog)
  instead of launching the raw URL; the previously silent font-load catch and
  the document-open / save / export / OCR failure catches now record to
  `AppLog`.
- `.github/ISSUE_TEMPLATE/app_feedback.yml`: added a `diagnostics` textarea
  (`render: text`) as the prefill target, described as auto-filled and
  containing no document contents.

## Gotchas

- The clipboard copy inside "Open feedback form" is fire-and-forget
  (`unawaited`, try/caught). Awaiting it gated the open when the clipboard
  channel is absent/denied (headless tests, locked-down web) - opening is the
  action and must not depend on the clipboard.
- The diagnostics box is wrapped in `Flexible` with a `maxHeight` constraint
  so the dialog doesn't overflow on short/mobile viewports (the default
  800x600 test surface tripped this).

## Tests

- `example/test/error_log_test.dart` - ring buffer capacity/ordering/notify,
  report contents + stack trimming, URL prefill + tail truncation.
- `example/test/feedback_dialog_test.dart` - dialog opens the form with
  version + diagnostics prefilled, the Attach toggle omits diagnostics, Copy
  writes the report to the clipboard.

(Pre-existing, unrelated: 8 example tests in demo_test/demo_document_test/
editing_test fail on the branch base too.)
