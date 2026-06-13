import 'package:flutter/material.dart';

import 'app_info.dart';
import 'recents.dart';

/// The landing surface shown when no document is open: a hero with the open
/// action and, below it, the most-recent documents.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({
    super.key,
    required this.recents,
    required this.onOpen,
    required this.onOpenRecent,
  });

  final RecentsStore recents;
  final VoidCallback onOpen;
  final void Function(RecentFile entry) onOpenRecent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
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
                  label: const Text('Open a PDF'),
                ),
                if (items.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Recent', style: theme.textTheme.titleSmall),
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
                          leading: const Icon(Icons.description_outlined),
                          title: Text(entry.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: entry.path != null
                              ? Text(entry.path!,
                                  maxLines: 1, overflow: TextOverflow.ellipsis)
                              : const Text('Pick again to reopen'),
                          enabled: entry.isReopenable,
                          trailing: IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            tooltip: 'Remove from recent',
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
    );
  }
}
