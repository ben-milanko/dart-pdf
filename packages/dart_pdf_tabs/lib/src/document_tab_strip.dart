import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'document_tab_drag_start_listener.dart';
import 'document_tabs_labels.dart';
import 'middle_ellipsis_text.dart';

/// The fixed dimensions of a [DocumentTabStrip].
@immutable
class DocumentTabStripMetrics {
  const DocumentTabStripMetrics({
    this.height = 42,
    this.minTabWidth = 56,
    this.maxTabWidth = 240,
    this.closeHideWidth = 100,
    this.buttonWidth = 40,
    this.listPadding = 4,
    this.resizeDuration = const Duration(milliseconds: 150),
  });

  /// Height of the strip.
  final double height;

  /// Chrome-style sizing: tabs share the strip equally, growing no wider than
  /// [maxTabWidth] and shrinking no narrower than [minTabWidth] before the
  /// strip starts to scroll.
  final double minTabWidth;
  final double maxTabWidth;

  /// Below this per-tab width the close button is hidden on inactive tabs (as
  /// in Chrome) so the label keeps room; the active tab always keeps its close.
  final double closeHideWidth;

  /// Width of the strip's add and view-all buttons.
  final double buttonWidth;

  /// Padding at each end of the tab list.
  final double listPadding;

  /// How long the tabs take to grow back after the pointer leaves the strip
  /// following a close (the width-hold release animation).
  final Duration resizeDuration;

  /// The equal-share width for one of [count] tabs given the space
  /// [available] to the whole tab list, clamped between [minTabWidth] and
  /// [maxTabWidth]. Below the minimum the tabs stop shrinking and the strip
  /// scrolls instead.
  double tabWidthFor(double available, int count) {
    if (count == 0) return 0;
    return (available / count).clamp(minTabWidth, maxTabWidth).toDouble();
  }
}

/// The state a [DocumentTabStrip] keeps across rebuilds and that its host
/// reads back: the list's scroll position, the most recent layout, and the
/// Chrome-style close-streak width hold.
///
/// Closing a tab while the pointer is over the strip would normally let the
/// survivors grow into the freed space, moving the next close button out from
/// under the cursor. Call [holdWidthForClose] just before removing tabs: while
/// the strip is hovered it pins the survivors at their current width, and the
/// pin is released (the tabs animate back out) when the pointer leaves.
class DocumentTabStripController extends ChangeNotifier {
  DocumentTabStripController({this.metrics = const DocumentTabStripMetrics()});

  /// The strip's dimensions.
  final DocumentTabStripMetrics metrics;

  /// The tab list's horizontal scroll position.
  final ScrollController scrollController = ScrollController();

  bool _hovered = false;
  double _naturalTabWidth = 0;
  double _renderedTabWidth = 0;
  double _renderedTabsWidth = 0;
  double? _heldTabWidth;

  /// Whether the pointer is over the tab list.
  bool get isHovered => _hovered;

  /// The most recent natural (unheld) per-tab width.
  double get naturalTabWidth => _naturalTabWidth;

  /// The per-tab width of the most recent layout (held or natural).
  double get renderedTabWidth => _renderedTabWidth;

  /// The visible width of the tab list in the most recent layout.
  double get renderedTabsWidth => _renderedTabsWidth;

  /// The pinned per-tab width while a close streak holds it, else null.
  double? get heldTabWidth => _heldTabWidth;

  /// Pins the tabs at their current width when the strip is hovered. Call it
  /// just before removing tabs; the first close of a streak sets the width
  /// and later ones keep it.
  void holdWidthForClose() {
    if (_hovered && _naturalTabWidth > 0) _heldTabWidth ??= _naturalTabWidth;
  }

  /// Drops the hold immediately - a tab is arriving, so the others have to
  /// shrink to fit it anyway.
  void clearHold() {
    if (_heldTabWidth == null) return;
    _heldTabWidth = null;
    notifyListeners();
  }

  void _setHovered(bool hovered) {
    _hovered = hovered;
    if (!hovered) clearHold();
  }

  void _recordLayout({
    required double natural,
    required double rendered,
    required double tabsWidth,
  }) {
    _naturalTabWidth = natural;
    _renderedTabWidth = rendered;
    _renderedTabsWidth = tabsWidth;
  }

  /// The insertion slot (0..[tabCount]) for a point [visibleOffset] logical
  /// pixels from the strip's leading edge, from the most recent layout - where
  /// a tab dragged in from elsewhere would land. [externalGap] is the slot a
  /// gap is currently open at for that drag (see
  /// [DocumentTabStrip.externalGapIndex]); a point over the gap returns it.
  int insertionIndexAt(
    double visibleOffset,
    int tabCount, {
    int? externalGap,
  }) {
    if (tabCount == 0) return 0;
    if (_renderedTabWidth <= 0 || _renderedTabsWidth <= 0) return tabCount;
    if (visibleOffset < 0) return 0;
    if (visibleOffset > _renderedTabsWidth) return tabCount;
    final scrollOffset =
        scrollController.hasClients ? scrollController.offset : 0.0;
    var contentOffset = visibleOffset + scrollOffset - metrics.listPadding;
    if (externalGap != null) {
      final gapStart = externalGap * _renderedTabWidth;
      final gapEnd = gapStart + _renderedTabWidth;
      if (contentOffset >= gapStart && contentOffset <= gapEnd) {
        return externalGap;
      }
      if (contentOffset > gapEnd) contentOffset -= _renderedTabWidth;
    }
    return ((contentOffset / _renderedTabWidth) + 0.5)
        .floor()
        .clamp(0, tabCount)
        .toInt();
  }

  /// The leading-edge offset, within the visible strip, of insertion slot
  /// [index] - where a drop indicator for it is drawn.
  double insertionOffsetFor(int index) {
    final scroll = scrollController.hasClients ? scrollController.offset : 0.0;
    return (metrics.listPadding + index * _renderedTabWidth - scroll)
        .clamp(2.0, math.max(2.0, _renderedTabsWidth - 2))
        .toDouble();
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }
}

/// Wraps one tab's chrome - see [DocumentTabStrip.tabBuilder].
typedef DocumentTabBuilder<T> = Widget Function(
  BuildContext context,
  int index,
  T tab,
  Widget chrome,
);

/// A browser-style tab strip: Chrome-style equal-share tab widths, a
/// close-streak width hold, drag to reorder, middle-ellipsized titles with an
/// unsaved-changes dot, and trailing add / view-all buttons.
///
/// The strip holds no tab state of its own: it draws [tabs] with
/// [activeIndex] on screen and reports what the user does through the
/// callbacks. Its layout state lives in [controller].
class DocumentTabStrip<T extends Object> extends StatelessWidget {
  const DocumentTabStrip({
    super.key,
    required this.tabs,
    required this.activeIndex,
    required this.controller,
    required this.titleOf,
    required this.onActivate,
    required this.onClose,
    required this.onReorder,
    this.isDirtyOf,
    this.listenableOf,
    this.onContextMenu,
    this.onAdd,
    this.onShowAll,
    this.tabBuilder,
    this.labels = const DocumentTabsLabels(),
    this.hidePdfExtension = true,
    this.externalGapIndex,
    this.insertionIndex,
    this.activeTabColor,
    this.tabColor,
  });

  /// The open tabs in strip order.
  final List<T> tabs;

  /// The index of the tab on screen.
  final int activeIndex;

  final DocumentTabStripController controller;

  /// A tab's label; an empty title shows [DocumentTabsLabels.untitled].
  final String Function(T tab) titleOf;

  /// Whether a tab has unsaved changes (drawn as a dot before its title).
  final bool Function(T tab)? isDirtyOf;

  /// What to listen to for a tab's title or dirty state changing, if the
  /// strip should repaint that tab on its own.
  final Listenable? Function(T tab)? listenableOf;

  /// A tap on the tab at the index - including the active one, so a host can
  /// give that a meaning of its own (the DartPDF app renames on mobile).
  final ValueChanged<int> onActivate;

  /// The tab at the index's close button.
  final ValueChanged<int> onClose;

  /// A drag-reorder, with the new index already adjusted for the removed item
  /// (the `onReorderItem` convention, as [DocumentTabs.reorder] takes it).
  final void Function(int oldIndex, int newIndex) onReorder;

  /// A secondary click on the tab at the index, at a global position.
  final void Function(int index, Offset globalPosition)? onContextMenu;

  /// The add button; hidden when null.
  final VoidCallback? onAdd;

  /// The trailing view-all button; hidden when null.
  final VoidCallback? onShowAll;

  /// Wraps each tab's chrome, for a host that adds a hover preview, a
  /// cross-window drag source or a drag animation. Without one each tab is
  /// wrapped in a [DocumentTabDragStartListener]; a host that supplies one
  /// wraps the chrome in that listener itself wherever it wants local
  /// drag-reorder.
  final DocumentTabBuilder<T>? tabBuilder;

  final DocumentTabsLabels labels;

  /// Whether titles hide a trailing `.pdf` (see [MiddleEllipsisText]).
  final bool hidePdfExtension;

  /// Opens a tab-width gap at this slot, for a tab being dragged in from
  /// outside the strip.
  final int? externalGapIndex;

  /// Highlights the strip as a drop target and draws an insertion indicator
  /// at this slot.
  final int? insertionIndex;

  /// Fill of the active tab; defaults to the scheme's secondary container.
  final Color? activeTabColor;

  /// Fill of the inactive tabs; defaults to the scheme's highest surface
  /// container.
  final Color? tabColor;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => SizedBox(
        height: controller.metrics.height,
        child: LayoutBuilder(builder: _buildLayout),
      ),
    );
  }

  Widget _buildLayout(BuildContext context, BoxConstraints constraints) {
    final metrics = controller.metrics;
    final buttonWidth = metrics.buttonWidth;
    final controlsWidth = (onAdd == null ? 0 : buttonWidth) +
        (onShowAll == null ? 0 : buttonWidth);
    final listPadding = metrics.listPadding * 2;
    final maxTabsWidth = (constraints.maxWidth - controlsWidth)
        .clamp(0.0, double.infinity)
        .toDouble();

    final natural =
        metrics.tabWidthFor(maxTabsWidth - listPadding, tabs.length);
    // While a close streak is held, keep the surviving tabs at the pinned
    // width; otherwise use the natural share (never wider than natural, so a
    // stale hold can't overflow after a resize).
    final held = controller.heldTabWidth;
    final tabWidth = held == null ? natural : math.min(held, natural);
    final gap = externalGapIndex;
    final visualTabCount = tabs.length + (gap == null ? 0 : 1);
    final tabsWidth = tabs.isEmpty
        ? 0.0
        : math.min(tabWidth * visualTabCount + listPadding, maxTabsWidth);
    controller._recordLayout(
      natural: natural,
      rendered: tabWidth,
      tabsWidth: tabsWidth,
    );
    final scheme = Theme.of(context).colorScheme;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final gapPadding = gap == null ? 0.0 : tabWidth;
    final insertion = insertionIndex;

    return Stack(
      children: [
        Row(
          children: [
            if (tabsWidth > 0)
              // A resize can make the constraint narrower than the
              // container's previous animated width. Clamp outside the
              // animation so even its first frame fits the current Row.
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxTabsWidth),
                child: MouseRegion(
                  onEnter: (_) => controller._setHovered(true),
                  onExit: (_) => controller._setHovered(false),
                  // Grow back smoothly once the hold releases; the strip and
                  // each tab animate to the same width with a linear curve,
                  // so they stay pixel-consistent throughout.
                  child: AnimatedContainer(
                    duration: metrics.resizeDuration,
                    curve: Curves.linear,
                    width: tabsWidth,
                    child: ReorderableListView.builder(
                      key: const ValueKey('tab-strip'),
                      scrollController: controller.scrollController,
                      scrollDirection: Axis.horizontal,
                      // The whole tab is the drag handle; the stock trailing
                      // handles don't fit a horizontal strip.
                      buildDefaultDragHandles: false,
                      padding: EdgeInsets.only(
                        left: metrics.listPadding + (rtl ? gapPadding : 0),
                        right: metrics.listPadding + (rtl ? 0 : gapPadding),
                      ),
                      itemCount: tabs.length,
                      onReorderItem: onReorder,
                      itemBuilder: (context, i) =>
                          _buildTab(context, i, tabWidth),
                    ),
                  ),
                ),
              ),
            if (onAdd != null)
              SizedBox(
                width: buttonWidth,
                height: metrics.height,
                child: IconButton(
                  key: const ValueKey('desktop-tab-add-button'),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints.tightFor(width: buttonWidth),
                  icon: const Icon(Icons.add),
                  tooltip: labels.openTab,
                  onPressed: onAdd,
                ),
              ),
            const Spacer(key: ValueKey('desktop-tabs-spacer')),
            if (onShowAll != null)
              SizedBox(
                width: buttonWidth,
                height: metrics.height,
                child: IconButton(
                  key: const ValueKey('desktop-tabs-button'),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints.tightFor(width: buttonWidth),
                  icon: const Icon(Icons.grid_view),
                  tooltip: labels.viewAllTabs,
                  onPressed: onShowAll,
                ),
              ),
          ],
        ),
        if (insertion != null)
          PositionedDirectional(
            start: 0,
            width: tabsWidth > 0 ? tabsWidth : maxTabsWidth,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: DecoratedBox(
                key: const ValueKey('tab-drag-drop-highlight'),
                decoration: BoxDecoration(
                  color: scheme.primary.withAlpha(0x12),
                  border: Border.all(color: scheme.primary.withAlpha(0xB0)),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        if (insertion != null && tabsWidth > 0)
          PositionedDirectional(
            start: controller.insertionOffsetFor(insertion),
            top: 4,
            bottom: 4,
            child: IgnorePointer(
              child: Container(
                key: const ValueKey('tab-drag-insertion-indicator'),
                width: 3,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.shadow.withAlpha(0x50),
                      blurRadius: 3,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTab(BuildContext context, int index, double width) {
    final tab = tabs[index];
    final selected = index == activeIndex;
    final scheme = Theme.of(context).colorScheme;
    final metrics = controller.metrics;
    // Like Chrome, drop the close button on inactive tabs once they get
    // narrow so the label keeps room; the active tab always keeps it.
    final showClose = selected || width >= metrics.closeHideWidth;

    Widget label(BuildContext context) {
      final title = titleOf(tab);
      final text = MiddleEllipsisText(
        title.isEmpty ? labels.untitled : title,
        hidePdfExtension: hidePdfExtension && title.isNotEmpty,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          color:
              selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
        ),
      );
      if (!(isDirtyOf?.call(tab) ?? false)) return text;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 6),
            child: Icon(Icons.circle, size: 8, color: scheme.primary),
          ),
          Flexible(child: text),
        ],
      );
    }

    final listenable = listenableOf?.call(tab);
    final chrome = AnimatedContainer(
      duration: metrics.resizeDuration,
      curve: Curves.linear,
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
      child: Material(
        color: selected
            ? activeTabColor ?? scheme.secondaryContainer
            : tabColor ?? scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onActivate(index),
          onSecondaryTapUp: onContextMenu == null
              ? null
              : (details) => onContextMenu!(index, details.globalPosition),
          child: Padding(
            padding:
                EdgeInsetsDirectional.only(start: 12, end: showClose ? 2 : 12),
            child: Row(
              children: [
                Expanded(
                  child: listenable == null
                      ? label(context)
                      : ListenableBuilder(
                          listenable: listenable,
                          builder: (context, _) => label(context),
                        ),
                ),
                if (showClose)
                  IconButton(
                    key: ValueKey('tab-close-$index'),
                    icon: const Icon(Icons.close, size: 16),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 30, minHeight: 30),
                    tooltip: labels.closeTab,
                    onPressed: () => onClose(index),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    final builder = tabBuilder;
    return KeyedSubtree(
      key: ValueKey(tab),
      child: builder == null
          ? DocumentTabDragStartListener(index: index, child: chrome)
          : builder(context, index, tab, chrome),
    );
  }
}
