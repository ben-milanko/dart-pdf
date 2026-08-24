import 'package:dart_pdf_editor/dart_pdf_editor.dart' show pdfSearchInputBorder;
import 'package:flutter/material.dart';

import 'app_info.dart';
import 'l10n/app_l10n.dart';
import 'middle_ellipsis_text.dart';
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
    this.excludedIds = const {},
    this.showHero = true,
    this.autofocusSearch = false,
  });

  final RecentsStore recents;
  final VoidCallback onOpen;
  final void Function(RecentFile entry) onOpenRecent;

  /// Recent entries already open in document tabs are omitted when this set
  /// is provided by the full recent-files browser.
  final Set<String> excludedIds;

  /// Whether to show the DartPDF logo and primary open button above recents.
  /// The dedicated recent-files route hides this welcome-only chrome.
  final bool showHero;

  /// Focuses the recent search when opening the dedicated browser route.
  final bool autofocusSearch;

  /// Renders the first-page thumbnail shown beside each recent entry. When
  /// null (or an entry has no readable source), the list shows a generic
  /// document icon instead.
  final RecentThumbnailCache? thumbnails;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

/// Full list/grid recent-files browser opened from the Open Recent submenu.
///
/// It shares the same search and layouts as [WelcomeScreen], so both entry
/// points behave consistently.
class RecentFilesScreen extends StatelessWidget {
  const RecentFilesScreen({
    super.key,
    required this.recents,
    required this.onOpenRecent,
    this.thumbnails,
    this.excludedIds = const {},
  });

  final RecentsStore recents;
  final void Function(RecentFile entry) onOpenRecent;
  final RecentThumbnailCache? thumbnails;
  final Set<String> excludedIds;

  @override
  Widget build(BuildContext context) {
    final l10n = appL10n(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsRecentFiles),
        actions: [
          ListenableBuilder(
            listenable: recents,
            builder: (context, _) => IconButton(
              key: const ValueKey('recent-files-clear'),
              tooltip: l10n.editorClearRecentFiles,
              onPressed: recents.isEmpty ? null : recents.clear,
              icon: const Icon(Icons.clear_all),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: WelcomeScreen(
        recents: recents,
        onOpen: () {},
        onOpenRecent: (entry) {
          Navigator.of(context).pop();
          onOpenRecent(entry);
        },
        thumbnails: thumbnails,
        excludedIds: excludedIds,
        showHero: false,
        autofocusSearch: true,
      ),
    );
  }
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  // Null until the user explicitly picks a layout with the toggle; while null
  // the layout follows the available width (grid when wide, list when narrow),
  // so resizing the window flips the default but an explicit choice sticks.
  RecentsView? _view;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.addListener(_searchChanged);
  }

  @override
  void dispose() {
    _search
      ..removeListener(_searchChanged)
      ..dispose();
    super.dispose();
  }

  void _searchChanged() => setState(() {});

  bool _matchesSearch(RecentFile entry) {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return true;
    return entry.title.toLowerCase().contains(query) ||
        (entry.path?.toLowerCase().contains(query) ?? false);
  }

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
                  final allItems = [
                    for (final item in widget.recents.items)
                      if (!widget.excludedIds.contains(item.id)) item,
                  ];
                  final items = [
                    for (final item in allItems)
                      if (_matchesSearch(item)) item,
                  ];
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.showHero) ...[
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
                      ],
                      if (allItems.isNotEmpty) ...[
                        SizedBox(height: widget.showHero ? 28 : 8),
                        _RecentsHeader(
                          view: view,
                          search: _search,
                          autofocusSearch: widget.autofocusSearch,
                          onViewChanged: (v) => setState(() => _view = v),
                        ),
                        const SizedBox(height: 8),
                        Flexible(
                          child: items.isEmpty
                              ? const _NoMatchingRecents()
                              : view == RecentsView.grid
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
                      ] else if (!widget.showHero) ...[
                        const SizedBox(height: 96),
                        Center(
                            child: Text(appL10n(context).editorNoRecentFiles)),
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

class _RecentsHeader extends StatelessWidget {
  const _RecentsHeader({
    required this.view,
    required this.search,
    required this.autofocusSearch,
    required this.onViewChanged,
  });

  final RecentsView view;
  final TextEditingController search;
  final bool autofocusSearch;
  final ValueChanged<RecentsView> onViewChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = Text(
      appL10n(context).welcomeRecent,
      style: theme.textTheme.titleSmall,
    );
    final toggle = _ViewToggle(view: view, onChanged: onViewChanged);
    final searchField = _RecentSearchField(
      controller: search,
      autofocus: autofocusSearch,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 560) {
          return Row(
            children: [
              Expanded(child: title),
              SizedBox(width: 280, child: searchField),
              const SizedBox(width: 12),
              toggle,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [Expanded(child: title), toggle]),
            const SizedBox(height: 8),
            searchField,
          ],
        );
      },
    );
  }
}

class _RecentSearchField extends StatelessWidget {
  const _RecentSearchField({
    required this.controller,
    required this.autofocus,
  });

  final TextEditingController controller;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => TextField(
        key: const ValueKey('recent-files-search'),
        controller: controller,
        autofocus: autofocus,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: appL10n(context).welcomeSearchRecentFiles,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  key: const ValueKey('recent-files-search-clear'),
                  tooltip: appL10n(context).clear,
                  onPressed: controller.clear,
                  icon: const Icon(Icons.close),
                ),
          border: pdfSearchInputBorder,
          isDense: true,
        ),
      );
}

class _NoMatchingRecents extends StatelessWidget {
  const _NoMatchingRecents();

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(appL10n(context).welcomeNoMatchingRecentFiles),
          ],
        ),
      );
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
      key: const ValueKey('recent-files-list'),
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
          title: MiddleEllipsisText(entry.title),
          subtitle: entry.path != null
              ? MiddleEllipsisText(entry.path!)
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
      key: const ValueKey('recent-files-grid'),
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
  // Fixed height of the thumbnail slot (~A4 portrait at [_tileWidth]). The
  // aspect-sized thumbnail is centred within it, so every tile keeps a common
  // height and the titles below share one bottom baseline regardless of each
  // page's shape.
  static const double _slotHeight = 210;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = entry.isReopenable;
    // The tooltip shows the full path when we have one (titles ellipsize),
    // otherwise the same reopen hint the list row carries.
    final tooltip = entry.path != null
        ? '${entry.title}\n${entry.path}'
        : enabled
            ? appL10n(context).welcomeTapToReopen
            : appL10n(context).welcomePickAgainToReopen;

    final thumbnail = Stack(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: enabled ? onOpen : null,
          child: _RecentThumbnail(
            key: ValueKey('recent-tile-thumb-${entry.id}'),
            entry: entry,
            thumbnails: thumbnails,
            width: _tileWidth,
            // Aspect-aware, but bounded to the slot so it stays centred in it.
            maxHeight: _slotHeight,
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
    );

    final tile = SizedBox(
      width: _tileWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Fixed slot: the thumbnail is centred vertically within it.
          SizedBox(
            height: _slotHeight,
            child: Center(child: thumbnail),
          ),
          const SizedBox(height: 6),
          // Fixed two-line box with the title pinned to the bottom, so a
          // one-line title sits on the same baseline as a two-line one and
          // titles line up across the whole grid.
          SizedBox(
            height: _twoLineHeight(context, theme.textTheme.bodySmall),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: MiddleEllipsisText(
                entry.title,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ),
    );

    return Tooltip(
      message: tooltip,
      child: Opacity(opacity: enabled ? 1.0 : 0.5, child: tile),
    );
  }

  /// Height of two lines of [style] at the current text scale, so the reserved
  /// title box always fits a wrapped two-line title.
  static double _twoLineHeight(BuildContext context, TextStyle? style) {
    final painter = TextPainter(
      text: TextSpan(text: 'Ag\nAg', style: style),
      maxLines: 2,
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
    )..layout(maxWidth: _tileWidth);
    final height = painter.height;
    painter.dispose();
    return height;
  }
}

/// A first-page thumbnail for a recent entry: renders once (memoized in the
/// [RecentThumbnailCache], keyed on [RecentFile.id]) and holds the future
/// across rebuilds so scrolling / recents changes don't flash back to the
/// placeholder. Falls back to a generic document icon while the render is
/// pending, when no cache is provided, or when the render fails.
///
/// With a fixed [height] (the list) the box is [width]×[height] and the
/// hairline border hugs the contained image. With [height] null (the grid)
/// the box takes [width] and derives its height from the rendered page's
/// aspect ratio, so each tile is shaped like its own page instead of being
/// letterboxed into a common box; the image then fills that box.
class _RecentThumbnail extends StatefulWidget {
  const _RecentThumbnail({
    super.key,
    required this.entry,
    required this.thumbnails,
    required this.width,
    this.height,
    this.maxHeight,
    this.iconSize,
  });

  final RecentFile entry;
  final RecentThumbnailCache? thumbnails;
  final double width;

  /// Fixed box height (list). Null makes the thumbnail aspect-aware (grid):
  /// its height follows the rendered page's aspect ratio.
  final double? height;

  /// Upper bound for the aspect-derived height (grid); ignored when [height]
  /// is set. Keeps the thumbnail inside the grid tile's fixed slot.
  final double? maxHeight;
  final double? iconSize;

  @override
  State<_RecentThumbnail> createState() => _RecentThumbnailState();
}

class _RecentThumbnailState extends State<_RecentThumbnail> {
  // A4 portrait - the box shape assumed before the real aspect ratio is known,
  // so the placeholder box already resembles a typical page.
  static const double _defaultAspect = 0.7071;
  // Clamp derived heights so a pathological page (a banner or a tall receipt)
  // can't blow the row height out; extremes get cropped by the cover fit.
  static const double _minHeight = 90;
  static const double _maxHeight = 260;

  // Fetched once and held for the widget's lifetime. The widget is keyed by
  // entry.id, so a different entry lands on a fresh state (and re-fetches from
  // the cache, which memoizes) rather than mutating this one.
  late final Future<RecentThumbnail?>? _thumbnail =
      widget.thumbnails?.thumbnailFor(widget.entry);

  bool get _aspectAware => widget.height == null;

  double _heightFor(RecentThumbnail? thumb) {
    if (!_aspectAware) return widget.height!;
    final aspect = thumb?.aspectRatio ?? _defaultAspect;
    return (widget.width / aspect)
        .clamp(_minHeight, widget.maxHeight ?? _maxHeight);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final placeholder = Icon(Icons.description_outlined,
        size: widget.iconSize, color: theme.iconTheme.color);
    final future = _thumbnail;
    const radius = BorderRadius.all(Radius.circular(4));

    Widget framed(RecentThumbnail thumb, double height) {
      // Aspect-aware tiles size their box to the page, so the image fills it
      // (cover, cropping only a clamped extreme); the fixed-box list lets the
      // border hug the contained image.
      final image = Image.memory(
        thumb.pngBytes,
        fit: _aspectAware ? BoxFit.cover : BoxFit.contain,
        gaplessPlayback: true,
        width: _aspectAware ? widget.width : null,
        height: _aspectAware ? height : null,
      );
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: theme.dividerColor),
        ),
        child: ClipRRect(borderRadius: radius, child: image),
      );
    }

    Widget box(double height, Widget child) =>
        SizedBox(width: widget.width, height: height, child: child);

    if (future == null) {
      return box(_heightFor(null), Center(child: placeholder));
    }
    return FutureBuilder<RecentThumbnail?>(
      future: future,
      builder: (context, snapshot) {
        final thumb = snapshot.data;
        final height = _heightFor(thumb);
        if (thumb == null) return box(height, Center(child: placeholder));
        return box(height, Center(child: framed(thumb, height)));
      },
    );
  }
}
