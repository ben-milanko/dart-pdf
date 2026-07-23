import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'app_info.dart';
import 'l10n/app_l10n.dart';
import 'recent_thumbnails.dart';
import 'recents.dart';

/// The landing surface shown when no document is open: a hero with the open
/// action and, below it, the most-recent documents.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({
    super.key,
    required this.recents,
    required this.onOpen,
    required this.onOpenRecent,
    this.thumbnails,
  });

  final RecentsStore recents;
  final VoidCallback onOpen;
  final void Function(RecentFile entry) onOpenRecent;

  /// Renders the first-page thumbnail shown beside each recent entry. When
  /// null (or an entry has no readable source), the list shows a generic
  /// document icon instead.
  final RecentThumbnailCache? thumbnails;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListenableBuilder(
            listenable: recents,
            builder: (context, _) {
              final items = recents.items;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.picture_as_pdf_outlined,
                      size: 64, color: theme.colorScheme.primary),
                  const SizedBox(height: 12),
                  Text(AppInfo.name,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: onOpen,
                    icon: const Icon(Icons.folder_open),
                    label: Text(appL10n(context).welcomeOpenPdf),
                  ),
                  if (items.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(appL10n(context).welcomeRecent,
                          style: theme.textTheme.titleSmall),
                    ),
                    const SizedBox(height: 4),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final entry = items[i];
                          return ListTile(
                            key: ValueKey('recent-${entry.id}'),
                            leading: _RecentLeading(
                                key: ValueKey('recent-leading-${entry.id}'),
                                entry: entry,
                                thumbnails: thumbnails),
                            title: Text(entry.title,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: entry.path != null
                                ? Text(entry.path!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis)
                                : entry.isReopenable
                                    // Mobile: reopens from a private snapshot,
                                    // so no path to show and no re-pick needed.
                                    ? Text(appL10n(context).welcomeTapToReopen)
                                    : Text(appL10n(context)
                                        .welcomePickAgainToReopen),
                            enabled: entry.isReopenable,
                            trailing: IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              tooltip: appL10n(context).welcomeRemoveFromRecent,
                              onPressed: () => recents.remove(entry.id),
                            ),
                            onTap: entry.isReopenable
                                ? () => onOpenRecent(entry)
                                : null,
                          );
                        },
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The leading widget for a recent-file row: the document's first-page
/// thumbnail once it renders, falling back to a generic icon while it loads
/// (or when no thumbnail is available). Fetches the thumbnail once per entry
/// and holds it across rebuilds so scrolling / recents changes don't reset it
/// to the placeholder.
class _RecentLeading extends StatefulWidget {
  const _RecentLeading({super.key, required this.entry, required this.thumbnails});

  final RecentFile entry;
  final RecentThumbnailCache? thumbnails;

  @override
  State<_RecentLeading> createState() => _RecentLeadingState();
}

class _RecentLeadingState extends State<_RecentLeading> {
  // Fetched once and held for the widget's lifetime. The row is keyed by
  // entry.id, so a different entry lands on a fresh state (and re-fetches from
  // the cache, which memoizes) rather than mutating this one.
  late final Future<Uint8List?>? _thumbnail =
      widget.thumbnails?.thumbnailFor(widget.entry);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final placeholder = Icon(Icons.description_outlined,
        color: theme.iconTheme.color);
    final future = _thumbnail;
    const radius = BorderRadius.all(Radius.circular(4));
    return SizedBox(
      width: 48,
      height: 62,
      child: future == null
          ? Center(child: placeholder)
          : FutureBuilder<Uint8List?>(
              future: future,
              builder: (context, snapshot) {
                final bytes = snapshot.data;
                if (bytes == null) return Center(child: placeholder);
                return Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: radius,
                      border: Border.all(color: theme.dividerColor),
                    ),
                    child: ClipRRect(
                      borderRadius: radius,
                      child: Image.memory(
                        bytes,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
