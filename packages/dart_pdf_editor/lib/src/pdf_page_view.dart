import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:pdf_document/pdf_document.dart';

import 'preview_cache.dart';
import 'render_scheduler.dart';
import 'renderer.dart';

/// Displays a single PDF page, rendered natively in Dart.
///
/// The page is interpreted once into a [ui.Picture]; changing [scale] only
/// re-rasterizes that cached picture, so zoom-driven re-renders are cheap.
/// Past the full-page raster caps, a detail patch covering the visible
/// part of the page (inflated for panning headroom) renders at full
/// resolution on top of the capped base — single patch, not a tile grid,
/// so the page is never interpreted more than once per zoom level.
class PdfPageView extends StatefulWidget {
  const PdfPageView({
    super.key,
    required this.page,
    this.scale = 1,
    this.settleGeneration = 0,
    this.pageColor = const Color(0xFFFFFFFF),
    this.showAnnotations = true,
    this.onRasterReady,
    this.renderHold,
    this.renderScheduler,
    this.previewCache,
    this.previewIndex = 0,
  });

  final PdfPage page;

  /// Shared low-res previews (see [PdfPagePreviewCache]): while this
  /// page's full render is pending — most visibly under [renderHold]
  /// during fast scrolling — the cached preview paints instead of the
  /// blank paper placeholder. When the full render lands, its picture
  /// refreshes the cache, so a page seen once keeps a preview after
  /// this state is long disposed.
  final PdfPagePreviewCache? previewCache;

  /// This page's index in [previewCache].
  final int previewIndex;

  /// While true, a page that has not been interpreted yet keeps its
  /// paper placeholder instead of starting the (UI-thread) interpreter
  /// walk — the viewer raises it during fast scrolling so heavy pages
  /// flying past can't stall the frame rate. Held pages render as soon
  /// as it drops back to false. Pages that already have a picture are
  /// unaffected (re-rasters reuse it).
  ///
  /// Superseded by [renderScheduler] when one is supplied: the scheduler
  /// both defers and paces the first interpret, so [renderHold] is only
  /// consulted on its own (the bare-[PdfPageView] case).
  final ValueListenable<bool>? renderHold;

  /// Paces this page's first (UI-thread) interpret against every other
  /// page's, so a settling fast scroll can't fire them all in one frame.
  /// When set, the page registers its first render here instead of
  /// interpreting directly; the scheduler grants it a turn (see
  /// [PdfPageRenderScheduler]). Re-rasters of an already-interpreted page
  /// bypass it. Null falls back to [renderHold].
  final PdfPageRenderScheduler? renderScheduler;

  /// Called whenever a full-page raster for the current [page] object
  /// lands on screen. Lets the editing overlay hold its just-committed
  /// preview exactly until the new revision is actually visible.
  final VoidCallback? onRasterReady;

  /// The paper color the page renders on (see
  /// [PdfPageRenderer.renderPicture]). Changing it re-renders the page.
  final Color pageColor;

  /// Whether the page's annotations render (see
  /// [PdfPageRenderer.renderPicture]). Changing it re-renders the page.
  final bool showAnnotations;

  /// Resolution multiplier on top of the device pixel ratio. The viewer
  /// raises it to the settled zoom level so pages stay sharp.
  final double scale;

  /// Bumped by the viewer when scrolling/zooming settles, so the detail
  /// patch can follow the viewport without the viewer knowing about it.
  final int settleGeneration;

  @override
  State<PdfPageView> createState() => _PdfPageViewState();
}

class _PdfPageViewState extends State<PdfPageView> {
  Future<ui.Picture>? _picture;
  ui.Image? _image;
  int _renderGeneration = 0;
  double? _pixelRatio;
  double? _layoutWidth;

  ui.Image? _detailImage;
  Rect? _detailFraction; // patch placement as fractions of the page
  int _detailGeneration = 0;

  /// Clone of this page's cached low-res preview; painted while no full
  /// raster exists, dropped (to free the buffer) the moment one lands.
  ui.Image? _preview;

  /// A render that arrived while [PdfPageView.renderHold] was up — it
  /// fires the moment the hold releases.
  bool _holdPending = false;

  // Full-page rasters stay within GPU texture limits and sane memory:
  // at most ~16.7M px (64 MB RGBA) and 8192 px per side. Past these caps
  // the detail patch takes over for the visible region.
  static const _maxPixels = 1 << 24;
  static const _maxDimension = 8192.0;

  @override
  void initState() {
    super.initState();
    widget.renderHold?.addListener(_onRenderHoldChanged);
    widget.previewCache?.addListener(_onPreviewCacheChanged);
    _refreshPreview();
  }

  void _onRenderHoldChanged() {
    if (widget.renderHold?.value == false && _holdPending) {
      _holdPending = false;
      if (mounted) _render();
    }
  }

  /// A background prerender landed somewhere; if this page is still
  /// showing its placeholder, its preview may just have arrived.
  void _onPreviewCacheChanged() {
    if (!mounted || _image != null || _preview != null) return;
    setState(_refreshPreview);
  }

  void _refreshPreview() {
    final cache = widget.previewCache;
    if (cache == null || _image != null) return;
    final next = cache.imageFor(widget.previewIndex);
    if (next == null) return; // keep whatever we already hold
    _preview?.dispose();
    _preview = next;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    if (ratio != _pixelRatio) {
      _pixelRatio = ratio;
      // before the first layout there is nothing to size against; the
      // initial render fires from the first LayoutBuilder pass instead
      if (_layoutWidth != null) _render();
    }
  }

  /// Re-rasterizes when the on-screen width changes meaningfully (window
  /// resize, move to another display). 5% hysteresis keeps live resizes
  /// from re-rendering on every frame; the old raster scales meanwhile.
  void _noteLayoutWidth(double width) {
    final previous = _layoutWidth;
    if (previous != null && (width - previous).abs() < previous * 0.05) {
      return;
    }
    _layoutWidth = width;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _render();
    });
  }

  @override
  void didUpdateWidget(PdfPageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.renderHold, widget.renderHold)) {
      oldWidget.renderHold?.removeListener(_onRenderHoldChanged);
      widget.renderHold?.addListener(_onRenderHoldChanged);
      _onRenderHoldChanged();
    }
    if (!identical(oldWidget.renderScheduler, widget.renderScheduler)) {
      oldWidget.renderScheduler?.cancel(this);
      // the new scheduler picks this page up on its next _render
    }
    if (!identical(oldWidget.previewCache, widget.previewCache) ||
        oldWidget.previewIndex != widget.previewIndex) {
      oldWidget.previewCache?.removeListener(_onPreviewCacheChanged);
      widget.previewCache?.addListener(_onPreviewCacheChanged);
      _preview?.dispose();
      _preview = null;
      _refreshPreview();
    }
    if (!identical(oldWidget.page, widget.page) ||
        oldWidget.pageColor != widget.pageColor ||
        oldWidget.showAnnotations != widget.showAnnotations) {
      _dropPicture();
      _dropDetail();
      _render();
    } else if (oldWidget.scale != widget.scale) {
      _render();
    } else if (oldWidget.settleGeneration != widget.settleGeneration) {
      // viewport settled somewhere new: refresh only the detail patch
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updateDetail();
      });
    }
  }

  @override
  void dispose() {
    widget.renderHold?.removeListener(_onRenderHoldChanged);
    widget.renderScheduler?.cancel(this);
    widget.previewCache?.removeListener(_onPreviewCacheChanged);
    _dropPicture();
    _image?.dispose();
    _detailImage?.dispose();
    _preview?.dispose();
    super.dispose();
  }

  void _dropPicture() {
    _picture?.then((picture) => picture.dispose());
    _picture = null;
  }

  void _dropDetail() {
    _detailGeneration++;
    if (_detailImage != null) {
      _detailImage?.dispose();
      _detailImage = null;
      _detailFraction = null;
      if (mounted) setState(() {});
    }
  }

  /// The resolution the current zoom actually wants, uncapped.
  double _desiredRatio() {
    final size = PdfPageRenderer.pageSize(widget.page);
    final width = math.max(1.0, size.width);
    // pages display fit-width, so the raster must match the on-screen
    // width — a 612pt page across a wide window needs far more pixels
    // than its nominal point size
    final fitWidth = (_layoutWidth ?? width) / width;
    return math.max(fitWidth * (_pixelRatio ?? 1.0) * widget.scale, 0.05);
  }

  double _effectiveRatio() {
    final size = PdfPageRenderer.pageSize(widget.page);
    final width = math.max(1.0, size.width);
    final height = math.max(1.0, size.height);
    var ratio = _desiredRatio();
    ratio = math.min(ratio, math.sqrt(_maxPixels / (width * height)));
    ratio = math.min(ratio, _maxDimension / math.max(width, height));
    return math.max(ratio, 0.05);
  }

  Future<void> _render() async {
    // Only the first interpretation is deferred: it walks the content
    // stream twice on the UI thread, which is what stalls fast scrolling
    // on heavy pages. With a picture cached, rendering is a raster-thread
    // toImage, so re-renders run directly.
    if (_picture == null) {
      final scheduler = widget.renderScheduler;
      if (scheduler != null) {
        // route the first walk through the viewer's paced drain so no
        // frame interprets more than one page (a settling fast scroll
        // used to release every held page in one event-loop turn)
        scheduler.request(this, widget.previewIndex, _renderNow);
        return;
      }
      if (widget.renderHold?.value ?? false) {
        _holdPending = true;
        return;
      }
    }
    await _renderNow();
  }

  /// The actual interpret + rasterize, run once the first render is no
  /// longer gated (or directly for re-rasters of a cached picture).
  Future<void> _renderNow() async {
    final generation = ++_renderGeneration;
    final picture = await (_picture ??= PdfPageRenderer.renderPicture(
        widget.page,
        pageColor: widget.pageColor,
        annotations: widget.showAnnotations));
    if (!mounted || generation != _renderGeneration) return;
    final image = await PdfPageRenderer.rasterize(
        picture, PdfPageRenderer.pageSize(widget.page), _effectiveRatio());
    if (!mounted || generation != _renderGeneration) {
      image.dispose();
      return;
    }
    // the previous raster stays up (transform-scaled) until this replaces
    // it, so zooming never flashes white
    setState(() {
      _image?.dispose();
      _image = image;
      _preview?.dispose();
      _preview = null;
    });
    widget.onRasterReady?.call();
    // feed the preview cache from the picture we already paid to
    // interpret — this is how previews appear for pages the background
    // prerender hasn't reached (and refresh after edits)
    final cache = widget.previewCache;
    if (cache != null && !cache.isFresh(widget.previewIndex, widget.page)) {
      unawaited(cache.putFromPicture(widget.previewIndex, widget.page, picture));
    }
    await _updateDetail();
  }

  /// Renders (or drops) the deep-zoom patch: the visible slice of the
  /// page, inflated by half a viewport on each side, at the resolution
  /// the zoom actually asks for.
  Future<void> _updateDetail() async {
    final generation = ++_detailGeneration;
    final desired = _desiredRatio();
    final effective = _effectiveRatio();
    if (desired <= effective * 1.05) {
      _dropDetail();
      return;
    }
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final pageRect = Rect.fromPoints(
      box.localToGlobal(Offset.zero),
      box.localToGlobal(Offset(box.size.width, box.size.height)),
    );
    final screen = Offset.zero & MediaQuery.sizeOf(context);
    final visible = pageRect.intersect(screen);
    if (visible.isEmpty || pageRect.width <= 0 || pageRect.height <= 0) {
      _dropDetail();
      return;
    }

    // visible slice as fractions of the page, inflated 50% per side
    final fraction = Rect.fromLTRB(
      ((visible.left - pageRect.left - visible.width / 2) / pageRect.width)
          .clamp(0.0, 1.0),
      ((visible.top - pageRect.top - visible.height / 2) / pageRect.height)
          .clamp(0.0, 1.0),
      ((visible.right - pageRect.left + visible.width / 2) / pageRect.width)
          .clamp(0.0, 1.0),
      ((visible.bottom - pageRect.top + visible.height / 2) / pageRect.height)
          .clamp(0.0, 1.0),
    );
    final size = PdfPageRenderer.pageSize(widget.page);
    final region = Rect.fromLTRB(
      fraction.left * size.width,
      fraction.top * size.height,
      fraction.right * size.width,
      fraction.bottom * size.height,
    );
    if (region.width <= 0 || region.height <= 0) {
      _dropDetail();
      return;
    }
    // the patch obeys the same pixel budget as the base
    var ratio = desired;
    ratio =
        math.min(ratio, math.sqrt(_maxPixels / (region.width * region.height)));
    ratio =
        math.min(ratio, _maxDimension / math.max(region.width, region.height));

    // never interpret the page for the first time inline here — that is
    // the scheduler's job (or, bare, the hold's); the next settle
    // refreshes the patch once the base picture lands
    if (_picture == null) {
      final scheduler = widget.renderScheduler;
      if (scheduler != null) {
        scheduler.request(this, widget.previewIndex, _renderNow);
        return;
      }
      if (widget.renderHold?.value ?? false) return;
    }
    final picture = await (_picture ??= PdfPageRenderer.renderPicture(
        widget.page,
        pageColor: widget.pageColor,
        annotations: widget.showAnnotations));
    if (!mounted || generation != _detailGeneration) return;
    final image = await PdfPageRenderer.rasterizeRegion(picture, region, ratio);
    if (!mounted || generation != _detailGeneration) {
      image.dispose();
      return;
    }
    setState(() {
      _detailImage?.dispose();
      _detailImage = image;
      _detailFraction = fraction;
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = PdfPageRenderer.pageSize(widget.page);
    final hasArea = size.width > 0 && size.height > 0;
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      if (width.isFinite && width > 0) _noteLayoutWidth(width);
      return AspectRatio(
        aspectRatio: hasArea ? size.width / size.height : 1,
        child: LayoutBuilder(builder: (context, inner) {
          final w = inner.maxWidth;
          final h = inner.maxHeight;
          final detail = _detailImage;
          final fraction = _detailFraction;
          return Stack(
              alignment: Alignment.topLeft,
              fit: StackFit.expand,
              children: [
                if (_image == null)
                  // before the first render lands: the low-res preview if
                  // the cache has one (fast scroll past a known page), else
                  // a placeholder matching the paper so nothing flashes. A
                  // translucent paper color washes over white, matching the
                  // renderer's white-backed raster.
                  _preview == null
                      ? (widget.pageColor.a < 1.0
                          ? ColoredBox(
                              color: const Color(0xFFFFFFFF),
                              child: ColoredBox(color: widget.pageColor),
                            )
                          : ColoredBox(color: widget.pageColor))
                      : RawImage(
                          image: _preview,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.medium,
                        )
                else
                  RawImage(
                    image: _image,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                  ),
                if (detail != null && fraction != null && w.isFinite)
                  Positioned(
                    left: fraction.left * w,
                    top: fraction.top * h,
                    width: fraction.width * w,
                    height: fraction.height * h,
                    child: RawImage(
                      image: detail,
                      fit: BoxFit.fill,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
              ]);
        }),
      );
    });
  }
}
