import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'l10n/app_l10n.dart';
import 'pdf_cache.dart';
import 'recents.dart';

/// Settings for disposable web snapshots, separate from Recents and recovery.
class CachedDocumentsSettings extends StatefulWidget {
  const CachedDocumentsSettings(
      {super.key,
      required this.recents,
      this.readUsage = cachedPdfUsage,
      this.clearCache = clearCachedPdfs});

  final RecentsStore recents;
  final Future<PdfCacheUsage?> Function() readUsage;
  final Future<bool> Function() clearCache;

  @override
  State<CachedDocumentsSettings> createState() =>
      _CachedDocumentsSettingsState();
}

class _CachedDocumentsSettingsState extends State<CachedDocumentsSettings> {
  late Future<PdfCacheUsage?> _usage;
  bool _clearing = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _usage = widget.readUsage();
    widget.recents.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.recents.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() {
        _usage = widget.readUsage();
      });

  Future<void> _clear() async {
    final checked = {
      for (final entry in widget.recents.items)
        if (entry.cachePath != null) entry.cachePath!,
    };
    setState(() {
      _clearing = true;
      _failed = false;
    });
    var cleared = false;
    try {
      cleared = await widget.clearCache();
    } catch (_) {
      // Keep the size and Recent availability when storage rejects the clear.
    }
    if (cleared) await widget.recents.updateCachedAvailability(checked, {});
    if (!mounted) return;
    setState(() {
      _clearing = false;
      _failed = !cleared;
      _usage = widget.readUsage();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = appL10n(context);
    final style = Theme.of(context).textTheme;
    final number =
        NumberFormat.decimalPattern(Localizations.localeOf(context).toString())
          ..minimumFractionDigits = 1
          ..maximumFractionDigits = 1;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(l10n.settingsCachedDocuments, style: style.titleSmall),
      const SizedBox(height: 8),
      FutureBuilder<PdfCacheUsage?>(
          future: _usage,
          builder: (context, snapshot) {
            final usage = snapshot.data;
            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (snapshot.connectionState != ConnectionState.done)
                    const LinearProgressIndicator()
                  else
                    Text(
                        usage == null
                            ? l10n.settingsCacheUnavailable
                            : l10n.settingsCacheUsage(
                                number.format(usage.bytes / (1024 * 1024)),
                                '${pdfCacheMaxBytes ~/ (1024 * 1024)}'),
                        key: const ValueKey('settings-cache-usage'),
                        style: style.bodySmall),
                  Text(
                      l10n.settingsCacheExplanation(
                          '${pdfCacheMaxFileBytes ~/ (1024 * 1024)}'),
                      style: style.bodySmall),
                  TextButton.icon(
                    key: const ValueKey('settings-clear-cache'),
                    onPressed: _clearing ||
                            usage?.documents == 0 ||
                            snapshot.connectionState != ConnectionState.done
                        ? null
                        : _clear,
                    icon: const Icon(Icons.delete_outline),
                    label: Text(l10n.settingsClearCachedDocuments),
                  ),
                ]);
          }),
      if (_failed)
        Text(l10n.settingsCacheClearFailed,
            style: style.bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.error)),
    ]);
  }
}
