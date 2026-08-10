/// Record a page once, replay it at any scale without re-interpreting the
/// content stream or re-decoding its images.
///
/// The classic zoom path caches a [ui.Picture] and re-rasterizes it on every
/// settle ([PdfPageRenderer.rasterize] - a `drawPicture` + `toImage`). A
/// nested `drawPicture` re-raster is measurably slower under Impeller than
/// rasterizing a freshly recorded flat picture of the same draws (~4-6x on
/// image-heavy pages), and the cached picture is a black box that cannot be
/// re-fed through a painting device. [PdfRetainedScene] keeps the page one
/// level higher - as the interpreter's own [PdfRenderCommand] transcript plus
/// the decoded [ui.Image]s it needs - so a zoom rebuilds a flat picture at
/// the new scale from retained data alone. Nothing is parsed and no codec
/// runs after [record] returns.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:pdf_cos/pdf_cos.dart' show CosInteger;
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

import 'banded_transcript.dart';
import 'canvas_device.dart';
import 'image_decoder.dart';
import 'perf_log.dart';
import 'renderer.dart';
import 'render_worker.dart';
import 'region_replay_index.dart';
import 'strips/strip_device.dart';

/// Mutable carrier for the image-decode half of a [PdfRetainedScene.fromCommands]
/// build, so the perf log can split the render 'build' phase into decode vs
/// canvas-call construction without [PdfRetainedScene.fromCommands] growing a
/// second return channel. The caller allocates one only while
/// [PdfPerfLog.enabled] - an ordinary render never pays for it.
class PdfSceneBuildTiming {
  /// Wall time of the `decodeImages` await, in milliseconds. Stays 0 when
  /// the buffer carried no images (or `includeImages` was false).
  double decodeMs = 0;
}

/// A page retained as a replayable scene: the recorded interpreter command
/// buffer plus its decoded images, both produced exactly once in [record].
///
/// [replay] is synchronous - it only re-issues canvas calls - which is the
/// point: the interpret (content-stream parse + walk) and the image decodes,
/// the two costs a zoom must never pay again, happened up front. The scene
/// owns its decoded images; dispose it with [dispose] when the page leaves
/// the cache window (outstanding pictures keep painting - `ui.Image.dispose`
/// on a picture-referenced image is safe, the picture holds its own ref).
class PdfRetainedScene {
  PdfRetainedScene._(this.page, this.plan, this.commands, this._images);

  /// Scenes holding sheddable spatial metadata (a region index or banded
  /// transcript), weakly held so a coordinated memory-pressure sweep can drop
  /// it without keeping any scene alive. Registration is lazy - a scene that
  /// never region-replays never joins - and the list self-prunes past a
  /// growing threshold so dead refs cannot accumulate unbounded.
  static final List<WeakReference<PdfRetainedScene>> _liveScenes = [];
  static int _livePruneThreshold = 64;
  bool _registered = false;

  void _register() {
    if (_registered) return;
    _registered = true;
    _liveScenes.add(WeakReference(this));
    if (_liveScenes.length > _livePruneThreshold) {
      _liveScenes
          .removeWhere((ref) => ref.target == null || ref.target!._disposed);
      _livePruneThreshold = math.max(64, _liveScenes.length * 2);
    }
  }

  /// Sheds the spatial retention metadata (region index + any X-strip banded
  /// transcript) of every live scene under platform memory pressure - the
  /// viewer's `didHaveMemoryPressure` drives this alongside the cache registry.
  /// The authoritative [commands] transcript is untouched; a dropped index
  /// rebuilds identically on the next region replay, and evicted strips
  /// re-materialize on demand. Returns the number of scenes touched.
  static int handleMemoryPressure() {
    var touched = 0;
    for (final ref in _liveScenes.toList()) {
      final scene = ref.target;
      if (scene == null || scene._disposed) continue;
      if (scene._regionIndex != null || scene._bands != null) {
        // Drops the index and the whole banded transcript (all retained
        // strips), the strongest shed short of the authoritative commands.
        scene.dropRegionIndex();
        touched++;
      }
    }
    _liveScenes
        .removeWhere((ref) => ref.target == null || ref.target!._disposed);
    return touched;
  }

  /// The page this scene replays. Must stay open (the scene borrows nothing
  /// from it after [record], but callers naturally keep both together).
  final PdfPage page;

  /// The display inputs the scene was recorded under (paper color,
  /// annotations, rotation). A different plan needs a new recording -
  /// annotations are baked into [commands].
  final PdfPageRenderPlan plan;

  /// The interpreter's transcript of the page, in paint order.
  final List<PdfRenderCommand> commands;

  /// Painter-order fragmentation of [commands] under the strip router.
  /// Computed lazily because ordinary pages below the dense-command ceiling
  /// never need it.
  late final int stripReplayEstimatedBatchCount =
      StripReplayProfile.of(commands).estimatedBatchCount;

  /// Enables the bounded selective path for ordinary retained region replay.
  /// Unsupported command groups conservatively use the full transcript.
  static bool spatialRegionReplay = true;

  /// Hard construction bound for the linear spatial index. Larger transcripts
  /// keep the historical full replay rather than retaining unbounded metadata
  /// — because the linear index is scanned in full on every region raster, so
  /// a huge unit count would cost O(N) per tile.
  static int spatialRegionReplayMaxCommands = 250000;

  /// Escalate to a uniform-grid spatial index for transcripts ABOVE the linear
  /// [spatialRegionReplayMaxCommands] ceiling, up to [spatialGridReplayMaxCommands].
  ///
  /// Below the linear ceiling nothing changes: the flat per-op scan is cheap
  /// enough. Above it, the historical behaviour was to give up on culling and
  /// full-replay the whole transcript into every tile — catastrophic on a dense
  /// CAD page (a 256px tile replaying ~850k commands, ~260ms, on the UI
  /// isolate). The grid makes region replay O(candidates) instead, so those
  /// pages become pannable. On by default because it only ever REPLACES the
  /// full-transcript fallback — it never changes a page that already culled.
  static bool spatialGridReplay = true;
  static int spatialGridReplayMaxCommands = 4000000;

  PdfRegionReplayIndex? _regionIndex;
  PdfBandedTranscript? _bands;

  /// Test/diagnostic counters for the most recent [replayRegion].
  bool debugLastRegionReplayWasSelective = false;
  int debugLastRegionReplayCommandCount = 0;

  /// Per-band unit distribution across [bands] equal-width X strips, the
  /// diagnostic that quantifies how unevenly paint work spreads along the pan
  /// axis (input to sizing an X-strip band decomposition). Empty when the
  /// transcript is outside the spatially-indexable subset.
  List<int> debugUnitBandHistogram(int bands) =>
      _ensureRegionIndex().unitBandHistogram(bands);

  /// Partitions this scene's transcript into [bandCount] X strips for lazy
  /// per-strip retention/eviction (see [PdfBandedTranscript]). Built once and
  /// reused; null when the transcript is not spatially indexable. Callers evict
  /// offscreen strips against the viewport and [reband] to re-materialize.
  PdfBandedTranscript? bandTranscript({required int bandCount}) {
    assert(!_disposed, 'bandTranscript after dispose');
    return _bands ??= PdfBandedTranscript.build(
      commands,
      bandCount: bandCount,
      index: _ensureRegionIndex(),
    );
  }

  /// The banded transcript built by [bandTranscript], if any.
  PdfBandedTranscript? get bands => _bands;

  /// Re-materializes any evicted strips of the banded transcript by
  /// re-interpreting the page once (the ~full-page record the strip dec
  /// omposition trades against) and re-partitioning it. No-op without a banded
  /// transcript or with every strip resident. Returns the strips restored.
  Future<List<int>> reband() async {
    final banded = _bands;
    if (banded == null) return const [];
    if (banded.bands.every((b) => b.resident)) return const [];
    final rebuilt = await record(page, plan: plan);
    try {
      return banded.restore(rebuilt.commands);
    } finally {
      rebuilt.dispose();
    }
  }

  /// Frees the retained spatial index (and any banded transcript); both rebuild
  /// identically on next use. A memory-pressure primitive on the extreme pages
  /// that carry a large index, and a component of strip eviction - the
  /// authoritative [commands] transcript stays intact. A no-op when none is
  /// held; an in-flight [warmRegionIndex] simply repopulates the index.
  void dropRegionIndex() {
    _regionIndex = null;
    _bands = null;
  }

  /// Whether region rasters ([rasterizeRegion]) can be spatially culled to the
  /// requested bounds rather than replaying the whole transcript. False when a
  /// transparency group or soft mask spans the page (splitting one would change
  /// its isolated compositing) - the [PdfTileStore] tile path leaves such pages
  /// on the legacy full-page raster to avoid per-tile full-transcript replays.
  bool get supportsRegionRaster => _ensureRegionIndex().supported;

  /// Approximate bytes of the decoded images this scene retains for replay
  /// (RGBA, width*height*4). Counted against the live-raster budget (#405): a
  /// dense sheet's underlays keep tens of MB of pixels resident per live page.
  int get decodedImageBytes {
    var total = 0;
    for (final image in _images.values) {
      total += image.width * image.height * 4;
    }
    return total;
  }

  /// Whether every image this scene retains is already decoded at its stream's
  /// full native pixel size, so no re-decode - at any zoom, for any region -
  /// could make its image draws sharper.
  ///
  /// The deep-zoom paths use this to skip a region re-record they would gain
  /// nothing from: an image whose display cap landed on native (a scan shown
  /// at roughly its own dpi) is already the best pixels that exist. An image
  /// the scene could not decode at all is ignored - a re-decode won't produce
  /// it either.
  bool get imagesAtNativeResolution =>
      _imagesAtNativeResolution ??= _computeImagesAtNativeResolution();

  /// Memoized: the scene's images never change after construction, and deep
  /// zoom asks this on every settle - an O(commands) walk per settle on a
  /// dense sheet is exactly the kind of per-frame cost the retained scene
  /// exists to avoid.
  bool? _imagesAtNativeResolution;

  bool _computeImagesAtNativeResolution() {
    final requests = <PdfImageRequest>[];
    PdfPageRenderer.collectImageRequests(commands, requests);
    for (final request in requests) {
      final image = _images[pdfImageKey(request)];
      if (image == null) continue;
      final dict = request.stream.dictionary;
      final cos = page.document.cos;
      final width = cos.resolve(dict['Width']);
      final height = cos.resolve(dict['Height']);
      if (width is! CosInteger || height is! CosInteger) continue;
      if (image.width < width.value || image.height < height.value) {
        return false;
      }
    }
    return true;
  }

  int get debugRegionReplayUnitCount => _ensureRegionIndex().units.length;
  int get debugRegionReplayEstimatedBytes =>
      _ensureRegionIndex().estimatedBytes;
  bool get debugRegionReplaySupported => _ensureRegionIndex().supported;
  bool get debugHasRegionReplayIndex => _regionIndex != null;

  /// Whether the transcript contains embedded-outline text that can benefit
  /// from the web Slug picture. Base-14/substituted text has no glyph
  /// outlines and stays on the cheaper normal raster path.
  bool get hasSlugTextCandidates => _hasSlugText(commands);

  static bool _hasSlugText(List<PdfRenderCommand> commands) {
    for (final command in commands) {
      switch (command) {
        case PdfDrawTextCommand(:final run):
          if (!run.invisible &&
              run.glyphs != null &&
              run.fill &&
              run.strokeColor == null &&
              run.gradient == null) {
            return true;
          }
        case PdfEndSoftMaskedCommand(:final maskCommands):
          if (_hasSlugText(maskCommands)) return true;
        default:
          break;
      }
    }
    return false;
  }

  /// Decoded images keyed by [pdfImageKey], owned by this scene.
  final Map<Object, ui.Image> _images;

  /// The already-decoded image for [request], or null when its codec failed or
  /// this is a deliberate vector-only progressive scene.
  ///
  /// Accelerated backends use this to upload each image once at session
  /// creation instead of decoding or uploading it once per tile.
  ui.Image? imageFor(PdfImageRequest request) {
    assert(!_disposed, 'imageFor after dispose');
    return _images[pdfImageKey(request)];
  }

  bool _disposed = false;

  /// Page size in points after the plan's rotation - the raster size at
  /// pixelRatio 1.
  Size get pageSize => plan.pageSize(page);

  /// Interprets [page] once into a retained scene: one recording walk (which
  /// also discovers every image the page draws, including inside soft-mask
  /// groups) followed by one decode pass. This is the only step that touches
  /// the content stream or an image codec.
  ///
  /// Decodes share [PdfImageCache.instance] like every other render path, so
  /// recording a page the viewer already showed is decode-free.
  ///
  /// [maxImagePixelRatio] (screen px per page point) caps each image decode to
  /// display resolution, as in [decodeImages] - the local twin of the render
  /// worker's own cap, so a JPEG the worker declined does not decode at full
  /// native resolution on the UI thread.
  static Future<PdfRetainedScene> record(
    PdfPage page, {
    PdfPageRenderPlan plan = const PdfPageRenderPlan(),
    bool Function(PdfAnnotation)? skipAnnotation,
    double? maxImagePixelRatio,
  }) async {
    final cos = page.document.cos;
    final recorder = RecordingPdfDevice();
    final recording = PdfInterpreter(cos: cos, device: recorder)
      ..drawPageContent(page, page.contentBytes());
    if (plan.annotations) recording.drawAnnotations(page, skip: skipAnnotation);
    final images = await decodeImages(cos, recorder.imageRequests,
        cache: PdfImageCache.instance, maxImagePixelRatio: maxImagePixelRatio);
    return PdfRetainedScene._(page, plan, recorder.commands, images);
  }

  /// Builds a scene from an already-recorded [commands] buffer (e.g. one a
  /// [PdfRenderWorker] shipped back), decoding its images once. The buffer
  /// must have been recorded for [page] under [plan]. Set [includeImages] to
  /// false for a deliberate vector-only progressive buffer; image draws then
  /// stay transparent until a complete scene replaces it.
  ///
  /// [timing], when non-null, receives the duration of the decode pass - the
  /// perf log's way of splitting the render 'build' phase into image decode
  /// vs the canvas-call construction that follows. Null (the default)
  /// measures nothing.
  ///
  /// [maxImagePixelRatio] caps each image decode to display resolution
  /// ([decodeImages]). This is the path that pays for a JPEG the worker shipped
  /// un-decoded (it cannot run the platform codec); the cap keeps that UI-thread
  /// decode at display size instead of the image's full native resolution.
  static Future<PdfRetainedScene> fromCommands(
    PdfPage page,
    List<PdfRenderCommand> commands, {
    PdfPageRenderPlan plan = const PdfPageRenderPlan(),
    bool includeImages = true,
    PdfSceneBuildTiming? timing,
    double? maxImagePixelRatio,
  }) async {
    final images = <Object, ui.Image>{};
    if (includeImages) {
      final requests = <PdfImageRequest>[];
      PdfPageRenderer.collectImageRequests(commands, requests);
      // The clock exists only when a caller asked for the split; an ordinary
      // render never pays for it.
      final clock = timing == null ? null : (Stopwatch()..start());
      images.addAll(await decodeImages(page.document.cos, requests,
          cache: PdfImageCache.instance,
          maxImagePixelRatio: maxImagePixelRatio));
      if (clock != null) {
        timing!.decodeMs = clock.elapsedMicroseconds / 1000.0;
      }
    }
    return PdfRetainedScene._(page, plan, commands, images);
  }

  /// Replays the retained commands into a fresh picture with [pixelRatio]
  /// baked into the canvas transform, so `picture.toImage(width * ratio,
  /// height * ratio)` rasterizes it 1:1. Synchronous: no interpretation, no
  /// decoding - only canvas calls.
  ///
  /// Unlike re-rasterizing a cached picture, the replay re-issues every draw
  /// into a flat picture at the new transform - which Impeller rasterizes
  /// significantly faster than a nested `drawPicture` at a new scale. The
  /// output is pixel-identical to the cached-picture path (asserted
  /// byte-for-byte in retained_scene_test.dart).
  ui.Picture replay({required double pixelRatio}) {
    assert(!_disposed, 'replay after dispose');
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(pixelRatio);
    _replayOnto(canvas);
    return recorder.endRecording();
  }

  /// Region variant of [replay]: only [region] (page points, y-down raster
  /// space - the same space [PdfPageRenderer.rasterizeRegion] takes) lands at
  /// the picture origin, at [pixelRatio]. The deep-zoom detail patch replays
  /// through this without re-interpreting.
  ui.Picture replayRegion(Rect region, {required double pixelRatio}) {
    assert(!_disposed, 'replay after dispose');
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(pixelRatio)
      ..translate(-region.left, -region.top);
    _replayOnto(canvas, rasterRegion: region);
    return recorder.endRecording();
  }

  /// Convenience: [replay] + `toImage` at the exact raster size, clamped to
  /// the engine's texture limit like [PdfPageRenderer.rasterize].
  Future<ui.Image> rasterize({required double pixelRatio}) async {
    final picture = replay(pixelRatio: pixelRatio);
    try {
      final size = pageSize;
      return await picture.toImage(
        (size.width * pixelRatio).ceil().clamp(1, 1 << 14),
        (size.height * pixelRatio).ceil().clamp(1, 1 << 14),
      );
    } finally {
      picture.dispose();
    }
  }

  /// Convenience: [replayRegion] + `toImage`, mirror of
  /// [PdfPageRenderer.rasterizeRegion].
  ///
  /// [tracePage] labels tile-pyramid calls for performance diagnostics. Null
  /// keeps the ordinary path instrumentation-free.
  Future<ui.Image> rasterizeRegion(Rect region,
      {required double pixelRatio, int? tracePage}) async {
    final replayClock =
        tracePage != null && PdfPerfLog.enabled ? (Stopwatch()..start()) : null;
    final picture = replayRegion(region, pixelRatio: pixelRatio);
    final replayMs = replayClock?.elapsedMicroseconds;
    final selectedCommands = debugLastRegionReplayCommandCount;
    final rasterClock =
        tracePage != null && PdfPerfLog.enabled ? (Stopwatch()..start()) : null;
    try {
      final image = await picture.toImage(
        (region.width * pixelRatio).ceil().clamp(1, 1 << 14),
        (region.height * pixelRatio).ceil().clamp(1, 1 << 14),
      );
      if (tracePage != null) {
        final replayElapsedMs = (replayMs ?? 0) / 1000;
        final rasterElapsedMs =
            (rasterClock?.elapsedMicroseconds ?? 0) / 1000;
        PdfPerfLog.log(
          'tile replay page=$tracePage '
          'region=${region.width.toStringAsFixed(0)}x'
          '${region.height.toStringAsFixed(0)}pt '
          'ratio=${pixelRatio.toStringAsFixed(2)} '
          'selected=$selectedCommands/${commands.length} '
          'replay=${replayElapsedMs.toStringAsFixed(1)}ms '
          'raster=${rasterElapsedMs.toStringAsFixed(1)}ms '
          'img=${image.width}x${image.height}${PdfPerfLog.rssSuffix()}',
        );
      }
      return image;
    } finally {
      picture.dispose();
    }
  }

  void _replayOnto(Canvas canvas, {Rect? rasterRegion}) {
    PdfPageRenderer.preparePageCanvas(canvas, page, plan);
    final device = CanvasPdfDevice(canvas, images: _images);
    if (rasterRegion != null && spatialRegionReplay) {
      final index = _ensureRegionIndex();
      final pageRegion = _pageSpaceRegion(rasterRegion);
      if (index.supported && pageRegion != null) {
        debugLastRegionReplayWasSelective = true;
        debugLastRegionReplayCommandCount =
            index.replay(pageRegion, commands, device);
        return;
      }
    }
    debugLastRegionReplayWasSelective = false;
    debugLastRegionReplayCommandCount = commands.length;
    replayCommands(commands, device);
  }

  PdfRegionReplayIndex _ensureRegionIndex() {
    _register();
    if (_regionIndex != null) return _regionIndex!;
    final params = _regionIndexBuildParams;
    return _regionIndex = PdfRegionReplayIndex.build(
      commands,
      maxCommands: params.maxCommands,
      buildGrid: params.buildGrid,
    );
  }

  /// Selects the painter-order units needed for [rasterRegion].
  ///
  /// [rasterRegion] uses the same page-point, y-down space as
  /// [rasterizeRegion]. Each returned unit carries its command index plus the
  /// clip and blend state active at that command. Null means the scene cannot
  /// be split safely (for example, it contains an isolated group or soft
  /// mask), so a backend must decline the scene and let the Canvas fallback
  /// render it whole. An empty list means the supported region is genuinely
  /// blank.
  List<PdfRegionReplayUnit>? selectRegion(Rect rasterRegion) {
    assert(!_disposed, 'selectRegion after dispose');
    final index = _ensureRegionIndex();
    if (!index.supported) return null;
    final pageRegion = _pageSpaceRegion(rasterRegion);
    if (pageRegion == null) return null;
    return index.select(pageRegion);
  }

  /// The `(maxCommands, buildGrid)` the region index builds under for this
  /// transcript, given the current escalation policy. Below the linear ceiling:
  /// the flat per-op scan (unchanged). Above it: escalate to the grid rather
  /// than falling back to full-transcript replay. Shared by the in-isolate
  /// build ([_ensureRegionIndex]) and the worker request ([warmRegionIndex]) so
  /// both bin the transcript identically — the worker re-records a byte-for-byte
  /// identical transcript, so the same parameters produce an index whose unit
  /// indices line up with this scene's [commands].
  ({int maxCommands, bool buildGrid}) get _regionIndexBuildParams {
    final overLinear = commands.length > spatialRegionReplayMaxCommands;
    final useGrid = spatialGridReplay && overLinear;
    return (
      maxCommands: useGrid
          ? spatialGridReplayMaxCommands
          : spatialRegionReplayMaxCommands,
      buildGrid: useGrid,
    );
  }

  Future<PdfRegionReplayIndex>? _regionIndexWarming;

  /// Whether the transcript is heavy enough that building the region index is
  /// worth offloading to a worker — the grid-escalation case, which is the
  /// ~O(commands) build (~210ms on the dense CAD probe) issue #384 targets. A
  /// small page's linear index builds in microseconds; warming it on a worker
  /// would only add a round trip.
  bool get regionIndexBuildIsHeavy => _regionIndexBuildParams.buildGrid;

  /// Builds the region-replay index off the UI isolate on [worker] when it can,
  /// so the first deep-zoom on a dense page does not pay the grid build (pure
  /// command-bounds arithmetic — no `dart:ui`) synchronously on the UI isolate.
  ///
  /// [worker] must be the worker this scene was recorded from (its re-record is
  /// deterministic, so the index it ships lines up with this scene's
  /// [commands]); [pageIndex] is that page's index in the worker's document.
  /// Falls back to an in-isolate build when the worker is null/inactive/declines
  /// or ships a buffer that fails to reconstruct, and to nothing extra when the
  /// index is already resident. Idempotent: concurrent calls share one build.
  Future<PdfRegionReplayIndex> warmRegionIndex(
    PdfRenderWorker? worker, {
    int pageIndex = -1,
    int priority = 0,
  }) {
    // A warmed index (worker-built grid on a dense CAD page) is exactly the
    // heavy retention the pressure sweep must be able to shed, so register even
    // though this path bypasses _ensureRegionIndex.
    _register();
    final resident = _regionIndex;
    if (resident != null) return Future.value(resident);
    final inFlight = _regionIndexWarming;
    if (inFlight != null) return inFlight;
    final future = _warmRegionIndex(worker, pageIndex, priority);
    _regionIndexWarming = future;
    // Clear the memo on completion, but only if it still points to THIS build.
    // The worker-less path completes _warmRegionIndex synchronously (no await),
    // so a `finally` inside it would null the field before the assignment above
    // even ran, leaving a stale completed future memoized - which a later
    // dropRegionIndex would then hand back instead of rebuilding. whenComplete
    // with an identity guard nulls exactly the right one, whenever it finishes.
    future.whenComplete(() {
      if (identical(_regionIndexWarming, future)) _regionIndexWarming = null;
    });
    return future;
  }

  Future<PdfRegionReplayIndex> _warmRegionIndex(
    PdfRenderWorker? worker,
    int pageIndex,
    int priority,
  ) async {
    final params = _regionIndexBuildParams;
    PdfRegionReplayIndex? fromWorker;
    if (worker != null && worker.isActive && pageIndex >= 0) {
      try {
        fromWorker = await worker.buildRegionIndex(
          pageIndex,
          annotations: plan.annotations,
          maxCommands: params.maxCommands,
          buildGrid: params.buildGrid,
          priority: priority,
        );
      } catch (_) {
        // worker failure → local build below
      }
    }
    // A synchronous access (supportsRegionRaster) may have built the index
    // while the worker ran; prefer the resident one to keep a single instance.
    final resident = _regionIndex;
    if (resident != null) return resident;
    final index = fromWorker ??
        PdfRegionReplayIndex.build(
          commands,
          maxCommands: params.maxCommands,
          buildGrid: params.buildGrid,
        );
    // Don't repopulate a disposed scene's field; the caller ignores the
    // result once disposed, but a rebuilt index would leak past dispose.
    if (!_disposed) _regionIndex = index;
    return index;
  }

  PdfRect? _pageSpaceRegion(Rect region) {
    final inverse = PdfPageRenderer.pageToDeviceMatrix(
      page,
      pageSize,
      page.cropBox,
      rotation: plan.rotation,
      pixelRatio: 1,
    ).inverted();
    if (inverse == null) return null;
    final points = <(double, double)>[
      (
        inverse.transformX(region.left, region.top),
        inverse.transformY(region.left, region.top)
      ),
      (
        inverse.transformX(region.right, region.top),
        inverse.transformY(region.right, region.top)
      ),
      (
        inverse.transformX(region.right, region.bottom),
        inverse.transformY(region.right, region.bottom)
      ),
      (
        inverse.transformX(region.left, region.bottom),
        inverse.transformY(region.left, region.bottom)
      ),
    ];
    var left = points.first.$1;
    var right = left;
    var bottom = points.first.$2;
    var top = bottom;
    for (final point in points.skip(1)) {
      left = math.min(left, point.$1);
      right = math.max(right, point.$1);
      bottom = math.min(bottom, point.$2);
      top = math.max(top, point.$2);
    }
    return PdfRect(left, bottom, right, top);
  }

  /// The strip device geometry a full-page strip replay at [pixelRatio]
  /// uses: the page->device-pixel matrix and the viewport in pixels. Public
  /// so [PdfPageView] can send the EXACT same six coefficients to
  /// [PdfRenderWorker.binStrips] that [replayStrips] will construct its
  /// device with - the plan's stale-geometry guard compares them with `==`.
  ({PdfMatrix pageToDevice, int width, int height}) stripGeometry(
      {required double pixelRatio}) {
    final size = pageSize;
    return (
      pageToDevice: PdfPageRenderer.pageToDeviceMatrix(page, size, page.cropBox,
          rotation: plan.rotation, pixelRatio: pixelRatio),
      width: (size.width * pixelRatio).ceil().clamp(1, 1 << 14),
      height: (size.height * pixelRatio).ceil().clamp(1, 1 << 14),
    );
  }

  /// [stripGeometry]'s region variant - mirrors [replayRegionStrips]'s
  /// device construction (the page matrix concatenated with the region
  /// translation, viewport = the region raster).
  ({PdfMatrix pageToDevice, int width, int height}) stripRegionGeometry(
      Rect region,
      {required double pixelRatio}) {
    return (
      pageToDevice: PdfPageRenderer.pageToDeviceMatrix(
              page, pageSize, page.cropBox,
              rotation: plan.rotation, pixelRatio: pixelRatio)
          .concat(PdfMatrix.translation(
              -region.left * pixelRatio, -region.top * pixelRatio)),
      width: (region.width * pixelRatio).ceil().clamp(1, 1 << 14),
      height: (region.height * pixelRatio).ceil().clamp(1, 1 << 14),
    );
  }

  /// Replays the retained commands through a [StripPdfDevice] instead of
  /// [CanvasPdfDevice]: fills/strokes/outline glyphs are re-binned into
  /// sparse strips at [pixelRatio] and drawn as shader-carrying
  /// `drawVertices` batches; everything the strip device can't express
  /// delegates to the canvas in painter's order. Async because the device's
  /// alpha-atlas upload awaits `decodeImageFromPixels` inside `finish()`.
  ///
  /// The resulting picture is only valid at the recorded [pixelRatio]
  /// (strip quads are device-pixel-aligned) - every zoom step is a fresh
  /// re-bin. Still zero re-interpretation and zero image re-decoding: the
  /// walk is a command replay and the image map is the scene's own.
  ///
  /// [stripPlan] skips even the re-bin: a worker-binned [StripPlan] for
  /// this exact geometry (see [stripGeometry] and
  /// [PdfRenderWorker.binStrips]) is consumed batch-by-batch, so the UI
  /// thread only creates engine objects and replays the tape. A stale or
  /// desynced plan transparently falls back to a local re-bin (counted in
  /// [StripPdfDevice.totalPlanMismatches]).
  ///
  /// Batching telemetry accumulates on [StripPdfDevice.totalFlushes] /
  /// `totalStripQuads` / `totalAtlasTexels`; call
  /// [StripPdfDevice.resetStats] around a step to read per-step deltas.
  Future<ui.Picture> replayStrips(
      {required double pixelRatio,
      StripPlan? stripPlan,
      bool slugGlyphs = false,
      void Function(({int quads, int fallbackOutlineRuns}))?
          onSlugStats}) async {
    assert(!_disposed, 'replay after dispose');
    try {
      return await _stripPicture(stripGeometry(pixelRatio: pixelRatio), null,
          pixelRatio, stripPlan, slugGlyphs, onSlugStats);
    } on StripPlanMismatchError {
      // The plan desynced mid-walk (only detectable at finish, before any
      // painting committed): discard and re-bin locally.
      return _stripPicture(stripGeometry(pixelRatio: pixelRatio), null,
          pixelRatio, null, slugGlyphs, onSlugStats);
    }
  }

  /// Region variant of [replayStrips]: only [region] (page points, y-down
  /// raster space, like [replayRegion]) lands at the picture origin, at
  /// [pixelRatio]. The strip viewport is the region raster, so offscreen
  /// geometry is clipped during binning rather than drawn. A [stripPlan]
  /// must have been binned for [stripRegionGeometry] of the same region.
  Future<ui.Picture> replayRegionStrips(Rect region,
      {required double pixelRatio,
      StripPlan? stripPlan,
      bool slugGlyphs = false,
      void Function(({int quads, int fallbackOutlineRuns}))?
          onSlugStats}) async {
    assert(!_disposed, 'replay after dispose');
    final geometry = stripRegionGeometry(region, pixelRatio: pixelRatio);
    try {
      return await _stripPicture(
          geometry, region, pixelRatio, stripPlan, slugGlyphs, onSlugStats);
    } on StripPlanMismatchError {
      return _stripPicture(
          geometry, region, pixelRatio, null, slugGlyphs, onSlugStats);
    }
  }

  /// Shared device construction + replay for the strip paths. [region] null
  /// is the full page. Throws [StripPlanMismatchError] (recording discarded,
  /// nothing painted) when [stripPlan] desyncs.
  Future<ui.Picture> _stripPicture(
      ({PdfMatrix pageToDevice, int width, int height}) geometry,
      Rect? region,
      double pixelRatio,
      StripPlan? stripPlan,
      bool slugGlyphs,
      void Function(({int quads, int fallbackOutlineRuns}))?
          onSlugStats) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(pixelRatio);
    if (region != null) canvas.translate(-region.left, -region.top);
    PdfPageRenderer.preparePageCanvas(canvas, page, plan);
    final device = StripPdfDevice(
      canvas,
      pageToDevice: geometry.pageToDevice,
      deviceWidth: geometry.width,
      deviceHeight: geometry.height,
      pixelRatio: pixelRatio,
      images: _images,
      precomputed: stripPlan,
      enableSlugGlyphs: slugGlyphs,
    );
    final ui.Picture picture;
    try {
      final sw = Stopwatch()..start();
      replayCommands(commands, device);
      StripPdfDevice.totalRouteMicros += sw.elapsedMicroseconds;
      await device.finish(); // must precede endRecording
      onSlugStats?.call((
        quads: device.slugQuadCount,
        fallbackOutlineRuns: device.slugFallbackOutlineRuns,
      ));
      picture = recorder.endRecording();
    } catch (_) {
      recorder.endRecording().dispose();
      device.dispose();
      rethrow;
    }
    device.dispose();
    return picture;
  }

  /// Convenience: [replayStrips] + `toImage`, the strip-router counterpart
  /// of [rasterize].
  Future<ui.Image> rasterizeStrips(
      {required double pixelRatio, StripPlan? stripPlan}) async {
    final picture =
        await replayStrips(pixelRatio: pixelRatio, stripPlan: stripPlan);
    try {
      final size = pageSize;
      return await picture.toImage(
        (size.width * pixelRatio).ceil().clamp(1, 1 << 14),
        (size.height * pixelRatio).ceil().clamp(1, 1 << 14),
      );
    } finally {
      picture.dispose();
    }
  }

  /// Convenience: [replayRegionStrips] + `toImage`, the strip-router
  /// counterpart of [rasterizeRegion].
  Future<ui.Image> rasterizeRegionStrips(Rect region,
      {required double pixelRatio, StripPlan? stripPlan}) async {
    final picture = await replayRegionStrips(region,
        pixelRatio: pixelRatio, stripPlan: stripPlan);
    try {
      return await picture.toImage(
        (region.width * pixelRatio).ceil().clamp(1, 1 << 14),
        (region.height * pixelRatio).ceil().clamp(1, 1 << 14),
      );
    } finally {
      picture.dispose();
    }
  }

  /// Releases the scene's decoded images. Pictures already returned by
  /// [replay] keep painting (they hold their own image refs); further
  /// replays are an error.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _regionIndex = null;
    _bands = null;
    for (final image in _images.values) {
      image.dispose();
    }
  }
}
