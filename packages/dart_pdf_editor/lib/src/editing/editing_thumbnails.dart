import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../page_range_dialog.dart';
import '../pdf_viewer.dart';
import '../render_worker.dart';
import '../renderer.dart';
import '../scrollbar.dart';
import '../toast.dart';
import 'editing_controller.dart';
import 'editing_panel.dart';
import 'editing_preferences.dart';

/// A panel of page thumbnails: tap one to jump there, drag a tile up or
/// down to reorder pages (with a mouse just drag; on touch, long-press
/// first so the list still scrolls), the per-tile button deletes a page
/// (the last remaining page cannot be deleted), and the strip's footer
/// appends a blank page. All of this needs [allowPageEditing].
///
/// Built to stay light on large documents: thumbnails are rasterized at
/// tile resolution and cached, keyed by
/// [PdfEditingController.pageRenderStamp] — so an edit re-renders only
/// the pages it touched, renders are serialized (one page at a time)
/// instead of bursting on first layout, and scrolling the viewer
/// repaints only each tile's viewport indicator, never the page images.
///
/// The strip follows the viewer ([followsViewer]): when the current page
/// changes — scrolling, search, a link jump — the strip scrolls its tile
/// into view. The inner edge is draggable ([resizable]); the chosen
/// width persists via [PdfEditingPreferences.thumbnailSidebarWidth].
///
/// Place it beside the viewer, typically in a [Row]:
///
/// ```dart
/// Row(children: [
///   PdfThumbnailSidebar(
///     controller: editing,
///     viewerController: viewerController,
///   ),
///   Expanded(child: PdfViewer(...)),
/// ])
/// ```
class PdfThumbnailSidebar extends StatefulWidget {
  const PdfThumbnailSidebar({
    super.key,
    required this.controller,
    required this.viewerController,
    this.width = 160,
    this.pageColor = const Color(0xFFFFFFFF),
    this.showAnnotations = true,
    this.side = PdfSidebarSide.left,
    this.resizable = true,
    this.minWidth = 100,
    this.maxWidth = 400,
    this.followsViewer = true,
    this.allowPageEditing = true,
    this.bottomSheet = false,
    this.onPickPdfToInsert,
    this.onExportPages,
    this.renderWorker,
  });

  final PdfEditingController controller;

  /// Offloads tile interpretation to a background isolate (see
  /// [PdfViewer.renderWorker]) so rasterizing thumbnails of heavy pages
  /// doesn't block the UI thread. Pass the same worker the viewer uses.
  final PdfRenderWorker? renderWorker;

  /// The viewer to navigate when a thumbnail is tapped.
  final PdfViewerController viewerController;

  /// The default width — a user-dragged width, persisted in
  /// [PdfEditingPreferences.thumbnailSidebarWidth], wins over it.
  final double width;

  /// The paper color thumbnails render on — pass the viewer's
  /// [PdfViewer.pageColor] so they match the pages.
  final Color pageColor;

  /// Whether thumbnails render their annotations — pass the viewer's
  /// [PdfViewer.showAnnotations] so they match the pages.
  final bool showAnnotations;

  /// Which side of the viewer the panel sits on; the resize grip rides
  /// the opposite (inner) edge.
  final PdfSidebarSide side;

  /// Whether the inner edge can be dragged to resize the panel.
  final bool resizable;

  /// Clamps for the dragged width.
  final double minWidth;
  final double maxWidth;

  /// Whether the strip scrolls the current page's tile into view when
  /// the viewer's page changes.
  final bool followsViewer;

  /// Whether pages can be reordered (drag) and deleted (footer button)
  /// from the strip. False makes it purely navigational — the mode a
  /// read-only viewer wants.
  final bool allowPageEditing;

  /// Lays the strip out to fill its parent (full width, no side resize
  /// grip) for hosting inside a bottom sheet on a small screen, rather
  /// than as a fixed-width docked column.
  final bool bottomSheet;

  /// Picks a PDF to insert and returns its bytes (null = cancelled). When
  /// given, a "Insert PDF…" entry appears in the strip's page-actions
  /// footer menu and merges all of the picked file's pages in after the
  /// current page. Needs the host for file I/O.
  final Future<Uint8List?> Function()? onPickPdfToInsert;

  /// Receives the bytes of an exported page range, for the host to save.
  /// When given, an "Export pages…" entry appears in the page-actions
  /// footer menu.
  final void Function(Uint8List bytes)? onExportPages;

  /// How many thumbnails have actually been rasterized — cache misses
  /// only, across all sidebars. Tests assert on the deltas.
  @visibleForTesting
  static int debugRasterizations = 0;

  @override
  State<PdfThumbnailSidebar> createState() => _PdfThumbnailSidebarState();
}

class _PdfThumbnailSidebarState extends State<PdfThumbnailSidebar> {
  final ScrollController _scroll = ScrollController();
  final _ThumbnailCache _cache = _ThumbnailCache();

  /// Per-slot keys so [_revealPage] can [Scrollable.ensureVisible] a
  /// built tile.
  final Map<int, GlobalKey> _tileKeys = {};

  /// The panel width while a resize drag is in flight, overriding the
  /// preference until the drag ends and persists it.
  double? _dragWidth;

  int _lastCurrent = 0;

  PdfEditingPreferences get _preferences => widget.controller.preferences;

  double get _width =>
      (_dragWidth ?? _preferences.thumbnailSidebarWidth ?? widget.width)
          .clamp(widget.minWidth, widget.maxWidth);

  /// The scrollbar (and, when it rides the same right edge, the resize
  /// grip) overlay the list — the list keeps clear of that zone so the
  /// bar never covers a tile. Tiles already pad 12px on their own.
  double get _barClearance =>
      PdfScrollbar.hitExtent +
      (widget.resizable &&
              !widget.bottomSheet &&
              widget.side == PdfSidebarSide.left
          ? PdfSidebarResizeGrip.width
          : 0);

  double get _extraRightPadding => math.max(0, _barClearance - 12);

  /// The width a tile's thumbnail actually lays out at: panel width less
  /// the tile's 12px side paddings, the 1px borders, and the scrollbar
  /// clearance.
  double get _tileWidth => _width - 26 - _extraRightPadding;

  @override
  void initState() {
    super.initState();
    _lastCurrent = widget.viewerController.currentPage;
    widget.viewerController.addListener(_onViewerChanged);
    _preferences.addListener(_onPreferences);
  }

  @override
  void didUpdateWidget(PdfThumbnailSidebar old) {
    super.didUpdateWidget(old);
    if (!identical(old.viewerController, widget.viewerController)) {
      old.viewerController.removeListener(_onViewerChanged);
      widget.viewerController.addListener(_onViewerChanged);
      _lastCurrent = widget.viewerController.currentPage;
    }
    if (!identical(old.controller.preferences, _preferences)) {
      old.controller.preferences.removeListener(_onPreferences);
      _preferences.addListener(_onPreferences);
    }
    // a different edit session: its render stamps restart at zero, so
    // cached rasters keyed by the old session's stamps would collide
    if (!identical(old.controller, widget.controller)) _cache.clear();
  }

  @override
  void dispose() {
    widget.viewerController.removeListener(_onViewerChanged);
    _preferences.removeListener(_onPreferences);
    _scroll.dispose();
    _cache.dispose();
    super.dispose();
  }

  void _onPreferences() {
    if (mounted) setState(() {});
  }

  void _onViewerChanged() {
    final current = widget.viewerController.currentPage;
    if (current == _lastCurrent) return;
    _lastCurrent = current;
    if (widget.followsViewer) _revealPage(current);
  }

  /// Scrolls the strip the minimal distance that makes [index]'s tile
  /// fully visible. Unbuilt tiles get a jump to an estimated offset
  /// first; the post-frame pass fine-tunes against the real layout.
  void _revealPage(int index) {
    if (_ensureTileVisible(index)) return;
    if (!_scroll.hasClients) return;
    _scroll.jumpTo(
        _estimateOffset(index).clamp(0.0, _scroll.position.maxScrollExtent));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ensureTileVisible(index);
    });
  }

  bool _ensureTileVisible(int index) {
    final context = _tileKeys[index]?.currentContext;
    if (context == null) return false;
    // the two policies each no-op unless the tile is hidden past their
    // edge — together they scroll the minimal distance
    for (final policy in const [
      ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      ScrollPositionAlignmentPolicy.keepVisibleAtStart,
    ]) {
      unawaited(Scrollable.ensureVisible(context,
          alignmentPolicy: policy,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic));
    }
    return true;
  }

  /// The list offset where [index]'s tile roughly starts, from the same
  /// layout math the tiles use (12px side padding, 1px border, 4px
  /// vertical padding, ~28px footer row).
  double _estimateOffset(int index) {
    final thumbWidth = _tileWidth;
    var offset = 8.0; // the list's top padding
    for (var i = 0; i < index; i++) {
      final size = PdfPageRenderer.pageSize(widget.controller.pageAt(i));
      offset += 8 + 28 + 2 + thumbWidth * size.height / size.width;
    }
    return offset;
  }

  void _onResizeDelta(double delta) => setState(() {
        _dragWidth = (_width + delta).clamp(widget.minWidth, widget.maxWidth);
      });

  void _onResizeEnd() {
    if (_dragWidth == null) return;
    _preferences.thumbnailSidebarWidth = _dragWidth;
    setState(() => _dragWidth = null);
  }

  @override
  Widget build(BuildContext context) {
    final width = _width;
    final controller = widget.controller;
    // a bottom sheet supplies its own width and resize affordance, so the
    // strip drops the side resize grip; the tile column keeps its preferred
    // width, centered in the wider sheet rather than stretched
    final showGrip = widget.resizable && !widget.bottomSheet;
    // [inset] centers the tile column inside a full-width parent: in a
    // bottom sheet the list fills the whole sheet (so a drag anywhere in
    // it scrolls — not just over the narrow tile column) and the inset is
    // baked into the list's own horizontal padding, which keeps the
    // scroll viewport full-width while the tiles stay centered.
    Widget buildList(double inset) => Material(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          // only document changes rebuild the list — viewer scrolling
          // repaints the per-tile indicators alone
          child: ListenableBuilder(
            listenable: controller,
            // the implicit desktop scrollbar is replaced by the
            // viewer-style bar below
            builder: (context, _) => Column(
              children: [
                // page-level file actions sit in a slim header at the top so
                // they never collide with the floating editing toolbar (or a
                // snackbar) that hugs the bottom of the viewport
                if (widget.onPickPdfToInsert != null ||
                    widget.onExportPages != null)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                        8 + inset, 2, _extraRightPadding + inset, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Pages',
                            style: Theme.of(context).textTheme.labelMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        _PageActionsButton(
                          controller: controller,
                          viewerController: widget.viewerController,
                          onPickPdfToInsert: widget.onPickPdfToInsert,
                          onExportPages: widget.onExportPages,
                        ),
                      ],
                    ),
                  ),
                // when more than one page is selected, a bar offers bulk
                // actions on the selection (a single selection is just the
                // navigation cursor — the per-tile delete handles it)
                if (controller.selectedPageCount > 1)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                        8 + inset, 2, _extraRightPadding + inset, 0),
                    child: _PageSelectionBar(
                      controller: controller,
                      allowPageEditing: widget.allowPageEditing,
                      onExportPages: widget.onExportPages,
                    ),
                  ),
                Expanded(
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context)
                        .copyWith(scrollbars: false),
                    child: ReorderableListView.builder(
                      scrollController: _scroll,
                      buildDefaultDragHandles: false,
                      padding: EdgeInsets.fromLTRB(
                          inset, 8, _extraRightPadding + inset, 8),
                      itemCount: controller.document.pageCount,
                      onReorderItem: controller.movePage,
                      itemBuilder: (context, index) {
                        final tile = _PageTile(
                          key: _tileKeys[index] ??= GlobalKey(),
                          controller: controller,
                          viewerController: widget.viewerController,
                          pageIndex: index,
                          pageColor: widget.pageColor,
                          showAnnotations: widget.showAnnotations,
                          allowPageEditing: widget.allowPageEditing,
                          cache: _cache,
                          tileWidth: _tileWidth,
                          renderWorker: widget.renderWorker,
                        );
                        // without the drag listener no reorder can ever start
                        return widget.allowPageEditing
                            ? _ReorderDragStartListener(
                                key: ValueKey(index), index: index, child: tile)
                            : KeyedSubtree(key: ValueKey(index), child: tile);
                      },
                    ),
                  ),
                ),
                // a footer to append a blank page; only when the strip
                // is editable (a read-only strip is purely navigational)
                if (widget.allowPageEditing)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                        4 + inset, 2, _extraRightPadding + inset, 4),
                    child: TextButton.icon(
                      key: const ValueKey('pdf-thumbnail-add-page'),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add page'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        textStyle: Theme.of(context).textTheme.labelMedium,
                      ),
                      onPressed: () => controller.addBlankPage(),
                    ),
                  ),
              ],
            ),
          ),
        );
    // the same scrollbar the viewer paints, so every bar in the chrome
    // looks and behaves alike
    final scrollbar = PdfScrollbar(
      scroll: _scroll,
      thumbKey: const ValueKey('pdf-thumbnail-scrollbar-thumb'),
    );

    // a bottom sheet spans the full width: the list fills it so a drag
    // anywhere in the sheet scrolls (not just over the narrow tile
    // column), the column stays centered via the list's own inset, and
    // the scrollbar pins to the sheet's right edge over the margin
    if (widget.bottomSheet) {
      return LayoutBuilder(builder: (context, constraints) {
        final inset = math.max(0.0, (constraints.maxWidth - width) / 2);
        return Stack(children: [
          Positioned.fill(child: buildList(inset)),
          Positioned(top: 0, bottom: 0, right: 0, child: scrollbar),
        ]);
      });
    }

    return SizedBox(
      width: width,
      child: Stack(children: [
        Positioned.fill(child: buildList(0)),
        // stepped off the resize grip when the grip rides the same
        // (right) edge
        Positioned(
          top: 0,
          bottom: 0,
          right: showGrip && widget.side == PdfSidebarSide.left
              ? PdfSidebarResizeGrip.width
              : 0,
          child: scrollbar,
        ),
        if (showGrip)
          Positioned(
            top: 0,
            bottom: 0,
            left: widget.side == PdfSidebarSide.right ? 0 : null,
            right: widget.side == PdfSidebarSide.left ? 0 : null,
            child: PdfSidebarResizeGrip(
              key: const ValueKey('pdf-thumbnail-resize-grip'),
              side: widget.side,
              onWidthDelta: _onResizeDelta,
              onResizeEnd: _onResizeEnd,
            ),
          ),
      ]),
    );
  }
}

/// The bulk-action bar shown above the tiles when more than one page is
/// selected: rotate / export / delete the selection, and clear it. Shared
/// by the docked strip ([PdfThumbnailSidebar]) and the full-area grid
/// ([PdfThumbnailView]) so both expose the same controls and test keys.
class _PageSelectionBar extends StatelessWidget {
  const _PageSelectionBar({
    required this.controller,
    required this.allowPageEditing,
    required this.onExportPages,
  });

  final PdfEditingController controller;
  final bool allowPageEditing;
  final void Function(Uint8List bytes)? onExportPages;

  /// A compact icon button — tight enough that several fit (and wrap)
  /// within the narrow strip.
  Widget _action({
    required String key,
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) =>
      IconButton(
        key: ValueKey(key),
        icon: Icon(icon, size: 18),
        tooltip: tooltip,
        style: IconButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(32, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        onPressed: onPressed,
      );

  void _exportSelected() {
    final onExport = onExportPages;
    if (onExport == null) return;
    final bytes = controller.exportSelectedPages();
    if (bytes != null) onExport(bytes);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${controller.selectedPageCount} selected',
          style: Theme.of(context).textTheme.labelMedium,
          overflow: TextOverflow.ellipsis,
        ),
        // a Wrap (not a Row) so the action buttons flow onto a second
        // line on the narrow strip instead of overflowing
        Wrap(
          children: [
            if (allowPageEditing) ...[
              _action(
                key: 'pdf-thumbnail-rotate-selected-ccw',
                icon: Icons.rotate_left,
                tooltip: 'Rotate selected pages left',
                onPressed: () => controller.rotateSelectedPages(-90),
              ),
              _action(
                key: 'pdf-thumbnail-rotate-selected-cw',
                icon: Icons.rotate_right,
                tooltip: 'Rotate selected pages right',
                onPressed: () => controller.rotateSelectedPages(90),
              ),
            ],
            if (onExportPages != null)
              _action(
                key: 'pdf-thumbnail-export-selected',
                icon: Icons.file_download_outlined,
                tooltip: 'Export selected pages',
                onPressed: _exportSelected,
              ),
            if (allowPageEditing)
              _action(
                key: 'pdf-thumbnail-delete-selected',
                icon: Icons.delete_outline,
                tooltip: 'Delete selected pages',
                onPressed: () => controller.removeSelectedPages(),
              ),
            _action(
              key: 'pdf-thumbnail-clear-selection',
              icon: Icons.close,
              tooltip: 'Clear selection',
              onPressed: controller.clearPageSelection,
            ),
          ],
        ),
      ],
    );
  }
}

enum _PageAction { insert, export }

/// The thumbnail strip's page-document actions: insert the pages of
/// another PDF (after the current page) and export a page range to a
/// standalone PDF. Both need the host for file I/O — [onPickPdfToInsert]
/// supplies the bytes to merge in, [onExportPages] receives the exported
/// bytes — so a menu item only appears when its callback is given.
class _PageActionsButton extends StatelessWidget {
  const _PageActionsButton({
    required this.controller,
    required this.viewerController,
    this.onPickPdfToInsert,
    this.onExportPages,
  });

  final PdfEditingController controller;
  final PdfViewerController viewerController;
  final Future<Uint8List?> Function()? onPickPdfToInsert;
  final void Function(Uint8List bytes)? onExportPages;

  Future<void> _insert(BuildContext context) async {
    final pick = onPickPdfToInsert;
    if (pick == null) return;
    // read everything off the context BEFORE the async gap
    final messenger = ScaffoldMessenger.maybeOf(context);
    final margin = pdfFloatingToastMargin(context);
    final bytes = await pick();
    if (bytes == null) return;
    try {
      controller.insertPagesFromBytes(bytes,
          at: viewerController.currentPage + 1);
    } catch (_) {
      // a non-PDF, corrupt, or password-protected file can't be opened —
      // tell the user rather than failing silently
      messenger?.showSnackBar(
        SnackBar(
          content: const Text("Couldn't insert that file."),
          behavior: SnackBarBehavior.floating,
          margin: margin,
        ),
      );
    }
  }

  Future<void> _export(BuildContext context) async {
    final onExport = onExportPages;
    if (onExport == null) return;
    final range = await showPdfPageRangeDialog(
      context,
      pageCount: controller.document.pageCount,
    );
    if (range == null) return;
    onExport(controller.exportPageRange(range.start, range.end));
  }

  @override
  Widget build(BuildContext context) {
    final canInsert = onPickPdfToInsert != null;
    final canExport = onExportPages != null;
    return PopupMenuButton<_PageAction>(
      key: const ValueKey('pdf-thumbnail-page-actions'),
      tooltip: 'Page actions',
      icon: const Icon(Icons.file_copy_outlined, size: 18),
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      onSelected: (action) {
        switch (action) {
          case _PageAction.insert:
            _insert(context);
          case _PageAction.export:
            _export(context);
        }
      },
      itemBuilder: (context) => [
        if (canInsert)
          const PopupMenuItem(
            key: ValueKey('pdf-thumbnail-insert-pdf'),
            value: _PageAction.insert,
            child: Text('Insert PDF…'),
          ),
        if (canExport)
          const PopupMenuItem(
            key: ValueKey('pdf-thumbnail-export-pages'),
            value: _PageAction.export,
            child: Text('Export pages…'),
          ),
      ],
    );
  }
}

/// A dedicated, full-area page thumbnail grid — the same page controls
/// as [PdfThumbnailSidebar] (tap to open a page, shift/⌘-click
/// multi-select with a bulk-action bar, per-tile rotate/delete, drag to
/// reorder, the page-actions menu, and the Add-page footer), laid out as
/// a reflowing grid whose tile size the header's size control changes.
/// Use it as a page-organizer view in place of the page viewer.
///
/// Unlike the strip, a plain tap is a "page picker": it scrolls the
/// viewer to that page and fires [onOpenPage] (the host turns the grid
/// off to reveal the page). Shift/⌘ clicks only extend the
/// multi-selection, so a selection can be built without the view jumping.
///
/// The tiles reuse the strip's serialized, render-stamp-keyed thumbnail
/// cache, so an edit re-rasterizes only the pages it touched. The chosen
/// tile width persists via [PdfEditingPreferences.thumbnailViewTileWidth].
///
/// ```dart
/// PdfThumbnailView(
///   controller: editing,
///   viewerController: viewerController,
///   onOpenPage: (_) => setState(() => showGrid = false),
/// )
/// ```
class PdfThumbnailView extends StatefulWidget {
  const PdfThumbnailView({
    super.key,
    required this.controller,
    required this.viewerController,
    this.pageColor = const Color(0xFFFFFFFF),
    this.showAnnotations = true,
    this.allowPageEditing = true,
    this.onPickPdfToInsert,
    this.onExportPages,
    this.onOpenPage,
    this.renderWorker,
    this.minTileWidth = 96,
    this.maxTileWidth = 360,
    this.defaultTileWidth = 168,
  });

  final PdfEditingController controller;

  /// The viewer a tapped tile scrolls to (see [onOpenPage]).
  final PdfViewerController viewerController;

  /// Offloads tile interpretation to a background isolate — pass the same
  /// worker the viewer uses. See [PdfThumbnailSidebar.renderWorker].
  final PdfRenderWorker? renderWorker;

  /// The paper color thumbnails render on (match the viewer's).
  final Color pageColor;

  /// Whether thumbnails render their annotations (match the viewer's).
  final bool showAnnotations;

  /// Whether pages can be reordered (drag), rotated, deleted, and added.
  /// False makes the grid a read-only page picker.
  final bool allowPageEditing;

  /// Picks a PDF to insert after the current page; null hides the
  /// "Insert PDF…" page-action. See [PdfThumbnailSidebar.onPickPdfToInsert].
  final Future<Uint8List?> Function()? onPickPdfToInsert;

  /// Receives the bytes of an exported page range; null hides the
  /// "Export pages…" page-action and the selection bar's export.
  final void Function(Uint8List bytes)? onExportPages;

  /// Called after a plain tap scrolls the viewer to [pageIndex]. Hosts
  /// that show the grid in place of the viewer turn it off here so the
  /// chosen page shows.
  final void Function(int pageIndex)? onOpenPage;

  /// Clamps for the tile-size control.
  final double minTileWidth;
  final double maxTileWidth;

  /// The tile width used until the size control (or a stored preference)
  /// sets one.
  final double defaultTileWidth;

  @override
  State<PdfThumbnailView> createState() => _PdfThumbnailViewState();
}

class _PdfThumbnailViewState extends State<PdfThumbnailView> {
  final ScrollController _scroll = ScrollController();
  final _ThumbnailCache _cache = _ThumbnailCache();

  PdfEditingPreferences get _preferences => widget.controller.preferences;

  double get _tileWidth =>
      (_preferences.thumbnailViewTileWidth ?? widget.defaultTileWidth)
          .clamp(widget.minTileWidth, widget.maxTileWidth);

  @override
  void initState() {
    super.initState();
    _preferences.addListener(_onPreferences);
  }

  @override
  void didUpdateWidget(PdfThumbnailView old) {
    super.didUpdateWidget(old);
    if (!identical(old.controller.preferences, _preferences)) {
      old.controller.preferences.removeListener(_onPreferences);
      _preferences.addListener(_onPreferences);
    }
    // a different edit session: its render stamps restart at zero, so
    // cached rasters keyed by the old session's stamps would collide
    if (!identical(old.controller, widget.controller)) _cache.clear();
  }

  @override
  void dispose() {
    _preferences.removeListener(_onPreferences);
    _scroll.dispose();
    _cache.dispose();
    super.dispose();
  }

  void _onPreferences() {
    if (mounted) setState(() {});
  }

  void _openPage(int index) {
    unawaited(widget.viewerController.jumpToPage(index));
    widget.onOpenPage?.call(index);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final tileWidth = _tileWidth;
    // the scrollbar overlays the grid's right edge; keep content clear of it
    const barClearance = PdfScrollbar.hitExtent;
    // opaque so the grid eats every pointer in its area — a host overlays it
    // over the live viewer, and a tap in a header/inter-tile gap must not
    // fall through to the page underneath
    return Listener(
      behavior: HitTestBehavior.opaque,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        // only document changes rebuild the grid — viewer scrolling repaints
        // the per-tile viewport indicators alone
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => Column(
            children: [
              // header: title, the tile-size control, and the page-actions menu
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 4 + barClearance, 4),
                child: Row(children: [
                  Text('Pages', style: Theme.of(context).textTheme.titleSmall),
                  const Spacer(),
                  _ThumbnailSizeControl(
                    value: tileWidth,
                    min: widget.minTileWidth,
                    max: widget.maxTileWidth,
                    onChanged: (value) =>
                        _preferences.thumbnailViewTileWidth = value,
                  ),
                  if (widget.onPickPdfToInsert != null ||
                      widget.onExportPages != null)
                    _PageActionsButton(
                      controller: controller,
                      viewerController: widget.viewerController,
                      onPickPdfToInsert: widget.onPickPdfToInsert,
                      onExportPages: widget.onExportPages,
                    ),
                ]),
              ),
              // bulk actions on the multi-selection, as in the strip
              if (controller.selectedPageCount > 1)
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(12, 0, 12 + barClearance, 4),
                  child: _PageSelectionBar(
                    controller: controller,
                    allowPageEditing: widget.allowPageEditing,
                    onExportPages: widget.onExportPages,
                  ),
                ),
              const Divider(height: 1),
              Expanded(
                child: Stack(children: [
                  Positioned.fill(
                    child: ScrollConfiguration(
                      // replaced by the viewer-style bar below
                      behavior: ScrollConfiguration.of(context)
                          .copyWith(scrollbars: false),
                      child: SingleChildScrollView(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(
                            12, 12, 12 + barClearance, 12),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (var i = 0;
                                i < controller.document.pageCount;
                                i++)
                              SizedBox(
                                width: tileWidth,
                                child: _GridPageCell(
                                  key: ValueKey('pdf-thumbnail-grid-cell-$i'),
                                  controller: controller,
                                  viewerController: widget.viewerController,
                                  pageIndex: i,
                                  pageColor: widget.pageColor,
                                  showAnnotations: widget.showAnnotations,
                                  allowPageEditing: widget.allowPageEditing,
                                  cache: _cache,
                                  // the tile pads ~21px around the thumbnail
                                  tileWidth: tileWidth - 21,
                                  renderWorker: widget.renderWorker,
                                  onActivatePage: _openPage,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    bottom: 0,
                    right: 0,
                    child: PdfScrollbar(
                      scroll: _scroll,
                      thumbKey:
                          const ValueKey('pdf-thumbnail-view-scrollbar-thumb'),
                    ),
                  ),
                ]),
              ),
              // a footer to append a blank page; editable grids only
              if (widget.allowPageEditing)
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: TextButton.icon(
                    key: const ValueKey('pdf-thumbnail-view-add-page'),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add page'),
                    onPressed: () => controller.addBlankPage(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The header slider that sets the grid's tile width, flanked by small/
/// large thumbnail glyphs.
class _ThumbnailSizeControl extends StatelessWidget {
  const _ThumbnailSizeControl({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.photo_size_select_small, size: 18, color: color),
        SizedBox(
          width: 120,
          child: Slider(
            key: const ValueKey('pdf-thumbnail-view-size'),
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        Icon(Icons.photo_size_select_large, size: 22, color: color),
      ],
    );
  }
}

/// One cell of the thumbnail grid: a [_PageTile] wrapped for drag-to-
/// reorder. A mouse picks a tile up immediately (it hovers first, so the
/// cell knows a pointer is present); touch and stylus need a long press,
/// so a finger drag still scrolls the grid. Dropping onto another cell
/// moves the page there ([PdfEditingController.movePage]). With
/// [allowPageEditing] off the cell is the bare tile — read-only grids
/// only navigate.
class _GridPageCell extends StatefulWidget {
  const _GridPageCell({
    super.key,
    required this.controller,
    required this.viewerController,
    required this.pageIndex,
    required this.pageColor,
    required this.showAnnotations,
    required this.allowPageEditing,
    required this.cache,
    required this.tileWidth,
    required this.renderWorker,
    required this.onActivatePage,
  });

  final PdfEditingController controller;
  final PdfViewerController viewerController;
  final int pageIndex;
  final Color pageColor;
  final bool showAnnotations;
  final bool allowPageEditing;
  final _ThumbnailCache cache;
  final double tileWidth;
  final PdfRenderWorker? renderWorker;
  final void Function(int pageIndex) onActivatePage;

  @override
  State<_GridPageCell> createState() => _GridPageCellState();
}

class _GridPageCellState extends State<_GridPageCell> {
  // hovering with a mouse switches the cell to an immediate drag; touch
  // never hovers, so it falls through to the long-press recognizer and a
  // finger drag still scrolls the grid.
  bool _hasMouse = false;

  Widget _tile() => _PageTile(
        controller: widget.controller,
        viewerController: widget.viewerController,
        pageIndex: widget.pageIndex,
        pageColor: widget.pageColor,
        showAnnotations: widget.showAnnotations,
        allowPageEditing: widget.allowPageEditing,
        cache: widget.cache,
        tileWidth: widget.tileWidth,
        renderWorker: widget.renderWorker,
        onActivatePage: widget.onActivatePage,
      );

  @override
  Widget build(BuildContext context) {
    final tile = _tile();
    if (!widget.allowPageEditing) return tile;

    final draggable = MouseRegion(
      onEnter: (_) => setState(() => _hasMouse = true),
      onExit: (_) => setState(() => _hasMouse = false),
      child: _draggable(tile),
    );
    return DragTarget<int>(
      // a page never drops onto itself
      onWillAcceptWithDetails: (details) => details.data != widget.pageIndex,
      // movePage lands the dragged page at this cell's index (§ moves the
      // page so it ends up at [to])
      onAcceptWithDetails: (details) =>
          widget.controller.movePage(details.data, widget.pageIndex),
      builder: (context, candidate, rejected) {
        final scheme = Theme.of(context).colorScheme;
        final active = candidate.isNotEmpty;
        // a 2px frame, always laid out (transparent when idle), marks the
        // cell a drop would land on — DecoratedBox paints it over the tile
        // edge without reserving space, so the tile never shifts
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active ? scheme.primary : Colors.transparent,
              width: 2,
            ),
            color: active ? scheme.primary.withValues(alpha: 0.08) : null,
          ),
          child: draggable,
        );
      },
    );
  }

  Widget _draggable(Widget tile) {
    final feedback = _DragFeedback(
      label: 'Page ${widget.pageIndex + 1}',
      width: widget.tileWidth,
    );
    // dim the page being dragged in place, leaving a gap-marker
    final placeholder = Opacity(opacity: 0.3, child: tile);
    return _hasMouse
        ? Draggable<int>(
            data: widget.pageIndex,
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: feedback,
            childWhenDragging: placeholder,
            child: tile,
          )
        : LongPressDraggable<int>(
            data: widget.pageIndex,
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: feedback,
            childWhenDragging: placeholder,
            child: tile,
          );
  }
}

/// The little card that rides the cursor while a grid tile is dragged.
class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.label, required this.width});

  final String label;
  final double width;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: Container(
        width: (width * 0.8).clamp(120.0, 260.0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.primary, width: 1.5),
          boxShadow: const [
            BoxShadow(
                color: Colors.black26, blurRadius: 8, offset: Offset(0, 4)),
          ],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.description_outlined, size: 18, color: scheme.primary),
          const SizedBox(width: 8),
          Flexible(
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: scheme.onSurface)),
          ),
        ]),
      ),
    );
  }
}

/// Starts a tile drag immediately for mouse pointers (the desktop
/// expectation — a mouse drag never means scrolling) but only after a
/// long press for touch and stylus, so finger drags still scroll the
/// list. Plain taps are unaffected either way: both recognizers claim
/// the pointer only once it moves past the slop.
class _ReorderDragStartListener extends ReorderableDragStartListener {
  const _ReorderDragStartListener({
    super.key,
    required super.index,
    required super.child,
  });

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        SliverReorderableList.maybeOf(context)?.startItemDragReorder(
          index: index,
          event: event,
          recognizer: (event.kind == PointerDeviceKind.mouse
              ? ImmediateMultiDragGestureRecognizer(debugOwner: this)
              : DelayedMultiDragGestureRecognizer(debugOwner: this))
            ..gestureSettings = MediaQuery.maybeGestureSettingsOf(context),
        );
      },
      child: child,
    );
  }
}

/// One page's thumbnail with its "Page N" / delete footer.
class _PageTile extends StatelessWidget {
  const _PageTile({
    super.key,
    required this.controller,
    required this.viewerController,
    required this.pageIndex,
    required this.pageColor,
    required this.showAnnotations,
    required this.allowPageEditing,
    required this.cache,
    required this.tileWidth,
    required this.renderWorker,
    this.onActivatePage,
  });

  final PdfEditingController controller;
  final PdfViewerController viewerController;
  final int pageIndex;
  final Color pageColor;
  final bool showAnnotations;
  final bool allowPageEditing;
  final _ThumbnailCache cache;
  final double tileWidth;
  final PdfRenderWorker? renderWorker;

  /// Overrides what a plain tap does after selecting the page. The strip
  /// leaves this null and just scrolls the viewer to the page; the
  /// full-area grid passes a handler that also dismisses the grid (a
  /// "page picker" tap). Shift/⌘ clicks are unaffected — they only
  /// extend the multi-selection, never navigate.
  final void Function(int pageIndex)? onActivatePage;

  /// WCAG-style contrast ratio between two opaque colors.
  static double _contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  /// Tapping a tile selects it for the strip's multi-select and (for a
  /// plain tap) navigates there. Shift extends a range from the anchor;
  /// ⌘/Ctrl toggles the tile in the selection — neither navigates, so the
  /// reader can build a selection without the viewport jumping around.
  void _onTap() {
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isShiftPressed) {
      controller.selectPageRange(pageIndex);
      return;
    }
    if (keyboard.isMetaPressed || keyboard.isControlPressed) {
      controller.togglePageSelection(pageIndex);
      return;
    }
    controller.selectPage(pageIndex);
    final activate = onActivatePage;
    if (activate != null) {
      activate(pageIndex);
    } else {
      unawaited(viewerController.jumpToPage(pageIndex));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = controller.isPageSelected(pageIndex);
    // the viewport mark paints over the paper, not the app surface: a
    // dark theme's light primary vanishes on a white thumbnail, so pick
    // whichever accent actually contrasts with the page color
    final indicator = _contrast(scheme.primary, pageColor) >=
            _contrast(scheme.inversePrimary, pageColor)
        ? scheme.primary
        : scheme.inversePrimary;
    final document = controller.document;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onTap,
      // a selected tile reads as a primary-framed, tinted chip behind the
      // thumbnail. The 1.5px frame is always laid out (transparent when
      // unselected) and paid back out of the padding, so selecting a tile
      // never nudges its contents — per-tile layout, _tileWidth's -26, and
      // _estimateOffset all still hold (each side still totals 12/4px).
      child: Container(
        padding: const EdgeInsets.fromLTRB(10.5, 2.5, 10.5, 2.5),
        decoration: BoxDecoration(
          color: selected ? scheme.primary.withValues(alpha: 0.20) : null,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? scheme.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // the current-page outline and the viewport mark track the
            // viewer per tile, without rebuilding the page image
            ListenableBuilder(
              listenable: Listenable.merge([
                viewerController,
                viewerController.viewportChanges,
              ]),
              builder: (context, _) {
                final current = viewerController.currentPage == pageIndex;
                final viewport = viewerController.visiblePageRegion(pageIndex);
                // Container, not DecoratedBox: the border must inset the
                // child (Container adds the decoration's padding), or the
                // full-bleed thumbnail paints over the 1-2px ring and
                // neither the current-page outline nor the hairline shows
                return Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: current ? scheme.primary : scheme.outlineVariant,
                      width: current ? 2 : 1,
                    ),
                  ),
                  child: Stack(children: [
                    // the boundary keeps scroll-driven indicator repaints
                    // from re-uploading the thumbnail
                    RepaintBoundary(
                      child: _PageThumbnail(
                        controller: controller,
                        pageIndex: pageIndex,
                        pageColor: pageColor,
                        showAnnotations: showAnnotations,
                        cache: cache,
                        tileWidth: tileWidth,
                        renderWorker: renderWorker,
                      ),
                    ),
                    if (viewport != null)
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _ViewportPainter(viewport, indicator),
                        ),
                      ),
                    // an explicit "in the selection" marker, painted last
                    // so it rides above the page and the viewport mark —
                    // the chip tint alone can be missed on a busy page
                    if (selected)
                      Positioned(
                        top: 3,
                        left: 3,
                        child: _SelectionBadge(scheme: scheme),
                      ),
                  ]),
                );
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  // the label echoes the selection so the cue carries into
                  // the footer row, below the framed thumbnail
                  child: Text('Page ${pageIndex + 1}',
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: selected ? scheme.primary : null,
                            fontWeight: selected ? FontWeight.w600 : null,
                          )),
                ),
                // No Tooltip on these buttons: a Tooltip is an OverlayPortal,
                // and an OverlayPortal inside a ReorderableListView item
                // crashes when the item is reactivated during a layout pass
                // (the strip's bottom-sheet LayoutBuilder, or a reorder) — it
                // mutates the overlay's RenderObject mid-layout. A Semantics
                // label keeps the buttons accessible without one.
                if (allowPageEditing)
                  Semantics(
                    label: 'Rotate page right',
                    button: true,
                    child: IconButton(
                      key: ValueKey('pdf-thumbnail-rotate-$pageIndex'),
                      icon: const Icon(Icons.rotate_right, size: 16),
                      style: IconButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(28, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => controller.rotatePages([pageIndex], 90),
                    ),
                  ),
                if (allowPageEditing && document.pageCount > 1)
                  Semantics(
                    label: 'Delete page',
                    button: true,
                    child: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 16),
                      style: IconButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(28, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => controller.removePage(pageIndex),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The check badge overlaid on a selected page's thumbnail — an
/// unmistakable "this page is in the selection" marker that reads on any
/// page color, where the chip tint alone can be missed. A ring in the
/// surface color keeps it legible where the primary circle meets a
/// same-hued page.
class _SelectionBadge extends StatelessWidget {
  const _SelectionBadge({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: scheme.primary,
          shape: BoxShape.circle,
          border: Border.all(color: scheme.surface, width: 1.5),
        ),
        padding: const EdgeInsets.all(1.5),
        child: Icon(Icons.check, size: 12, color: scheme.onPrimary),
      );
}

/// Renders a page to a tile-resolution bitmap, cached across revisions
/// by the page's render stamp — an edit elsewhere reuses the raster.
class _PageThumbnail extends StatefulWidget {
  const _PageThumbnail({
    required this.controller,
    required this.pageIndex,
    required this.pageColor,
    required this.showAnnotations,
    required this.cache,
    required this.tileWidth,
    required this.renderWorker,
  });

  final PdfEditingController controller;
  final int pageIndex;
  final Color pageColor;
  final bool showAnnotations;
  final _ThumbnailCache cache;
  final double tileWidth;
  final PdfRenderWorker? renderWorker;

  @override
  State<_PageThumbnail> createState() => _PageThumbnailState();
}

class _PageThumbnailState extends State<_PageThumbnail> {
  ui.Image? _image; // this tile's clone; the cache owns the original
  String? _imageKey;
  String? _pendingKey;

  /// Raster widths snap to 64px steps so a resize drag doesn't re-render
  /// every page per pixel.
  static int _bucket(double px) => ((px / 64).ceil() * 64).clamp(64, 1024);

  @override
  void didUpdateWidget(_PageThumbnail old) {
    super.didUpdateWidget(old);
    // a different edit session: render stamps restart at zero, so the
    // new document's keys collide with the shown image's — drop it
    if (!identical(old.controller, widget.controller)) {
      _image?.dispose();
      _image = null;
      _imageKey = null;
      _pendingKey = null;
    }
  }

  @override
  void dispose() {
    _pendingKey = null;
    _image?.dispose();
    _image = null;
    super.dispose();
  }

  void _enqueue(String key, int pixelWidth) {
    _pendingKey = key;
    final controller = widget.controller;
    final pageIndex = widget.pageIndex;
    final pageColor = widget.pageColor;
    final annotations = widget.showAnnotations;
    final cache = widget.cache;
    final worker = widget.renderWorker;
    cache.enqueue(() async {
      // superseded (newer revision, resize) or already landed — skip
      if (!mounted || _pendingKey != key) return;
      // nothing may escape: a single failing page must neither poison
      // the panel's queue (every later thumbnail would silently never
      // render) nor surface — it just keeps its blank placeholder
      try {
        final page = controller.pageAt(pageIndex);
        final size = PdfPageRenderer.pageSize(page);
        if (size.width <= 0 || size.height <= 0) return;
        final ratio = pixelWidth / size.width;
        // priority 2: thumbnails yield to the on-screen page (0) and its
        // previews (1); the heavy interpret runs on the isolate, only the
        // small replay + raster stays here. Image pages and the web
        // fallback return null and rasterize locally as before.
        final commands = worker != null && worker.isActive
            ? await worker.record(pageIndex,
                annotations: annotations, priority: 2)
            : null;
        if (!mounted || _pendingKey != key) return;
        final ui.Image image;
        if (commands != null) {
          final picture = await PdfPageRenderer.pictureFromCommands(
              page, commands,
              pageColor: pageColor);
          if (!mounted || _pendingKey != key) {
            picture.dispose();
            return;
          }
          try {
            image = await PdfPageRenderer.rasterize(picture, size, ratio);
          } finally {
            picture.dispose();
          }
        } else {
          image = await PdfPageRenderer.renderImage(page,
              pixelRatio: ratio,
              pageColor: pageColor,
              annotations: annotations);
        }
        PdfThumbnailSidebar.debugRasterizations++;
        cache.put(key, image);
        if (!mounted || _pendingKey != key) return;
        setState(() {
          _pendingKey = null;
          _image?.dispose();
          _image = cache.claim(key);
          _imageKey = key;
        });
      } catch (_) {
        // keep the placeholder; the queue moves on to the next page
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.controller.pageAt(widget.pageIndex);
    final size = PdfPageRenderer.pageSize(page);
    final pixelWidth =
        _bucket(widget.tileWidth * MediaQuery.devicePixelRatioOf(context));
    final stamp = widget.controller.pageRenderStamp(widget.pageIndex);
    final key = '${widget.pageIndex}|$stamp'
        '|${widget.pageColor.toARGB32()}|$pixelWidth'
        '${widget.showAnnotations ? '' : '|noannots'}';
    if (_imageKey != key) {
      final cached = widget.cache.claim(key);
      if (cached != null) {
        _image?.dispose();
        _image = cached;
        _imageKey = key;
        _pendingKey = null;
      } else if (_pendingKey != key) {
        _enqueue(key, pixelWidth);
      }
    }
    // while a re-render is in flight the previous raster keeps showing
    return AspectRatio(
      aspectRatio:
          size.width <= 0 || size.height <= 0 ? 1 : size.width / size.height,
      child: _image == null
          ? ColoredBox(color: widget.pageColor)
          : RawImage(image: _image, fit: BoxFit.contain),
    );
  }
}

/// An LRU of rasterized thumbnails, owned by the sidebar — and the
/// panel's render queue. Entries hand out [ui.Image.clone]s, so an
/// eviction never pulls pixels out from under a tile that is still
/// painting them.
class _ThumbnailCache {
  static const _capacity = 96;

  final Map<String, ui.Image> _images = {};
  bool _disposed = false;

  /// The serialization tail: renders run strictly one page at a time
  /// per panel, so a burst of fresh tiles never interprets a dozen
  /// pages at once. Per panel, not static — a process-wide chain would
  /// strand continuations in a dead async zone once any earlier zone
  /// (a widget test's FakeAsync, for one) completed the tail.
  Future<void> _queue = Future<void>.value();

  void enqueue(Future<void> Function() task) {
    // tasks swallow their own errors, so the chain never fails
    _queue = _queue.then((_) => task());
  }

  ui.Image? claim(String key) {
    final image = _images.remove(key);
    if (image == null) return null;
    _images[key] = image; // back to most-recently-used
    return image.clone();
  }

  void put(String key, ui.Image image) {
    if (_disposed) {
      image.dispose(); // landed after the sidebar went away
      return;
    }
    _images.remove(key)?.dispose();
    _images[key] = image;
    while (_images.length > _capacity) {
      _images.remove(_images.keys.first)!.dispose();
    }
  }

  /// Drops every entry — a new document's render stamps restart at
  /// zero, so stale keys from the old one would collide.
  void clear() {
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
  }

  void dispose() {
    _disposed = true;
    clear();
  }
}

/// Marks the viewer's viewport on a thumbnail: [region] is the visible
/// part of the page as fractions of its area.
class _ViewportPainter extends CustomPainter {
  const _ViewportPainter(this.region, this.color);

  final Rect region;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTRB(
      region.left * size.width,
      region.top * size.height,
      region.right * size.width,
      region.bottom * size.height,
    );
    canvas
      ..drawRect(rect, Paint()..color = color.withValues(alpha: 0.10))
      ..drawRect(
          rect.deflate(0.75),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = color);
  }

  @override
  bool shouldRepaint(_ViewportPainter old) =>
      old.region != region || old.color != color;
}
