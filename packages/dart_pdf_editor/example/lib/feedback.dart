import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'error_log.dart';
import 'l10n/app_l10n.dart';

/// The plain-language GitHub issue form for app feedback. The diagnostics
/// report is prefilled into the form's `diagnostics` field.
final Uri kFeedbackFormUrl = Uri.parse(
    'https://github.com/ben-milanko/dart-pdf/issues/new?template=app_feedback.yml');

/// Browsers and GitHub both cap issue-prefill URLs. Stay comfortably under
/// the ~8k practical ceiling; the untruncated report is still copied to the
/// clipboard so nothing is lost.
const int _maxFeedbackUrlLength = 6000;

/// Builds the GitHub issue URL with the app version and, when [report] is
/// given, the diagnostics prefilled into the form's `diagnostics` field.
///
/// The report is attached tail-first (most recent events are the most useful)
/// and truncated so the whole URL stays under [maxUrlLength]; a truncation
/// marker is prepended when that happens.
Uri buildFeedbackUri(
  Uri base, {
  String? report,
  String version = kAppVersion,
  int maxUrlLength = _maxFeedbackUrlLength,
}) {
  final params = Map<String, String>.from(base.queryParameters)
    ..['version'] = version;
  if (report == null || report.isEmpty) {
    return base.replace(queryParameters: params);
  }

  // Grow the attached report from the tail until the encoded URL would exceed
  // the budget, then keep the largest prefix that fits.
  String withReport(String value) => base
      .replace(queryParameters: {...params, 'diagnostics': value})
      .toString();

  var attached = report;
  if (withReport(attached).length > maxUrlLength) {
    const marker = '[older entries truncated - full log copied to clipboard]\n';
    // Binary-search the longest tail that fits under the budget.
    var lo = 0;
    var hi = report.length;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      final tail = marker + report.substring(report.length - mid);
      if (withReport(tail).length <= maxUrlLength) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    attached = marker + report.substring(report.length - lo);
  }
  return base.replace(queryParameters: {...params, 'diagnostics': attached});
}

/// Shows the feedback dialog: the user reviews the captured diagnostics,
/// optionally copies them, and opens the GitHub feedback form with the report
/// (and app version) prefilled.
///
/// [onOpen] launches the built URL (injected so the caller owns url_launcher
/// and error toasts); [onCopied] fires after the report is copied so the host
/// can toast. [log] defaults to the shared [AppLog].
Future<void> showFeedbackDialog(
  BuildContext context, {
  required Future<void> Function(Uri url) onOpen,
  VoidCallback? onCopied,
  AppLog? log,
}) {
  final appLog = log ?? AppLog.instance;
  return showDialog<void>(
    context: context,
    builder: (context) => _FeedbackDialog(
      log: appLog,
      onOpen: onOpen,
      onCopied: onCopied,
    ),
  );
}

class _FeedbackDialog extends StatefulWidget {
  const _FeedbackDialog({
    required this.log,
    required this.onOpen,
    this.onCopied,
  });

  final AppLog log;
  final Future<void> Function(Uri url) onOpen;
  final VoidCallback? onCopied;

  @override
  State<_FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<_FeedbackDialog> {
  bool _includeDiagnostics = true;

  String get _report => widget.log.buildReport(
        environment: DiagnosticsEnvironment.current(),
        now: DateTime.now(),
      );

  Future<void> _copy({bool notify = true}) async {
    try {
      await Clipboard.setData(ClipboardData(text: _report));
      if (notify) widget.onCopied?.call();
    } catch (_) {
      // Clipboard access can be denied (locked-down web, headless tests);
      // it's a convenience, so a failure must not block the feedback flow.
    }
  }

  Future<void> _open() async {
    final url = buildFeedbackUri(
      kFeedbackFormUrl,
      report: _includeDiagnostics ? _report : null,
    );
    if (_includeDiagnostics) {
      // Copy too, so the full log is available to paste even when the URL had
      // to truncate it - best-effort and fire-and-forget (opening is the
      // action; a slow or denied clipboard must not delay it), no toast.
      unawaited(_copy(notify: false));
    }
    if (mounted) Navigator.of(context).pop();
    await widget.onOpen(url);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(appL10n(context).feedbackTitle),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              appL10n(context).feedbackDiagnosticsNotice,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListenableBuilder(
                listenable: widget.log,
                builder: (context, _) => Container(
                  constraints: const BoxConstraints(maxHeight: 220),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: Scrollbar(
                    child: SingleChildScrollView(
                      child: SelectableText(
                        _report,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          height: 1.35,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            CheckboxListTile(
              value: _includeDiagnostics,
              onChanged: (value) =>
                  setState(() => _includeDiagnostics = value ?? true),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              title: Text(appL10n(context).feedbackAttachDiagnostics),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: widget.log.isEmpty
              ? null
              : () {
                  widget.log.clear();
                  setState(() {});
                },
          icon: const Icon(Icons.delete_outline),
          label: Text(appL10n(context).feedbackClearLog),
        ),
        TextButton.icon(
          onPressed: _copy,
          icon: const Icon(Icons.copy_outlined),
          label: Text(appL10n(context).feedbackCopyDiagnostics),
        ),
        FilledButton.icon(
          onPressed: _open,
          icon: const Icon(Icons.open_in_new),
          label: Text(appL10n(context).feedbackOpenForm),
        ),
      ],
    );
  }
}
