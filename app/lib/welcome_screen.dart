import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'app_info.dart';
import 'l10n/app_l10n.dart';
import 'recent_thumbnails.dart';
import 'recents.dart';

/// How the recent-documents section is laid out.
enum RecentsView {
  /// A vertical list of rows with a small leading thumbnail.
  list,

  /// A reflowing grid of large thumbnail tiles.
  grid,
}

/// Body width at or above which the grid is the default recents layout. Below
/// it (phones / narrow windows) the list is the default. Mirrors the editor's
/// own mobile breakpoint so the two agree on what "narrow" means.
const double _gridDefaultBreakpoint = 700;

/// The landing surface shown when no document is open: a hero with the open
/// action and, below it, the most-recent documents.
class WelcomeScreen extends StatefulWidget {
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
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  // Null until the user explicitly picks a layout with the toggle; while null
  // the layout follows the available width (grid when wide, list when narrow),
  // so resizing the window flips the default but an explicit choice sticks.
  RecentsView? _view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final view = _view ??
            (constraints.maxWidth >= _gridDefaultBreakpoint
                ? RecentsView.grid
                : RecentsView.list);
        // The grid wants more room to lay out several tiles per row; the list
        // reads better kept narrow.
        final maxWidth = view == RecentsView.grid ? 900.0 : 520.0;
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: ListenableBuilder(
                listenable: widget.recents,
                builder: (context, _) {
                  final items = widget.recents.items;
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
                      Align(
                        alignment: Alignment.center,
                        child: FilledButton.icon(
                          onPressed: widget.onOpen,
                          icon: const Icon(Icons.folder_open),
                          label: Text(appL10n(context).welcomeOpenPdf),
                        ),
                      ),
                      if (items.isNotEmpty) ...[
                        const SizedBox(height: 28),
                        Row(
                          children: [
                            Expanded(
                              child: Text(appL10n(context).welcomeRecent,
                                  style: theme.textTheme.titleSmall),
                            ),
                            _ViewToggle(
                              view: view,
                              onChanged: (v) => setState(() => _view = v),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Flexible(
                          child: view == RecentsView.grid
                              ? _RecentsGrid(
                                  items: items,
                                  recents: widget.recents,
                                  onOpenRecent: widget.onOpenRecent,
                                  thumbnails: widget.thumbnails,
                                )
                              : _RecentsList(
                                  items: items,
                                  recents: widget.recents,
                                  onOpenRecent: widget.onOpenRecent,
                                  thumbnails: widget.thumbnails,
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
      },
    );
  }
}

/// The list/grid layout switch shown beside the "Recent" header.
class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.view, required this.onChanged});

  final RecentsView view;
  final ValueChanged<RecentsView> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = appL10n(context);
    return SegmentedButton<RecentsView>(
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      segments: [
        ButtonSegment(
          value: RecentsView.list,
          icon: const Icon(Icons.view_list_outlined, size: 18),
          tooltip: l10n.welcomeViewAsList,
        ),
        ButtonSegment(
          value: RecentsView.grid,
          icon: const Icon(Icons.grid_view_outlined, size: 18),
          tooltip: l10n.welcomeViewAsGrid,
        ),
      ],
      selected: {view},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

/// The recents rendered as a vertical list, each row leading with a small
/// first-page thumbnail.
class _RecentsList extends StatelessWidget {
  const _RecentsList({
    required this.items,
    required this.recents,
    required this.onOpenRecent,
    required this.thumbnails,
  });

  final List<RecentFile> items;
  final RecentsStore recents;
  final void Function(RecentFile entry) onOpenRecent;
  final RecentThumbnailCache? thumbnails;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      itemCount: items.length,
      itemBuilder: (context, i) {
        final entry = items[i];
        return ListTile(
          key: ValueKey('recent-${entry.id}'),
          leading: _RecentThumbnail(
            key: ValueKey('recent-leading-${entry.id}'),
            entry: entry,
            thumbnails: thumbnails,
            width: 48,
            height: 62,
          ),
          title: Text(entry.title,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: entry.path != null
              ? Text(entry.path!, maxLines: 1, overflow: TextOverflow.ellipsis)
              : entry.isReopenable
                  // Mobile: reopens from a private snapshot, so no path to
                  // show and no re-pick needed.
                  ? Text(appL10n(context).welcomeTapToReopen)
                  : Text(appL10n(context).welcomePickAgainToReopen),
          enabled: entry.isReopenable,
          trailing: IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: appL10n(context).welcomeRemoveFromRecent,
            onPressed: () => recents.remove(entry.id),
          ),
          onTap: entry.isReopenable ? () => onOpenRecent(entry) : null,
        );
      },
    );
  }
}

/// The recents rendered as a reflowing grid of large thumbnail tiles.
class _RecentsGrid extends StatelessWidget {
  const _RecentsGrid({
    required this.items,
    required this.recents,
    required this.onOpenRecent,
    required this.thumbnails,
  });

  final List<RecentFile> items;
  final RecentsStore recents;
  final void Function(RecentFile entry) onOpenRecent;
  final RecentThumbnailCache? thumbnails;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final entry in items)
              _RecentGridTile(
                key: ValueKey('recent-tile-${entry.id}'),
                entry: entry,
                thumbnails: thumbnails,
                onOpen: () => onOpenRecent(entry),
                onRemove: () => recents.remove(entry.id),
              ),
          ],
        ),
      ),
    );
  }
}

/// A single grid cell: a large first-page thumbnail with the document title
/// below and a corner remove button. Disabled (dimmed, non-tappable) when the
/// entry can no longer be reopened directly.
class _RecentGridTile extends StatelessWidget {
  const _RecentGridTile({
    super.key,
    required this.entry,
    required this.thumbnails,
    required this.onOpen,
    required this.onRemove,
  });

  final RecentFile entry;
  final RecentThumbnailCache? thumbnails;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  static const double _tileWidth = 150;
  static const double _thumbHeight = 190;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = entry.isReopenable;
    final subtitle = entry.path ??
        (enabled
            ? appL10n(context).welcomeTapToReopen
            : appL10n(context).welcomePickAgainToReopen);

    final tile = SizedBox(
      width: _tileWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: enabled ? onOpen : null,
                child: _RecentThumbnail(
                  key: ValueKey('recent-tile-thumb-${entry.id}'),
                  entry: entry,
                  thumbnails: thumbnails,
                  width: _tileWidth,
                  height: _thumbHeight,
                  fill: true,
                  iconSize: 48,
                ),
              ),
              Positioned(
                top: 2,
                right: 2,
                child: Material(
                  color: theme.colorScheme.surface.withValues(alpha: 0.85),
                  shape: const CircleBorder(),
                  child: IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                    tooltip: appL10n(context).welcomeRemoveFromRecent,
                    onPressed: onRemove,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            entry.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );

    return Tooltip(
      message: entry.path != null ? '${entry.title}\n${entry.path}' : subtitle,
      child: Opacity(opacity: enabled ? 1.0 : 0.5, child: tile),
    );
  }
}

/// A first-page thumbnail for a recent entry: renders once (memoized in the
/// [RecentThumbnailCache], keyed on [RecentFile.id]) and holds the future
/// across rebuilds so scrolling / recents changes don't flash back to the
/// placeholder. Falls back to a generic document icon while the render is
/// pending, when no cache is provided, or when the render fails.
///
/// With [fill] false (the list) the hairline border hugs the rendered image,
/// which fits within [width]×[height]. With [fill] true (the grid) the image
/// is letterboxed to fill that box so tiles line up regardless of page
/// aspect ratio or device pixel ratio.
class _RecentThumbnail extends StatefulWidget {
  const _RecentThumbnail({
    super.key,
    required this.entry,
    required this.thumbnails,
    required this.width,
    required this.height,
    this.fill = false,
    this.iconSize,
  });

  final RecentFile entry;
  final RecentThumbnailCache? thumbnails;
  final double width;
  final double height;
  final bool fill;
  final double? iconSize;

  @override
  State<_RecentThumbnail> createState() => _RecentThumbnailState();
}

class _RecentThumbnailState extends State<_RecentThumbnail> {
  // Fetched once and held for the widget's lifetime. The widget is keyed by
  // entry.id, so a different entry lands on a fresh state (and re-fetches from
  // the cache, which memoizes) rather than mutating this one.
  late final Future<Uint8List?>? _thumbnail =
      widget.thumbnails?.thumbnailFor(widget.entry);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final placeholder = Icon(Icons.description_outlined,
        size: widget.iconSize, color: theme.iconTheme.color);
    final future = _thumbnail;
    const radius = BorderRadius.all(Radius.circular(4));

    Widget framed(Uint8List bytes) {
      final image = Image.memory(
        bytes,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        width: widget.fill ? widget.width : null,
        height: widget.fill ? widget.height : null,
      );
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: theme.dividerColor),
        ),
        child: ClipRRect(borderRadius: radius, child: image),
      );
    }

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: future == null
          ? Center(child: placeholder)
          : FutureBuilder<Uint8List?>(
              future: future,
              builder: (context, snapshot) {
                final bytes = snapshot.data;
                if (bytes == null) return Center(child: placeholder);
                return Center(child: framed(bytes));
              },
            ),
    );
  }
}
