import 'dart:async';

import 'package:flutter/material.dart';

import 'editing/editing_controller.dart';
import 'editing/editing_fonts.dart';
import 'editing/editing_panel.dart';
import 'editing/editing_preferences.dart';
import 'l10n/pdf_l10n.dart';
import 'pdf_viewer.dart';
import 'theme.dart';
import 'toast.dart';

/// A compact document-search field: a slim text box with the match
/// count, previous/next, and clear riding alongside - small enough for
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
    this.showOptions = true,
    this.preferences,
  });

  final PdfViewerController controller;

  /// The text box's width; the count and the stepper buttons sit
  /// outside it, appearing only while a query is live.
  final double width;

  /// Whether to show the match-case / whole-word / regex toggle buttons
  /// beside the field. They drive [PdfViewerController.searchOptions].
  final bool showOptions;

  /// When given, the match-case / whole-word / regex toggles persist to
  /// (and seed from) these preferences, so they survive across sessions.
  final PdfEditingPreferences? preferences;

  /// Optional external text controller - pass one to clear or prefill
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
                            tooltip: pdfL10n(context).searchClearSearch,
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
          if (widget.showOptions)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 4),
              child: _SearchOptionsBar(
                  controller: controller, preferences: widget.preferences),
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
              tooltip: pdfL10n(context).searchPreviousMatch,
              visualDensity: VisualDensity.compact,
              onPressed:
                  controller.matchCount == 0 ? null : controller.previousMatch,
            ),
            IconButton(
              key: const ValueKey('pdf-search-next'),
              icon: const Icon(Icons.keyboard_arrow_down),
              tooltip: pdfL10n(context).searchNextMatch,
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
/// grouped by page - tap one to jump there.
///
/// Reads [PdfViewerController.searchResults]; the current match is
/// highlighted and taps go through [PdfViewerController.goToMatch].
/// The inner edge is draggable ([resizable]); with [preferences] the
/// chosen width persists ([PdfEditingPreferences.searchPanelWidth]).
///
/// Pass [editing] to turn the panel into find *and replace*: a replacement
/// field appears under the options bar with "Replace" (the current match
/// alone) and "Replace all" (every hit, one undo step).
class PdfSearchResultsPanel extends StatefulWidget {
  const PdfSearchResultsPanel({
    super.key,
    required this.controller,
    this.editing,
    this.preferences,
    this.width = 280,
    this.dock = PdfPanelDock.left,
    this.resizable = true,
    this.minWidth = 200,
    this.maxWidth = 480,
    this.bottomSheet = false,
    this.showOptions = true,
    this.onClose,
  });

  final PdfViewerController controller;

  /// The edit session that backs the replace controls. Null (the default)
  /// leaves the panel a pure find panel - which is what a read-only viewer
  /// wants.
  final PdfEditingController? editing;

  /// Persists the user-dragged width when provided.
  final PdfEditingPreferences? preferences;

  /// Whether the panel shows the match-case / whole-word / regex toggle
  /// controls in its header. They drive [PdfViewerController.searchOptions].
  final bool showOptions;

  /// The default width - a persisted user-dragged width wins over it.
  final double width;

  /// Which edge of the viewer the panel docks on; the resize grip rides
  /// the opposite (inner) edge.
  final PdfPanelDock dock;

  /// Whether the inner edge can be dragged to resize the panel.
  final bool resizable;

  /// Clamps for the dragged width.
  final double minWidth;
  final double maxWidth;

  /// Lays the panel out to fill its parent (full width, no side resize
  /// grip) for hosting inside a bottom sheet on a small screen, rather
  /// than as a fixed-width docked column.
  final bool bottomSheet;

  /// Closes the docked panel - the host turns its visibility preference
  /// off. When given (and not a [bottomSheet]) a close (×) button appears
  /// in the panel's header. Null leaves the panel with no close button (a
  /// bottom sheet supplies its own).
  final VoidCallback? onClose;

  @override
  State<PdfSearchResultsPanel> createState() => _PdfSearchResultsPanelState();
}

class _PdfSearchResultsPanelState extends State<PdfSearchResultsPanel> {
  final ScrollController _scroll = ScrollController();

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
      // Annotation hits (note bodies, comments, free text) carry a small
      // comment glyph so they read apart from page-text hits in the list.
      leading: result.isAnnotation
          ? Icon(Icons.comment_outlined,
              size: 16, color: scheme.onSurfaceVariant)
          : null,
      horizontalTitleGap: result.isAnnotation ? 8 : null,
      minLeadingWidth: result.isAnnotation ? 16 : null,
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

  /// The state-dependent body below the options bar: a hint, the spinner,
  /// the "no matches" line, or the grouped results list with its scrollbar.
  Widget _body(
    BuildContext context, {
    required PdfSidebarPanelGeometry geometry,
  }) {
    final controller = widget.controller;
    if (controller.query.isEmpty) {
      return _hint(pdfL10n(context).searchEmptyHint);
    }
    if (controller.isSearching) {
      return const Center(child: CircularProgressIndicator());
    }
    final results = controller.searchResults;
    if (results.isEmpty) {
      return _hint(pdfL10n(context).searchNoMatches(controller.query));
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
    final textTheme = Theme.of(context).textTheme;
    return geometry.withScrollbar(
      scroll: _scroll,
      thumbKey: const ValueKey('pdf-search-scrollbar-thumb'),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(children: [
            Expanded(
              child: Text(
                pdfL10n(context).searchMatchCount(results.length),
                style: textTheme.labelLarge,
              ),
            ),
          ]),
        ),
        Expanded(
          child: ScrollConfiguration(
            behavior:
                ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: ListView.builder(
              key: const ValueKey('pdf-search-results-list'),
              controller: _scroll,
              padding: EdgeInsets.only(
                  right: geometry.scrollbarClearance, bottom: 8),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                if (entry.header != null) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                    child: Text(
                        pdfL10n(context).searchPageHeader(entry.header! + 1),
                        style: textTheme.labelMedium?.copyWith(
                            color: Theme.of(context).colorScheme.primary)),
                  );
                }
                return _resultTile(
                    context, entry.result!, results[entry.result!]);
              },
            ),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return PdfSidebarPanelFrame(
      width: widget.width,
      minWidth: widget.minWidth,
      maxWidth: widget.maxWidth,
      persistedWidth: widget.preferences?.searchPanelWidth,
      onPersistWidth: widget.preferences == null
          ? null
          : (width) => widget.preferences!.searchPanelWidth = width,
      dock: widget.dock,
      panel: PdfDockablePanel.search,
      resizable: widget.resizable,
      bottomSheet: widget.bottomSheet,
      gripKey: const ValueKey('pdf-search-resize-grip'),
      onClose: widget.onClose,
      builder: (context, geometry) {
        final moveHandle = geometry.moveHandle(
          key: const ValueKey('pdf-search-panel-move'),
        );
        final closeButton = geometry.closeButton(
          key: const ValueKey('pdf-search-panel-close'),
        );
        return Material(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => Column(children: [
              // the drag-to-redock handle and the docked panel's close
              // button; a bottom sheet supplies its own in its sheet chrome
              if (moveHandle != null || closeButton != null)
                Padding(
                  // clear the right-edge resize grip when it rides this side
                  padding: EdgeInsets.fromLTRB(
                      16, 4, geometry.contentEndInset + 4, 0),
                  child: Row(children: [
                    Expanded(
                      child: Text(pdfL10n(context).searchResultsTitle,
                          style: Theme.of(context).textTheme.titleSmall),
                    ),
                    if (moveHandle != null) moveHandle,
                    if (closeButton != null) closeButton,
                  ]),
                ),
              if (widget.showOptions) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: _SearchOptionsBar(
                        controller: controller,
                        preferences: widget.preferences),
                  ),
                ),
                Divider(
                  height: 1,
                  indent: geometry.contentStartInset,
                  endIndent: geometry.contentEndInset,
                ),
              ],
              if (widget.editing != null) ...[
                _ReplaceBar(
                  controller: controller,
                  editing: widget.editing!,
                ),
                Divider(
                  height: 1,
                  indent: geometry.contentStartInset,
                  endIndent: geometry.contentEndInset,
                ),
              ],
              Expanded(child: _body(context, geometry: geometry)),
            ]),
          ),
        );
      },
    );
  }
}

/// The find-and-replace row under the search panel's options bar: a
/// replacement field plus "Replace" (the current match alone) and "Replace
/// all" (every hit).
///
/// "Replace" goes through [PdfEditingController.replaceMatchText], which
/// pins the hit to exactly one content run or declines - so it can never
/// silently rewrite the other place on the page that happens to read the
/// same. "Replace all" is the page-wide form, because that is what the user
/// asked for, and lands as a single undo step.
class _ReplaceBar extends StatefulWidget {
  const _ReplaceBar({required this.controller, required this.editing});

  final PdfViewerController controller;
  final PdfEditingController editing;

  @override
  State<_ReplaceBar> createState() => _ReplaceBarState();
}

class _ReplaceBarState extends State<_ReplaceBar> {
  final TextEditingController _field = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _toast(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: pdfFloatingToastMargin(context),
        duration: const Duration(seconds: 4),
        action: widget.editing.canUndo
            ? SnackBarAction(
                label: pdfL10n(context).undo, onPressed: widget.editing.undo)
            : null,
      ));
  }

  /// Re-runs the live query against the rewritten document: the hits the
  /// panel is listing were measured against the previous revision, and their
  /// offsets no longer mean anything once a run has been re-typed.
  ///
  /// Ordering matters. The viewer swaps in the new revision during the next
  /// frame and clears the search as it does, so a re-search issued straight
  /// after the edit is discarded a moment later and the panel goes blank.
  /// Waiting for that frame lets the fresh results survive.
  Future<void> _refresh(String query) async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await widget.controller
        .search(query, options: widget.controller.searchOptions);
  }

  Future<void> _replaceOne() async {
    final controller = widget.controller;
    final results = controller.searchResults;
    final index = controller.currentMatch;
    if (index < 0 || index >= results.length) return;
    final result = results[index];
    final query = controller.query;
    final l10n = pdfL10n(context);

    setState(() => _busy = true);
    try {
      final fallbacks = await loadFallbackFonts();
      final count = widget.editing.replaceMatchText(
        result.pageIndex,
        result.match.rects,
        result.matchText,
        _field.text,
        fallbackFonts: fallbacks,
      );
      if (!mounted) return;
      _toast(count == 0 ? l10n.searchReplaceNotTargetable : l10n.searchReplaced(count));
      if (count > 0) await _refresh(query);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _replaceAll() async {
    final controller = widget.controller;
    final query = controller.query;
    final pages = {for (final r in controller.searchResults) r.pageIndex};
    if (pages.isEmpty) return;
    final l10n = pdfL10n(context);

    setState(() => _busy = true);
    try {
      final fallbacks = await loadFallbackFonts();
      final count = widget.editing.replaceTextOnPages(
        pages,
        query,
        _field.text,
        fallbackFonts: fallbacks,
      );
      if (!mounted) return;
      _toast(l10n.searchReplaced(count));
      if (count > 0) await _refresh(query);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final l10n = pdfL10n(context);
    // an annotation hit lives in a /Contents string, not the page's content
    // stream, so the content editor has nothing to rewrite for it
    final results = controller.searchResults;
    final current = controller.currentMatch >= 0 &&
            controller.currentMatch < results.length
        ? results[controller.currentMatch]
        : null;
    final ready = !_busy &&
        !controller.isSearching &&
        controller.query.isNotEmpty &&
        results.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('pdf-search-replace-field'),
            controller: _field,
            enabled: !_busy,
            decoration: InputDecoration(
              hintText: l10n.searchReplaceHint,
              prefixIcon: const Icon(Icons.find_replace, size: 18),
              isDense: true,
              border: const OutlineInputBorder(),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
            style: Theme.of(context).textTheme.bodySmall,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('pdf-search-replace-one'),
                onPressed: ready && current != null && !current.isAnnotation
                    ? _replaceOne
                    : null,
                child: Text(l10n.searchReplace,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.tonal(
                key: const ValueKey('pdf-search-replace-all'),
                onPressed: ready ? _replaceAll : null,
                child: Text(l10n.searchReplaceAll,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

/// A compact row of toggle buttons for the search match options - case
/// sensitivity, whole word, and regular expression - driving
/// [PdfViewerController.searchOptions]. Shared by [PdfSearchField] and
/// [PdfSearchResultsPanel].
///
/// With [preferences] the toggles persist: the bar seeds the controller
/// from the stored values once they load, and a toggle writes back.
class _SearchOptionsBar extends StatefulWidget {
  const _SearchOptionsBar({required this.controller, this.preferences});

  final PdfViewerController controller;
  final PdfEditingPreferences? preferences;

  @override
  State<_SearchOptionsBar> createState() => _SearchOptionsBarState();
}

class _SearchOptionsBarState extends State<_SearchOptionsBar> {
  @override
  void initState() {
    super.initState();
    // Seed the controller from the stored options once they have loaded.
    // ready completes after the frame, so setSearchOptions runs outside any
    // build; the prefs' own _modified guard means a programmatic change
    // before load still wins.
    final prefs = widget.preferences;
    if (prefs != null) {
      prefs.ready.then((_) {
        if (!mounted) return;
        final p = widget.preferences;
        if (p == null) return;
        widget.controller.setSearchOptions(PdfSearchOptions(
          matchCase: p.searchMatchCase,
          wholeWord: p.searchWholeWord,
          regex: p.searchRegex,
          searchAnnotations: p.searchAnnotations,
        ));
      });
    }
  }

  void _apply(PdfSearchOptions next) {
    widget.controller.setSearchOptions(next);
    final prefs = widget.preferences;
    if (prefs != null) {
      prefs
        ..searchMatchCase = next.matchCase
        ..searchWholeWord = next.wholeWord
        ..searchRegex = next.regex
        ..searchAnnotations = next.searchAnnotations;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final options = widget.controller.searchOptions;

    Widget toggle({
      required String keyName,
      String? glyph,
      IconData? iconData,
      required String tooltip,
      required bool selected,
      required PdfSearchOptions next,
    }) =>
        IconButton(
          key: ValueKey(keyName),
          tooltip: tooltip,
          isSelected: selected,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          style: IconButton.styleFrom(
            backgroundColor: selected ? scheme.secondaryContainer : null,
            foregroundColor: selected
                ? scheme.onSecondaryContainer
                : scheme.onSurfaceVariant,
          ),
          onPressed: () => _apply(next),
          icon: iconData != null
              ? Icon(iconData, size: 16)
              : Text(
                  glyph!,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, height: 1),
                ),
        );

    return Row(mainAxisSize: MainAxisSize.min, children: [
      toggle(
        keyName: 'pdf-search-match-case',
        glyph: 'Aa',
        tooltip: pdfL10n(context).searchMatchCase,
        selected: options.matchCase,
        next: options.copyWith(matchCase: !options.matchCase),
      ),
      toggle(
        keyName: 'pdf-search-whole-word',
        glyph: 'W',
        tooltip: pdfL10n(context).searchWholeWord,
        selected: options.wholeWord,
        next: options.copyWith(wholeWord: !options.wholeWord),
      ),
      toggle(
        keyName: 'pdf-search-regex',
        glyph: '.*',
        tooltip: pdfL10n(context).searchRegex,
        selected: options.regex,
        next: options.copyWith(regex: !options.regex),
      ),
      toggle(
        keyName: 'pdf-search-annotations',
        iconData: Icons.comment_outlined,
        tooltip: pdfL10n(context).searchAnnotations,
        selected: options.searchAnnotations,
        next: options.copyWith(searchAnnotations: !options.searchAnnotations),
      ),
    ]);
  }
}
