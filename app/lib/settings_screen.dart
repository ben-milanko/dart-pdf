import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_info.dart';
import 'l10n/app_l10n.dart';
import 'l10n/app_localizations.dart';
import 'language_names.dart';
import 'recents.dart';
import 'update.dart';
import 'update_install_flow.dart';
import 'update_installer.dart';

// The platform-specific default-app help lives in the ARB as one ICU `select`
// key each (branches: web/windows/macos/linux/android/ios/other), resolved from
// this selector. Both consumers below have a BuildContext, so no literal needs
// to live at the no-context data site any more.
String get _defaultAppPlatform {
  if (kIsWeb) return 'web';
  return switch (defaultTargetPlatform) {
    TargetPlatform.windows => 'windows',
    TargetPlatform.macOS => 'macos',
    TargetPlatform.linux => 'linux',
    TargetPlatform.android => 'android',
    TargetPlatform.iOS => 'ios',
    TargetPlatform.fuchsia => 'fuchsia',
  };
}

String _defaultAppSubtitle(BuildContext context) =>
    appL10n(context).settingsDefaultAppSubtitle(_defaultAppPlatform);

String _defaultAppInstructions(BuildContext context) =>
    appL10n(context).settingsDefaultAppInstructions(_defaultAppPlatform);

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
      content: Text(_defaultAppInstructions(context)),
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
  UpdateInstaller? updateInstaller,
  VoidCallback? onOpenDevTools,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _SettingsDialog(
      prefs: prefs,
      recents: recents,
      updates: updates,
      updateInstaller: updateInstaller,
      onOpenDevTools: onOpenDevTools,
    ),
  );
}

/// The Settings UI-language dropdown: "System default" plus every locale the
/// app ships translations for, each shown by its native name. Writes the
/// choice to [PdfEditingPreferences.locale] (null = follow the platform),
/// which `app.dart` feeds to `MaterialApp.locale`.
class _LanguagePicker extends StatelessWidget {
  const _LanguagePicker({required this.prefs});

  final PdfEditingPreferences prefs;

  @override
  Widget build(BuildContext context) {
    // Sort supported locales by native name so the list reads naturally; the
    // "System default" entry (value null) always leads.
    final locales = AppLocalizations.supportedLocales.toList()
      ..sort((a, b) => languageDisplayName(a)
          .toLowerCase()
          .compareTo(languageDisplayName(b).toLowerCase()));
    // Match the stored preference to a supported locale by value; an
    // unsupported stored tag falls back to showing "System default" without
    // discarding the preference.
    Locale? selected;
    for (final locale in locales) {
      if (locale == prefs.locale) {
        selected = locale;
        break;
      }
    }
    return DropdownButtonFormField<Locale?>(
      key: const ValueKey('settings-language'),
      initialValue: selected,
      isExpanded: true,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        isDense: true,
        prefixIcon: Icon(Icons.language),
      ),
      items: [
        DropdownMenuItem<Locale?>(
          value: null,
          child: Text(appL10n(context).settingsLanguageSystem),
        ),
        for (final locale in locales)
          DropdownMenuItem<Locale?>(
            value: locale,
            child: Text(languageDisplayName(locale)),
          ),
      ],
      onChanged: (value) => prefs.locale = value,
    );
  }
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({
    required this.prefs,
    required this.recents,
    this.updates,
    this.updateInstaller,
    this.onOpenDevTools,
  });

  final PdfEditingPreferences prefs;
  final RecentsStore recents;
  final UpdateService? updates;
  final UpdateInstaller? updateInstaller;

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
                const SizedBox(height: 16),
                Text(appL10n(context).settingsLanguage,
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                _LanguagePicker(prefs: widget.prefs),
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
                  subtitle: Text(_defaultAppSubtitle(context)),
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
                if (widget.updates != null && widget.updates!.supported) ...[
                  const Divider(height: 32),
                  _UpdateSection(
                    updates: widget.updates!,
                    installer: widget.updateInstaller,
                  ),
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
  const _UpdateSection({required this.updates, this.installer});

  final UpdateService updates;

  /// The in-app updater; null defaults to a real one (tests inject a fake).
  final UpdateInstaller? installer;

  Future<void> _install(BuildContext context) => startUpdateInstall(
        context,
        updates: updates,
        installer: installer ?? UpdateInstaller(),
      );

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
                alignment: AlignmentDirectional.centerStart,
                child: FilledButton.icon(
                  key: const ValueKey('settings-download-update'),
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: Text(appL10n(context).settingsDownloadVersion(
                      updates.latest!.version.toString())),
                  onPressed: () => _install(context),
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
