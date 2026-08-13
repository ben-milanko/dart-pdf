import 'dart:async';
import 'dart:developer' show TimelineTask;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../debug_overlays.dart';
import '../l10n/pdf_l10n.dart';
import '../page_range_dialog.dart';
import '../pdf_page_view.dart';
import '../pdf_viewer.dart';
import '../tile_store.dart';
import '../perf_log.dart';
import '../raster_cache.dart';
import '../render_worker.dart';
import '../renderer.dart';
import '../scrollbar.dart';
import '../toast.dart';
import 'editing_controller.dart';
import 'editing_panel.dart';
import 'editing_preferences.dart';
import 'editing_thumbnail_drop.dart';
import 'thumbnail_cache.dart';

/// A panel of page thumbnails: tap one to jump there, drag a tile up or
/// down to reorder pages (with a mouse just drag; on touch, long-press
/// first so the list still scrolls), the per-tile button deletes a page
/// (the last remaining page cannot be deleted), and the strip's footer
/// appends a blank page. Right-clicking a tile (secondary tap) opens a
/// page context menu - rotate, duplicate, copy/cut/paste (a shared page
/// clipboard, so pages copied here paste into a different document tab),
/// insert a blank page before or after, export (when [onExportPages] is
/// given), delete - that acts on the strip's selection when the tile
/// belongs to it. Copy/cut/paste are also bound to ⌘/Ctrl+C/X/V, and
/// Delete/Backspace removes the strip's selection (or the keyboard/current
/// page when nothing is selected). All of this (export aside) needs
/// [allowPageEditing].
///
/// Built to stay light on large documents: thumbnails are rasterized at
/// tile resolution and cached, keyed by
/// [PdfEditingController.pageRenderStamp] - so an edit re-renders only
/// the pages it touched, renders are serialized (one page at a time)
/// instead of bursting on first layout, and scrolling the viewer
/// repaints only each tile's viewport indicator, never the page images.
///
/// The strip follows the viewer ([followsViewer]): when the current page
/// changes - scrolling, search, a link jump - the strip scrolls its tile
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
    this.dock = PdfPanelDock.left,
    this.resizable = true,
    this.minWidth = 100,
    this.maxWidth = 400,
    this.followsViewer = true,
    this.allowPageEditing = true,
    this.bottomSheet = false,
    this.onClose,
    this.onPickPdfToInsert,
    this.onExportPages,
    this.fileDropController,
    this.renderWorker,
    this.rasterCache,
  });

  final PdfEditingController controller;

  /// Offloads tile interpretation to a background isolate (see
  /// [PdfViewer.renderWorker]) so rasterizing thumbnails of heavy pages
  /// doesn't block the UI thread. Pass the same worker the viewer uses.
  final PdfRenderWorker? renderWorker;

  /// Optional persistent on-disk thumbnail cache, bound to the open document
  /// (see [PdfRasterCache]). When given, unedited pages open straight from
  /// disk in a later session and freshly-rendered ones write through, so a
  /// re-opened page grid doesn't re-interpret every page.
  final PdfRasterCache? rasterCache;

  /// The viewer to navigate when a thumbnail is tapped.
  final PdfViewerController viewerController;

  /// The default width - a user-dragged width, persisted in
  /// [PdfEditingPreferences.thumbnailSidebarWidth], wins over it.
  final double width;

  /// The paper color thumbnails render on - pass the viewer's
  /// [PdfViewer.pageColor] so they match the pages.
  final Color pageColor;

  /// Whether thumbnails render their annotations - pass the viewer's
  /// [PdfViewer.showAnnotations] so they match the pages.
  final bool showAnnotations;

  /// Which edge of the viewer the panel docks on; the resize grip rides
  /// the opposite (inner) edge.
  final PdfPanelDock dock;

  /// Whether the inner edge can be dragged to resize the panel.
  final bool resizable;

  /// Clamps for the dragged width.
  final double minWidth;
  final double maxWidth;

  /// Whether the strip scrolls the current page's tile into view when
  /// the viewer's page changes.
  final bool followsViewer;

  /// Whether pages can be reordered (drag) and deleted (footer button)
  /// from the strip. False makes it purely navigational - the mode a
  /// read-only viewer wants.
  final bool allowPageEditing;

  /// Lays the strip out to fill its parent (full width, no side resize
  /// grip) for hosting inside a bottom sheet on a small screen, rather
  /// than as a fixed-width docked column.
  final bool bottomSheet;

  /// Closes the docked panel - the host turns its visibility preference
  /// off. When given (and not a [bottomSheet]) a close (×) button appears
  /// in the strip's header. Null leaves the strip with no close button (a
  /// bottom sheet supplies its own).
  final VoidCallback? onClose;

  /// Picks a PDF to insert and returns its bytes (null = cancelled). When
  /// given, a "Insert PDF…" entry appears in the strip's page-actions
  /// footer menu and merges all of the picked file's pages in after the
  /// current page. Needs the host for file I/O.
  final Future<Uint8List?> Function()? onPickPdfToInsert;

  /// Receives the bytes of an exported page range, for the host to save.
  /// When given, an "Export pages…" entry appears in the page-actions
  /// footer menu.
  final void Function(Uint8List bytes)? onExportPages;

  /// Lets a PDF dragged in from outside the app (the desktop, a browser
  /// download) be dropped *between two tiles* - the strip paints an
  /// insertion marker where the pages would land while the drag hovers,
  /// and the host reads the index back to insert there. The platform's
  /// drag stream lives with the host, so it drives the controller; the
  /// strip only supplies the geometry. Null (the default) leaves the
  /// strip inert to external drags. See [PdfThumbnailDropController].
  final PdfThumbnailDropController? fileDropController;

  /// How many thumbnails have actually been rasterized - cache misses
  /// only, across all sidebars. Tests assert on the deltas.
  @visibleForTesting
  static int debugRasterizations = 0;

  @override
  State<PdfThumbnailSidebar> createState() => _PdfThumbnailSidebarState();
}

class _PdfThumbnailSidebarState extends State<PdfThumbnailSidebar> {
  final ScrollController _scroll = ScrollController();
  final FocusNode _focusNode = FocusNode(debugLabel: 'PdfThumbnailSidebar');

  /// The session's shared thumbnail cache (and viewport-ordered render
  /// queue) - the same instance the page grid uses, so a page rendered in
  /// one is reused by the other.
  PdfThumbnailCache get _cache => widget.controller.thumbnailCache;

  /// Per-slot keys so [_revealPage] can [Scrollable.ensureVisible] a
  /// built tile.
  final Map<int, GlobalKey> _tileKeys = {};

  PdfSidebarPanelGeometry? _frameGeometry;

  int _lastCurrent = 0;

  /// The tile the mouse is over, tracked even while Shift is up so the
  /// range preview can appear the instant Shift goes down.
  int? _hoverPage;

  /// Whether Shift is held - while it is (and a tile is hovered) the strip
  /// previews the range a shift-click would select.
  bool _shiftHeld = HardwareKeyboard.instance.isShiftPressed;

  /// The page keyboard navigation last landed on. When null, the current
  /// page selection or viewer page supplies the starting point.
  int? _keyboardPage;

  /// The selected tile currently driving a reorder. Other pages in the same
  /// selection stay in place as dimmed placeholders while the proxy carries
  /// the whole selection's page count.
  int? _reorderPage;

  /// This strip's hit-test, registered with
  /// [PdfThumbnailSidebar.fileDropController]. Held in a field so attach
  /// and detach pass the *same* closure (a method tear-off is a fresh
  /// object each time it's read).
  late final PdfThumbnailDropResolver _dropResolver = _dropIndexAt;

  PdfEditingPreferences get _preferences => widget.controller.preferences;

  /// The pages the strip is previewing as a shift-click range: empty
  /// unless Shift is held over a hovered tile.
  Set<int> get _rangePreview => _shiftHeld && _hoverPage != null
      ? widget.controller.pageRangePreviewTo(_hoverPage!).toSet()
      : const {};

  /// Tracks Shift's up/down so the preview can show and clear live. The
  /// handler never consumes the event.
  bool _onKeyEvent(KeyEvent event) {
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (shift != _shiftHeld && mounted) setState(() => _shiftHeld = shift);
    return false;
  }

  /// A tile's mouse enter/exit. The field always updates; a rebuild only
  /// happens while Shift is held or desktop hover-revealed controls are
  /// enabled.
  void _setHover(int index, bool hovering) {
    final next = hovering ? index : (_hoverPage == index ? null : _hoverPage);
    if (next == _hoverPage) return;
    _hoverPage = next;
    if ((_shiftHeld || pdfPanelControlsRevealOnHover()) && mounted) {
      setState(() {});
    }
  }

  void _focusPage(int index) {
    _keyboardPage = index;
    _focusNode.requestFocus();
  }

  int _keyboardBase() {
    final selected = widget.controller.selectedPages;
    final count = widget.controller.document.pageCount;
    final base = _keyboardPage ??
        (selected.isNotEmpty
            ? selected.last
            : widget.viewerController.currentPage);
    return base.clamp(0, math.max(0, count - 1)).toInt();
  }

  void _moveKeyboardSelection(int delta) {
    final count = widget.controller.document.pageCount;
    if (count == 0) return;
    final target = (_keyboardBase() + delta).clamp(0, count - 1).toInt();
    _focusPage(target);
    if (HardwareKeyboard.instance.isShiftPressed) {
      widget.controller.selectPageRange(target);
    } else {
      widget.controller.selectPage(target);
    }
    _cache.focus = target;
    if (widget.followsViewer) _revealPage(target);
    unawaited(widget.viewerController.jumpToPage(target));
  }

  /// The pages a copy/cut shortcut acts on: the strip's selection, or the
  /// keyboard/current page when nothing is selected.
  List<int> _clipboardTargets() {
    final selected = widget.controller.selectedPages;
    if (selected.isNotEmpty) return selected;
    if (widget.controller.document.pageCount == 0) return const [];
    return [_keyboardBase()];
  }

  void _copyPages() => widget.controller.copyPages(_clipboardTargets());

  void _cutPages() => widget.controller.cutPages(_clipboardTargets());

  /// The page a paste would drop the clipboard's pages after while the mouse
  /// hovers the strip: the tile under the cursor, once the shared page
  /// clipboard holds something. Null when nothing is copied, no tile is
  /// hovered, or the platform has no reliable hover (touch). Drives both the
  /// on-tile insertion indicator and where [_pastePages] lands, so the mark
  /// always tells the truth about the next paste.
  int? get _pasteInsertionPage => widget.allowPageEditing &&
          widget.controller.hasPageClipboard &&
          _hoverPage != null &&
          pdfPanelControlsRevealOnHover()
      ? _hoverPage
      : null;

  /// Pastes the shared clipboard's pages after the selection (or the
  /// keyboard/current page) and reveals where they landed. A live hover over
  /// the strip - the case the insertion indicator marks - aims the paste at
  /// the hovered tile instead, so ⌘/Ctrl+V drops the pages exactly where the
  /// mark shows.
  void _pastePages() {
    final selected = widget.controller.selectedPages;
    final base = _pasteInsertionPage ??
        (selected.isNotEmpty ? selected.last : _keyboardBase());
    final at = base + 1;
    if (!widget.controller.pastePages(at: at)) return;
    _focusPage(at);
    if (widget.followsViewer) {
      // A paste inserts pages, so the viewer resets its scroll to the top in
      // a post-frame callback (a geometry-changing revision). A following
      // strip chases that reset via [_onViewerChanged] and scrolls back to
      // the top, burying the pages that just landed. Drive the viewer to the
      // paste target after its reset settles so the strip reveals the new
      // pages instead - the same route the menu/header paste paths take.
      unawaited(_jumpToInsertedPage(widget.viewerController, at));
    } else {
      _revealPage(at);
    }
  }

  /// Deletes the strip's selection, or the keyboard/current page when
  /// nothing is selected - the last remaining page is kept either way.
  void _deletePages() {
    if (widget.controller.hasPageSelection) {
      widget.controller.removeSelectedPages();
    } else if (widget.controller.document.pageCount > 0) {
      widget.controller.removePage(_keyboardBase());
    }
  }

  Map<ShortcutActivator, VoidCallback> get _keyboardShortcuts => {
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _moveKeyboardSelection(-1),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _moveKeyboardSelection(1),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _moveKeyboardSelection(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _moveKeyboardSelection(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp, shift: true): () =>
            _moveKeyboardSelection(-1),
        const SingleActivator(LogicalKeyboardKey.arrowDown, shift: true): () =>
            _moveKeyboardSelection(1),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true): () =>
            _moveKeyboardSelection(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true): () =>
            _moveKeyboardSelection(1),
        if (widget.allowPageEditing) ...{
          const SingleActivator(LogicalKeyboardKey.keyC, meta: true):
              _copyPages,
          const SingleActivator(LogicalKeyboardKey.keyC, control: true):
              _copyPages,
          const SingleActivator(LogicalKeyboardKey.keyX, meta: true): _cutPages,
          const SingleActivator(LogicalKeyboardKey.keyX, control: true):
              _cutPages,
          const SingleActivator(LogicalKeyboardKey.keyV, meta: true):
              _pastePages,
          const SingleActivator(LogicalKeyboardKey.keyV, control: true):
              _pastePages,
          const SingleActivator(LogicalKeyboardKey.delete): _deletePages,
          const SingleActivator(LogicalKeyboardKey.backspace): _deletePages,
        },
      };

  double get _frameWidth =>
      _frameGeometry?.width ??
      (_preferences.thumbnailSidebarWidth ?? widget.width)
          .clamp(widget.minWidth, widget.maxWidth)
          .toDouble();

  /// The scrollbar (and, when it rides the same right edge, the resize
  /// grip) overlay the list - the list keeps clear of that zone so the
  /// bar never covers a tile. Tiles already pad 12px on their own.
  double get _barClearance =>
      _frameGeometry?.scrollbarClearance ??
      PdfScrollbar.hitExtent +
          (widget.resizable &&
                  !widget.bottomSheet &&
                  widget.dock == PdfPanelDock.left
              ? PdfSidebarResizeGrip.width
              : 0);

  double get _extraRightPadding => math.max(0, _barClearance - 12);

  /// The width a tile's thumbnail actually lays out at: panel width less
  /// the tile's 12px side paddings, the 1px borders, and the scrollbar
  /// clearance.
  double get _tileWidth => _frameWidth - 26 - _extraRightPadding;

  @override
  void initState() {
    super.initState();
    _lastCurrent = widget.viewerController.currentPage;
    widget.viewerController.addListener(_onViewerChanged);
    _preferences.addListener(_onPreferences);
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
    // scrolling the strip re-prioritizes the shared render queue toward the
    // tiles that just came into view
    _scroll.addListener(_onScroll);
    _attachDrop(widget.fileDropController);
  }

  @override
  void didUpdateWidget(PdfThumbnailSidebar old) {
    super.didUpdateWidget(old);
    if (!identical(old.fileDropController, widget.fileDropController)) {
      _detachDrop(old.fileDropController);
      _attachDrop(widget.fileDropController);
    }
    if (!identical(old.viewerController, widget.viewerController)) {
      old.viewerController.removeListener(_onViewerChanged);
      widget.viewerController.addListener(_onViewerChanged);
      _lastCurrent = widget.viewerController.currentPage;
    }
    if (!identical(old.controller.preferences, _preferences)) {
      old.controller.preferences.removeListener(_onPreferences);
      _preferences.addListener(_onPreferences);
    }
    // a different edit session brings its own (empty) shared cache, so the
    // old session's warm prerender must be withdrawn from the old cache -
    // [build] re-arms it against the new one
    if (!identical(old.controller, widget.controller)) {
      old.controller.thumbnailCache.clearWarm(this);
    }
  }

  @override
  void dispose() {
    _detachDrop(widget.fileDropController);
    widget.viewerController.removeListener(_onViewerChanged);
    _preferences.removeListener(_onPreferences);
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    // the cache outlives the panel (it belongs to the session), so only
    // withdraw this strip's background warm - don't dispose it
    _cache.clearWarm(this);
    _scroll.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _attachDrop(PdfThumbnailDropController? drop) {
    drop
      ?..attachPanel(_dropResolver)
      ..addListener(_onDropChanged);
  }

  void _detachDrop(PdfThumbnailDropController? drop) {
    drop
      ?..removeListener(_onDropChanged)
      ..detachPanel(_dropResolver);
  }

  /// The drag moved (or ended): repaint so the insertion marker follows it.
  void _onDropChanged() {
    if (mounted) setState(() {});
  }

  /// Where a PDF dropped at [globalPosition] would be inserted - the slot
  /// between the tiles nearest the pointer. Null when the point misses the
  /// strip, or when the strip can't take structural page edits at all.
  int? _dropIndexAt(Offset globalPosition) {
    if (!mounted || !widget.allowPageEditing) return null;
    return pdfThumbnailDropIndexAt(
      panelContext: context,
      tileKeys: _tileKeys,
      pageCount: widget.controller.document.pageCount,
      axis: Axis.vertical,
      globalPosition: globalPosition,
    );
  }

  void _onPreferences() {
    if (mounted) setState(() {});
  }

  /// The gate the shared cache's background warm consults: true while the
  /// viewer still has foreground page work in flight. See
  /// [PdfThumbnailCache.bindForegroundGate].
  bool _viewerRenderBusy() => widget.viewerController.isPageRenderBusy;

  /// Pushes the strip's scroll position into the shared cache as the render
  /// focus, so the tiles nearest the visible band render before the rest.
  void _onScroll() {
    if (!_scroll.hasClients) return;
    _cache.focus = _thumbnailFocusFromScroll(
        _scroll, widget.controller.document.pageCount);
  }

  void _onViewerChanged() {
    final current = widget.viewerController.currentPage;
    if (current == _lastCurrent) return;
    _lastCurrent = current;
    // the strip follows the viewer; bias the render queue to the page the
    // viewer just moved to even before the reveal scroll settles
    _cache.focus = current;
    if (widget.followsViewer) _revealPage(current);
  }

  /// Renders one page's thumbnail straight into the shared cache - the idle
  /// background fill of every page (see [PdfThumbnailCache.setWarm]). Renders
  /// at the lower warm worker priority and declines the UI-thread fallback,
  /// so a tile the user is looking at always preempts it; a page another
  /// surface (a tile, the grid) already rendered is skipped.
  Future<void> _warmRender(int index, int pixelWidth) async {
    final controller = widget.controller;
    if (index >= controller.document.pageCount) return;
    final cache = _cache;
    final key = thumbnailKey(controller, index, widget.pageColor,
        widget.showAnnotations, pixelWidth);
    if (cache.contains(key)) return;
    final image = await rasterizeThumbnail(
      controller: controller,
      pageIndex: index,
      pageColor: widget.pageColor,
      annotations: widget.showAnnotations,
      pixelWidth: pixelWidth,
      worker: widget.renderWorker,
      priority: 3,
      skipIfWorkerDeclines: true,
      deferUiWork: _viewerRenderBusy,
      reason: 'warm',
      disk: controller.pageRenderStamp(index) == 0 ? cache.disk : null,
    );
    if (image == null) return;
    PdfThumbnailSidebar.debugRasterizations++;
    cache.put(key, image);
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
    // edge - together they scroll the minimal distance
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

  @override
  Widget build(BuildContext context) {
    return PdfSidebarPanelFrame(
      width: widget.width,
      minWidth: widget.minWidth,
      maxWidth: widget.maxWidth,
      persistedWidth: _preferences.thumbnailSidebarWidth,
      onPersistWidth: (width) => _preferences.thumbnailSidebarWidth = width,
      dock: widget.dock,
      panel: PdfDockablePanel.thumbnails,
      resizable: widget.resizable,
      bottomSheet: widget.bottomSheet,
      gripKey: const ValueKey('pdf-thumbnail-resize-grip'),
      onClose: widget.onClose,
      builder: _buildFrame,
    );
  }

  Widget _buildFrame(
    BuildContext context,
    PdfSidebarPanelGeometry geometry,
  ) {
    _frameGeometry = geometry;
    final width = geometry.width;
    final controller = widget.controller;
    // persist thumbnails to disk (bound to this document) so a later session
    // opens onto already-rendered pages instead of re-interpreting them
    _cache.disk = widget.rasterCache;
    // (re)arm the idle background prerender of every page into the shared
    // cache, at the resolution this strip renders, so the page grid and
    // scrolling back open onto already-cached thumbnails. A paced loop that
    // yields to every visible tile, so it never delays one.
    final pixelWidth =
        _thumbnailBucket(_tileWidth * MediaQuery.devicePixelRatioOf(context));
    // ...and hold it off entirely while the viewer is rendering: the warm's
    // replay/rasterize run on the platform thread, so a lower worker priority
    // alone still lets it land on the frame the visible page needs (#603).
    _cache.bindForegroundGate(
        widget.viewerController.pageRenderActivity, _viewerRenderBusy);
    if (pdfShouldWarmThumbnails(controller.document.pageCount)) {
      _cache.setWarm(
        this,
        controller.document.pageCount,
        '$pixelWidth|${widget.pageColor.toARGB32()}|${widget.showAnnotations}',
        (index) => _warmRender(index, pixelWidth),
      );
    } else {
      // On web, rasterizing even a 128 px thumbnail replays the entire vector
      // picture through CanvasKit and can monopolize the platform thread for
      // hundreds of milliseconds. Long documents use on-demand tiles plus
      // the viewer's already-cached soft previews instead of speculatively
      // paying that cost for every off-screen page.
      _cache.clearWarm(this);
      _cache.bindForegroundGate(
          widget.viewerController.pageRenderActivity, _viewerRenderBusy);
    }
    // pages a shift-click would select from the current hover - painted as
    // a ghost of the selection chip while Shift is held
    final rangePreview = _rangePreview;
    // a bottom sheet supplies its own width and resize affordance, so the
    // strip drops the side resize grip; the tile column keeps its preferred
    // width, centered in the wider sheet rather than stretched
    // [inset] centers the tile column inside a full-width parent: in a
    // bottom sheet the list fills the whole sheet (so a drag anywhere in
    // it scrolls - not just over the narrow tile column) and the inset is
    // baked into the list's own horizontal padding, which keeps the
    // scroll viewport full-width while the tiles stay centered.
    Widget buildList(double inset) => CallbackShortcuts(
          bindings: _keyboardShortcuts,
          child: Focus(
            focusNode: _focusNode,
            autofocus: true,
            child: Material(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              // only document changes rebuild the list - viewer scrolling
              // repaints the per-tile indicators alone
              child: ListenableBuilder(
                listenable: controller,
                // the implicit desktop scrollbar is replaced by the
                // viewer-style bar below
                builder: (context, _) {
                  // the tile a paste would land after while the mouse hovers -
                  // marked with an insertion bar. Computed here, inside the
                  // controller's builder, so filling/clearing the clipboard
                  // (a controller notification) re-evaluates it.
                  final pasteInsertionPage = _pasteInsertionPage;
                  // ...and the slot an external PDF being dragged over the
                  // strip would drop into. The marker rides the top edge of
                  // the tile the pages would land before - or the bottom
                  // edge of the last tile for a drop past the end.
                  final dropIndex = widget.fileDropController
                      ?.indicatorIndexFor(_dropResolver);
                  final pageCount = controller.document.pageCount;
                  return Column(
                    children: [
                      // page-level file actions sit in a slim header at the top so
                      // they never collide with the floating editing toolbar (or a
                      // snackbar) that hugs the bottom of the viewport. The slot is
                      // a fixed height and always present, so swapping in the bulk-
                      // action bar when 2+ pages are selected never reflows the
                      // tiles below (a single selection is just the navigation
                      // cursor - the per-tile delete handles it).
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                            8 + inset, 2, _extraRightPadding + inset, 2),
                        child: SizedBox(
                          height: 36,
                          child: Row(
                            children: [
                              Expanded(
                                child: controller.selectedPageCount > 1
                                    ? _PageSelectionBar(
                                        controller: controller,
                                        allowPageEditing:
                                            widget.allowPageEditing,
                                        onExportPages: widget.onExportPages,
                                        compact: true,
                                      )
                                    : Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              pdfL10n(context).thumbPages,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelMedium,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (widget.onPickPdfToInsert !=
                                                  null ||
                                              widget.onExportPages != null ||
                                              (widget.allowPageEditing &&
                                                  controller.hasPageClipboard))
                                            _PageActionsButton(
                                              controller: controller,
                                              viewerController:
                                                  widget.viewerController,
                                              allowPageEditing:
                                                  widget.allowPageEditing,
                                              onPickPdfToInsert:
                                                  widget.onPickPdfToInsert,
                                              onExportPages:
                                                  widget.onExportPages,
                                            ),
                                        ],
                                      ),
                              ),
                              // the drag-to-redock handle and the docked
                              // strip's close button; a bottom sheet supplies
                              // its own close in its sheet chrome
                              if (geometry.moveHandle(
                                key: const ValueKey('pdf-thumbnail-panel-move'),
                              )
                                  case final moveHandle?)
                                moveHandle,
                              if (geometry.closeButton(
                                key:
                                    const ValueKey('pdf-thumbnail-panel-close'),
                              )
                                  case final closeButton?)
                                closeButton,
                            ],
                          ),
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
                            onReorderStart: (index) =>
                                setState(() => _reorderPage = index),
                            onReorderEnd: (_) {
                              if (mounted) setState(() => _reorderPage = null);
                            },
                            proxyDecorator: (child, index, animation) {
                              final count = controller.isPageSelected(index)
                                  ? controller.selectedPageCount
                                  : 1;
                              return count > 1
                                  ? _MultiPageDragProxy(
                                      count: count, child: child)
                                  : child;
                            },
                            onReorderItem: controller.movePage,
                            itemBuilder: (context, index) {
                              Widget tile = _PageTile(
                                key: _tileKeys[index] ??= GlobalKey(),
                                controller: controller,
                                viewerController: widget.viewerController,
                                pageIndex: index,
                                pageColor: widget.pageColor,
                                showAnnotations: widget.showAnnotations,
                                allowPageEditing: widget.allowPageEditing,
                                onExportPages: widget.onExportPages,
                                cache: _cache,
                                tileWidth: _tileWidth,
                                renderWorker: widget.renderWorker,
                                inRangePreview: rangePreview.contains(index),
                                showPasteIndicator: pasteInsertionPage == index,
                                dropEdge: _tileDropEdge(
                                  dropIndex,
                                  index,
                                  pageCount,
                                  Axis.vertical,
                                ),
                                showPageActions:
                                    !pdfPanelControlsRevealOnHover() ||
                                        _hoverPage == index,
                                onHover: (hovering) =>
                                    _setHover(index, hovering),
                                onFocusPage: _focusPage,
                              );
                              if (_reorderPage != null &&
                                  index != _reorderPage &&
                                  controller.isPageSelected(_reorderPage!) &&
                                  controller.isPageSelected(index)) {
                                tile = Opacity(
                                  key: ValueKey(
                                      'pdf-thumbnail-reorder-companion-$index'),
                                  opacity: 0.35,
                                  child: tile,
                                );
                              }
                              // without the drag listener no reorder can ever start
                              return widget.allowPageEditing
                                  ? _ReorderDragStartListener(
                                      key: ValueKey(index),
                                      index: index,
                                      child: tile)
                                  : KeyedSubtree(
                                      key: ValueKey(index), child: tile);
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
                            label: Text(pdfL10n(context).thumbAddPage),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              textStyle:
                                  Theme.of(context).textTheme.labelMedium,
                            ),
                            onPressed: () => controller.addBlankPage(),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
    // the same scrollbar the viewer paints, so every bar in the chrome
    // looks and behaves alike
    final scrollbar = PdfScrollbar(
      scroll: _scroll,
      thumbKey: const ValueKey('pdf-thumbnail-scrollbar-thumb'),
    );
    // an outline around the whole strip while a file drag hovers it, so the
    // panel reads as the drop target the per-tile marker is aiming into
    final dropOutline =
        widget.fileDropController?.indicatorIndexFor(_dropResolver) == null
            ? null
            : Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    key: const ValueKey('pdf-thumbnail-drop-outline'),
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: Theme.of(context).colorScheme.primary,
                          width: 2),
                    ),
                  ),
                ),
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
          if (dropOutline != null) dropOutline,
        ]);
      });
    }

    return Stack(children: [
      Positioned.fill(child: buildList(0)),
      // stepped off the resize grip when the grip rides the same
      // (right) edge
      Positioned(
        top: 0,
        bottom: 0,
        right: geometry.scrollbarInset,
        child: scrollbar,
      ),
      if (dropOutline != null) dropOutline,
    ]);
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
    this.compact = false,
  });

  final PdfEditingController controller;
  final bool allowPageEditing;
  final void Function(Uint8List bytes)? onExportPages;

  /// A single-row layout (count + a horizontally-scrollable action group)
  /// that fits a fixed-height header slot - the docked strip swaps it in
  /// for the "Pages" header so a selection never reflows the tiles. The
  /// full-area grid leaves it false for the roomier two-row layout.
  final bool compact;

  /// A compact icon button - tight enough that several fit (and wrap)
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
    final actions = <Widget>[
      if (allowPageEditing) ...[
        _action(
          key: 'pdf-thumbnail-rotate-selected-ccw',
          icon: Icons.rotate_left,
          tooltip: pdfL10n(context).thumbRotateSelectedLeft,
          onPressed: () => controller.rotateSelectedPages(-90),
        ),
        _action(
          key: 'pdf-thumbnail-rotate-selected-cw',
          icon: Icons.rotate_right,
          tooltip: pdfL10n(context).thumbRotateSelectedRight,
          onPressed: () => controller.rotateSelectedPages(90),
        ),
      ],
      if (allowPageEditing) ...[
        _action(
          key: 'pdf-thumbnail-copy-selected',
          icon: Icons.copy_outlined,
          tooltip: pdfL10n(context).thumbCopySelectedPages,
          onPressed: () => controller.copySelectedPages(),
        ),
        _action(
          key: 'pdf-thumbnail-cut-selected',
          icon: Icons.content_cut,
          tooltip: pdfL10n(context).thumbCutSelectedPages,
          onPressed: () => controller.cutSelectedPages(),
        ),
      ],
      if (onExportPages != null)
        _action(
          key: 'pdf-thumbnail-export-selected',
          icon: Icons.file_download_outlined,
          tooltip: pdfL10n(context).thumbExportSelectedPages,
          onPressed: _exportSelected,
        ),
      if (allowPageEditing)
        _action(
          key: 'pdf-thumbnail-delete-selected',
          icon: Icons.delete_outline,
          tooltip: pdfL10n(context).thumbDeleteSelectedPages,
          onPressed: () => controller.removeSelectedPages(),
        ),
      _action(
        key: 'pdf-thumbnail-clear-selection',
        icon: Icons.close,
        tooltip: pdfL10n(context).thumbClearSelection,
        onPressed: controller.clearPageSelection,
      ),
    ];
    final count = Text(
      pdfL10n(context).thumbSelectedCount(controller.selectedPageCount),
      style: Theme.of(context).textTheme.labelMedium,
      overflow: TextOverflow.ellipsis,
    );
    // the strip's fixed-height header slot: one row, the actions scrolling
    // horizontally so a narrow strip never overflows (and never reflows
    // the tiles when the bar swaps in for the "Pages" header)
    if (compact) {
      return Row(
        children: [
          Flexible(child: count),
          const SizedBox(width: 4),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(mainAxisSize: MainAxisSize.min, children: actions),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        count,
        // a Wrap (not a Row) so the action buttons flow onto a second
        // line on the narrow strip instead of overflowing
        Wrap(children: actions),
      ],
    );
  }
}

/// Which edge of tile [index] carries the file-drop insertion marker for a
/// drag currently aimed at slot [dropIndex] (null: no drag over this
/// panel). The marker leads the tile the dropped pages would land before -
/// or trails the last tile when they'd go past the end - so it always
/// paints in the gap the pages will fill. [reversed] flips the horizontal
/// edges for a right-to-left grid.
PdfThumbnailDropEdge? _tileDropEdge(
  int? dropIndex,
  int index,
  int pageCount,
  Axis axis, {
  bool reversed = false,
}) {
  if (dropIndex == null) return null;
  final leading = axis == Axis.vertical
      ? PdfThumbnailDropEdge.top
      : (reversed ? PdfThumbnailDropEdge.right : PdfThumbnailDropEdge.left);
  final trailing = axis == Axis.vertical
      ? PdfThumbnailDropEdge.bottom
      : (reversed ? PdfThumbnailDropEdge.left : PdfThumbnailDropEdge.right);
  if (dropIndex == index) return leading;
  if (dropIndex >= pageCount && index == pageCount - 1) return trailing;
  return null;
}

enum _PageAction { paste, insert, export }

const _densePopupMenuHeight = 34.0;

TextStyle? _densePopupTextStyle(BuildContext context, {Color? color}) =>
    Theme.of(context).textTheme.labelMedium?.copyWith(
          color: color,
          height: 1.1,
        );

/// The thumbnail strip's page-document actions: insert the pages of
/// another PDF (after the current page) and export a page range to a
/// standalone PDF. Both need the host for file I/O - [onPickPdfToInsert]
/// supplies the bytes to merge in, [onExportPages] receives the exported
/// bytes - so a menu item only appears when its callback is given.
class _PageActionsButton extends StatelessWidget {
  const _PageActionsButton({
    required this.controller,
    required this.viewerController,
    required this.allowPageEditing,
    this.onPickPdfToInsert,
    this.onExportPages,
  });

  final PdfEditingController controller;
  final PdfViewerController viewerController;

  /// Whether structural page edits (paste, insert) are offered - a
  /// read-only strip drops them and keeps only Export.
  final bool allowPageEditing;
  final Future<Uint8List?> Function()? onPickPdfToInsert;
  final void Function(Uint8List bytes)? onExportPages;

  void _paste() {
    // paste the shared clipboard's pages after the current page, then
    // scroll there so the reader sees what landed
    final pastedAt = viewerController.currentPage + 1;
    if (controller.pastePages(at: pastedAt)) {
      unawaited(_jumpToInsertedPage(viewerController, pastedAt));
    }
  }

  Future<void> _insert(BuildContext context) async {
    final pick = onPickPdfToInsert;
    if (pick == null) return;
    // read everything off the context BEFORE the async gap
    final messenger = ScaffoldMessenger.maybeOf(context);
    final margin = pdfFloatingToastMargin(context);
    final failedMessage = pdfL10n(context).thumbInsertFileFailed;
    final bytes = await pick();
    if (bytes == null) return;
    try {
      final insertedAt = viewerController.currentPage + 1;
      controller.insertPagesFromBytes(bytes, at: insertedAt);
      // A page-count change rebuilds the viewer and resets its scroll metrics.
      // Navigate only after that reset so the newly inserted pages stay in
      // view instead of the replacement document opening at page one.
      unawaited(_jumpToInsertedPage(viewerController, insertedAt));
    } catch (_) {
      // a non-PDF, corrupt, or password-protected file can't be opened -
      // tell the user rather than failing silently
      messenger?.showSnackBar(
        SnackBar(
          content: Text(failedMessage),
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
    final canPaste = allowPageEditing && controller.hasPageClipboard;
    final canInsert = onPickPdfToInsert != null;
    final canExport = onExportPages != null;
    return PopupMenuButton<_PageAction>(
      key: const ValueKey('pdf-thumbnail-page-actions'),
      tooltip: pdfL10n(context).thumbPageActions,
      icon: const Icon(Icons.file_copy_outlined, size: 18),
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      onSelected: (action) {
        switch (action) {
          case _PageAction.paste:
            _paste();
          case _PageAction.insert:
            _insert(context);
          case _PageAction.export:
            _export(context);
        }
      },
      itemBuilder: (context) => [
        if (canPaste)
          PopupMenuItem(
            key: const ValueKey('pdf-thumbnail-paste-pages'),
            value: _PageAction.paste,
            height: _densePopupMenuHeight,
            child: Text(
              pdfL10n(context)
                  .thumbPastePages(controller.pageClipboard.pageCount),
              style: _densePopupTextStyle(context),
            ),
          ),
        if (canInsert)
          PopupMenuItem(
            key: const ValueKey('pdf-thumbnail-insert-pdf'),
            value: _PageAction.insert,
            height: _densePopupMenuHeight,
            child: Text(pdfL10n(context).thumbInsertPdf,
                style: _densePopupTextStyle(context)),
          ),
        if (canExport)
          PopupMenuItem(
            key: const ValueKey('pdf-thumbnail-export-pages'),
            value: _PageAction.export,
            height: _densePopupMenuHeight,
            child: Text(pdfL10n(context).thumbExportPagesEllipsis,
                style: _densePopupTextStyle(context)),
          ),
      ],
    );
  }
}

/// A dedicated, full-area page thumbnail grid - the same page controls
/// as [PdfThumbnailSidebar] (click to select a page, double-click to open it,
/// shift/⌘-click
/// multi-select with a bulk-action bar, per-tile rotate/delete, drag to
/// reorder, the page-actions menu, and the Add-page footer), laid out as
/// a reflowing grid whose tile size the header's size control changes.
/// Use it as a page-organizer view in place of the page viewer.
///
/// Unlike the strip, a plain click only selects the page. A double-click
/// scrolls the viewer to that page and fires [onOpenPage] (the host turns
/// the grid off to reveal the page). Shift/⌘ clicks only extend the
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
    this.fileDropController,
    this.onOpenPage,
    this.renderWorker,
    this.rasterCache,
    this.minTileWidth = 96,
    this.maxTileWidth = 360,
    this.defaultTileWidth = 168,
  });

  final PdfEditingController controller;

  /// The viewer a tapped tile scrolls to (see [onOpenPage]).
  final PdfViewerController viewerController;

  /// Offloads tile interpretation to a background isolate - pass the same
  /// worker the viewer uses. See [PdfThumbnailSidebar.renderWorker].
  final PdfRenderWorker? renderWorker;

  /// Optional persistent on-disk thumbnail cache, bound to the open document.
  /// See [PdfThumbnailSidebar.rasterCache].
  final PdfRasterCache? rasterCache;

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

  /// Lets a PDF dragged in from outside the app be dropped between two
  /// tiles, at the marked position in the page order. The host drives the
  /// controller from the platform's drag stream; the grid supplies the
  /// geometry. See [PdfThumbnailDropController].
  final PdfThumbnailDropController? fileDropController;

  /// Called after a double-click scrolls the viewer to [pageIndex]. Hosts
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
  final FocusNode _focusNode = FocusNode(debugLabel: 'PdfThumbnailView');
  final Map<int, GlobalKey> _tileKeys = {};

  /// The session's shared thumbnail cache (and viewport-ordered render
  /// queue) - the same instance the docked strip uses.
  PdfThumbnailCache get _cache => widget.controller.thumbnailCache;

  PdfEditingPreferences get _preferences => widget.controller.preferences;

  /// The tile the mouse is over, tracked while Shift is held so the grid
  /// paints the same range preview as the thumbnail strip.
  int? _hoverPage;

  bool _shiftHeld = HardwareKeyboard.instance.isShiftPressed;
  int? _keyboardPage;
  int? _dragPage;

  /// This grid's hit-test, registered with
  /// [PdfThumbnailView.fileDropController] - a stable closure so attach and
  /// detach agree on identity (see the strip's copy).
  late final PdfThumbnailDropResolver _dropResolver = _dropIndexAt;

  Set<int> get _rangePreview => _shiftHeld && _hoverPage != null
      ? widget.controller.pageRangePreviewTo(_hoverPage!).toSet()
      : const {};

  double get _tileWidth =>
      (_preferences.thumbnailViewTileWidth ?? widget.defaultTileWidth)
          .clamp(widget.minTileWidth, widget.maxTileWidth);

  @override
  void initState() {
    super.initState();
    _preferences.addListener(_onPreferences);
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
    // the grid builds every cell eagerly, so without a viewport focus every
    // page would compete equally; scroll position drives which render first
    _scroll.addListener(_onScroll);
    _attachDrop(widget.fileDropController);
  }

  @override
  void didUpdateWidget(PdfThumbnailView old) {
    super.didUpdateWidget(old);
    if (!identical(old.fileDropController, widget.fileDropController)) {
      _detachDrop(old.fileDropController);
      _attachDrop(widget.fileDropController);
    }
    if (!identical(old.controller.preferences, _preferences)) {
      old.controller.preferences.removeListener(_onPreferences);
      _preferences.addListener(_onPreferences);
    }
    // a different edit session brings its own (empty) shared cache; withdraw
    // the warm prerender from the old one ([build] re-arms the new)
    if (!identical(old.controller, widget.controller)) {
      old.controller.thumbnailCache.clearWarm(this);
    }
  }

  @override
  void dispose() {
    _detachDrop(widget.fileDropController);
    _preferences.removeListener(_onPreferences);
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    // the cache belongs to the session, not this grid - only withdraw its
    // background warm
    _cache.clearWarm(this);
    _scroll.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _attachDrop(PdfThumbnailDropController? drop) {
    drop
      ?..attachPanel(_dropResolver)
      ..addListener(_onDropChanged);
  }

  void _detachDrop(PdfThumbnailDropController? drop) {
    drop
      ?..removeListener(_onDropChanged)
      ..detachPanel(_dropResolver);
  }

  void _onDropChanged() {
    if (mounted) setState(() {});
  }

  /// Where a PDF dropped at [globalPosition] would be inserted: the gap
  /// between the grid cells nearest the pointer, along the reading
  /// direction. Null when the point misses the grid or it is read-only.
  int? _dropIndexAt(Offset globalPosition) {
    if (!mounted || !widget.allowPageEditing) return null;
    return pdfThumbnailDropIndexAt(
      panelContext: context,
      tileKeys: _tileKeys,
      pageCount: widget.controller.document.pageCount,
      axis: Axis.horizontal,
      globalPosition: globalPosition,
      reversed: Directionality.of(context) == TextDirection.rtl,
    );
  }

  void _onPreferences() {
    if (mounted) setState(() {});
  }

  /// The gate the shared cache's background warm consults: true while the
  /// viewer still has foreground page work in flight. See
  /// [PdfThumbnailCache.bindForegroundGate].
  bool _viewerRenderBusy() => widget.viewerController.isPageRenderBusy;

  /// Pushes the grid's scroll position into the shared cache as the render
  /// focus, so the rows on screen render before the rest of the document and
  /// scrolling re-prioritizes toward what just came into view.
  void _onScroll() {
    if (!_scroll.hasClients) return;
    _cache.focus = _thumbnailFocusFromScroll(
        _scroll, widget.controller.document.pageCount);
  }

  bool _onKeyEvent(KeyEvent event) {
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (shift != _shiftHeld && mounted) setState(() => _shiftHeld = shift);
    return false;
  }

  void _setHover(int index, bool hovering) {
    final next = hovering ? index : (_hoverPage == index ? null : _hoverPage);
    if (next == _hoverPage) return;
    _hoverPage = next;
    if ((_shiftHeld || pdfPanelControlsRevealOnHover()) && mounted) {
      setState(() {});
    }
  }

  void _focusPage(int index) {
    _keyboardPage = index;
    _focusNode.requestFocus();
  }

  int _keyboardBase() {
    final selected = widget.controller.selectedPages;
    final count = widget.controller.document.pageCount;
    final base = _keyboardPage ??
        (selected.isNotEmpty
            ? selected.last
            : widget.viewerController.currentPage);
    return base.clamp(0, math.max(0, count - 1)).toInt();
  }

  void _moveKeyboardSelection(int delta) {
    final count = widget.controller.document.pageCount;
    if (count == 0) return;
    final target = (_keyboardBase() + delta).clamp(0, count - 1).toInt();
    _focusPage(target);
    if (HardwareKeyboard.instance.isShiftPressed) {
      widget.controller.selectPageRange(target);
    } else {
      widget.controller.selectPage(target);
    }
    _cache.focus = target;
    _revealPage(target);
  }

  /// The pages a copy/cut shortcut acts on: the grid's selection, or the
  /// keyboard/current page when nothing is selected.
  List<int> _clipboardTargets() {
    final selected = widget.controller.selectedPages;
    if (selected.isNotEmpty) return selected;
    if (widget.controller.document.pageCount == 0) return const [];
    return [_keyboardBase()];
  }

  void _copyPages() => widget.controller.copyPages(_clipboardTargets());

  void _cutPages() => widget.controller.cutPages(_clipboardTargets());

  /// Pastes the shared clipboard's pages after the selection (or the
  /// keyboard/current page) and reveals where they landed.
  void _pastePages() {
    final selected = widget.controller.selectedPages;
    final at = (selected.isNotEmpty ? selected.last : _keyboardBase()) + 1;
    if (!widget.controller.pastePages(at: at)) return;
    _focusPage(at);
    _revealPage(at);
  }

  /// Deletes the grid's selection, or the keyboard/current page when
  /// nothing is selected - the last remaining page is kept either way.
  void _deletePages() {
    if (widget.controller.hasPageSelection) {
      widget.controller.removeSelectedPages();
    } else if (widget.controller.document.pageCount > 0) {
      widget.controller.removePage(_keyboardBase());
    }
  }

  Map<ShortcutActivator, VoidCallback> _keyboardShortcuts(int columns) => {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _moveKeyboardSelection(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _moveKeyboardSelection(1),
        SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _moveKeyboardSelection(-columns),
        SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _moveKeyboardSelection(columns),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true): () =>
            _moveKeyboardSelection(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true): () =>
            _moveKeyboardSelection(1),
        SingleActivator(LogicalKeyboardKey.arrowUp, shift: true): () =>
            _moveKeyboardSelection(-columns),
        SingleActivator(LogicalKeyboardKey.arrowDown, shift: true): () =>
            _moveKeyboardSelection(columns),
        if (widget.allowPageEditing) ...{
          const SingleActivator(LogicalKeyboardKey.keyC, meta: true):
              _copyPages,
          const SingleActivator(LogicalKeyboardKey.keyC, control: true):
              _copyPages,
          const SingleActivator(LogicalKeyboardKey.keyX, meta: true): _cutPages,
          const SingleActivator(LogicalKeyboardKey.keyX, control: true):
              _cutPages,
          const SingleActivator(LogicalKeyboardKey.keyV, meta: true):
              _pastePages,
          const SingleActivator(LogicalKeyboardKey.keyV, control: true):
              _pastePages,
          const SingleActivator(LogicalKeyboardKey.delete): _deletePages,
          const SingleActivator(LogicalKeyboardKey.backspace): _deletePages,
        },
      };

  void _revealPage(int index) {
    final context = _tileKeys[index]?.currentContext;
    if (context == null) return;
    for (final policy in const [
      ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      ScrollPositionAlignmentPolicy.keepVisibleAtStart,
    ]) {
      unawaited(Scrollable.ensureVisible(context,
          alignmentPolicy: policy,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic));
    }
  }

  /// Renders one page's thumbnail straight into the shared cache - the idle
  /// background fill (see [PdfThumbnailCache.setWarm]). Lower worker priority
  /// and no UI-thread fallback, so a visible tile always preempts it.
  Future<void> _warmRender(int index, int pixelWidth) async {
    final controller = widget.controller;
    if (index >= controller.document.pageCount) return;
    final cache = _cache;
    final key = thumbnailKey(controller, index, widget.pageColor,
        widget.showAnnotations, pixelWidth);
    if (cache.contains(key)) return;
    final image = await rasterizeThumbnail(
      controller: controller,
      pageIndex: index,
      pageColor: widget.pageColor,
      annotations: widget.showAnnotations,
      pixelWidth: pixelWidth,
      worker: widget.renderWorker,
      priority: 3,
      skipIfWorkerDeclines: true,
      deferUiWork: _viewerRenderBusy,
      reason: 'warm',
      disk: controller.pageRenderStamp(index) == 0 ? cache.disk : null,
    );
    if (image == null) return;
    PdfThumbnailSidebar.debugRasterizations++;
    cache.put(key, image);
  }

  void _openPage(int index) {
    unawaited(widget.viewerController.jumpToPage(index));
    widget.onOpenPage?.call(index);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final tileWidth = _tileWidth;
    // persist thumbnails to disk (bound to this document) so a re-opened grid
    // loads already-rendered pages instead of re-interpreting them
    _cache.disk = widget.rasterCache;
    // (re)arm the idle background prerender of every page at the cell's
    // thumbnail resolution (the tile pads ~21px around the thumbnail). A
    // paced loop that yields to every visible cell, so it never delays one.
    final pixelWidth = _thumbnailBucket(
        (tileWidth - 21) * MediaQuery.devicePixelRatioOf(context));
    // see the strip's copy: the warm stands down while the viewer renders
    _cache.bindForegroundGate(
        widget.viewerController.pageRenderActivity, _viewerRenderBusy);
    if (pdfShouldWarmThumbnails(controller.document.pageCount)) {
      _cache.setWarm(
        this,
        controller.document.pageCount,
        '$pixelWidth|${widget.pageColor.toARGB32()}|${widget.showAnnotations}',
        (index) => _warmRender(index, pixelWidth),
      );
    } else {
      _cache.clearWarm(this);
      _cache.bindForegroundGate(
          widget.viewerController.pageRenderActivity, _viewerRenderBusy);
    }
    // the scrollbar overlays the grid's right edge; keep content clear of it
    const barClearance = PdfScrollbar.hitExtent;
    return LayoutBuilder(builder: (context, constraints) {
      final gridWidth = math.max(0, constraints.maxWidth - 24 - barClearance);
      final columns =
          math.max(1, ((gridWidth + 12) / (tileWidth + 12)).floor());
      // opaque so the grid eats every pointer in its area - a host overlays it
      // over the live viewer, and a tap in a header/inter-tile gap must not
      // fall through to the page underneath
      return CallbackShortcuts(
        bindings: _keyboardShortcuts(columns),
        child: Focus(
          focusNode: _focusNode,
          autofocus: true,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            child: Material(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              // only document changes rebuild the grid - viewer scrolling
              // repaints the per-tile viewport indicators alone
              child: ListenableBuilder(
                listenable: controller,
                builder: (context, _) {
                  final rangePreview = _rangePreview;
                  // the slot an external PDF being dragged over the grid
                  // would drop into - marked on the leading edge of the
                  // cell its pages would land before
                  final dropIndex = widget.fileDropController
                      ?.indicatorIndexFor(_dropResolver);
                  final rtl = Directionality.of(context) == TextDirection.rtl;
                  return Column(
                    children: [
                      // header: title, the tile-size control, and the page-actions menu
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                            12, 6, 4 + barClearance, 4),
                        child: Row(children: [
                          Expanded(
                            child: controller.selectedPageCount > 1
                                ? _PageSelectionBar(
                                    controller: controller,
                                    allowPageEditing: widget.allowPageEditing,
                                    onExportPages: widget.onExportPages,
                                    compact: true,
                                  )
                                : Text(pdfL10n(context).thumbPages,
                                    style:
                                        Theme.of(context).textTheme.titleSmall,
                                    overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(width: 8),
                          _ThumbnailSizeControl(
                            value: tileWidth,
                            min: widget.minTileWidth,
                            max: widget.maxTileWidth,
                            onChanged: (value) =>
                                _preferences.thumbnailViewTileWidth = value,
                          ),
                          if (widget.onPickPdfToInsert != null ||
                              widget.onExportPages != null ||
                              (widget.allowPageEditing &&
                                  controller.hasPageClipboard))
                            _PageActionsButton(
                              controller: controller,
                              viewerController: widget.viewerController,
                              allowPageEditing: widget.allowPageEditing,
                              onPickPdfToInsert: widget.onPickPdfToInsert,
                              onExportPages: widget.onExportPages,
                            ),
                        ]),
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
                                      KeyedSubtree(
                                        key: _tileKeys[i] ??= GlobalKey(),
                                        child: SizedBox(
                                          key: ValueKey(
                                              'pdf-thumbnail-grid-cell-$i'),
                                          width: tileWidth,
                                          child: _GridPageCell(
                                            controller: controller,
                                            viewerController:
                                                widget.viewerController,
                                            pageIndex: i,
                                            pageColor: widget.pageColor,
                                            showAnnotations:
                                                widget.showAnnotations,
                                            allowPageEditing:
                                                widget.allowPageEditing,
                                            onExportPages: widget.onExportPages,
                                            cache: _cache,
                                            // the tile pads ~21px around the thumbnail
                                            tileWidth: tileWidth - 21,
                                            renderWorker: widget.renderWorker,
                                            onActivatePage: _openPage,
                                            inRangePreview:
                                                rangePreview.contains(i),
                                            dropEdge: _tileDropEdge(
                                              dropIndex,
                                              i,
                                              controller.document.pageCount,
                                              Axis.horizontal,
                                              reversed: rtl,
                                            ),
                                            showPageActions:
                                                !pdfPanelControlsRevealOnHover() ||
                                                    _hoverPage == i,
                                            onHover: (hovering) =>
                                                _setHover(i, hovering),
                                            onFocusPage: _focusPage,
                                            dimmed: _dragPage != null &&
                                                i != _dragPage &&
                                                controller.isPageSelected(
                                                    _dragPage!) &&
                                                controller.isPageSelected(i),
                                            onDragStarted: () =>
                                                setState(() => _dragPage = i),
                                            onDragEnded: () {
                                              if (mounted) {
                                                setState(
                                                    () => _dragPage = null);
                                              }
                                            },
                                          ),
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
                              thumbKey: const ValueKey(
                                  'pdf-thumbnail-view-scrollbar-thumb'),
                            ),
                          ),
                          // the grid reads as the drop target while a file
                          // drag hovers it
                          if (dropIndex != null)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: DecoratedBox(
                                  key: const ValueKey(
                                      'pdf-thumbnail-view-drop-outline'),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                      width: 2,
                                    ),
                                  ),
                                ),
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
                            label: Text(pdfL10n(context).thumbAddPage),
                            onPressed: () => controller.addBlankPage(),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
    });
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
/// moves the page there ([PdfEditingController.movePage]); if that page is
/// part of a multi-page selection, the entire selection moves together.
/// With [allowPageEditing] off the cell is the bare tile - read-only grids
/// only navigate.
class _GridPageCell extends StatefulWidget {
  const _GridPageCell({
    required this.controller,
    required this.viewerController,
    required this.pageIndex,
    required this.pageColor,
    required this.showAnnotations,
    required this.allowPageEditing,
    required this.onExportPages,
    required this.cache,
    required this.tileWidth,
    required this.renderWorker,
    required this.onActivatePage,
    required this.dimmed,
    required this.onDragStarted,
    required this.onDragEnded,
    this.inRangePreview = false,
    this.dropEdge,
    this.showPageActions = true,
    this.onHover,
    this.onFocusPage,
  });

  final PdfEditingController controller;
  final PdfViewerController viewerController;
  final int pageIndex;
  final Color pageColor;
  final bool showAnnotations;
  final bool allowPageEditing;
  final void Function(Uint8List bytes)? onExportPages;
  final PdfThumbnailCache cache;
  final double tileWidth;
  final PdfRenderWorker? renderWorker;
  final void Function(int pageIndex) onActivatePage;
  final bool dimmed;
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnded;
  final bool inRangePreview;

  /// The edge carrying the file-drop insertion marker, if this cell is the
  /// one the hovering drag would insert against. See [_PageTile.dropEdge].
  final PdfThumbnailDropEdge? dropEdge;
  final bool showPageActions;
  final void Function(bool hovering)? onHover;
  final void Function(int pageIndex)? onFocusPage;

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
        onExportPages: widget.onExportPages,
        cache: widget.cache,
        tileWidth: widget.tileWidth,
        renderWorker: widget.renderWorker,
        onActivatePage: widget.onActivatePage,
        activateOnTap: false,
        inRangePreview: widget.inRangePreview,
        dropEdge: widget.dropEdge,
        showPageActions: widget.showPageActions,
        onHover: widget.onHover,
        onFocusPage: widget.onFocusPage,
      );

  @override
  Widget build(BuildContext context) {
    final tile = _tile();
    if (!widget.allowPageEditing) return tile;

    final draggable = AnimatedOpacity(
      key: ValueKey('pdf-thumbnail-grid-reorder-companion-${widget.pageIndex}'),
      opacity: widget.dimmed ? 0.35 : 1,
      duration: const Duration(milliseconds: 120),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hasMouse = true),
        onExit: (_) => setState(() => _hasMouse = false),
        child: _draggable(tile),
      ),
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
        // cell a drop would land on - DecoratedBox paints it over the tile
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
    final selectedCount = widget.controller.isPageSelected(widget.pageIndex)
        ? widget.controller.selectedPageCount
        : 0;
    final feedback = _DragFeedback(
      label: selectedCount > 1
          ? _dragPageCountLabel(context, selectedCount)
          : pdfL10n(context).thumbPageNumber(widget.pageIndex + 1),
      width: widget.tileWidth,
    );
    // dim the page being dragged in place, leaving a gap-marker
    final placeholder = Opacity(opacity: 0.3, child: tile);
    return _hasMouse
        ? Draggable<int>(
            data: widget.pageIndex,
            onDragStarted: widget.onDragStarted,
            onDragEnd: (_) => widget.onDragEnded(),
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: feedback,
            childWhenDragging: placeholder,
            child: tile,
          )
        : LongPressDraggable<int>(
            data: widget.pageIndex,
            onDragStarted: widget.onDragStarted,
            onDragEnd: (_) => widget.onDragEnded(),
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: feedback,
            childWhenDragging: placeholder,
            child: tile,
          );
  }
}

String _dragPageCountLabel(BuildContext context, int count) =>
    '$count ${pdfL10n(context).thumbPages.toLowerCase()}';

/// Marks the reorder proxy as representing every selected page rather than
/// only the thumbnail under the pointer.
class _MultiPageDragProxy extends StatelessWidget {
  const _MultiPageDragProxy({required this.count, required this.child});

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          Positioned(
            top: 8,
            right: 8,
            child: Material(
              key: const ValueKey('pdf-thumbnail-reorder-count'),
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(16),
              elevation: 3,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: Text(
                  _dragPageCountLabel(context, count),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
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
/// expectation - a mouse drag never means scrolling) but only after a
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
        // a right- or middle-click is for the context menu, not a reorder
        // drag - let the tile's secondary-tap recognizer have the pointer
        if (event.kind == PointerDeviceKind.mouse &&
            event.buttons != kPrimaryButton) {
          return;
        }
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
class _PageTile extends StatefulWidget {
  const _PageTile({
    super.key,
    required this.controller,
    required this.viewerController,
    required this.pageIndex,
    required this.pageColor,
    required this.showAnnotations,
    required this.allowPageEditing,
    required this.onExportPages,
    required this.cache,
    required this.tileWidth,
    required this.renderWorker,
    this.onActivatePage,
    this.activateOnTap = true,
    this.inRangePreview = false,
    this.showPasteIndicator = false,
    this.dropEdge,
    this.showPageActions = true,
    this.onHover,
    this.onFocusPage,
  });

  final PdfEditingController controller;
  final PdfViewerController viewerController;
  final int pageIndex;
  final Color pageColor;
  final bool showAnnotations;
  final bool allowPageEditing;
  final void Function(Uint8List bytes)? onExportPages;
  final PdfThumbnailCache cache;
  final double tileWidth;
  final PdfRenderWorker? renderWorker;

  /// Whether a shift-click on this tile would add it to the selection
  /// right now - painted as a faint preview of the selection chip while
  /// the strip's Shift hover is live. Ignored when already [selected].
  final bool inRangePreview;

  /// Whether to paint a paste-insertion bar along this tile's bottom edge:
  /// the strip sets it on the tile the mouse hovers while the shared page
  /// clipboard has pages, marking where ⌘/Ctrl+V (or the strip's paste)
  /// will drop them - right after this page. The grid leaves it false.
  final bool showPasteIndicator;

  /// The edge to paint a file-drop insertion marker on while a PDF dragged
  /// in from outside the app hovers the panel: the pages would land in the
  /// gap the marker fills. Null (the usual case) paints nothing. See
  /// [PdfThumbnailDropController].
  final PdfThumbnailDropEdge? dropEdge;

  /// The mouse entering (true) or leaving (false) this tile, so the strip
  /// can track the hovered page for its Shift range preview. Null off the
  /// strip (the grid does its own hover handling).
  final void Function(bool hovering)? onHover;

  /// Overrides what a plain tap does after selecting the page. The strip
  /// leaves this null and just scrolls the viewer to the page; the
  /// full-area grid passes a handler for double-click activation. Shift/⌘
  /// clicks are unaffected - they only extend the multi-selection, never
  /// navigate.
  final void Function(int pageIndex)? onActivatePage;

  /// Whether a plain tap should also activate the page. The strip keeps
  /// the historical tap-to-jump behavior; the grid sets this false so a
  /// single click selects and a double-click opens.
  final bool activateOnTap;

  /// Whether per-page action buttons should be visible. Hidden actions
  /// retain their layout space to avoid row shifts on hover.
  final bool showPageActions;

  /// Notifies the owning strip/grid that this page was interacted with,
  /// so its keyboard focus and arrow-navigation anchor follow the tile.
  final void Function(int pageIndex)? onFocusPage;

  @override
  State<_PageTile> createState() => _PageTileState();
}

class _PageTileState extends State<_PageTile> {
  DateTime? _lastPlainTapAt;

  PdfEditingController get controller => widget.controller;
  PdfViewerController get viewerController => widget.viewerController;
  int get pageIndex => widget.pageIndex;
  Color get pageColor => widget.pageColor;
  bool get showAnnotations => widget.showAnnotations;
  bool get allowPageEditing => widget.allowPageEditing;
  void Function(Uint8List bytes)? get onExportPages => widget.onExportPages;
  PdfThumbnailCache get cache => widget.cache;
  double get tileWidth => widget.tileWidth;
  PdfRenderWorker? get renderWorker => widget.renderWorker;
  bool get inRangePreview => widget.inRangePreview;
  bool get showPasteIndicator => widget.showPasteIndicator;
  PdfThumbnailDropEdge? get dropEdge => widget.dropEdge;
  void Function(bool hovering)? get onHover => widget.onHover;
  void Function(int pageIndex)? get onActivatePage => widget.onActivatePage;
  bool get activateOnTap => widget.activateOnTap;
  bool get showPageActions => widget.showPageActions;
  void Function(int pageIndex)? get onFocusPage => widget.onFocusPage;

  /// WCAG-style contrast ratio between two opaque colors.
  static double _contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  /// Tapping a tile selects it for the strip's multi-select and (for a
  /// plain tap) navigates there. Shift extends a range from the anchor;
  /// ⌘/Ctrl toggles the tile in the selection - neither navigates, so the
  /// reader can build a selection without the viewport jumping around.
  void _onTap() {
    onFocusPage?.call(pageIndex);
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isShiftPressed) {
      controller.selectPageRange(pageIndex);
      return;
    }
    if (keyboard.isMetaPressed || keyboard.isControlPressed) {
      controller.togglePageSelection(pageIndex);
      return;
    }
    final now = DateTime.now();
    final doubleClick = !activateOnTap &&
        _lastPlainTapAt != null &&
        now.difference(_lastPlainTapAt!) <= kDoubleTapTimeout;
    _lastPlainTapAt = now;
    controller.selectPage(pageIndex);
    if (!activateOnTap && !doubleClick) return;
    _activate();
  }

  void _activate() {
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
    // a shift-click would add this tile to the selection: paint a fainter
    // version of the selected chip so the would-be range reads ahead of
    // the click. The selected look always wins.
    final preview = inRangePreview && !selected;
    final tile = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onTap,
      // a right-click (or control-click on macOS) opens the page context
      // menu - rotate / duplicate / insert / export / delete - operating
      // on the strip's selection when this tile belongs to it
      onSecondaryTapUp: (details) {
        onFocusPage?.call(pageIndex);
        _showPageTileMenu(
          context: context,
          position: details.globalPosition,
          controller: controller,
          viewerController: viewerController,
          pageIndex: pageIndex,
          allowPageEditing: allowPageEditing,
          onExportPages: onExportPages,
        );
      },
      // a selected tile reads as a primary-framed, tinted chip behind the
      // thumbnail. The 1.5px frame is always laid out (transparent when
      // unselected) and paid back out of the padding, so selecting a tile
      // never nudges its contents - per-tile layout, _tileWidth's -26, and
      // _estimateOffset all still hold (each side still totals 12/4px).
      child: Container(
        // a stable key (never toggles, so it doesn't churn the thumbnail
        // raster) the strip's tests read the chip decoration through
        key: ValueKey('pdf-thumbnail-tile-chip-$pageIndex'),
        padding: const EdgeInsets.fromLTRB(10.5, 2.5, 10.5, 2.5),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.20)
              : (preview ? scheme.primary.withValues(alpha: 0.08) : null),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected
                ? scheme.primary
                : (preview
                    ? scheme.primary.withValues(alpha: 0.45)
                    : Colors.transparent),
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
                        viewerController: viewerController,
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
                    // Devtools overlay: each page's cached tiles (green) and
                    // legacy detail patch (purple), scaled into the thumbnail.
                    Positioned.fill(
                      child: ValueListenableBuilder<bool>(
                        valueListenable: pdfDebugPaintDetailBounds,
                        builder: (context, on, _) {
                          if (!on) return const SizedBox.shrink();
                          final store = PdfPageView.debugTileStoreOverride ??
                              PdfTileStore.instanceOrNull;
                          return ListenableBuilder(
                            listenable: Listenable.merge([
                              PdfDebugDetailRegions.instance,
                              if (store != null) store,
                            ]),
                            builder: (context, _) => IgnorePointer(
                              child: CustomPaint(
                                painter: _DetailBoundsPainter(
                                  store?.debugTileFractionsForPage(pageIndex) ??
                                      const [],
                                  PdfDebugDetailRegions.instance
                                      .patchFractionOf(pageIndex),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    // Devtools overlay: mark the pages whose page-view state
                    // is live (the lazy list's render window) - the pages
                    // whose retained scenes/rasters hold real memory.
                    Positioned.fill(
                      child: ValueListenableBuilder<bool>(
                        valueListenable: pdfDebugShowRenderWindow,
                        builder: (context, on, _) => !on
                            ? const SizedBox.shrink()
                            : ListenableBuilder(
                                listenable: PdfLivePageRegistry.instance,
                                builder: (context, _) => !PdfLivePageRegistry
                                        .instance
                                        .contains(pageIndex)
                                    ? const SizedBox.shrink()
                                    : IgnorePointer(
                                        child: DecoratedBox(
                                          key: ValueKey(
                                              'pdf-thumbnail-live-$pageIndex'),
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                              // teal: live render window
                                              color: const Color(0xCC009688),
                                              width: 2,
                                            ),
                                          ),
                                        ),
                                      ),
                              ),
                      ),
                    ),
                  ]),
                );
              },
            ),
            SizedBox(
              height: 28,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    // the label echoes the selection so the cue carries into
                    // the footer row, below the framed thumbnail
                    child: Text(pdfL10n(context).thumbPageNumber(pageIndex + 1),
                        overflow: TextOverflow.ellipsis,
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: selected ? scheme.primary : null,
                                  fontWeight: selected ? FontWeight.w600 : null,
                                )),
                  ),
                  // No Tooltip on these buttons: a Tooltip is an OverlayPortal,
                  // and an OverlayPortal inside a ReorderableListView item
                  // crashes when the item is reactivated during a layout pass
                  // (the strip's bottom-sheet LayoutBuilder, or a reorder) - it
                  // mutates the overlay's RenderObject mid-layout. A Semantics
                  // label keeps the buttons accessible without one.
                  if (allowPageEditing)
                    Visibility(
                      visible: showPageActions,
                      child: Semantics(
                        label: pdfL10n(context).thumbRotatePageRight,
                        button: true,
                        child: IconButton(
                          key: ValueKey('pdf-thumbnail-rotate-$pageIndex'),
                          icon: const Icon(Icons.rotate_right, size: 16),
                          style: IconButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(28, 28),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () =>
                              controller.rotatePages([pageIndex], 90),
                        ),
                      ),
                    ),
                  if (allowPageEditing && document.pageCount > 1)
                    Visibility(
                      visible: showPageActions,
                      child: Semantics(
                        label: pdfL10n(context).thumbDeletePages(1),
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
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    // an insertion bar hugging the bottom edge marks where a paste would
    // drop the clipboard's pages (right after this page) while the mouse
    // hovers the strip; it never eats a pointer, so tap/drag still work
    Widget content = tile;
    if (showPasteIndicator) {
      content = Stack(
        children: [
          content,
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: _InsertionMarker(
                key: ValueKey('pdf-thumbnail-paste-indicator-$pageIndex'),
                color: scheme.primary,
              ),
            ),
          ),
        ],
      );
    }
    // the same bar, on the edge a file dragged in from outside the app
    // would drop its pages into
    final dropEdge = this.dropEdge;
    if (dropEdge != null) {
      final vertical = dropEdge == PdfThumbnailDropEdge.left ||
          dropEdge == PdfThumbnailDropEdge.right;
      content = Stack(
        children: [
          content,
          Positioned(
            left: dropEdge == PdfThumbnailDropEdge.right ? null : 0,
            right: dropEdge == PdfThumbnailDropEdge.left ? null : 0,
            top: dropEdge == PdfThumbnailDropEdge.bottom ? null : 0,
            bottom: dropEdge == PdfThumbnailDropEdge.top ? null : 0,
            child: IgnorePointer(
              child: _InsertionMarker(
                key: ValueKey(
                    'pdf-thumbnail-drop-indicator-$pageIndex-${dropEdge.name}'),
                color: scheme.primary,
                axis: vertical ? Axis.vertical : Axis.horizontal,
              ),
            ),
          ),
        ],
      );
    }
    final onHover = this.onHover;
    if (onHover == null) return content;
    return MouseRegion(
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      child: content,
    );
  }
}

/// A slim bar with rounded end caps, painted along a page tile's edge to
/// mark where pages will be inserted - a paste (right after the tile it
/// sits under) or a file dragged in from outside the app (into the gap the
/// bar fills). Purely decorative - the insert runs from the strip's
/// paste/drop handling - so it ignores pointers.
class _InsertionMarker extends StatelessWidget {
  const _InsertionMarker({
    super.key,
    required this.color,
    this.axis = Axis.horizontal,
  });

  final Color color;

  /// The bar's own direction: horizontal along a top/bottom edge (the
  /// stacked strip), vertical along a left/right one (the flowing grid).
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    Widget cap() => Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        );
    final bar = Expanded(
      child: Container(
        height: axis == Axis.horizontal ? 3 : null,
        width: axis == Axis.vertical ? 3 : null,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(1.5),
        ),
      ),
    );
    return Padding(
      padding: axis == Axis.horizontal
          ? const EdgeInsets.symmetric(horizontal: 8)
          : const EdgeInsets.symmetric(vertical: 8),
      child: axis == Axis.horizontal
          ? Row(children: [cap(), bar, cap()])
          : Column(children: [cap(), bar, cap()]),
    );
  }
}

/// The page actions a thumbnail's right-click (secondary tap) menu offers.
enum _PageTileAction {
  rotateLeft,
  rotateRight,
  rotate180,
  duplicate,
  copy,
  cut,
  paste,
  insertBefore,
  insertAfter,
  export,
  delete,
}

/// Shows the thumbnail context menu at [position] (global coordinates) for
/// the page right-clicked. When that page is already part of a multi-page
/// strip selection the actions span the whole selection; otherwise the
/// menu first selects just that page (so its target is unambiguous), then
/// acts on it alone. Resolves when the menu closes, after the picked
/// action ran.
///
/// [allowPageEditing] gates the structural entries (rotate, duplicate,
/// insert, delete); [onExportPages] gates Export - each is omitted when
/// unavailable, so a read-only strip with no export handler never opens a
/// menu at all.
Future<void> _showPageTileMenu({
  required BuildContext context,
  required Offset position,
  required PdfEditingController controller,
  required PdfViewerController viewerController,
  required int pageIndex,
  required bool allowPageEditing,
  required void Function(Uint8List bytes)? onExportPages,
}) async {
  final canExport = onExportPages != null;
  if (!allowPageEditing && !canExport) return;
  // right-clicking a tile that isn't already selected selects just it (a
  // right-click on a tile that is part of a multi-selection keeps the
  // selection), so the pages the menu acts on always include this one
  if (!controller.isPageSelected(pageIndex)) controller.selectPage(pageIndex);
  final targets = controller.selectedPages;
  final multi = targets.length > 1;
  final pageCount = controller.document.pageCount;
  final l10n = pdfL10n(context);
  // "Duplicate page" / "Export 3 pages" - the verb's object reflects how
  // many pages the action spans (each verb is its own ICU plural)
  final count = targets.length;

  final items = <PopupMenuEntry<_PageTileAction>>[
    if (allowPageEditing) ...[
      _pageMenuRow(context, _PageTileAction.rotateLeft,
          tileKey: 'pdf-thumbnail-menu-rotate-left',
          icon: Icons.rotate_left,
          label: l10n.thumbRotateLeft),
      _pageMenuRow(context, _PageTileAction.rotateRight,
          tileKey: 'pdf-thumbnail-menu-rotate-right',
          icon: Icons.rotate_right,
          label: l10n.thumbRotateRight),
      _pageMenuRow(context, _PageTileAction.rotate180,
          tileKey: 'pdf-thumbnail-menu-rotate-180',
          icon: Icons.cached,
          label: l10n.thumbRotate180),
      _pageMenuRow(context, _PageTileAction.duplicate,
          tileKey: 'pdf-thumbnail-menu-duplicate',
          icon: Icons.copy_all_outlined,
          label: l10n.thumbDuplicatePages(count)),
      // copy/cut fill the shared page clipboard (cross-tab); paste drops
      // its pages after the right-clicked page. Cut can't empty the
      // document, so it dims when it would take every page.
      _pageMenuRow(context, _PageTileAction.copy,
          tileKey: 'pdf-thumbnail-menu-copy',
          icon: Icons.copy_outlined,
          label: l10n.thumbCopyPages(count)),
      _pageMenuRow(context, _PageTileAction.cut,
          tileKey: 'pdf-thumbnail-menu-cut',
          icon: Icons.content_cut,
          label: l10n.thumbCutPages(count),
          enabled: multi ? targets.length < pageCount : pageCount > 1),
      _pageMenuRow(context, _PageTileAction.paste,
          tileKey: 'pdf-thumbnail-menu-paste',
          icon: Icons.content_paste,
          label: l10n.thumbPastePages(controller.pageClipboard.pageCount),
          enabled: controller.hasPageClipboard),
      // insert is relative to the right-clicked page - a single insertion
      // point - so it stays singular even under a multi-selection
      _pageMenuRow(context, _PageTileAction.insertBefore,
          tileKey: 'pdf-thumbnail-menu-insert-before',
          icon: Icons.vertical_align_top,
          label: l10n.thumbInsertBlankBefore),
      _pageMenuRow(context, _PageTileAction.insertAfter,
          tileKey: 'pdf-thumbnail-menu-insert-after',
          icon: Icons.vertical_align_bottom,
          label: l10n.thumbInsertBlankAfter),
    ],
    if (canExport)
      _pageMenuRow(context, _PageTileAction.export,
          tileKey: 'pdf-thumbnail-menu-export',
          icon: Icons.file_download_outlined,
          label: l10n.thumbExportPagesMenu(count)),
    if (allowPageEditing)
      _pageMenuRow(context, _PageTileAction.delete,
          tileKey: 'pdf-thumbnail-menu-delete',
          icon: Icons.delete_outline,
          label: l10n.thumbDeletePages(count),
          // a document must keep at least one page
          enabled: multi ? targets.length < pageCount : pageCount > 1),
  ];
  if (items.isEmpty) return;

  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final picked = await showMenu<_PageTileAction>(
    context: context,
    position:
        RelativeRect.fromRect(position & Size.zero, Offset.zero & overlay.size),
    items: items,
  );
  switch (picked) {
    case null:
      return;
    case _PageTileAction.rotateLeft:
      controller.rotatePages(targets, -90);
    case _PageTileAction.rotateRight:
      controller.rotatePages(targets, 90);
    case _PageTileAction.rotate180:
      controller.rotatePages(targets, 180);
    case _PageTileAction.duplicate:
      controller.duplicatePages(targets);
    case _PageTileAction.copy:
      controller.copyPages(targets);
    case _PageTileAction.cut:
      controller.cutPages(targets);
    case _PageTileAction.paste:
      final pastedAt = pageIndex + 1;
      if (controller.pastePages(at: pastedAt)) {
        unawaited(_jumpToInsertedPage(viewerController, pastedAt));
      }
    case _PageTileAction.insertBefore:
      controller.addBlankPage(at: pageIndex);
    case _PageTileAction.insertAfter:
      final insertedPage = pageIndex + 1;
      controller.addBlankPage(at: insertedPage);
      unawaited(_jumpToInsertedPage(viewerController, insertedPage));
    case _PageTileAction.export:
      onExportPages?.call(controller.exportPages(targets));
    case _PageTileAction.delete:
      controller.removeSelectedPages();
  }
}

Future<void> _jumpToInsertedPage(
  PdfViewerController viewerController,
  int pageIndex,
) async {
  // The controller notification first rebuilds the viewer with the new page
  // list. A geometry-changing revision then resets its old scroll position in
  // a post-frame callback, so navigate on the following frame, after both the
  // new list metrics and that reset have landed. `endOfFrame` schedules a
  // frame when idle and avoids leaving a test-host timer behind.
  await SchedulerBinding.instance.endOfFrame;
  await SchedulerBinding.instance.endOfFrame;
  await viewerController.jumpToPage(pageIndex);
}

PopupMenuItem<_PageTileAction> _pageMenuRow(
  BuildContext context,
  _PageTileAction action, {
  required String tileKey,
  required IconData icon,
  required String label,
  bool enabled = true,
}) =>
    PopupMenuItem<_PageTileAction>(
      key: ValueKey(tileKey),
      value: action,
      enabled: enabled,
      height: _densePopupMenuHeight,
      child: Row(children: [
        // PopupMenuItem dims only its text when disabled; match it on the icon
        Icon(icon,
            size: 16, color: enabled ? null : Theme.of(context).disabledColor),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: _densePopupTextStyle(context,
                color: enabled ? null : Theme.of(context).disabledColor),
          ),
        ),
      ]),
    );

/// Renders a page to a tile-resolution bitmap, served from the session's
/// shared [PdfThumbnailCache] and keyed by the page's render stamp - an
/// edit elsewhere reuses the raster, and a tile already drawn by the strip
/// or grid (or the background warm) shows instantly. While a fresh raster
/// is still rendering it paints the viewer's matching low-res preview as a
/// soft placeholder, falling back to blank paper when there is none.
class _PageThumbnail extends StatefulWidget {
  const _PageThumbnail({
    required this.controller,
    required this.viewerController,
    required this.pageIndex,
    required this.pageColor,
    required this.showAnnotations,
    required this.cache,
    required this.tileWidth,
    required this.renderWorker,
  });

  final PdfEditingController controller;
  final PdfViewerController viewerController;
  final int pageIndex;
  final Color pageColor;
  final bool showAnnotations;
  final PdfThumbnailCache cache;
  final double tileWidth;
  final PdfRenderWorker? renderWorker;

  @override
  State<_PageThumbnail> createState() => _PageThumbnailState();
}

class _PageThumbnailState extends State<_PageThumbnail> {
  ui.Image? _image; // this tile's clone; the cache owns the original
  String? _imageKey;
  String? _pendingKey;

  /// A soft low-res placeholder cloned from the viewer's preview cache,
  /// shown until the sharp raster lands. The tile owns this clone.
  ui.Image? _placeholder;

  @override
  void didUpdateWidget(_PageThumbnail old) {
    super.didUpdateWidget(old);
    // a different edit session: render stamps restart at zero, so the
    // new document's keys collide with the shown image's - drop it, and
    // withdraw any pending render against the old shared cache
    if (!identical(old.controller, widget.controller)) {
      old.cache.cancel(this);
      _image?.dispose();
      _image = null;
      _imageKey = null;
      _pendingKey = null;
      _placeholder?.dispose();
      _placeholder = null;
    }
  }

  @override
  void dispose() {
    // withdraw this tile's pending render from the shared queue - it scrolled
    // out of the lazy strip, or its panel went away
    widget.cache.cancel(this);
    _pendingKey = null;
    _image?.dispose();
    _image = null;
    _placeholder?.dispose();
    _placeholder = null;
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
    cache.request(this, pageIndex, () async {
      // superseded (newer revision, resize) or already landed - skip
      if (!mounted || _pendingKey != key) return;
      // another surface (the grid, the warm prerender) may have rendered
      // this exact raster while we waited our turn - adopt it, no re-render
      if (cache.contains(key)) {
        setState(() {
          _pendingKey = null;
          _image?.dispose();
          _image = cache.claim(key);
          _imageKey = key;
        });
        return;
      }
      // nothing may escape: a single failing page must neither poison the
      // queue nor surface - it just keeps its placeholder
      try {
        var deferred = false;
        final image = await rasterizeThumbnail(
          controller: controller,
          pageIndex: pageIndex,
          pageColor: pageColor,
          annotations: annotations,
          pixelWidth: pixelWidth,
          worker: worker,
          // The task may have been granted before a fast scroll and return
          // from its worker during the render hold. Do not replay/rasterize
          // that stale result on the platform thread; keep the viewer preview
          // and let the shared queue retry after its foreground gate clears.
          deferUiWork: () {
            final value = cache.shouldDeferUiWork;
            deferred |= value;
            return value;
          },
          // only persist/read disk for pages untouched this session - the
          // disk key is content-derived and render stamps reset per session
          disk: controller.pageRenderStamp(pageIndex) == 0 ? cache.disk : null,
        );
        if (image == null) {
          if (deferred && mounted && _pendingKey == key) {
            // This request has already been removed from the queue. Put the
            // same token back while the gate is closed; its activity listener
            // will grant it when the viewer becomes idle again.
            _enqueue(key, pixelWidth);
          }
          return;
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

  /// The viewer's low-res preview for this page, cloned once, as a soft
  /// placeholder until the sharp raster is ready. Best-effort: missed
  /// previews just leave blank paper as before.
  void _seedPlaceholder() {
    if (_placeholder != null) return;
    _placeholder =
        widget.viewerController.pagePreviewCache?.imageFor(widget.pageIndex);
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.controller.pageAt(widget.pageIndex);
    final size = PdfPageRenderer.pageSize(page);
    final pixelWidth = _thumbnailBucket(
        widget.tileWidth * MediaQuery.devicePixelRatioOf(context));
    final key = thumbnailKey(widget.controller, widget.pageIndex,
        widget.pageColor, widget.showAnnotations, pixelWidth);
    if (_imageKey != key) {
      final cached = widget.cache.claim(key);
      if (cached != null) {
        _image?.dispose();
        _image = cached;
        _imageKey = key;
        _pendingKey = null;
        _placeholder?.dispose();
        _placeholder = null;
      } else if (_pendingKey != key) {
        _enqueue(key, pixelWidth);
      }
    }
    if (_image == null) _seedPlaceholder();
    // while a re-render is in flight the previous raster (or the soft
    // preview placeholder) keeps showing
    final shown = _image ?? _placeholder;
    return AspectRatio(
      aspectRatio:
          size.width <= 0 || size.height <= 0 ? 1 : size.width / size.height,
      child: shown == null
          ? ColoredBox(color: widget.pageColor)
          : RawImage(image: shown, fit: BoxFit.contain),
    );
  }
}

/// The shared-cache key a page's thumbnail is stored under: page index, its
/// render stamp (so an edit re-renders only the pages it touched), the paper
/// color, the raster width bucket, and whether annotations are drawn. The
/// tile, the grid cell, and the background warm all derive the same key, so
/// they reuse one another's rasters.
String thumbnailKey(PdfEditingController controller, int pageIndex,
        Color pageColor, bool annotations, int pixelWidth) =>
    '$pageIndex|${controller.pageRenderStamp(pageIndex)}'
    '|${pageColor.toARGB32()}|$pixelWidth${annotations ? '' : '|noannots'}';

/// Whole-document thumbnail warming policy.
///
/// Native platforms can rasterize tile-sized pictures away from the Flutter
/// web platform-thread bottleneck. On web, a dense vector page still costs
/// hundreds of milliseconds in CanvasKit even at 128 px, so proactively
/// warming every page of a long document creates periodic frame drops before
/// the user ever visits those pages. Such documents render visible tiles on
/// demand and show the viewer's 200 px preview meanwhile.
@visibleForTesting
bool pdfShouldWarmThumbnails(int pageCount, {bool? web}) =>
    !(web ?? kIsWeb) || pageCount <= 24;

/// Raster widths snap to 64px steps so a resize drag doesn't re-render every
/// page per pixel.
int _thumbnailBucket(double px) => ((px / 64).ceil() * 64).clamp(64, 1024);

/// The page index nearest the scroll viewport, used as the shared cache's
/// render focus. A coarse estimate from the scroll fraction - enough to
/// order "render what's on screen first" without per-tile layout math.
int _thumbnailFocusFromScroll(ScrollController scroll, int pageCount) {
  if (!scroll.hasClients || pageCount <= 1) return 0;
  final max = scroll.position.maxScrollExtent;
  if (max <= 0) return 0;
  final fraction = (scroll.position.pixels / max).clamp(0.0, 1.0);
  return (fraction * (pageCount - 1)).round();
}

/// Interprets [pageIndex] and rasterizes it to a tile-resolution image, off
/// the UI thread via [worker] when one is active and locally otherwise.
/// Returns null when the page has no area or can't be rendered.
///
/// [priority] orders the worker's queue (lower served first): on-screen
/// tiles use 2, the background warm a lower 3, so a tile the user is looking
/// at preempts an in-flight warm render. When [skipIfWorkerDeclines] is true
/// (the warm pass) a page the worker won't offload - or whose render the
/// worker preempted for a higher-priority tile - returns null instead of
/// falling back to a heavy UI-thread interpret, so warming never blocks a
/// frame.
Future<ui.Image?> rasterizeThumbnail({
  required PdfEditingController controller,
  required int pageIndex,
  required Color pageColor,
  required bool annotations,
  required int pixelWidth,
  required PdfRenderWorker? worker,
  int priority = 2,
  bool skipIfWorkerDeclines = false,
  bool Function()? deferUiWork,
  String reason = 'tile',
  PdfRasterCache? disk,
}) async {
  final page = controller.pageAt(pageIndex);
  final size = PdfPageRenderer.pageSize(page);
  if (size.width <= 0 || size.height <= 0) return null;
  final ratio = pixelWidth / size.width;
  // an unedited page reopened in a later session can come straight off disk -
  // no interpret at all. [disk] is supplied already gated to such pages (its
  // key is content-derived, and render stamps reset per session), so loading
  // it back is always for the right pixels.
  if (disk != null) {
    final stored = await disk.loadThumbnail(pageIndex, pixelWidth,
        pageColor: pageColor.toARGB32(), annotations: annotations);
    if (stored != null) {
      PdfPerfLog.log(
          'thumbnail page=$pageIndex $reason px=$pixelWidth disk-hit');
      return stored;
    }
  }
  // a DevTools-timeline span for the whole thumbnail render (free when no
  // trace is recording; appears when you capture one), split into its phases
  // so a trace shows where the time actually goes - and matching gated
  // PdfPerfLog console lines for `--dart-define=PDF_PERF_LOG=true` / `?perf=1`.
  final trace = TimelineTask()
    ..start('thumbnail', arguments: {
      'page': pageIndex,
      'pixelWidth': pixelWidth,
      'priority': priority,
      'reason': reason,
    });
  final sw = Stopwatch()..start();
  try {
    // the heavy interpret runs on the isolate, only the small replay + raster
    // stays here. Image pages and the web fallback return null and rasterize
    // locally.
    final usingWorker = worker != null && worker.isActive;
    final commands = usingWorker
        ? await worker.record(pageIndex,
            annotations: annotations,
            priority: priority,
            imagePixelRatio: ratio)
        : null;
    final recordMs = sw.elapsedMicroseconds / 1000.0;
    if (commands != null) {
      // A thumbnail may have started while the viewer was idle, then received
      // its worker result after scrolling began. Do not turn that result into
      // a picture/raster on the platform thread now: the tile already has a
      // soft viewer preview, and foreground motion wins. A visible tile is
      // re-queued; a warm pass may leave the page for its on-demand render.
      if (deferUiWork?.call() ?? false) {
        trace.instant('defer ui replay', arguments: {'ms': recordMs});
        PdfPerfLog.log('thumbnail page=$pageIndex $reason px=$pixelWidth '
            'defer ui replay record=${_traceMs(recordMs)}');
        return null;
      }
      trace.instant('worker.record',
          arguments: {'ms': recordMs, 'commands': commands.length});
      sw.reset();
      // The replay is the one part of a thumbnail that CANNOT leave the
      // platform thread, so it gets the tile's own resolution too: any image
      // the worker's codec declined arrives un-decoded, and without the cap it
      // would decode at native size here - a 10-megapixel scan run through the
      // pure-Dart codec to fill a 256px tile (#603). Sliced into the timeline
      // as its own span so a trace attributes it to the thumbnail rather than
      // to whatever frame it lands in.
      final picture = await _timedReplay(
          pageIndex,
          reason,
          () => PdfPageRenderer.pictureFromCommands(page, commands,
              pageColor: pageColor, maxImagePixelRatio: ratio));
      final replayMs = sw.elapsedMicroseconds / 1000.0;
      sw.reset();
      try {
        // pictureFromCommands can yield while resolving resources. Re-check
        // before the much more expensive CanvasKit raster in case scrolling
        // began during that replay.
        if (deferUiWork?.call() ?? false) {
          trace.instant('defer ui raster',
              arguments: {'recordMs': recordMs, 'replayMs': replayMs});
          PdfPerfLog.log('thumbnail page=$pageIndex $reason px=$pixelWidth '
              'defer ui raster record=${_traceMs(recordMs)} '
              'replay=${_traceMs(replayMs)}');
          return null;
        }
        final image = await PdfPageRenderer.rasterize(picture, size, ratio);
        final rasterMs = sw.elapsedMicroseconds / 1000.0;
        trace.instant('rasterize', arguments: {'ms': rasterMs});
        PdfPerfLog.log(
            'thumbnail page=$pageIndex $reason px=$pixelWidth worker '
            'record=${_traceMs(recordMs)} replay=${_traceMs(replayMs)} '
            'raster=${_traceMs(rasterMs)}');
        // write through so this page opens straight from disk next session
        disk?.storeThumbnail(pageIndex, pixelWidth, image,
            pageColor: pageColor.toARGB32(), annotations: annotations);
        return image;
      } finally {
        picture.dispose();
      }
    }
    // The warm pass skips whenever it cannot get a worker result: the worker
    // may have declined/preempted the page, or there may be no active worker
    // (web worker script missing, or a caller omitted renderWorker). On-screen
    // tiles still fall back to a local interpret as before.
    if (skipIfWorkerDeclines) {
      trace.instant('skip local fallback', arguments: {'ms': recordMs});
      PdfPerfLog.log('thumbnail page=$pageIndex $reason px=$pixelWidth '
          'skip local fallback record=${_traceMs(recordMs)} '
          '${usingWorker ? '(worker declined)' : '(no worker)'}');
      return null;
    }
    // The worker may have declined only after the viewer started moving. A
    // visible tile normally falls back to a local interpret here, which is
    // even more disruptive than replaying a returned command buffer; defer it
    // under the same gate and retry after settle.
    if (deferUiWork?.call() ?? false) {
      trace.instant('defer ui local fallback', arguments: {'ms': recordMs});
      PdfPerfLog.log('thumbnail page=$pageIndex $reason px=$pixelWidth '
          'defer ui local fallback record=${_traceMs(recordMs)}');
      return null;
    }
    sw.reset();
    final image = await PdfPageRenderer.renderImage(page,
        pixelRatio: ratio, pageColor: pageColor, annotations: annotations);
    final localMs = sw.elapsedMicroseconds / 1000.0;
    trace.instant('local interpret+raster', arguments: {'ms': localMs});
    PdfPerfLog.log('thumbnail page=$pageIndex $reason px=$pixelWidth '
        'local interpret+raster=${_traceMs(localMs)} '
        '${usingWorker ? '(worker declined)' : '(no worker)'}');
    disk?.storeThumbnail(pageIndex, pixelWidth, image,
        pageColor: pageColor.toARGB32(), annotations: annotations);
    return image;
  } finally {
    trace.finish();
  }
}

String _traceMs(double v) => '${v.toStringAsFixed(1)}ms';

/// Wraps a thumbnail's command replay in its own async timeline slice.
///
/// The replay builds a `ui.Picture` on the platform thread - the same thread
/// the visible page's build needs - so in a DevTools capture it is otherwise
/// indistinguishable from foreground work. A named slice per page/reason is
/// what lets a trace say "this frame went to warming page 47's thumbnail"
/// (#603). Free when nothing is recording.
Future<T> _timedReplay<T>(
    int pageIndex, String reason, Future<T> Function() replay) async {
  final flow = TimelineTask()
    ..start('thumbnail replay',
        arguments: {'page': pageIndex, 'reason': reason});
  try {
    return await replay();
  } finally {
    flow.finish();
  }
}

/// Marks the viewer's viewport on a thumbnail: [region] is the visible
/// part of the page as fractions of its area.
/// Devtools: strokes a page's cached tile grid (green, dimmer the coarser
/// the rung relative to the sharpest present) and its legacy detail patch
/// (purple) into the thumbnail. Rects arrive as page fractions.
class _DetailBoundsPainter extends CustomPainter {
  const _DetailBoundsPainter(this.tiles, this.patch);

  final List<({Rect fraction, int rung})> tiles;
  final Rect? patch;

  @override
  void paint(Canvas canvas, Size size) {
    Rect scale(Rect f) => Rect.fromLTRB(f.left * size.width,
        f.top * size.height, f.right * size.width, f.bottom * size.height);
    if (tiles.isNotEmpty) {
      final sharpest = tiles.map((t) => t.rung).reduce((a, b) => a > b ? a : b);
      for (final tile in tiles) {
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0xFF00C853)
              .withValues(alpha: tile.rung == sharpest ? 0.9 : 0.35);
        canvas.drawRect(scale(tile.fraction), paint);
      }
    }
    if (patch != null) {
      canvas.drawRect(
        scale(patch!),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0xCCAA00FF),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DetailBoundsPainter old) => true;
}

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
