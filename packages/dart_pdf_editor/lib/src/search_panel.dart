import 'dart:async';

import 'package:flutter/material.dart';

import 'editing/editing_panel.dart';
import 'editing/editing_preferences.dart';
import 'pdf_viewer.dart';
import 'scrollbar.dart';
import 'theme.dart';

/// A compact document-search field: a slim text box with the match
/// count, previous/next, and clear riding alongside — small enough for
/// an app bar.
///
/// Searches as you type (debounced) and on enter; once a query is live,
/// pressing enter again steps to the next match (browser-style). Pair it
/// with a [PdfSearchResultsPanel] listing every hit.
class PdfSearchField extends StatefulWidget {
  const PdfSearchField({
    super.key,
    required this.controller,
    this.width = 200,
    this.searchController,
    this.focusNode,
    this.hintText = 'Search',
  });

  final PdfViewerController controller;

  /// The text box's width; the count and the stepper buttons sit
  /// outside it, appearing only while a query is live.
  final double width;

  /// Optional external text controller — pass one to clear or prefill
  /// the field from the host (e.g. when a new document opens).
  final TextEditingController? searchController;

  /// Optional focus node, for a host-level ⌘F shortcut.
  final FocusNode? focusNode;

  final String hintText;

  @override
  State<PdfSearchField> createState() => _PdfSearchFieldState();
}

class _PdfSearchFieldState extends State<PdfSearchField> {
  TextEditingController? _ownField;
  Timer? _debounce;

  TextEditingController get _field =>
      widget.searchController ?? (_ownField ??= TextEditingController());

  @override
  void dispose() {
    _debounce?.cancel();
    _ownField?.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    // clearing is instant; typing searches after a quiet moment
    if (text.isEmpty) {
      widget.controller.clearSearch();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) unawaited(widget.controller.search(text));
    });
  }

  void _onSubmitted(String text) {
    _debounce?.cancel();
    final controller = widget.controller;
    // Browser-style: the first enter searches; once the query is live
    // (already searched, with hits), each subsequent enter steps to the
    // next match. A changed query searches afresh.
    if (text == controller.query &&
        !controller.isSearching &&
        controller.matchCount > 0) {
      controller.nextMatch();
    } else {
      unawaited(controller.search(text));
    }
  }

  void _clear() {
    _debounce?.cancel();
    _field.clear();
    widget.controller.clearSearch();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final hasQuery = controller.query.isNotEmpty;
        return Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: widget.width,
            child: TextField(
              key: const ValueKey('pdf-search-field'),
              controller: _field,
              focusNode: widget.focusNode,
              decoration: InputDecoration(
                hintText: widget.hintText,
                prefixIcon: const Icon(Icons.search, size: 18),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 32, minHeight: 32),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                suffixIcon: controller.isSearching
                    ? const Padding(
                        padding: EdgeInsets.all(8),
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : hasQuery
                        ? IconButton(
                            key: const ValueKey('pdf-search-clear'),
                            icon: const Icon(Icons.close, size: 16),
                            tooltip: 'Clear search',
                            visualDensity: VisualDensity.compact,
                            onPressed: _clear,
                          )
                        : null,
                suffixIconConstraints:
                    const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              textInputAction: TextInputAction.search,
              // The search action unfocuses the field by default; keep
              // focus so a second enter reaches onSubmitted and steps to
              // the next match instead of dismissing the field.
              onEditingComplete: () {},
              onChanged: _onChanged,
              onSubmitted: _onSubmitted,
            ),
          ),
          if (hasQuery && !controller.isSearching) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                controller.matchCount == 0
                    ? '0/0'
                    : '${controller.currentMatch + 1}/'
                        '${controller.matchCount}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            IconButton(
              key: const ValueKey('pdf-search-prev'),
              icon: const Icon(Icons.keyboard_arrow_up),
              tooltip: 'Previous match',
              visualDensity: VisualDensity.compact,
              onPressed:
                  controller.matchCount == 0 ? null : controller.previousMatch,
            ),
            IconButton(
              key: const ValueKey('pdf-search-next'),
              icon: const Icon(Icons.keyboard_arrow_down),
              tooltip: 'Next match',
              visualDensity: VisualDensity.compact,
              onPressed:
                  controller.matchCount == 0 ? null : controller.nextMatch,
            ),
          ],
        ]);
      },
    );
  }
}

/// One list entry: a page header or an index into the results.
typedef _Entry = ({int? header, int? result});

/// A side panel listing every search hit with its surrounding text,
/// grouped by page — tap one to jump there.
///
/// Reads [PdfViewerController.searchResults]; the current match is
/// highlighted and taps go through [PdfViewerController.goToMatch].
/// The inner edge is draggable ([resizable]); with [preferences] the
/// chosen width persists ([PdfEditingPreferences.searchPanelWidth]).
class PdfSearchResultsPanel extends StatefulWidget {
  const PdfSearchResultsPanel({
    super.key,
    required this.controller,
    this.preferences,
    this.width = 280,
    this.side = PdfSidebarSide.left,
    this.resizable = true,
    this.minWidth = 200,
    this.maxWidth = 480,
    this.bottomSheet = false,
  });

  final PdfViewerController controller;

  /// Persists the user-dragged width when provided.
  final PdfEditingPreferences? preferences;

  /// The default width — a persisted user-dragged width wins over it.
  final double width;

  /// Which side of the viewer the panel sits on; the resize grip rides
  /// the opposite (inner) edge.
  final PdfSidebarSide side;

  /// Whether the inner edge can be dragged to resize the panel.
  final bool resizable;

  /// Clamps for the dragged width.
  final double minWidth;
  final double maxWidth;

  /// Lays the panel out to fill its parent (full width, no side resize
  /// grip) for hosting inside a bottom sheet on a small screen, rather
  /// than as a fixed-width docked column.
  final bool bottomSheet;

  @override
  State<PdfSearchResultsPanel> createState() => _PdfSearchResultsPanelState();
}

class _PdfSearchResultsPanelState extends State<PdfSearchResultsPanel> {
  final ScrollController _scroll = ScrollController();
  double? _dragWidth;

  double get _width =>
      (_dragWidth ?? widget.preferences?.searchPanelWidth ?? widget.width)
          .clamp(widget.minWidth, widget.maxWidth);

  @override
  void initState() {
    super.initState();
    widget.preferences?.addListener(_onPreferences);
  }

  @override
  void didUpdateWidget(PdfSearchResultsPanel old) {
    super.didUpdateWidget(old);
    if (!identical(old.preferences, widget.preferences)) {
      old.preferences?.removeListener(_onPreferences);
      widget.preferences?.addListener(_onPreferences);
    }
  }

  @override
  void dispose() {
    widget.preferences?.removeListener(_onPreferences);
    _scroll.dispose();
    super.dispose();
  }

  void _onPreferences() {
    if (mounted) setState(() {});
  }

  void _onResizeDelta(double delta) => setState(() {
        _dragWidth = (_width + delta).clamp(widget.minWidth, widget.maxWidth);
      });

  void _onResizeEnd() {
    final preferences = widget.preferences;
    if (preferences == null || _dragWidth == null) return;
    // without preferences the dragged width simply stays in _dragWidth
    preferences.searchPanelWidth = _dragWidth;
    setState(() => _dragWidth = null);
  }

  Widget _hint(String message) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(message, textAlign: TextAlign.center),
        ),
      );

  Widget _resultTile(BuildContext context, int index, PdfSearchResult result) {
    final scheme = Theme.of(context).colorScheme;
    final highlight =
        PdfViewerTheme.of(context).searchMatchColor ?? const Color(0x66FFEB3B);
    final style = Theme.of(context).textTheme.bodySmall;
    return ListTile(
      key: ValueKey('pdf-search-result-$index'),
      dense: true,
      selected: index == widget.controller.currentMatch,
      selectedTileColor: scheme.secondaryContainer,
      selectedColor: scheme.onSecondaryContainer,
      title: Text.rich(
        TextSpan(children: [
          TextSpan(text: result.prefix),
          TextSpan(
            text: result.matchText,
            style: TextStyle(
                fontWeight: FontWeight.bold, backgroundColor: highlight),
          ),
          TextSpan(text: result.suffix),
        ]),
        style: style,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => widget.controller.goToMatch(index),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final showGrip = widget.resizable && !widget.bottomSheet;
    final onLeftEdge = !widget.bottomSheet && widget.side == PdfSidebarSide.left;
    final content = Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) {
                if (controller.query.isEmpty) {
                  return _hint('Search the document to list every match here');
                }
                if (controller.isSearching) {
                  return const Center(child: CircularProgressIndicator());
                }
                final results = controller.searchResults;
                if (results.isEmpty) {
                  return _hint('No matches for “${controller.query}”');
                }
                final entries = <_Entry>[];
                int? page;
                for (var i = 0; i < results.length; i++) {
                  if (results[i].pageIndex != page) {
                    page = results[i].pageIndex;
                    entries.add((header: page, result: null));
                  }
                  entries.add((header: null, result: i));
                }
                final barClearance = PdfScrollbar.hitExtent +
                    (showGrip && onLeftEdge ? PdfSidebarResizeGrip.width : 0);
                final textTheme = Theme.of(context).textTheme;
                return Stack(children: [
                  Column(children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Row(children: [
                        Expanded(
                          child: Text(
                            results.length == 1
                                ? '1 match'
                                : '${results.length} matches',
                            style: textTheme.labelLarge,
                          ),
                        ),
                      ]),
                    ),
                    Expanded(
                      child: ScrollConfiguration(
                        behavior: ScrollConfiguration.of(context)
                            .copyWith(scrollbars: false),
                        child: ListView.builder(
                          key: const ValueKey('pdf-search-results-list'),
                          controller: _scroll,
                          padding:
                              EdgeInsets.only(right: barClearance, bottom: 8),
                          itemCount: entries.length,
                          itemBuilder: (context, index) {
                            final entry = entries[index];
                            if (entry.header != null) {
                              return Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 10, 16, 2),
                                child: Text('Page ${entry.header! + 1}',
                                    style: textTheme.labelMedium?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary)),
                              );
                            }
                            return _resultTile(
                                context, entry.result!, results[entry.result!]);
                          },
                        ),
                      ),
                    ),
                  ]),
                  Positioned(
                    top: 0,
                    bottom: 0,
                    right:
                        showGrip && onLeftEdge ? PdfSidebarResizeGrip.width : 0,
                    child: PdfScrollbar(
                      scroll: _scroll,
                      thumbKey: const ValueKey('pdf-search-scrollbar-thumb'),
                    ),
                  ),
                ]);
              },
            ),
          );
    if (widget.bottomSheet) return content;
    return SizedBox(
      width: _width,
      child: Stack(children: [
        Positioned.fill(child: content),
        if (showGrip)
          Positioned(
            top: 0,
            bottom: 0,
            left: widget.side == PdfSidebarSide.right ? 0 : null,
            right: widget.side == PdfSidebarSide.left ? 0 : null,
            child: PdfSidebarResizeGrip(
              key: const ValueKey('pdf-search-resize-grip'),
              side: widget.side,
              onWidthDelta: _onResizeDelta,
              onResizeEnd: _onResizeEnd,
            ),
          ),
      ]),
    );
  }
}
