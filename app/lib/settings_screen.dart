import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_info.dart';
import 'recents.dart';

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
                    child: Text('Recent files', style: theme.textTheme.titleSmall),
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
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
