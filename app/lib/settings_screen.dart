import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_info.dart';
import 'recents.dart';

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
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Could not open system settings'),
    ));
  }
}

Future<void> _showDefaultAppSetup(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Set up as default application'),
      content: Text(_defaultAppInstructions),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        if (_canOpenDefaultAppsSettings)
          FilledButton.icon(
            key: const ValueKey('default-app-open-settings'),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open Settings'),
            onPressed: () {
              Navigator.of(context).pop();
              _openDefaultAppsSettings(context);
            },
          ),
      ],
    ),
  );
}

/// Opens the app settings sheet: theme mode, recent-files management, and the
/// About section. Style defaults (tool colours, stroke, font) are edited live
/// from the editor toolbar and persist through [PdfEditingPreferences], so they
/// aren't duplicated here.
Future<void> showAppSettings(
  BuildContext context, {
  required PdfEditingPreferences prefs,
  required RecentsStore recents,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _SettingsDialog(prefs: prefs, recents: recents),
  );
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({required this.prefs, required this.recents});

  final PdfEditingPreferences prefs;
  final RecentsStore recents;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Settings'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: ListenableBuilder(
            listenable: Listenable.merge([widget.prefs, widget.recents]),
            builder: (context, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Appearance', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                        value: ThemeMode.system,
                        icon: Icon(Icons.brightness_auto),
                        label: Text('System')),
                    ButtonSegment(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode),
                        label: Text('Light')),
                    ButtonSegment(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode),
                        label: Text('Dark')),
                  ],
                  selected: {widget.prefs.themeMode},
                  onSelectionChanged: (s) => widget.prefs.themeMode = s.first,
                ),
                const Divider(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: Text('Recent files',
                          style: theme.textTheme.titleSmall),
                    ),
                    TextButton(
                      onPressed: widget.recents.isEmpty
                          ? null
                          : () => widget.recents.clear(),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
                Text(
                  widget.recents.isEmpty
                      ? 'No recent files'
                      : '${widget.recents.items.length} remembered',
                  style: theme.textTheme.bodySmall,
                ),
                const Divider(height: 32),
                Text('System', style: theme.textTheme.titleSmall),
                ListTile(
                  key: const ValueKey('settings-default-app'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.assignment_turned_in_outlined),
                  title: const Text('Set up as default application'),
                  subtitle: Text(_defaultAppSubtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showDefaultAppSetup(context),
                ),
                const Divider(height: 32),
                Text('About', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text('${AppInfo.name} ${AppInfo.version}',
                    style: theme.textTheme.bodyMedium),
                Text(AppInfo.tagline, style: theme.textTheme.bodySmall),
                const SizedBox(height: 4),
                TextButton.icon(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  icon: const Icon(Icons.code, size: 18),
                  label: const Text('View source on GitHub'),
                  onPressed: () => launchUrl(Uri.parse(AppInfo.sourceUrl),
                      mode: LaunchMode.externalApplication),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
