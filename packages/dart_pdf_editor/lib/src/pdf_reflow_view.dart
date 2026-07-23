import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

import 'image_decoder.dart';
import 'l10n/pdf_l10n.dart';
import 'pdf_viewer.dart';

/// Receives a figure the reader tapped in [PdfReflowView], rendered as a PNG,
/// to save or share it (typically the platform share sheet / a save dialog).
/// With no handler the fullscreen image viewer still opens (pan and pinch to
/// zoom) - it just omits the share action.
typedef PdfReflowImageShareHandler = Future<void> Function(
    BuildContext context, Uint8List pngBytes);

/// A text-first view of a PDF document.
///
/// The PDF page graphics are not rendered here. Instead the content stream is
/// interpreted for positioned text and images, then [PdfTextExtractor] infers
/// visual lines, reading order, and paragraph blocks, interleaving the page's
/// figures and diagrams in place. This is useful for narrow screens and
/// accessibility-style reading where fixed page layout is less important than
/// continuous, reflowable content.
///
/// Pages are laid out lazily: each page's content is only extracted, and its
/// images only decoded, once it scrolls near the viewport - so opening (and
/// scrolling) a 600-page book stays responsive instead of walking every
/// content stream and decoding every image up front.
///
/// When a [controller] is given the view registers as its
/// [PdfReflowBackend], so the thumbnail strip, bookmarks, and the shell's
/// saved-position memory drive and follow the reading view exactly as they do
/// the page viewer - page taps scroll here, and the reading position is
/// remembered per document.
class PdfReflowView extends StatefulWidget {
  const PdfReflowView({
    super.key,
    required this.document,
    this.controller,
    this.onShareImage,
    this.backgroundColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
    this.maxWidth = 760,
    this.showImages = true,
  });

  final PdfDocument document;

  /// The shared viewer controller. When present, the reading view registers
  /// as its navigation backend (page jumps, current-page tracking, saved
  /// position); null keeps the view standalone.
  final PdfViewerController? controller;

  /// Saves or shares a figure the reader taps to open fullscreen. Null hides
  /// the share action but still allows fullscreen pan/pinch-zoom viewing.
  final PdfReflowImageShareHandler? onShareImage;

  final Color? backgroundColor;
  final EdgeInsetsGeometry padding;
  final double maxWidth;

  /// Whether to interleave the page's images and diagrams with the text.
  /// When false the view is text-only (the historical behaviour).
  final bool showImages;

  @override
  State<PdfReflowView> createState() => _PdfReflowViewState();
}

class _PdfReflowViewState extends State<PdfReflowView>
    implements PdfReflowBackend {
  final ScrollController _scroll = ScrollController();

  /// The list's viewport, keyed so we can read its render box for scroll math.
  final GlobalKey _listKey = GlobalKey();

  /// One key per built page item, for measuring and `ensureVisible`.
  final Map<int, GlobalKey> _itemKeys = {};

  /// Reflowed pages, computed on demand and cached for the document's life.
  final Map<int, PdfReflowPage> _reflowed = {};

  /// Resolves once we know whether the document has any extractable content
  /// (scans lazily, stopping at the first non-empty page - so a real book
  /// resolves after one page).
  late Future<bool> _hasContent;

  /// A viewport (page + fraction) to restore once the list has laid out.
  PdfViewport? _pendingRestore;

  /// A page to jump to once the list has laid out (a tap before first layout).
  int? _pendingJump;

  @override
  void initState() {
    super.initState();
    _hasContent = _probeContent();
    _scroll.addListener(_onScroll);
    _attachBackend();
  }

  @override
  void didUpdateWidget(PdfReflowView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) {
      oldWidget.controller?.detachReflowBackend(this);
      _attachBackend();
    }
    if (!identical(widget.document, oldWidget.document) ||
        widget.showImages != oldWidget.showImages) {
      _reflowed.clear();
      _itemKeys.clear();
      _pendingRestore = null;
      _pendingJump = null;
      _hasContent = _probeContent();
      widget.controller?.reflowReportPageCount(widget.document.pageCount);
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
  }

  @override
  void dispose() {
    widget.controller?.detachReflowBackend(this);
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _attachBackend() {
    final controller = widget.controller;
    if (controller == null) return;
    controller
      ..attachReflowBackend(this)
      ..reflowReportPageCount(widget.document.pageCount);
  }

  PdfReflowPage _pageAt(int index) => _reflowed.putIfAbsent(
      index, () => PdfTextExtractor.reflowPage(widget.document, index));

  bool _isEmpty(PdfReflowPage page) =>
      widget.showImages ? page.items.isEmpty : page.blocks.isEmpty;

  Future<bool> _probeContent() async {
    // Only the first page gates the reading view - a single (cached) reflow.
    // A multi-page document opens even when page 0 is blank (front matter),
    // so we never reflow a run of heavy pages up front just to decide whether
    // to show the "no content" message; per-page items take it from here.
    await Future<void>.delayed(Duration.zero);
    final pageCount = widget.document.pageCount;
    if (pageCount == 0) return false;
    if (!_isEmpty(_pageAt(0))) return true;
    return pageCount > 1;
  }

  GlobalKey _keyFor(int index) =>
      _itemKeys.putIfAbsent(index, () => GlobalKey());

  // --- scroll math -----------------------------------------------------------

  RenderBox? get _viewportBox =>
      _listKey.currentContext?.findRenderObject() as RenderBox?;

  /// Item [index]'s top edge, in pixels below the viewport's top edge; null
  /// when the item is not currently built.
  double? _itemTop(int index) {
    final viewport = _viewportBox;
    final box = _keyFor(index).currentContext?.findRenderObject() as RenderBox?;
    if (viewport == null || box == null || !box.attached) return null;
    return box.localToGlobal(Offset.zero).dy -
        viewport.localToGlobal(Offset.zero).dy;
  }

  /// The topmost page currently occupying the viewport's top edge (the page
  /// the reader is "on"), or null while nothing is laid out.
  int? _topVisiblePage() {
    final viewport = _viewportBox;
    if (viewport == null) return null;
    final height = viewport.size.height;
    int? cover; // an item straddling the top edge
    double coverTop = double.negativeInfinity;
    int? firstVisible;
    double firstTop = double.infinity;
    for (final index in _itemKeys.keys) {
      final box =
          _keyFor(index).currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final top = box.localToGlobal(Offset.zero).dy -
          viewport.localToGlobal(Offset.zero).dy;
      final bottom = top + box.size.height;
      if (bottom <= 0 || top >= height) continue; // off-screen
      if (top < firstTop) {
        firstTop = top;
        firstVisible = index;
      }
      if (top <= 0 && top > coverTop) {
        coverTop = top;
        cover = index;
      }
    }
    return cover ?? firstVisible;
  }

  void _onScroll() {
    final page = _topVisiblePage();
    if (page == null) return;
    // Reports the page (when changed) and always bumps the viewport, so the
    // thumbnail indicator and the shell's saved-position memory follow the
    // scroll.
    widget.controller?.reflowReportPage(page);
  }


  // --- PdfReflowBackend ------------------------------------------------------

  @override
  void reflowJumpToPage(int index) {
    final pageCount = widget.document.pageCount;
    if (pageCount == 0) return;
    index = index.clamp(0, pageCount - 1);
    if (!_scroll.hasClients) {
      _pendingJump = index;
      return;
    }
    // Already built: align it precisely. Otherwise estimate from the average
    // built-item height, jump, and correct once the frame builds the target
    // into view. Page heights are final on build (text extracts synchronously),
    // so the estimate is stable and a couple of corrections converge.
    if (_alignTop(index)) {
      widget.controller?.reflowReportPage(index);
      return;
    }
    _scroll.jumpTo(_estimateOffset(index));
    _correctTo(index, triesLeft: 4);
  }

  double _estimateOffset(int index) {
    final offset = widget.padding.resolve(TextDirection.ltr).top +
        _averageExtent() * index;
    return offset.clamp(0.0, _scroll.position.maxScrollExtent);
  }

  void _correctTo(int index, {required int triesLeft}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (_alignTop(index)) {
        widget.controller?.reflowReportPage(index);
      } else if (triesLeft > 0) {
        _scroll.jumpTo(_estimateOffset(index));
        _correctTo(index, triesLeft: triesLeft - 1);
      }
    });
  }

  /// Average height of the currently built page items - the estimate for
  /// pages not yet laid out. Text extracts synchronously so these heights are
  /// final, not placeholders.
  double _averageExtent() {
    var sum = 0.0;
    var n = 0;
    for (final index in _itemKeys.keys) {
      final box =
          _keyFor(index).currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      sum += box.size.height;
      n++;
    }
    return n == 0 ? 640.0 : sum / n;
  }

  /// Jumps so item [index]'s top aligns with the viewport top; returns false
  /// when the item is not built (so the caller can estimate first).
  bool _alignTop(int index) {
    final top = _itemTop(index);
    if (top == null) return false;
    final target = (_scroll.position.pixels + top)
        .clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.jumpTo(target);
    return true;
  }

  @override
  PdfViewport? reflowCaptureViewport() {
    if (!_scroll.hasClients) return _pendingRestore;
    final page = _topVisiblePage();
    if (page == null) return null;
    var fraction = 0.0;
    final top = _itemTop(page);
    final box = _keyFor(page).currentContext?.findRenderObject() as RenderBox?;
    if (top != null && box != null && box.size.height > 0) {
      fraction = (-top / box.size.height).clamp(0.0, 1.0);
    }
    return PdfViewport(page: page, top: fraction);
  }

  @override
  void reflowRestoreViewport(PdfViewport viewport) {
    _pendingRestore = viewport;
    // Apply straight away when the list is laid out (scrolling schedules the
    // frame the corrections ride on); otherwise wait for layout - and ask for
    // a frame, since a bare post-frame callback never runs on its own.
    _applyRestoreIfPending();
  }

  void _applyRestoreIfPending() {
    if (!mounted) return;
    final viewport = _pendingRestore;
    if (viewport == null) return;
    if (!_scroll.hasClients) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _applyRestoreIfPending());
      WidgetsBinding.instance.scheduleFrame();
      return;
    }
    _pendingRestore = null;
    // Restore to the saved page (the pin loop settles it at the top). Page
    // granularity is enough to reopen where the reader left off; chasing the
    // exact sub-page fraction would fight the pin as pages resolve.
    reflowJumpToPage(viewport.page);
  }

  @override
  Rect? reflowVisibleFraction(int index) {
    final viewport = _viewportBox;
    final top = _itemTop(index);
    final box = _keyFor(index).currentContext?.findRenderObject() as RenderBox?;
    if (viewport == null || top == null || box == null) return null;
    final height = box.size.height;
    if (height <= 0) return null;
    final bottom = top + height;
    if (bottom <= 0 || top >= viewport.size.height) return null;
    final topFrac = (-top / height).clamp(0.0, 1.0);
    final botFrac = ((viewport.size.height - top) / height).clamp(0.0, 1.0);
    return Rect.fromLTRB(0, topFrac, 1, botFrac);
  }

  // --- build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background =
        widget.backgroundColor ?? theme.colorScheme.surfaceContainerLowest;
    return ColoredBox(
      color: background,
      child: FutureBuilder<bool>(
        future: _hasContent,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data != true) {
            return Center(
              child: Text(
                pdfL10n(context).reflowNoContent,
                style: theme.textTheme.bodyLarge,
              ),
            );
          }
          // Apply any restore/jump queued before the list existed.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (_pendingRestore != null) {
              _applyRestoreIfPending();
            } else if (_pendingJump != null && _scroll.hasClients) {
              final index = _pendingJump!;
              _pendingJump = null;
              reflowJumpToPage(index);
            }
          });
          return KeyedSubtree(
            key: const ValueKey('pdf-reflow-view'),
            child: Scrollbar(
              controller: _scroll,
              child: ListView.builder(
                key: _listKey,
                controller: _scroll,
                padding: widget.padding,
                itemCount: widget.document.pageCount,
                itemBuilder: (context, index) => Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: widget.maxWidth),
                    child: RepaintBoundary(
                      child: _ReflowPageItem(
                        key: _keyFor(index),
                        document: widget.document,
                        page: _pageAt(index),
                        showImages: widget.showImages,
                        onShareImage: widget.onShareImage,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One page of the reading view. The page's text is laid out from the
/// [page] reflow synchronously, so the item's height is final the moment it
/// builds - the list never resizes a laid-out page under the viewport, which
/// is what would make the scroll jump. Images decode lazily (their slot keeps
/// a fixed aspect-ratio box either way, so that stays height-stable) and their
/// clones are disposed when the page scrolls out, so only the pages near the
/// viewport hold pixels.
class _ReflowPageItem extends StatefulWidget {
  const _ReflowPageItem({
    super.key,
    required this.document,
    required this.page,
    required this.showImages,
    this.onShareImage,
  });

  final PdfDocument document;
  final PdfReflowPage page;
  final bool showImages;
  final PdfReflowImageShareHandler? onShareImage;

  @override
  State<_ReflowPageItem> createState() => _ReflowPageItemState();
}

class _ReflowPageItemState extends State<_ReflowPageItem> {
  /// Decoded images keyed by [pdfImageKey]; the clones are ours to dispose.
  Map<Object, ui.Image> _images = const {};

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(_ReflowPageItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.page, oldWidget.page) ||
        widget.showImages != oldWidget.showImages) {
      _decode();
    }
  }

  @override
  void dispose() {
    _disposeImages();
    super.dispose();
  }

  void _disposeImages() {
    for (final image in _images.values) {
      image.dispose();
    }
    _images = const {};
  }

  Future<void> _decode() async {
    if (!widget.showImages) {
      if (_images.isNotEmpty) setState(_disposeImages);
      return;
    }
    final requests = [for (final image in widget.page.images) image.request];
    if (requests.isEmpty) {
      if (_images.isNotEmpty) setState(_disposeImages);
      return;
    }
    final images = await decodeImages(widget.document.cos, requests,
        cache: PdfImageCache.instance);
    if (!mounted) {
      for (final image in images.values) {
        image.dispose();
      }
      return;
    }
    setState(() {
      _disposeImages();
      _images = images;
    });
  }

  /// Opens a decoded figure fullscreen. The route holds its own clone, so it
  /// is unaffected if this page scrolls out and disposes its images.
  void _openImage(ui.Image image) {
    final owned = image.clone();
    Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (context, _, __) =>
          _FullscreenReflowImage(image: owned, onShare: widget.onShareImage),
      transitionsBuilder: (context, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ));
  }

  @override
  Widget build(BuildContext context) => _ReflowPage(
        page: widget.page,
        images: _images,
        showImages: widget.showImages,
        onTapImage: _openImage,
      );
}

class _ReflowPage extends StatelessWidget {
  const _ReflowPage({
    required this.page,
    required this.images,
    required this.showImages,
    this.onTapImage,
  });

  final PdfReflowPage page;
  final Map<Object, ui.Image> images;
  final bool showImages;

  /// Opens a decoded figure fullscreen when tapped.
  final void Function(ui.Image image)? onTapImage;

  @override
  Widget build(BuildContext context) {
    final items = showImages
        ? page.items
        : page.items.whereType<PdfReflowBlock>().toList();
    if (items.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final median = _median(page.blocks.map((block) => block.fontSize));
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            pdfL10n(context).reflowPageLabel(page.pageIndex + 1),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: switch (item) {
                final PdfReflowBlock block => _block(theme, block, median),
                final PdfReflowImage image => _image(context, theme, image),
              },
            ),
        ],
      ),
    );
  }

  Widget _block(ThemeData theme, PdfReflowBlock block, double pageMedian) {
    final text = SelectableText(
      block.text,
      style: _styleFor(theme, block, pageMedian),
    );
    if (!block.isListItem) return text;
    // Hang the wrapped lines under the marker's text.
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 16),
      child: text,
    );
  }

  Widget _image(BuildContext context, ThemeData theme, PdfReflowImage image) {
    final decoded = images[pdfImageKey(image.request)];
    if (decoded == null) {
      // Undecodable (or images turned off): leave a labelled placeholder so the
      // reading position still reflects that something sat here.
      return _ImagePlaceholder(aspectRatio: image.aspectRatio);
    }
    final picture = ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: AspectRatio(
        aspectRatio: image.aspectRatio <= 0 ? 1 : image.aspectRatio,
        child: RawImage(
          image: decoded,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
    if (onTapImage == null) return picture;
    // Tap a figure to view it fullscreen (pan and pinch to zoom, share).
    return Semantics(
      button: true,
      label: pdfL10n(context).reflowViewFigure,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onTapImage!(decoded),
          child: picture,
        ),
      ),
    );
  }

  TextStyle? _styleFor(
      ThemeData theme, PdfReflowBlock block, double pageMedian) {
    final base = block.fontSize >= pageMedian * 1.3
        ? theme.textTheme.titleMedium
        : theme.textTheme.bodyLarge;
    return base?.copyWith(
      height: 1.45,
      fontWeight: block.fontSize >= pageMedian * 1.3
          ? FontWeight.w600
          : base.fontWeight,
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder({required this.aspectRatio});

  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AspectRatio(
      aspectRatio: aspectRatio <= 0 ? 1 : aspectRatio,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Icon(
            Icons.image_outlined,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// A fullscreen figure viewer: a dark backdrop with the image centered,
/// pan and pinch/scroll to zoom ([InteractiveViewer]), a close button, and -
/// when a share handler is supplied - a save/share action that renders the
/// image to a PNG. Owns [image] (a clone) and disposes it on close.
class _FullscreenReflowImage extends StatefulWidget {
  const _FullscreenReflowImage({required this.image, this.onShare});

  final ui.Image image;
  final PdfReflowImageShareHandler? onShare;

  @override
  State<_FullscreenReflowImage> createState() => _FullscreenReflowImageState();
}

class _FullscreenReflowImageState extends State<_FullscreenReflowImage> {
  bool _sharing = false;

  @override
  void dispose() {
    widget.image.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    final handler = widget.onShare;
    if (handler == null || _sharing) return;
    setState(() => _sharing = true);
    try {
      final data =
          await widget.image.toByteData(format: ui.ImageByteFormat.png);
      if (!mounted || data == null) return;
      await handler(context, data.buffer.asUint8List());
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            // SizedBox.expand gives RawImage tight viewport constraints, so
            // BoxFit.contain scales the figure to fit and centres it (a bare
            // RawImage would sit top-left at its intrinsic pixel size).
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 8,
              child: SizedBox.expand(
                child: RawImage(
                  image: widget.image,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  IconButton(
                    key: const ValueKey('pdf-reflow-image-close'),
                    icon: const Icon(Icons.close),
                    color: Colors.white,
                    tooltip: pdfL10n(context).close,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const Spacer(),
                  if (widget.onShare != null)
                    IconButton(
                      key: const ValueKey('pdf-reflow-image-share'),
                      icon: _sharing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.ios_share),
                      color: Colors.white,
                      tooltip: pdfL10n(context).reflowSaveOrShare,
                      onPressed: _sharing ? null : _share,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

double _median(Iterable<double> values) {
  final sorted = [...values]..sort();
  if (sorted.isEmpty) return 0;
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle];
  return (sorted[middle - 1] + sorted[middle]) / 2;
}
