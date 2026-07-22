import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_info.dart';
import 'l10n/app_l10n.dart';
import 'recents.dart';
import 'update.dart';

String get _defaultAppSubtitle {
  if (kIsWeb) return 'Install the web app, then choose it for PDF files.';
  return switch (defaultTargetPlatform) {
    TargetPlatform.windows => 'Open Windows default apps settings for PDFs.',
    TargetPlatform.macOS => 'Follow Finder’s “Always Open With” steps.',
    TargetPlatform.linux => 'Use your desktop’s default applications settings.',
    TargetPlatform.android =>
      'Choose DartPDF when opening a PDF, then tap Always.',
    TargetPlatform.iOS => 'Use Share or Open In from Files to send PDFs here.',
    TargetPlatform.fuchsia => 'Configure your system’s PDF file handler.',
  };
}

String get _defaultAppInstructions {
  if (kIsWeb) {
    return 'Install DartPDF from your browser first. Then use the browser or operating system file-handler settings to associate PDF files with the installed app.';
  }
  return switch (defaultTargetPlatform) {
    TargetPlatform.windows =>
      'Windows Settings will open to Default apps. Search for “.pdf” or “PDF”, choose the current PDF app, then select DartPDF.',
    TargetPlatform.macOS =>
      'In Finder, select any PDF, choose File > Get Info, expand “Open with”, pick DartPDF, then click “Change All…”.',
    TargetPlatform.linux =>
      'Open your desktop settings for Default Applications, or right-click a PDF in Files, choose Properties, and set DartPDF as the default for PDF documents.',
    TargetPlatform.android =>
      'Open a PDF from Files or Downloads, choose DartPDF in the app picker, then select Always. If another app already opens PDFs, clear that app’s defaults in Android Settings first.',
    TargetPlatform.iOS =>
      'iOS does not provide a global default PDF editor. Use Files > Share, or long-press a PDF and choose Share/Open In, then pick DartPDF.',
    TargetPlatform.fuchsia =>
      'Use the system settings for file handlers to associate PDF documents with DartPDF.',
  };
}

bool get _canOpenDefaultAppsSettings =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

Future<void> _openDefaultAppsSettings(BuildContext context) async {
  final uri = Uri.parse('ms-settings:defaultapps');
  final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(appL10n(context).settingsCouldNotOpenSystemSettings),
    ));
  }
}

Future<void> _showDefaultAppSetup(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(appL10n(context).settingsSetUpAsDefault),
      content: Text(_defaultAppInstructions),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(appL10n(context).close),
        ),
        if (_canOpenDefaultAppsSettings)
          FilledButton.icon(
            key: const ValueKey('default-app-open-settings'),
            icon: const Icon(Icons.open_in_new),
            label: Text(appL10n(context).settingsOpenSettings),
            onPressed: () {
              Navigator.of(context).pop();
              _openDefaultAppsSettings(context);
            },
          ),
      ],
    ),
  );
}

/// Opens the app settings sheet: theme mode, recent-files management, the
/// update check, and the About section. Style defaults (tool colours, stroke,
/// font) are edited live from the editor toolbar and persist through
/// [PdfEditingPreferences], so they aren't duplicated here.
Future<void> showAppSettings(
  BuildContext context, {
  required PdfEditingPreferences prefs,
  required RecentsStore recents,
  UpdateService? updates,
  VoidCallback? onOpenDevTools,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _SettingsDialog(
      prefs: prefs,
      recents: recents,
      updates: updates,
      onOpenDevTools: onOpenDevTools,
    ),
  );
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({
    required this.prefs,
    required this.recents,
    this.updates,
    this.onOpenDevTools,
  });

  final PdfEditingPreferences prefs;
  final RecentsStore recents;
  final UpdateService? updates;

  /// Non-null in debug/profile builds: closes the dialog and opens the
  /// developer tools panel (same as F12).
  final VoidCallback? onOpenDevTools;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(appL10n(context).settingsTitle),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: ListenableBuilder(
            listenable: Listenable.merge([widget.prefs, widget.recents]),
            builder: (context, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(appL10n(context).settingsAppearance,
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<ThemeMode>(
                  segments: [
                    ButtonSegment(
                        value: ThemeMode.system,
                        icon: const Icon(Icons.brightness_auto),
                        label: Text(appL10n(context).settingsThemeSystem)),
                    ButtonSegment(
                        value: ThemeMode.light,
                        icon: const Icon(Icons.light_mode),
                        label: Text(appL10n(context).settingsThemeLight)),
                    ButtonSegment(
                        value: ThemeMode.dark,
                        icon: const Icon(Icons.dark_mode),
                        label: Text(appL10n(context).settingsThemeDark)),
                  ],
                  selected: {widget.prefs.themeMode},
                  onSelectionChanged: (s) => widget.prefs.themeMode = s.first,
                ),
                const Divider(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: Text(appL10n(context).settingsRecentFiles,
                          style: theme.textTheme.titleSmall),
                    ),
                    TextButton(
                      onPressed: widget.recents.isEmpty
                          ? null
                          : () => widget.recents.clear(),
                      child: Text(appL10n(context).clear),
                    ),
                  ],
                ),
                Text(
                  appL10n(context).settingsRecentCount(widget.recents.items.length),
                  style: theme.textTheme.bodySmall,
                ),
                const Divider(height: 32),
                Text(appL10n(context).settingsSystem,
                    style: theme.textTheme.titleSmall),
                ListTile(
                  key: const ValueKey('settings-default-app'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.assignment_turned_in_outlined),
                  title: Text(appL10n(context).settingsSetUpAsDefault),
                  subtitle: Text(_defaultAppSubtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showDefaultAppSetup(context),
                ),
                if (widget.onOpenDevTools != null)
                  ListTile(
                    key: const ValueKey('settings-devtools'),
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.build_outlined),
                    title: Text(appL10n(context).settingsDeveloperTools),
                    subtitle:
                        Text(appL10n(context).settingsDeveloperToolsSubtitle),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(context).pop();
                      widget.onOpenDevTools!();
                    },
                  ),
                if (widget.updates != null && UpdateService.supported) ...[
                  const Divider(height: 32),
                  _UpdateSection(updates: widget.updates!),
                ],
                const Divider(height: 32),
                Text(appL10n(context).settingsAbout,
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text('${AppInfo.name} ${AppInfo.version}',
                    style: theme.textTheme.bodyMedium),
                Text(AppInfo.tagline, style: theme.textTheme.bodySmall),
                const SizedBox(height: 4),
                TextButton.icon(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  icon: const Icon(Icons.code, size: 18),
                  label: Text(appL10n(context).settingsViewSource),
                  onPressed: () => launchUrl(Uri.parse(AppInfo.sourceUrl),
                      mode: LaunchMode.externalApplication),
                ),
                ListTile(
                  key: const ValueKey('settings-licenses'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.article_outlined),
                  title: const Text('Open source licenses'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: AppInfo.name,
                    applicationVersion: AppInfo.version,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(appL10n(context).close),
        ),
      ],
    );
  }
}

/// The Settings "Updates" block: a "Check for updates" button and a status
/// line that reflects the [UpdateService]'s latest result, with a Download
/// button (opening the platform artifact or release page) when a newer build
/// is available.
class _UpdateSection extends StatelessWidget {
  const _UpdateSection({required this.updates});

  final UpdateService updates;

  Future<void> _openDownload(BuildContext context) async {
    final url = updates.downloadUrl;
    if (url == null) return;
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(appL10n(context).settingsCouldNotOpenDownload),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: updates,
      builder: (context, _) {
        final checking = updates.status == UpdateStatus.checking;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(appL10n(context).settingsUpdates,
                      style: theme.textTheme.titleSmall),
                ),
                TextButton(
                  key: const ValueKey('settings-check-updates'),
                  onPressed: checking
                      ? null
                      : () => updates.checkForUpdates(force: true),
                  child: checking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(appL10n(context).settingsCheckNow),
                ),
              ],
            ),
            _statusLine(context, theme),
            if (updates.updateAvailable) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  key: const ValueKey('settings-download-update'),
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: Text(appL10n(context).settingsDownloadVersion(
                      updates.latest!.version.toString())),
                  onPressed: () => _openDownload(context),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _statusLine(BuildContext context, ThemeData theme) {
    final scheme = theme.colorScheme;
    final style = theme.textTheme.bodySmall;
    return switch (updates.status) {
      UpdateStatus.checking =>
        Text(appL10n(context).settingsCheckingForUpdates, style: style),
      UpdateStatus.updateAvailable => Text(
          appL10n(context).settingsUpdateAvailable(
              updates.latest!.version.toString(), AppInfo.version),
          key: const ValueKey('settings-update-available'),
          style: style?.copyWith(color: scheme.primary),
        ),
      UpdateStatus.upToDate => Text(
          appL10n(context).settingsUpToDate(AppInfo.version),
          key: const ValueKey('settings-up-to-date'),
          style: style,
        ),
      UpdateStatus.failed => Text(
          appL10n(context).settingsUpdateFailed,
          key: const ValueKey('settings-update-failed'),
          style: style?.copyWith(color: scheme.error),
        ),
      UpdateStatus.idle => Text(
          appL10n(context).settingsUpdateIdle(AppInfo.name, AppInfo.version),
          style: style,
        ),
    };
  }
}
