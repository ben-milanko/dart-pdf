import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:pdf_cos/pdf_cos.dart' show CosInteger;
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

import 'canvas_device.dart';
import 'image_decoder.dart';
import 'strips/strip_device.dart';

/// Which device family [PdfPageRenderer.renderImageWithPlan] paints with.
enum PdfRenderDeviceMode {
  /// The stock [CanvasPdfDevice] pipeline (default).
  canvas,

  /// Experimental sparse-strip shader device ([StripPdfDevice]): solid
  /// fills/strokes/outline text batch into drawVertices+FragmentShader
  /// draws, everything else falls back to the canvas device. Only the
  /// pixelRatio-aware bitmap path honors this; picture paths stay canvas.
  strips,
}

/// The resolution and physical pixel size a page raster is baked at.
///
/// A page displayed [layoutWidth] logical pixels wide on a display of
/// [devicePixelRatio] needs `layoutWidth / pageWidth * devicePixelRatio`
/// device pixels per PDF point, times the live zoom [scale]. Two caps bound
/// what that can ask for; past them the deep-zoom detail patch takes over for
/// the visible region rather than the base raster growing without limit.
///
/// This lives here - rather than inside the page widget that reads it every
/// render - because the idle full-raster warm ([PdfPagePreviewCache
/// .warmFullRaster]) has to bake a raster at *exactly* the geometry the page
/// widget will later ask the cache for. Two copies of this arithmetic that
/// disagree by one pixel turn every warmed page into a cache miss, so both
/// sides compute it here.
class PdfPageRasterGeometry {
  PdfPageRasterGeometry._();

  /// Pixel ceiling for one whole-page raster (~4.2M px, 16 MiB RGBA).
  ///
  /// This matches [PdfPageRasterCachePolicy]'s default per-entry budget. Once
  /// a view asks for more resolution, the whole-page image remains a bounded
  /// backing layer and [PdfPageView]'s visible-region detail path supplies the
  /// sharp pixels. A larger base would be expensive to raster, rejected by the
  /// default cache, and mostly outside the viewport.
  static const maxPixels = 1 << 22;

  /// Pixel ceiling for one visible-region detail raster (~16.7M px).
  ///
  /// Detail is already cropped to the viewport and its panning guard band, so
  /// this larger transient allowance preserves sharpness without paying for a
  /// whole page at the same density.
  static const maxDetailPixels = 1 << 24;

  /// Per-side pixel ceiling for one page raster.
  static const maxDimension = 8192.0;

  /// The uncapped resolution, in device pixels per PDF point.
  static double desiredRatio({
    required Size pageSize,
    required double layoutWidth,
    required double devicePixelRatio,
    double scale = 1.0,
  }) {
    final width = math.max(1.0, pageSize.width);
    // pages display fit-width, so the raster must match the on-screen width -
    // a 612pt page across a wide window needs far more pixels than its
    // nominal point size
    final fitWidth = (layoutWidth <= 0 ? width : layoutWidth) / width;
    return math.max(fitWidth * devicePixelRatio * scale, 0.05);
  }

  /// [desiredRatio] bounded by [maxPixels] and [maxDimension].
  static double effectiveRatio({
    required Size pageSize,
    required double layoutWidth,
    required double devicePixelRatio,
    double scale = 1.0,
  }) {
    final width = math.max(1.0, pageSize.width);
    final height = math.max(1.0, pageSize.height);
    var ratio = desiredRatio(
      pageSize: pageSize,
      layoutWidth: layoutWidth,
      devicePixelRatio: devicePixelRatio,
      scale: scale,
    );
    ratio = math.min(ratio, math.sqrt(maxPixels / (width * height)));
    ratio = math.min(ratio, maxDimension / math.max(width, height));
    return math.max(ratio, 0.05);
  }

  /// The physical raster size [PdfPageRenderer.rasterize] produces for a page
  /// of [pageSize] at [pixelRatio] - the same rounding and clamp, so a cache
  /// lookup keyed on these dimensions matches the image that lands.
  static (int width, int height) dimensions(Size pageSize, double pixelRatio) =>
      (
        (pageSize.width * pixelRatio).ceil().clamp(1, 1 << 14),
        (pageSize.height * pixelRatio).ceil().clamp(1, 1 << 14),
      );
}

/// Immutable display inputs for rendering a page.
///
/// The same trio travels through the viewer, thumbnails, color sampler,
/// previews, and export paths. Grouping it keeps those paths from growing
/// parallel parameter lists as rendering options expand.
class PdfPageRenderPlan {
  const PdfPageRenderPlan({
    this.pageColor = const Color(0xFFFFFFFF),
    this.annotations = true,
    this.rotation,
    this.paper = true,
  });

  /// The paper color painted behind page contents.
  final Color pageColor;

  /// Whether the paper is painted at all. False leaves the picture
  /// transparent wherever the content does not draw, so it can be composited
  /// over something else - a page fragment floating above the live page.
  /// [pageColor] is then unused.
  final bool paper;

  /// Whether page annotations are included in the render.
  final bool annotations;

  /// Display rotation override. Null uses the page's own /Rotate.
  final int? rotation;

  Size pageSize(PdfPage page) =>
      PdfPageRenderer.pageSize(page, rotation: rotation);

  @override
  bool operator ==(Object other) =>
      other is PdfPageRenderPlan &&
      pageColor == other.pageColor &&
      annotations == other.annotations &&
      rotation == other.rotation &&
      paper == other.paper;

  @override
  int get hashCode =>
      Object.hash(pageColor.toARGB32(), annotations, rotation, paper);
}

/// Rasterizes PDF pages.
///
/// Two passes: first an [ImageCollector] walk finds image XObjects so they
/// can be decoded asynchronously, then the page is painted synchronously
/// onto a recorded canvas.
class PdfPageRenderer {
  PdfPageRenderer._();

  /// Renders [page] into a picture at 1 unit = 1 PDF point, cropped to the
  /// page's crop box and rotated per /Rotate.
  ///
  /// [pageColor] is the paper: the fill painted under the page content.
  /// PDF pages have no background of their own - white is only the
  /// convention - so any opaque color works (a viewer-level setting; the
  /// document is untouched).
  ///
  /// [annotations] false leaves the page's annotations (highlights, ink,
  /// stamps, form fields...) out of the render - the clean underlying
  /// page. Display-only, like [pageColor]; the document is untouched.
  ///
  /// [skipAnnotation] omits the annotations it matches while keeping the
  /// rest - the "lift" model behind a live drag/resize preview, so the
  /// page reads as the artwork minus the one being edited.
  static Future<ui.Picture> renderPicture(PdfPage page,
      {Color pageColor = const Color(0xFFFFFFFF),
      bool annotations = true,
      bool Function(PdfAnnotation)? skipAnnotation,
      int? rotation}) async {
    return renderPictureWithPlan(
      page,
      PdfPageRenderPlan(
        pageColor: pageColor,
        annotations: annotations,
        rotation: rotation,
      ),
      skipAnnotation: skipAnnotation,
    );
  }

  /// Renders [page] using a pre-computed display [plan].
  ///
  /// [maxImagePixelRatio] (screen px per page point) caps each image decode to
  /// display resolution; see [decodeImages]. Callers that know the final raster
  /// scale (e.g. [renderImageWithPlan]) pass it so a giant raster underlay is
  /// not decoded at full native resolution.
  /// [operations] renders those operations in place of the page's own
  /// content stream - the page still supplies resources, boxes and
  /// annotations. Callers pass a filtered list to paint a subset of the page
  /// (see `PdfPageElements.operationsRetaining`); null parses the page.
  static Future<ui.Picture> renderPictureWithPlan(
      PdfPage page, PdfPageRenderPlan plan,
      {bool Function(PdfAnnotation)? skipAnnotation,
      double? maxImagePixelRatio,
      List<ContentOperation>? operations}) async {
    final cos = page.document.cos;

    // Parsing the content stream (and decompressing it) dominates rendering on
    // graphics-rich pages, and the page is interpreted twice here - once to
    // discover images to decode, once to paint. Parse it once and feed both.
    final pageOps =
        operations ?? ContentStreamParser.parse(page.contentBytes());

    // Discover the images to decode with a scan-only interpretation: it walks
    // the same content (so it sees every image - including those drawn by
    // Type3 glyphs and tiling patterns) but skips the path/text/colour/shading
    // build work, so the collect walk is a fraction of the paint walk.
    final collector = ImageCollector();
    final collecting =
        PdfInterpreter(cos: cos, device: collector, scanImagesOnly: true)
          ..drawPageOperations(page, pageOps);
    if (plan.annotations) {
      collecting.drawAnnotations(page, skip: skipAnnotation);
    }
    final images = await decodeImages(cos, collector.streams,
        cache: PdfImageCache.instance, maxImagePixelRatio: maxImagePixelRatio);

    final box = page.cropBox;
    final size = plan.pageSize(page);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    if (plan.paper) _paintBackground(canvas, size, plan.pageColor);
    _applyPageTransform(canvas, page, size, box, rotation: plan.rotation);

    final painting = PdfInterpreter(
        cos: cos, device: CanvasPdfDevice(canvas, images: images))
      ..drawPageOperations(page, pageOps);
    if (plan.annotations) painting.drawAnnotations(page, skip: skipAnnotation);
    final picture = recorder.endRecording();
    // The picture retains its own reference to every drawn image, so the
    // decode handles (clones from the cache, or fresh decodes) can be freed
    // now - the cache keeps the masters for the next render.
    for (final image in images.values) {
      disposePdfDecodedImage(image);
    }
    return picture;
  }

  /// Renders [page] like [renderPicture] but by first recording the page's
  /// interpreter callbacks into a portable [PdfRenderCommand] buffer (a
  /// [RecordingPdfDevice]) and then replaying that buffer onto the canvas via
  /// the unchanged [CanvasPdfDevice].
  ///
  /// The result is pixel-identical to [renderPicture] - the same canvas calls
  /// happen in the same order - but the interpretation (the dominant cost: the
  /// content-stream parse and walk) is now decoupled from the painting. This
  /// is the seam the background-isolate work splits across: the recording half
  /// is pure Dart and `dart:ui`-free, so it can move to a worker isolate, with
  /// only this replay (cheap) and image decoding staying on the UI thread.
  ///
  /// For now both halves run on the calling isolate; this method exists so the
  /// record/replay split can be exercised and proven equivalent before any
  /// isolate machinery is introduced.
  static Future<ui.Picture> renderPictureRecorded(PdfPage page,
      {Color pageColor = const Color(0xFFFFFFFF),
      bool annotations = true,
      bool Function(PdfAnnotation)? skipAnnotation,
      int? rotation}) async {
    return renderPictureRecordedWithPlan(
      page,
      PdfPageRenderPlan(
        pageColor: pageColor,
        annotations: annotations,
        rotation: rotation,
      ),
      skipAnnotation: skipAnnotation,
    );
  }

  /// Renders [page] through the record/replay path using [plan].
  ///
  /// [maxImagePixelRatio] caps each image decode to display resolution, as in
  /// [renderPictureWithPlan].
  static Future<ui.Picture> renderPictureRecordedWithPlan(
      PdfPage page, PdfPageRenderPlan plan,
      {bool Function(PdfAnnotation)? skipAnnotation,
      double? maxImagePixelRatio,
      double imageDecodeHeadroom = 2}) async {
    final cos = page.document.cos;

    // Record the page into a flat command buffer. This single walk also
    // discovers every image (the recording device's drawImage calls), so the
    // separate scan-only collect pass [renderPicture] runs is unnecessary here.
    final recorder = RecordingPdfDevice();
    final recording = PdfInterpreter(cos: cos, device: recorder)
      ..drawPageContent(page, page.contentBytes());
    if (plan.annotations) recording.drawAnnotations(page, skip: skipAnnotation);

    final images = await decodeImages(cos, recorder.imageRequests,
        cache: PdfImageCache.instance,
        maxImagePixelRatio: maxImagePixelRatio,
        imageDecodeHeadroom: imageDecodeHeadroom);

    final box = page.cropBox;
    final size = plan.pageSize(page);
    final uiRecorder = ui.PictureRecorder();
    final canvas = Canvas(uiRecorder);

    _paintBackground(canvas, size, plan.pageColor);
    _applyPageTransform(canvas, page, size, box, rotation: plan.rotation);

    replayCommands(recorder.commands, CanvasPdfDevice(canvas, images: images));
    final picture = uiRecorder.endRecording();
    for (final image in images.values) {
      disposePdfDecodedImage(image);
    }
    return picture;
  }

  /// Builds a page picture from an already-recorded [commands] buffer -
  /// the replay half of an off-thread render. The interpreter walk that
  /// produced [commands] happened elsewhere (a [PdfRenderWorker]'s isolate),
  /// so this is just the cheap canvas replay plus the paper/transform setup,
  /// pixel-identical to [renderPictureRecorded].
  ///
  /// The only UI-thread work besides the replay is decoding any images the
  /// buffer carries (image XObjects serialize as self-contained streams; see
  /// [serializeCommands]). Those decodes are shared through [PdfImageCache] like
  /// every other render path - the reconstructed streams key by content, so a
  /// page redrawn while scrolling reuses its decoded pixels instead of re-
  /// running the codec. An image-free buffer decodes nothing.
  ///
  /// [includeImages] false skips image decoding entirely and replays with an
  /// empty image map, so the device draws the page's vector/text and skips
  /// every image. This is the fast first pass of progressive rendering: a heavy
  /// raster underlay can take many seconds to decode, so the page paints its
  /// linework immediately and the images drop in on a later full pass.
  ///
  /// [maxImagePixelRatio] caps those decodes to the resolution the picture is
  /// about to be rasterized at, exactly as in [pictureFromCommandsWithPlan].
  /// Pass it whenever the buffer may carry un-decoded images (the worker's
  /// codec declined them) and the target is smaller than the page: without it
  /// a 256px thumbnail decodes a declined image at its native size, on the
  /// platform thread (#603).
  static Future<ui.Picture> pictureFromCommands(
      PdfPage page, List<PdfRenderCommand> commands,
      {Color pageColor = const Color(0xFFFFFFFF),
      int? rotation,
      bool includeImages = true,
      double? maxImagePixelRatio}) async {
    return pictureFromCommandsWithPlan(
      page,
      commands,
      PdfPageRenderPlan(pageColor: pageColor, rotation: rotation),
      includeImages: includeImages,
      maxImagePixelRatio: maxImagePixelRatio,
    );
  }

  /// Replays recorded [commands] for [page] using [plan].
  ///
  /// [maxImagePixelRatio] caps any images the buffer carries un-decoded to
  /// display resolution ([decodeImages]) - the JPEGs a render worker shipped
  /// without decoding, which would otherwise decode at native size here.
  static Future<ui.Picture> pictureFromCommandsWithPlan(
      PdfPage page, List<PdfRenderCommand> commands, PdfPageRenderPlan plan,
      {bool includeImages = true, double? maxImagePixelRatio}) async {
    final requests = <PdfImageRequest>[];
    if (includeImages) collectImageRequests(commands, requests);
    final Map<Object, ui.Image> images = requests.isEmpty
        ? const <Object, ui.Image>{}
        : await decodeImages(page.document.cos, requests,
            cache: PdfImageCache.instance,
            maxImagePixelRatio: maxImagePixelRatio,
            imageDecodeHeadroom: 1);

    final box = page.cropBox;
    final size = plan.pageSize(page);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    _paintBackground(canvas, size, plan.pageColor);
    _applyPageTransform(canvas, page, size, box, rotation: plan.rotation);
    replayCommands(commands, CanvasPdfDevice(canvas, images: images));
    final picture = recorder.endRecording();
    for (final image in images.values) {
      disposePdfDecodedImage(image);
    }
    return picture;
  }

  /// Counts the decoded images a worker [commands] buffer carries and their
  /// total pixels (recursing soft-mask groups). The deciding diagnostic for why
  /// a raster-heavy page is slow: one oversized image escaping the resolution
  /// cap looks very different from many tiles each capped but summing large.
  /// Images shipped un-decoded (the platform-codec path) don't count.
  static (int count, int pixels) decodedImageStats(
      List<PdfRenderCommand> commands) {
    final requests = <PdfImageRequest>[];
    collectImageRequests(commands, requests);
    var count = 0;
    var pixels = 0;
    for (final request in requests) {
      final decoded = request.decoded;
      if (decoded != null) {
        count++;
        pixels += decoded.width * decoded.height;
      }
    }
    return (count, pixels);
  }

  /// Whether [commands] draws any image at all (decoded or not, including
  /// inside soft-mask groups) - the cue the progressive vector-first pass uses
  /// to decide whether a slower full (image-decoding) pass needs to follow it.
  static bool hasImageDraws(List<PdfRenderCommand> commands) {
    final requests = <PdfImageRequest>[];
    collectImageRequests(commands, requests);
    return requests.isNotEmpty;
  }

  /// Total pixels the image draws in [commands] will decode and upload -
  /// the honest cost of replaying this buffer, as opposed to merely whether
  /// it contains an image at all ([hasImageDraws]).
  ///
  /// Prefers the pixels the worker already decoded; falls back to the source
  /// image's declared /Width x /Height for a draw that will decode locally.
  /// Returns -1 when any image declines to say how big it is, so a caller
  /// weighing a budget cannot mistake "unknown" for "small".
  static int imageDrawPixels(List<PdfRenderCommand> commands) {
    final requests = <PdfImageRequest>[];
    collectImageRequests(commands, requests);
    var pixels = 0;
    for (final request in requests) {
      final decoded = request.decoded;
      if (decoded != null) {
        pixels += decoded.width * decoded.height;
        continue;
      }
      final width =
          request.decodedWidth ?? _declaredExtent(request, 'Width', 'W');
      final height =
          request.decodedHeight ?? _declaredExtent(request, 'Height', 'H');
      if (width == null || height == null) return -1;
      pixels += width * height;
    }
    return pixels;
  }

  /// An image's declared extent, by its full key or the abbreviation an
  /// inline image (BI ... ID) uses for the same entry.
  static int? _declaredExtent(
      PdfImageRequest request, String key, String abbreviation) {
    final dict = request.stream.dictionary;
    final value = dict[key] ?? dict[abbreviation];
    return value is CosInteger ? value.value : null;
  }

  /// Decodes the image payloads in a retained command buffer into the shared
  /// image cache without replaying or rasterizing the page.
  ///
  /// This is the cheap UI-side half of speculative nearby-page warming: the
  /// worker can parse and decode off-thread, then the platform image handles
  /// are admitted while the current page is already stable. A later visible
  /// render receives cache clones and only pays command replay. Every temporary
  /// handle is released here; [PdfImageCache] retains its bounded masters.
  static Future<void> predecodeCommandImages(
    PdfPage page,
    List<PdfRenderCommand> commands, {
    double? maxImagePixelRatio,
  }) async {
    final requests = <PdfImageRequest>[];
    collectImageRequests(commands, requests);
    if (requests.isEmpty) return;
    final images = await decodeImages(
      page.document.cos,
      requests,
      cache: PdfImageCache.instance,
      maxImagePixelRatio: maxImagePixelRatio,
      imageDecodeHeadroom: 1,
    );
    for (final image in images.values) {
      disposePdfDecodedImage(image);
    }
  }

  /// Gathers every image draw request in [commands], descending into soft-mask
  /// groups and retained tiling cells, in replay order.
  static void collectImageRequests(
      List<PdfRenderCommand> commands, List<PdfImageRequest> out) {
    for (final command in commands) {
      switch (command) {
        case PdfDrawImageCommand(:final request):
          out.add(request);
        case PdfEndSoftMaskedCommand(:final maskCommands):
          collectImageRequests(maskCommands, out);
        case PdfDrawTiledCellCommand(:final cellCommands):
          collectImageRequests(cellCommands, out);
        default:
          break;
      }
    }
  }

  /// Paints the page paper under the content: an opaque white backing when
  /// [pageColor] is translucent (so a tint washes over white rather than the
  /// viewer canvas behind the page), then [pageColor]. A fully opaque colour
  /// makes the white backing a no-op, so it is free in the common case.
  static void _paintBackground(Canvas canvas, Size size, Color pageColor) {
    if (pageColor.a < 1.0) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = const Color(0xFFFFFFFF),
      );
    }
    canvas.drawRect(Offset.zero & size, Paint()..color = pageColor);
  }

  /// Sets the canvas up in PDF user space: /Rotate, then the y-flip and crop
  /// box origin, so interpreter output (page space, y-up) lands correctly.
  static void _applyPageTransform(
      Canvas canvas, PdfPage page, Size size, PdfRect box,
      {int? rotation}) {
    switch (rotation ?? page.rotation) {
      case 90:
        canvas.translate(size.width, 0);
        canvas.rotate(math.pi / 2);
      case 180:
        canvas.translate(size.width, size.height);
        canvas.rotate(math.pi);
      case 270:
        canvas.translate(0, size.height);
        canvas.rotate(-math.pi / 2);
    }
    // PDF user space is y-up with the crop box's own origin
    canvas.translate(0, box.height);
    canvas.scale(1, -1);
    canvas.translate(-box.left, -box.bottom);
  }

  /// Renders one annotation's appearance into a picture in the same page
  /// raster space as [renderPicture] (post-rotation, y down, 1 unit =
  /// 1 point) but with a transparent background - for live drag/resize
  /// previews and the viewer's annotation layer. Null when the annotation has
  /// no appearance stream.
  ///
  /// The picture is scale-independent: callers replay it at any page-to-view
  /// scale, so stroke widths stay in page space (no device-pixel floor - see
  /// [CanvasPdfDevice.pixelRatio]).
  static Future<ui.Picture?> renderAnnotationPicture(
      PdfPage page, PdfAnnotation annotation,
      {int? rotation}) async {
    if (annotation.normalAppearance == null) return null;
    final cos = page.document.cos;

    final collector = ImageCollector();
    PdfInterpreter(cos: cos, device: collector, scanImagesOnly: true)
        .drawAnnotation(page, annotation);
    final images = await decodeImages(cos, collector.streams,
        cache: PdfImageCache.instance);

    final box = page.cropBox;
    final size = pageSize(page, rotation: rotation);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    _applyPageTransform(canvas, page, size, box, rotation: rotation);

    // pixelRatio 0 turns the one-device-pixel stroke floor off (#660). This
    // picture is scale-independent - the appearance layer replays it at
    // whatever page-to-view scale the viewer is at - so flooring here would
    // bake a scale-dependent choice in: every positive width under 1 pt
    // would become a Skia hairline that stays one pixel at 333% zoom. A
    // pressure-sensitive ink stroke is exactly that case (a 1.5 pt pen at
    // zero pressure draws 0.6 pt), and it visibly snapped from its live
    // width to a hairline the moment this picture replaced the overlay.
    // A genuine `0 w` stroke arrives here as 0 and still paints as Skia's
    // hairline, which is what §8.4.3.2 asks for. The raster paths that do
    // know their output scale keep their positive ratio, so #426's
    // CAD-linework floor is untouched.
    PdfInterpreter(
            cos: cos,
            device: CanvasPdfDevice(canvas, images: images, pixelRatio: 0))
        .drawAnnotation(page, annotation);
    final picture = recorder.endRecording();
    for (final image in images.values) {
      disposePdfDecodedImage(image);
    }
    return picture;
  }

  /// Renders [page] to a bitmap. [pixelRatio] of 2 doubles the resolution.
  static Future<ui.Image> renderImage(PdfPage page,
      {double pixelRatio = 1,
      Color pageColor = const Color(0xFFFFFFFF),
      bool annotations = true,
      bool recorded = true,
      int? rotation}) async {
    return renderImageWithPlan(
      page,
      plan: PdfPageRenderPlan(
        pageColor: pageColor,
        annotations: annotations,
        rotation: rotation,
      ),
      pixelRatio: pixelRatio,
      recorded: recorded,
    );
  }

  /// Experimental device selector for [renderImageWithPlan]. Static so the
  /// benchmark/parity harnesses (and a future viewer flag) can flip every
  /// render path at once; strip pictures bake the pixel ratio in, so only
  /// the bitmap path (which knows the ratio) participates.
  static PdfRenderDeviceMode deviceMode = PdfRenderDeviceMode.canvas;

  /// Renders [page] to a bitmap using a pre-computed display [plan].
  static Future<ui.Image> renderImageWithPlan(PdfPage page,
      {required PdfPageRenderPlan plan,
      double pixelRatio = 1,
      bool recorded = true}) async {
    // Strips is its own device axis (opt-in via [deviceMode], only the
    // benchmark/parity harnesses set it) - independent of the recorded/two-walk
    // choice, so it engages whenever selected regardless of [recorded].
    if (deviceMode == PdfRenderDeviceMode.strips) {
      return _renderImageStrips(page, plan, pixelRatio);
    }
    final picture = recorded
        ? await renderPictureRecordedWithPlan(page, plan,
            maxImagePixelRatio: pixelRatio)
        : await renderPictureWithPlan(page, plan,
            maxImagePixelRatio: pixelRatio);
    try {
      return await rasterize(picture, plan.pageSize(page), pixelRatio);
    } finally {
      picture.dispose();
    }
  }

  /// Phase timing (microseconds) for the strips path, aggregated across
  /// renders for the benchmark: interpret+strip-generation (the walk into
  /// [StripPdfDevice]) and the final picture rasterization. Atlas-decode
  /// and tape-replay phases live on [StripPdfDevice].
  static int stripInterpretMicros = 0;
  static int stripRasterMicros = 0;

  /// Strip-device bitmap render: interpret once through [StripPdfDevice]
  /// (recording strips + fallback ops in painter's order), then paint and
  /// rasterize. The picture is recorded with [pixelRatio] baked in so the
  /// strip quads are device-pixel-aligned - matching [rasterize]'s output
  /// geometry for the same ratio.
  static Future<ui.Image> _renderImageStrips(
      PdfPage page, PdfPageRenderPlan plan, double pixelRatio) async {
    final cos = page.document.cos;
    final pageOps = ContentStreamParser.parse(page.contentBytes());

    final collector = ImageCollector();
    final collecting =
        PdfInterpreter(cos: cos, device: collector, scanImagesOnly: true)
          ..drawPageOperations(page, pageOps);
    if (plan.annotations) collecting.drawAnnotations(page);
    // Cap image decodes to display resolution just like the canvas bitmap path
    // ([renderImageWithPlan]), so the two devices stay pixel-parity on scaled
    // images instead of one decoding sharper than the other.
    final images = await decodeImages(cos, collector.streams,
        cache: PdfImageCache.instance, maxImagePixelRatio: pixelRatio);

    final box = page.cropBox;
    final size = plan.pageSize(page);
    final width = (size.width * pixelRatio).ceil().clamp(1, 1 << 14);
    final height = (size.height * pixelRatio).ceil().clamp(1, 1 << 14);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(pixelRatio);
    _paintBackground(canvas, size, plan.pageColor);
    _applyPageTransform(canvas, page, size, box, rotation: plan.rotation);

    final device = StripPdfDevice(
      canvas,
      pageToDevice: pageToDeviceMatrix(page, size, box,
          rotation: plan.rotation, pixelRatio: pixelRatio),
      deviceWidth: width,
      deviceHeight: height,
      pixelRatio: pixelRatio,
      images: images,
    );
    final sw = Stopwatch()..start();
    final painting = PdfInterpreter(cos: cos, device: device)
      ..drawPageOperations(page, pageOps);
    if (plan.annotations) painting.drawAnnotations(page);
    stripInterpretMicros += sw.elapsedMicroseconds;
    await device.finish();

    final picture = recorder.endRecording();
    sw.reset();
    try {
      final image = await picture.toImage(width, height);
      stripRasterMicros += sw.elapsedMicroseconds;
      return image;
    } finally {
      picture.dispose();
      device.dispose();
      for (final image in images.values) {
        disposePdfDecodedImage(image);
      }
    }
  }

  /// The page->device-pixel matrix matching [_applyPageTransform] followed
  /// by a [pixelRatio] canvas scale (geometric application order: crop-box
  /// shift, y-flip, /Rotate, ratio). Public so [PdfRetainedScene] can feed
  /// a [StripPdfDevice] the exact transform its canvas preamble implies.
  static PdfMatrix pageToDeviceMatrix(PdfPage page, Size size, PdfRect box,
      {int? rotation, required double pixelRatio}) {
    var m = PdfMatrix.translation(-box.left, -box.bottom)
        .concat(const PdfMatrix(1, 0, 0, -1, 0, 0))
        .concat(PdfMatrix.translation(0, box.height));
    switch (rotation ?? page.rotation) {
      case 90:
        m = m
            .concat(const PdfMatrix(0, 1, -1, 0, 0, 0))
            .concat(PdfMatrix.translation(size.width, 0));
      case 180:
        m = m
            .concat(const PdfMatrix(-1, 0, 0, -1, 0, 0))
            .concat(PdfMatrix.translation(size.width, size.height));
      case 270:
        m = m
            .concat(const PdfMatrix(0, -1, 1, 0, 0, 0))
            .concat(PdfMatrix.translation(0, size.height));
    }
    return m.concat(PdfMatrix.scaled(pixelRatio, pixelRatio));
  }

  /// Rasterizes an already-recorded page [picture] (sized [size] points) -
  /// re-rasterizing a cached picture at a new zoom skips re-interpreting
  /// the page entirely.
  static Future<ui.Image> rasterize(
      ui.Picture picture, Size size, double pixelRatio) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder)
      ..scale(pixelRatio)
      ..drawPicture(picture);
    final scaled = recorder.endRecording();
    try {
      return await scaled.toImage(
        (size.width * pixelRatio).ceil().clamp(1, 1 << 14),
        (size.height * pixelRatio).ceil().clamp(1, 1 << 14),
      );
    } finally {
      scaled.dispose();
    }
  }

  /// Paints the paper background and sets [canvas] up in PDF user space for
  /// [page] under [plan] - the shared preamble every replay target runs
  /// before feeding interpreter output (or a recorded command buffer) to a
  /// painting device. Public so alternative replay paths ([PdfRetainedScene])
  /// reuse the exact transform stack instead of duplicating it.
  static void preparePageCanvas(
      Canvas canvas, PdfPage page, PdfPageRenderPlan plan) {
    final size = plan.pageSize(page);
    _paintBackground(canvas, size, plan.pageColor);
    _applyPageTransform(canvas, page, size, page.cropBox,
        rotation: plan.rotation);
  }

  /// Rasterizes only [region] (in page points, y-down raster space) of a
  /// recorded page [picture] at [pixelRatio] - the deep-zoom detail patch.
  static Future<ui.Image> rasterizeRegion(
      ui.Picture picture, Rect region, double pixelRatio) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder)
      ..scale(pixelRatio)
      ..translate(-region.left, -region.top)
      ..drawPicture(picture);
    final scaled = recorder.endRecording();
    try {
      return await scaled.toImage(
        (region.width * pixelRatio).ceil().clamp(1, 1 << 14),
        (region.height * pixelRatio).ceil().clamp(1, 1 << 14),
      );
    } finally {
      scaled.dispose();
    }
  }

  /// Samples the rendered color of [page] at [point] - page raster space,
  /// i.e. post-rotation points with y down (view coordinates divided by
  /// the view scale). One-shot; for repeated samples (an eyedropper's
  /// live preview) build a [PdfPageColorSampler] once instead.
  static Future<ui.Color?> sampleColor(PdfPage page, ui.Offset point,
          {Color pageColor = const Color(0xFFFFFFFF),
          bool annotations = true,
          int? rotation}) async =>
      (await PdfPageColorSampler.of(page,
              plan: PdfPageRenderPlan(
                  pageColor: pageColor,
                  annotations: annotations,
                  rotation: rotation)))
          .colorAt(point);

  /// Page size in points after applying rotation.
  ///
  /// [rotation] overrides the page's own /Rotate when set - the view
  /// rotation feature uses this to display a page at a different
  /// orientation without modifying the document.
  static Size pageSize(PdfPage page, {int? rotation}) {
    final box = page.cropBox;
    final r = rotation ?? page.rotation;
    final swap = r == 90 || r == 270;
    return swap ? Size(box.height, box.width) : Size(box.width, box.height);
  }
}

/// Pixel access to a page rendered once, for repeated color sampling -
/// the eyedropper's live preview follows the pointer, and re-rendering
/// per event would be far too slow.
///
/// Points are page raster space: post-rotation points with y down, the
/// view position divided by the view scale.
class PdfPageColorSampler {
  PdfPageColorSampler._(this._pixels, this._width, this._height);

  final ByteData _pixels;
  final int _width;
  final int _height;

  /// Renders and rasterizes [page] at 1 px per point. [pageColor] and
  /// [annotations] must match how the page is displayed, so samples
  /// read the color the user actually sees.
  static Future<PdfPageColorSampler> of(PdfPage page,
      {Color pageColor = const Color(0xFFFFFFFF),
      bool annotations = true,
      int? rotation,
      PdfPageRenderPlan? plan}) async {
    final renderPlan = plan ??
        PdfPageRenderPlan(
          pageColor: pageColor,
          annotations: annotations,
          rotation: rotation,
        );
    final picture =
        await PdfPageRenderer.renderPictureRecordedWithPlan(page, renderPlan);
    try {
      final image = await PdfPageRenderer.rasterize(
          picture, renderPlan.pageSize(page), 1);
      try {
        final data = await image.toByteData();
        if (data == null) {
          throw StateError('page raster yielded no pixels');
        }
        return PdfPageColorSampler._(data, image.width, image.height);
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  }

  /// The color at [point], averaged over a 3×3-point patch so
  /// anti-aliased strokes still read as their color. Null off the page.
  ui.Color? colorAt(ui.Offset point) {
    final cx = point.dx.round(), cy = point.dy.round();
    var r = 0, g = 0, b = 0, n = 0;
    for (var y = cy - 1; y <= cy + 1; y++) {
      for (var x = cx - 1; x <= cx + 1; x++) {
        if (x < 0 || y < 0 || x >= _width || y >= _height) continue;
        final i = (y * _width + x) * 4;
        if (_pixels.getUint8(i + 3) == 0) continue; // past the page edge
        r += _pixels.getUint8(i);
        g += _pixels.getUint8(i + 1);
        b += _pixels.getUint8(i + 2);
        n++;
      }
    }
    return n == 0 ? null : ui.Color.fromARGB(255, r ~/ n, g ~/ n, b ~/ n);
  }
}
