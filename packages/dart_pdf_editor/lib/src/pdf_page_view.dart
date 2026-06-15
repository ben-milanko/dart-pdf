import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:pdf_document/pdf_document.dart';

import 'perf_log.dart';
import 'preview_cache.dart';
import 'render_scheduler.dart';
import 'render_worker.dart';
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
    this.renderWorker,
  });

  final PdfPage page;

  /// Offloads this page's interpretation (the content-stream parse + walk)
  /// to a background isolate when set and [showAnnotations] matches a
  /// serializable page — the picture is then replayed cheaply on this
  /// thread. Image-bearing pages and the null fallback render locally. Must
  /// be a worker started over the same bytes [page] belongs to.
  final PdfRenderWorker? renderWorker;

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

  /// The effective pixel ratio [_image] was last rasterized at. A settle
  /// that only moved the detail patch (scale unchanged) must not re-read
  /// the whole page back off the GPU — an expensive, uncancellable
  /// `toImage` on web — so [_renderNow] skips the full-page raster when
  /// this still matches.
  double? _rasteredRatio;

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
    if (oldWidget.previewIndex != widget.previewIndex) {
      // The lazy list reused this State for a different page (it scrolled into
      // this slot): cancel the old page's queued worker request — the user
      // scrolled past it, so decoding it now would only delay the page now on
      // screen. The in-flight one can't be preempted; this clears the backlog.
      oldWidget.renderWorker?.cancel(oldWidget.previewIndex, priority: 0);
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
    } else if (oldWidget.scale != widget.scale ||
        oldWidget.settleGeneration != widget.settleGeneration) {
      // scale change re-rasters the page; a settle that only moved the
      // viewport refreshes the detail patch. Both route through _render so
      // they pace and coalesce through the scheduler (_renderNow skips the
      // full-page raster when the resolution is unchanged).
      _render();
    }
  }

  @override
  void dispose() {
    widget.renderHold?.removeListener(_onRenderHoldChanged);
    widget.renderScheduler?.cancel(this);
    // Scrolled out of the cache window: drop this page's queued worker request
    // so the worker's next slot serves a page still on screen (the abandoned
    // result is ignored — _interpretPicture's !mounted guard skips the local
    // fallback). No-op if nothing is queued for it.
    widget.renderWorker?.cancel(widget.previewIndex, priority: 0);
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
    _rasteredRatio = null; // the next picture must re-raster, not be skipped
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
    final scheduler = widget.renderScheduler;
    if (scheduler != null) {
      // Route the first interpret AND every re-raster (zoom settle,
      // detail-patch follow) through the scheduler: it dedupes per page
      // (token), paces one render per frame, and defers while a scroll or
      // zoom is in flight. The first interpret walks the content stream
      // twice on the UI thread — what stalls fast scrolling on heavy
      // pages. Re-rasters are a `toImage`, cheap on a raster thread but a
      // single-threaded GPU readback on web: rapid zoom in/out used to
      // fire one uncancellable readback per settle and they piled up,
      // freezing the UI. Coalescing collapses them to the latest.
      scheduler.request(this, widget.previewIndex, _renderNow);
      return;
    }
    // The bare PdfPageView (no scheduler) defers only the first interpret
    // behind renderHold; cached re-rasters run directly.
    if (_picture == null && (widget.renderHold?.value ?? false)) {
      _holdPending = true;
      return;
    }
    await _renderNow();
  }

  /// Interprets the page into a picture, off the UI thread when a worker is
  /// available and the page is serializable, else locally. The worker path
  /// records the page on a background isolate and replays the returned
  /// command buffer here (cheap); image-bearing pages come back null and
  /// fall through to the local recorded render.
  Future<ui.Picture> _interpretPicture() async {
    final pageIndex = widget.previewIndex;
    final worker = widget.renderWorker;
    if (worker != null && worker.isActive) {
      // priority 0: the on-screen page preempts background prefetch
      final commands = await worker.record(pageIndex,
          annotations: widget.showAnnotations, priority: 0);
      // Abandoned while the worker ran — the State was disposed or the lazy
      // list recycled it onto another page (this is the cancel() path: a
      // cancelled request returns null). Skip the local fallback: the page is
      // gone, so a re-interpret would burn the UI thread for nothing — exactly
      // what the worker exists to avoid. Note we DON'T gate on the render
      // generation here: a newer same-page render (e.g. a zoom mid-interpret)
      // reuses this very future, so the picture must still be produced for it.
      if (_abandoned(pageIndex)) return _emptyPicture();
      if (commands != null) {
        _lastInterpretPath = 'worker';
        return PdfPageRenderer.pictureFromCommands(widget.page, commands,
            pageColor: widget.pageColor);
      }
    }
    if (_abandoned(pageIndex)) return _emptyPicture();
    // The worker may be active yet decline this page (it returns null), in
    // which case the interpret runs here — the log must say so, not 'worker'.
    _lastInterpretPath = 'recorded';
    return PdfPageRenderer.renderPictureRecorded(widget.page,
        pageColor: widget.pageColor, annotations: widget.showAnnotations);
  }

  /// Whether the page this render was for is gone — the widget unmounted, or
  /// the lazy list recycled this State onto a different page. Picture
  /// production stops here (no wasted local interpret); painting is gated
  /// separately by [_superseded], which also rejects a stale generation.
  bool _abandoned(int pageIndex) => !mounted || widget.previewIndex != pageIndex;

  /// Whether a render started at ([generation], [pageIndex]) must not paint —
  /// [_abandoned], or a newer render bumped the generation past this one.
  bool _superseded(int generation, int pageIndex) =>
      _abandoned(pageIndex) || generation != _renderGeneration;

  /// A zero-op picture for an abandoned render. Never painted (the caller's
  /// [_superseded] guards discard it); it only satisfies the return type.
  ui.Picture _emptyPicture() {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder);
    return recorder.endRecording();
  }

  /// Which path [_interpretPicture] actually took, for the perf log — 'worker'
  /// only when a command buffer came back and replayed, else 'recorded'.
  String _lastInterpretPath = 'recorded';

  /// The actual interpret + rasterize, run once the first render is no
  /// longer gated (or directly for re-rasters of a cached picture).
  Future<void> _renderNow() async {
    final generation = ++_renderGeneration;
    final pageIndex = widget.previewIndex;
    final firstInterpret = _picture == null;
    final sw = Stopwatch()..start();
    final picture = await (_picture ??= _interpretPicture());
    sw.stop();
    // Bail before logging when superseded — an abandoned interpret (page
    // recycled, disposed, or cancelled prefetch) never paints, so logging it
    // as a 'recorded' interpret would be a phantom UI-thread cost.
    if (_superseded(generation, pageIndex)) return;
    if (firstInterpret) {
      PdfPerfLog.interpret(pageIndex,
          path: _lastInterpretPath,
          interpretMs: sw.elapsedMicroseconds / 1000.0,
          first: true);
    }
    final effective = _effectiveRatio();
    // Skip the full-page readback when the cached raster is already at
    // this resolution: a settle that only moved the detail patch reaches
    // here too (one combined callback paces base + detail through the
    // scheduler), and re-reading the whole page off the GPU is the
    // expensive part on web.
    final stale = _image == null ||
        _rasteredRatio == null ||
        (effective - _rasteredRatio!).abs() > _rasteredRatio! * 0.01;
    if (stale) {
      final image = await PdfPageRenderer.rasterize(
          picture, PdfPageRenderer.pageSize(widget.page), effective);
      if (_superseded(generation, pageIndex)) {
        image.dispose();
        return;
      }
      // the previous raster stays up (transform-scaled) until this
      // replaces it, so zooming never flashes white
      setState(() {
        _image?.dispose();
        _image = image;
        _rasteredRatio = effective;
        _preview?.dispose();
        _preview = null;
      });
      widget.onRasterReady?.call();
      // feed the preview cache from the picture we already paid to
      // interpret — this is how previews appear for pages the background
      // prerender hasn't reached (and refresh after edits)
      final cache = widget.previewCache;
      if (cache != null && !cache.isFresh(widget.previewIndex, widget.page)) {
        unawaited(
            cache.putFromPicture(widget.previewIndex, widget.page, picture));
      }
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
