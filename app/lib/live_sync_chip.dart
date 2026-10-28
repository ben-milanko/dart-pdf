import 'package:material_ui/material_ui.dart';

import 'l10n/app_l10n.dart';
import 'live_sync.dart';

/// App-bar indicator for a document in live sync: whether it is working
/// (connecting, live, offline) and who else is in the document. Tapping it
/// opens [showLiveSyncDetails].
class LiveSyncChip extends StatelessWidget {
  const LiveSyncChip({
    super.key,
    required this.session,
    required this.selfName,
    required this.onStop,
  });

  final LiveSyncSession session;

  /// How this session appears to the others, listed first as "(you)".
  final String selfName;

  /// Ends live sync for the document.
  final VoidCallback onStop;

  /// Peer avatars shown before the rest collapse into "+N".
  static const maxAvatars = 3;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          final l = appL10n(context);
          final scheme = Theme.of(context).colorScheme;
          final peers = session.peers;
          final (
            Widget icon,
            String label,
            Color background,
            Color foreground
          ) = switch (session.status) {
            LiveSyncStatus.connecting => (
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                l.liveSyncConnecting,
                scheme.secondaryContainer,
                scheme.onSecondaryContainer,
              ),
            LiveSyncStatus.live => (
                Icon(Icons.circle, size: 10, color: Colors.green.shade600),
                l.liveSyncLive,
                scheme.secondaryContainer,
                scheme.onSecondaryContainer,
              ),
            LiveSyncStatus.offline => (
                Icon(Icons.cloud_off, size: 14, color: scheme.onErrorContainer),
                l.liveSyncOffline,
                scheme.errorContainer,
                scheme.onErrorContainer,
              ),
          };
          return Tooltip(
            message: [
              l.liveSyncPeopleCount(peers.length),
              for (final peer in peers) peer.name,
            ].join('\n'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Material(
                key: const ValueKey('live-sync-chip'),
                color: background,
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => showLiveSyncDetails(context,
                      session: session, selfName: selfName, onStop: onStop),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(
                        start: 10, end: 6, top: 4, bottom: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        icon,
                        const SizedBox(width: 6),
                        Text(label,
                            key: const ValueKey('live-sync-status'),
                            style: TextStyle(fontSize: 12, color: foreground)),
                        const SizedBox(width: 4),
                        for (final peer in peers.take(maxAvatars))
                          Padding(
                            padding: const EdgeInsetsDirectional.only(start: 2),
                            child: LiveSyncAvatar(name: peer.name, id: peer.id),
                          ),
                        if (peers.length > maxAvatars)
                          Padding(
                            padding: const EdgeInsetsDirectional.only(start: 4),
                            child: Text('+${peers.length - maxAvatars}',
                                style:
                                    TextStyle(fontSize: 12, color: foreground)),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
}

/// A peer's initials on a colour derived from their writer id, so the same
/// session keeps its colour as people come and go.
class LiveSyncAvatar extends StatelessWidget {
  const LiveSyncAvatar({super.key, required this.name, required this.id});

  final String name;
  final String id;

  static const _colors = [
    Color(0xFF1E88E5),
    Color(0xFF8E24AA),
    Color(0xFF00897B),
    Color(0xFFF4511E),
    Color(0xFF6D4C41),
    Color(0xFF3949AB),
    Color(0xFFC0CA33),
    Color(0xFFD81B60),
  ];

  /// Up to two initials from [name]'s words; '?' for an empty name.
  static String initials(String name) {
    final words = name.trim().split(RegExp(r'[\s._-]+'))
      ..removeWhere((w) => w.isEmpty);
    if (words.isEmpty) return '?';
    final first = words.first.characters.first;
    final last = words.length > 1 ? words.last.characters.first : '';
    return (first + last).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final color = _colors[id.hashCode.abs() % _colors.length];
    return Semantics(
      label: name,
      child: CircleAvatar(
        radius: 11,
        backgroundColor: color,
        child: Text(
          initials(name),
          style: const TextStyle(
              fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// The details behind the chip: status, everyone in the document, which
/// device writes the PDF, and a Stop button.
Future<void> showLiveSyncDetails(
  BuildContext context, {
  required LiveSyncSession session,
  required String selfName,
  required VoidCallback onStop,
}) =>
    showDialog<void>(
      context: context,
      builder: (context) => ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          final l = appL10n(context);
          final status = switch (session.status) {
            LiveSyncStatus.connecting => l.liveSyncConnecting,
            LiveSyncStatus.live => l.liveSyncLive,
            LiveSyncStatus.offline => l.liveSyncOfflineDetail,
          };
          return AlertDialog(
            key: const ValueKey('live-sync-details'),
            title: Text(l.liveSyncDetailsTitle),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(status),
                  const SizedBox(height: 12),
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading:
                        LiveSyncAvatar(name: selfName, id: session.writerId),
                    title: Text(l.liveSyncYou(selfName)),
                  ),
                  for (final peer in session.peers)
                    ListTile(
                      key: ValueKey('live-sync-peer-${peer.id}'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: LiveSyncAvatar(name: peer.name, id: peer.id),
                      title: Text(peer.name),
                      subtitle: peer.device == null || peer.device == peer.name
                          ? null
                          : Text(peer.device!),
                    ),
                  if (session.peers.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(l.liveSyncNobodyElse),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    session.isWriter
                        ? l.liveSyncWritesPdf
                        : l.liveSyncOtherWritesPdf,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                key: const ValueKey('live-sync-stop'),
                onPressed: () {
                  Navigator.of(context).pop();
                  onStop();
                },
                child: Text(l.liveSyncMenuStop),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(MaterialLocalizations.of(context).closeButtonLabel),
              ),
            ],
          );
        },
      ),
    );
