import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:pdf_cos/pdf_cos.dart'
    show ContentStreamParser, CosDictionary, CosName, CosStream;
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart'
    show
        PdfDrawImageCommand,
        PdfEndSoftMaskedCommand,
        PdfMatrix,
        PdfRenderCommand;

import 'canvas_device.dart';
import 'debug_overlays.dart';
import 'live_raster_budget.dart';
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
import 'tile_raster_backend.dart';
import 'tile_store.dart';
import 'web_page_surface.dart';
import 'web_surface_profile.dart';

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
    this.baseRasterScale,
    this.settleGeneration = 0,
    this.pageColor = const Color(0xFFFFFFFF),
    this.showAnnotations = true,
    this.onRasterReady,
    this.renderHold,
    this.renderScheduler,
    this.renderPriority = 0,
    this.focusDistance = 0,
    this.onScreen = true,
    this.qualityVisible = true,
    this.qualityPageCount = 1,
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
    this.tileRasterBackend = const PdfCanvasTileRasterBackend(),
  }) : assert(qualityPageCount >= 1);

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

  /// Caps speculative/off-screen full-page image decode requests. Every page
  /// intersecting the viewport keeps [focusedImageDecodeHeadroom] over its
  /// base raster's physical resolution; deep-zoom region requests likewise
  /// stay uncapped so visible content can sharpen on demand.
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

  /// Scene-scoped renderer for deep-zoom tile slabs.
  ///
  /// The default replays the retained scene through Flutter Canvas. An
  /// experimental backend can instead retain GPU buffers and textures once
  /// per scene. It is created lazily only after the tile path engages, so it
  /// cannot delay the page's initial raster; null sessions and failures fall
  /// back to the Canvas implementation.
  final PdfTileRasterBackend tileRasterBackend;

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

  /// Distance in pages from the focused page (0 = the page the viewport is on).
  /// Off-focus neighbours are prefetched, so their embedded images are decoded
  /// and shipped at a reduced resolution ([prefetchImagePixelRatioFactor]) to
  /// keep record traffic down (a Flate raster underlay ships as full RGBA - a
  /// single page can reach tens of MB, starving the visible page, #451). The
  /// page re-renders at full image resolution the moment a meaningful share
  /// of it becomes visible (see [qualityVisible]).
  ///
  /// Focus is a *ranking*, not a visibility test - see [onScreen], which is
  /// what decides whether this page is treated as a prefetch neighbour at all.
  final int focusDistance;

  /// Whether any part of this page currently overlaps the viewport.
  ///
  /// A page can be half the screen and still sit at [focusDistance] 1, because
  /// focus is the single page under the viewport *centre*. Prefetch economies -
  /// reduced-resolution image decodes, live-raster reclaim - apply to pages the
  /// user cannot see; applying them to a visible page is what made the pages
  /// above and below the centre soften and blank as they crossed the screen
  /// edge on large-format scans (#657).
  ///
  /// Defaults to true: a page mounted on its own is on screen, and a host
  /// embedding [PdfPageView] directly gets full-resolution behaviour without
  /// having to say so.
  final bool onScreen;

  /// Whether enough of this page is visible to require foreground-quality
  /// image decoding and zoom detail. A narrow page-edge sliver may be false
  /// while [onScreen] remains true; when the viewport rests between two pages,
  /// both pages are true. Standalone page views default to foreground quality.
  final bool qualityVisible;

  /// Number of pages simultaneously receiving foreground-quality rendering.
  ///
  /// Tile storage is shared across the viewer. At a page boundary each
  /// foreground page must therefore admit only its share of that cache, or
  /// both pages can pass a page-local budget check and evict one another on
  /// every tile completion. Standalone page views default to one claimant.
  final int qualityPageCount;

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

  /// Optional scale ceiling for the whole-page backing raster.
  ///
  /// The normal viewer sets this to 1: its fit-size raster remains as the soft
  /// backing while [scale] above 1 sharpens only the visible detail region,
  /// matching a tiled renderer instead of re-reading a mostly off-screen full
  /// page at every zoom level. Null preserves the standalone widget's legacy
  /// behaviour, where the base follows [scale] until the global pixel cap.
  final double? baseRasterScale;

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

  /// Experimental web benchmark path: transfers a DOM canvas to the render
  /// worker and paints supported pages there without a `dart:ui` image or
  /// SkWasm presentation frame.
  ///
  /// False by default and a no-op off web. This exists to test whether the
  /// remaining PDFium parity gap is the Flutter surface presentation frame;
  /// it is not a supported rendering mode until the competitive harness proves
  /// a material win and the visual corpora pass through it.
  static bool webDomRasterPresentation = false;

  /// Quiet window after the last wheel/list scroll event before a worker-owned
  /// DOM surface sharpens its focused page. The ordinary 500 ms window protects
  /// the UI isolate from a CAD interpretation starting between delayed wheel
  /// acknowledgements; a surface paints on the dedicated worker and needs only
  /// enough debounce to avoid repainting every input tick. Two 60 Hz frames
  /// let a delayed final wheel acknowledgement join the burst without adding
  /// a visibly separate post-scroll pause; the worker queue still coalesces
  /// obsolete requests.
  static Duration webDomSurfaceScrollSettleDelay =
      const Duration(milliseconds: 32);

  /// Small, resource-simple web pages may take their first recorded picture
  /// locally instead of waiting for a newly-started render worker. Worker boot
  /// is roughly 150 ms in real Chromium while an ordinary text page records in
  /// about 10 ms; the full raster still runs through the engine either way.
  /// Pages with XObjects or larger content stay on the worker path so image
  /// decode and dense interpreter walks never move onto the UI isolate.
  /// Set to zero to disable.
  static int webLocalFirstPaintMaxRawContentBytes = 64 * 1024;

  // One local-first attempt per document worker. The worker wrapper is unique
  // to a document session and Expando does not keep it alive. Claiming the
  // attempt even when the opening page turns out to be too large/resource-rich
  // is important: this is a worker-startup hedge, not a policy for moving every
  // later simple navigation onto the UI isolate.
  static final Expando<bool> _webLocalFirstPaintAttempted = Expando<bool>();

  /// Test hook for the web half of [webLocalFirstPaintMaxRawContentBytes].
  static bool? debugWebLocalFirstPaintBackendOverride;

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
  /// visible viewport - a measured ~235 ms worker round trip plus a large
  /// transient raster per step, with nothing reused. Tiling turns that into a
  /// first fill plus an edge strip of new tiles.
  ///
  /// The default bounds the retained transcript to roughly 100 MB (~260 bytes
  /// per command, measured on a production CAD sheet: 850k commands retained
  /// 221 MB). Sheets past it keep today's behaviour rather than trade an
  /// unbounded retention for the win.
  static int retainedZoomReplayTileMaxCommands = 400000;

  /// Whether dense scenes used only by the tile/strip routes stay retained on
  /// pages that do not own viewport focus.
  ///
  /// Off-focus pages keep their completed raster/picture, while the focused
  /// page retains the scene needed for cross-platform tile and strip replay.
  /// Keeping this false cut the real CAD journey's peak browser RSS without a
  /// navigation or dense-page zoom regression. Hosts that prefer eager nearby
  /// tile readiness over memory can opt back in.
  static bool retainDenseScenesOffFocus = false;

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
  /// tape. The first fit-page raster always flattens the completed picture
  /// directly: re-binning hundreds of thousands of commands cannot improve
  /// that already-recorded base and measured 250-370 ms on the CAD corpus
  /// where its 0.1-0.6 MP picture raster took 7-20 ms. Strips start with a
  /// later zoom/detail settle, where their scale-aware replay is the win.
  /// Without a worker (or when it declines) the re-bin runs locally
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

  /// Presents a bounded completed page picture directly instead of first
  /// flattening it through `Picture.toImage`.
  ///
  /// This is the cross-platform presentation path for ordinary pages. The
  /// retained display list is already the exact painter-order result; drawing
  /// it avoids a full-page GPU readback before the page can be declared ready.
  /// Dense pages stay on their raster/tile routes because replaying a large
  /// display list on every compositor frame can be more expensive than keeping
  /// a texture. Deep zoom still uses the existing detail/tile layers for image
  /// resolution.
  ///
  /// The retained picture and fallback raster routes are pixel-equivalent; the
  /// command ceiling keeps dense CAD pages on their tile/raster path.
  static bool directPicturePresentation = true;

  /// Maximum retained-scene command count eligible for
  /// [directPicturePresentation].
  static int directPicturePresentationMaxCommands = 5000;

  /// Prioritizes a bounded page's complete display list after its image-free
  /// worker transcript has warmed, instead of spending UI/GPU time flattening
  /// that intermediate vector preview.
  ///
  /// Large pages keep progressive vector paint because showing partial ink is
  /// materially better than waiting on a long complete record. On ordinary
  /// mixed pages, however, the vector preview can cost longer to build and
  /// raster than the transcript-cache hit needed to fetch the final commands.
  /// This is platform-neutral and pairs with [directPicturePresentation].
  static bool prioritizeBoundedFinalPicture = true;

  /// Encoded-content ceiling for starting the complete worker record directly
  /// when [prioritizeBoundedFinalPicture] is enabled.
  ///
  /// Below this bound the page is cheap enough that first walking it only to
  /// discover its command count costs more than it protects: the ordinary
  /// path serializes and transfers an image-free command graph, then repeats
  /// that work for the complete graph. Dense pages keep the measured
  /// command-count gate in [_paintVectorFirst], preserving their progressive
  /// first ink.
  static int boundedFinalSinglePassMaxRawContentBytes = 128 * 1024;

  /// Defers a cold deep-zoom page's ordinary full-image refinement until its
  /// visible detail patch has rasterized and reached a frame.
  ///
  /// The detail request already outranks the full request in the worker queue;
  /// this additionally prevents the full decode from starting while the main
  /// thread turns the returned detail commands into the sharp on-screen patch.
  static bool deferFullRenderUntilDetailPaint = true;

  /// Paints a bounded command *prefix* before the full vector record, so a
  /// dense sheet shows real ink instead of blank paper while its whole-page
  /// transcript is still being built.
  ///
  /// The worker maps `commandLimit` to the parse cursor's `operationLimit`, so
  /// a limited record genuinely stops early rather than recording everything
  /// and trimming. See [_paintEarlyPrefix]; set false to disable.
  static bool earlyPrefixPaint = true;

  /// Commands in that first bounded record - large enough for the prefix to be
  /// recognizable, small enough to land in a fraction of a dense page's walk.
  static int earlyPrefixCommandLimit = 20000;

  /// Only pages whose raw (still-encoded) content exceeds this pay the extra
  /// record. [PdfPage.rawContentLength] is an O(streams) size proxy that costs
  /// no decode, so an ordinary few-KB page skips the prefix entirely and is
  /// never charged a second worker job.
  static int earlyPrefixMinContentBytes = 512 * 1024;

  /// Progressively reveals a dense page top-down (#564): the vector-first record
  /// streams the growing linework prefix the worker records, and each prefix is
  /// rasterized into the preview slot, so the page fills in as it records instead
  /// of appearing all at once when the whole-page walk finishes. This replaces
  /// the single bounded [earlyPrefixPaint] on a dense page - a growing sequence
  /// of prefixes rather than one snapshot - and lands *before* the vector-first
  /// full raster, so it is strictly more information sooner.
  ///
  /// Default **on**: both backends stream (isolate and web worker), and the
  /// reveal measured ~25% faster first ink than the bounded prefix it replaces
  /// on a dense sheet in real Chrome (`tool/perf.sh web open-diagram` vs
  /// `open-diagram-progressive`). Gated on the same [earlyPrefixMinContentBytes]
  /// density proxy, so an ordinary page is untouched. Backends that don't stream
  /// (the null worker) make it a no-op - the page renders exactly as before.
  /// Set false to fall back to the single bounded [earlyPrefixPaint] snapshot.
  static bool progressiveStreamingPaint = true;

  /// UI-time ceiling for progressive prefix replay. Once one prefix costs at
  /// least this long, larger cumulative prefixes from the same record are
  /// skipped and the final worker result is allowed to land next.
  ///
  /// This is deliberately a measured time budget rather than a command-count
  /// limit: 8,000 simple lines and 8,000 clipped glyphs have radically
  /// different costs, as do desktop and mobile GPUs. Twelve milliseconds
  /// leaves roughly 4.7 ms of a 60 Hz frame for layout, input and composition.
  /// Set null to keep painting every streamed prefix.
  static Duration? progressivePartialUiBudget =
      const Duration(milliseconds: 12);

  /// Uses one decoding worker record for both a page's progressive
  /// linework reveal and its final image-bearing render.
  ///
  /// The old path first completed a `decodeImages: false` record, then issued
  /// an otherwise-identical decoding record. Native isolates consequently
  /// walked the content stream twice; web workers reused the transcript but
  /// still paid for a second request and serialization. A fused record streams
  /// the same image-free prefixes while it walks, emits the complete vector
  /// snapshot before image decoding, and resolves with the final decoded
  /// commands. The optimization is shared by the isolate and web backends.
  ///
  /// Fit-scale first paints use this path whenever progressive painting is on.
  /// Pages small enough to finish in one worker chunk emit only the complete
  /// vector snapshot, so they do not pay for intermediate-prefix churn.
  /// Deep-zoom first paints keep their separate image-free record because it
  /// bootstraps the visible-region detail request.
  static bool fusedProgressiveRecord = true;

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

  /// Factor applied to a prefetched off-screen page's image-decode resolution,
  /// relative to a visible page's. Off-screen pages aren't being looked at, so
  /// shipping their embedded images at full display resolution wastes record
  /// bandwidth (a Flate raster underlay ships as full RGBA - tens of MB) and
  /// competes with the visible page on the worker (#451). 0.5 halves the image
  /// ratio (~4x smaller image payload); the page re-decodes at full resolution
  /// the moment it becomes visible. Only images are affected - vectors and text
  /// are resolution-independent commands. 1.0 disables the reduction.
  static double prefetchImagePixelRatioFactor = 0.5;

  /// Linear embedded-image resolution retained above a visible page's
  /// physical raster footprint.
  ///
  /// A 1:1 decode is sampled once while the PDF image is painted into the page
  /// picture and again when that picture is rasterized/presented. In real
  /// scanned and illustrated documents that double resampling is visibly
  /// softer than PDFium even though the final page raster itself has enough
  /// pixels. Two-times headroom matches the native/local rendering default,
  /// while source dimensions and the shared 16 MP image ceiling still bound
  /// memory. Speculative neighbours retain their lower adaptive cap.
  static const double focusedImageDecodeHeadroom = 2.0;

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

  /// Single-patch scroll settles satisfied by the raster's retained guard
  /// band instead of issuing another region render.
  @visibleForTesting
  static int debugDetailPatchReuses = 0;

  /// Region-scoped image-detail scenes the tile path adopted, and the ratio
  /// the most recent one decoded its images at (see `_adoptTileDetailScene`).
  @visibleForTesting
  static int debugTileImageDetailAdoptions = 0;
  @visibleForTesting
  static double? debugTileImageDetailRatio;
  @visibleForTesting
  static Rect? debugTileImageDetailRegion;

  static void debugResetSpeculativeStats() {
    debugSpeculativePlanHits = 0;
    debugSpeculativePlanMisses = 0;
    debugSpeculativeDetailHits = 0;
    debugSpeculativeDetailMisses = 0;
  }

  @override
  State<PdfPageView> createState() => _PdfPageViewState();
}

class _PendingWorkerRecord {
  const _PendingWorkerRecord(this.commands, this.imageRatio, this.waitClock);

  final Future<List<PdfRenderCommand>?> commands;
  final double imageRatio;
  final Stopwatch? waitClock;
}

class _PdfPageViewState extends State<PdfPageView>
    implements PdfLiveRasterHolder {
  late final PdfPageRenderSession _renderSession;
  Future<ui.Picture>? _picture;

  /// Web-only retained strip picture whose outline-text draws use the Slug
  /// curve shader. Unlike [_image], this remains vector/shader-backed under
  /// the viewer's live transform and is reused across every zoom settle.
  ui.Picture? _slugPicture;
  bool _slugPictureRejected = false;

  /// The ordinary completed page picture when it is presented without a
  /// `toImage` flatten. This aliases the picture owned by [_picture] (or its
  /// retained-scene handle) and therefore must never be disposed separately.
  ui.Picture? _directPicture;
  PdfPageRenderIntent? _directPictureIntent;

  /// The page retained as a replayable scene (commands + decoded images),
  /// produced by the same interpret that yielded [_picture]. Zoom re-rasters
  /// replay it into a flat picture at the new ratio instead of re-reading
  /// the nested cached picture. Null on fallback paths (then the classic
  /// [_picture] re-raster runs) and when [PdfPageView.retainedZoomReplay]
  /// is off. Complete scenes can outlive this lazy page widget through
  /// [_sceneHandle], while the widget itself holds one lease.
  PdfRetainedScene? _scene;

  /// Tile sessions are keyed by retained-scene identity. Usually this holds
  /// the base scene and, on image-heavy deep zooms, one sharper detail scene.
  /// Keeping the owner here—not in PdfTileStore—makes uploads scene-lifetime
  /// while the store remains backend-agnostic and document-revision safe.
  final Map<PdfRetainedScene, PdfTileRasterSession> _tileRasterSessions =
      Map.identity();

  PdfRetainedSceneHandle? _sceneHandle;
  ui.Image? _image;
  bool _webSurfaceDeclined = false;
  (int, int)? _webSurfaceDimensions;
  double? _pixelRatio;
  double? _layoutWidth;

  /// The effective pixel ratio [_image] was last rasterized at. A settle
  /// that only moved the detail patch (scale unchanged) must not re-read
  /// the whole page back off the GPU - an expensive, uncancellable
  /// `toImage` on web - so [_renderNow] skips the full-page raster when
  /// this still matches.
  double? _rasteredRatio;

  /// What the live [_image] actually depicts, when it is a COMPLETE base
  /// raster: the resolution it was rasterized at, the image-decode resolution
  /// its buffer carried, and the content intent it was taken under.
  ///
  /// Distinct from [_rasteredRatio], and deliberately so. [_rasteredRatio] is
  /// "the next picture must re-raster" bookkeeping, and half a dozen paths null
  /// it while leaving perfectly good pixels on screen ([_dropPicture] alone is
  /// reached from an additive edit, a focus-distance promotion, and every scene
  /// swap). That left the resolution-unchanged guard unable to fire, and the
  /// 2026-07-29 trace shows the cost: `base-full page=0 ratio=1.4 1715x1213`
  /// twice inside 306ms, byte-identical, ~8MB and a full GPU readback apiece -
  /// and the same shape on pages 0 and 1 three more times in the session.
  ///
  /// This records what the pixels ARE rather than what the bookkeeping wants,
  /// so [_baseRasterIsCurrent] can answer the only question that matters: would
  /// re-rendering produce anything different? Set only where a full raster is
  /// adopted - NEVER by the vector-first path, whose image is deliberately
  /// incomplete (no PDF images) and must be replaced by the full pass.
  ({double ratio, double? imageRatio, PdfPageRenderIntent intent})? _imageState;

  ui.Image? _detailImage;
  Rect? _detailFraction; // patch placement as fractions of the page
  double? _detailPixelRatio;
  PdfPageRenderIntent? _detailIntent;

  /// The settle generation whose scale change should sharpen only the visible
  /// slice plus a small guard. A zoom has an existing raster transformed under
  /// it, so its first sharp frame should not pay for a half-viewport of unseen
  /// pixels on every side. A later pan increments [widget.settleGeneration]
  /// without changing [widget.scale] and falls back to the normal, generous
  /// guard that makes successive pan settles reusable.
  int? _tightDetailGeneration;

  /// A scale or layout-width update reached this lazy-list child while another
  /// page owns focus. Keep the previous raster (it remains a valid soft preview
  /// under the transform) and sharpen it only when it becomes focus. Otherwise
  /// a discrete zoom of one page immediately queues the two cache-window
  /// neighbours too, serializing three multi-megapixel GPU readbacks behind the
  /// pixels the user is waiting for.
  bool _deferredOffscreenRasterRefresh = false;
  bool _deferredVisibilityCheckScheduled = false;

  /// Visible slice (fraction of the page) and desired ratio for the
  /// [PdfPageView.tileStoreDetail] tile layer, recomputed on each settle in
  /// [_refreshTileGeometry] - post-render, never during layout - so `build`
  /// reads a stored value instead of probing the render tree. Null when the
  /// tile path is inactive.
  Rect? _tileFraction;
  double? _tileDesiredRatio;

  /// A retained scene whose PDF images were decoded FOR [_tileDetailRegion] at
  /// [_tileDetailRatio], so tiles inside that region rasterize their images at
  /// the zoom's own resolution instead of magnifying the base scene's
  /// display-capped decode.
  ///
  /// The base scene decodes images at [_fullImageRatio], which the full-page
  /// raster caps ([PdfPageRasterGeometry.maxPixels] / [_maxDimension]).
  /// Vectors and text replay
  /// resolution-independently, so tiling them at a deeper ratio is sharp for
  /// free - but an image draw can only ever be as sharp as the pixels it holds.
  /// On a page that IS one big image (a scan), tiling the base scene therefore
  /// produced nothing the base raster didn't already have. The single detail
  /// patch never had this problem: it re-records through the worker with an
  /// `imageDecodeRegion`, which decodes only the visible slice's source pixels
  /// at the requested ratio. This is that same request, kept alive across the
  /// pans the pyramid is built to make cheap.
  PdfRetainedScene? _tileDetailScene;

  /// Raster-space region (page points, y-down) [_tileDetailScene]'s images
  /// cover, and the ratio they were decoded at. A tile outside the region, or
  /// a zoom past the ratio, falls back to the base scene.
  Rect? _tileDetailRegion;
  double? _tileDetailRatio;

  /// Geometry of the in-flight [_tileDetailScene] request, so a settle that
  /// wants the same slice doesn't queue a second one. Cleared on completion.
  (Rect, double)? _tileDetailPending;

  /// The current tile view needs image pixels the base scene doesn't have, and
  /// a request for them is outstanding. While it is set, tiles the detail scene
  /// does not yet cover are VETOED rather than rastered from the base scene.
  ///
  /// Rastering them and re-rastering once the sharp pixels land doubles the
  /// tile work of every zoom settle - measured as +15% buildP95 on the
  /// `zoom-scan` web scenario. Holding the tile back instead leaves the base
  /// raster showing through for one worker round trip (exactly what the view
  /// showed before the pyramid engaged) and rasters each tile once, from pixels
  /// that are already sharp. Cleared when the request lands or fails, so a
  /// worker that declines falls back to base-scene tiles rather than never
  /// tiling at all.
  bool _tileDetailWanted = false;

  /// The retained scene whose heavy region index this page has asked a worker
  /// to build. Keeps repeated zoom settles from attaching duplicate completion
  /// handlers while that one build is in flight.
  PdfRetainedScene? _regionIndexWarmScene;

  /// Clone of this page's cached low-res preview; painted while no full
  /// raster exists, dropped (to free the buffer) the moment one lands.
  ui.Image? _preview;
  int? _previewCacheGeneration;

  /// Monotonic sequence assigned to each streamed progressive partial (#564),
  /// never reset - so partials from a newer render pass always outrank an older
  /// pass's, not just later partials within one record. Two `_renderNow` passes
  /// for one page can briefly overlap on first interpret (see the generation
  /// note in `_renderNow`); a shared, ever-increasing counter plus the
  /// generation guard in [_paintProgressivePartial] keeps the reveal ordered.
  int _progressiveSeqCounter = 0;

  /// Highest progressive-partial sequence actually painted into [_preview], so
  /// an out-of-order async rasterize of an earlier partial can't clobber a later
  /// one. Only advances; a partial applies only if its seq exceeds this.
  int _progressiveAppliedSeq = 0;

  /// Latest-only mailbox for cumulative progressive prefixes. The worker may
  /// emit another (strict superset) while picture construction or rasterization
  /// of the current prefix is awaiting the GPU. Retaining every callback as an
  /// independent future kept all of those command buffers live and replayed
  /// obsolete snapshots. One active build plus this one pending slot bounds the
  /// transient memory and always advances to the newest available prefix.
  ({
    int generation,
    int pageIndex,
    List<PdfRenderCommand> commands,
    int seq,
  })? _progressivePending;
  bool _progressiveDrainActive = false;
  int _progressiveFinalizedThrough = 0;
  int _progressiveBudgetGeneration = 0;
  bool _progressiveBudgetSpent = false;

  // Full-page rasters stay within the default exact-raster cache entry budget:
  // at most ~4.2M px (16 MiB RGBA) and 8192 px per side. Past these caps the
  // detail path takes over for the visible region. Shared with the idle
  // full-raster warm, which must price a page exactly as this widget will.
  // A detail raster is already cropped to the viewport plus its guard band, so
  // it keeps the historical 16.7M-pixel allowance for visible sharpness.
  static const _maxDetailPixels = PdfPageRasterGeometry.maxDetailPixels;
  static const _maxDimension = PdfPageRasterGeometry.maxDimension;
  // Pixel budget for the progressive vector-first preview raster - a fraction
  // of [PdfPageRasterGeometry.maxPixels]. The preview is transient (the full
  // pass re-rasterizes at
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
    PdfLiveRasterBudget.instance.register(this);
    _renderSession = PdfPageRenderSession(_renderIntent(widget));
    widget.renderHold?.addListener(_onRenderHoldChanged);
    widget.previewCache?.addListener(_onPreviewCacheChanged);
    _liveTransformFor(widget)?.addListener(_onLiveTransformChanged);
    _refreshPreview();
    _restoreRetainedScene();
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
        _directPicture != null ||
        (_preview != null && _previewCacheGeneration == null)) {
      return;
    }
    setState(_refreshPreview);
  }

  void _refreshPreview() {
    final cache = widget.previewCache;
    if (cache == null ||
        _image != null ||
        _slugPicture != null ||
        _directPicture != null) {
      return;
    }
    final frame = cache.previewFor(widget.previewIndex);
    if (frame == null) return; // keep whatever we already hold
    final next = frame.image;
    if (_preview != null) {
      if (_previewCacheGeneration == frame.generation) {
        next.dispose();
        return;
      }
      final currentPixels = _preview!.width * _preview!.height;
      final nextPixels = next.width * next.height;
      if (nextPixels < currentPixels) {
        // A byte-budget eviction can remove the sharpest cached LoD while the
        // page still owns a live clone. Keep painting that clone rather than
        // visibly stepping backward to the base preview.
        next.dispose();
        return;
      }
    }
    _preview?.dispose();
    _preview = next;
    _previewCacheGeneration = frame.generation;
    PdfPerfLog.log(
      'preview-paint page=${widget.previewIndex} '
      'lod=${frame.lod == PdfPagePreviewLod.base ? 'base' : '${frame.targetLongestSide}px'} '
      '${next.width}x${next.height}',
    );
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
    // A retained scene can be adopted from initState before LayoutBuilder has
    // supplied the page's real width. At that point the fallback 1 px/pt
    // target can make a 1.25x speculative scene look final-quality even when
    // this focused page will occupy 2x physical pixels. Re-check after the
    // first concrete layout (and after meaningful resizes), otherwise the
    // low-LoD embedded images are replayed into a sharp 2x base raster and can
    // remain soft indefinitely.
    final retainedImageRatio = _pictureImageRatio;
    if (_picture != null &&
        widget.onScreen &&
        widget.qualityVisible &&
        !_renderedAtDisplayImageRatio()) {
      _dropPicture();
      PdfPerfLog.log(
        'scene-cache reject page=${widget.previewIndex} reason=image-lod-layout '
        'have=${retainedImageRatio?.toStringAsFixed(2) ?? 'unknown'} '
        'need=${_imageRatioTarget().toStringAsFixed(2)}',
      );
    }
    // First layout of a revisited/prepared visible page can consume the exact
    // raster before scheduling any render work. The build-level check below
    // remains necessary for a placeholder State whose width was established
    // while it was off-focus.
    if (widget.onScreen && _restoreFullRaster(duringBuild: true)) {
      return;
    }
    // Zoom below fit-width changes the page's layout width while `scale` stays
    // at 1. Treat every intersecting page as foreground so a viewport spanning
    // a page boundary does not leave one half soft; mounted off-screen cache
    // neighbours retain their previous raster until they enter.
    if (previous != null && (!widget.onScreen || !widget.qualityVisible)) {
      _deferredOffscreenRasterRefresh = true;
      widget.renderScheduler?.cancel(this);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _render();
    });
  }

  @override
  void didUpdateWidget(PdfPageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.page, widget.page) ||
        oldWidget.pageEpoch != widget.pageEpoch ||
        oldWidget.contentStamp != widget.contentStamp ||
        oldWidget.destructiveStamp != widget.destructiveStamp) {
      _imageOnlyPage = null;
    }
    final scaleChanged = oldWidget.scale != widget.scale;
    final settleChanged = oldWidget.settleGeneration != widget.settleGeneration;
    final tileShareChanged =
        oldWidget.qualityPageCount != widget.qualityPageCount;
    if (scaleChanged) {
      _tightDetailGeneration = widget.settleGeneration;
    }
    final transition = _renderSession.update(_renderIntent(widget));
    if (!identical(oldWidget.renderWorker, widget.renderWorker) ||
        oldWidget.previewIndex != widget.previewIndex ||
        !identical(oldWidget.page, widget.page) ||
        oldWidget.pageEpoch != widget.pageEpoch ||
        oldWidget.contentStamp != widget.contentStamp ||
        oldWidget.destructiveStamp != widget.destructiveStamp) {
      _webSurfaceDeclined = false;
      _webSurfaceDimensions = null;
    }
    if (!identical(oldWidget.renderHold, widget.renderHold)) {
      oldWidget.renderHold?.removeListener(_onRenderHoldChanged);
      widget.renderHold?.addListener(_onRenderHoldChanged);
      _onRenderHoldChanged();
    }
    if (!identical(oldWidget.renderScheduler, widget.renderScheduler)) {
      oldWidget.renderScheduler?.cancel(this);
      // the new scheduler picks this page up on its next _render
    }
    if (!identical(oldWidget.tileRasterBackend, widget.tileRasterBackend)) {
      // Cached tiles remain valid because every backend promises the same
      // pixels. Only scene-level resources and future misses change owner.
      _disposeTileRasterSessions();
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
      _previewCacheGeneration = null;
      _refreshPreview();
      if (!transition.dropPicture) {
        _dropPicture();
        _restoreRetainedScene();
      }
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
      _imageState = null;
      _preview?.dispose();
      _preview = null;
      _previewCacheGeneration = null;
    }
    if (transition.dropPicture) {
      // Re-interpret at the new content/page. Unless we blanked above, the
      // old base raster stays up until the new render replaces it -
      // _dropPicture nulls _rasteredRatio so _renderNow still re-rasters -
      // so an additive edit on a heavy page never flashes blank.
      _dropPicture();
      _restoreRetainedScene();
      if (transition.dropDetail) {
        // The deep-zoom detail patch is a sharper raster layered above the
        // base. For additive annotation edits, keep the stale patch for
        // sharpness and let the editing overlay's commit afterimage cover the
        // new annotation until the fresh patch lands. For destructive edits
        // and display-setting changes there is no safe afterimage, so drop it.
        _dropDetail();
      }
    }
    // A far page can already have a placeholder State in the lazy sliver's
    // cache window. Its layout width therefore does not change when a page
    // command makes it the focus, so the first-layout cache adoption above is
    // not revisited. Consume a prepared retained scene/picture and then an
    // exact raster here, still inside the parent build, before composing the
    // destination frame. Command warming commonly lands after the placeholder
    // State was created, so initState alone cannot see it.
    if (_picture == null &&
        _scene == null &&
        ((widget.focusDistance == 0 && oldWidget.focusDistance > 0) ||
            (widget.onScreen && !oldWidget.onScreen))) {
      _restoreRetainedScene();
    }
    if (_image == null &&
        ((widget.focusDistance == 0 && oldWidget.focusDistance > 0) ||
            (widget.onScreen && !oldWidget.onScreen))) {
      _restoreFullRaster(duringBuild: true);
    }
    // A prefetch neighbour decoded its images at reduced resolution
    // ([prefetchImagePixelRatioFactor]); now that it is closer to focus - or
    // has scrolled into view at all - and wants full-resolution images, drop
    // the reduced buffer (and its raster) so the render below rebuilds it
    // sharp. Guarded on an actual ratio increase, so it fires once as the page
    // approaches focus, not as a churn loop.
    var promoteForFocus = false;
    final enteredViewport = widget.onScreen && !oldWidget.onScreen;
    final becameQualityVisible = widget.onScreen &&
        widget.qualityVisible &&
        (!oldWidget.onScreen || !oldWidget.qualityVisible);
    if ((widget.focusDistance < oldWidget.focusDistance &&
            widget.qualityVisible) ||
        becameQualityVisible) {
      if (!_renderedAtDisplayImageRatio()) {
        // _dropPicture nulls _rasteredRatio, so the render below re-rasters
        // rather than skipping. The reduced-resolution base raster is left up
        // (it is the right geometry, only its images are soft) until the
        // full-resolution one replaces it - no blank flash as a page scrolls in.
        _dropPicture();
        promoteForFocus = true;
      }
      // onScreen deliberately does not participate in PdfPageRenderIntent: it
      // is a scheduling hint, not part of pixel identity. It must still wake a
      // zoomed page, though. An off-screen page may have restored an exact
      // fit-size raster from PdfPagePreviewCache; that restore carries no
      // retained picture and _pictureImageRatio is null, so the image-ratio
      // promotion above correctly has nothing to invalidate. Without this
      // explicit wake-up the fit raster remains enlarged after it scrolls into
      // the zoomed viewport because no render-intent field changed.
      if (enteredViewport && widget.scale > 1.05) promoteForFocus = true;
    }
    final onScreen = _isOnScreen();
    final foreground = onScreen && widget.qualityVisible;
    // Every page that intersects the viewport must settle sharp. Near a page
    // boundary two pages can be equally important even though the viewer has
    // only one integer currentPage/focusDistance == 0. The on-screen span
    // bounds this to the small visible set; cache-window neighbours still
    // defer their replay/readback until they actually enter.
    if ((scaleChanged || settleChanged) && !foreground) {
      _deferredOffscreenRasterRefresh = true;
      // A request queued under the previous scale reads the State's current
      // fields when granted, so cancel it as well as declining the new one.
      widget.renderScheduler?.cancel(this);
    }
    if (transition.scheduleRender ||
        promoteForFocus ||
        (tileShareChanged && foreground && widget.scale > 1.05)) {
      // scale change re-rasters the page; a settle that only moved the
      // viewport refreshes the detail patch. Both route through _render so
      // they pace and coalesce through the scheduler (_renderNow skips the
      // full-page raster when the resolution is unchanged).
      if (!_deferredOffscreenRasterRefresh || foreground) {
        _deferredOffscreenRasterRefresh = false;
        _render();
      }
    } else if (_deferredOffscreenRasterRefresh && foreground) {
      // Scrolling can bring a still-mounted cache-window child back on screen
      // without changing its render intent. Its first rebuild at the new focus
      // is the trigger that consumes the deferred scale refresh.
      _deferredOffscreenRasterRefresh = false;
      _render();
    }
    if (_deferredOffscreenRasterRefresh) _scheduleDeferredVisibilityCheck();
  }

  void _scheduleDeferredVisibilityCheck() {
    if (_deferredVisibilityCheckScheduled) return;
    _deferredVisibilityCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _deferredVisibilityCheckScheduled = false;
      if (!mounted ||
          !_deferredOffscreenRasterRefresh ||
          !widget.qualityVisible ||
          !_isOnScreen()) {
        return;
      }
      _deferredOffscreenRasterRefresh = false;
      _render();
    });
  }

  bool _isOnScreen() {
    final box = context.findRenderObject();
    final viewport = MediaQuery.maybeSizeOf(context);
    if (box is! RenderBox ||
        !box.attached ||
        !box.hasSize ||
        viewport == null ||
        viewport.isEmpty) {
      // Before layout, trust the viewer's explicit visible-span answer. A
      // standalone PdfPageView defaults to onScreen=true.
      return widget.onScreen;
    }
    final pageRect = Rect.fromPoints(
      box.localToGlobal(Offset.zero),
      box.localToGlobal(Offset(box.size.width, box.size.height)),
    );
    return pageRect.overlaps(Offset.zero & viewport);
  }

  @override
  void dispose() {
    PdfLivePageRegistry.instance.remove(widget.previewIndex);
    PdfLiveRasterBudget.instance.unregister(this);
    PdfDebugDetailRegions.instance.report(widget.previewIndex, null);
    widget.renderHold?.removeListener(_onRenderHoldChanged);
    _liveTransformFor(widget)?.removeListener(_onLiveTransformChanged);
    _speculateTimer?.cancel();
    // any pending speculative bin is reaped by the cancelBinStrips below;
    // its null result resolves into a future nobody awaits any more
    _speculativeStripPlan = null;
    _speculativeStripDetail = null;
    _progressivePending = null;
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
    _disposeTileRasterSessions();
    _image?.dispose();
    _detailImage?.dispose();
    _tileDetailScene?.dispose();
    _preview?.dispose();
    super.dispose();
  }

  void _dropPicture() {
    // A retained-scene handle owns the complete picture beside the scene. Its
    // lease, rather than this page widget, decides when the shared picture can
    // be disposed; an uncached/local picture keeps the historical ownership.
    if (_sceneHandle?.picture == null) {
      _picture?.then((picture) => picture.dispose());
    }
    _directPicture = null;
    _directPictureIntent = null;
    _picture = null;
    _slugPicture?.dispose();
    _slugPicture = null;
    _setScene(null); // the scene transcribes the same content as the picture
    _pictureHasImageDraws = false;
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
    int pictureBytes = 0,
    ui.Picture? picture,
  }) {
    _releaseScene();
    if (scene != null &&
        !vectorOnly &&
        _renderedAtFullImageRatio() &&
        widget.previewCache != null) {
      // Command count is the best portable retained-heap proxy available.
      // The complete engine picture and decoded images are additional retained
      // allocations, so count all three rather than under-pricing complex
      // pages into the LRU.
      final commandBytes = scene.commands.length * 260;
      final estimatedBytes =
          commandBytes + pictureBytes + scene.decodedImageBytes;
      _sceneHandle = widget.previewCache!.retainScene(
        widget.previewIndex,
        widget.page,
        scene,
        plan: _renderPlan,
        fromWorker: fromWorker,
        imagePixelRatio: _pictureImageRatio,
        estimatedBytes: estimatedBytes,
        picture: picture,
      );
      scene = _sceneHandle!.scene;
      PdfPerfLog.log(
        'scene-cache store page=${widget.previewIndex} '
        'commands=${scene.commands.length} bytes=$estimatedBytes',
      );
    }
    _assignScene(scene, fromWorker: fromWorker, vectorOnly: vectorOnly);
  }

  void _restoreRetainedScene() {
    if (_scene != null || !PdfPageView.retainedZoomReplay) return;
    final handle = widget.previewCache?.retainedSceneFor(
      widget.previewIndex,
      widget.page,
      plan: _renderPlan,
    );
    if (handle == null) return;
    final retainedImageRatio = handle.imagePixelRatio;
    final requiredImageRatio = _imageRatioTarget();
    if (retainedImageRatio != null &&
        retainedImageRatio < requiredImageRatio * 0.99) {
      handle.dispose();
      PdfPerfLog.log(
        'scene-cache reject page=${widget.previewIndex} reason=image-lod '
        'have=${retainedImageRatio.toStringAsFixed(2)} '
        'need=${requiredImageRatio.toStringAsFixed(2)}',
      );
      return;
    }
    _sceneHandle = handle;
    _pictureImageRatio = retainedImageRatio;
    _assignScene(handle.scene, fromWorker: handle.fromWorker);
    final picture = handle.picture;
    if (picture != null) _picture = Future.value(picture);
    PdfPerfLog.log(
      'scene-cache hit page=${widget.previewIndex} '
      'commands=${handle.scene.commands.length}',
    );
  }

  void _releaseScene() {
    final previous = _scene;
    if (previous != null) {
      _disposeTileRasterSession(previous);
    }
    final handle = _sceneHandle;
    _sceneHandle = null;
    if (handle != null) {
      handle.dispose();
    } else {
      _scene?.dispose();
    }
    _scene = null;
  }

  void _assignScene(
    PdfRetainedScene? scene, {
    bool fromWorker = false,
    bool vectorOnly = false,
  }) {
    _scene = scene;
    // The image-detail decode belongs to the scene it sharpened; a new scene
    // (new content, or the same page re-recorded) invalidates it.
    _dropTileImageDetail();
    if (!identical(_regionIndexWarmScene, scene)) {
      _regionIndexWarmScene = null;
    }
    _sceneHasImageDraws =
        scene != null && PdfPageRenderer.hasImageDraws(scene.commands);
    if (scene != null) _pictureHasImageDraws = _sceneHasImageDraws;
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
  bool? _imageOnlyPage;

  /// Whether this page's small content program paints only raster images and
  /// non-painting setup/clip operators.
  ///
  /// The worker's vector-first pass deliberately omits image pixels. On a scan
  /// that pass therefore produces blank paper, then the full record starts the
  /// real Flate/JPEG decode only after the wasted request returns. Parsing a
  /// tiny scan wrapper (`q cm /Im Do Q`) locally is sub-millisecond and lets the
  /// full worker record start immediately. Complex/large streams, forms, and
  /// any actual vector or text operator conservatively keep the established
  /// progressive path.
  bool _isImageOnlyPage() {
    final cached = _imageOnlyPage;
    if (cached != null) return cached;
    final page = widget.page;
    // Keep the synchronous decode bounded as well as the parse. A tiny Flate
    // wrapper around one image is normally tens of bytes; accepting kilobytes
    // here would let a high-expansion stream turn a first-frame optimization
    // into main-isolate work. Larger programs simply take the proven worker
    // path.
    if (page.rawContentLength > 512) {
      return _imageOnlyPage = false;
    }
    try {
      final cos = page.document.cos;
      final xObjects = cos.resolve(page.resources['XObject']);
      var drewImage = false;
      final operations = ContentStreamParser.parse(page.contentBytes());
      for (final operation in operations) {
        switch (operation.operator) {
          case 'q':
          case 'Q':
          case 'cm':
          case 'gs':
          case 're':
          case 'W':
          case 'W*':
          case 'n':
            continue;
          case 'BI':
            drewImage = true;
            continue;
          case 'Do':
            if (xObjects is! CosDictionary ||
                operation.operands.isEmpty ||
                operation.operands.first is! CosName) {
              return _imageOnlyPage = false;
            }
            final name = (operation.operands.first as CosName).value;
            final object = cos.resolve(xObjects[name]);
            if (object is! CosStream ||
                object.dictionary['Subtype'] is! CosName ||
                (object.dictionary['Subtype'] as CosName).value != 'Image') {
              return _imageOnlyPage = false;
            }
            drewImage = true;
          default:
            return _imageOnlyPage = false;
        }
      }
      return _imageOnlyPage = drewImage;
    } on Exception {
      return _imageOnlyPage = false;
    }
  }

  bool _preferLocalFirstPaint() {
    if (!(PdfPageView.debugWebLocalFirstPaintBackendOverride ?? kIsWeb) ||
        PdfPageView.webLocalFirstPaintMaxRawContentBytes <= 0 ||
        widget.focusDistance != 0) {
      return false;
    }
    final worker = widget.renderWorker;
    if (worker == null ||
        !worker.isActive ||
        PdfPageView._webLocalFirstPaintAttempted[worker] == true) {
      return false;
    }
    PdfPageView._webLocalFirstPaintAttempted[worker] = true;
    if (widget.page.rawContentLength >
        PdfPageView.webLocalFirstPaintMaxRawContentBytes) {
      return false;
    }
    // Any page-level XObject can hide a large image or nested form. Keep those
    // on the worker without recursively inspecting their resource graph on the
    // very path whose purpose is a cheap first paint.
    final xObjects = widget.page.document.cos.resolve(
      widget.page.resources['XObject'],
    );
    return xObjects is! CosDictionary || xObjects.entries.isEmpty;
  }

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
    _dropTileImageDetail();
    _renderSession.invalidateDetail();
    final hadImage = _detailImage != null;
    _detailImage?.dispose();
    _detailImage = null;
    _detailFraction = null;
    _detailPixelRatio = null;
    _detailIntent = null;
    if (hadImage && mounted) setState(() {});
  }

  void _adoptDetail(
    ui.Image image,
    Rect fraction,
    double pixelRatio,
  ) {
    _detailImage?.dispose();
    _detailImage = image;
    _detailFraction = fraction;
    _detailPixelRatio = pixelRatio;
    _detailIntent = _renderIntent(widget);
  }

  bool _detailContentIsCurrent() => _intentIsCurrent(_detailIntent);

  /// Whether pixels taken under [intent] still depict this page's current
  /// content. Shared by the detail patch and the base raster - both ask exactly
  /// this question, and a second copy of the field list would be one edit away
  /// from letting one of them paint stale content.
  bool _intentIsCurrent(PdfPageRenderIntent? intent) {
    if (intent == null ||
        intent.pageIndex != widget.previewIndex ||
        intent.pageEpoch != widget.pageEpoch ||
        intent.contentStamp != widget.contentStamp ||
        intent.destructiveStamp != widget.destructiveStamp ||
        intent.trustContentStamp != widget.trustContentStamp ||
        intent.rotation != widget.rotation ||
        intent.pageColor != widget.pageColor ||
        intent.showAnnotations != widget.showAnnotations) {
      return false;
    }
    return widget.trustContentStamp || identical(intent.page, widget.page);
  }

  /// Whether the live base raster already is what this render pass needs.
  /// Below the full-page caps that means exactly the resolution a fresh render
  /// would produce. Past the caps, an existing current base remains the soft
  /// whole-page backing and [_updateDetail] supplies the sharp visible pixels.
  ///
  /// The last clause is what keeps a prefetch neighbour honest: a page rendered
  /// off-focus decoded its images at [PdfPageView.prefetchImagePixelRatioFactor]
  /// of full, and once it comes into focus those pixels are genuinely stale even
  /// though the ratio and content match. Mirrors [_renderedAtFullImageRatio]'s
  /// comparison so the two cannot disagree about what "full" means.
  bool _baseRasterIsCurrent() {
    if (PdfPageView.directPicturePresentation &&
        _directPicture != null &&
        _intentIsCurrent(_directPictureIntent) &&
        _renderedAtDisplayImageRatio()) {
      return true;
    }
    final state = _imageState;
    // A Slug-routed page paints its picture under a transform instead of a base
    // raster; its render pass is not a readback this can skip.
    if (state == null || _image == null || _slugPicture != null) return false;
    if (!_intentIsCurrent(state.intent)) return false;
    final effective = _effectiveRatio();
    final needsDetail = _desiredRatioAt(widget.scale) > effective * 1.05;
    // A sharper raster is also current when zooming out: scaling it down is
    // both visually lossless and far cheaper than replaying the page into a
    // smaller image. The live-raster budget can still evict that extra memory.
    if (!needsDetail && state.ratio < effective * 0.99) {
      return false;
    }
    final imageRatio = state.imageRatio;
    if (!needsDetail &&
        imageRatio != null &&
        imageRatio < _fullImageRatio() * 0.99) {
      return false;
    }
    return true;
  }

  /// The uncapped resolution at an explicit [scale], so speculation can price
  /// the scale a settle is ABOUT to apply.
  double _desiredRatioAt(double scale) => PdfPageRasterGeometry.desiredRatio(
        pageSize: _renderPlan.pageSize(widget.page),
        layoutWidth: _layoutWidth ?? 0,
        devicePixelRatio: _pixelRatio ?? 1.0,
        scale: scale,
      );

  /// Scale used by the whole-page base raster.
  ///
  /// The InteractiveViewer's live zoom is global, so lazy-list neighbours also
  /// receive it even when no pixel of those pages is visible. Rasterizing them
  /// at that zoom produced 60-70 MB full-page images that were immediately
  /// replaced by fit rasters as navigation moved on. Off-screen pages instead
  /// keep (or first build) the fit-resolution safety net; once a page overlaps
  /// the viewport its ordinary promotion path requests the sharp base and
  /// region/tile detail.
  double get _baseRasterScale =>
      widget.onScreen ? widget.scale : math.min(1.0, widget.scale);

  double _effectiveRatio() => _effectiveRatioAt(_baseRasterScale);

  // --- Live-raster budget (#405) --------------------------------------------

  static int _imageBytes(ui.Image? image) =>
      image == null ? 0 : image.width * image.height * 4;

  @override
  int get liveRasterBytes =>
      _imageBytes(_image) +
      _imageBytes(_detailImage) +
      (_scene?.decodedImageBytes ?? 0) +
      (_tileDetailScene?.decodedImageBytes ?? 0);

  @override
  int get liveRasterDistance => widget.focusDistance;

  @override
  bool get liveRasterOnScreen => widget.onScreen;

  @override
  void evictLiveRaster() {
    if (!mounted) return;
    // Reclaim this off-viewport page's heavy rasters: the base raster, the
    // deep-zoom detail patch, and the retained scene's decoded images. The soft
    // preview (if any) stays up, and the page re-rasterises when it is next
    // scrolled back near the viewport (_render re-runs because _image and
    // _rasteredRatio are null). Never called on the focused page.
    setState(() {
      _image?.dispose();
      _image = null;
      _imageState = null;
      _dropDetail(); // also frees the tile image-detail scene
      _dropPicture(); // frees the scene + slug picture and nulls _rasteredRatio
    });
    PdfPerfLog.log(
      'live-raster evict page=${widget.previewIndex} '
      'dist=${widget.focusDistance} '
      'onScreen=${widget.onScreen}',
    );
  }

  bool _budgetRebalanceScheduled = false;

  /// Trims the global live-raster budget after this page's raster grew, once
  /// per frame. Post-frame so evicting another page (its setState) never lands
  /// mid-build of this one.
  void _scheduleBudgetRebalance() {
    if (_budgetRebalanceScheduled) return;
    _budgetRebalanceScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _budgetRebalanceScheduled = false;
      PdfLiveRasterBudget.instance.rebalance();
    });
  }

  /// The image-decode resolution this page's record should use: the display
  /// ratio (capped by [PdfPageView.workerImagePixelRatioCap]), reduced by
  /// [PdfPageView.prefetchImagePixelRatioFactor] when the page is an off-screen
  /// prefetch neighbour (#451). A page any part of which is on screen always
  /// gets the full ratio, so a page scrolling in decodes sharp once instead of
  /// landing soft and re-rendering when it reaches the centre (#657).
  double _imageRatioTarget() {
    final base = _fullImageRatio();
    // The document's first cold visible page decodes at its exact physical
    // footprint. That gets useful image pixels on screen without making open's
    // first-content boundary pay for the 2x final-quality payload. Once that
    // raster lands, [_scheduleFocusedImageRefinement] keeps it painted while a
    // second record replaces the image layer at [focusedImageDecodeHeadroom].
    // Do not repeat that two-pass transaction on navigation: by then a soft
    // preview already supplies first pixels, and one direct final-quality
    // record reaches stable sharpness substantially sooner.
    if (widget.onScreen &&
        widget.qualityVisible &&
        (widget.renderWorker?.isActive ?? false) &&
        widget.performance?.diagnostics.observations == 0 &&
        _image == null &&
        _directPicture == null &&
        _slugPicture == null) {
      return _effectiveRatio();
    }
    if (widget.onScreen || widget.focusDistance <= 0) return base;
    return base * PdfPageView.prefetchImagePixelRatioFactor;
  }

  /// The full (unreduced) image-decode ratio for the current page state.
  ///
  /// Adaptive image caps are a speculation/memory-pressure control, not a
  /// final-quality ceiling. Once a page is on screen, decode its
  /// images with [PdfPageView.focusedImageDecodeHeadroom] over the base
  /// raster's physical resolution. A 1:1 image decode is sampled into the page
  /// picture and then sampled again into the final raster; on the real-world
  /// illustrated corpus that remains visibly softer than PDFium. Otherwise a
  /// 1.25x conservative cap can be flattened into (and later restored as) a
  /// 1.7-2.2x page raster, leaving image content permanently blurry while
  /// vector text remains sharp. Off-screen pages still honor the cap and the
  /// additional prefetch reduction in [_imageRatioTarget].
  double _fullImageRatio() {
    final effective = _effectiveRatio();
    if (widget.onScreen && widget.qualityVisible) {
      return effective * PdfPageView.focusedImageDecodeHeadroom;
    }
    return math.min(
      effective,
      widget.workerImagePixelRatioCap ?? double.infinity,
    );
  }

  /// The image ratio [_picture]/[_scene] were interpreted at, so a later render
  /// can tell a reduced-resolution prefetch buffer from a full-resolution one
  /// and drop it when the page becomes visible (null = none / unknown).
  double? _pictureImageRatio;
  bool _pictureHasImageDraws = false;
  bool _focusedImageRefinementScheduled = false;

  /// Whether the current buffer decoded its images at full resolution - i.e.
  /// this is not a reduced-resolution prefetch buffer. Only such buffers seed
  /// the shared full-raster cache, so [_restoreFullRaster] never serves a
  /// blurry prefetch raster to a page that has since become visible (#451).
  bool _renderedAtFullImageRatio() =>
      !_pictureHasImageDraws ||
      _pictureImageRatio == null ||
      _pictureImageRatio! >= _fullImageRatio() * 0.99;

  /// Whether the decoded image source has at least one sample per physical
  /// display pixel at the current scale. A picture recorded with 2x headroom
  /// at fit scale can therefore zoom up to 2x without another decode; cache
  /// admission still uses the stricter [_renderedAtFullImageRatio].
  bool _renderedAtDisplayImageRatio() =>
      !_pictureHasImageDraws ||
      _pictureImageRatio == null ||
      _pictureImageRatio! >= _effectiveRatio() * 0.99;

  /// Whether a transform-retained picture's embedded images are sharp at the
  /// live zoom, rather than merely at the fit-size backing resolution.
  ///
  /// [_renderedAtDisplayImageRatio] intentionally answers the latter: it is
  /// used to decide whether a retained picture can replace the base raster.
  /// With [baseRasterScale] set, however, [_effectiveRatio] stays at the fit
  /// ratio while the viewer transform can be many times larger. Using that
  /// answer to suppress [_updateDetail] leaves vector/text transform-sharp but
  /// permanently magnifies the fit-size image decode (the CAD symptom is crisp
  /// labels over a blocky raster underlay). Native image pixels cannot be
  /// improved by another decode; otherwise compare with the uncapped live
  /// display footprint that the detail/tile path exists to supply.
  bool _pictureImagesAreSharpAtZoom() {
    if (!_pictureHasImageDraws) return true;
    if (_scene?.imagesAtNativeResolution ?? false) return true;
    final imageRatio = _pictureImageRatio;
    return imageRatio != null &&
        imageRatio >= _desiredRatioAt(widget.scale) * 0.99;
  }

  /// Refines the initial cold page's 1x embedded-image decode after its first
  /// raster has reached the compositor. The existing raster remains the
  /// backing layer, so this is a soft-to-sharp transition rather than another
  /// blank/loading state. Navigation requests final quality in one pass.
  void _scheduleFocusedImageRefinement() {
    if (_focusedImageRefinementScheduled ||
        !widget.onScreen ||
        !widget.qualityVisible ||
        _image == null ||
        !_pictureHasImageDraws ||
        _renderedAtFullImageRatio()) {
      return;
    }
    _focusedImageRefinementScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusedImageRefinementScheduled = false;
      if (!mounted ||
          !widget.onScreen ||
          !widget.qualityVisible ||
          _image == null ||
          !_pictureHasImageDraws ||
          _renderedAtFullImageRatio()) {
        return;
      }
      final previousRatio = _pictureImageRatio;
      _dropPicture();
      PdfPerfLog.log(
        'image-refine page=${widget.previewIndex} '
        'have=${previousRatio?.toStringAsFixed(2) ?? 'unknown'} '
        'need=${_fullImageRatio().toStringAsFixed(2)}',
      );
      _render();
    });
  }

  /// [_effectiveRatio] at an explicit [scale] (see [_desiredRatioAt]).
  double _effectiveRatioAt(double scale) =>
      PdfPageRasterGeometry.effectiveRatio(
        pageSize: _renderPlan.pageSize(widget.page),
        layoutWidth: _layoutWidth ?? 0,
        devicePixelRatio: _pixelRatio ?? 1.0,
        scale: math.min(scale, widget.baseRasterScale ?? scale),
      );

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

  (int width, int height) _rasterDimensions(double pixelRatio) =>
      PdfPageRasterGeometry.dimensions(
        _renderPlan.pageSize(widget.page),
        pixelRatio,
      );

  /// Restores an exact recent-page raster without waiting for render hold.
  ///
  /// This path is deliberately ahead of the scheduler: the image has already
  /// been interpreted and read back at the requested physical size, so using
  /// it cannot introduce the UI-thread hitch that fast-scroll hold prevents.
  bool _restoreFullRaster({bool duringBuild = false}) {
    final cache = widget.previewCache;
    if (cache == null ||
        _image != null ||
        _slugPicture != null ||
        _directPicture != null ||
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
    // Memory-cache lookups may deliberately return a sharper raster for the
    // same page geometry. Record what those pixels can actually resolve, not
    // merely the lower ratio requested today, so a subsequent scale change can
    // keep reusing them until it genuinely asks for more detail.
    final actualRatio = effective *
        math.min(
          image.width / dimensions.$1,
          image.height / dimensions.$2,
        );
    widget.renderScheduler?.cancel(this);
    _renderSession.invalidateFull();
    void adopt() {
      _image = image;
      _rasteredRatio = actualRatio;
      // A cache entry only ever holds a full-resolution raster (putFullImage is
      // gated on _renderedAtFullImageRatio), so it restores as one.
      _imageState = (
        ratio: actualRatio,
        imageRatio: null,
        intent: _renderIntent(widget),
      );
      _preview?.dispose();
      _preview = null;
    }

    if (duringBuild) {
      adopt();
    } else {
      setState(adopt);
    }
    _scheduleBudgetRebalance();
    PdfPerfLog.log(
      'full-raster cache hit page=${widget.previewIndex} '
      '${image.width}x${image.height}',
    );
    if (duringBuild) {
      // _PdfViewerPage records readiness with setState. Calling it from this
      // child's LayoutBuilder would mark the parent dirty during build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onRasterReady?.call();
      });
    } else {
      widget.onRasterReady?.call();
    }
    return true;
  }

  /// Promotes a complete low-resolution preview when it is not actually low
  /// resolution at this page's current physical display size.
  ///
  /// Mixed-format CAD files can lay ordinary sheets out at less than 200 px on
  /// their longest side because a panoramic sheet establishes the fit width.
  /// The preview cache already holds a complete 200 px raster in that case;
  /// reinterpreting hundreds of thousands of vector operations to replace it
  /// with the same number of pixels only delays viewport stability.
  bool _restoreSufficientPreview() {
    final cache = widget.previewCache;
    if (cache == null ||
        _image != null ||
        _slugPicture != null ||
        _directPicture != null ||
        _layoutWidth == null ||
        _pixelRatio == null) {
      return false;
    }
    final effective = _effectiveRatio();
    final dimensions = _rasterDimensions(effective);
    final image = cache.completeImageFor(
      widget.previewIndex,
      widget.page,
      width: dimensions.$1,
      height: dimensions.$2,
    );
    if (image == null) return false;
    final actualRatio = effective *
        math.min(
          image.width / dimensions.$1,
          image.height / dimensions.$2,
        );
    widget.renderScheduler?.cancel(this);
    _renderSession.invalidateFull();
    setState(() {
      _image = image;
      _rasteredRatio = actualRatio;
      _imageState = (
        ratio: actualRatio,
        imageRatio: null,
        intent: _renderIntent(widget),
      );
      _preview?.dispose();
      _preview = null;
    });
    _scheduleBudgetRebalance();
    PdfPerfLog.log(
      'preview-promote page=${widget.previewIndex} '
      '${image.width}x${image.height} target=${dimensions.$1}x${dimensions.$2}',
    );
    widget.onRasterReady?.call();
    return true;
  }

  /// The content identity a persistent raster is keyed by, so an edit that
  /// changed (or removed) this page's content can never load the pixels the
  /// page used to have. Static documents keep this at `0.0.0` for the whole
  /// session, which is exactly when the disk tier is allowed to be bound.
  String _contentRevision() =>
      '${widget.pageEpoch}.${widget.contentStamp}.${widget.destructiveStamp}';

  /// Whether a persistent-tier lookup is worth an await right now: the tier
  /// exists, and this page has nothing to paint, so a disk hit is a strictly
  /// faster first paint than interpreting and rasterizing the page.
  bool _shouldTryDiskRaster() {
    final cache = widget.previewCache;
    return cache != null &&
        cache.hasPersistentFullRasters &&
        _image == null &&
        _picture == null &&
        _slugPicture == null &&
        _directPicture == null &&
        _layoutWidth != null &&
        _pixelRatio != null;
  }

  /// Restores an exact raster stored by a previous session.
  ///
  /// Unlike [_restoreFullRaster] this awaits a store read plus a decode, so it
  /// takes a generation token first and drops the result if a newer render (or
  /// any other source of pixels) won the race meanwhile.
  Future<bool> _restoreFullRasterFromDisk() async {
    final cache = widget.previewCache;
    if (cache == null) return false;
    final pageIndex = widget.previewIndex;
    final effective = _effectiveRatio();
    final dimensions = _rasterDimensions(effective);
    final generation = _renderSession.fullGeneration;
    final image = await cache.loadFullFromDisk(
      pageIndex,
      widget.page,
      width: dimensions.$1,
      height: dimensions.$2,
      pageColor: widget.pageColor,
      annotations: widget.showAnnotations,
      rotation: widget.rotation,
      revision: _contentRevision(),
    );
    if (image == null) return false;
    if (!_renderSession.acceptsFull(generation, pageIndex) ||
        _image != null ||
        _slugPicture != null ||
        _directPicture != null) {
      image.dispose();
      return false;
    }
    widget.renderScheduler?.cancel(this);
    _renderSession.invalidateFull();
    setState(() {
      _image = image;
      _rasteredRatio = effective;
      // Stored rasters are only ever written from a full-resolution render
      // (putFullImage is gated on _renderedAtFullImageRatio), so they restore
      // as full-resolution ones.
      _imageState = (
        ratio: effective,
        imageRatio: null,
        intent: _renderIntent(widget),
      );
      _preview?.dispose();
      _preview = null;
    });
    _scheduleBudgetRebalance();
    PdfPerfLog.log(
      'full-raster disk hit page=$pageIndex ${image.width}x${image.height}',
    );
    widget.onRasterReady?.call();
    return true;
  }

  Future<void> _render() async {
    // The worker-owned DOM canvas starts from build once its concrete pixel
    // dimensions are known. Do not simultaneously interpret/rasterize the same
    // page through SkWasm; a capability decline calls back and re-enters this
    // method with [_webSurfaceDeclined] set.
    if (_usesWebWorkerSurface) return;
    if (_restoreFullRaster()) return;
    if (_restoreSufficientPreview()) return;
    // Lazy slivers build cache-window neighbours before they enter the
    // viewport. Do not turn those placeholders into first-render worker jobs:
    // on a page jump, two invisible neighbours otherwise deserialize and
    // rasterize beside the focused page, serializing three GPU readbacks and
    // delaying the visible result. Focus-distance updates call `_render` when
    // one actually crosses on screen; the idle raster warmer remains the
    // explicit, budgeted mechanism for preparing farther pages in advance.
    if (_picture == null && _image == null && !_isOnScreen()) {
      widget.renderScheduler?.cancel(this);
      return;
    }
    // Then the persistent tier: a stored raster at exactly this size is the
    // whole page already interpreted and rasterized, so reading and decoding
    // it beats scheduling the render it would replace. A miss costs an
    // in-memory manifest lookup (PdfDiskCache answers from `_sizes` without
    // touching the backend) and falls straight through.
    if (_shouldTryDiskRaster() && await _restoreFullRasterFromDisk()) return;
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
        rastered >= _effectiveRatio() * 0.99) {
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

  Future<bool> _paceWorkerUiWork({bool replacePending = true}) async {
    final scheduler = widget.renderScheduler;
    if (scheduler == null) return true;
    // renderPriority includes large visibility boosts (for example -1000),
    // while PdfPageRenderScheduler.focus is a real page index. Comparing the
    // two made completion ordering effectively arbitrary. The state token
    // already identifies the visible/preloaded slot; rank it by its actual
    // page index and keep only its latest cumulative worker result.
    return scheduler.paceUiWork(
      this,
      widget.previewIndex,
      replacePending: replacePending,
    );
  }

  bool get _usesWebWorkerSurface {
    final worker = widget.renderWorker;
    return kIsWeb &&
        PdfPageView.webDomRasterPresentation &&
        !_webSurfaceDeclined &&
        worker != null &&
        worker.supportsPageSurfaces;
  }

  void _webSurfacePresented() {
    if (!mounted || !_usesWebWorkerSurface) return;
    PdfPerfLog.log(
      'web-worker-surface presented page=${widget.previewIndex}',
    );
    widget.onRasterReady?.call();
  }

  void _webSurfaceRejected() {
    if (!mounted || _webSurfaceDeclined) return;
    setState(() {
      _webSurfaceDeclined = true;
    });
    _render();
  }

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
  Future<(ui.Picture, PdfRetainedScene?, bool)?> _interpretPicture(
      {bool forceLocal = false,
      _PendingWorkerRecord? pendingWorkerRecord}) async {
    final pageIndex = widget.previewIndex;
    final worker = widget.renderWorker;
    // Phase clocks exist only while the perf log is on (the render_worker_web
    // _perfClock pattern): this runs per page render, so even a cheap
    // Stopwatch allocation stays off the ordinary path.
    final waitClock = pendingWorkerRecord?.waitClock ??
        (PdfPerfLog.enabled ? (Stopwatch()..start()) : null);
    if (!forceLocal &&
        (pendingWorkerRecord != null || (worker != null && worker.isActive))) {
      // priority 0: the on-screen page preempts background prefetch.
      // imagePixelRatio caps embedded images to the page's on-screen
      // resolution so a CAD raster underlay isn't decoded/shipped/rasterized
      // at its native 100+ megapixels (the deep-zoom patch re-rasters the
      // visible region for sharper zoom).
      final imageRatio = pendingWorkerRecord?.imageRatio ?? _imageRatioTarget();
      _pictureImageRatio = imageRatio;
      final commands = await (pendingWorkerRecord?.commands ??
          worker!.record(
            pageIndex,
            annotations: widget.showAnnotations,
            priority: widget.renderPriority,
            imagePixelRatio: imageRatio,
          ));
      // The wait phase ends when the record reply lands; the build phase is
      // everything after - decoding images that shipped un-decoded and
      // turning the command buffer into the picture.
      final waitMs =
          waitClock == null ? null : waitClock.elapsedMicroseconds / 1000.0;
      final buildClock = waitClock == null ? null : (Stopwatch()..start());
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
        _pictureHasImageDraws = PdfPageRenderer.hasImageDraws(commands);
        // A focus jump can leave the old page's worker request in flight. Its
        // background parse is harmless (and warms the worker transcript), but
        // replaying that display list can occupy the UI isolate precisely
        // when the destination result arrives. Check both before and after
        // the paced UI turn because the page may leave while queued.
        bool deferOffscreenReplay() {
          if (widget.focusDistance == 0 || _isOnScreen()) return false;
          _deferredOffscreenRasterRefresh = true;
          PdfPerfLog.log(
            'render defer-replay page=$pageIndex reason=left-viewport',
          );
          return true;
        }

        if (deferOffscreenReplay()) return null;
        if (!await _paceWorkerUiWork() || _abandoned(pageIndex)) return null;
        if (deferOffscreenReplay()) return null;
        _lastInterpretPath = 'worker';
        _lastInterpretResultBytes = _logImageStats(pageIndex, commands);
        final (picture, scene) = await _replayableFromCommands(commands,
            maxImagePixelRatio: imageRatio);
        if (_abandoned(pageIndex) || _renderPaused) {
          picture.dispose();
          scene?.dispose();
          return null;
        }
        _lastInterpretWaitMs = waitMs;
        _lastInterpretBuildMs =
            buildClock == null ? null : buildClock.elapsedMicroseconds / 1000.0;
        return (picture, scene, true);
      }
    }
    if (_abandoned(pageIndex)) return (_emptyPicture(), null, false);
    if (_renderPaused) return null;
    // The worker may be active yet decline this page (it returns null), in
    // which case the interpret runs here - the log must say so, not 'worker'.
    _lastInterpretPath = 'recorded';
    // The staged first-content pass is worker-only: once the worker has
    // declined a visible page, recording it locally twice would add two UI
    // isolate stalls. Pay for the final image quality in that single pass.
    final localImageRatio = widget.onScreen && widget.qualityVisible
        ? _fullImageRatio()
        : _imageRatioTarget();
    _pictureImageRatio = localImageRatio;
    // The local path has no worker wait: record + decode + picture build are
    // one UI-thread phase, reported entirely as build.
    final buildClock = PdfPerfLog.enabled ? (Stopwatch()..start()) : null;
    void stampLocalPhases() {
      _lastInterpretWaitMs = buildClock == null ? null : 0;
      _lastInterpretBuildMs =
          buildClock == null ? null : buildClock.elapsedMicroseconds / 1000.0;
    }

    if (!PdfPageView.retainedZoomReplay) {
      final result = await PdfPageRenderer.renderPictureRecordedWithPlan(
        widget.page,
        _renderPlan,
        maxImagePixelRatio: localImageRatio,
        imageDecodeHeadroom: 1,
      );
      stampLocalPhases();
      return (result, null, false);
    }
    // Same record + decode renderPictureRecordedWithPlan runs internally,
    // but the command buffer and decoded images are kept for zoom replays
    // instead of being discarded after the 1:1 replay below.
    final scene = await PdfRetainedScene.record(widget.page,
        plan: _renderPlan,
        maxImagePixelRatio: localImageRatio,
        imageDecodeHeadroom: 1);
    _lastInterpretResultBytes = _logImageStats(pageIndex, scene.commands);
    if (!_retainScene(scene.commands)) {
      // Too dense or too fragmented to replay per zoom settle: take the 1:1
      // picture (it holds its own image refs) and drop the scene - the classic
      // cached-picture path serves this page's zooms.
      final picture = scene.replay(pixelRatio: 1);
      scene.dispose();
      stampLocalPhases();
      return (picture, null, false);
    }
    final picture = scene.replay(pixelRatio: 1);
    stampLocalPhases();
    return (picture, scene, false);
  }

  /// Whether a page's recorded commands should retain their scene - the
  /// [PdfPageView.retainedZoomReplay] switch plus the
  /// [PdfPageView.retainedZoomReplayMaxCommands] density ceiling. With
  /// [PdfPageView.stripZoomReplay] on, eligible over-ceiling pages retain too:
  /// their zooms re-bin through the strip device instead of the flat replay.
  bool _retainScene(List<PdfRenderCommand> commands) =>
      PdfPageView.retainedZoomReplay &&
      (commands.length <= PdfPageView.retainedZoomReplayMaxCommands ||
          ((PdfPageView.retainDenseScenesOffFocus ||
                  (widget.onScreen && widget.qualityVisible)) &&
              (_stripReplayCommands(commands) || _retainForTiles(commands))));

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
    List<PdfRenderCommand> commands, {
    double? maxImagePixelRatio,
  }) async {
    // The build-split instrumentation exists only while the perf log is on
    // (the phase-clock pattern in _interpretPicture): the carrier and the
    // replay clock stay off the ordinary path. 'build' is the dominant
    // opaque figure in a cold-open trace, and whether it is the image decode
    // or the canvas calls is exactly what these two numbers answer.
    final timing = PdfPerfLog.enabled ? PdfSceneBuildTiming() : null;
    if (!_retainScene(commands)) {
      final picture = await PdfPageRenderer.pictureFromCommandsWithPlan(
        widget.page,
        commands,
        _renderPlan,
        maxImagePixelRatio: maxImagePixelRatio,
      );
      // Deliberately unmeasured: this branch decodes INSIDE
      // pictureFromCommandsWithPlan and constructs the picture in the same
      // call, so a replayMs to pair with a decodeMs doesn't exist here -
      // and PdfPerfLog.interpret prints the split only as a pair, so a lone
      // decode would never surface anyway. Threading a carrier into the
      // public renderer API to collect an unprintable number is cost without
      // signal; both fields stay null and the line omits them.
      _lastInterpretDecodeMs = null;
      _lastInterpretReplayMs = null;
      _lastInterpretTextShapeMs = null;
      _lastInterpretTextShapeMiss = null;
      _lastInterpretTextShapeHit = null;
      return (picture, null);
    }
    // The record shipped platform-codec images (JPEGs the worker can't decode)
    // un-decoded; cap that UI-thread decode to the same display resolution the
    // worker used, so a giant raster underlay isn't decoded at native size here
    // (the perf(web) 643 ms main-thread JPEG decode, #458).
    final scene = await PdfRetainedScene.fromCommands(
      widget.page,
      commands,
      plan: _renderPlan,
      retainDecodedPixels:
          widget.tileRasterBackend.prefersDirectDecodedImageUploads,
      timing: timing,
      maxImagePixelRatio: maxImagePixelRatio,
    );
    if (timing != null) CanvasPdfDevice.debugResetTextShape();
    final replayClock = timing == null ? null : (Stopwatch()..start());
    final picture = scene.replay(pixelRatio: 1);
    _lastInterpretDecodeMs = timing?.decodeMs;
    _lastInterpretReplayMs =
        replayClock == null ? null : replayClock.elapsedMicroseconds / 1000.0;
    _lastInterpretTextShapeMs =
        timing == null ? null : CanvasPdfDevice.debugTextShapeUs / 1000.0;
    _lastInterpretTextShapeMiss =
        timing == null ? null : CanvasPdfDevice.debugTextShapeMiss;
    _lastInterpretTextShapeHit =
        timing == null ? null : CanvasPdfDevice.debugTextShapeHit;
    return (picture, scene);
  }

  /// Progressive rendering's fast first pass: records the page WITHOUT decoding
  /// its images (so it returns quickly even when a raster underlay takes
  /// seconds to decode) and paints the vector/text at once, images skipped.
  /// The full pass in [_renderNow] then re-rasters with the images in. No-op
  /// without an active worker (the local render already decodes inline).
  ///
  /// When the page draws no images the fast buffer is the whole page, so it is
  /// cached as [_picture] for the full pass to reuse - no second record.
  /// Rasterizes a bounded command prefix into the preview slot before the full
  /// vector record runs.
  ///
  /// On a dense sheet the `worker.record` in [_paintVectorFirst] walks the
  /// whole page, which can take seconds - and until it returns the page is
  /// blank paper. A `commandLimit`'d record stops the parse cursor early, so
  /// this lands in a small fraction of that time and puts real ink on screen;
  /// the vector and full passes replace it as they arrive.
  ///
  /// This is deliberately a *painter-order prefix*, not PDFium's spatial
  /// top-down band: our worker protocol is strictly one-request-one-response,
  /// so a true streaming band is a much larger change (tracked as #564). On a
  /// sheet authored in region order the prefix reads naturally; on one authored
  /// by layer it is a partial drawing. Either way it is strictly more
  /// information than blank paper, and it is transient.
  ///
  /// Only dense pages pay the extra record - see [earlyPrefixMinContentBytes].
  Future<void> _paintEarlyPrefix(
    int generation,
    int pageIndex,
    PdfRenderWorker worker,
    int priority,
  ) async {
    if (!PdfPageView.earlyPrefixPaint || _renderPaused) return;
    // Something is already on screen for this page; there is nothing to
    // improve on, and overwriting it would be a downgrade.
    if (_image != null || _preview != null || _slugPicture != null) return;
    if (widget.page.rawContentLength < PdfPageView.earlyPrefixMinContentBytes) {
      return;
    }

    final commands = await worker.record(
      pageIndex,
      // The prefix is transient, so keep it pure page content: annotations are
      // drawn after the (truncated) content walk and the full passes bring
      // them in anyway.
      annotations: false,
      priority: priority,
      decodeImages: false,
      commandLimit: PdfPageView.earlyPrefixCommandLimit,
    );
    if (commands == null ||
        commands.isEmpty ||
        _superseded(generation, pageIndex) ||
        _renderPaused ||
        // A full pass may have overtaken us while the prefix was recording.
        _image != null) {
      return;
    }
    if (!await _paceWorkerUiWork() ||
        _superseded(generation, pageIndex) ||
        _renderPaused ||
        _image != null) {
      return;
    }

    final picture = await PdfPageRenderer.pictureFromCommandsWithPlan(
      widget.page,
      commands,
      _renderPlan,
      includeImages: false,
    );
    if (_superseded(generation, pageIndex) || _renderPaused || _image != null) {
      picture.dispose();
      return;
    }
    // _vectorFirstRatio is already bounded by _previewMaxPixels, so a large
    // sheet cannot turn this into an expensive fill.
    final ratio = _vectorFirstRatio();
    final image = await PdfPageRenderer.rasterize(
      picture,
      PdfPageRenderer.pageSize(widget.page, rotation: widget.rotation),
      ratio,
    );
    picture.dispose();
    if (_superseded(generation, pageIndex) || _image != null) {
      image.dispose();
      return;
    }
    if (!mounted) {
      image.dispose();
      return;
    }
    setState(() {
      _preview?.dispose();
      _preview = image;
      _previewCacheGeneration = null;
    });
    PdfPerfLog.log('early-prefix page=$pageIndex commands=${commands.length} '
        'limit=${PdfPageView.earlyPrefixCommandLimit}${PdfPerfLog.rssSuffix()}');
  }

  /// Rasterizes one streamed linework prefix ([commands]) into [_preview] as the
  /// vector-first record walks the page (#564), giving a top-down reveal before
  /// that record's own full raster lands. [seq] is the partial's monotonic order
  /// within this record; the guards keep the newest applied and drop anything a
  /// landed full raster ([_image]) or a superseded render has overtaken. Each
  /// partial is a superset of the last, so replacing the preview outright is
  /// correct.
  Future<void> _paintProgressivePartial(
    int generation,
    int pageIndex,
    List<PdfRenderCommand> commands,
    int seq,
  ) async {
    if (!PdfPageView.progressiveStreamingPaint) return;
    // Bail on anything that outranks a preview in the paint stack, matching
    // _paintEarlyPrefix: a landed full raster (_image), a slug picture, or a
    // superseded/recycled render. _superseded (not just _abandoned) also drops
    // an older overlapping pass so its smaller prefix can't flicker over a
    // newer pass's larger one.
    if (commands.isEmpty ||
        _superseded(generation, pageIndex) ||
        _renderPaused ||
        _image != null ||
        _slugPicture != null ||
        generation <= _progressiveFinalizedThrough ||
        (generation == _progressiveBudgetGeneration &&
            _progressiveBudgetSpent) ||
        seq <= _progressiveAppliedSeq) {
      return;
    }
    if (!await _paceWorkerUiWork()) return;
    if (_superseded(generation, pageIndex) ||
        _renderPaused ||
        _image != null ||
        _slugPicture != null ||
        generation <= _progressiveFinalizedThrough ||
        (generation == _progressiveBudgetGeneration &&
            _progressiveBudgetSpent) ||
        seq <= _progressiveAppliedSeq) {
      return;
    }
    final uiClock = Stopwatch()..start();
    final picture = await PdfPageRenderer.pictureFromCommandsWithPlan(
      widget.page,
      commands,
      _renderPlan,
      includeImages: false,
    );
    // Re-check after each await: the full raster or a slug may have landed, the
    // page may have been recycled, or a newer partial may already be applied.
    if (_superseded(generation, pageIndex) ||
        _renderPaused ||
        _image != null ||
        _slugPicture != null ||
        generation <= _progressiveFinalizedThrough ||
        seq <= _progressiveAppliedSeq) {
      picture.dispose();
      return;
    }
    final image = await PdfPageRenderer.rasterize(
      picture,
      PdfPageRenderer.pageSize(widget.page, rotation: widget.rotation),
      _vectorFirstRatio(),
    );
    picture.dispose();
    if (!mounted ||
        _superseded(generation, pageIndex) ||
        _renderPaused ||
        _image != null ||
        _slugPicture != null ||
        generation <= _progressiveFinalizedThrough ||
        seq <= _progressiveAppliedSeq) {
      image.dispose();
      return;
    }
    _progressiveAppliedSeq = seq;
    uiClock.stop();
    final budget = PdfPageView.progressivePartialUiBudget;
    final budgetSpent = budget != null && uiClock.elapsed >= budget;
    if (budgetSpent && generation == _progressiveBudgetGeneration) {
      _progressiveBudgetSpent = true;
      // A pending partial is necessarily larger than this one and cannot fit
      // the same frame budget. Release its cumulative command buffer now.
      if (_progressivePending?.generation == generation) {
        _progressivePending = null;
      }
    }
    setState(() {
      _preview?.dispose();
      _preview = image;
      _previewCacheGeneration = null;
    });
    PdfPerfLog.log('progressive-partial page=$pageIndex seq=$seq '
        'commands=${commands.length} ui='
        '${(uiClock.elapsedMicroseconds / 1000).toStringAsFixed(1)}ms '
        'budgetStop=$budgetSpent${PdfPerfLog.rssSuffix()}');
  }

  void _queueProgressivePartial(
    int generation,
    int pageIndex,
    List<PdfRenderCommand> commands,
    int seq,
  ) {
    if (generation <= _progressiveFinalizedThrough ||
        _superseded(generation, pageIndex)) {
      return;
    }
    if (generation > _progressiveBudgetGeneration) {
      _progressiveBudgetGeneration = generation;
      _progressiveBudgetSpent = false;
    }
    if (_progressiveBudgetSpent) return;
    _progressivePending = (
      generation: generation,
      pageIndex: pageIndex,
      commands: commands,
      seq: seq,
    );
    if (_progressiveDrainActive) return;
    _progressiveDrainActive = true;
    unawaited(_drainProgressivePartials());
  }

  Future<void> _drainProgressivePartials() async {
    try {
      while (mounted) {
        final pending = _progressivePending;
        _progressivePending = null;
        if (pending == null) return;
        await _paintProgressivePartial(
          pending.generation,
          pending.pageIndex,
          pending.commands,
          pending.seq,
        );
      }
    } finally {
      _progressiveDrainActive = false;
      // There is no await between observing a null mailbox and this finally on
      // Dart's single isolate, but retain this guard for callbacks delivered by
      // a custom worker during error unwinding.
      if (mounted && _progressivePending != null) {
        _progressiveDrainActive = true;
        unawaited(_drainProgressivePartials());
      }
    }
  }

  void _finalizeProgressivePartials(int generation) {
    if (generation > _progressiveFinalizedThrough) {
      _progressiveFinalizedThrough = generation;
    }
    if ((_progressivePending?.generation ?? generation + 1) <= generation) {
      _progressivePending = null;
    }
  }

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
    final priority = visibleDetailRequested
        ? widget.renderPriority - 100
        : widget.renderPriority;
    // On a dense sheet the full record below is a multi-second wait on blank
    // paper. Progressive streaming (#564) reveals the growing linework prefix as
    // the record walks the page - a sequence of prefixes that supersedes the
    // single bounded early prefix, so skip that when it is on. Otherwise put one
    // bounded prefix on screen first. Both no-op on ordinary pages.
    final progressive = PdfPageView.progressiveStreamingPaint &&
        widget.page.rawContentLength >= PdfPageView.earlyPrefixMinContentBytes;
    if (!progressive) {
      await _paintEarlyPrefix(generation, pageIndex, worker, priority);
      if (_superseded(generation, pageIndex) || _renderPaused) return null;
    }
    final commands = await worker.record(
      pageIndex,
      annotations: widget.showAnnotations,
      priority: priority,
      decodeImages: false,
      onPartial: !progressive
          ? null
          : (partial) {
              final seq = ++_progressiveSeqCounter;
              _queueProgressivePartial(generation, pageIndex, partial, seq);
            },
    );
    if (_superseded(generation, pageIndex) ||
        _renderPaused ||
        commands == null) {
      return null;
    }
    // Every partial is a subset of this final buffer. Clear the mailbox before
    // requesting the final UI turn so it cannot wait behind or race another
    // obsolete prefix from its own page.
    _finalizeProgressivePartials(generation);
    if (!await _paceWorkerUiWork() ||
        _superseded(generation, pageIndex) ||
        _renderPaused) {
      return null;
    }

    final retainScene = _retainScene(commands);
    final hasImageDraws = PdfPageRenderer.hasImageDraws(commands);
    if (!hasImageDraws) {
      PdfPerfLog.log(
        'vector-first complete page=$pageIndex commands=${commands.length} '
        'retained=$retainScene',
      );
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
        final picture = scene.replay(pixelRatio: 1);
        _setScene(
          scene,
          fromWorker: true,
          pictureBytes: picture.approximateBytesUsed,
          picture: picture,
        );
        _picture = Future.value(picture);
      } else {
        _picture = PdfPageRenderer.pictureFromCommandsWithPlan(
          widget.page,
          commands,
          _renderPlan,
        );
      }
      return null;
    }

    if (PdfPageView.prioritizeBoundedFinalPicture &&
        commands.length <= PdfPageView.directPicturePresentationMaxCommands) {
      PdfPerfLog.log(
        'vector-first skip-presentation page=$pageIndex '
        'commands=${commands.length} reason=bounded-final-first',
      );
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
    final image = await PdfRasterProbe.measure(
      'vector-first-full',
      page: pageIndex,
      ratio: vectorRatio,
      rasterize: () => PdfPageRenderer.rasterize(
        picture,
        PdfPageRenderer.pageSize(widget.page, rotation: widget.rotation),
        vectorRatio,
      ),
    );
    picture.dispose();
    // Adopt the vector raster only if the full pass hasn't already landed (a
    // landed full raster has a non-null _rasteredRatio). Deliberately leave
    // _rasteredRatio null so the full pass below is not skipped by its
    // resolution-unchanged guard - it must re-raster to bring the images in.
    if (_superseded(generation, pageIndex) ||
        _renderPaused ||
        _rasteredRatio != null) {
      image.dispose();
      return null;
    }
    setState(() {
      _image?.dispose();
      _image = image;
      // Deliberately NOT recorded in _imageState: these pixels carry no PDF
      // images, so the full pass below must re-raster and _baseRasterIsCurrent
      // must never call them current. Same reasoning as _rasteredRatio above.
      _imageState = null;
      _preview?.dispose();
      _preview = null;
    });
    _scheduleBudgetRebalance();
    PdfPerfLog.log('vector-first page=$pageIndex${PdfPerfLog.rssSuffix()}');
    // This path rasterized a full-page vector preview instead of arming a
    // region detail, so there is nothing for the caller to wait on.
    return null;
  }

  /// Starts the dense-page full worker record early and uses its streamed
  /// image-free prefixes for progressive paint. The returned future is passed
  /// straight to [_interpretPicture], so the final decoded commands are never
  /// requested a second time.
  _PendingWorkerRecord? _startFusedProgressiveRecord(
      int generation, int pageIndex) {
    final worker = widget.renderWorker;
    if (worker == null || !worker.isActive) return null;
    final imageRatio = _imageRatioTarget();
    _pictureImageRatio = imageRatio;
    final waitClock = PdfPerfLog.enabled ? (Stopwatch()..start()) : null;
    final commands = worker.record(
      pageIndex,
      annotations: widget.showAnnotations,
      priority: widget.renderPriority,
      imagePixelRatio: imageRatio,
      onPartial: (partial) {
        final seq = ++_progressiveSeqCounter;
        _queueProgressivePartial(generation, pageIndex, partial, seq);
      },
    );
    PdfPerfLog.log('progressive-fused page=$pageIndex');
    return _PendingWorkerRecord(commands, imageRatio, waitClock);
  }

  /// Starts the ordinary page's complete record immediately when the caller
  /// has already chosen final-first presentation. Unlike
  /// [_startFusedProgressiveRecord], this sends no image-free partial: a partial
  /// would duplicate the command-buffer transfer and trigger the intermediate
  /// raster that final-first exists to avoid. The final future is handed to
  /// [_interpretPicture], so native isolates and web workers both perform one
  /// content walk and one serialization.
  _PendingWorkerRecord? _startBoundedFinalRecord(int pageIndex) {
    final worker = widget.renderWorker;
    if (worker == null || !worker.isActive) return null;
    final imageRatio = _imageRatioTarget();
    _pictureImageRatio = imageRatio;
    final waitClock = PdfPerfLog.enabled ? (Stopwatch()..start()) : null;
    final commands = worker.record(
      pageIndex,
      annotations: widget.showAnnotations,
      priority: widget.renderPriority,
      imagePixelRatio: imageRatio,
    );
    PdfPerfLog.log('bounded-final-fused page=$pageIndex');
    return _PendingWorkerRecord(commands, imageRatio, waitClock);
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

  /// The last interpret's phase split (worker-reply wait vs picture build),
  /// for the perf log. Null while the log is off - the Stopwatches that
  /// produce them are never allocated then.
  double? _lastInterpretWaitMs;
  double? _lastInterpretBuildMs;

  /// The last interpret's build-phase split (image decode vs picture
  /// construction), for the perf log. Null while the log is off - the
  /// Stopwatch and timing carrier that produce them are never allocated then.
  /// Also null on the local 'recorded' path, where decode and construction
  /// are fused into one walk and no split exists to report.
  double? _lastInterpretDecodeMs;
  double? _lastInterpretReplayMs;

  /// The within-replay substituted-text shaping split (#454): shaping wall time
  /// and run-cache miss/hit counts, filled only when [PdfPerfLog.enabled] on the
  /// retained-scene replay path; null everywhere else, like the decode/replay
  /// pair above.
  double? _lastInterpretTextShapeMs;
  int? _lastInterpretTextShapeMiss;
  int? _lastInterpretTextShapeHit;

  /// The actual interpret + rasterize, run once the first render is no
  /// longer gated (or directly for re-rasters of a cached picture).
  Future<void> _renderNow() async {
    final generation = _renderSession.beginFull();
    final pageIndex = widget.previewIndex;
    final firstInterpret = _picture == null;
    if (firstInterpret) {
      _lastInterpretResultBytes = null;
      _lastInterpretWaitMs = null;
      _lastInterpretBuildMs = null;
      _lastInterpretDecodeMs = null;
      _lastInterpretReplayMs = null;
      _lastInterpretTextShapeMs = null;
      _lastInterpretTextShapeMiss = null;
      _lastInterpretTextShapeHit = null;
    }
    final sw = Stopwatch()..start();
    // The vector-first phase below runs INSIDE [sw]'s span but interprets
    // nothing the `interpret=` figure is about - it rasterizes a full-page
    // vector preview (seconds, on a dense sheet) and can wait a frame for the
    // detail paint. Left unmeasured it is simply missing from the line, which
    // is how the 2026-07-29 trace reported a 1224ms "interpret" whose wait and
    // build summed to 242ms. Measured, it closes the line's accounting.
    var progressiveMs = 0.0;
    if (_renderPaused) {
      _render();
      return;
    }
    // Nothing to render: the live raster already is what this pass would
    // produce. The scheduler re-grants a request that arrived while a render
    // was in flight (render_scheduler.dart's `_inFlight` queue) on the premise
    // that it "may carry a new scale or revision", and when it doesn't, the
    // pass below re-interprets and re-reads the whole page off the GPU to
    // arrive back at the pixels already on screen - 260-500ms and ~8MB per
    // repeat at 2.1MP in the 2026-07-29 trace, several times per session.
    //
    // Still refresh the detail patch: a settle that only moved the viewport
    // routes through here too (one combined callback paces base + detail), and
    // that IS work even when the base raster is untouched.
    if (_baseRasterIsCurrent()) {
      PdfPerfLog.log('render skip page=$pageIndex reason=base-current '
          'ratio=${_effectiveRatio().toStringAsFixed(2)}');
      await _updateDetail();
      return;
    }
    // Progressive first paint: on a page's first interpret, paint its
    // vector/text immediately (images skipped) so a heavy raster underlay -
    // which can take seconds to decode - doesn't leave the page blank
    // meanwhile. The full pass below then re-rasters with the images in.
    final preferLocalFirstPaint = firstInterpret && _preferLocalFirstPaint();
    if (preferLocalFirstPaint) {
      PdfPerfLog.log('cold-local page=$pageIndex '
          'raw=${widget.page.rawContentLength}B');
    }
    final previewFresh =
        widget.previewCache?.isFresh(pageIndex, widget.page) ?? false;
    // A cached preview is enough to avoid another vector-only first paint at
    // fit scale. Once zoomed, however, the lightweight worker recording also
    // bootstraps the visible-region request that can beat a slow full-page
    // image decode. Ask for it even when soft preview pixels already exist.
    final needsRegionBootstrap = widget.onScreen &&
        widget.qualityVisible &&
        widget.scale > 1.05 &&
        _scene == null &&
        (widget.renderWorker?.isActive ?? false);
    final skipEmptyVectorPass = firstInterpret && _isImageOnlyPage();
    if (skipEmptyVectorPass) {
      PdfPerfLog.log('vector-first skip page=$pageIndex reason=image-only');
    }
    _PendingWorkerRecord? pendingWorkerRecord;
    if (firstInterpret &&
        !preferLocalFirstPaint &&
        !skipEmptyVectorPass &&
        (!previewFresh || needsRegionBootstrap)) {
      // The armed detail completer is returned, not parked in a field. Renders
      // are not serialized - PdfPageRenderScheduler invokes render() without
      // awaiting it (render_scheduler.dart, "starts one page render this
      // frame") and only de-duplicates *pending* requests, so two _renderNow
      // passes for one page can interleave. With shared state, whichever pass
      // read the field last either inherited a future belonging to an
      // abandoned paint or stole the live pass's own. A local keeps each pass
      // with exactly the completer it armed.
      final useBoundedFinalRecord = PdfPageView.prioritizeBoundedFinalPicture &&
          widget.page.rawContentLength <=
              PdfPageView.boundedFinalSinglePassMaxRawContentBytes &&
          !needsRegionBootstrap;
      final useFusedProgressive = !useBoundedFinalRecord &&
          PdfPageView.fusedProgressiveRecord &&
          PdfPageView.progressiveStreamingPaint &&
          !needsRegionBootstrap;
      final progressiveDetail = useFusedProgressive
          ? null
          : useBoundedFinalRecord
              ? null
              : await _paintVectorFirst(generation, pageIndex);
      if (useBoundedFinalRecord) {
        pendingWorkerRecord = _startBoundedFinalRecord(pageIndex);
      } else if (useFusedProgressive) {
        pendingWorkerRecord =
            _startFusedProgressiveRecord(generation, pageIndex);
      }
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
      progressiveMs = sw.elapsedMicroseconds / 1000.0;
    }
    final cached = _picture;
    final ui.Picture picture;
    if (cached != null) {
      picture = await cached;
    } else {
      final interpreted = await _interpretPicture(
        forceLocal: preferLocalFirstPaint,
        pendingWorkerRecord: pendingWorkerRecord,
      );
      if (interpreted == null) {
        if (!_superseded(generation, pageIndex) &&
            !_deferredOffscreenRasterRefresh) {
          _render();
        }
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
        _setScene(
          interpretedScene,
          fromWorker: sceneFromWorker,
          pictureBytes: interpretedPicture.approximateBytesUsed,
          picture: interpretedPicture,
        );
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
        progressiveMs: progressiveMs,
        waitMs: _lastInterpretWaitMs,
        buildMs: _lastInterpretBuildMs,
        decodeMs: _lastInterpretDecodeMs,
        replayMs: _lastInterpretReplayMs,
        textShapeMs: _lastInterpretTextShapeMs,
        textShapeMiss: _lastInterpretTextShapeMiss,
        textShapeHit: _lastInterpretTextShapeHit,
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
    if (_renderedAtDisplayImageRatio() &&
        _slugPictureScene(retainedScene) &&
        !_slugPictureRejected) {
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
              _imageState = null;
              _preview?.dispose();
              _preview = null;
              _rasteredRatio = effective;
            });
            _dropDetail();
            final cache = widget.previewCache;
            await _updateDetail();
            if (_abandoned(pageIndex) || !identical(_scene, retainedScene)) {
              return;
            }
            widget.onRasterReady?.call();
            if (cache != null && _renderedAtFullImageRatio()) {
              _schedulePreviewFeed(cache, picture, generation, pageIndex);
            }
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
    final canPresentPictureDirectly = PdfPageView.directPicturePresentation &&
        widget.onScreen &&
        _renderedAtDisplayImageRatio() &&
        retainedScene != null &&
        !_sceneIsTileOnly(retainedScene) &&
        retainedScene.commands.length <=
            PdfPageView.directPicturePresentationMaxCommands;
    if (canPresentPictureDirectly) {
      setState(() {
        _directPicture = picture;
        _directPictureIntent = _renderIntent(widget);
        _image?.dispose();
        _image = null;
        _imageState = null;
        _preview?.dispose();
        _preview = null;
        _rasteredRatio = effective;
      });
      final detailReady = await _updateDetail();
      if (!detailReady ||
          _superseded(generation, pageIndex) ||
          !identical(_directPicture, picture)) {
        return;
      }
      // Readiness means pixels have reached a frame, not merely that setState
      // queued the display list. This keeps the competitive visual-settle
      // clock honest and lets editing afterimages clear on the right frame.
      await SchedulerBinding.instance.endOfFrame;
      if (!_superseded(generation, pageIndex) &&
          identical(_directPicture, picture)) {
        widget.onRasterReady?.call();
      }
      return;
    }
    if (_directPicture != null) {
      setState(() {
        _directPicture = null;
        _directPictureIntent = null;
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
        _rasteredRatio! < effective * 0.99;
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
      // The probe starts at each rasterize, not above the branch: the strip
      // path awaits a worker bin first, and attributing that queue wait to
      // the raster itself would corrupt the number this log exists to read.
      // Selecting the closure here and measuring it below keeps that property
      // while leaving one log call for all three branches.
      final Future<ui.Image> Function() rasterize;
      final stripScene = scene != null && _stripReplayScene(scene);
      // A freshly completed page already has [picture], the exact painter-
      // order display list that produced its retained scene. Flatten that for
      // the first base image instead of walking the dense transcript again to
      // build a strip plan. Strip replay remains the zoom/detail path once a
      // base image exists; that is where re-rastering at a new scale benefits
      // from the sparse device. This is shared by web and supported Impeller
      // platforms (iOS/software were already on the picture branch).
      if (stripScene && _image != null) {
        final stripPlan = await _workerStripPlan(scene, pixelRatio: effective);
        if (_superseded(generation, pageIndex)) return;
        rasterize = () => scene.rasterizeStrips(
              pixelRatio: effective,
              stripPlan: stripPlan,
            );
      } else if (scene != null && !stripScene && !_sceneIsTileOnly(scene)) {
        rasterize = () => scene.rasterize(pixelRatio: effective);
      } else {
        // No scene, or one retained only to feed tiles: a flat replay of a
        // dense transcript would be a UI-thread hitch, so the cached picture
        // stays the full-page base raster.
        rasterize = () => PdfPageRenderer.rasterize(
              picture,
              _renderPlan.pageSize(widget.page),
              effective,
            );
      }
      final image = await PdfRasterProbe.measure(
        'base-full',
        page: pageIndex,
        ratio: effective,
        rasterize: rasterize,
      );
      if (_superseded(generation, pageIndex) || _renderPaused) {
        image.dispose();
        if (!_superseded(generation, pageIndex)) _render();
        return;
      }
      final cache = widget.previewCache;
      // the previous raster stays up (transform-scaled) until this
      // replaces it, so zooming never flashes white
      setState(() {
        _image?.dispose();
        _image = image;
        _rasteredRatio = effective;
        _imageState = (
          ratio: effective,
          imageRatio: _pictureImageRatio,
          intent: _renderIntent(widget),
        );
        _preview?.dispose();
        _preview = null;
      });
      _scheduleBudgetRebalance();
      if (_renderedAtFullImageRatio()) {
        cache?.putFullImage(
          widget.previewIndex,
          widget.page,
          image,
          pageColor: widget.pageColor,
          annotations: widget.showAnnotations,
          rotation: widget.rotation,
          revision: _contentRevision(),
        );
      }
    }
    final detailReady = await _updateDetail();
    if (stale && detailReady) widget.onRasterReady?.call();
    if (stale && detailReady) _scheduleFocusedImageRefinement();
    if (stale && detailReady && _renderedAtFullImageRatio()) {
      final cache = widget.previewCache;
      if (cache != null) {
        _schedulePreviewFeed(cache, picture, generation, pageIndex);
      }
    }
  }

  /// Feeds the fast-scroll preview only after the completed full raster has
  /// had a frame to reach the compositor. The downscale is another CanvasKit
  /// readback on web; starting it before [onRasterReady] made a useful cache
  /// side effect sit directly in front of the page the user requested. On web
  /// it is omitted entirely: the viewer's idle prerender and active-scroll
  /// vector prefetch populate the low-resolution tier without issuing a
  /// second back-to-back CanvasKit readback after every requested page. The
  /// exact full-raster cache already covers immediate revisits.
  void _schedulePreviewFeed(PdfPagePreviewCache cache, ui.Picture picture,
      int generation, int pageIndex) {
    if (kIsWeb) return;
    unawaited(() async {
      await SchedulerBinding.instance.endOfFrame;
      if (_superseded(generation, pageIndex) ||
          !identical(cache, widget.previewCache) ||
          cache.isFresh(
            widget.previewIndex,
            widget.page,
            requireImages: true,
          )) {
        return;
      }
      await cache.putFromPicture(
        widget.previewIndex,
        widget.page,
        picture,
        rotation: widget.rotation,
      );
    }());
  }

  /// Renders (or drops) the deep-zoom patch: the visible slice of the
  /// page, inflated by half a viewport on each side, at the resolution
  /// the zoom actually asks for.
  Future<bool> _updateDetail({
    _DetailGeometry? detailGeometry,
    VoidCallback? onPaint,
  }) async {
    if (_renderPaused) return false;
    // The viewer's global transform reaches cache-window neighbours too. They
    // keep a bounded fit-resolution base, but a detail raster is useful only
    // where the page actually intersects the viewport. Building one here made
    // every off-screen neighbour pay the live zoom's GPU readback and memory
    // cost despite none of those pixels being visible.
    if (!widget.onScreen) {
      _dropDetail();
      return true;
    }

    // A retained/direct picture keeps vector and text commands live under the
    // viewer transform. When its decoded images already have at least one
    // source sample per physical display pixel, that picture is the complete
    // sharp zoom result; a region raster would only add a delayed compositor
    // change. This is the common <=2x zoom path after a 2x-headroom base
    // record. Beyond that ratio the detail/tile path resumes normally.
    if ((_directPicture != null || _slugPicture != null) &&
        _pictureImagesAreSharpAtZoom()) {
      _dropDetail();
      return true;
    }

    // The tile pyramid supplies deep-zoom detail instead of the single patch:
    // refresh the visible slice and let the tile layer schedule/composite. When
    // the view is too dense to tile within the pyramid budget,
    // _refreshTileGeometry returns false and we fall through to the single-patch
    // path below, which covers an arbitrarily large region in one raster
    // without thrashing the shared pyramid (issues #314/#360).
    // _refreshTileGeometry also bootstraps a dense scene's worker-built region
    // index. Do not guard this call on _useTilePath: that gate cannot become
    // true until the very warm-up this call starts has completed.
    final tightDetail = _tightDetailGeneration == widget.settleGeneration;
    if (PdfPageView.tileStoreDetail && !tightDetail) {
      if (_refreshTileGeometry()) return true;
      // A worker-built grid takes a few hundred milliseconds on the dense CAD
      // pages that need it. Keep the already-visible capped base raster during
      // that one warm-up instead of launching a competing full-viewport detail
      // record which will be obsolete before it can rasterize.
      if (_tilePathStatus == 'index-warming') {
        PdfPerfLog.log(
          'detail waits for region-index page=${widget.previewIndex}',
        );
        return true;
      }
    } else if (tightDetail && _tileFraction != null) {
      // A scale-changing frame needs one exact visible patch as quickly as
      // possible. Tile alignment can nearly double each dimension and then
      // slice the oversized raster back into the viewport; retain the existing
      // tiles as cache entries, but take their stale layer out of this frame.
      setState(() {
        _tileFraction = null;
        _tileDesiredRatio = null;
      });
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
    detailGeometry ??= _detailGeometryAt(
      widget.scale,
      inflation: _tightDetailGeneration == widget.settleGeneration
          ? _zoomDetailInflation
          : 0.5,
    );
    if (detailGeometry == null) {
      _dropDetail();
      return true;
    }
    final fraction = detailGeometry.fraction;
    final region = detailGeometry.region;
    final ratio = detailGeometry.pixelRatio;

    // The single-patch fallback deliberately rasterizes half a viewport of
    // headroom on every side. Keep using those pixels while they still cover
    // the live viewport instead of rebuilding an almost-identical 3-6 MP
    // raster after every wheel-scroll settle. This is the fallback for pages
    // that cannot use the reusable tile pyramid, so without this coverage
    // check the guard band was pure extra work.
    //
    // Content identity is checked separately: additive edits intentionally
    // leave the old patch painted until its replacement lands, but that stale
    // patch must never satisfy this fast path. A higher-density request (zoom
    // in, or a smaller cap-bound region) also gets a fresh raster.
    final existingFraction = _detailFraction;
    final existingRatio = _detailPixelRatio;
    if (_detailImage != null &&
        existingFraction != null &&
        existingRatio != null &&
        _detailContentIsCurrent() &&
        existingRatio >= ratio * 0.99 &&
        _detailPatchCovers(
          existingFraction,
          detailGeometry.visibleFraction,
        )) {
      PdfPageView.debugDetailPatchReuses++;
      onPaint?.call();
      PdfPerfLog.log(
        'detail reuse page=${widget.previewIndex} '
        'ratio=${existingRatio.toStringAsFixed(2)}',
      );
      return true;
    }

    // Claim the detail generation only when this pass is actually about to
    // produce a replacement patch. The tile route above is a successful
    // no-op for the single-patch adapter: beginning a generation before that
    // return used to cancel an already-decoded tight zoom patch during the
    // follow-up full-render grant. On the large raster CAD sheets that patch
    // was ready in ~1.5 s, but was discarded immediately before rasterization;
    // the user then waited for an 8-9 s, ~70 MB tile-prefetch decode instead.
    final generation = _renderSession.beginDetail();

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
    // Whether replaying the retained vector-only scene alone yields the
    // FINISHED region rather than a placeholder to be replaced. It does exactly
    // when no image draw reaches the region - the same invariant that lets the
    // tile path rasterize from such a scene ([_tileCanRasterize]).
    //
    // When it holds, the worker pass that normally follows has nothing to add:
    // it re-records the identical commands and re-rasterizes the identical
    // pixels. The 2026-07-29 trace paid that twice on a page whose single image
    // decoded to 0.0 megapixels - `detail-vector … 1715x999 ms=401.9` followed
    // 320ms later by `detail-worker-picture … 1715x999 ms=322.5`, a second 1.7MP
    // allocation and platform-thread readback for byte-identical output.
    final retainedCoversRegion = heldScene != null &&
        (_sceneIsVectorOnly
            ? !_imagesIntersectRegion(heldScene.commands, region)
            : !_sceneHasImageDraws || heldScene.imagesAtNativeResolution);
    final detailClock = Stopwatch()..start();
    PdfPerfLog.log(
      'detail request page=${widget.previewIndex} '
      'strip=$stripDetail vectorOnly=$_sceneIsVectorOnly '
      'retainedCovers=$retainedCoversRegion '
      // scene/tiles: why this page does or does not get reusable tiles instead
      // of a fresh full-viewport raster on every pan step.
      'scene=${heldScene != null} tiles=$_tilePathStatus',
    );
    final workerStripFuture = stripDetail && !retainedCoversRegion
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
    final workerPictureFuture = !stripDetail && !retainedCoversRegion
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
    // complete worker patch replaces this one at the same geometry - unless
    // [retainedCoversRegion], in which case this replay IS the final patch and no
    // worker pass was started to replace it.
    if (retainedCoversRegion) {
      final cachedPicture = await _picture;
      if (!mounted ||
          !_renderSession.acceptsDetail(generation) ||
          _renderPaused) {
        return false;
      }
      final retainedImage = await PdfRasterProbe.measure(
        cachedPicture == null ? 'detail-retained' : 'detail-cached-picture',
        page: widget.previewIndex,
        ratio: ratio,
        region: (width: region.width, height: region.height),
        rasterize: () => cachedPicture == null
            ? heldScene.rasterizeRegion(region, pixelRatio: ratio)
            : PdfPageRenderer.rasterizeRegion(cachedPicture, region, ratio),
      );
      if (!mounted ||
          !_renderSession.acceptsDetail(generation) ||
          _renderPaused) {
        retainedImage.dispose();
        return false;
      }
      setState(() {
        _adoptDetail(retainedImage, fraction, ratio);
      });
      onPaint?.call();
      _logDetailPaintAfterFrame(generation, detailClock, source: 'retained');
      PdfPerfLog.log(
        'detail retained page=${widget.previewIndex} complete '
        'elapsed=${detailClock.elapsedMilliseconds}ms',
      );
      return true;
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
        _adoptDetail(workerStripImage, fraction, ratio);
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
      final image = await PdfRasterProbe.measure(
        'detail-worker-picture',
        page: widget.previewIndex,
        ratio: ratio,
        region: (width: region.width, height: region.height),
        rasterize: () =>
            PdfPageRenderer.rasterizeRegion(workerPicture, region, ratio),
      );
      workerPicture.dispose();
      if (!mounted ||
          !_renderSession.acceptsDetail(generation) ||
          _renderPaused) {
        image.dispose();
        return false;
      }
      setState(() {
        _adoptDetail(image, fraction, ratio);
      });
      onPaint?.call();
      _logDetailPaintAfterFrame(
        generation,
        detailClock,
        source: 'worker-picture',
      );
      return true;
    }

    // A progressive scene contains image placeholders. Reaching here means an
    // image DOES reach this region (the [retainedCoversRegion] path returned
    // above) and the worker request that would have supplied its pixels was
    // cancelled or declined - so nothing was painted. Wait for the ordinary
    // full record instead of painting a vector-only patch as if it were
    // complete.
    if (_sceneIsVectorOnly) return false;

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
    final picture =
        await (_picture ??= PdfPageRenderer.renderPictureRecordedWithPlan(
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
    final String detailKind;
    // Same per-branch probe placement as the base raster: the strip branch
    // awaits a worker bin before rasterizing, and that wait must not read
    // as raster time.
    final Future<ui.Image> Function() rasterize;
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
      rasterize = () => scene.rasterizeRegionStrips(
            region,
            pixelRatio: ratio,
            stripPlan: stripPlan,
          );
      detailKind = 'detail-strip';
    } else if (scene != null) {
      rasterize = () => scene.rasterizeRegion(region, pixelRatio: ratio);
      detailKind = 'detail-region';
    } else {
      // Classic cached-picture path: replays the WHOLE page picture clipped to
      // [region] at [ratio]. On a huge (unretained) transcript this is where a
      // deep-zoom raster gets expensive - the raster instrumentation flags it.
      rasterize = () => PdfPageRenderer.rasterizeRegion(picture, region, ratio);
      detailKind = 'detail-picture';
    }
    final image = await PdfRasterProbe.measure(
      detailKind,
      page: widget.previewIndex,
      ratio: ratio,
      region: (width: region.width, height: region.height),
      rasterize: rasterize,
    );
    if (!mounted ||
        !_renderSession.acceptsDetail(generation) ||
        _renderPaused) {
      image.dispose();
      return false;
    }
    setState(() {
      _adoptDetail(image, fraction, ratio);
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
    Rect fractionAt(double amount) => Rect.fromLTRB(
          ((visible.left - pageRect.left - visible.width * amount) /
                  pageRect.width)
              .clamp(0.0, 1.0),
          ((visible.top - pageRect.top - visible.height * amount) /
                  pageRect.height)
              .clamp(0.0, 1.0),
          ((visible.right - pageRect.left + visible.width * amount) /
                  pageRect.width)
              .clamp(0.0, 1.0),
          ((visible.bottom - pageRect.top + visible.height * amount) /
                  pageRect.height)
              .clamp(0.0, 1.0),
        );
    final visibleFraction = fractionAt(0);
    final fraction = fractionAt(inflation);
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
      math.sqrt(_maxDetailPixels / (region.width * region.height)),
    );
    ratio = math.min(
      ratio,
      _maxDimension / math.max(region.width, region.height),
    );
    return _DetailGeometry(fraction, visibleFraction, region, ratio);
  }

  /// The first sharp zoom patch covers exactly the visible viewport. It lands
  /// before any pan-ahead work and avoids rasterizing 56% extra pixels for the
  /// old 1/8-viewport guard. A later translation-only settle uses the normal
  /// 0.5 guard above, so sustained panning still gains reusable headroom.
  static const _zoomDetailInflation = 0.0;

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
  bool get _useTilePath => _tilePathStatus == 'active';

  /// Diagnostic state for the tile gate. The old boolean trace could only say
  /// `tiles=false`, leaving patch mode, a missing/warming spatial index, and an
  /// unsupported scene indistinguishable in field traces.
  String get _tilePathStatus {
    if (!PdfPageView.tileStoreDetail) return 'off';
    if (!PdfPageView.retainedZoomReplay) return 'replay-off';
    final scene = PdfPageView.retainedZoomReplay ? _scene : null;
    if (scene == null) return 'no-scene';
    // A dense (grid-escalated) page's region index is a ~O(commands) build
    // (~210ms on the CAD probe, issue #384). Never pay it synchronously on the
    // UI isolate: defer the tile path until the warmed index is resident (built
    // on the render worker when eligible - see [_warmRegionIndexIfNeeded]).
    // Until then the base raster / single detail patch covers the view. Pages
    // below the grid ceiling keep the cheap synchronous linear build.
    if (scene.regionIndexBuildIsHeavy && !scene.debugHasRegionReplayIndex) {
      return 'index-warming';
    }
    return scene.supportsRegionRaster ? 'active' : 'unsupported-scene';
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
        !scene.regionIndexBuildIsHeavy ||
        identical(_regionIndexWarmScene, scene)) {
      return;
    }
    final worker = _sceneFromWorker ? widget.renderWorker : null;
    final pageIndex = widget.previewIndex;
    _regionIndexWarmScene = scene;
    final clock = Stopwatch()..start();
    PdfPerfLog.log(
      'region-index warm page=$pageIndex '
      'commands=${scene.commands.length} '
      'requested=${worker != null && worker.isActive ? 'worker' : 'local'}',
    );
    unawaited(_completeRegionIndexWarm(scene, worker, pageIndex, clock));
  }

  Future<void> _completeRegionIndexWarm(
    PdfRetainedScene scene,
    PdfRenderWorker? worker,
    int pageIndex,
    Stopwatch clock,
  ) async {
    try {
      final index = await scene.warmRegionIndex(
        worker,
        pageIndex: pageIndex,
      );
      PdfPerfLog.log(
        'region-index ready page=$pageIndex '
        'supported=${index.supported} units=${index.units.length} '
        'bytes=${index.estimatedBytes} elapsed=${clock.elapsedMilliseconds}ms',
      );
      // Only refresh if this is still the adopted scene and we're mounted; a
      // document swap or scroll-away may have replaced it while the worker ran.
      if (mounted && identical(_scene, scene)) {
        final tiling = _refreshTileGeometry();
        PdfPerfLog.log(
          'region-index route page=$pageIndex '
          'gate=$_tilePathStatus tiling=$tiling',
        );
        // A fallback detail request may have started while the index was
        // warming. Once tiles can cover this view, invalidate that generation
        // so its multi-megapixel worker picture is dropped instead of rastered.
        if (tiling) {
          _renderSession.invalidateDetail();
        } else {
          // Unsupported grouped scenes and views too large for the tile budget
          // still need the legacy detail patch. Re-enter now that the gate has
          // a final verdict; _updateDetail will no longer take the warming wait.
          _render();
        }
      }
    } catch (error) {
      PdfPerfLog.log(
        'region-index failed page=$pageIndex '
        'elapsed=${clock.elapsedMilliseconds}ms error=$error',
      );
    } finally {
      if (identical(_regionIndexWarmScene, scene)) {
        _regionIndexWarmScene = null;
      }
    }
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
      // Never replace a visible sharp rung with a coarser one merely because
      // the settle target dipped (rounding, a tiny zoom-out, or a worker image
      // detail landing). Keep the active resolution until tiling ends; a
      // later independent tile session may start at the then-current target.
      final requested = _desiredRatioAt(widget.scale);
      final candidate = math.max(requested, _tileDesiredRatio ?? 0);
      if (geom != null && _tilesFitBudget(geom.fraction, candidate)) {
        fraction = geom.fraction;
        desired = candidate;
        tiling = true;
      }
    }
    if (fraction != _tileFraction || desired != _tileDesiredRatio) {
      setState(() {
        _tileFraction = fraction;
        _tileDesiredRatio = desired;
      });
    }
    if (tiling) _ensureTileImageDetail();
    return tiling;
  }

  /// Per-tile admission for the tile layer: the scene-bound veto
  /// ([_tileCanRasterize]) plus the image-detail wait described on
  /// [_tileDetailWanted].
  bool _tileRegionRasterizable(Rect region) {
    final base = _tileCanRasterize;
    if (base != null && !base(region)) return false;
    if (!_tileDetailWanted) return true;
    final desired = _tileDesiredRatio;
    return desired != null &&
        _tileDetailCovers(
          region,
          _tileImageRatio(_tileRasterRatio(desired)),
        );
  }

  /// The actual ratio at which the tile pyramid will rasterize [desired].
  ///
  /// Tile keys live on a discrete zoom ladder. Image-detail requirements must
  /// start from that snapped ratio: using the continuous view ratio can leave
  /// a tile rung sharper than the decoded images replayed into it.
  double _tileRasterRatio(double desired) {
    final store = PdfPageView.debugTileStoreOverride ?? PdfTileStore.instance;
    final rung = store.ladder.rungAtOrAbove(desired);
    return store.ladder.ratioFor(rung);
  }

  /// The image-decode ratio retained behind a tile rasterized at [tileRatio].
  ///
  /// Visible full-page rendering keeps [PdfPageView.focusedImageDecodeHeadroom]
  /// because flattening an image into a picture and then into the presented
  /// raster otherwise leaves it visibly softer than adjacent vector content.
  /// Tile detail must preserve the same policy: decoding at merely the tile
  /// ratio made a raster CAD underlay look low resolution even after the
  /// vector/text parts of the tile had sharpened.
  double _tileImageRatio(double tileRatio) =>
      tileRatio * PdfPageView.focusedImageDecodeHeadroom;

  /// Whether [outer] covers [inner], with [slack] page points of tolerance.
  ///
  /// Not `Rect.contains`: that excludes the right/bottom edges, so a rectangle
  /// does not contain itself - which would make an exactly-matching region read
  /// as uncovered and re-request forever.
  static bool _rectCovers(Rect outer, Rect inner, double slack) =>
      inner.left >= outer.left - slack &&
      inner.top >= outer.top - slack &&
      inner.right <= outer.right + slack &&
      inner.bottom <= outer.bottom + slack;

  /// Whether [_tileDetailScene] can serve a tile covering [region] at
  /// [imageRatio]: its images must cover the region and be at least as sharp
  /// as asked.
  bool _tileDetailCovers(Rect region, double imageRatio) {
    final have = _tileDetailRegion;
    final haveRatio = _tileDetailRatio;
    if (have == null || haveRatio == null || !(imageRatio > 0)) return false;
    if (haveRatio < imageRatio * 0.99) return false;
    // Half a device pixel of slack: the region round-trips through page space
    // and back, so an exactly-abutting tile must not read as uncovered.
    return _rectCovers(have, region, 0.5 / imageRatio);
  }

  /// Requests a region-scoped, zoom-resolution image decode for the tile
  /// layer's current slice when the base scene's images are the limiting
  /// factor. No-op when the page draws no images, when the base decode is
  /// already at least as sharp as the zoom asks, or when the current detail
  /// scene already covers the slice.
  void _ensureTileImageDetail() {
    if (!_sceneHasImageDraws || _sceneIsVectorOnly) return;
    final scene = _scene;
    final fraction = _tileFraction;
    final desired = _tileDesiredRatio;
    if (scene == null || fraction == null || desired == null) return;
    // PdfTileLayer snaps the continuous view ratio onto its zoom ladder before
    // it invokes rasterize. Base image quality on that exact rung, then retain
    // the same decode headroom as the visible full-page path.
    final tileRatio = _tileRasterRatio(desired);
    final imageRatio = _tileImageRatio(tileRatio);
    // Vectors tile sharply from the base scene at any ratio; only the decoded
    // image pixels are capped. Nothing to do until the zoom outruns them.
    final baseImageRatio = _pictureImageRatio;
    if (baseImageRatio != null && imageRatio <= baseImageRatio * 1.05) return;
    final size = _renderPlan.pageSize(widget.page);
    final visibleRegion = Rect.fromLTRB(
      fraction.left * size.width,
      fraction.top * size.height,
      fraction.right * size.width,
      fraction.bottom * size.height,
    );
    if (visibleRegion.width <= 0 || visibleRegion.height <= 0) return;
    // A base decode that already landed on the stream's native pixels cannot be
    // improved by re-decoding it for a region, so the round trip would buy
    // nothing. This is the ordinary case on backends whose worker ships JPEGs
    // un-decoded (the platform codec then runs on this isolate, uncapped); the
    // web worker, which decodes in-worker and ships display-capped pixels, is
    // the one that needs the re-decode.
    if (scene.imagesAtNativeResolution) return;
    // Pan headroom: the tile slice itself carries none ([_tileInflation] is 0
    // because the pyramid prefetches its own ring), but a decode round trip is
    // far more expensive than a tile raster, so the decode covers a viewport of
    // slack per side and survives the pans in between.
    final inflated = Rect.fromLTRB(
      math.max(0, visibleRegion.left - visibleRegion.width * 0.5),
      math.max(0, visibleRegion.top - visibleRegion.height * 0.5),
      math.min(size.width, visibleRegion.right + visibleRegion.width * 0.5),
      math.min(size.height, visibleRegion.bottom + visibleRegion.height * 0.5),
    );
    final store = PdfPageView.debugTileStoreOverride ?? PdfTileStore.instance;
    // Decode the WHOLE grid cells the tile store may raster, including the
    // ring it schedules after the visible cells land. Decoding only the
    // visible slice can leave a whole tile partially uncovered; that tile then
    // replays from the capped base scene and is cached indefinitely at the
    // sharp rung (most visible when a viewport straddles two pages).
    final region = store.rasterCoverageForView(
      pageSize: size,
      desiredRatio: desired,
      visiblePageRect: inflated,
      // Always cover the normal ring. A scale-changing paint may temporarily
      // suppress it, but a later store repaint can restore it without another
      // page-geometry refresh.
      prefetchRingOverride: store.prefetchRing,
    );
    if (region == null || region.width <= 0 || region.height <= 0) return;
    if (_tileDetailCovers(region, imageRatio)) return;
    final pending = _tileDetailPending;
    if (pending != null &&
        pending.$2 >= imageRatio * 0.99 &&
        _rectCovers(pending.$1, region, 0.5 / tileRatio)) {
      return;
    }
    if (widget.renderWorker?.isActive != true) return;
    _setTileDetailWanted(true);
    unawaited(_requestTileImageDetail(region, tileRatio, imageRatio));
  }

  /// Flips the tile admission gate, repainting the layer so the new verdict
  /// takes effect (the painter compares its callbacks by identity).
  void _setTileDetailWanted(bool wanted) {
    if (_tileDetailWanted == wanted) return;
    if (!mounted) {
      _tileDetailWanted = wanted;
      return;
    }
    setState(() => _tileDetailWanted = wanted);
  }

  Future<void> _requestTileImageDetail(
      Rect region, double tileRatio, double imageRatio) async {
    final pageIndex = widget.previewIndex;
    final intent = _renderIntent(widget);
    // Claim the slot BEFORE anything that can return: the `finally` clears the
    // tile veto only for the request that owns it, so an early return that
    // never claimed would leave tiles vetoed for good.
    _tileDetailPending = (region, imageRatio);
    try {
      final worker = widget.renderWorker;
      // Region-scoped decoding lives in the command codec, which only the
      // worker record path reaches; a local decode has no region and would
      // expand the whole image at zoom resolution. With no worker the base
      // scene stays and its tiles are admitted again.
      if (worker == null || !worker.isActive) return;
      final commands = await worker.record(
        pageIndex,
        annotations: widget.showAnnotations,
        priority: widget.renderPriority,
        imagePixelRatio: imageRatio,
        imageDecodeRegion: _pdfRegionForRasterRegion(region),
      );
      if (commands == null || !mounted || _abandoned(pageIndex)) return;
      if (!_intentIsCurrent(intent) || _renderPaused) return;
      final scene = await PdfRetainedScene.fromCommands(
        widget.page,
        commands,
        plan: _renderPlan,
        retainDecodedPixels:
            widget.tileRasterBackend.prefersDirectDecodedImageUploads,
        maxImagePixelRatio: imageRatio,
      );
      if (!mounted || _abandoned(pageIndex) || !_intentIsCurrent(intent)) {
        scene.dispose();
        return;
      }
      _adoptTileDetailScene(scene, region, tileRatio, imageRatio);
    } catch (error) {
      PdfPerfLog.log('tile image detail failed page=$pageIndex error=$error');
    } finally {
      if (_tileDetailPending?.$1 == region &&
          _tileDetailPending?.$2 == imageRatio) {
        _tileDetailPending = null;
        // Whether it landed or not, stop holding tiles back: an adopted scene
        // now answers through [_tileDetailCovers], and a declined one must not
        // veto the page's tiles forever.
        _setTileDetailWanted(false);
      }
    }
  }

  /// Installs a sharper image-detail scene and evicts only newly covered tiles
  /// that were not guaranteed sharp under the previous scene.
  ///
  /// Normally the grid-aligned request plus [_tileDetailWanted] prevents such
  /// tiles from landing. The selective eviction closes the remaining race with
  /// a tile already dispatched as the visible region grows, without throwing
  /// away sharp tiles retained for the previous pan position.
  void _adoptTileDetailScene(PdfRetainedScene scene, Rect region,
      double tileRatio, double imageRatio) {
    final previous = _tileDetailScene;
    final previousRegion = _tileDetailRegion;
    final previousRatio = _tileDetailRatio;
    final store = PdfPageView.debugTileStoreOverride ?? PdfTileStore.instance;
    store.invalidatePageTilesWhere(widget.previewIndex, (tile) {
      final retainedTileRatio = store.ladder.ratioFor(tile.rung);
      final slack = 0.5 / retainedTileRatio;
      final requiredImageRatio = _tileImageRatio(retainedTileRatio);
      if (requiredImageRatio > imageRatio * 1.01 ||
          !_rectCovers(region, tile.region, slack)) {
        return false;
      }
      return previousRegion == null ||
          previousRatio == null ||
          previousRatio < requiredImageRatio * 0.99 ||
          !_rectCovers(previousRegion, tile.region, slack);
    });
    if (previous != null) {
      _disposeTileRasterSession(previous);
      previous.dispose();
    }
    setState(() {
      _tileDetailScene = scene;
      _tileDetailRegion = region;
      _tileDetailRatio = imageRatio;
    });
    PdfPageView.debugTileImageDetailAdoptions++;
    PdfPageView.debugTileImageDetailRatio = imageRatio;
    PdfPageView.debugTileImageDetailRegion = region;
    PdfPerfLog.log(
      'tile image detail page=${widget.previewIndex} '
      'tileRatio=${tileRatio.toStringAsFixed(2)} '
      'imageRatio=${imageRatio.toStringAsFixed(2)} '
      'region=${region.width.toStringAsFixed(0)}x'
      '${region.height.toStringAsFixed(0)}pt',
    );
  }

  /// Frees the tile image-detail scene. Called wherever the page's content or
  /// retained scene is replaced - the decode is bound to both.
  void _dropTileImageDetail() {
    _tileDetailPending = null;
    _tileDetailWanted = false;
    if (_tileDetailScene == null) return;
    _disposeTileRasterSession(_tileDetailScene!);
    _tileDetailScene?.dispose();
    _tileDetailScene = null;
    _tileDetailRegion = null;
    _tileDetailRatio = null;
  }

  /// Whether the shared tile store can hold [fraction]'s tiles at the current
  /// zoom without evicting them out from under the view that just asked for
  /// them - see [PdfTileStore.viewFitsBudget].
  bool _tilesFitBudget(Rect fraction, double desired) {
    final store = PdfPageView.debugTileStoreOverride ?? PdfTileStore.instance;
    final size = _renderPlan.pageSize(widget.page);
    if (size.width <= 0 || size.height <= 0) return false;
    final status = store.viewBudgetStatus(
      pageSize: size,
      desiredRatio: desired,
      visiblePageRect: Rect.fromLTRB(
        fraction.left * size.width,
        fraction.top * size.height,
        fraction.right * size.width,
        fraction.bottom * size.height,
      ),
    );
    if (status == null) {
      PdfPerfLog.log(
        'tile fallback page=${widget.previewIndex} reason=invalid-geometry '
        'desired=${desired.toStringAsFixed(2)}',
      );
      return false;
    }
    final sharedLimit = math.max(1, status.limit ~/ widget.qualityPageCount);
    final fits = status.visibleTiles <= sharedLimit;
    if (!fits) {
      PdfPerfLog.log(
        'tile fallback page=${widget.previewIndex} reason=budget '
        'rung=${status.rung} visible=${status.visibleTiles} '
        'limit=${status.limit} perPageLimit=$sharedLimit '
        'foregroundPages=${widget.qualityPageCount} '
        'capacity=${status.capacity} '
        'desired=${desired.toStringAsFixed(2)}',
      );
    }
    return fits;
  }

  /// The [PdfTileStore] deep-zoom composite for this page, or null when the
  /// tile path is inactive or the page is not zoomed past the base raster.
  ///
  /// [size] is the page-point size (the tile grid space). Placed above the base
  /// raster and any completed visible-region patch, so uncovered gaps keep the
  /// sharpest already-available pixels while exact tiles land over them.
  Widget? _tileLayerWidget(Size size) {
    if (!_useTilePath) return null;
    final scene = _scene;
    final fraction = _tileFraction;
    final desired = _tileDesiredRatio;
    if (scene == null || fraction == null || desired == null) return null;
    final store = PdfPageView.debugTileStoreOverride ?? PdfTileStore.instance;
    final session = _tileRasterSessionFor(scene);
    final scheduling = session is PdfTileRasterScheduling
        ? session as PdfTileRasterScheduling
        : null;
    final sessionCap = scheduling?.maxNewTilesPerPaint;
    final sceneCap = scene.regionIndexBuildIsHeavy ? 1 : null;
    final maxNewTiles = sessionCap == null
        ? sceneCap
        : sceneCap == null
            ? sessionCap
            : math.min(sessionCap, sceneCap);
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
        // Images come from the region-scoped detail scene wherever it reaches
        // (that is the only thing the base scene cannot supply at this zoom);
        // everything else replays identically from either.
        rasterize: (region, ratio) => _rasterizeTile(
          _tileDetailCovers(region, ratio) ? _tileDetailScene ?? scene : scene,
          region,
          ratio,
        ),
        persistence: _tilePersistence,
        canRasterize: _tileRegionRasterizable,
        batchRasters: scheduling?.batchAdjacentTiles,
        // A grid-indexed CAD scene can select tens of thousands of commands
        // across one viewport slab. replayRegion records those commands
        // synchronously before toImage yields, so batching every missing tile
        // made the whole slab one UI-frame stall (271ms in the field trace).
        // Admit one tile per paint instead. A tile completion repaints the
        // layer and advances the center-out fill; ordinary scenes retain the
        // lower-overhead batched path.
        maxNewTilesPerPaint: maxNewTiles,
        // A scale-changing frame sharpens the visible tiles first. Once a pan
        // advances the settle generation, the store's configured ring resumes
        // and supplies the usual pan-ahead headroom.
        prefetchRingOverride: widget.qualityPageCount > 1 ||
                _tightDetailGeneration == widget.settleGeneration
            ? 0
            : null,
        // A retained picture keeps vector/text edges transform-sharp. An
        // upscaled coarser raster tile would cover that better base with a
        // visibly blurry square while the exact tile is pending. Coarse tiles
        // are also excluded when pages share the viewport: their combined
        // fallback sets can consume the headroom reserved above and restart
        // the same cross-page LRU churn the collective admission prevents.
        // Exact tiles still land; misses simply show the stable base through.
        allowCoarserFallback: widget.qualityPageCount == 1 &&
            _slugPicture == null &&
            _directPicture == null,
        // An old pyramid rung is useful pan-ahead outside the current patch,
        // but must not cover that sharper patch with stretched pixels. Exact
        // tiles are not clipped and replace it normally as they land.
        fallbackOcclusionFraction:
            _detailImage != null && _detailContentIsCurrent()
                ? _detailFraction
                : null,
      ),
    );
  }

  PdfTilePersistence? get _tilePersistence {
    final disk = widget.previewCache?.disk;
    return disk != null && disk.storesTiles ? disk : null;
  }

  Future<ui.Image> _rasterizeTile(
    PdfRetainedScene scene,
    Rect region,
    double pixelRatio,
  ) =>
      _tileRasterSessionFor(scene).rasterizeRegion(
        region,
        pixelRatio: pixelRatio,
        tracePage: widget.previewIndex,
      );

  PdfTileRasterSession _tileRasterSessionFor(PdfRetainedScene scene) =>
      _tileRasterSessions.putIfAbsent(scene, () {
        final backend = widget.tileRasterBackend;
        String label() => _tileBackendLabel(backend);
        PdfTileRasterSession? preferred;
        try {
          preferred = backend.createSession(scene);
        } catch (error) {
          PdfPerfLog.log(
            'tile backend init fallback page=${widget.previewIndex} '
            'backend=${label()} error=$error',
          );
        }
        final fallback =
            const PdfCanvasTileRasterBackend().createSession(scene);
        if (preferred == null) {
          scene.releaseDecodedImagePixels();
          PdfPerfLog.log(
            'tile backend session page=${widget.previewIndex} '
            'requested=${label()} route=canvas '
            'reason=${backend.lastSessionRejection ?? 'backend declined'} '
            'commands=${scene.commands.length}',
          );
          return fallback;
        }
        PdfPerfLog.log(
          'tile backend session page=${widget.previewIndex} '
          'requested=${label()} route=${preferred == fallback ? 'canvas' : label()} '
          'commands=${scene.commands.length}',
        );
        // Skip the adapter only for the stock implementation itself. A
        // subclass may override createSession and must receive the same
        // failure and output-validation guarantees as every other backend.
        if (backend.runtimeType == PdfCanvasTileRasterBackend) {
          fallback.dispose();
          return preferred;
        }
        return _FallbackTileRasterSession(
          primary: preferred,
          fallback: fallback,
          onFallback: (error) => PdfPerfLog.log(
            'tile backend raster fallback page=${widget.previewIndex} '
            'backend=${label()} error=$error',
          ),
        );
      });

  void _disposeTileRasterSession(PdfRetainedScene scene) {
    final session = _tileRasterSessions.remove(scene);
    if (session != null) _disposeTileRasterSessionSafely(session);
  }

  void _disposeTileRasterSessions() {
    final sessions = _tileRasterSessions.values.toList();
    _tileRasterSessions.clear();
    for (final session in sessions) {
      _disposeTileRasterSessionSafely(session);
    }
  }

  void _disposeTileRasterSessionSafely(PdfTileRasterSession session) {
    try {
      session.dispose();
    } catch (error) {
      PdfPerfLog.log(
        'tile backend dispose ignored page=${widget.previewIndex} '
        'session=${session.runtimeType} error=$error',
      );
    }
  }

  static String _tileBackendLabel(PdfTileRasterBackend backend) {
    try {
      return backend.debugLabel;
    } catch (_) {
      return backend.runtimeType.toString();
    }
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
      // A retained scene whose image samples are already complete for this
      // region takes the direct replay path in _updateDetail. Do not enqueue a
      // combined worker record + strip plan that the settle cannot consume.
      final retainedCoversRegion = _sceneIsVectorOnly
          ? !_imagesIntersectRegion(scene.commands, detail.region)
          : !_sceneHasImageDraws || scene.imagesAtNativeResolution;
      if (retainedCoversRegion) return;
      _speculateStripDetail(scene, detail);
      return;
    }

    final eff = _effectiveRatioAt(anticipated);
    // Mirror _renderNow's staleness gate: when the settle won't re-raster
    // the full page (resolution unchanged within 1%), don't bin for it.
    if (_image != null &&
        _rasteredRatio != null &&
        _rasteredRatio! >= eff * 0.99) {
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
      maxImagePixelRatio: ratio,
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
      maxImagePixelRatio: ratio,
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
        if (width.isFinite && width > 0) {
          _noteLayoutWidth(width);
          // A prepared exact raster can be adopted in this very frame. This
          // also covers a far page whose placeholder State was laid out in the
          // sliver cache before it became focus: its width does not change on
          // arrival, so `_noteLayoutWidth` alone has no reason to run work.
          // Reading the LRU is synchronous; mutate this State before its
          // children are composed and defer only the parent-ready callback.
          if (_image == null && widget.onScreen) {
            _restoreFullRaster(duringBuild: true);
          }
        }
        return AspectRatio(
          aspectRatio: hasArea ? size.width / size.height : 1,
          child: LayoutBuilder(
            builder: (context, inner) {
              final w = inner.maxWidth;
              final h = inner.maxHeight;
              final detail = _detailImage;
              final fraction = _detailFraction;
              final slugPicture = _slugPicture;
              final directPicture = _directPicture;
              final tileLayer = _tileLayerWidget(size);
              final worker = widget.renderWorker;
              (int, int)? webDimensions;
              _DetailGeometry? webDetailGeometry;
              if (_usesWebWorkerSurface) {
                final desiredRatio = widget.onScreen && widget.qualityVisible
                    ? _desiredRatioAt(widget.scale)
                    : _effectiveRatio();
                // Keep a reusable full-page source through 2x. Beyond that,
                // repaint only the visible slice below: resizing a complete
                // A3 scan to 3x commits ~9MP through the DOM compositor even
                // though the viewport exposes only ~1MP.
                final baseRatio = pdfWebSurfaceBasePixelRatio(desiredRatio);
                final desired = _rasterDimensions(baseRatio);
                // Match the normal raster path's visible-span zoom policy: the
                // live transform already scales every mounted page, so only
                // pages intersecting the viewport need a sharper backing store
                // at this settle. Cache-window neighbours stay deferred.
                // A higher-resolution backing is also valid after zooming
                // back out, so keep it rather than clearing/repainting the
                // canvas on every alternating zoom leg.
                _webSurfaceDimensions = pdfRetainedWebSurfaceDimensions(
                  _webSurfaceDimensions,
                  desired,
                  focused: widget.onScreen && widget.qualityVisible,
                );
                webDimensions = _webSurfaceDimensions;
                if (widget.onScreen &&
                    widget.qualityVisible &&
                    desiredRatio > baseRatio * 1.05) {
                  webDetailGeometry = _detailGeometryAt(
                    widget.scale,
                    force: true,
                    inflation: _zoomDetailInflation,
                  );
                }
              }
              final webSurface = worker != null && webDimensions != null
                  ? pdfWebPageSurface(
                      key: ValueKey<Object>(worker),
                      worker: worker,
                      pageIndex: widget.previewIndex,
                      annotations: widget.showAnnotations,
                      width: webDimensions.$1,
                      height: webDimensions.$2,
                      pageColor: widget.pageColor.toARGB32(),
                      rotation: widget.rotation,
                      priority: widget.renderPriority,
                      onReady: _webSurfacePresented,
                      onDeclined: _webSurfaceRejected,
                    )
                  : null;
              final webDetail = worker != null && webDetailGeometry != null
                  ? Positioned(
                      left: webDetailGeometry.fraction.left * w,
                      top: webDetailGeometry.fraction.top * h,
                      width: webDetailGeometry.fraction.width * w,
                      height: webDetailGeometry.fraction.height * h,
                      child: pdfWebPageSurface(
                        key: ValueKey<Object>((worker, 'detail')),
                        worker: worker,
                        pageIndex: widget.previewIndex,
                        annotations: widget.showAnnotations,
                        width: (webDetailGeometry.region.width *
                                webDetailGeometry.pixelRatio)
                            .ceil()
                            .clamp(1, 1 << 14),
                        height: (webDetailGeometry.region.height *
                                webDetailGeometry.pixelRatio)
                            .ceil()
                            .clamp(1, 1 << 14),
                        pageColor: widget.pageColor.toARGB32(),
                        region: PdfPageSurfaceRegion(
                          left: webDetailGeometry.region.left,
                          top: webDetailGeometry.region.top,
                          right: webDetailGeometry.region.right,
                          bottom: webDetailGeometry.region.bottom,
                          pixelRatio: webDetailGeometry.pixelRatio,
                        ),
                        rotation: widget.rotation,
                        priority: widget.renderPriority,
                        onReady: () {},
                        onDeclined: () {},
                      ),
                    )
                  : null;
              // Publish this page's patch bounds for the thumbnail debug
              // overlay (report coalesces its notify past this build).
              if (pdfDebugPaintDetailBounds.value) {
                PdfDebugDetailRegions.instance.report(
                  widget.previewIndex,
                  detail != null ? fraction : null,
                );
              }
              return Stack(
                alignment: Alignment.topLeft,
                fit: StackFit.expand,
                children: [
                  if (slugPicture != null)
                    CustomPaint(
                      key: const ValueKey('pdf-page-slug-picture'),
                      painter: _RetainedPagePicturePainter(slugPicture, size),
                    )
                  else if (directPicture != null)
                    CustomPaint(
                      key: const ValueKey('pdf-page-direct-picture'),
                      painter: _RetainedPagePicturePainter(directPicture, size),
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
                  if (webSurface != null) webSurface,
                  if (webDetail != null) webDetail,
                  // Keep the fast, viewport-sized refinement underneath the
                  // pyramid. The tile layer is sparse while its region image
                  // decode is pending; making these alternatives hid the
                  // completed refinement and exposed the soft base raster as
                  // a conspicuous strip until the much larger tile scene
                  // arrived. Exact tiles paint afterward and therefore can
                  // only improve—not downgrade—the pixels below.
                  if (detail != null && fraction != null && w.isFinite)
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
                  if (tileLayer != null) tileLayer,
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// Permanently retires an accelerated session after its first failure and
/// serves that request (and every later one) through Canvas. The failed
/// session stays owned until dispose: another slab may already be in flight,
/// and the backend contract allows it to finish before resources are freed.
class _FallbackTileRasterSession
    implements PdfTileRasterSession, PdfTileRasterScheduling {
  _FallbackTileRasterSession({
    required PdfTileRasterSession primary,
    required this.fallback,
    required this.onFallback,
  })  : _primary = primary,
        assert(identical(primary.scene, fallback.scene));

  final PdfTileRasterSession _primary;
  final PdfTileRasterSession fallback;
  final void Function(Object error) onFallback;
  bool _primaryEnabled = true;
  bool _primaryDisposed = false;

  @override
  PdfRetainedScene get scene => fallback.scene;

  @override
  bool get batchAdjacentTiles {
    final active = _primaryEnabled ? _primary : fallback;
    return active is PdfTileRasterScheduling
        ? (active as PdfTileRasterScheduling).batchAdjacentTiles
        : true;
  }

  @override
  int? get maxNewTilesPerPaint {
    final active = _primaryEnabled ? _primary : fallback;
    return active is PdfTileRasterScheduling
        ? (active as PdfTileRasterScheduling).maxNewTilesPerPaint
        : null;
  }

  @override
  Future<ui.Image> rasterizeRegion(
    Rect region, {
    required double pixelRatio,
    int? tracePage,
  }) async {
    if (_primaryEnabled) {
      ui.Image? image;
      try {
        image = await _primary.rasterizeRegion(
          region,
          pixelRatio: pixelRatio,
          tracePage: tracePage,
        );
        final expectedWidth =
            (region.width * pixelRatio).ceil().clamp(1, 1 << 14);
        final expectedHeight =
            (region.height * pixelRatio).ceil().clamp(1, 1 << 14);
        if (image.width != expectedWidth || image.height != expectedHeight) {
          final actual = '${image.width}x${image.height}';
          image.dispose();
          image = null;
          throw StateError(
            'tile backend returned $actual, expected '
            '${expectedWidth}x$expectedHeight',
          );
        }
        return image;
      } catch (error) {
        // A backend may throw after producing an image (for example from a
        // validation getter); never leak that rejected slab.
        image?.dispose();
        if (_primaryEnabled) {
          _primaryEnabled = false;
          _disposePrimary();
          onFallback(error);
        }
      }
    }
    return fallback.rasterizeRegion(
      region,
      pixelRatio: pixelRatio,
      tracePage: tracePage,
    );
  }

  @override
  void dispose() {
    _disposePrimary();
    fallback.dispose();
  }

  void _disposePrimary() {
    if (_primaryDisposed) return;
    _primaryDisposed = true;
    _primary.dispose();
  }
}

/// Paints a retained page picture into the page widget's fitted dimensions.
/// The picture remains in PDF-point coordinates; the surrounding viewer's
/// transform therefore reaches its Slug runtime shader instead of scaling a
/// previously-rasterized image.
class _RetainedPagePicturePainter extends CustomPainter {
  const _RetainedPagePicturePainter(this.picture, this.sourceSize);

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
  bool shouldRepaint(covariant _RetainedPagePicturePainter oldDelegate) =>
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
  const _DetailGeometry(
    this.fraction,
    this.visibleFraction,
    this.region,
    this.pixelRatio,
  );

  final Rect fraction;
  final Rect visibleFraction;
  final Rect region;
  final double pixelRatio;
}

/// Whether a retained detail patch fully covers the current visible slice.
///
/// Fractions come from independent render-tree projections and can differ by
/// a few ulps at a shared edge, hence the tiny tolerance.
bool _detailPatchCovers(Rect patch, Rect visible) {
  const epsilon = 1e-9;
  return patch.left <= visible.left + epsilon &&
      patch.top <= visible.top + epsilon &&
      patch.right + epsilon >= visible.right &&
      patch.bottom + epsilon >= visible.bottom;
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
