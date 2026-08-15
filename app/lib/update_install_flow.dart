import 'package:dart_pdf_editor/dart_pdf_editor.dart' show showPdfDialog;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'l10n/app_l10n.dart';
import 'l10n/app_localizations.dart';
import 'update.dart';
import 'update_installer.dart';
import 'update_platform.dart';

/// Runs the interactive "update now" flow for the update [updates] found: on
/// desktop, downloads the artifact in a progress dialog and applies it in place
/// (AppImage self-replace + relaunch) or hands it to the OS installer
/// (macOS/Windows). Where no in-app apply path exists, or on failure, it falls
/// back to opening the browser download.
///
/// Reused by both the Settings "Update now" button and the startup banner.
Future<void> startUpdateInstall(
  BuildContext context, {
  required UpdateService updates,
  required UpdateInstaller installer,
}) async {
  final url = updates.downloadUrl;
  if (url == null) return;
  final assetName = updates.downloadAssetName;

  // Capture the messenger and localizations before any await, so a snackbar
  // still resolves after the async download even if the context is unmounted.
  final messenger = ScaffoldMessenger.of(context);
  final l10n = appL10n(context);

  // No in-app apply path (mobile, a release page only, a Linux tarball): keep
  // the old behaviour and open the download in the browser.
  final mode = installer.modeFor(assetName);
  if (mode == UpdateApplyMode.unsupported) {
    await _openInBrowser(messenger, l10n, url);
    return;
  }

  final progress =
      ValueNotifier<_UpdateProgress>(const _UpdateProgress(fraction: null));
  var cancelled = false;

  final dialogFuture = showPdfDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _UpdateProgressDialog(
      progress: progress,
      onCancel: () => cancelled = true,
    ),
  );

  UpdateInstallOutcome? outcome;
  Object? failure;
  try {
    outcome = await installer.downloadAndApply(
      url: url,
      assetName: assetName!,
      expectedSize: updates.downloadAssetSize,
      isCancelled: () => cancelled,
      onProgress: (received, total) {
        progress.value = _UpdateProgress(
            fraction: (total != null && total > 0) ? received / total : null);
      },
      // The AppImage path relaunches immediately after applying; show a
      // "restarting" state so the dialog isn't frozen at 100% before exit.
      onApplying: mode == UpdateApplyMode.inPlaceRelaunch
          ? () => progress.value = const _UpdateProgress(applying: true)
          : null,
    );
  } on UpdateCancelledException {
    // User cancelled - close the dialog quietly, no toast.
  } catch (e) {
    failure = e;
  }

  // Dismiss the progress dialog. (An AppImage relaunch already exited the
  // process, so this only runs on hand-off, cancel, or failure.)
  if (context.mounted) {
    Navigator.of(context, rootNavigator: true).pop();
  }
  await dialogFuture;
  progress.dispose();

  if (failure != null) {
    final message =
        failure is UpdateInstallException ? failure.message : '$failure';
    messenger.showSnackBar(SnackBar(
      key: const ValueKey('update-install-failed'),
      content: Text(l10n.updateFailed(message)),
      action: SnackBarAction(
        label: l10n.editorDownload,
        onPressed: () =>
            launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      ),
    ));
    return;
  }

  if (outcome == UpdateInstallOutcome.handedOff) {
    messenger.showSnackBar(SnackBar(
      key: const ValueKey('update-handed-off'),
      content: Text(l10n.updateHandedOff),
    ));
  }
}

Future<void> _openInBrowser(
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  String url,
) async {
  final opened =
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  if (!opened) {
    messenger.showSnackBar(SnackBar(
      content: Text(l10n.settingsCouldNotOpenDownload),
    ));
  }
}

/// The progress dialog's state: download [fraction] (null before it's known),
/// or [applying] once the download is done and the update is being applied
/// (the AppImage restart).
class _UpdateProgress {
  const _UpdateProgress({this.fraction, this.applying = false});
  final double? fraction;
  final bool applying;
}

/// Modal progress dialog for an in-app update download, with a cancel button.
class _UpdateProgressDialog extends StatelessWidget {
  const _UpdateProgressDialog({required this.progress, required this.onCancel});

  final ValueListenable<_UpdateProgress> progress;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey('update-progress-dialog'),
      title: Text(appL10n(context).updateDownloadingTitle),
      content: ValueListenableBuilder<_UpdateProgress>(
        valueListenable: progress,
        builder: (context, value, _) {
          final l10n = appL10n(context);
          final label = value.applying
              ? l10n.updateRestarting
              : value.fraction == null
                  ? l10n.updatePreparing
                  : l10n.updateDownloadingPercent((value.fraction! * 100)
                      .round());
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(label),
              const SizedBox(height: 16),
              // Indeterminate bar (null value) while applying/restarting.
              LinearProgressIndicator(
                  value: value.applying ? null : value.fraction),
            ],
          );
        },
      ),
      actions: [
        TextButton(
          key: const ValueKey('update-progress-cancel'),
          onPressed: onCancel,
          child: Text(appL10n(context).cancel),
        ),
      ],
    );
  }
}
