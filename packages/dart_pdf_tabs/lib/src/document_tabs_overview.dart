import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

import 'document_tab_tile.dart';
import 'document_tabs_labels.dart';

/// An open-tabs grid for a compact bottom sheet or a desktop dialog: a
/// title-search field over a thumbnail grid that opens scrolled to the active
/// tab. The header's select button (or a long-press on a tile)
/// switches the grid into a multi-select whose header shares or closes the
/// checked tabs together.
class DocumentTabsOverview<T extends Object> extends StatefulWidget {
  const DocumentTabsOverview({
    super.key,
    required this.tabs,
    required this.activeIndex,
    required this.titleOf,
    required this.onActivate,
    required this.onCloseTabs,
    required this.tileBuilder,
    this.keyPrefix = 'tabs',
    this.headerTopPadding = 0,
    this.autofocusSearch = false,
    this.onOpen,
    this.shareLabel,
    this.shareIcon,
    this.onShare,
    this.labels = const DocumentTabsLabels(),
  });

  /// The host's live tab list (indices passed to [tileBuilder] and
  /// [onActivate] index into it).
  final List<T> tabs;
  final int activeIndex;

  /// A tab's title, which the search matches against.
  final String Function(T tab) titleOf;

  /// Prefixes the keys of the overview's controls (`<prefix>-tabs-search`,
  /// `<prefix>-tabs-grid`, ...) so two overviews can be told apart.
  final String keyPrefix;
  final double headerTopPadding;

  /// Whether the search field takes focus straight away - right for a
  /// desktop dialog, wrong on a phone, where it would raise the keyboard over
  /// the grid the user came to see.
  final bool autofocusSearch;

  /// The header's add button; hidden when null.
  final VoidCallback? onOpen;
  final void Function(int index) onActivate;

  /// The selection header's share action: its label and icon (Share on a
  /// phone, Save copies elsewhere) and what it does with the checked tabs.
  /// Hidden unless all three are given.
  final String? shareLabel;
  final IconData? shareIcon;
  final Future<void> Function(List<T> tabs)? onShare;

  final DocumentTabsLabels labels;

  /// Closes the checked tabs (confirming unsaved edits once for all of them).
  final Future<void> Function(List<T> tabs) onCloseTabs;

  final Widget Function(
    BuildContext context,
    int index,
    DocumentTabTileSelection selection,
  ) tileBuilder;

  static const double _padding = 12;
  static const gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: 220,
    mainAxisSpacing: _padding,
    crossAxisSpacing: _padding,
    childAspectRatio: 0.78,
  );

  @override
  State<DocumentTabsOverview<T>> createState() =>
      _DocumentTabsOverviewState<T>();
}

class _DocumentTabsOverviewState<T extends Object>
    extends State<DocumentTabsOverview<T>> {
  final _query = TextEditingController();
  ScrollController? _scroll;

  /// The checked tabs while the grid is selecting; null when it is not.
  /// Held by identity, so a tab closed meanwhile simply drops out.
  Set<T>? _selected;

  void _toggle(T tab) => setState(() {
        final selected = _selected ??= {};
        if (!selected.remove(tab)) selected.add(tab);
      });

  /// Checks every tab the search shows, or unchecks them when they all are.
  void _toggleAll(List<int> matches) => setState(() {
        final selected = _selected ??= {};
        final shown = [for (final i in matches) widget.tabs[i]];
        if (shown.every(selected.contains)) {
          selected.removeAll(shown);
        } else {
          selected.addAll(shown);
        }
      });

  /// The checked tabs in strip order.
  List<T> get _checkedTabs => [
        for (final tab in widget.tabs)
          if (_selected!.contains(tab)) tab
      ];

  @override
  void dispose() {
    _query.dispose();
    _scroll?.dispose();
    super.dispose();
  }

  /// Indices into [DocumentTabsOverview.tabs] whose title matches the search.
  List<int> _matches() {
    final query = _query.text.trim().toLowerCase();
    final tabs = widget.tabs;
    return [
      for (var i = 0; i < tabs.length; i++)
        if (query.isEmpty ||
            widget.titleOf(tabs[i]).toLowerCase().contains(query))
          i,
    ];
  }

  /// The scroll offset that centres the active tab's row in a viewport of
  /// [size], clamped to the grid's extent, so the grid opens on the current
  /// tab instead of the first row.
  double _activeOffset(Size size, int count) {
    final active = widget.activeIndex;
    if (active <= 0 || active >= count) return 0;
    const padding = DocumentTabsOverview._padding;
    final layout = DocumentTabsOverview.gridDelegate.getLayout(
      SliverConstraints(
        axisDirection: AxisDirection.down,
        growthDirection: GrowthDirection.forward,
        userScrollDirection: ScrollDirection.idle,
        scrollOffset: 0,
        precedingScrollExtent: 0,
        overlap: 0,
        remainingPaintExtent: size.height,
        crossAxisExtent: math.max(0, size.width - 2 * padding),
        crossAxisDirection: AxisDirection.right,
        viewportMainAxisExtent: size.height,
        remainingCacheExtent: size.height,
        cacheOrigin: 0,
      ),
    ) as SliverGridRegularTileLayout;
    final stride = layout.mainAxisStride;
    final rows = (count + layout.crossAxisCount - 1) ~/ layout.crossAxisCount;
    final row = active ~/ layout.crossAxisCount;
    final contentHeight = 2 * padding + rows * stride - padding;
    final maxOffset = math.max(0.0, contentHeight - size.height);
    final centred = padding +
        row * stride +
        layout.childMainAxisExtent / 2 -
        size.height / 2;
    return centred.clamp(0.0, maxOffset);
  }

  /// The header while selecting: leave, the count, then select all, share
  /// and close for the checked tabs.
  Widget _buildSelectionHeader(
    BuildContext context,
    Set<T> selected,
    List<int> matches,
  ) {
    final labels = widget.labels;
    final material = MaterialLocalizations.of(context);
    final onShare = widget.onShare;
    final shareIcon = widget.shareIcon;
    final prefix = widget.keyPrefix;
    final none = selected.isEmpty;
    return Row(
      children: [
        IconButton(
          key: ValueKey('$prefix-tabs-select-done'),
          icon: const Icon(Icons.arrow_back),
          tooltip: material.cancelButtonLabel,
          onPressed: () => setState(() => _selected = null),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            material.selectedRowCountTitle(selected.length),
            key: ValueKey('$prefix-tabs-selected-count'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        IconButton(
          key: ValueKey('$prefix-tabs-select-all'),
          icon: const Icon(Icons.select_all),
          tooltip: material.selectAllButtonLabel,
          onPressed: matches.isEmpty ? null : () => _toggleAll(matches),
        ),
        if (onShare != null && shareIcon != null && widget.shareLabel != null)
          IconButton(
            key: ValueKey('$prefix-tabs-share-selected'),
            icon: Icon(shareIcon),
            tooltip: widget.shareLabel,
            onPressed: none ? null : () => onShare(_checkedTabs),
          ),
        IconButton(
          key: ValueKey('$prefix-tabs-close-selected'),
          icon: const Icon(Icons.close),
          tooltip: labels.closeSelectedTabs,
          onPressed: none
              ? null
              : () async {
                  await widget.onCloseTabs(_checkedTabs);
                  if (mounted) setState(() {});
                },
        ),
      ],
    );
  }

  void _onQueryChanged(String _) {
    setState(() {});
    // A new result set starts from its first match.
    final scroll = _scroll;
    if (scroll != null && scroll.hasClients) scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final labels = widget.labels;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final prefix = widget.keyPrefix;
    final matches = _matches();
    _selected?.removeWhere((tab) => !widget.tabs.contains(tab));
    final selected = _selected;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
              selected == null ? 20 : 8, widget.headerTopPadding, 12, 8),
          child: selected == null
              ? Row(
                  children: [
                    Expanded(
                      child:
                          Text(labels.tabs, style: theme.textTheme.titleMedium),
                    ),
                    IconButton(
                      key: ValueKey('$prefix-tabs-select'),
                      icon: const Icon(Icons.checklist),
                      tooltip: labels.selectTabs,
                      onPressed: () => setState(() => _selected = {}),
                    ),
                    if (widget.onOpen != null)
                      IconButton(
                        key: ValueKey('$prefix-tabs-open'),
                        icon: const Icon(Icons.add),
                        tooltip: labels.openTab,
                        onPressed: widget.onOpen,
                      ),
                  ],
                )
              : _buildSelectionHeader(context, selected, matches),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: TextField(
            key: ValueKey('$prefix-tabs-search'),
            controller: _query,
            autofocus: widget.autofocusSearch,
            textInputAction: TextInputAction.go,
            decoration: InputDecoration(
              hintText: labels.searchTabs,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.text.isEmpty
                  ? null
                  : IconButton(
                      key: ValueKey('$prefix-tabs-search-clear'),
                      icon: const Icon(Icons.clear),
                      tooltip: labels.clearTabSearch,
                      onPressed: () {
                        _query.clear();
                        _onQueryChanged('');
                      },
                    ),
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            onChanged: _onQueryChanged,
            // Enter opens the best (first) match, like a quick switcher
            // (or checks it, while selecting).
            onSubmitted: (_) {
              if (matches.isEmpty) return;
              if (selected != null) {
                _toggle(widget.tabs[matches.first]);
              } else {
                widget.onActivate(matches.first);
              }
            },
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  // The first layout decides where the grid opens: on the
                  // active tab. The grid does not cache offscreen rows, so a
                  // measured initial offset (rather than a scroll after the
                  // first frame) never builds the top rows' thumbnails. The
                  // grid stays mounted while a search matches nothing so its
                  // position (reset per query) is never re-seeded from here.
                  _scroll ??= ScrollController(
                    initialScrollOffset: _activeOffset(
                      constraints.biggest,
                      widget.tabs.length,
                    ),
                  );
                  return GridView.builder(
                    key: ValueKey('$prefix-tabs-grid'),
                    controller: _scroll,
                    // A tile paints a real PDF thumbnail. Do not build the
                    // next row speculatively: with large documents that work
                    // competes with a fling even though the thumbnails are
                    // still off-screen.
                    scrollCacheExtent: const ScrollCacheExtent.pixels(0),
                    padding:
                        const EdgeInsets.all(DocumentTabsOverview._padding),
                    gridDelegate: DocumentTabsOverview.gridDelegate,
                    itemCount: matches.length,
                    itemBuilder: (context, i) {
                      final tab = widget.tabs[matches[i]];
                      return widget.tileBuilder(context, matches[i], (
                        selecting: selected != null,
                        checked: selected?.contains(tab) ?? false,
                        toggle: () => _toggle(tab),
                      ));
                    },
                  );
                },
              ),
              if (matches.isEmpty)
                Center(
                  key: ValueKey('$prefix-tabs-no-matches'),
                  child: Text(
                    labels.noMatchingTabs,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            labels.tabsOpenCount(widget.tabs.length),
            style: theme.textTheme.labelMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
