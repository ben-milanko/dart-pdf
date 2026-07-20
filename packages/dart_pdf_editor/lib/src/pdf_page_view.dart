import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart'
    show
        PdfDrawImageCommand,
        PdfEndSoftMaskedCommand,
        PdfMatrix,
        PdfRenderCommand;

import 'debug_overlays.dart';
import 'perf_log.dart';
import 'page_render_session.dart';
import 'performance_policy.dart';
import 'preview_cache.dart';
import 'render_scheduler.dart';
import 'render_worker.dart';
import 'renderer.dart';
import 'retained_scene.dart';
import 'strips/strip_device.dart';
import 'tile_layer.dart';
import 'tile_store.dart';

/// Displays a single PDF page, rendered natively in Dart.
///
/// The page is interpreted once into a [ui.Picture] and, by default, its
/// command transcript is retained as a [PdfRetainedScene]; changing [scale]
/// replays that scene into a fresh flat picture at the new resolution -
/// no re-interpretation, no image re-decoding, and no nested-picture
/// re-raster (which Impeller rasterizes several times slower than a flat
/// replay of the same draws).
/// Past the full-page raster caps, a detail patch covering the visible
/// part of the page (inflated for panning headroom) renders at full
/// resolution on top of the capped base - single patch, not a tile grid,
/// so the page is never interpreted more than once per zoom level.
class PdfPageView extends StatefulWidget {
  const PdfPageView({
    super.key,
    required this.page,
    this.rotation,
    this.scale = 1,
    this.settleGeneration = 0,
    this.pageColor = const Color(0xFFFFFFFF),
    this.showAnnotations = true,
    this.onRasterReady,
    this.renderHold,
    this.renderScheduler,
    this.renderPriority = 0,
    this.previewCache,
    this.previewIndex = 0,
    this.pageEpoch = 0,
    this.contentStamp = 0,
    this.trustContentStamp = false,
    this.destructiveStamp = 0,
    this.renderWorker,
    this.performance,
    this.workerImagePixelRatioCap,
    this.transformScale,
    this.transformChanges,
  });

  final PdfPage page;

  /// Display rotation override. When set, the page renders at this
  /// rotation instead of its own /Rotate - the view rotation feature
  /// rotates the display without modifying the document. Null (the
  /// default) uses the page's own /Rotate.
  final int? rotation;

  /// Offloads this page's interpretation (the content-stream parse + walk)
  /// to a background isolate when set and [showAnnotations] matches a
  /// serializable page - the picture is then replayed cheaply on this
  /// thread. Image-bearing pages and the null fallback render locally. Must
  /// be a worker started over the same bytes [page] belongs to.
  final PdfRenderWorker? renderWorker;

  /// Optional adaptive policy receiving first-render latency samples.
  final PdfPerformanceController? performance;

  /// Caps ordinary full-page worker image decode requests. Deep-zoom region
  /// requests stay uncapped so visible image detail can sharpen on demand.
  final double? workerImagePixelRatioCap;

  /// The viewer's LIVE zoom scale (the InteractiveViewer matrix's scale on
  /// every change), as opposed to [scale], which the viewer only updates at
  /// the debounced zoom settle. When set alongside [renderWorker], a dense
  /// strip-routed page uses it to bin its strip plan speculatively while the
  /// gesture quiesces: the settle then consumes the already-in-flight worker
  /// plan instead of starting the ~290 ms bin from scratch. Null (the
  /// default) disables speculation; settles behave exactly as before.
  final ValueListenable<double>? transformScale;

  /// The viewer's complete live transform notifier (scale and translation).
  ///
  /// [transformScale] only notifies when the numeric scale changes, so a
  /// deep-zoom pan leaves it quiet even though the visible detail region has
  /// moved. When supplied, this notifier drives strip speculation instead;
  /// the page reads its post-transform global bounds after the debounce and
  /// pre-requests the exact region-detail job the next settle will consume.
  /// Null falls back to [transformScale], preserving the standalone widget's
  /// zoom-only speculation behavior.
  final Listenable? transformChanges;

  /// Shared low-res previews (see [PdfPagePreviewCache]): while this
  /// page's full render is pending - most visibly under [renderHold]
  /// during fast scrolling - the cached preview paints instead of the
  /// blank paper placeholder. When the full render lands, its picture
  /// refreshes the cache, so a page seen once keeps a preview after
  /// this state is long disposed.
  final PdfPagePreviewCache? previewCache;

  /// This page's index in [previewCache].
  final int previewIndex;

  /// Bumped by the viewer whenever the document is swapped for a revision
  /// whose page structure differs (insert, remove, reorder). The lazy list
  /// has no per-page key, so it reconciles States by slot: after pages
  /// shift, a reused State keeps the same [previewIndex] while [page]
  /// silently becomes a different page, and its already-rastered [_image]/
  /// preview would otherwise keep painting the *old* page during a fast
  /// scroll. A changed epoch forces the stale rasters to drop and re-render.
  /// Unchanged across same-geometry (content-only) edits, so those keep
  /// re-rendering in place without a blank flash.
  final int pageEpoch;

  /// This page's content stamp (see [_PdfViewerPage.contentStamp]). Unlike
  /// [pageEpoch] it is per-page, so a content-only same-geometry edit that
  /// changed *this* page advances it while leaving untouched pages alone.
  /// When it changes the page re-renders, but the held raster and preview
  /// stay painted until the fresh render replaces them - an additive edit
  /// (ink, a highlight, a shape) on a heavy page must not flash the page
  /// blank, and the just-added markup rides on top through the editing
  /// overlay until the new raster (with it baked in) lands. 0 outside an
  /// editing session (never changes).
  final int contentStamp;

  /// When true, a new [page] object with the same [contentStamp] is treated as
  /// the same base page image. Editing revisions reopen the document and give
  /// every page a new object even for annotation-only changes; the viewer uses
  /// this flag when annotations are painted in a separate overlay.
  final bool trustContentStamp;

  /// This page's [PdfEditingController.pageDestructiveStamp]. Unlike
  /// [contentStamp] it advances only when an edit *removed* content from
  /// this page (a redaction burn). When it changes the held raster and
  /// preview are dropped immediately - keeping the pre-edit (un-redacted)
  /// content up, even for the frame before the re-render lands or in a
  /// fast-scroll preview, would expose the very content the burn deleted.
  /// 0 outside an editing session (never changes).
  final int destructiveStamp;

  /// While true, a page that has not been interpreted yet keeps its
  /// paper placeholder instead of starting the (UI-thread) interpreter
  /// walk - the viewer raises it during fast scrolling so heavy pages
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

  /// Worker queue priority for this page's on-screen record requests. Lower
  /// values win. The viewer ranks the page nearest the viewport above cache-
  /// window neighbours so a long jump paints the destination first.
  final int renderPriority;

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

  /// Kill switch for the retained-scene zoom replay. When true (the
  /// default) the page's recorded command buffer and decoded images are
  /// retained alongside the cached picture, and zoom re-rasters replay them
  /// into a flat picture at the new ratio - byte-identical output
  /// (retained_scene_test.dart), several times faster under Impeller. Set
  /// false to restore the previous behavior (re-rasterize the cached
  /// [ui.Picture]) if a regression is ever suspected in the field.
  static bool retainedZoomReplay = true;

  /// Command-count ceiling above which a page does NOT retain its scene and
  /// keeps the classic cached-picture zoom path.
  ///
  /// Replay cost is linear in the command count and runs on the UI thread
  /// (~0.7 µs/command measured), so a dense CAD sheet - the corpus stress
  /// case records ~99k commands - would pay ~65 ms of UI-thread replay per
  /// zoom settle where the nested-picture path pays ~3 ms and ships the
  /// raster off-thread. Not retaining (rather than retaining-but-not-
  /// replaying) also skips the command buffer's memory (~31 MB for that
  /// sheet) on exactly the pages where replay is never used. Office pages
  /// record a few hundred commands; at the 20k default a worst-case
  /// retained replay costs about one frame.
  static int retainedZoomReplayMaxCommands = 20000;

  /// Command-count ceiling for retaining a scene *solely to drive the deep-zoom
  /// tile path* ([tileStoreDetail]), above [retainedZoomReplayMaxCommands].
  ///
  /// [retainedZoomReplayMaxCommands] is about *flat replay* cost: a retained
  /// scene makes the full-page base raster a UI-thread replay, linear in the
  /// command count, so a dense sheet must not take that route. Tiling is a
  /// different consumer - each tile replays only the commands its region
  /// intersects (a few thousand, via the region/grid cull), never the whole
  /// transcript - so that argument does not bound it. Pages retained under this
  /// ceiling therefore keep the cached picture for the base raster
  /// ([_sceneIsTileOnly]) and use the scene only for region rasters.
  ///
  /// Why it matters: without this, a dense single-sheet drawing drops its scene,
  /// which disables tiling, which makes every pan step re-render the entire
  /// visible viewport - a measured ~235 ms worker round trip plus a 16.8 MP
  /// (67 MB) raster, per step, with nothing reused. Tiling turns that into a
  /// first fill plus an edge strip of new tiles.
  ///
  /// The default bounds the retained transcript to roughly 100 MB (~260 bytes
  /// per command, measured on a production CAD sheet: 850k commands retained
  /// 221 MB). Sheets past it keep today's behaviour rather than trade an
  /// unbounded retention for the win.
  static int retainedZoomReplayTileMaxCommands = 400000;

  /// Maximum estimated atlas batches allowed on the dense-page strip route.
  ///
  /// Command count alone does not predict strip performance. Some Visio/CAD
  /// exports wrap nearly every small shape in its own clip, forcing thousands
  /// of tiny painter-order batches. Every batch needs a separate alpha-atlas
  /// upload; at that topology the cached canvas picture is dramatically
  /// faster even though the page is dense. [StripReplayProfile] identifies
  /// the fragmentation without flattening paths or generating coverage.
  static int stripZoomReplayMaxEstimatedBatches = 256;

  /// Strip routing for pages ABOVE [retainedZoomReplayMaxCommands] whose
  /// topology stays under [stripZoomReplayMaxEstimatedBatches]: they retain
  /// their scene, and zoom-driven re-rasters (full page and deep-zoom detail
  /// patch) replay it through the sparse-strip shader device
  /// ([PdfRetainedScene.rasterizeStrips]) at the new ratio instead of
  /// re-rasterizing the cached nested picture. Pages under the ceiling keep
  /// the flat canvas replay - strips lose on office pages (fixed
  /// atlas-decode/replay overhead, and Impeller already rasterizes light
  /// flat pictures quickly).
  ///
  /// Default TRUE since worker-isolate strip binning landed: the two
  /// concerns that kept #210's router opt-in are gone. (1) Backend: the
  /// Impeller gate below turns the flag off automatically where strips
  /// lose, so no host knowledge is needed. (2) UI-thread cost: with a
  /// render worker attached the ~340 ms re-bin runs off-thread and the
  /// settle blocks the UI ~35 ms (measured, ly9-far-cad p4) - decode the
  /// plan, create engine objects, replay the tape. With [transformScale]
  /// wired (the viewer does), the bin is additionally requested
  /// speculatively while the zoom gesture quiesces, so most of the worker's
  /// bin wall time overlaps the viewer's own 200 ms settle debounce and the
  /// settle only waits for the residual. Set false to restore
  /// the cached-picture zoom path for dense pages if a regression is ever
  /// suspected in the field.
  ///
  /// Strip routing engages on web and supported non-iOS Impeller backends.
  /// Native software Skia's SkSL interpreter runs the coverage shader per
  /// fragment, making strips ~2x slower than the canvas there, so that backend
  /// keeps the classic cached-picture zoom path. iOS also keeps the canvas
  /// path: large drawVertices runtime-effect pictures can exhaust Metal
  /// snapshot resources and paint Flutter's diagnostic magenta partway through
  /// a dense page (OGW-30-06_Diagram.pdf produces 6,809 atlas batches at a
  /// normal iPad zoom). The web strip device and worker plan protocol are
  /// browser-validated together (CanvasKit/skwasm load the package fragment
  /// asset and produce the same plan-fed raster), while keeping the expensive
  /// bin walk off the main browser thread. Measured on macOS Impeller/Metal:
  /// the dense CAD sheet reaches sharp pixels ~4x sooner
  /// per zoom settle - and with a render worker attached the ~270 ms strip
  /// re-bin runs on the worker isolate ([PdfRenderWorker.binStrips]), so
  /// the UI thread only uploads the precomputed batches and replays the
  /// tape. Without a worker (or when it declines) the re-bin runs locally
  /// on the UI thread, the honest cost of the fastest available settle.
  static bool stripZoomReplay = true;

  /// Keeps a Slug-routed retained picture live on web for ordinary-size
  /// pages instead of flattening it into a bitmap on every zoom settle.
  /// CanvasKit evaluates the curve shader under the current canvas transform,
  /// so outline text stays sharp throughout a pinch and the page pays no
  /// settle readback. The complete painter-order picture stays live (rather
  /// than lifting glyphs into one topmost overlay), preserving text/vector
  /// occlusion, clips, groups, and soft masks exactly.
  ///
  /// Dense image-free pages above [retainedZoomReplayMaxCommands] receive a
  /// worker-built Slug/strip plan and only upload/replay it on the UI thread;
  /// if the worker declines they keep the ordinary worker-planned strip
  /// raster path rather than binning Slug locally.
  /// Image-bearing pages keep the same complete painter-order picture. At a
  /// capped deep zoom, a full-composite region raster supplies higher decode
  /// resolution while stationary and is removed during the next live
  /// transform so it cannot cover the sharp Slug base with stale raster text.
  static bool webSlugGlyphLayer = true;

  /// Defers a cold deep-zoom page's ordinary full-image refinement until its
  /// visible detail patch has rasterized and reached a frame.
  ///
  /// The detail request already outranks the full request in the worker queue;
  /// this additionally prevents the full decode from starting while the main
  /// thread turns the returned detail commands into the sharp on-screen patch.
  static bool deferFullRenderUntilDetailPaint = true;

  /// Composite deep-zoom detail from the [PdfTileStore] zoom-bucket pyramid
  /// instead of the single unbudgeted detail patch. When true (and the page
  /// retains a region-cullable scene), the visible slice is tiled: panning at
  /// deep zoom draws cached tiles with zero re-raster and a settle only
  /// rasterizes the missing tiles (batched into slab readbacks), all under one
  /// shared byte budget that evicts by least-recently used and drops under
  /// memory pressure.
  ///
  /// Additive to the existing pipeline: the tile layer sits ABOVE the base
  /// raster, so a gap not yet tiled shows the (capped) base image through it,
  /// and pages the region index cannot cull (soft-mask/group spans) keep the
  /// legacy single-patch path. On by default on every platform
  /// ([pdfDefaultTileStoreDetail], issues #314/#360) now the budget-vs-demand
  /// guard keeps a dense view from thrashing the shared pyramid.
  static bool tileStoreDetail = pdfDefaultTileStoreDetail();

  /// Test seam: the store the tile layer draws from. Null uses the shared
  /// [PdfTileStore.instance].
  static PdfTileStore? debugTileStoreOverride;

  /// Test hook for [webSlugGlyphLayer]. Null uses [kIsWeb].
  static bool? debugWebSlugGlyphLayerBackendOverride;

  /// Test hook for the shader-capability half of the backend gate:
  /// `flutter test` runs on software Skia where
  /// `ui.ImageFilter.isShaderFilterSupported` is false, so strip router tests
  /// force the decision. The iOS safety gate still applies when this is true.
  /// Null (production) asks the engine.
  static bool? debugStripZoomReplayBackendOverride;

  /// Settles that consumed a speculatively-binned worker strip plan (the
  /// [transformScale]-driven pre-request matched the settle's geometry
  /// exactly and resolved to a plan). Test telemetry, following the
  /// [StripPdfDevice.totalPlanMismatches] pattern.
  static int debugSpeculativePlanHits = 0;

  /// Speculative worker strip plans that were dropped unconsumed (the
  /// settle asked for a different geometry, a region bin superseded them,
  /// or the scene changed) or resolved null when consumed.
  static int debugSpeculativePlanMisses = 0;

  /// Deep-zoom settles that consumed a combined region-detail request issued
  /// while a live pan was quiescing.
  static int debugSpeculativeDetailHits = 0;

  /// Region-detail speculations that were stale, cancelled, or declined.
  static int debugSpeculativeDetailMisses = 0;

  static void debugResetSpeculativeStats() {
    debugSpeculativePlanHits = 0;
    debugSpeculativePlanMisses = 0;
    debugSpeculativeDetailHits = 0;
    debugSpeculativeDetailMisses = 0;
  }

  @override
  State<PdfPageView> createState() => _PdfPageViewState();
}

class _PdfPageViewState extends State<PdfPageView> {
  late final PdfPageRenderSession _renderSession;
  Future<ui.Picture>? _picture;

  /// Web-only retained strip picture whose outline-text draws use the Slug
  /// curve shader. Unlike [_image], this remains vector/shader-backed under
  /// the viewer's live transform and is reused across every zoom settle.
  ui.Picture? _slugPicture;
  bool _slugPictureRejected = false;

  /// The page retained as a replayable scene (commands + decoded images),
  /// produced by the same interpret that yielded [_picture]. Zoom re-rasters
  /// replay it into a flat picture at the new ratio instead of re-reading
  /// the nested cached picture. Null on fallback paths (then the classic
  /// [_picture] re-raster runs) and when [PdfPageView.retainedZoomReplay]
  /// is off. Lives and dies with [_picture] (see [_dropPicture]).
  PdfRetainedScene? _scene;
  ui.Image? _image;
  double? _pixelRatio;
  double? _layoutWidth;

  /// The effective pixel ratio [_image] was last rasterized at. A settle
  /// that only moved the detail patch (scale unchanged) must not re-read
  /// the whole page back off the GPU - an expensive, uncancellable
  /// `toImage` on web - so [_renderNow] skips the full-page raster when
  /// this still matches.
  double? _rasteredRatio;

  ui.Image? _detailImage;
  Rect? _detailFraction; // patch placement as fractions of the page

  /// Visible slice (fraction of the page) and desired ratio for the
  /// [PdfPageView.tileStoreDetail] tile layer, recomputed on each settle in
  /// [_refreshTileGeometry] - post-render, never during layout - so `build`
  /// reads a stored value instead of probing the render tree. Null when the
  /// tile path is inactive.
  Rect? _tileFraction;
  double? _tileDesiredRatio;

  /// Clone of this page's cached low-res preview; painted while no full
  /// raster exists, dropped (to free the buffer) the moment one lands.
  ui.Image? _preview;

  // Full-page rasters stay within GPU texture limits and sane memory:
  // at most ~16.7M px (64 MB RGBA) and 8192 px per side. Past these caps
  // the detail patch takes over for the visible region.
  static const _maxPixels = 1 << 24;
  static const _maxDimension = 8192.0;
  // Pixel budget for the progressive vector-first preview raster - a fraction
  // of [_maxPixels]. The preview is transient (the full pass re-rasterizes at
  // [_effectiveRatio] on settle), so bounding it keeps rasterizing a dense
  // large-format CAD sheet's linework (~8000px wide, tens of thousands of
  // vector ops) off the ~300ms GPU-raster spike that stutters a mid-scroll
  // page-in. Normal-sized pages fit well under this, so they are unaffected.
  static const _previewMaxPixels = 1 << 21;

  PdfPageRenderPlan get _renderPlan => PdfPageRenderPlan(
        pageColor: widget.pageColor,
        annotations: widget.showAnnotations,
        rotation: widget.rotation,
      );

  PdfPageRenderIntent _renderIntent(PdfPageView source) => PdfPageRenderIntent(
        page: source.page,
        pageIndex: source.previewIndex,
        pageEpoch: source.pageEpoch,
        contentStamp: source.contentStamp,
        destructiveStamp: source.destructiveStamp,
        trustContentStamp: source.trustContentStamp,
        rotation: source.rotation,
        pageColor: source.pageColor,
        showAnnotations: source.showAnnotations,
        scale: source.scale,
        settleGeneration: source.settleGeneration,
      );

  @override
  void initState() {
    super.initState();
    PdfLivePageRegistry.instance.add(widget.previewIndex);
    _renderSession = PdfPageRenderSession(_renderIntent(widget));
    widget.renderHold?.addListener(_onRenderHoldChanged);
    widget.previewCache?.addListener(_onPreviewCacheChanged);
    _liveTransformFor(widget)?.addListener(_onLiveTransformChanged);
    _refreshPreview();
  }

  /// How long the live transform must stay quiet before a speculative strip
  /// bin fires. During active motion matrix events arrive every frame, so
  /// this timer keeps resetting and nothing fires; once motion pauses 50 ms
  /// we bin speculatively - 150 ms of the viewer's 200 ms settle debounce
  /// then overlaps the ~290 ms worker bin. Firing on every tick instead
  /// would cancel-churn the worker continuously for no benefit.
  static const _speculateDebounce = Duration(milliseconds: 50);

  Timer? _speculateTimer;

  /// The in-flight/completed speculative worker bin (geometry + future) the
  /// next full-page settle may consume. See [_speculateStripPlan].
  _SpeculativeStripPlan? _speculativeStripPlan;

  /// The combined region commands + strip plan requested while a deep-zoom
  /// pan is quiescing. The next detail settle consumes it only on an exact
  /// geometry match.
  _SpeculativeStripDetail? _speculativeStripDetail;

  static Listenable? _liveTransformFor(PdfPageView widget) =>
      widget.transformChanges ?? widget.transformScale;

  void _onLiveTransformChanged() {
    // A settled detail patch is a complete high-resolution raster composite.
    // Drop it at the first live transform tick when a painter-order Slug
    // picture sits underneath, so stale raster text cannot scale over and
    // hide the transform-sharp glyphs during pinch/pan. The next settle
    // rebuilds the complete detail composite for image resolution.
    if (_slugPicture != null && _detailImage != null) _dropDetail();
    _speculateTimer?.cancel();
    _speculateTimer = Timer(_speculateDebounce, _speculateStripPlan);
  }

  void _onRenderHoldChanged() {
    if (widget.renderHold?.value == false && _renderSession.releaseHold()) {
      if (mounted) _render();
    }
  }

  /// A background prerender landed somewhere; if this page is still
  /// showing its placeholder, its preview may just have arrived.
  void _onPreviewCacheChanged() {
    if (!mounted ||
        _image != null ||
        _slugPicture != null ||
        _preview != null) {
      return;
    }
    setState(_refreshPreview);
  }

  void _refreshPreview() {
    final cache = widget.previewCache;
    if (cache == null || _image != null || _slugPicture != null) return;
    final next = cache.imageFor(widget.previewIndex);
    if (next == null) return; // keep whatever we already hold
    _preview?.dispose();
    _preview = next;
    PdfPerfLog.log('preview-paint page=${widget.previewIndex}');
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
    final transition = _renderSession.update(_renderIntent(widget));
    if (!identical(oldWidget.renderHold, widget.renderHold)) {
      oldWidget.renderHold?.removeListener(_onRenderHoldChanged);
      widget.renderHold?.addListener(_onRenderHoldChanged);
      _onRenderHoldChanged();
    }
    if (!identical(oldWidget.renderScheduler, widget.renderScheduler)) {
      oldWidget.renderScheduler?.cancel(this);
      // the new scheduler picks this page up on its next _render
    }
    final oldLiveTransform = _liveTransformFor(oldWidget);
    final liveTransform = _liveTransformFor(widget);
    if (!identical(oldLiveTransform, liveTransform)) {
      oldLiveTransform?.removeListener(_onLiveTransformChanged);
      liveTransform?.addListener(_onLiveTransformChanged);
    }
    if (oldWidget.previewIndex != widget.previewIndex) {
      PdfLivePageRegistry.instance
          .move(oldWidget.previewIndex, widget.previewIndex);
      PdfDebugDetailRegions.instance.report(oldWidget.previewIndex, null);
      // The lazy list reused this State for a different page (it scrolled into
      // this slot): cancel the old page's queued worker request - the user
      // scrolled past it, so decoding it now would only delay the page now on
      // screen. The in-flight one can't be preempted; this clears the backlog.
      oldWidget.renderWorker?.cancel(
        oldWidget.previewIndex,
        priority: oldWidget.renderPriority,
      );
      oldWidget.renderWorker?.cancelBinStrips(
        oldWidget.previewIndex,
        priority: oldWidget.renderPriority,
      );
    }
    if (!identical(oldWidget.previewCache, widget.previewCache) ||
        oldWidget.previewIndex != widget.previewIndex) {
      oldWidget.previewCache?.removeListener(_onPreviewCacheChanged);
      widget.previewCache?.addListener(_onPreviewCacheChanged);
      _preview?.dispose();
      _preview = null;
      _refreshPreview();
    }
    if (transition.dropBaseRaster) {
      // Either a structural document change reused this State for a different
      // page at the same slot (pageEpoch; previewIndex unchanged, so the
      // branches above don't fire), or content was removed from this page in
      // a same-geometry edit (destructiveStamp - a redaction burn). Either
      // way the held raster and preview show content that must not linger:
      // drop them so neither the gap before the re-render nor a fast-scroll
      // preview can flash the old (or, after a redaction, removed) content;
      // the preview cache (cleared for changed pages) and _render below
      // repaint. An *additive* same-geometry edit (ink, a highlight, a
      // shape - contentStamp only) deliberately does NOT land here: its old
      // raster stays painted until the fresh one replaces it.
      _image?.dispose();
      _image = null;
      _preview?.dispose();
      _preview = null;
    }
    if (transition.dropPicture) {
      // Re-interpret at the new content/page. Unless we blanked above, the
      // old base raster stays up until the new render replaces it -
      // _dropPicture nulls _rasteredRatio so _renderNow still re-rasters -
      // so an additive edit on a heavy page never flashes blank.
      _dropPicture();
      if (transition.dropDetail) {
        // The deep-zoom detail patch is a sharper raster layered above the
        // base. For additive annotation edits, keep the stale patch for
        // sharpness and let the editing overlay's commit afterimage cover the
        // new annotation until the fresh patch lands. For destructive edits
        // and display-setting changes there is no safe afterimage, so drop it.
        _dropDetail();
      }
    }
    if (transition.scheduleRender) {
      // scale change re-rasters the page; a settle that only moved the
      // viewport refreshes the detail patch. Both route through _render so
      // they pace and coalesce through the scheduler (_renderNow skips the
      // full-page raster when the resolution is unchanged).
      _render();
    }
  }

  @override
  void dispose() {
    PdfLivePageRegistry.instance.remove(widget.previewIndex);
    PdfDebugDetailRegions.instance.report(widget.previewIndex, null);
    widget.renderHold?.removeListener(_onRenderHoldChanged);
    _liveTransformFor(widget)?.removeListener(_onLiveTransformChanged);
    _speculateTimer?.cancel();
    // any pending speculative bin is reaped by the cancelBinStrips below;
    // its null result resolves into a future nobody awaits any more
    _speculativeStripPlan = null;
    _speculativeStripDetail = null;
    widget.renderScheduler?.cancel(this);
    // Scrolled out of the cache window: drop this page's queued worker request
    // so the worker's next slot serves a page still on screen (the abandoned
    // result is ignored - _interpretPicture's !mounted guard skips the local
    // fallback). No-op if nothing is queued for it.
    widget.renderWorker?.cancel(
      widget.previewIndex,
      priority: widget.renderPriority,
    );
    widget.renderWorker?.cancelBinStrips(
      widget.previewIndex,
      priority: widget.renderPriority,
    );
    widget.previewCache?.removeListener(_onPreviewCacheChanged);
    _renderSession.dispose();
    _dropPicture();
    _image?.dispose();
    _detailImage?.dispose();
    _preview?.dispose();
    super.dispose();
  }

  void _dropPicture() {
    _picture?.then((picture) => picture.dispose());
    _picture = null;
    _slugPicture?.dispose();
    _slugPicture = null;
    _setScene(null); // the scene transcribes the same content as the picture
    _rasteredRatio = null; // the next picture must re-raster, not be skipped
  }

  /// Adopts [scene] as the page's retained scene, disposing the previous
  /// one. Outstanding pictures replayed from the old scene keep painting
  /// (they hold their own image refs); only new replays need the new scene.
  ///
  /// [fromWorker] marks a scene built from a worker-recorded command buffer
  /// (its geometry carries the wire codec's float32 truncation and its
  /// content matches what the worker would re-record). ONLY such scenes may
  /// consume worker-binned strip plans; locally-recorded scenes - the
  /// worker declined, or an editing flow recorded with skipAnnotation -
  /// keep local binning, because a worker re-record could desync from them.
  void _setScene(
    PdfRetainedScene? scene, {
    bool fromWorker = false,
    bool vectorOnly = false,
  }) {
    _scene?.dispose();
    _scene = scene;
    _sceneHasImageDraws =
        scene != null && PdfPageRenderer.hasImageDraws(scene.commands);
    _sceneFromWorker = scene != null && fromWorker;
    _sceneIsVectorOnly = scene != null && vectorOnly;
    // A vector-only scene may feed the tile path everywhere its absent image
    // pixels can't corrupt a tile; a full scene has no veto.
    _tileCanRasterize = scene != null && vectorOnly && _sceneHasImageDraws
        ? (region) => !_imagesIntersectRegion(scene.commands, region)
        : null;
    _slugPictureRejected = false;
    // a speculative bin's geometry was computed against the previous scene;
    // with the scene identity changed it is meaningless, so drop it (the
    // next _workerStripPlan's cancelBinStrips reaps the worker-side job)
    _speculativeStripPlan = null;
    _speculativeStripDetail = null;
  }

  /// Whether [_scene] came from the render worker (see [_setScene]).
  bool _sceneFromWorker = false;

  /// The retained scene currently carries image placeholders from the
  /// progressive vector-first record. It can route a visible-region worker
  /// request, but must not be used as that detail's local fallback because
  /// its image pixels are deliberately absent. The full record replaces it.
  bool _sceneIsVectorOnly = false;

  /// Whether the retained command stream paints any PDF images.
  ///
  /// Cached at scene adoption so deep-zoom settles do not rescan a dense CAD
  /// page's command list on every pan.
  bool _sceneHasImageDraws = false;

  /// Drops this page's retained tiles when its content is replaced (edit,
  /// redaction, display change), the tile analogue of [_dropDetail]. Content
  /// stamps already key stale tiles out; this frees them eagerly and discards
  /// any in-flight raster from the superseded scene (issue #308's model).
  void _invalidateTiles() {
    if (!PdfPageView.tileStoreDetail) return;
    (PdfPageView.debugTileStoreOverride ?? PdfTileStore.instance)
        .invalidate(pages: {widget.previewIndex});
  }

  void _dropDetail() {
    _invalidateTiles();
    _renderSession.invalidateDetail();
    if (_detailImage != null) {
      _detailImage?.dispose();
      _detailImage = null;
      _detailFraction = null;
      if (mounted) setState(() {});
    }
  }

  /// The uncapped resolution at an explicit [scale], so speculation can price
  /// the scale a settle is ABOUT to apply.
  double _desiredRatioAt(double scale) {
    final size = _renderPlan.pageSize(widget.page);
    final width = math.max(1.0, size.width);
    // pages display fit-width, so the raster must match the on-screen
    // width - a 612pt page across a wide window needs far more pixels
    // than its nominal point size
    final fitWidth = (_layoutWidth ?? width) / width;
    return math.max(fitWidth * (_pixelRatio ?? 1.0) * scale, 0.05);
  }

  double _effectiveRatio() => _effectiveRatioAt(widget.scale);

  /// [_effectiveRatio] at an explicit [scale] (see [_desiredRatioAt]).
  double _effectiveRatioAt(double scale) {
    final size = _renderPlan.pageSize(widget.page);
    final width = math.max(1.0, size.width);
    final height = math.max(1.0, size.height);
    var ratio = _desiredRatioAt(scale);
    ratio = math.min(ratio, math.sqrt(_maxPixels / (width * height)));
    ratio = math.min(ratio, _maxDimension / math.max(width, height));
    return math.max(ratio, 0.05);
  }

  /// Resolution for the progressive vector-first preview raster: [_effectiveRatio]
  /// further bounded by [_previewMaxPixels] so a dense large-format sheet paints
  /// its linework quickly instead of spiking the GPU raster thread. The full
  /// pass re-rasterizes at [_effectiveRatio] once the page settles, so the only
  /// visible effect is a briefly softer preview while actively scrolling.
  double _vectorFirstRatio() {
    final size = _renderPlan.pageSize(widget.page);
    final width = math.max(1.0, size.width);
    final height = math.max(1.0, size.height);
    final ratio = math.min(
      _effectiveRatio(),
      math.sqrt(_previewMaxPixels / (width * height)),
    );
    return math.max(ratio, 0.05);
  }

  (int width, int height) _rasterDimensions(double pixelRatio) {
    final size = _renderPlan.pageSize(widget.page);
    return (
      (size.width * pixelRatio).ceil().clamp(1, 1 << 14),
      (size.height * pixelRatio).ceil().clamp(1, 1 << 14),
    );
  }

  /// Restores an exact recent-page raster without waiting for render hold.
  ///
  /// This path is deliberately ahead of the scheduler: the image has already
  /// been interpreted and read back at the requested physical size, so using
  /// it cannot introduce the UI-thread hitch that fast-scroll hold prevents.
  bool _restoreFullRaster() {
    final cache = widget.previewCache;
    if (cache == null ||
        _image != null ||
        _slugPicture != null ||
        _layoutWidth == null ||
        _pixelRatio == null) {
      return false;
    }
    final effective = _effectiveRatio();
    final dimensions = _rasterDimensions(effective);
    final image = cache.fullImageFor(
      widget.previewIndex,
      widget.page,
      width: dimensions.$1,
      height: dimensions.$2,
      pageColor: widget.pageColor,
      annotations: widget.showAnnotations,
      rotation: widget.rotation,
    );
    if (image == null) return false;
    widget.renderScheduler?.cancel(this);
    _renderSession.invalidateFull();
    setState(() {
      _image = image;
      _rasteredRatio = effective;
      _preview?.dispose();
      _preview = null;
    });
    PdfPerfLog.log(
      'full-raster cache hit page=${widget.previewIndex} '
      '${image.width}x${image.height}',
    );
    widget.onRasterReady?.call();
    return true;
  }

  Future<void> _render() async {
    if (_restoreFullRaster()) return;
    // A fit-scale cache restore has no retained picture/scene, but it already
    // is the exact requested raster. A later scroll-settle generation must not
    // interpret the page merely to discover that the readback is current.
    // Zoomed pages still proceed: they may need a retained scene and visible
    // detail patch even when the capped base raster happens to match.
    final rastered = _rasteredRatio;
    if (_picture == null &&
        _image != null &&
        rastered != null &&
        widget.scale <= 1.05 &&
        (_effectiveRatio() - rastered).abs() <= rastered * 0.01) {
      return;
    }
    await _renderSession.request(
      owner: this,
      hasPicture: _picture != null,
      scheduler: widget.renderScheduler,
      hold: widget.renderHold,
      render: _renderNow,
    );
  }

  bool get _renderPaused => _renderSession.paused(
        scheduler: widget.renderScheduler,
        hold: widget.renderHold,
      );

  /// Interprets the page into a picture, off the UI thread when a worker is
  /// available and the page is serializable, else locally. The worker path
  /// records the page on a background isolate and replays the returned
  /// command buffer here (cheap); image-bearing pages come back null and
  /// fall through to the local recorded render.
  ///
  /// Both paths go through a recorded command buffer, so alongside the
  /// picture they also return the [PdfRetainedScene] built from that same
  /// buffer (null when [PdfPageView.retainedZoomReplay] is off) - the caller
  /// adopts it once the render is known not to be superseded - and whether
  /// the buffer came from the worker (see [_setScene]'s fromWorker).
  Future<(ui.Picture, PdfRetainedScene?, bool)?> _interpretPicture() async {
    final pageIndex = widget.previewIndex;
    final worker = widget.renderWorker;
    if (worker != null && worker.isActive) {
      // priority 0: the on-screen page preempts background prefetch.
      // imagePixelRatio caps embedded images to ~2x the page's on-screen
      // resolution so a CAD raster underlay isn't decoded/shipped/rasterized
      // at its native 100+ megapixels (the deep-zoom patch re-rasters the
      // visible region for sharper zoom).
      final commands = await worker.record(
        pageIndex,
        annotations: widget.showAnnotations,
        priority: widget.renderPriority,
        imagePixelRatio: math.min(
          _effectiveRatio(),
          widget.workerImagePixelRatioCap ?? double.infinity,
        ),
      );
      // Abandoned while the worker ran - the State was disposed or the lazy
      // list recycled it onto another page (this is the cancel() path: a
      // cancelled request returns null). Skip the local fallback: the page is
      // gone, so a re-interpret would burn the UI thread for nothing - exactly
      // what the worker exists to avoid. Note we DON'T gate on the render
      // generation here: a newer same-page render (e.g. a zoom mid-interpret)
      // reuses this very future, so the picture must still be produced for it.
      if (_abandoned(pageIndex)) return (_emptyPicture(), null, false);
      if (commands != null) {
        if (_renderPaused) return null;
        _lastInterpretPath = 'worker';
        _lastInterpretResultBytes = _logImageStats(pageIndex, commands);
        final (picture, scene) = await _replayableFromCommands(commands);
        return (picture, scene, true);
      }
    }
    if (_abandoned(pageIndex)) return (_emptyPicture(), null, false);
    if (_renderPaused) return null;
    // The worker may be active yet decline this page (it returns null), in
    // which case the interpret runs here - the log must say so, not 'worker'.
    _lastInterpretPath = 'recorded';
    if (!PdfPageView.retainedZoomReplay) {
      return (
        await PdfPageRenderer.renderPictureRecordedWithPlan(
          widget.page,
          _renderPlan,
        ),
        null,
        false,
      );
    }
    // Same record + decode renderPictureRecordedWithPlan runs internally,
    // but the command buffer and decoded images are kept for zoom replays
    // instead of being discarded after the 1:1 replay below.
    final scene = await PdfRetainedScene.record(widget.page, plan: _renderPlan);
    _lastInterpretResultBytes = _logImageStats(pageIndex, scene.commands);
    if (!_retainScene(scene.commands)) {
      // Too dense or too fragmented to replay per zoom settle: take the 1:1
      // picture (it holds its own image refs) and drop the scene - the classic
      // cached-picture path serves this page's zooms.
      final picture = scene.replay(pixelRatio: 1);
      scene.dispose();
      return (picture, null, false);
    }
    return (scene.replay(pixelRatio: 1), scene, false);
  }

  /// Whether a page's recorded commands should retain their scene - the
  /// [PdfPageView.retainedZoomReplay] switch plus the
  /// [PdfPageView.retainedZoomReplayMaxCommands] density ceiling. With
  /// [PdfPageView.stripZoomReplay] on, eligible over-ceiling pages retain too:
  /// their zooms re-bin through the strip device instead of the flat replay.
  static bool _retainScene(List<PdfRenderCommand> commands) =>
      PdfPageView.retainedZoomReplay &&
      (commands.length <= PdfPageView.retainedZoomReplayMaxCommands ||
          _stripReplayCommands(commands) ||
          _retainForTiles(commands));

  /// Whether a page too dense for flat replay is still worth retaining to feed
  /// the tile path (see [PdfPageView.retainedZoomReplayTileMaxCommands]).
  ///
  /// Region-cull support is deliberately NOT checked here: proving it means
  /// building the spatial index, an O(commands) walk that would become a
  /// UI-thread hitch at exactly the sizes this admits. The index is built lazily
  /// on the first region raster instead; if the page turns out not to be
  /// cullable, [_useTilePath] simply stays false and the retention is wasted -
  /// bounded, by the ceiling, to the memory the ceiling allows.
  static bool _retainForTiles(List<PdfRenderCommand> commands) =>
      PdfPageView.tileStoreDetail &&
      commands.length <= PdfPageView.retainedZoomReplayTileMaxCommands;

  /// Whether [scene] is retained purely to feed tiles - dense enough that a
  /// full-page flat replay would be a UI-thread hitch, and not on the strip
  /// route. The full-page base raster keeps the cached picture for these; only
  /// region rasters (which cull) go through the scene.
  static bool _sceneIsTileOnly(PdfRetainedScene scene) =>
      scene.commands.length > PdfPageView.retainedZoomReplayMaxCommands &&
      !_stripReplayCommands(scene.commands);

  static bool _stripReplayCommands(List<PdfRenderCommand> commands) =>
      PdfPageView.stripZoomReplay &&
      _stripBackendSupported &&
      StripReplayProfile.of(commands).estimatedBatchCount <=
          PdfPageView.stripZoomReplayMaxEstimatedBatches;

  /// Whether the runtime backend supports the strip route: web (validated
  /// through the worker/device probe), or a non-iOS native Impeller backend
  /// (`ui.ImageFilter.isShaderFilterSupported`). iOS deliberately stays on
  /// the canvas path; see [stripZoomReplay]. Consulted by BOTH the retention
  /// decision ([_retainScene], at scene-adoption time) and the settle router
  /// ([_stripReplayScene]) so a dense page retained for strips actually
  /// strips - the two must never disagree.
  static bool get _stripBackendSupported {
    final shaderSupported = PdfPageView.debugStripZoomReplayBackendOverride ??
        (kIsWeb || ui.ImageFilter.isShaderFilterSupported);
    return shaderSupported &&
        (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS);
  }

  /// Whether [scene]'s zoom re-rasters route through the strip device: the
  /// flag, the Impeller backend gate, and only above the ceiling (under it
  /// the flat canvas replay wins - see [PdfPageView.stripZoomReplay]).
  static bool _stripReplayScene(PdfRetainedScene scene) =>
      PdfPageView.stripZoomReplay &&
      _stripBackendSupported &&
      scene.commands.length > PdfPageView.retainedZoomReplayMaxCommands &&
      scene.stripReplayEstimatedBatchCount <=
          PdfPageView.stripZoomReplayMaxEstimatedBatches;

  bool _slugPictureScene(PdfRetainedScene? scene) =>
      scene != null &&
      PdfPageView.webSlugGlyphLayer &&
      (PdfPageView.debugWebSlugGlyphLayerBackendOverride ?? kIsWeb) &&
      scene.hasSlugTextCandidates &&
      (scene.commands.length <= PdfPageView.retainedZoomReplayMaxCommands ||
          _workerBinningEligible);

  /// Builds the picture (and, unless [PdfPageView.retainedZoomReplay] is
  /// off, the retained scene) from a recorded command buffer. One decode
  /// pass serves both, and the picture IS the scene's own 1:1 replay, so
  /// the pair can never disagree.
  Future<(ui.Picture, PdfRetainedScene?)> _replayableFromCommands(
    List<PdfRenderCommand> commands,
  ) async {
    if (!_retainScene(commands)) {
      return (
        await PdfPageRenderer.pictureFromCommandsWithPlan(
          widget.page,
          commands,
          _renderPlan,
        ),
        null,
      );
    }
    final scene = await PdfRetainedScene.fromCommands(
      widget.page,
      commands,
      plan: _renderPlan,
    );
    return (scene.replay(pixelRatio: 1), scene);
  }

  /// Progressive rendering's fast first pass: records the page WITHOUT decoding
  /// its images (so it returns quickly even when a raster underlay takes
  /// seconds to decode) and paints the vector/text at once, images skipped.
  /// The full pass in [_renderNow] then re-rasters with the images in. No-op
  /// without an active worker (the local render already decodes inline).
  ///
  /// When the page draws no images the fast buffer is the whole page, so it is
  /// cached as [_picture] for the full pass to reuse - no second record.
  Future<Completer<bool>?> _paintVectorFirst(
      int generation, int pageIndex) async {
    final worker = widget.renderWorker;
    if (worker == null || !worker.isActive) return null;
    // A zoomed, visible page's lightweight transcript is the prerequisite for
    // its sharp region. Give it a clear lead over ordinary neighbouring-page
    // work so it preempts the pool instead of being cancelled and requeued as
    // the scheduler drains the cache window around it.
    final visibleDetailRequested =
        _detailGeometryAt(widget.scale, force: true, inflation: 0.125) != null;
    final commands = await worker.record(
      pageIndex,
      annotations: widget.showAnnotations,
      priority: visibleDetailRequested
          ? widget.renderPriority - 100
          : widget.renderPriority,
      decodeImages: false,
    );
    if (_superseded(generation, pageIndex) ||
        _renderPaused ||
        commands == null) {
      return null;
    }

    final retainScene = _retainScene(commands);
    if (!PdfPageRenderer.hasImageDraws(commands)) {
      // Image-free page: this fast buffer already is the complete page. Cache
      // it (and its retained scene) so the full pass reuses it instead of
      // recording a second time; the normal raster path below paints it.
      _lastInterpretPath = 'worker';
      _lastInterpretResultBytes = 0;
      if (retainScene) {
        // No images to decode, so this completes synchronously in practice.
        final scene = await PdfRetainedScene.fromCommands(
          widget.page,
          commands,
          plan: _renderPlan,
        );
        if (_superseded(generation, pageIndex)) {
          scene.dispose();
          return null;
        }
        _setScene(scene, fromWorker: true);
        _picture = Future.value(scene.replay(pixelRatio: 1));
      } else {
        _picture = PdfPageRenderer.pictureFromCommandsWithPlan(
          widget.page,
          commands,
          _renderPlan,
        );
      }
      return null;
    }

    // In a zoomed view the visible region can sharpen without waiting
    // for the full-page image decode. Retain this lightweight placeholder
    // scene long enough to route that worker request now; the normal full
    // record below still replaces it and warms the complete page base.
    final progressiveDetail = _detailGeometryAt(
      widget.scale,
      force: true,
      inflation: 0.125,
    );
    final needsDetail = progressiveDetail != null;
    PdfPerfLog.log(
      'vector-first detail page=$pageIndex '
      'scale=${widget.scale.toStringAsFixed(2)} eligible=$needsDetail '
      'retained=$retainScene '
      'commands=${commands.length}${PdfPerfLog.rssSuffix()}',
    );
    if (needsDetail && retainScene) {
      final scene = await PdfRetainedScene.fromCommands(
        widget.page,
        commands,
        plan: _renderPlan,
        includeImages: false,
      );
      if (_superseded(generation, pageIndex) || _renderPaused) {
        scene.dispose();
        return null;
      }
      _setScene(scene, fromWorker: true, vectorOnly: true);
      // Keep the already-painted soft preview as the base and sharpen the
      // visible slice directly. Rasterizing a full-page vector preview first
      // can itself take seconds on a wide CAD sheet, while this region replay
      // is small and lands almost immediately.
      PdfPerfLog.log('vector-first region page=$pageIndex');
      final paintReady = Completer<bool>();
      final detailFuture = _updateDetail(
        detailGeometry: progressiveDetail,
        onPaint: () {
          if (!paintReady.isCompleted) paintReady.complete(true);
        },
      );
      unawaited(
        detailFuture.then(
          (ready) {
            if (!paintReady.isCompleted) paintReady.complete(ready);
          },
          // A detail render that throws (worker error, region raster failure,
          // web OOM) must still complete this completer. deferFullRenderUntil-
          // DetailPaint has _renderNow await paintReady before it interprets
          // the full image record; a swallowed error here would leave that
          // await hanging forever, so the page's blurry base raster never
          // sharpens until an unrelated relayout (opening devtools, a window
          // resize) fires a fresh _render. Treat a failed detail as "not
          // ready" and let the full pass proceed.
          onError: (Object _, StackTrace __) {
            if (!paintReady.isCompleted) paintReady.complete(false);
          },
        ),
      );
      return paintReady;
    }

    final picture = await PdfPageRenderer.pictureFromCommandsWithPlan(
      widget.page,
      commands,
      _renderPlan,
      includeImages: false,
    );
    if (_superseded(generation, pageIndex) || _renderPaused) {
      picture.dispose();
      return null;
    }
    final vectorRatio = _vectorFirstRatio();
    final image = await PdfPageRenderer.rasterize(
      picture,
      PdfPageRenderer.pageSize(widget.page, rotation: widget.rotation),
      vectorRatio,
    );
    PdfPerfLog.raster(
      'vector-first-full',
      page: pageIndex,
      imageWidth: image.width,
      imageHeight: image.height,
      ratio: vectorRatio,
    );
    picture.dispose();
    // Adopt the vector raster only if the full pass hasn't already landed (a
    // landed full raster has a non-null _rasteredRatio). Deliberately leave
    // _rasteredRatio null so the full pass below is not skipped by its
    // resolution-unchanged guard - it must re-raster to bring the images in.
    if (_superseded(generation, pageIndex) || _rasteredRatio != null) {
      image.dispose();
      return null;
    }
    setState(() {
      _image?.dispose();
      _image = image;
      _preview?.dispose();
      _preview = null;
    });
    PdfPerfLog.log('vector-first page=$pageIndex${PdfPerfLog.rssSuffix()}');
    // This path rasterized a full-page vector preview instead of arming a
    // region detail, so there is nothing for the caller to wait on.
    return null;
  }

  /// Reports, when the perf log is on, how many images a worker buffer carries
  /// and their total decoded megapixels - the deciding number for why a
  /// raster-heavy page is still slow: one oversized image escaping the
  /// resolution cap looks very different from many tiles each capped but
  /// summing large. The walk lives in [PdfPageRenderer.decodedImageStats] (and
  /// is tested there); this only formats the line, and is skipped entirely when
  /// the log is off.
  int _logImageStats(int pageIndex, List<PdfRenderCommand> commands) {
    final (count, pixels) = PdfPageRenderer.decodedImageStats(commands);
    if (count > 0 && PdfPerfLog.enabled) {
      PdfPerfLog.log(
        'images page=$pageIndex count=$count '
        'decodedMpx=${(pixels / 1e6).toStringAsFixed(1)}',
      );
    }
    return pixels * 4;
  }

  /// Whether the page this render was for is gone - the widget unmounted, or
  /// the lazy list recycled this State onto a different page. Picture
  /// production stops here (no wasted local interpret); painting is gated
  /// separately by [_superseded], which also rejects a stale generation.
  bool _abandoned(int pageIndex) =>
      !mounted || !_renderSession.matchesPage(pageIndex);

  /// Whether a render started at ([generation], [pageIndex]) must not paint -
  /// [_abandoned], or a newer render bumped the generation past this one.
  bool _superseded(int generation, int pageIndex) =>
      !mounted || !_renderSession.acceptsFull(generation, pageIndex);

  /// A zero-op picture for an abandoned render. Never painted (the caller's
  /// [_superseded] guards discard it); it only satisfies the return type.
  ui.Picture _emptyPicture() {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder);
    return recorder.endRecording();
  }

  /// Which path [_interpretPicture] actually took, for the perf log - 'worker'
  /// only when a command buffer came back and replayed, else 'recorded'.
  String _lastInterpretPath = 'recorded';
  int? _lastInterpretResultBytes;

  /// The actual interpret + rasterize, run once the first render is no
  /// longer gated (or directly for re-rasters of a cached picture).
  Future<void> _renderNow() async {
    final generation = _renderSession.beginFull();
    final pageIndex = widget.previewIndex;
    final firstInterpret = _picture == null;
    if (firstInterpret) _lastInterpretResultBytes = null;
    final sw = Stopwatch()..start();
    if (_renderPaused) {
      _render();
      return;
    }
    // Progressive first paint: on a page's first interpret, paint its
    // vector/text immediately (images skipped) so a heavy raster underlay -
    // which can take seconds to decode - doesn't leave the page blank
    // meanwhile. The full pass below then re-rasters with the images in.
    final previewFresh =
        widget.previewCache?.isFresh(pageIndex, widget.page) ?? false;
    // A cached preview is enough to avoid another vector-only first paint at
    // fit scale. Once zoomed, however, the lightweight worker recording also
    // bootstraps the visible-region request that can beat a slow full-page
    // image decode. Ask for it even when soft preview pixels already exist.
    final needsRegionBootstrap = widget.scale > 1.05 &&
        _scene == null &&
        (widget.renderWorker?.isActive ?? false);
    if (firstInterpret && (!previewFresh || needsRegionBootstrap)) {
      // The armed detail completer is returned, not parked in a field. Renders
      // are not serialized - PdfPageRenderScheduler invokes render() without
      // awaiting it (render_scheduler.dart, "starts one page render this
      // frame") and only de-duplicates *pending* requests, so two _renderNow
      // passes for one page can interleave. With shared state, whichever pass
      // read the field last either inherited a future belonging to an
      // abandoned paint or stole the live pass's own. A local keeps each pass
      // with exactly the completer it armed.
      final progressiveDetail = await _paintVectorFirst(generation, pageIndex);
      if (_superseded(generation, pageIndex)) return;
      if (PdfPageView.deferFullRenderUntilDetailPaint &&
          progressiveDetail != null) {
        final detailReady = await progressiveDetail.future;
        if (_superseded(generation, pageIndex)) return;
        if (detailReady) {
          PdfPerfLog.log('full refine waits for detail paint page=$pageIndex');
          await SchedulerBinding.instance.endOfFrame;
          if (_superseded(generation, pageIndex)) return;
        }
      }
    }
    final cached = _picture;
    final ui.Picture picture;
    if (cached != null) {
      picture = await cached;
    } else {
      final interpreted = await _interpretPicture();
      if (interpreted == null) {
        if (!_superseded(generation, pageIndex)) _render();
        return;
      }
      final (interpretedPicture, interpretedScene, sceneFromWorker) =
          interpreted;
      if (_superseded(generation, pageIndex)) {
        interpretedPicture.dispose();
        interpretedScene?.dispose();
        return;
      }
      _picture = Future.value(interpretedPicture);
      if (interpretedScene != null) {
        _setScene(interpretedScene, fromWorker: sceneFromWorker);
      }
      picture = interpretedPicture;
    }
    sw.stop();
    // Bail before logging when superseded - an abandoned interpret (page
    // recycled, disposed, or cancelled prefetch) never paints, so logging it
    // as a 'recorded' interpret would be a phantom UI-thread cost.
    if (_superseded(generation, pageIndex)) return;
    if (firstInterpret) {
      PdfPerfLog.interpret(
        pageIndex,
        path: _lastInterpretPath,
        interpretMs: sw.elapsedMicroseconds / 1000.0,
        first: true,
      );
      widget.performance?.observe(
        PdfPerformanceSample(
          workerRecordDuration: sw.elapsed,
          resultBytes: _lastInterpretResultBytes,
        ),
      );
    }
    final effective = _effectiveRatio();
    final retainedScene = PdfPageView.retainedZoomReplay ? _scene : null;

    // On web, keep one Slug-routed picture live under the viewer transform.
    // Record at 1 px/pt: Skia reevaluates the curve shader under later CTMs,
    // which is the property this path exists to preserve. This replaces the
    // base raster rather than overlaying it, so text is never double-painted
    // and painter order remains the command stream's exact order.
    if (_slugPictureScene(retainedScene) && !_slugPictureRejected) {
      if (_slugPicture == null) {
        StripPlan? slugPlan;
        final dense = retainedScene!.commands.length >
            PdfPageView.retainedZoomReplayMaxCommands;
        if (dense) {
          slugPlan = await _workerSlugPlan(retainedScene);
          // Layout/zoom can advance the raster generation while this one-off
          // transform picture is building. It is scale-independent, so only
          // a recycled page or replaced scene makes it stale.
          if (_abandoned(pageIndex) || !identical(_scene, retainedScene)) {
            if (mounted && !_abandoned(pageIndex)) _render();
            return;
          }
          // Never rebuild a dense Slug plan locally: that is the UI-thread
          // curve/bin walk this worker path exists to avoid.
          if (slugPlan == null) {
            _slugPictureRejected = true;
          }
        }
        if (!_slugPictureRejected) {
          var slugStats = (quads: 0, fallbackOutlineRuns: 0);
          final slugPicture = await retainedScene.replayStrips(
            pixelRatio: 1,
            stripPlan: slugPlan,
            slugGlyphs: true,
            onSlugStats: (stats) => slugStats = stats,
          );
          if (_abandoned(pageIndex) || !identical(_scene, retainedScene)) {
            slugPicture.dispose();
            if (mounted && !_abandoned(pageIndex)) _render();
            return;
          }
          // Minified or atlas-overflow outline runs fall back to pixel-aligned
          // strips. Keeping that picture under a transform would blur those
          // runs, so use the normal raster path unless every outline run took
          // Slug and at least one glyph was emitted.
          if (slugStats.quads == 0 || slugStats.fallbackOutlineRuns != 0) {
            slugPicture.dispose();
            _slugPictureRejected = true;
          } else {
            setState(() {
              _slugPicture = slugPicture;
              _image?.dispose();
              _image = null;
              _preview?.dispose();
              _preview = null;
              _rasteredRatio = effective;
            });
            _dropDetail();
            final cache = widget.previewCache;
            if (cache != null &&
                !cache.isFresh(
                  widget.previewIndex,
                  widget.page,
                  requireImages: true,
                )) {
              unawaited(
                cache.putFromPicture(
                  widget.previewIndex,
                  widget.page,
                  picture,
                  rotation: widget.rotation,
                ),
              );
            }
            await _updateDetail();
            if (_abandoned(pageIndex) || !identical(_scene, retainedScene)) {
              return;
            }
            widget.onRasterReady?.call();
            return;
          }
        }
      } else {
        // No replay and no GPU readback on a zoom settle; the existing
        // picture will be painted under the new InteractiveViewer transform.
        _rasteredRatio = effective;
      }
      if (_slugPicture != null) {
        await _updateDetail();
        return;
      }
    }
    if (_slugPicture != null) {
      setState(() {
        _slugPicture?.dispose();
        _slugPicture = null;
        _rasteredRatio = null;
      });
    }
    // Skip the full-page readback when the cached raster is already at
    // this resolution: a settle that only moved the detail patch reaches
    // here too (one combined callback paces base + detail through the
    // scheduler), and re-reading the whole page off the GPU is the
    // expensive part on web.
    final stale = _image == null ||
        _rasteredRatio == null ||
        (effective - _rasteredRatio!).abs() > _rasteredRatio! * 0.01;
    if (stale) {
      if (_renderPaused) {
        _render();
        return;
      }
      // Replay the retained scene into a flat picture at the new ratio when
      // one is held - Impeller rasterizes that several times faster than the
      // nested drawPicture re-raster, with byte-identical output. Dense
      // pages retained under PdfPageView.stripZoomReplay re-bin through the
      // strip shader device instead - with the re-bin itself offloaded to
      // the render worker when the scene is worker-backed (the plan comes
      // back precomputed; null plan = local bin). Fallback paths (no scene,
      // or the kill switch) re-raster the cached picture.
      final scene = retainedScene;
      final ui.Image image;
      if (scene != null && _stripReplayScene(scene)) {
        final stripPlan = await _workerStripPlan(scene, pixelRatio: effective);
        if (_superseded(generation, pageIndex)) return;
        image = await scene.rasterizeStrips(
          pixelRatio: effective,
          stripPlan: stripPlan,
        );
      } else if (scene != null && !_sceneIsTileOnly(scene)) {
        image = await scene.rasterize(pixelRatio: effective);
      } else {
        // No scene, or one retained only to feed tiles: a flat replay of a
        // dense transcript would be a UI-thread hitch, so the cached picture
        // stays the full-page base raster.
        image = await PdfPageRenderer.rasterize(
          picture,
          _renderPlan.pageSize(widget.page),
          effective,
        );
      }
      PdfPerfLog.raster(
        'base-full',
        page: pageIndex,
        imageWidth: image.width,
        imageHeight: image.height,
        ratio: effective,
      );
      if (_superseded(generation, pageIndex)) {
        image.dispose();
        return;
      }
      final cache = widget.previewCache;
      // the previous raster stays up (transform-scaled) until this
      // replaces it, so zooming never flashes white
      setState(() {
        _image?.dispose();
        _image = image;
        _rasteredRatio = effective;
        _preview?.dispose();
        _preview = null;
      });
      cache?.putFullImage(
        widget.previewIndex,
        widget.page,
        image,
        pageColor: widget.pageColor,
        annotations: widget.showAnnotations,
        rotation: widget.rotation,
      );
      // feed the preview cache from the picture we already paid to
      // interpret - this is how previews appear for pages the background
      // prerender hasn't reached (and refresh after edits)
      if (cache != null &&
          !cache.isFresh(
            widget.previewIndex,
            widget.page,
            requireImages: true,
          )) {
        unawaited(
          cache.putFromPicture(
            widget.previewIndex,
            widget.page,
            picture,
            rotation: widget.rotation,
          ),
        );
      }
    }
    final detailReady = await _updateDetail();
    if (stale && detailReady) widget.onRasterReady?.call();
  }

  /// Renders (or drops) the deep-zoom patch: the visible slice of the
  /// page, inflated by half a viewport on each side, at the resolution
  /// the zoom actually asks for.
  Future<bool> _updateDetail({
    _DetailGeometry? detailGeometry,
    VoidCallback? onPaint,
  }) async {
    final generation = _renderSession.beginDetail();
    if (_renderPaused) return false;

    // The tile pyramid supplies deep-zoom detail instead of the single patch:
    // refresh the visible slice and let the tile layer schedule/composite. When
    // the view is too dense to tile within the pyramid budget,
    // _refreshTileGeometry returns false and we fall through to the single-patch
    // path below, which covers an arbitrarily large region in one raster
    // without thrashing the shared pyramid (issues #314/#360).
    if (_useTilePath && _refreshTileGeometry()) {
      return true;
    }

    // A Slug page picture is already transform-sharp for text and vector
    // content. Image-free pages therefore gain nothing from a deep-zoom
    // raster patch: it only re-records the whole page in the worker, performs
    // a GPU readback, and then scales stale pixels over the sharp picture
    // during the next pan. Mixed pages still need the patch for sharper PDF
    // images, so retain the normal path whenever the scene draws an image.
    if (_slugPicture != null && !_sceneHasImageDraws) {
      _dropDetail();
      return true;
    }
    detailGeometry ??= _detailGeometryAt(widget.scale);
    if (detailGeometry == null) {
      _dropDetail();
      return true;
    }
    final fraction = detailGeometry.fraction;
    final region = detailGeometry.region;
    final ratio = detailGeometry.pixelRatio;

    // Dense strip-routed pages ask for one combined worker result: commands
    // whose images were decoded for this region plus the StripPlan binned
    // from those exact commands. That keeps the flat strip replay, restores
    // region-resolution images, and pays one worker queue/transfer round trip
    // instead of serial record + bin requests. Unsupported backends fall
    // through to the retained base scene below.
    final heldScene = PdfPageView.retainedZoomReplay ? _scene : null;
    final stripDetail = heldScene != null && _stripReplayScene(heldScene);
    final progressivePriority =
        _sceneIsVectorOnly ? widget.renderPriority - 1 : widget.renderPriority;
    final detailClock = Stopwatch()..start();
    PdfPerfLog.log(
      'detail request page=${widget.previewIndex} '
      'strip=$stripDetail vectorOnly=$_sceneIsVectorOnly '
      // scene/tiles: why this page does or does not get reusable tiles instead
      // of a fresh full-viewport raster on every pan step.
      'scene=${heldScene != null} tiles=$_useTilePath',
    );
    final workerStripFuture = stripDetail
        ? _detailStripImageFromWorker(
            heldScene,
            region,
            ratio,
            widget.previewIndex,
            generation,
            priority: progressivePriority,
          )
        : Future<ui.Image?>.value();
    // Non-strip pages keep the ordinary region-record path. Dense strip pages
    // use recordStripDetail on every worker backend so commands and the plan
    // come from one geometry-consistent, cancellable job.
    final workerPictureFuture = !stripDetail
        ? _detailPictureFromWorker(
            region,
            ratio,
            widget.previewIndex,
            priority: progressivePriority,
          )
        : Future<ui.Picture?>.value();

    // The progressive scene already has every vector/text command. Replay
    // that visible slice immediately while the worker fills in its image
    // pixels: CAD linework becomes sharp after the lightweight recording,
    // rather than after a second multi-megabyte command transfer. A later
    // complete worker patch replaces this one at the same geometry.
    var progressiveReady = false;
    if (_sceneIsVectorOnly &&
        heldScene != null &&
        !_imagesIntersectRegion(heldScene.commands, region)) {
      final vectorImage = await heldScene.rasterizeRegion(
        region,
        pixelRatio: ratio,
      );
      PdfPerfLog.raster(
        'detail-vector',
        page: widget.previewIndex,
        imageWidth: vectorImage.width,
        imageHeight: vectorImage.height,
        ratio: ratio,
        region: (width: region.width, height: region.height),
      );
      if (mounted &&
          _renderSession.acceptsDetail(generation) &&
          !_renderPaused) {
        setState(() {
          _detailImage?.dispose();
          _detailImage = vectorImage;
          _detailFraction = fraction;
        });
        onPaint?.call();
        progressiveReady = true;
        _logDetailPaintAfterFrame(generation, detailClock, source: 'vector');
        PdfPerfLog.log(
          'detail vector page=${widget.previewIndex} '
          'elapsed=${detailClock.elapsedMilliseconds}ms',
        );
      } else {
        vectorImage.dispose();
      }
    }

    final workerStripImage = await workerStripFuture;
    final workerPicture = await workerPictureFuture;
    PdfPerfLog.log(
      'detail worker page=${widget.previewIndex} '
      'elapsed=${detailClock.elapsedMilliseconds}ms '
      'stripImage=${workerStripImage != null} picture=${workerPicture != null}',
    );
    if (!mounted ||
        !_renderSession.acceptsDetail(generation) ||
        _renderPaused) {
      workerStripImage?.dispose();
      workerPicture?.dispose();
      return false;
    }
    if (workerStripImage != null) {
      setState(() {
        _detailImage?.dispose();
        _detailImage = workerStripImage;
        _detailFraction = fraction;
      });
      onPaint?.call();
      _logDetailPaintAfterFrame(
        generation,
        detailClock,
        source: 'worker-strip',
      );
      return true;
    }
    if (workerPicture != null) {
      final image = await PdfPageRenderer.rasterizeRegion(
        workerPicture,
        region,
        ratio,
      );
      PdfPerfLog.raster(
        'detail-worker-picture',
        page: widget.previewIndex,
        imageWidth: image.width,
        imageHeight: image.height,
        ratio: ratio,
        region: (width: region.width, height: region.height),
      );
      workerPicture.dispose();
      if (!mounted ||
          !_renderSession.acceptsDetail(generation) ||
          _renderPaused) {
        image.dispose();
        return false;
      }
      setState(() {
        _detailImage?.dispose();
        _detailImage = image;
        _detailFraction = fraction;
      });
      onPaint?.call();
      _logDetailPaintAfterFrame(
        generation,
        detailClock,
        source: 'worker-picture',
      );
      return true;
    }

    // A progressive scene contains image placeholders. If its worker region
    // request was cancelled or declined, wait for the ordinary full record
    // instead of painting a vector-only patch as if it were complete.
    if (_sceneIsVectorOnly) return progressiveReady;

    // never interpret the page for the first time inline here - that is
    // the scheduler's job (or, bare, the hold's); the next settle
    // refreshes the patch once the base picture lands
    if (_picture == null) {
      final scheduler = widget.renderScheduler;
      if (scheduler != null) {
        scheduler.request(this, widget.previewIndex, _renderNow);
        return false;
      }
      if (widget.renderHold?.value ?? false) return false;
    }
    final picture = await (_picture ??= PdfPageRenderer.renderPictureWithPlan(
      widget.page,
      _renderPlan,
    ));
    if (!mounted ||
        !_renderSession.acceptsDetail(generation) ||
        _renderPaused) {
      return false;
    }
    // Same replay-over-nested-raster swap as the full-page path: the deep-
    // zoom patch replays only [region] from the retained scene when held
    // (through the strip device for dense pages under stripZoomReplay,
    // worker-binned when the scene is worker-backed - a pan at deep zoom
    // fires these repeatedly, so each fresh region cancels the previous
    // region's still-queued bin inside _workerStripPlan).
    final scene = PdfPageView.retainedZoomReplay ? _scene : null;
    final ui.Image image;
    final String detailKind;
    if (scene != null && _stripReplayScene(scene)) {
      final stripPlan = await _workerStripPlan(
        scene,
        pixelRatio: ratio,
        region: region,
      );
      if (!mounted ||
          !_renderSession.acceptsDetail(generation) ||
          _renderPaused) {
        return false;
      }
      image = await scene.rasterizeRegionStrips(
        region,
        pixelRatio: ratio,
        stripPlan: stripPlan,
      );
      detailKind = 'detail-strip';
    } else if (scene != null) {
      image = await scene.rasterizeRegion(region, pixelRatio: ratio);
      detailKind = 'detail-region';
    } else {
      // Classic cached-picture path: replays the WHOLE page picture clipped to
      // [region] at [ratio]. On a huge (unretained) transcript this is where a
      // deep-zoom raster gets expensive - the raster instrumentation flags it.
      image = await PdfPageRenderer.rasterizeRegion(picture, region, ratio);
      detailKind = 'detail-picture';
    }
    PdfPerfLog.raster(
      detailKind,
      page: widget.previewIndex,
      imageWidth: image.width,
      imageHeight: image.height,
      ratio: ratio,
      region: (width: region.width, height: region.height),
    );
    if (!mounted ||
        !_renderSession.acceptsDetail(generation) ||
        _renderPaused) {
      image.dispose();
      return false;
    }
    setState(() {
      _detailImage?.dispose();
      _detailImage = image;
      _detailFraction = fraction;
    });
    onPaint?.call();
    _logDetailPaintAfterFrame(generation, detailClock, source: 'local');
    return true;
  }

  void _logDetailPaintAfterFrame(
    int generation,
    Stopwatch clock, {
    required String source,
  }) {
    if (!PdfPerfLog.enabled) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_renderSession.acceptsDetail(generation)) return;
      PdfPerfLog.log(
        'detail paint page=${widget.previewIndex} source=$source '
        'elapsed=${clock.elapsedMicroseconds / 1000.0}ms',
      );
    });
  }

  /// Conservative image-overlap test for the transparent-image progressive
  /// scene. Its local replay is only a visually complete CAD/vector patch
  /// when no image draw reaches the visible region; otherwise the soft base
  /// stays up until the image-complete worker region replaces it.
  bool _imagesIntersectRegion(
    List<PdfRenderCommand> commands,
    Rect rasterRegion,
  ) {
    final region = _pdfRegionForRasterRegion(rasterRegion);
    bool overlaps(List<PdfRenderCommand> list) {
      for (final command in list) {
        switch (command) {
          case PdfDrawImageCommand(:final request):
            final m = request.transform;
            final xs = [
              m.transformX(0, 0),
              m.transformX(1, 0),
              m.transformX(1, 1),
              m.transformX(0, 1),
            ];
            final ys = [
              m.transformY(0, 0),
              m.transformY(1, 0),
              m.transformY(1, 1),
              m.transformY(0, 1),
            ];
            final left = xs.reduce(math.min);
            final right = xs.reduce(math.max);
            final bottom = ys.reduce(math.min);
            final top = ys.reduce(math.max);
            if (right > region.left &&
                left < region.right &&
                top > region.bottom &&
                bottom < region.top) {
              return true;
            }
          case PdfEndSoftMaskedCommand(:final maskCommands):
            if (overlaps(maskCommands)) return true;
          default:
            break;
        }
      }
      return false;
    }

    return overlaps(commands);
  }

  /// Computes the exact patch geometry shared by progressive rendering,
  /// live-transform speculation, and the settled render. Null means the page
  /// needs no detail patch (unless [force] is set), is not currently visible,
  /// or has no usable region.
  _DetailGeometry? _detailGeometryAt(
    double scale, {
    bool force = false,
    double inflation = 0.5,
  }) {
    final desired = _desiredRatioAt(scale);
    final effective = _effectiveRatioAt(scale);
    if (!force && desired <= effective * 1.05) return null;
    if (force && scale <= 1.05) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final pageRect = Rect.fromPoints(
      box.localToGlobal(Offset.zero),
      box.localToGlobal(Offset(box.size.width, box.size.height)),
    );
    final screen = Offset.zero & MediaQuery.sizeOf(context);
    final visible = pageRect.intersect(screen);
    if (visible.isEmpty || pageRect.width <= 0 || pageRect.height <= 0) {
      return null;
    }

    // Visible slice as fractions of the page. Settled cap-driven patches use
    // 50% per-side panning headroom. The progressive region-first request is
    // deliberately tighter: its job is to beat the still-warming full page,
    // and a large guard band would re-decode most of that page again.
    final fraction = Rect.fromLTRB(
      ((visible.left - pageRect.left - visible.width * inflation) /
              pageRect.width)
          .clamp(0.0, 1.0),
      ((visible.top - pageRect.top - visible.height * inflation) /
              pageRect.height)
          .clamp(0.0, 1.0),
      ((visible.right - pageRect.left + visible.width * inflation) /
              pageRect.width)
          .clamp(0.0, 1.0),
      ((visible.bottom - pageRect.top + visible.height * inflation) /
              pageRect.height)
          .clamp(0.0, 1.0),
    );
    final size = _renderPlan.pageSize(widget.page);
    final region = Rect.fromLTRB(
      fraction.left * size.width,
      fraction.top * size.height,
      fraction.right * size.width,
      fraction.bottom * size.height,
    );
    if (region.width <= 0 || region.height <= 0) return null;
    // the patch obeys the same pixel budget as the base
    var ratio = desired;
    ratio = math.min(
      ratio,
      math.sqrt(_maxPixels / (region.width * region.height)),
    );
    ratio = math.min(
      ratio,
      _maxDimension / math.max(region.width, region.height),
    );
    return _DetailGeometry(fraction, region, ratio);
  }

  /// Whether the [PdfPageView.tileStoreDetail] tile path drives deep-zoom
  /// detail for this page: the flag is on and the retained scene is
  /// region-cullable (soft-mask/group spans keep the legacy single-patch
  /// path).
  ///
  /// A vector-only progressive scene is eligible too - on the dense CAD pages
  /// the pyramid targets, the full image-bearing record may never land during
  /// a deep-zoom dwell, so excluding vector-only scenes meant 0 tiles exactly
  /// where tiles matter most. Its absent image pixels are handled per tile:
  /// [_tileCanRasterize] vetoes the regions an image draw intersects, which
  /// keep the fallback/base raster and heal automatically if the full record
  /// later replaces the scene.
  bool get _useTilePath {
    if (!PdfPageView.tileStoreDetail) return false;
    final scene = PdfPageView.retainedZoomReplay ? _scene : null;
    if (scene == null) return false;
    // A dense (grid-escalated) page's region index is a ~O(commands) build
    // (~210ms on the CAD probe, issue #384). Never pay it synchronously on the
    // UI isolate: defer the tile path until the warmed index is resident (built
    // on the render worker when eligible - see [_warmRegionIndexIfNeeded]).
    // Until then the base raster / single detail patch covers the view. Pages
    // below the grid ceiling keep the cheap synchronous linear build.
    if (scene.regionIndexBuildIsHeavy && !scene.debugHasRegionReplayIndex) {
      return false;
    }
    return scene.supportsRegionRaster;
  }

  /// Kicks the region-replay index build onto the render worker when the page
  /// is dense enough that the build would otherwise stall the UI isolate (issue
  /// #384). Idempotent and cheap when the index is already resident, the build
  /// is light, or a warm is already in flight; re-runs [_refreshTileGeometry]
  /// once the index lands so the tile path can engage. Only a worker-recorded
  /// scene may take a worker-built index (its transcript must match the
  /// worker's re-record); other scenes warm in-isolate.
  void _warmRegionIndexIfNeeded() {
    final scene = PdfPageView.retainedZoomReplay ? _scene : null;
    if (scene == null ||
        scene.debugHasRegionReplayIndex ||
        !scene.regionIndexBuildIsHeavy) {
      return;
    }
    final worker = _sceneFromWorker ? widget.renderWorker : null;
    final warming = scene;
    scene
        .warmRegionIndex(worker, pageIndex: widget.previewIndex)
        .then((_) {
      // Only refresh if this is still the adopted scene and we're mounted; a
      // document swap or scroll-away may have replaced it while the worker ran.
      if (mounted && identical(_scene, warming)) _refreshTileGeometry();
    });
  }

  /// Per-tile veto for the tile store while the scene is vector-only: a tile
  /// region an image draw intersects would bake the placeholder's missing
  /// pixels into a cached tile. Bound to the scene at adoption ([_setScene])
  /// so the painter's identity check doesn't see a fresh closure every build.
  bool Function(Rect region)? _tileCanRasterize;

  /// Pan-ahead guard band for the tile path's visible slice, as a fraction of
  /// the viewport per side. Zero: the pyramid's prefetch ring already
  /// pre-rasters the border, so - unlike the single patch - the tile slice
  /// needs no inflation, and inheriting the patch's 50% band only quadrupled
  /// the working set past the tile budget (issues #314/#360).
  static const _tileInflation = 0.0;

  /// Recomputes the tile layer's visible slice + desired ratio on a settle and
  /// reports whether the tile path is handling this view. Runs post-render
  /// (never during layout), so reading the render tree in [_detailGeometryAt]
  /// is safe; `build` reads the stored fields.
  ///
  /// Returns false when the caller should fall back to the single detail patch:
  /// either the base raster is already sharp ([_detailGeometryAt] null - tiles
  /// add nothing) or the view is too dense to tile within the pyramid budget
  /// ([PdfTileStore.viewFitsBudget]), where tiling would thrash the shared LRU.
  bool _refreshTileGeometry() {
    if (!mounted) return false;
    // Ahead of the tile path engaging, warm a dense page's region index on the
    // worker so its build never lands on the UI isolate (issue #384).
    _warmRegionIndexIfNeeded();
    Rect? fraction;
    double? desired;
    var tiling = false;
    if (_useTilePath) {
      final geom = _detailGeometryAt(widget.scale, inflation: _tileInflation);
      if (geom != null && _tilesFitBudget(geom.fraction)) {
        fraction = geom.fraction;
        desired = _desiredRatioAt(widget.scale);
        tiling = true;
      }
    }
    if (fraction != _tileFraction || desired != _tileDesiredRatio) {
      setState(() {
        _tileFraction = fraction;
        _tileDesiredRatio = desired;
      });
    }
    return tiling;
  }

  /// Whether the shared tile store can hold [fraction]'s tiles at the current
  /// zoom without evicting them out from under the view that just asked for
  /// them - see [PdfTileStore.viewFitsBudget].
  bool _tilesFitBudget(Rect fraction) {
    final store = PdfPageView.debugTileStoreOverride ?? PdfTileStore.instance;
    final size = _renderPlan.pageSize(widget.page);
    if (size.width <= 0 || size.height <= 0) return false;
    return store.viewFitsBudget(
      pageSize: size,
      desiredRatio: _desiredRatioAt(widget.scale),
      visiblePageRect: Rect.fromLTRB(
        fraction.left * size.width,
        fraction.top * size.height,
        fraction.right * size.width,
        fraction.bottom * size.height,
      ),
    );
  }

  /// The [PdfTileStore] deep-zoom composite for this page, or null when the
  /// tile path is inactive or the page is not zoomed past the base raster.
  ///
  /// [size] is the page-point size (the tile grid space). Placed above the base
  /// raster so uncovered gaps show it through; it replaces the single detail
  /// patch when active.
  Widget? _tileLayerWidget(Size size) {
    if (!_useTilePath) return null;
    final scene = _scene;
    final fraction = _tileFraction;
    final desired = _tileDesiredRatio;
    if (scene == null || fraction == null || desired == null) return null;
    final store = PdfPageView.debugTileStoreOverride ?? PdfTileStore.instance;
    return Positioned.fill(
      child: PdfTileLayer(
        store: store,
        identity: PdfTilePageIdentity(
          pageIndex: widget.previewIndex,
          pageEpoch: widget.pageEpoch,
          contentStamp: widget.contentStamp,
          destructiveStamp: widget.destructiveStamp,
          plan: _renderPlan,
        ),
        pageSize: size,
        desiredRatio: desired,
        visibleFraction: fraction,
        rasterize: (region, ratio) =>
            scene.rasterizeRegion(region, pixelRatio: ratio),
        canRasterize: _tileCanRasterize,
      ),
    );
  }

  /// Whether worker strip binning may be asked for at all - shared by
  /// [_workerStripPlan] and [_speculateStripPlan] so the two paths' guards
  /// can't drift: a worker-recorded scene, a live worker, and no
  /// debug-delegate flag forcing local routing (the worker isolate has its
  /// own statics and would bin the full routing, desyncing flush ordinals).
  bool get _workerBinningEligible {
    if (!_sceneFromWorker) return false;
    final worker = widget.renderWorker;
    if (worker == null || !worker.isActive) return false;
    if (StripPdfDevice.debugDelegateAll ||
        StripPdfDevice.debugDelegateFills ||
        StripPdfDevice.debugDelegateStrokes ||
        StripPdfDevice.debugDelegateText) {
      return false;
    }
    return true;
  }

  /// Fired by [_speculateTimer] once the live transform has been quiet for
  /// [_speculateDebounce]. A normal zoom pre-requests the full-page strip
  /// plan; a pixel-capped deep zoom pre-requests the combined region commands
  /// + plan for the live translated viewport. The matching settle consumes
  /// the stored future after most of the worker latency has overlapped the
  /// viewer's own debounce.
  void _speculateStripPlan() {
    final transformScale = widget.transformScale;
    if (!mounted || transformScale == null) return;
    if (!PdfPageView.retainedZoomReplay) return;
    final scene = _scene;
    if (scene == null || !_stripReplayScene(scene)) return;
    if (!_workerBinningEligible) return;
    // Anticipate the scale the settle will pass: this mirrors the viewer's
    // _renderScale quantization in _PdfViewerState._onTransformChanged
    // (pdf_viewer.dart) EXACTLY and the two must stay in sync - a drift
    // makes every speculation a geometry miss, silently re-paying the full
    // bin wait the feature exists to avoid.
    final live = math.max(1.0, transformScale.value);
    final anticipated =
        (live - widget.scale).abs() > 0.1 * widget.scale ? live : widget.scale;

    // Past the full-page pixel cap the settle does not re-raster the base; it
    // moves a sharper region patch instead. Compute that patch from the live
    // post-transform page bounds so translation-only pans can speculate too.
    final detail = _detailGeometryAt(anticipated);
    if (detail != null) {
      _speculateStripDetail(scene, detail);
      return;
    }

    final eff = _effectiveRatioAt(anticipated);
    // Mirror _renderNow's staleness gate: when the settle won't re-raster
    // the full page (resolution unchanged within 1%), don't bin for it.
    if (_image != null &&
        _rasteredRatio != null &&
        (eff - _rasteredRatio!).abs() <= _rasteredRatio! * 0.01) {
      return;
    }
    final geometry = scene.stripGeometry(pixelRatio: eff);
    final pending = _speculativeStripPlan;
    if (pending != null && pending.matches(geometry, eff)) return; // no churn
    final worker = widget.renderWorker!;
    // supersede any previous speculative bin (queued or in-flight)
    worker.cancelBinStrips(
      widget.previewIndex,
      priority: widget.renderPriority,
    );
    _speculativeStripDetail = null;
    final m = geometry.pageToDevice;
    _speculativeStripPlan = _SpeculativeStripPlan(
      geometry,
      eff,
      worker.binStrips(
        widget.previewIndex,
        annotations: scene.plan.annotations,
        pageToDevice: [m.a, m.b, m.c, m.d, m.e, m.f],
        deviceWidth: geometry.width,
        deviceHeight: geometry.height,
        pixelRatio: eff,
        // the SAME priority as the settle's own bin, so speculation is
        // never preempted by (nor preempts) equal-priority work
        priority: widget.renderPriority,
      ),
    );
  }

  void _speculateStripDetail(PdfRetainedScene scene, _DetailGeometry detail) {
    final geometry = scene.stripRegionGeometry(
      detail.region,
      pixelRatio: detail.pixelRatio,
    );
    final decodeRegion = _pdfRegionForRasterRegion(detail.region);
    final pending = _speculativeStripDetail;
    if (pending != null &&
        pending.matches(geometry, detail.pixelRatio, decodeRegion)) {
      return; // the live transform settled on the same region; no churn
    }
    final worker = widget.renderWorker!;
    worker.cancelBinStrips(
      widget.previewIndex,
      priority: widget.renderPriority,
    );
    _speculativeStripPlan = null;
    final m = geometry.pageToDevice;
    _speculativeStripDetail = _SpeculativeStripDetail(
      geometry,
      detail.pixelRatio,
      decodeRegion,
      worker.recordStripDetail(
        widget.previewIndex,
        annotations: scene.plan.annotations,
        pageToDevice: [m.a, m.b, m.c, m.d, m.e, m.f],
        deviceWidth: geometry.width,
        deviceHeight: geometry.height,
        pixelRatio: detail.pixelRatio,
        imageDecodeRegion: decodeRegion,
        priority: widget.renderPriority,
      ),
    );
  }

  /// Asks the render worker to bin this page's strips for the exact device
  /// geometry the strip replay is about to construct ([stripGeometry] /
  /// [stripRegionGeometry] of [scene]), or null to bin locally: no worker /
  /// worker declined, a locally-recorded scene (see [_setScene]'s
  /// fromWorker), or a debug-delegate flag forcing local routing (see
  /// [_workerBinningEligible]).
  ///
  /// A full-page call first checks [_speculativeStripPlan]: when the
  /// transform-quiescence speculation already requested this EXACT geometry
  /// (all six matrix coefficients, width, height, pixelRatio), the stored
  /// future is consumed instead of starting a fresh bin - the worker has
  /// been binning through the viewer's settle debounce, so only the
  /// residual wait is paid.
  ///
  /// Otherwise any still-queued or in-flight bin for this page is cancelled
  /// first, so a newer settle/region supersedes an older one in the worker
  /// queue; the cancelled caller's null resolves under a stale generation
  /// and is discarded by its guard without falling back to a local bin.
  Future<StripPlan?> _workerStripPlan(
    PdfRetainedScene scene, {
    required double pixelRatio,
    Rect? region,
  }) async {
    if (!_workerBinningEligible) return null;
    final worker = widget.renderWorker!;
    final geometry = region == null
        ? scene.stripGeometry(pixelRatio: pixelRatio)
        : scene.stripRegionGeometry(region, pixelRatio: pixelRatio);
    final speculative = _speculativeStripPlan;
    if (speculative != null) {
      _speculativeStripPlan = null;
      if (region == null && speculative.matches(geometry, pixelRatio)) {
        final plan = await speculative.plan;
        if (plan != null) {
          PdfPageView.debugSpeculativePlanHits++;
          return plan;
        }
        // The speculative bin was cancelled/declined (a preemption, a
        // worker death). Fall through to a fresh request - exactly today's
        // semantics for a settle that finds no plan in flight.
        PdfPageView.debugSpeculativePlanMisses++;
      } else {
        // Wrong geometry (or a region bin): the cancelBinStrips below
        // reaps the stale speculative job; its stored future resolves null
        // unobserved.
        PdfPageView.debugSpeculativePlanMisses++;
      }
    }
    final m = geometry.pageToDevice;
    worker.cancelBinStrips(
      widget.previewIndex,
      priority: widget.renderPriority,
    );
    return worker.binStrips(
      widget.previewIndex,
      annotations: scene.plan.annotations,
      pageToDevice: [m.a, m.b, m.c, m.d, m.e, m.f],
      deviceWidth: geometry.width,
      deviceHeight: geometry.height,
      pixelRatio: pixelRatio,
      priority: widget.renderPriority,
    );
  }

  /// Builds the one transform-time Slug picture for an over-ceiling page.
  /// Unlike settle plans this is always ratio 1 and explicitly asks the
  /// worker for Slug routing; a null result is not rebuilt locally.
  Future<StripPlan?> _workerSlugPlan(PdfRetainedScene scene) async {
    if (!_workerBinningEligible) return null;
    final worker = widget.renderWorker!;
    final geometry = scene.stripGeometry(pixelRatio: 1);
    final m = geometry.pageToDevice;
    worker.cancelBinStrips(
      widget.previewIndex,
      priority: widget.renderPriority,
    );
    return worker.binStrips(
      widget.previewIndex,
      annotations: scene.plan.annotations,
      pageToDevice: [m.a, m.b, m.c, m.d, m.e, m.f],
      deviceWidth: geometry.width,
      deviceHeight: geometry.height,
      pixelRatio: 1,
      slugGlyphs: true,
      priority: widget.renderPriority,
    );
  }

  Future<ui.Picture?> _detailPictureFromWorker(
    Rect rasterRegion,
    double ratio,
    int pageIndex, {
    int? priority,
  }) async {
    final worker = widget.renderWorker;
    if (worker == null || !worker.isActive) return null;
    final decodeRegion = _pdfRegionForRasterRegion(rasterRegion);
    final commands = await worker.record(
      pageIndex,
      annotations: widget.showAnnotations,
      priority: priority ?? widget.renderPriority,
      imagePixelRatio: ratio,
      imageDecodeRegion: decodeRegion,
    );
    if (_abandoned(pageIndex) || commands == null) return null;
    if (_renderPaused) return null;
    _logImageStats(pageIndex, commands);
    return PdfPageRenderer.pictureFromCommandsWithPlan(
      widget.page,
      commands,
      _renderPlan,
    );
  }

  Future<ui.Image?> _detailStripImageFromWorker(
    PdfRetainedScene baseScene,
    Rect rasterRegion,
    double ratio,
    int pageIndex,
    int generation, {
    int? priority,
  }) async {
    if (!_workerBinningEligible) return null;
    final worker = widget.renderWorker!;
    final requestPriority = priority ?? widget.renderPriority;
    final geometry = baseScene.stripRegionGeometry(
      rasterRegion,
      pixelRatio: ratio,
    );
    final decodeRegion = _pdfRegionForRasterRegion(rasterRegion);
    PdfStripDetail? detail;
    final speculative = _speculativeStripDetail;
    if (speculative != null) {
      _speculativeStripDetail = null;
      if (speculative.matches(geometry, ratio, decodeRegion)) {
        detail = await speculative.detail;
        if (detail != null) {
          PdfPageView.debugSpeculativeDetailHits++;
        } else {
          PdfPageView.debugSpeculativeDetailMisses++;
        }
      } else {
        PdfPageView.debugSpeculativeDetailMisses++;
      }
    }
    if (detail == null) {
      final m = geometry.pageToDevice;
      worker.cancelBinStrips(pageIndex, priority: requestPriority);
      detail = await worker.recordStripDetail(
        pageIndex,
        annotations: baseScene.plan.annotations,
        pageToDevice: [m.a, m.b, m.c, m.d, m.e, m.f],
        deviceWidth: geometry.width,
        deviceHeight: geometry.height,
        pixelRatio: ratio,
        imageDecodeRegion: decodeRegion,
        priority: requestPriority,
      );
    }
    if (_abandoned(pageIndex) ||
        !_renderSession.acceptsDetail(generation) ||
        _renderPaused ||
        detail == null) {
      return null;
    }
    _logImageStats(pageIndex, detail.commands);
    final scene = await PdfRetainedScene.fromCommands(
      widget.page,
      detail.commands,
      plan: _renderPlan,
    );
    if (_abandoned(pageIndex) ||
        !_renderSession.acceptsDetail(generation) ||
        _renderPaused) {
      scene.dispose();
      return null;
    }
    try {
      return await scene.rasterizeRegionStrips(
        rasterRegion,
        pixelRatio: ratio,
        stripPlan: detail.plan,
      );
    } finally {
      scene.dispose();
    }
  }

  PdfRect _pdfRegionForRasterRegion(Rect region) {
    final box = widget.page.cropBox;
    final rotation =
        ((widget.rotation ?? widget.page.rotation) % 360 + 360) % 360;
    final points = <(double, double)>[
      _pdfPointForRasterPoint(region.left, region.top, box, rotation),
      _pdfPointForRasterPoint(region.right, region.top, box, rotation),
      _pdfPointForRasterPoint(region.right, region.bottom, box, rotation),
      _pdfPointForRasterPoint(region.left, region.bottom, box, rotation),
    ];
    var left = points.first.$1;
    var right = points.first.$1;
    var bottom = points.first.$2;
    var top = points.first.$2;
    for (final p in points.skip(1)) {
      left = math.min(left, p.$1);
      right = math.max(right, p.$1);
      bottom = math.min(bottom, p.$2);
      top = math.max(top, p.$2);
    }
    return PdfRect(left, bottom, right, top);
  }

  (double, double) _pdfPointForRasterPoint(
    double x,
    double y,
    PdfRect box,
    int rotation,
  ) {
    final w = box.width;
    final h = box.height;
    final (u, v) = switch (rotation) {
      90 => (y, h - x),
      180 => (w - x, h - y),
      270 => (w - y, x),
      _ => (x, y),
    };
    return (box.left + u, box.top - v);
  }

  @override
  Widget build(BuildContext context) {
    final size = PdfPageRenderer.pageSize(
      widget.page,
      rotation: widget.rotation,
    );
    final hasArea = size.width > 0 && size.height > 0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width.isFinite && width > 0) _noteLayoutWidth(width);
        return AspectRatio(
          aspectRatio: hasArea ? size.width / size.height : 1,
          child: LayoutBuilder(
            builder: (context, inner) {
              final w = inner.maxWidth;
              final h = inner.maxHeight;
              final detail = _detailImage;
              final fraction = _detailFraction;
              final slugPicture = _slugPicture;
              final tileLayer = _tileLayerWidget(size);
              // Publish this page's patch bounds for the thumbnail debug
              // overlay (report coalesces its notify past this build).
              if (pdfDebugPaintDetailBounds.value) {
                PdfDebugDetailRegions.instance.report(widget.previewIndex,
                    tileLayer == null && detail != null ? fraction : null);
              }
              return Stack(
                alignment: Alignment.topLeft,
                fit: StackFit.expand,
                children: [
                  if (slugPicture != null)
                    CustomPaint(
                      key: const ValueKey('pdf-page-slug-picture'),
                      painter: _SlugPagePicturePainter(slugPicture, size),
                    )
                  else if (_image == null)
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
                  if (tileLayer != null)
                    tileLayer
                  else if (detail != null && fraction != null && w.isFinite)
                    Positioned(
                      left: fraction.left * w,
                      top: fraction.top * h,
                      width: fraction.width * w,
                      height: fraction.height * h,
                      // The debug border repaints on toggle without a page
                      // rebuild (the flag is a ValueNotifier).
                      child: ValueListenableBuilder<bool>(
                        valueListenable: pdfDebugPaintDetailBounds,
                        child: RawImage(
                          key: const ValueKey('pdf-page-detail-image'),
                          image: detail,
                          fit: BoxFit.fill,
                          filterQuality: FilterQuality.medium,
                        ),
                        builder: (context, debugBounds, child) => !debugBounds
                            ? child!
                            : DecoratedBox(
                                position: DecorationPosition.foreground,
                                decoration: BoxDecoration(
                                  // purple: the legacy single detail patch
                                  border: Border.all(
                                      color: const Color(0xAAAA00FF)),
                                ),
                                child: child,
                              ),
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// Paints a retained page picture into the page widget's fitted dimensions.
/// The picture remains in PDF-point coordinates; the surrounding viewer's
/// transform therefore reaches its Slug runtime shader instead of scaling a
/// previously-rasterized image.
class _SlugPagePicturePainter extends CustomPainter {
  const _SlugPagePicturePainter(this.picture, this.sourceSize);

  final ui.Picture picture;
  final Size sourceSize;

  @override
  void paint(Canvas canvas, Size size) {
    if (sourceSize.width <= 0 || sourceSize.height <= 0) return;
    canvas.save();
    canvas.scale(
      size.width / sourceSize.width,
      size.height / sourceSize.height,
    );
    canvas.drawPicture(picture);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SlugPagePicturePainter oldDelegate) =>
      !identical(picture, oldDelegate.picture) ||
      sourceSize != oldDelegate.sourceSize;
}

/// A worker strip bin requested speculatively while the zoom gesture was
/// quiescing (see `_PdfPageViewState._speculateStripPlan`): the exact device
/// geometry it was binned for, and the in-flight/completed plan future the
/// settle consumes when its geometry matches.
class _SpeculativeStripPlan {
  _SpeculativeStripPlan(this.geometry, this.pixelRatio, this.plan);

  final ({PdfMatrix pageToDevice, int width, int height}) geometry;
  final double pixelRatio;
  final Future<StripPlan?> plan;

  /// Exact match only - all six matrix coefficients, the pixel viewport,
  /// and the ratio compare with `==` (the coefficients round-trip the wire
  /// codec bit-exactly, so a matching settle really is the same geometry).
  bool matches(
    ({PdfMatrix pageToDevice, int width, int height}) other,
    double otherPixelRatio,
  ) =>
      pixelRatio == otherPixelRatio && _sameStripGeometry(geometry, other);
}

class _DetailGeometry {
  const _DetailGeometry(this.fraction, this.region, this.pixelRatio);

  final Rect fraction;
  final Rect region;
  final double pixelRatio;
}

/// A combined region-detail job issued from the translated live viewport.
class _SpeculativeStripDetail {
  const _SpeculativeStripDetail(
    this.geometry,
    this.pixelRatio,
    this.decodeRegion,
    this.detail,
  );

  final ({PdfMatrix pageToDevice, int width, int height}) geometry;
  final double pixelRatio;
  final PdfRect decodeRegion;
  final Future<PdfStripDetail?> detail;

  bool matches(
    ({PdfMatrix pageToDevice, int width, int height}) other,
    double otherPixelRatio,
    PdfRect otherDecodeRegion,
  ) =>
      pixelRatio == otherPixelRatio &&
      _sameStripGeometry(geometry, other) &&
      decodeRegion.left == otherDecodeRegion.left &&
      decodeRegion.bottom == otherDecodeRegion.bottom &&
      decodeRegion.right == otherDecodeRegion.right &&
      decodeRegion.top == otherDecodeRegion.top;
}

bool _sameStripGeometry(
  ({PdfMatrix pageToDevice, int width, int height}) a,
  ({PdfMatrix pageToDevice, int width, int height}) b,
) {
  final am = a.pageToDevice;
  final bm = b.pageToDevice;
  return a.width == b.width &&
      a.height == b.height &&
      am.a == bm.a &&
      am.b == bm.b &&
      am.c == bm.c &&
      am.d == bm.d &&
      am.e == bm.e &&
      am.f == bm.f;
}
