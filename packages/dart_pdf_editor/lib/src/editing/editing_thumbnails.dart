import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../pdf_viewer.dart';
import '../renderer.dart';
import '../scrollbar.dart';
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
  });

  final PdfEditingController controller;

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
    final body = SizedBox(
      width: width,
      child: Stack(children: [
        Positioned.fill(
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            // only document changes rebuild the list — viewer scrolling
            // repaints the per-tile indicators alone
            child: ListenableBuilder(
              listenable: controller,
              // the implicit desktop scrollbar is replaced by the
              // viewer-style bar below
              builder: (context, _) => Column(
                children: [
                  Expanded(
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context)
                          .copyWith(scrollbars: false),
                      child: ReorderableListView.builder(
                        scrollController: _scroll,
                        buildDefaultDragHandles: false,
                        padding:
                            EdgeInsets.fromLTRB(0, 8, _extraRightPadding, 8),
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
                          );
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
                      padding: EdgeInsets.fromLTRB(4, 2, _extraRightPadding, 4),
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
          ),
        ),
        // the same scrollbar the viewer paints, so every bar in the
        // chrome looks and behaves alike; stepped off the resize grip
        // when the grip rides the same (right) edge
        Positioned(
          top: 0,
          bottom: 0,
          right: showGrip && widget.side == PdfSidebarSide.left
              ? PdfSidebarResizeGrip.width
              : 0,
          child: PdfScrollbar(
            scroll: _scroll,
            thumbKey: const ValueKey('pdf-thumbnail-scrollbar-thumb'),
          ),
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
    return widget.bottomSheet ? Center(child: body) : body;
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
  });

  final PdfEditingController controller;
  final PdfViewerController viewerController;
  final int pageIndex;
  final Color pageColor;
  final bool showAnnotations;
  final bool allowPageEditing;
  final _ThumbnailCache cache;
  final double tileWidth;

  /// WCAG-style contrast ratio between two opaque colors.
  static double _contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // the viewport mark paints over the paper, not the app surface: a
    // dark theme's light primary vanishes on a white thumbnail, so pick
    // whichever accent actually contrasts with the page color
    final indicator = _contrast(scheme.primary, pageColor) >=
            _contrast(scheme.inversePrimary, pageColor)
        ? scheme.primary
        : scheme.inversePrimary;
    final document = controller.document;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => unawaited(viewerController.jumpToPage(pageIndex)),
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
                      ),
                    ),
                    if (viewport != null)
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _ViewportPainter(viewport, indicator),
                        ),
                      ),
                  ]),
                );
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text('Page ${pageIndex + 1}',
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium),
                ),
                if (allowPageEditing && document.pageCount > 1)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 16),
                    tooltip: 'Delete page',
                    style: IconButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(28, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => controller.removePage(pageIndex),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
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
  });

  final PdfEditingController controller;
  final int pageIndex;
  final Color pageColor;
  final bool showAnnotations;
  final _ThumbnailCache cache;
  final double tileWidth;

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
        final image = await PdfPageRenderer.renderImage(page,
            pixelRatio: pixelWidth / size.width,
            pageColor: pageColor,
            annotations: annotations);
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
